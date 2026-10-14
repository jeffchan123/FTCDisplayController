#!/bin/bash
# Local Mac controller. Requires Python 3; uses existing ADB and scrcpy installation.
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to run this controller."
  read -r -p "Press Enter to close ..."
  exit 1
fi
python3 - <<'PY'
import concurrent.futures, json, os, secrets, shlex, subprocess, threading, time, webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ADB = os.environ.get('FTC_ADB', os.path.expanduser('~/Downloads/platform-tools/adb'))
SCRCPY = os.environ.get('FTC_SCRCPY_DIR', '/Users/ahot/scrcpy-2.7')
DEFAULT_URL = 'http://192.168.86.37/event/s0/display/?type=audience'
TOKEN = secrets.token_urlsafe(24)
POOL = concurrent.futures.ThreadPoolExecutor(max_workers=12)
STATE_LOCK = threading.Lock()
DEVICES = {n: {'ip': '192.168.86.' + str(n), 'model': 'K2R2TE' if n == 105 else ('M3N6RA' if n == 106 else 'E9L29Y'),
               'status': 'Connecting', 'busy': False, 'logs': [], 'mirror': None,
               'screen_lock': threading.Lock()} for n in range(100, 107)}

def log(n, text, status=None):
    with STATE_LOCK:
        d = DEVICES[n]
        d['logs'].append(time.strftime('%H:%M:%S') + '  ' + str(text))
        d['logs'] = d['logs'][-70:]
        if status is not None: d['status'] = status

def call(args, timeout=15):
    r = subprocess.run([ADB] + args, capture_output=True, timeout=timeout)
    if r.returncode:
        raise RuntimeError((r.stderr or r.stdout).decode(errors='replace').strip() or 'ADB command failed')
    return r.stdout

def serial(n): return DEVICES[n]['ip'] + ':5555'
def shell(n, *args): return call(['-s', serial(n), 'shell'] + list(args)).decode(errors='replace').strip()
def key(n, code): shell(n, 'input', 'keyevent', str(code))

def connect(n):
    text = call(['connect', serial(n)]).decode(errors='replace').strip()
    if call(['-s', serial(n), 'get-state']).strip() != b'device':
        raise RuntimeError(text or 'Offline or awaiting ADB authorization')
    log(n, text, 'Connected')

def mirror(n):
    d = DEVICES[n]
    with STATE_LOCK:
        old = d['mirror']
        if old is not None and old.poll() is None:
            log_text = 'scrcpy is already open'
        else:
            run = os.path.join(SCRCPY, 'run')
            if not os.path.isfile(run) or not os.access(run, os.X_OK):
                raise RuntimeError('scrcpy launcher not found: ' + run)
            env = dict(os.environ, ADB=ADB)
            d['mirror'] = subprocess.Popen(['./run', 'x', '-s', serial(n), '--window-title',
                                            d['ip'] + ' - ' + d['model'], '--max-size=800', '--max-fps=15', '-b', '1M'], cwd=SCRCPY, env=env)
            log_text = 'Opened scrcpy: ' + d['ip'] + ' - ' + d['model']
    log(n, log_text)

def setup(n, url, open_mirror):
    connect(n)
    if open_mirror:
        try: mirror(n)
        except Exception as exc: log(n, 'scrcpy warning: ' + str(exc))
    log(n, 'Setting up ' + DEVICES[n]['model'], 'Setting up')
    for namespace, name, value in [('secure','screensaver_enabled','0'), ('secure','sleep_timeout','0'),
                                   ('system','screen_off_timeout','2147483647')]:
        try:
            shell(n, 'settings', 'put', namespace, name, value)
            actual = shell(n, 'settings', 'get', namespace, name)
            log(n, name + ' = ' + actual + ('' if actual == value else ' (unexpected value)'))
        except Exception as exc: log(n, 'Setting warning: ' + str(exc))
    key(n, 224); time.sleep(2)
    key(n, 3); time.sleep(2)
    result = shell(n, 'am start -W -a android.intent.action.VIEW -d ' + shlex.quote(url) + ' -p com.amazon.cloud9')
    if any(s in result.lower() for s in ['error:', 'exception', 'unable to resolve']):
        raise RuntimeError(result)
    log(n, 'Opened ' + url)
    if n == 105:
        time.sleep(2); key(n, 82)
        for _ in range(5): key(n, 20); time.sleep(.15)
        time.sleep(2); key(n, 82); time.sleep(2); key(n, 82)
    else:
        time.sleep(5); key(n, 82); time.sleep(5); key(n, 82)
    version = shell(n, 'dumpsys', 'package', 'com.amazon.cloud9')
    lines = [s.strip() for s in version.splitlines() if 'versionName=' in s]
    if lines: log(n, 'Silk ' + lines[0])
    log(n, 'Setup sequence complete; check the screen preview.', 'Ready — check preview')

def perform(n, action, payload):
    try:
        if action == 'setup': setup(n, payload['url'], payload.get('mirror', False))
        elif action == 'connect': connect(n)
        elif action == 'mirror': connect(n); mirror(n)
        elif action == 'key': key(n, payload['key']); log(n, 'Remote: ' + str(payload['key']))
        elif action == 'reload': key(n, 285); log(n, 'Refresh key sent')
    except Exception as exc: log(n, str(exc), 'Error — see log')
    finally:
        with STATE_LOCK: DEVICES[n]['busy'] = False

def submit(n, action, payload):
    with STATE_LOCK:
        if DEVICES[n]['busy']: return False
        DEVICES[n]['busy'] = True
    POOL.submit(perform, n, action, payload)
    return True

HTML = r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FTC Fire Stick Controller</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#101720;color:#edf3fb;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}header{padding:22px 26px;border-bottom:1px solid #2b3645;background:#182230}h1{font-size:23px;margin:0 0 6px}p{color:#aabbd0;margin:0}main{padding:18px 26px}.bar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:16px}input[type=text]{background:#0c131d;color:#fff;border:1px solid #41536a;padding:11px;border-radius:7px;width:100px}input[type=url]{flex:1;min-width:230px;background:#0c131d;color:#fff;border:1px solid #41536a;padding:11px;border-radius:7px}select{background:#0c131d;color:#edf3fb;border:1px solid #41536a;padding:7px;border-radius:6px}button{background:#2c3b50;color:#edf3fb;border:1px solid #455a73;border-radius:6px;padding:8px 10px;cursor:pointer}button:hover{background:#405570}button:disabled{opacity:.4;cursor:default}.primary{background:#177b78;border-color:#229992}.primary:hover{background:#219791}label{color:#bac8d9}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}.card[hidden]{display:none}.tray{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 16px}.tray button{font-size:12px}.heading button{padding:5px 8px;margin-left:8px}.card{background:#1a2635;border:1px solid #32445a;border-radius:10px;overflow:hidden}.heading{padding:13px 14px;display:flex;justify-content:space-between;align-items:center}.heading strong{font-size:17px}.model{color:#95afcb;font-size:12px}.screen{height:180px;background:#070c13;position:relative;display:flex;align-items:center;justify-content:center}.screen img{max-width:100%;max-height:180px;object-fit:contain}.empty{position:absolute;color:#8b9bb0;text-align:center;padding:15px;pointer-events:none}.screen img:not([src]){display:none}.status{padding:8px 14px;color:#80d6cb;font-size:12px;min-height:32px}.controls{padding:0 14px 12px}.actions{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:9px}.remote{display:flex;gap:6px;flex-wrap:wrap}.remote button{min-width:36px;padding:6px 8px}details{border-top:1px solid #32445a;padding:9px 14px;color:#aabbd0}summary{cursor:pointer}pre{white-space:pre-wrap;font-size:11px;max-height:150px;overflow:auto;color:#c7d7e7}#notice{min-height:23px;color:#e8b77a;margin-bottom:8px}.footer{padding:14px 0;color:#8c9db4;font-size:12px}@media(max-width:650px){.grid{grid-template-columns:1fr}main,header{padding:16px}input[type=url]{min-width:220px}}
</style></head><body><header><h1>FTC Fire Stick Controller</h1><p>Seven displays · .100–104 E9L29Y · .105 K2R2TE · .106 M3N6RA</p></header><main>
<div class="bar"><label>Server <input id="server" type="url" value="http://192.168.86.37" aria-label="Display server"></label><label>Event code <input id="event" type="text" value="s0" aria-label="Event code"></label><label>Display type <select id="displayType"><option value="audience" selected>Audience</option><option value="field">Field</option><option value="pit">Pit</option><option value="sponsor">Sponsor</option><option value="cmpBar">Championship bar</option></select></label><button class="primary" id="setupAll">Set up visible</button><button id="connectAll">Reconnect visible</button><button id="mirrorAll">Open visible scrcpy</button></div>
<div class="bar"><label><input type="checkbox" id="live" checked> Live previews</label><label>Refresh <select id="interval"><option value="0">Realtime (as fast as available)</option><option value="2000" selected>2 seconds</option><option value="5000">5 seconds</option><option value="10000">10 seconds</option></select></label><label><input type="checkbox" id="mirror"> Open scrcpy during setup</label><button id="refresh">Refresh previews</button></div><div id="urlPreview" style="color:#95afcb;margin-bottom:10px;overflow-wrap:anywhere"></div><div id="notice"></div><div class="tray" id="tray" aria-label="Minimized devices"></div><div class="grid" id="grid"></div><div class="footer">Minimize unused devices with −; restore them from the tray. Group actions and preview refresh apply only to visible devices. Leave the controller's Terminal window open. Closing a scrcpy window does not stop the display. Realtime requests the next screenshot as soon as the previous one finishes; actual speed depends on Wi-Fi and the stick. Open scrcpy for continuous video and live control.</div></main>
<script>
const token='__TOKEN__',devices=[100,101,102,103,104,105,106],pending=new Set(),timers=new Map();
const api=(path)=>path+(path.includes('?')?'&':'?')+'token='+encodeURIComponent(token);
function displayURL(){const base=document.getElementById('server').value.trim().replace(/\/+$/,'');const event=document.getElementById('event').value.trim();if(!event)throw new Error('Enter an event code');const server=new URL(base);if(!['http:','https:'].includes(server.protocol))throw new Error('Server must begin with http:// or https://');return base+'/event/'+encodeURIComponent(event)+'/display/?type='+encodeURIComponent(document.getElementById('displayType').value)}
function updateURLPreview(){try{document.getElementById('urlPreview').textContent=displayURL()}catch(e){document.getElementById('urlPreview').textContent=e.message}}
for(const id of ['server','event','displayType'])document.getElementById(id).addEventListener('input',updateURLPreview);updateURLPreview();
const minimized=new Set();
try{for(const n of JSON.parse(localStorage.getItem('ftc-minimized')||'[]'))if(devices.includes(n))minimized.add(n)}catch(e){}
function visibleDevices(){return devices.filter(n=>!minimized.has(n))}
function saveMinimized(){try{localStorage.setItem('ftc-minimized',JSON.stringify([...minimized]))}catch(e){}}
function renderTray(){const tray=document.getElementById('tray');tray.textContent='';for(const n of devices){document.getElementById('card'+n).hidden=minimized.has(n);if(minimized.has(n)){const b=document.createElement('button');b.textContent='Restore .'+n+' · '+(n===105?'K2R2TE':n===106?'M3N6RA':'E9L29Y');b.onclick=()=>restore(n);tray.appendChild(b)}}}
function minimize(n){minimized.add(n);clearTimeout(timers.get(n));timers.delete(n);saveMinimized();renderTray()}
function restore(n){minimized.delete(n);saveMinimized();renderTray();screen(n)}

for(const n of devices){const model=n===105?'K2R2TE':n===106?'M3N6RA':'E9L29Y';const card=document.createElement('section');card.className='card';card.id='card'+n;card.innerHTML=`<div class="heading"><strong>192.168.86.${n}</strong><span><span class="model">${model}</span><button data-minimize="true" title="Minimize this device">−</button></span></div><div class="screen"><img id="img${n}" alt="Screen preview for ${n}"><span class="empty" id="empty${n}">Connecting…</span></div><div class="status" id="status${n}">Connecting</div><div class="controls"><div class="actions"><button class="primary" data-action="setup">Set up display</button><button data-action="mirror">Open scrcpy</button><button data-action="connect">Reconnect</button></div><div class="remote">${[['Wake',224],['Home',3],['Back',4],['Menu',82],['↑',19],['←',21],['OK',23],['→',22],['↓',20]].map(([label,key])=>`<button data-key="${key}">${label}</button>`).join('')}</div></div><details><summary>Activity log</summary><pre id="log${n}"></pre></details>`;card.addEventListener('click',e=>{const b=e.target.closest('button');if(b){if(b.dataset.minimize)minimize(n);else act(n,b.dataset.action||'key',b.dataset.key?Number(b.dataset.key):null)}});document.getElementById('grid').appendChild(card)}
async function act(n,action,key=null){let url='';if(action==='setup'){try{url=displayURL()}catch(e){document.getElementById('notice').textContent=e.message;return}}try{const r=await fetch(api('/action'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({n,action,key,url,mirror:document.getElementById('mirror').checked})});const d=await r.json();if(!r.ok)throw new Error(d.error);document.getElementById('notice').textContent=d.message;poll()}catch(e){document.getElementById('notice').textContent=String(e)}}
for(const [id,action] of [['setupAll','setup'],['connectAll','connect'],['mirrorAll','mirror']])document.getElementById(id).onclick=()=>visibleDevices().forEach(n=>act(n,action));
async function poll(){try{const r=await fetch(api('/state'));const data=await r.json();for(const d of data){document.getElementById('status'+d.n).textContent=d.status+(d.busy?' · Working…':'');document.getElementById('log'+d.n).textContent=d.logs.join('\n');document.querySelectorAll('#card'+d.n+' button').forEach(b=>b.disabled=b.dataset.minimize?false:d.busy)}}catch(e){document.getElementById('notice').textContent='Controller stopped or disconnected. Keep its Terminal window open.'}}
async function screen(n){if(minimized.has(n)||pending.has(n))return;clearTimeout(timers.get(n));pending.add(n);const started=Date.now();try{const r=await fetch(api('/screen?n='+n));if(!r.ok)throw new Error(await r.text());const blob=await r.blob(),img=document.getElementById('img'+n),old=img.dataset.object;const object=URL.createObjectURL(blob);img.src=object;img.dataset.object=object;if(old)URL.revokeObjectURL(old);document.getElementById('empty'+n).textContent='';img.style.opacity='1'}catch(e){document.getElementById('empty'+n).textContent='Preview unavailable · reconnect or authorize ADB';document.getElementById('img'+n).style.opacity='.2'}finally{pending.delete(n);if(!minimized.has(n)&&document.getElementById('live').checked){const interval=Number(document.getElementById('interval').value);timers.set(n,setTimeout(()=>screen(n),Math.max(100,interval-(Date.now()-started))))}}}
function refresh(){visibleDevices().forEach(screen)}document.getElementById('refresh').onclick=refresh;
function restartPreviews(){for(const timer of timers.values())clearTimeout(timer);timers.clear();if(document.getElementById('live').checked)refresh()}
document.getElementById('live').onchange=restartPreviews;document.getElementById('interval').onchange=restartPreviews;
renderTray();setInterval(poll,1500);poll();visibleDevices().forEach(n=>act(n,'setup'));setTimeout(refresh,2000);
</script></body></html>'''

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def respond(self, code, data, mime='application/json'):
        if mime == 'application/json': data = json.dumps(data).encode()
        elif isinstance(data, str): data = data.encode()
        self.send_response(code); self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store'); self.end_headers(); self.wfile.write(data)
    def authorized(self):
        q = parse_qs(urlparse(self.path).query)
        return secrets.compare_digest(q.get('token', [''])[0], TOKEN)
    def do_GET(self):
        if not self.authorized(): return self.respond(403, {'error':'Unauthorized'})
        route = urlparse(self.path).path
        if route == '/':
            return self.respond(200, HTML.replace('__TOKEN__', TOKEN).replace('__URL__', json.dumps(DEFAULT_URL)), 'text/html; charset=utf-8')
        if route == '/state':
            with STATE_LOCK:
                data = [{'n':n, 'status':d['status'], 'busy':d['busy'], 'logs':list(d['logs'])} for n,d in DEVICES.items()]
            return self.respond(200, data)
        if route == '/screen':
            try:
                n = int(parse_qs(urlparse(self.path).query)['n'][0])
                if n not in DEVICES: raise ValueError('Unknown device')
                with DEVICES[n]['screen_lock']:
                    data = call(['-s', serial(n), 'exec-out', 'screencap', '-p'], timeout=8)
                if not data.startswith(b'\x89PNG\r\n\x1a\n'): raise RuntimeError('No screenshot received')
                return self.respond(200, data, 'image/png')
            except Exception as exc: return self.respond(503, str(exc), 'text/plain')
        self.respond(404, {'error':'Not found'})
    def do_POST(self):
        if not self.authorized(): return self.respond(403, {'error':'Unauthorized'})
        if urlparse(self.path).path != '/action': return self.respond(404, {'error':'Not found'})
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 8192: raise ValueError('Invalid request size')
            data = json.loads(self.rfile.read(length))
            n = int(data['n']); action = data['action']
            if n not in DEVICES or action not in ('setup','connect','mirror','key'): raise ValueError('Unknown action or device')
            if action == 'key' and data.get('key') not in (224,3,4,82,19,21,23,22,20): raise ValueError('Unknown remote button')
            if action == 'setup':
                url = data.get('url','')
                if not isinstance(url,str) or urlparse(url).scheme not in ('http','https') or not urlparse(url).netloc:
                    raise ValueError('Enter a valid HTTP or HTTPS URL')
            if not submit(n, action, data): return self.respond(409, {'error':DEVICES[n]['ip']+' is busy; wait for setup to finish.'})
            self.respond(200, {'message':action.capitalize()+' started for '+DEVICES[n]['ip']})
        except Exception as exc: self.respond(400, {'error':str(exc)})

if __name__ == '__main__':
    if not os.path.isfile(ADB) or not os.access(ADB, os.X_OK):
        raise SystemExit('ADB not found: ' + ADB + '\nSet FTC_ADB to its full path before launching.')
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    address = 'http://127.0.0.1:%d/?token=%s' % (server.server_port, TOKEN)
    print('FTC Fire Stick Controller is running. Keep this Terminal window open.', flush=True)
    print('Press Control-C to stop. Your Fire Stick displays will keep running.', flush=True)
    webbrowser.open(address)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        server.server_close()
        POOL.shutdown(wait=False)
PY
