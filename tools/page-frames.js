// page-frames.js - seek the <video> in a headless Edge tab to N timestamps and
// capture a screenshot of the video element at each one.
// Usage: node page-frames.js [port] [outDir] [frames]
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.argv[2] || '9222';
const outDir = process.argv[3] || path.join(process.env.TEMP, 'pframes');
const frames = parseInt(process.argv[4] || '14', 10);

function targets() {
  return new Promise((res, rej) => {
    http.get({ host: '127.0.0.1', port, path: '/json/list' }, (r) => {
      let d = '';
      r.on('data', (c) => (d += c));
      r.on('end', () => { try { res(JSON.parse(d)); } catch (e) { rej(e); } });
    }).on('error', rej);
  });
}

(async () => {
  fs.mkdirSync(outDir, { recursive: true });
  const list = await targets();
  const pages = list.filter((t) => t.type === 'page' && t.webSocketDebuggerUrl);
  const wantHost = (() => { try { return process.argv[5] ? new URL(process.argv[5]).host : ''; } catch (_) { return ''; } })();
  const page = (wantHost && pages.find((p) => p.url.includes(wantHost))) || pages[0];
  if (!page) { console.error('no page'); process.exit(2); }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const mid = ++id; pending.set(mid, { resolve, reject });
    ws.send(JSON.stringify({ id: mid, method, params }));
  });
  ws.addEventListener('message', (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (_) { return; }
    if (m.id && pending.has(m.id)) {
      const p = pending.get(m.id); pending.delete(m.id);
      m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result);
    }
  });
  await new Promise((r) => ws.addEventListener('open', r));

  const evalJs = async (expr) => {
    const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(JSON.stringify(r.exceptionDetails).slice(0, 200));
    return r.result.value;
  };

  await evalJs(`(() => { const v=document.querySelector('video'); if(v){v.pause(); v.muted=true;} return 1; })()`);
  await evalJs(`(() => { let n=0; document.querySelectorAll('div,section').forEach(el=>{ const cs=getComputedStyle(el); if((cs.position==='fixed'||cs.position==='absolute') && parseInt(cs.zIndex||0)>10 && el.innerText && el.innerText.includes('登录')){ el.remove(); n++; } }); return n; })()`);
  await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 2, mobile: false });
  await new Promise((r) => setTimeout(r, 1500));
  const dur = Number(await evalJs(`(() => { const v=document.querySelector('video'); return v? v.duration : 0; })()`)) || 60;
  console.log('duration:', dur.toFixed(1));

  const rect = JSON.parse(await evalJs(`(() => { const v=document.querySelector('video'); if(!v) return '{}'; const r=v.getBoundingClientRect(); return JSON.stringify({x:r.x,y:r.y,w:r.width,h:r.height}); })()`));
  console.log('rect:', rect.x, rect.y, rect.w, rect.h);

  const out = [];
  const rate = 4;
  await evalJs(`(() => { const v=document.querySelector('video'); v.muted=true; v.playbackRate=${rate}; v.play(); return 1; })()`);
  const span = dur / rate;
  const step = span / (frames + 1);
  for (let i = 1; i <= frames; i++) {
    await new Promise((r) => setTimeout(r, Math.max(400, step * 1000)));
    const shot = await send('Page.captureScreenshot', {
      format: 'png',
      clip: { x: rect.x, y: rect.y, width: rect.w, height: Math.min(rect.h, 900), scale: 1 },
      captureBeyondViewport: false,
    });
    const f = path.join(outDir, `f${String(i).padStart(2, '0')}.png`);
    fs.writeFileSync(f, Buffer.from(shot.data, 'base64'));
    out.push(f);
    const cur = await evalJs(`(() => { const v=document.querySelector('video'); return v? v.currentTime : 0; })()`);
    process.stdout.write(`\rframe ${i}/${frames} @${Number(cur).toFixed(0)}s   `);
  }
  console.log('\nframes:', out.length, '->', outDir);
  ws.close(); process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
