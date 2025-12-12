#!/bin/bash
#
# install_standalone_stream.sh - Installation script for USRP Audio Streamer (Standalone Node)
# - Installs dependencies (Python, websockets, system tools)
# - Sets up usrp_ws.py service
# - Configures Apache WebSocket proxy
# - Installs stream.html (Separate audio page)
#

set -e  # Exit on error

# Color codes
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

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}USRP Audio Streamer (Standalone) Install${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Check files
echo -e "${YELLOW}Checking required files...${NC}"
REQUIRED_FILES=("asl-monitor.js" "usrp_ws.py" "stream.html")
for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$file" ]; then
        echo -e "${RED}Error: Required file '$file' not found in $SCRIPT_DIR${NC}"
        exit 1
    fi
    echo -e "  ✓ Found $file"
done

# Check Allmon3
if [ ! -d "$ALLMON3_DIR" ]; then
    echo -e "${RED}Error: Allmon3 directory not found at $ALLMON3_DIR${NC}"
    exit 1
fi

# Check Apache
if [ ! -f "$APACHE_CONF" ]; then
    echo -e "${RED}Error: Apache config not found at $APACHE_CONF${NC}"
    exit 1
fi

# Install Dependencies
echo -e "${YELLOW}Installing system dependencies...${NC}"
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
    echo -e "${RED}Error: Unsupported package manager.${NC}"
    exit 1
fi

echo "Detected package manager: $PKG_MGR"
$PKG_UPDATE || true
$PKG_INSTALL $PKGS

# Verify Python libraries (fallback to pip)
if python3 -c "import websockets" &> /dev/null; then
    echo -e "  ✓ python3-websockets found"
else
    echo -e "  ${YELLOW}⚠ python3-websockets not found via system package.${NC}"
    echo -e "  ${YELLOW}Attempting pip install...${NC}"
    pip3 install websockets --break-system-packages || pip3 install websockets
fi
echo ""

# Install Service
echo -e "${YELLOW}Installing WebSocket server...${NC}"
mkdir -p "$INSTALL_DIR"
cp "$SCRIPT_DIR/usrp_ws.py" "$INSTALL_DIR/"
chmod 755 "$INSTALL_DIR/usrp_ws.py"
chown -R www-data:www-data "$INSTALL_DIR"
echo -e "  ✓ Installed usrp_ws.py"

# Install stream.html and JS
echo -e "${YELLOW}Installing web page...${NC}"
mkdir -p "$ALLMON3_DIR/js"
cp "$SCRIPT_DIR/asl-monitor.js" "$ALLMON3_DIR/js/"
cp "$SCRIPT_DIR/stream.html" "$ALLMON3_DIR/"
chmod 644 "$ALLMON3_DIR/js/asl-monitor.js"
chmod 644 "$ALLMON3_DIR/stream.html"
chown -R www-data:www-data "$ALLMON3_DIR"
echo -e "  ✓ Installed stream.html and asl-monitor.js"
echo ""

# Configure Systemd
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
echo -e "  ✓ Created systemd service"
echo ""

# Configure Apache
echo -e "${YELLOW}Updating Apache configuration...${NC}"
if grep -q "ProxyPass /allmon3/audio-ws" "$APACHE_CONF"; then
    echo -e "  ${YELLOW}⚠ WebSocket proxy already configured in Apache${NC}"
else
    cp "$APACHE_CONF" "${APACHE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    sed -i '/ProxyPass \/allmon3\/master\//a\
\
# USRP Audio Streamer WebSocket Proxy\
ProxyPass /allmon3/audio-ws ws://localhost:8080/\
ProxyPassReverse /allmon3/audio-ws ws://localhost:8080/' "$APACHE_CONF"
    echo -e "  ✓ Added WebSocket proxy configuration"
fi
echo ""

# Enable Modules
echo -e "${YELLOW}Enabling Apache modules...${NC}"
a2enmod proxy proxy_http proxy_wstunnel rewrite > /dev/null 2>&1 || true
echo -e "  ✓ Apache modules enabled"

# Start Service
echo -e "${YELLOW}Starting services...${NC}"
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}.service
systemctl restart ${SERVICE_NAME}.service
systemctl reload apache2

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Access the Audio Stream:${NC}"
echo -e "  http://<YOUR_NODE_IP>/allmon3/stream.html"
echo ""
