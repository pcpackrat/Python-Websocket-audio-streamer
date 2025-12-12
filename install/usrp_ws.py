
#!/usr/bin/env python3
"""
AllStarLink USRP -> WebSocket bridge (Python 3 + websockets, Debian 12)
- Listens for USRP UDP packets (default UDP port 34001).
- For voice (type=0), forwards payload (Int16LE PCM @ 8000 Hz) to WebSocket clients.
- For metadata (type=2 TLV msgType=8), broadcasts JSON with talkgroup, slot, callsign.
- Broadcasts PTT events (keyup/unkey) based on USRP header.
"""

import asyncio
import socket
import struct
import os
import signal
import json
from websockets.server import serve
from websockets.exceptions import ConnectionClosed

UDP_LISTEN = int(os.environ.get("USRP_UDP_PORT", "34001"))
WS_PORT    = int(os.environ.get("WS_PORT", "8080"))

CLIENTS = set()
_last_keyup = None
stop_event = asyncio.Event()

def parse_usrp_header(msg: bytes):
    if len(msg) < 32 or msg[0:4] != b"USRP":
        return None
    seq       = struct.unpack(">i", msg[4:8])[0]
    memory    = struct.unpack(">i", msg[8:12])[0]
    keyup     = struct.unpack(">i", msg[12:16])[0]
    talkgroup = struct.unpack(">i", msg[16:20])[0]
    ptype     = struct.unpack(">i", msg[20:24])[0]
    mpxid     = struct.unpack(">i", msg[24:28])[0]
    reserved  = struct.unpack(">i", msg[28:32])[0]
    payload   = msg[32:]
    return {
        "seq": seq, "memory": memory, "keyup": keyup, "talkgroup": talkgroup,
        "type": ptype, "mpxid": mpxid, "reserved": reserved, "payload": payload
    }

def parse_tlv_metadata(payload: bytes):
    if not payload or len(payload) < 15:
        return None
    msg_type = payload[0]
    if msg_type != 8:
        return None
    tg = (payload[9] << 16) | (payload[10] << 8) | payload[11]
    rxslot = payload[12]
    try:
        callsign = payload[14:].decode(errors="ignore").strip()
    except Exception:
        callsign = ""
    return {"msgType": msg_type, "talkgroup_tlv": tg, "slot": rxslot, "callsign": callsign}

async def broadcast_text(obj: dict):
    if not CLIENTS:
        return
    data = json.dumps(obj, separators=(",", ":"))
    targets = list(CLIENTS)
    await asyncio.gather(*[ws.send(data) for ws in targets if not ws.closed], return_exceptions=True)

async def broadcast_binary(buf: bytes):
    if not CLIENTS:
        return
    targets = list(CLIENTS)
    await asyncio.gather(*[ws.send(buf) for ws in targets if not ws.closed], return_exceptions=True)

async def udp_listener():
    loop = asyncio.get_running_loop()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", UDP_LISTEN))
    sock.setblocking(False)
    print(f"[USRP] UDP listening on 0.0.0.0:{UDP_LISTEN}")

    global _last_keyup
    while not stop_event.is_set():
        try:
            # Wait for packet or stop event
            recv_task = asyncio.create_task(loop.sock_recvfrom(sock, 4096))
            stop_task = asyncio.create_task(stop_event.wait())
            done, pending = await asyncio.wait(
                [recv_task, stop_task],
                return_when=asyncio.FIRST_COMPLETED
            )
            
            # If stop event fired, cancel receive and exit
            if stop_task in done:
                recv_task.cancel()
                break
                
            msg, addr = recv_task.result()
            
            # Clean up stop waiter
            stop_task.cancel()

        except asyncio.CancelledError:
            break
        except Exception as e:
            print(f"[USRP] UDP error: {e}")
            await asyncio.sleep(0.05)
            continue

        hdr = parse_usrp_header(msg)
        if not hdr:
            continue

        keyup = 1 if hdr["keyup"] else 0
        if _last_keyup is None or keyup != _last_keyup:
            _last_keyup = keyup
            await broadcast_text({"event": "ptt", "state": "keyup" if keyup else "unkey"})

        if hdr["type"] == 0:
            payload = hdr["payload"]
            if payload:
                await broadcast_binary(payload)
        elif hdr["type"] == 2:
            meta = parse_tlv_metadata(hdr["payload"])
            if meta:
                tg = meta.get("talkgroup_tlv") or hdr["talkgroup"]
                await broadcast_text({
                    "event": "meta",
                    "talkgroup": tg,
                    "slot": meta.get("slot"),
                    "callsign": meta.get("callsign", "")
                })

async def ws_handler(websocket):
    CLIENTS.add(websocket)
    try:
        peer = websocket.remote_address
        print(f"[WS] Client connected: {peer}")
        async for _ in websocket:
            pass
    except ConnectionClosed:
        pass  # Normal disconnect
    except Exception as e:
        print(f"[WS] Client error: {e}")
    finally:
        CLIENTS.discard(websocket)
        print("[WS] Client disconnected")

async def main():
    async with serve(ws_handler, "0.0.0.0", WS_PORT, max_size=None):
        print(f"[WS] WebSocket listening on :{WS_PORT}")
        await udp_listener()

def signal_handler():
    print("[SYS] Shutdown signal received.")
    stop_event.set()

if __name__ == "__main__":
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, signal_handler)
        
    try:
        loop.run_until_complete(main())
    except (KeyboardInterrupt, asyncio.CancelledError):
        pass
    finally:
        loop.close()
        print("[SYS] Stopped.")
