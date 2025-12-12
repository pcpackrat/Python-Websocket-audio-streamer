# Allmon3 Integration Guide for USRP Audio Monitor

## Allmon3 Directory Structure (ASL3/Debian 12)

Allmon3 is typically installed in:
```
/usr/share/allmon3/
```

Directory structure:
```
css/
img/
index.html
js/
voter.html
```

## File Placement

### 1. JavaScript Files
Place your JavaScript in the Allmon3 js directory:
```bash
sudo cp asl-monitor.js /usr/share/allmon3/js/
```

### 3. Python WebSocket Server
Place the Python server in a system location:
```bash
sudo mkdir -p /opt/usrp-ws
sudo cp usrp_ws.py /opt/usrp-ws/
sudo chmod +x /opt/usrp-ws/usrp_ws.py
```

## Apache Configuration for Allmon3

Allmon3 already has Apache configured. You just need to add the WebSocket proxy.

### Edit Allmon3 Apache Config
The Allmon3 config is typically at:
```
/etc/apache2/conf-available/allmon3.conf
```

Add these lines **after the existing ProxyPass directives**:

```apache
# USRP Audio Streamer WebSocket Proxy
ProxyPass /allmon3/audio-ws ws://localhost:8080/
ProxyPassReverse /allmon3/audio-ws ws://localhost:8080/
```

Then reload Apache:
```bash
sudo systemctl reload apache2
```

## Systemd Service for Python Server

Create `/etc/systemd/system/usrp-ws.service`:

```ini
[Unit]
Description=USRP WebSocket Audio Bridge for Allmon3
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

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable usrp-ws.service
sudo systemctl start usrp-ws.service
sudo systemctl status usrp-ws.service
```

## Adding to Allmon3 Page

The `install.sh` script automatically adds a "Stream Audio" button to your `index.html`.

If you need to do this manually:

1. Add the script reference before the closing `</body>` tag:
   ```html
   <script src="js/asl-monitor.js"></script>
   <script>
       var audioMonitorActive = false;
       function toggleAudioStream() {
           if (!audioMonitorActive) {
               ASLMonitor.start({ wsPath: "/allmon3/audio-ws" });
               audioMonitorActive = true;
               document.getElementById("audioStreamBtn").textContent = "Stop Audio";
               document.getElementById("audioStreamBtn").classList.add("active");
           } else {
               ASLMonitor.stop();
               audioMonitorActive = false;
               document.getElementById("audioStreamBtn").textContent = "Stream Audio";
               document.getElementById("audioStreamBtn").classList.remove("active");
           }
       }
   </script>
   ```

2. Add the button where you want it to appear:
   ```html
   <button id="audioStreamBtn" onclick="toggleAudioStream()" style="padding: 8px 16px; background-color: #4CAF50; color: white; border: none; border-radius: 4px; cursor: pointer;">
       Stream Audio
   </button>
   ```



## Verification Steps

1. **Check Python server is running:**
   ```bash
   sudo systemctl status usrp-ws.service
   sudo netstat -tlnp | grep 8080
   ```

2. **Check Apache proxy:**
   ```bash
   sudo apache2ctl -M | grep proxy
   sudo tail -f /var/log/apache2/error.log
   ```

3. **Test WebSocket connection:**
   - Open browser console (F12)
   - Navigate to Allmon3 page
   - Look for WebSocket connection messages

4. **Verify USRP packets:**
   ```bash
   sudo tcpdump -i any -n udp port 34001
   ```

## File Permissions

Ensure proper permissions:
```bash
sudo chown -R www-data:www-data /usr/share/allmon3/
sudo chmod 644 /usr/share/allmon3/js/asl-monitor.js
sudo chown -R www-data:www-data /opt/usrp-ws/
sudo chmod 755 /opt/usrp-ws/usrp_ws.py
```

## Troubleshooting

### WebSocket 403 Forbidden
- Check Apache proxy modules are enabled
- Verify ProxyPass directives are in the VirtualHost

### No Audio
- Verify USRP is sending to UDP 34001
- Check browser console for errors
- Ensure browser audio permissions

### Service Won't Start
- Check Python dependencies: `pip3 install websockets`
- Review service logs: `sudo journalctl -u usrp-ws.service -f`

## Complete Installation Script

```bash
#!/bin/bash
# Quick install script for Allmon3 integration

# Install Python dependencies
pip3 install websockets

# Create directories
sudo mkdir -p /opt/usrp-ws

# Copy files
sudo cp usrp_ws.py /opt/usrp-ws/
sudo cp asl-monitor.js /usr/share/allmon3/js/
sudo cp style.css /usr/share/allmon3/css/asl-monitor.css

# Set permissions
sudo chown -R www-data:www-data /opt/usrp-ws/
sudo chown -R www-data:www-data /usr/share/allmon3/
sudo chmod 755 /opt/usrp-ws/usrp_ws.py

# Create systemd service
sudo tee /etc/systemd/system/usrp-ws.service > /dev/null <<EOF
[Unit]
Description=USRP WebSocket Audio Bridge for Allmon3
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
EOF

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable usrp-ws.service
sudo systemctl start usrp-ws.service

echo "Installation complete!"
echo "Add WebSocket proxy to /etc/apache2/conf-available/allmon3.conf"
echo "Then reload Apache: sudo systemctl reload apache2"
```
