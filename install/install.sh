#!/bin/bash
#
# Installation script for USRP Audio Streamer integration with Allmon3
# This script installs the WebSocket audio streamer for AllStarLink/Allmon3
#

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ALLMON3_DIR="/usr/share/allmon3"
APACHE_CONF="/etc/apache2/conf-enabled/allmon3.conf"
INSTALL_DIR="/opt/usrp-ws"
SERVICE_NAME="usrp-ws"
WS_PORT="8080"
USRP_UDP_PORT="34001"

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}USRP Audio Streamer Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Check if required files exist
echo -e "${YELLOW}Checking required files...${NC}"
REQUIRED_FILES=("asl-monitor.js" "usrp_ws.py")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo -e "${RED}Error: Required file '$file' not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    echo -e "  ✓ Found $file"
done

# Check if Allmon3 directory exists
if [ ! -d "$ALLMON3_DIR" ]; then
    echo -e "${RED}Error: Allmon3 directory not found at $ALLMON3_DIR${NC}"
    exit 1
fi
echo -e "  ✓ Allmon3 directory found"

# Check if Apache config exists
if [ ! -f "$APACHE_CONF" ]; then
    echo -e "${RED}Error: Apache config not found at $APACHE_CONF${NC}"
    exit 1
fi
echo -e "  ✓ Apache config found"
echo ""

# Install System Dependencies
echo -e "${YELLOW}Installing system dependencies...${NC}"

# Detect OS/Package Manager
if command -v apt-get &> /dev/null; then
    PKG_MGR="apt-get"
    PKG_UPDATE="apt-get update"
    PKG_INSTALL="apt-get install -y"
    PKGS="python3 python3-pip python3-websockets net-tools tcpdump"
elif command -v yum &> /dev/null; then
    PKG_MGR="yum"
    PKG_UPDATE="yum check-update"
    PKG_INSTALL="yum install -y"
    PKGS="python3 python3-pip python3-websockets net-tools tcpdump"
elif command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
    PKG_UPDATE="dnf check-update"
    PKG_INSTALL="dnf install -y"
    PKGS="python3 python3-pip python3-websockets net-tools tcpdump"
else
    echo -e "${RED}Error: Unsupported package manager. Please install python3, pip, net-tools manually.${NC}"
    exit 1
fi

echo "Detected package manager: $PKG_MGR"
$PKG_UPDATE || true
$PKG_INSTALL $PKGS

# Verify Python libraries (fallback to pip if system package didn't provide websockets)
echo -e "${YELLOW}Verifying Python libraries...${NC}"
if python3 -c "import websockets" &> /dev/null; then
    echo -e "  ✓ python3-websockets found (installed via system package)"
else
    echo -e "  ${YELLOW}⚠ python3-websockets package not found or didn't provide library.${NC}"
    echo -e "  ${YELLOW}Attempting pip install (Note: this may require --break-system-packages on newer systems)${NC}"
    
    if pip3 install websockets; then
        echo -e "  ✓ websockets installed via pip"
    else
        # Try with --break-system-packages for newer Debian/Ubuntu
        echo -e "  ${YELLOW}⚠ Standard pip install failed. Trying with --break-system-packages...${NC}"
        if pip3 install websockets --break-system-packages; then
            echo -e "  ✓ websockets installed via pip (--break-system-packages)"
        else
            echo -e "${RED}Error: Failed to install websockets library.${NC}"
            echo -e "Please manually install it: sudo apt install python3-websockets"
            exit 1
        fi
    fi
fi
echo ""

# Create installation directory
echo -e "${YELLOW}Creating installation directory...${NC}"
mkdir -p "$INSTALL_DIR"
echo -e "  ✓ Created $INSTALL_DIR"
echo ""

# Copy Python WebSocket server
echo -e "${YELLOW}Installing WebSocket server...${NC}"
cp "$SCRIPT_DIR/usrp_ws.py" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/usrp_ws.py"
chown -R www-data:www-data "$INSTALL_DIR"
echo -e "  ✓ Installed usrp_ws.py to $INSTALL_DIR"
echo ""

# Copy JavaScript and CSS to Allmon3
echo -e "${YELLOW}Installing web assets to Allmon3...${NC}"
cp "$SCRIPT_DIR/asl-monitor.js" "$ALLMON3_DIR/js/"
chmod 644 "$ALLMON3_DIR/js/asl-monitor.js"
echo -e "  ✓ Installed asl-monitor.js"

chown -R www-data:www-data "$ALLMON3_DIR"
echo ""

# Modify Allmon3 index.html to add Stream Audio button
echo -e "${YELLOW}Modifying Allmon3 index.html...${NC}"
INDEX_HTML="$ALLMON3_DIR/index.html"

if [ ! -f "$INDEX_HTML" ]; then
    echo -e "  ${RED}✗ index.html not found at $INDEX_HTML${NC}"
else
    # Restore from backup if exists to ensure we start clean
    if [ -f "${INDEX_HTML}.backup.*" ]; then
        # Find latest backup
        LATEST_BACKUP=$(ls -t ${INDEX_HTML}.backup.* 2>/dev/null | head -n1)
        if [ -n "$LATEST_BACKUP" ]; then
            cp "$LATEST_BACKUP" "$INDEX_HTML"
            echo -e "  ✓ Restored clean index.html from backup"
        fi
    else
        # Create backup if none exists
        cp "$INDEX_HTML" "${INDEX_HTML}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "  ✓ Backed up index.html"
    fi
    
    # Add the JavaScript include before </body>
    if ! grep -q "asl-monitor.js" "$INDEX_HTML"; then
        sed -i 's|</body>|<script src="js/asl-monitor.js"></script>\n<script>\nvar audioMonitorActive = false;\nfunction toggleAudioStream() {\n    var btn = document.getElementById("audioStreamBtn");\n    if (!audioMonitorActive) {\n        ASLMonitor.start({ wsPath: "/allmon3/audio-ws" });\n        audioMonitorActive = true;\n        btn.textContent = "Stop Audio";\n        btn.classList.add("active");\n        btn.style.backgroundColor = "#f44336";\n    } else {\n        ASLMonitor.stop();\n        audioMonitorActive = false;\n        btn.textContent = "Stream Audio";\n        btn.classList.remove("active");\n        btn.style.backgroundColor = "#4CAF50";\n    }\n}\n</script>\n</body>|' "$INDEX_HTML"
    fi
    
    # Inject Button: Look for "navbar-midbar" (Title area)
    echo -e "${YELLOW}Injecting Button...${NC}"
    # Inline button with margin
    BUTTON_HTML='<button id="audioStreamBtn" onclick="toggleAudioStream()" style="vertical-align: middle; margin-left: 20px; padding: 4px 10px; background-color: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 14px;">Stream</button>'
    
    if grep -q "id=\"navbar-midbar\"" "$INDEX_HTML"; then
        # Append after the midbar div
        sed -i "s|id=\"navbar-midbar\"[^>]*></div>|& $BUTTON_HTML|" "$INDEX_HTML"
        echo -e "  ✓ Added Stream Audio button next to 'navbar-midbar'"
    elif grep -q "<b>Allmon v3</b>" "$INDEX_HTML"; then
        # Fallback to sidebar (Inline verify)
        sed -i "s|<b>Allmon v3</b>|<b>Allmon v3</b> $BUTTON_HTML|" "$INDEX_HTML"
        echo -e "  ✓ Added Stream Audio button next to 'Allmon v3' (Sidebar)"
    elif grep -q "Allmon v3" "$INDEX_HTML"; then
        sed -i "s|Allmon v3|Allmon v3 $BUTTON_HTML|" "$INDEX_HTML"
        echo -e "  ✓ Added Stream Audio button next to 'Allmon v3'"
    else
        # Fallback: Top of body
        sed -i "s|<body[^>]*>|&\n<div style='margin:10px;'>$BUTTON_HTML</div>|" "$INDEX_HTML"
        echo -e "  ✓ Added Stream Audio button to top of page (text not found)"
    fi
fi
echo ""

# Create systemd service
echo -e "${YELLOW}Creating systemd service...${NC}"
cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=USRP WebSocket Audio Bridge for Allmon3
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/usrp_ws.py
Restart=always
RestartSec=10
Environment="USRP_UDP_PORT=$USRP_UDP_PORT"
Environment="WS_PORT=$WS_PORT"

[Install]
WantedBy=multi-user.target
EOF
echo -e "  ✓ Created systemd service file"
echo ""

# Modify Apache configuration
echo -e "${YELLOW}Updating Apache configuration...${NC}"

# Check if the proxy lines already exist
if grep -q "ProxyPass /allmon3/audio-ws" "$APACHE_CONF"; then
    echo -e "  ${YELLOW}⚠ WebSocket proxy already configured in Apache${NC}"
else
    # Backup the original config
    cp "$APACHE_CONF" "${APACHE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "  ✓ Backed up Apache config"
    
    # Add the proxy configuration before the closing of the file
    # We'll add it after the last ProxyPass line
    sed -i '/ProxyPass \/allmon3\/master\//a\
\
# USRP Audio Streamer WebSocket Proxy\
ProxyPass /allmon3/audio-ws ws://localhost:8080/\
ProxyPassReverse /allmon3/audio-ws ws://localhost:8080/' "$APACHE_CONF"
    
    echo -e "  ✓ Added WebSocket proxy configuration"
fi
echo ""

# Enable Apache proxy modules
echo -e "${YELLOW}Enabling Apache modules...${NC}"
a2enmod proxy proxy_http proxy_wstunnel rewrite > /dev/null 2>&1 || true
echo -e "  ✓ Apache modules enabled"
echo ""

# Reload systemd and start service
echo -e "${YELLOW}Starting WebSocket service...${NC}"
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service

# Check if service started successfully
sleep 2
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    echo -e "  ${GREEN}✓ Service started successfully${NC}"
else
    echo -e "  ${RED}✗ Service failed to start${NC}"
    echo -e "  Check logs with: sudo journalctl -u ${SERVICE_NAME}.service -n 50"
fi
echo ""

# Reload Apache
echo -e "${YELLOW}Reloading Apache...${NC}"
systemctl reload apache2
if systemctl is-active --quiet apache2; then
    echo -e "  ${GREEN}✓ Apache reloaded successfully${NC}"
else
    echo -e "  ${RED}✗ Apache failed to reload${NC}"
    echo -e "  Check logs with: sudo tail -f /var/log/apache2/error.log"
fi
echo ""

# Display status
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Service Status:${NC}"
systemctl status ${SERVICE_NAME}.service --no-pager -l || true
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Verify the service is running:"
echo "   sudo systemctl status ${SERVICE_NAME}.service"
echo ""
echo "2. Check if WebSocket is listening:"
echo "   sudo netstat -tlnp | grep $WS_PORT"
echo ""
echo "3. Test USRP packets are being received:"
echo "   sudo tcpdump -i any -n udp port $USRP_UDP_PORT"
echo ""
echo "4. Refresh your Allmon3 page in the browser."
echo "   You should see a 'Stream Audio' button active on the page."
echo ""
echo -e "${YELLOW}Troubleshooting:${NC}"
echo "  View service logs: sudo journalctl -u ${SERVICE_NAME}.service -f"
echo "  View Apache logs: sudo tail -f /var/log/apache2/error.log"
echo "  Restart service: sudo systemctl restart ${SERVICE_NAME}.service"
echo ""
echo -e "${GREEN}Installation script completed successfully!${NC}"
