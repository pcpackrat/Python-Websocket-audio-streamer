#!/bin/bash
#
# update_index.sh - Re-apply Stream Audio button to Allmon3 index.html
# Use this if an Allmon3 update overwrites your index.html
#

set -e

# Configuration
ALLMON3_DIR="/usr/share/allmon3"
INDEX_HTML="$ALLMON3_DIR/index.html"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Restoring Audio Streamer UI Button${NC}"
echo -e "${GREEN}========================================${NC}"

if [ ! -f "$INDEX_HTML" ]; then
    echo -e "${RED}Error: index.html not found at $INDEX_HTML${NC}"
    exit 1
fi

# Check if already patched
if grep -q "asl-monitor.js" "$INDEX_HTML"; then
    echo -e "${YELLOW}Audio monitor script already present.${NC}"
    
    # Try to find a backup to restore
    if ls ${INDEX_HTML}.backup.* 1> /dev/null 2>&1; then
        LATEST_BACKUP=$(ls -t ${INDEX_HTML}.backup.* | head -n1)
        echo -e "${YELLOW}Restoring from latest backup: $LATEST_BACKUP${NC}"
        cp "$LATEST_BACKUP" "$INDEX_HTML"
    else
        echo -e "${RED}No backup found. Please restore index.html manually.${NC}"
        exit 1
    fi
fi

# Backup current file
cp "$INDEX_HTML" "${INDEX_HTML}.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "  ✓ Backed up index.html"

# Add the JavaScript include before </body>
echo -e "${YELLOW}Injecting JavaScript...${NC}"
sed -i 's|</body>|<script src="js/asl-monitor.js"></script>\n<script>\nvar audioMonitorActive = false;\nfunction toggleAudioStream() {\n    var btn = document.getElementById("audioStreamBtn");\n    if (!audioMonitorActive) {\n        ASLMonitor.start({ wsPath: "/allmon3/audio-ws" });\n        audioMonitorActive = true;\n        btn.textContent = "Stop Audio";\n        btn.classList.add("active");\n        btn.style.backgroundColor = "#f44336";\n    } else {\n        ASLMonitor.stop();\n        audioMonitorActive = false;\n        btn.textContent = "Stream Audio";\n        btn.classList.remove("active");\n        btn.style.backgroundColor = "#4CAF50";\n    }\n}\n</script>\n</body>|' "$INDEX_HTML"

# Inject Button
echo -e "${YELLOW}Injecting Button...${NC}"
# Inline button with margin (no div wrapper)
# Using margin-left 20px to separate from title
BUTTON_HTML='<button id="audioStreamBtn" onclick="toggleAudioStream()" style="vertical-align: middle; margin-left: 20px; padding: 4px 10px; background-color: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 14px;">Stream Audio</button>'

# Strategy: Find "navbar-midbar" div and append button AFTER it (so it sits next to it in flex layout)
if grep -q "id=\"navbar-midbar\"" "$INDEX_HTML"; then
    # Replace ending </div> of the midbar line with </div> BUTTON
    # We assume the div closes on the same line as it opens (standard allmon3)
    sed -i "s|id=\"navbar-midbar\"[^>]*></div>|& $BUTTON_HTML|" "$INDEX_HTML"
    echo -e "  ✓ Added Stream Audio button next to 'navbar-midbar' (Header)"
elif grep -q "<b>Allmon v3</b>" "$INDEX_HTML"; then
    # Fallback to sidebar
    sed -i "s|<b>Allmon v3</b>|<b>Allmon v3</b> $BUTTON_HTML|" "$INDEX_HTML"
    echo -e "  ✓ Added Stream Audio button next to 'Allmon v3' (Sidebar)"
elif grep -q "Allmon v3" "$INDEX_HTML"; then
    # Fallback for plain text
    sed -i "s|Allmon v3|Allmon v3 $BUTTON_HTML|" "$INDEX_HTML"
    echo -e "  ✓ Added Stream Audio button next to 'Allmon v3'"
else
    # Fallback: Top of body
    sed -i "s|<body[^>]*>|&\n<div style='margin:10px;'>$BUTTON_HTML</div>|" "$INDEX_HTML"
    echo -e "  ✓ Added Stream Audio button to top of page (text not found)"
fi

echo ""
echo -e "${GREEN}Success! UI patched.${NC}"
echo "Refresh your browser to see the button."
