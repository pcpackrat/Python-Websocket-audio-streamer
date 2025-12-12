#!/bin/bash
#
# Uninstallation script for USRP Audio Streamer
# This script removes the WebSocket audio streamer from Allmon3
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

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}USRP Audio Streamer Uninstallation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Please run: sudo $0"
    exit 1
fi

# Stop and disable service
echo -e "${YELLOW}Stopping and disabling service...${NC}"
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
    systemctl stop ${SERVICE_NAME}.service
    echo -e "  ✓ Service stopped"
fi

if systemctl is-enabled --quiet ${SERVICE_NAME}.service 2>/dev/null; then
    systemctl disable ${SERVICE_NAME}.service
    echo -e "  ✓ Service disabled"
fi

# Remove systemd service file
if [ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]; then
    rm /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    echo -e "  ✓ Service file removed"
fi
echo ""

# Remove installation directory
echo -e "${YELLOW}Removing installation files...${NC}"
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo -e "  ✓ Removed $INSTALL_DIR"
fi
echo ""

# Remove web assets from Allmon3
echo -e "${YELLOW}Removing web assets from Allmon3...${NC}"
if [ -f "$ALLMON3_DIR/js/asl-monitor.js" ]; then
    rm "$ALLMON3_DIR/js/asl-monitor.js"
    echo -e "  ✓ Removed asl-monitor.js"
fi
echo ""

# Restore original index.html
echo -e "${YELLOW}Restoring Allmon3 index.html...${NC}"
INDEX_HTML="$ALLMON3_DIR/index.html"

if [ -f "$INDEX_HTML" ]; then
    # Find the most recent backup
    LATEST_BACKUP=$(ls -t ${INDEX_HTML}.backup.* 2>/dev/null | head -n1)
    
    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$INDEX_HTML"
        echo -e "  ✓ Restored index.html from backup: $(basename $LATEST_BACKUP)"
    else
        echo -e "  ${YELLOW}⚠ No backup found. You may need to manually remove audio monitor code from index.html${NC}"
        echo -e "    Look for and remove:"
        echo -e "      - <script src=\"js/asl-monitor.js\"></script>"
        echo -e "      - toggleAudioStream() function"
        echo -e "      - Stream Audio button"
    fi
fi
echo ""

# Remove Apache configuration
echo -e "${YELLOW}Removing Apache configuration...${NC}"
if [ -f "$APACHE_CONF" ]; then
    if grep -q "ProxyPass /allmon3/audio-ws" "$APACHE_CONF"; then
        # Backup the config
        cp "$APACHE_CONF" "${APACHE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        echo -e "  ✓ Backed up Apache config"
        
        # Remove the proxy configuration lines
        sed -i '/# USRP Audio Streamer WebSocket Proxy/,/ProxyPassReverse \/allmon3\/audio-ws/d' "$APACHE_CONF"
        
        # Remove any blank lines that might be left
        sed -i '/^$/N;/^\n$/D' "$APACHE_CONF"
        
        echo -e "  ✓ Removed WebSocket proxy configuration"
        
        # Reload Apache
        systemctl reload apache2
        echo -e "  ✓ Apache reloaded"
    else
        echo -e "  ${YELLOW}⚠ No WebSocket proxy configuration found${NC}"
    fi
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Uninstallation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "If you manually added the audio monitor HTML to Allmon3's index.html,"
echo "you will need to remove those sections manually."
echo ""
echo "Files to check:"
echo "  - $ALLMON3_DIR/index.html"
echo ""
echo "Look for and remove:"
echo "  - <link rel=\"stylesheet\" href=\"css/asl-monitor.css\">"
echo "  - <script src=\"js/asl-monitor.js\"></script>"
echo "  - ASLMonitor.start() calls"
echo "  - Any <div class=\"asl-audio-monitor\"> sections"
echo ""
echo -e "${GREEN}Uninstallation completed successfully!${NC}"
