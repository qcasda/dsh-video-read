// page-media.js - capture media response URLs from a headless page via CDP.
// Usage: node page-media.js [port] [waitSec]
const http = require('http');

const port = process.argv[2] || '9222';
const waitSec = parseInt(process.argv[3] || '20', 10);

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
  const list = await targets();
  const page = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
  if (!page) { console.error('no page'); process.exit(2); }

  const ws = new WebSocket(page.webSocketDebuggerUrl);
  let id = 0; const pending = new Map();
  const send = (m, p = {}) => new Promise((res, rej) => {
    const i = ++id; pending.set(i, { res, rej });
    ws.send(JSON.stringify({ id: i, method: m, params: p }));
  });
  const found = new Set();
  ws.addEventListener('message', (ev) => {
    let m; try { m = JSON.parse(ev.data); } catch (_) { return; }
    if (m.id && pending.has(m.id)) {
      const q = pending.get(m.id); pending.delete(m.id);
      m.error ? q.rej(new Error(JSON.stringify(m.error))) : q.res(m.result);
      return;
    }
    if (m.method === 'Network.responseReceived') {
      const r = m.params.response;
      if (/video|audio|mpegurl|mp4/i.test(r.mimeType) || /\.mp4|\.m4a|\.ts\?/i.test(r.url)) {
        if (!found.has(r.url)) { found.add(r.url); }
      }
    }
  });

  await new Promise((r) => ws.addEventListener('open', r));
  await send('Network.enable');
  await send('Page.reload', { ignoreCache: true });
  await new Promise((r) => setTimeout(r, waitSec * 1000));
  require('fs').writeFileSync(process.argv[4]||'media.json', JSON.stringify([...found], null, 1));
  console.log('total:', found.size);
  ws.close(); process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
