# USRP Audio Streamer - Installation Summary

## What You Have

This package contains everything needed to integrate the USRP Audio Streamer with Allmon3, customized for different deployment needs.

### Installation Directories

- **`install/`** - Standard installation for Allmon3 (supports HAProxy/Apache proxy).
  - `install.sh`: The main automated installer.
  - `uninstall.sh`: Remover script.
  - `update_index.sh`: Fixes the index page link after updates.
- **`install-other/`** - Alternative scripts for custom setups.
  - `install_standalone_stream.sh`: Creates a separate `stream.html` page instead of modifying `index.html`.
  - `install_allmon3_index.sh`: Manually adds the "Stream Audio" link to the existing `index.html`.
  - `update_index.sh`: Repair script (same function as in `install/` but for this context).

### Documentation
- **`README.md`** - General deployment guide
- **`ALLMON3_INTEGRATION.md`** - Detailed Allmon3 integration guide
- **`apache-config.conf`** - Example Apache configuration

## Standard Installation (Recommended)

1. **Transfer files to your server:**
   ```bash
   scp -r * user@your-server:/tmp/usrp-audio-streamer/
   ```

2. **Run the installer:**
   ```bash
   cd /tmp/usrp-audio-streamer/install
   chmod +x install.sh
   sudo ./install.sh
   ```

3. **Follow the on-screen instructions** to verify the installation.

## Alternative Instructions

### Standalone Page
To create a dedicated `stream.html` instead of integrating into the dashboard:
```bash
cd /tmp/usrp-audio-streamer/install-other
chmod +x install_standalone_stream.sh
sudo ./install_standalone_stream.sh
```

### Manual Integration
To just add the link to `index.html` (useful if you installed manually or `install.sh` missed it):
```bash
cd /tmp/usrp-audio-streamer/install-other
chmod +x install_allmon3_index.sh
sudo ./install_allmon3_index.sh
```

## Maintenance

### Restoring the Link
If an Allmon3 update overwrites your `index.html`, you can restore the button using the update script:
```bash
cd /tmp/usrp-audio-streamer/install  # or install-other
sudo ./update_index.sh
```

## What the Installer Does

1. ✅ Installs System Dependencies (Python 3, pip, net-tools, tcpdump)
2. ✅ Installs Python `websockets` library
3. ✅ Copies `usrp_ws.py` to `/opt/usrp-ws/`
4. ✅ Copies `asl-monitor.js` to `/usr/share/allmon3/js/`
5. ✅ Automatically adds "Stream Audio" button to `/usr/share/allmon3/index.html` (Standard install only)
6. ✅ Creates systemd service `/etc/systemd/system/usrp-ws.service`
7. ✅ Modifies Apache config at `/etc/apache2/conf-enabled/allmon3.conf`
8. ✅ Enables Apache proxy modules
9. ✅ Starts the WebSocket service
10. ✅ Reloads Apache

## After Installation

Simply refresh your Allmon3 page in the browser! You should see a "Stream Audio" button.

Clicking "Stream Audio" will connect to the WebSocket and start playing audio.

(Note: The script attempts to place the button above the "Home" link/button. If not found, it places it at the top of the body.)

## Verification

After installation, verify everything is working:

```bash
# Check service status
sudo systemctl status usrp-ws.service

# Check WebSocket is listening
sudo netstat -tlnp | grep 8080

# Check for USRP packets
sudo tcpdump -i any -n udp port 34001

# View service logs
sudo journalctl -u usrp-ws.service -f
```

## Troubleshooting

### No Audio / Old Interface
If the button doesn't appear or audio fails, **Hard Refresh** your browser (Ctrl+F5 or Cmd+Shift+R) to clear the cache. This is critical after updating files.

### Choppy Audio
The player includes a 60ms jitter buffer. If audio is still choppy:
- Ensure your network connection is stable.
- Check if other processes are consuming CPU on the server.

### Service won't start
```bash
sudo journalctl -u usrp-ws.service -n 50
```

### Apache errors / Port 443 Conflict
If Apache fails to restart, check if it's conflicting with HAProxy on port 443:
```bash
sudo journalctl -u apache2
grep -r "Listen 443" /etc/apache2/
```
You may need to disable `Listen 443` in `/etc/apache2/ports.conf` if HAProxy handles SSL.

## HAProxy Support

If using HAProxy, we recommend routing the WebSocket directly to the Python service (port 8080) for best performance, bypassing Apache for the stream.

Add to `haproxy.cfg` frontend:
```haproxy
acl is_websocket path_beg /allmon3/audio-ws
use_backend ws_back if is_websocket
```

Add backend:
```haproxy
backend ws_back
    server ws1 127.0.0.1:8080
```

## Uninstallation

To remove the audio streamer:
```bash
cd install
sudo ./uninstall.sh
```

Note: The uninstaller attempts to restore `index.html` from backup. If that fails, you may need to manually remove the injected script/button.

## Configuration

The service uses these defaults:
- **USRP UDP Port**: 34001
- **WebSocket Port**: 8080 (localhost only)
- **WebSocket Path**: `/allmon3/audio-ws`

To change these, edit `/etc/systemd/system/usrp-ws.service` and restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart usrp-ws.service
```

## Support

For issues or questions:
1. Check the logs (see Troubleshooting section)
2. Review `ALLMON3_INTEGRATION.md` for detailed setup
3. Review `README.md` for general deployment information
