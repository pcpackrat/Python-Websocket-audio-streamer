
// WebSocket PCM player + metadata (USRP TLV) for AllStar (16-bit PCM @ 8000 Hz, mono)
(function () {
  const WS_PATH = '/ws';
  const RATE = 8000;

  function createPlayer(wsUrl, ui) {
    const AudioCtx = window.AudioContext || window.webkitAudioContext;
    const audioCtx = new AudioCtx({ sampleRate: RATE });

    const ws = new WebSocket(wsUrl);
    ws.binaryType = 'arraybuffer';

    // Jitter buffering state
    let nextStartTime = 0;

    function setPTT(state) {
      if (ui.ptt) ui.ptt.textContent = (state === 'keyup') ? 'Transmitting' : 'Idle';
    }
    function setMeta(meta) {
      if (ui.callsign) ui.callsign.textContent = meta.callsign || '';
      if (ui.tg) ui.tg.textContent = (meta.talkgroup !== undefined) ? String(meta.talkgroup) : '';
      if (ui.slot) ui.slot.textContent = (meta.slot !== undefined) ? String(meta.slot) : '';
    }

    ws.onopen = () => { if (ui.status) ui.status.textContent = 'Connected.'; };
    ws.onclose = () => { if (ui.status) ui.status.textContent = 'Disconnected.'; };
    ws.onerror = (e) => { if (ui.status) ui.status.textContent = 'WS error.'; console.error(e); };

    ws.onmessage = (ev) => {
      // If data is text: JSON metadata or PTT
      if (typeof ev.data === 'string') {
        try {
          const obj = JSON.parse(ev.data);
          if (obj.event === 'ptt') setPTT(obj.state);
          else if (obj.event === 'meta') setMeta(obj);
        } catch (e) {
          // ignore
        }
        return;
      }

      // Resume context if suspended (Autoplay policy)
      if (audioCtx.state === 'suspended') {
        audioCtx.resume();
      }

      // Binary audio: Int16LE PCM -> Float32
      const int16 = new Int16Array(ev.data);
      const n = int16.length;
      const buf = audioCtx.createBuffer(1, n, RATE);
      const out = buf.getChannelData(0);
      for (let i = 0; i < n; i++) out[i] = int16[i] / 32768.0;

      const src = audioCtx.createBufferSource();
      src.buffer = buf;
      src.connect(audioCtx.destination);

      // Jitter Buffer Logic
      const now = audioCtx.currentTime;
      if (nextStartTime < now) {
        // Buffer run dry or first packet: reset to now + 60ms latency
        nextStartTime = now + 0.060;
      }

      src.start(nextStartTime);
      nextStartTime += buf.duration;
    };

    return {
      stop: () => { try { ws.close(); } catch (_) { } try { audioCtx.close(); } catch (_) { } }
    };
  }

  // Expose API
  window.ASLMonitor = {
    start: function (opts = {}) {
      const proto = (location.protocol === 'https:') ? 'wss:' : 'ws:';
      const wsPath = opts.wsPath || WS_PATH;
      const url = `${proto}//${location.host}${wsPath}`;
      const ui = {
        status: document.getElementById(opts.statusId || 'rxStatus'),
        ptt: document.getElementById(opts.pttId || 'rxPTT'),
        callsign: document.getElementById(opts.callId || 'rxCall'),
        tg: document.getElementById(opts.tgId || 'rxTG'),
        slot: document.getElementById(opts.slotId || 'rxSlot'),
      };
      window.__asl_player = createPlayer(url, ui);
    },
    stop: function () {
      if (window.__asl_player) { window.__asl_player.stop(); window.__asl_player = null; }
    }
  };

})();