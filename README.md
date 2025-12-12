# AllStarLink Audio Monitor - Deployment Guide

## Quick Install (Allmon3 + HAProxy Integration)

For standard installation where Allmon3 is running under HAProxy (or standard Apache):

```bash
cd install
chmod +x install.sh
sudo ./install.sh
```

The script will:
- Install Python dependencies
- Copy files to Allmon3 directories (`/usr/share/allmon3`)
- Create and start the systemd service
- Configure Apache WebSocket proxy
- Provide next steps for adding the monitor to your Allmon3 page

See [ALLMON3_INTEGRATION.md](ALLMON3_INTEGRATION.md) for detailed integration instructions.

To uninstall:
```bash
cd install
sudo ./uninstall.sh
```

---

## Alternative Installations

The `install-other/` directory contains scripts for specific use cases:

### 1. Standalone Stream Page
If you want a dedicated stream page (e.g., `stream.html`) instead of modifying `index.html`:

```bash
cd install-other
chmod +x install_standalone_stream.sh
sudo ./install_standalone_stream.sh
```
This creates `http://your-node/allmon3/stream.html`.

### 2. Manual Index Link
If you only need to add the "Stream Audio" link to the top of your existing Allmon3 index page (useful if `install.sh` didn't place it where you wanted):

```bash
cd install-other
chmod +x install_allmon3_index.sh
sudo ./install_allmon3_index.sh
```

### 3. Repair Index Link
If an Allmon3 update overwrites your `index.html` and removes the link, run:

```bash
cd install-other
chmod +x update_index.sh
sudo ./update_index.sh
```

---

## Overview
This project provides a web-based audio monitor for AllStarLink USRP streams. It consists of:
- **Python WebSocket Server** (`usrp_ws.py`) - Receives UDP packets from USRP and streams audio/metadata via WebSocket
- **Web Interface** (`index.html`, `style.css`, `asl-monitor.js`) - Browser-based audio player with real-time metadata display
- **Apache Configuration** - Serves the web interface and proxies WebSocket connections

## Architecture
```
USRP (UDP:34001) → Python Server (WS:8080) → Apache (HTTP:80) → Browser
```

## Prerequisites
- Python 3.7+ with `websockets` library
- Apache 2.4+ web server
- Linux/Unix system (for production) or Windows (for development)

## Manual Installation Steps (Reference)

### 1. Install Python Dependencies
```bash
pip3 install websockets
```

### 2. Configure Apache

#### Enable Required Modules
```bash
sudo a2enmod proxy
sudo a2enmod proxy_http
sudo a2enmod proxy_wstunnel
sudo a2enmod rewrite
sudo systemctl restart apache2
```

#### Deploy Web Files
```bash
# Create directory for the application
sudo mkdir -p /var/www/html/asl-monitor

# Copy web files (adjust paths as needed)
sudo cp index.html /var/www/html/asl-monitor/
sudo cp style.css /var/www/html/asl-monitor/
sudo cp asl-monitor.js /var/www/html/asl-monitor/

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html/asl-monitor
sudo chmod -R 755 /var/www/html/asl-monitor
```

#### Configure Virtual Host
```bash
# Copy Apache configuration
sudo cp apache-config.conf /etc/apache2/sites-available/asl-monitor.conf

# Edit the configuration to update DocumentRoot if needed
sudo nano /etc/apache2/sites-available/asl-monitor.conf

# Enable the site
sudo a2ensite asl-monitor.conf

# Test configuration
sudo apache2ctl configtest

# Reload Apache
sudo systemctl reload apache2
```

### 3. Run the Python WebSocket Server

#### Manual Start (for testing)
```bash
python3 usrp_ws.py
```

#### Create Systemd Service (for production)
Create `/etc/systemd/system/usrp-ws.service`:
```ini
[Unit]
Description=USRP WebSocket Audio Bridge
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/usrp-ws
ExecStart=/usr/bin/python3 /opt/usrp-ws/usrp_ws.py
Restart=always
RestartSec=10
Environment="USRP_UDP_PORT=34001"
Environment="WS_PORT=8080"

[Install]
WantedBy=multi-user.target
```

Then enable and start:
```bash
# Copy Python script to /opt
sudo mkdir -p /opt/usrp-ws
sudo cp usrp_ws.py /opt/usrp-ws/

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable usrp-ws.service
sudo systemctl start usrp-ws.service

# Check status
sudo systemctl status usrp-ws.service
```

## Configuration

### Environment Variables
The Python server supports these environment variables:
- `USRP_UDP_PORT` - UDP port to listen for USRP packets (default: 34001)
- `WS_PORT` - WebSocket server port (default: 8080)

### Firewall Configuration
If using a firewall, ensure these ports are open:
- **UDP 34001** - For USRP packets
- **TCP 8080** - For WebSocket connections (localhost only)
- **TCP 80** - For HTTP web interface

```bash
# Example UFW rules
sudo ufw allow 80/tcp
sudo ufw allow 34001/udp
# Port 8080 should only be accessible from localhost (Apache proxy)
```

## Usage

1. **Access the Web Interface**
   - Open your browser to: `http://your-server-ip/`
   - The monitor will auto-start and connect to the WebSocket server

2. **Monitor Display**
   - **Connection Status** - Shows WebSocket connection state
   - **PTT State** - Shows "Transmitting" or "Idle"
   - **Callsign** - Displays the transmitting station's callsign
   - **Talkgroup** - Shows the active talkgroup number
   - **Slot** - Displays the timeslot (for DMR systems)

3. **Controls**
   - **Start Monitoring** - Begin receiving audio stream
   - **Stop Monitoring** - Disconnect from audio stream

## Troubleshooting

### WebSocket Connection Fails
- Check that `usrp_ws.py` is running: `sudo systemctl status usrp-ws.service`
- Verify port 8080 is listening: `sudo netstat -tlnp | grep 8080`
- Check Apache error logs: `sudo tail -f /var/log/apache2/asl-monitor-error.log`

### No Audio
- Verify USRP is sending packets to UDP port 34001
- Check Python server logs for incoming packets
- Ensure browser has audio permissions enabled
- Try clicking the page to enable audio (browser autoplay policy)

### Apache Proxy Issues
- Verify proxy modules are enabled: `apache2ctl -M | grep proxy`
- Check Apache configuration: `sudo apache2ctl configtest`
- Review Apache logs: `sudo tail -f /var/log/apache2/error.log`

### Permission Errors
- Ensure www-data user has access to web files
- Check file permissions: `ls -la /var/www/html/asl-monitor/`

## Development Notes

### Testing Locally (Windows)
1. Run Python server: `python usrp_ws.py`
2. Open `index.html` directly in browser
3. Modify `asl-monitor.js` line 4 to use `ws://localhost:8080` instead of `/ws`

### Audio Format
- **Sample Rate**: 8000 Hz
- **Format**: 16-bit signed integer PCM (Int16LE)
- **Channels**: Mono

### USRP Packet Structure
- **Header**: 32 bytes (USRP magic + metadata)
- **Type 0**: Voice data (PCM audio)
- **Type 2**: TLV metadata (callsign, talkgroup, slot)

## Security Considerations

1. **Production Deployment**
   - Use HTTPS/WSS for encrypted connections
   - Implement authentication if exposing to internet
   - Restrict UDP port 34001 to trusted sources

2. **HTTPS Setup** (recommended)
   - Install SSL certificate (Let's Encrypt)
   - Update Apache config to use port 443
   - Change WebSocket to use `wss://` protocol

## License
This project is provided as-is for AllStarLink community use.
