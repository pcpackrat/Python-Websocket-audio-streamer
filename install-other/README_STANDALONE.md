# ASL3 Audio Streamer (Standalone Node)

This package installs the USRP Audio Streamer for a standard ASL3 node (Debian 12).
Unlike the main installer, this **does not** touch your existing `index.html`. Instead, it creates a separate streaming page.

## Contents
- `install_standalone.sh` - Automated installer
- `usrp_ws.py` - Audio Streaming Service
- `stream.html` - The audio player page
- `asl-monitor.js` - Audio player logic

## Installation

1. Copy this folder to your node:
   ```bash
   scp -r install-other user@node:/tmp/
   ```

2. Run the installer:
   ```bash
   cd /tmp/install-other
   chmod +x install_standalone.sh
   sudo ./install_standalone.sh
   ```

3. Access the Stream:
   Open your browser to:
   **http://<YOUR_NODE_IP>/allmon3/stream.html**

## Troubleshooting
- **No Audio**: Hard refresh your browser (Ctrl+F5).
- **Service Status**: `sudo systemctl status usrp-ws.service`
- **Logs**: `sudo journalctl -u usrp-ws.service -f`
- **Apache Error**: `sudo tail -f /var/log/apache2/error.log`

## Configuration
- **Port**: Default UDP 34001 used for USRP input.
- **WebSocket**: Uses internal `ws://localhost:8080` proxied via Apache `/allmon3/audio-ws`.
