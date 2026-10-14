#!/bin/bash
# Local Mac controller. Requires Python 3; uses existing ADB and scrcpy installation.
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 is required to run this controller."
  read -r -p "Press Enter to close ..."
  exit 1
fi
python3 - <<'PY'
import concurrent.futures, json, os, secrets, shlex, subprocess, threading, time, webbrowser
from pathlib import Path
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
               'screen_lock': threading.Lock(), 'health': 'unknown', 'last_preview': None,
               'seen_connected': False, 'location': '', 'minimized': False, 'selected': True, 'auto_restore': False, 'url': DEFAULT_URL} for n in range(100, 107)}

CONFIG_PATH = Path(os.environ.get('FTC_CONFIG', str(Path.home() / '.ftc-firestick-controller.json')))
OPTIONS = {'startup': 'monitor', 'auto_reconnect': True}
STOP = threading.Event()
STARTUP_LOCK = threading.Lock()
STARTUP_DONE = False
CONFIG_WRITE_LOCK = threading.Lock()
try:
    stored = json.loads(CONFIG_PATH.read_text())
    OPTIONS.update({k:v for k,v in stored.get('options', {}).items() if k in OPTIONS})
    for n,d in DEVICES.items():
        for k in ('location','minimized','selected','auto_restore','url'):
            if k in stored.get('devices',{}).get(str(n),{}): d[k] = stored['devices'][str(n)][k]
except (OSError, ValueError, TypeError): pass
if OPTIONS['startup'] not in ('monitor','setup'): OPTIONS['startup'] = 'monitor'

def save_config():
    with CONFIG_WRITE_LOCK:
        with STATE_LOCK:
            snapshot = {'options': dict(OPTIONS), 'devices': {str(n):{k:d[k] for k in ('location','minimized','selected','auto_restore','url')} for n,d in DEVICES.items()}}
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        temp = CONFIG_PATH.with_suffix('.tmp')
        temp.write_text(json.dumps(snapshot, indent=2))
        os.replace(temp, CONFIG_PATH)

def state_data():
    with STATE_LOCK:
        return {'options':dict(OPTIONS), 'devices':[{'n':n, **{k:d[k] for k in ('ip','model','status','health','busy','logs','last_preview','location','minimized','selected','auto_restore','url')}} for n,d in DEVICES.items()]}


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
    with STATE_LOCK:
        DEVICES[n]['health'] = 'connected'
        DEVICES[n]['seen_connected'] = True
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
                                            (d['location'] + ' - ' if d['location'] else '') + d['ip'] + ' - ' + d['model'], '--max-size=800', '--max-fps=15', '-b', '1M'], cwd=SCRCPY, env=env)
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
    open_display(n, url)
    try:
        version = shell(n, 'dumpsys', 'package', 'com.amazon.cloud9')
        lines = [v.strip() for v in version.splitlines() if 'versionName=' in v]
        if lines: log(n, 'Silk ' + lines[0])
    except Exception as exc: log(n, 'Version lookup warning: ' + str(exc))

def open_display(n, url):
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
    with STATE_LOCK: DEVICES[n]['url'] = url
    save_config()
    log(n, 'Display opened; check preview.', 'Ready — check preview')

def recover(n):
    connect(n)
    log(n, 'Restoring assigned display', 'Recovering display')
    open_display(n, DEVICES[n]['url'])


def perform(n, action, payload):
    try:
        if action == 'setup': setup(n, payload['url'], payload.get('mirror', False))
        elif action == 'recover': recover(n)
        elif action == 'connect': connect(n)
        elif action == 'mirror': connect(n); mirror(n)
        elif action == 'key': key(n, payload['key']); log(n, 'Remote: ' + str(payload['key']))
        elif action == 'reload': key(n, 285); log(n, 'Refresh key sent')
    except Exception as exc:
        message = str(exc)
        with STATE_LOCK:
            if 'unauthorized' in message.lower(): DEVICES[n]['health'] = 'unauthorized'
            elif any(x in message.lower() for x in ('offline','failed to connect','no devices','not found')): DEVICES[n]['health'] = 'offline'
        log(n, message, 'Error — see log')
    finally:
        with STATE_LOCK: DEVICES[n]['busy'] = False

def submit(n, action, payload):
    with STATE_LOCK:
        if DEVICES[n]['busy']: return False
        DEVICES[n]['busy'] = True
    POOL.submit(perform, n, action, payload)
    return True

def startup_once():
    global STARTUP_DONE
    with STARTUP_LOCK:
        if STARTUP_DONE: return
        STARTUP_DONE = True
    for n,d in DEVICES.items():
        if not d['minimized']:
            submit(n, 'setup' if OPTIONS['startup']=='setup' else 'connect', {'url': d['url'], 'mirror': False})

def monitor_connections():
    while not STOP.is_set():
        try:
            if not STARTUP_DONE:
                STOP.wait(1)
                continue
            listing = call(['devices'], timeout=8).decode(errors='replace')
            states = dict(line.split()[:2] for line in listing.splitlines() if ':5555' in line and len(line.split())>=2)
            for n,d in DEVICES.items():
                with STATE_LOCK:
                    if d['busy'] or d['minimized']: continue
                    before = d['health']
                    raw = states.get(serial(n), 'offline')
                    health = 'connected' if raw=='device' else 'unauthorized' if raw=='unauthorized' else 'offline'
                    d['health'] = health
                    if health=='connected': d['seen_connected'] = True
                    if health!='connected': d['status'] = 'Authorize on TV' if health=='unauthorized' else 'Waiting for connection'
                    reconnect = OPTIONS['auto_reconnect'] and health=='offline'
                    restore = health=='connected' and before=='offline' and d['auto_restore']
                if reconnect: submit(n, 'recover' if d['auto_restore'] and d['seen_connected'] else 'connect', {})
                elif restore: submit(n, 'recover', {})
        except Exception:
            pass
        STOP.wait(10)


HTML = r'''<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>FTC Fire Stick Controller</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#101720;color:#edf3fb;font:14px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}header{padding:22px 26px;border-bottom:1px solid #2b3645;background:#182230}h1{font-size:23px;margin:0 0 6px}p{color:#aabbd0;margin:0}main{padding:18px 26px}.bar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin-bottom:16px}input[type=text]{background:#0c131d;color:#fff;border:1px solid #41536a;padding:11px;border-radius:7px;width:100px}input[type=url]{flex:1;min-width:230px;background:#0c131d;color:#fff;border:1px solid #41536a;padding:11px;border-radius:7px}select{background:#0c131d;color:#edf3fb;border:1px solid #41536a;padding:7px;border-radius:6px}button{background:#2c3b50;color:#edf3fb;border:1px solid #455a73;border-radius:6px;padding:8px 10px;cursor:pointer}button:hover{background:#405570}button:disabled{opacity:.4;cursor:default}.primary{background:#177b78;border-color:#229992}.primary:hover{background:#219791}label{color:#bac8d9}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:16px}.card[hidden]{display:none}.tray{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 16px}.tray button{font-size:12px}.heading button{padding:5px 8px;margin-left:8px}.card{background:#1a2635;border:1px solid #32445a;border-radius:10px;overflow:hidden}.heading{padding:13px 14px;display:flex;justify-content:space-between;align-items:center}.location{width:100%!important;margin:0 0 8px;padding:7px!important}.health{padding:0 14px 8px;color:#95afcb;font-size:12px}.heading strong{font-size:17px}.model{color:#95afcb;font-size:12px}.screen{height:180px;background:#070c13;position:relative;display:flex;align-items:center;justify-content:center}.screen img{max-width:100%;max-height:180px;object-fit:contain}.empty{position:absolute;color:#8b9bb0;text-align:center;padding:15px;pointer-events:none}.screen img:not([src]){display:none}.status{padding:8px 14px;color:#80d6cb;font-size:12px;min-height:32px}.controls{padding:0 14px 12px}.actions{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:9px}.remote{display:flex;gap:6px;flex-wrap:wrap}.remote button{min-width:36px;padding:6px 8px}details{border-top:1px solid #32445a;padding:9px 14px;color:#aabbd0}summary{cursor:pointer}pre{white-space:pre-wrap;font-size:11px;max-height:150px;overflow:auto;color:#c7d7e7}#notice{min-height:23px;color:#e8b77a;margin-bottom:8px}.footer{padding:14px 0;color:#8c9db4;font-size:12px}@media(max-width:650px){.grid{grid-template-columns:1fr}main,header{padding:16px}input[type=url]{min-width:220px}}
</style></head><body><header><h1>FTC Fire Stick Controller</h1><p>Seven displays · .100–104 E9L29Y · .105 K2R2TE · .106 M3N6RA</p></header><main>
<div class="bar"><label>Server <input id="server" type="url" value="http://192.168.86.37" aria-label="Display server"></label><label>Event code <input id="event" type="text" value="s0" aria-label="Event code"></label><label>Display type <select id="displayType"><option value="audience" selected>Audience</option><option value="field">Field</option><option value="pit">Pit</option><option value="sponsor">Sponsor</option><option value="cmpBar">Championship bar</option></select></label><button class="primary" id="setupAll">Set up selected</button><button id="connectAll">Reconnect selected</button><button id="mirrorAll">Open selected scrcpy</button></div>
<div class="bar"><label>Startup <select id="startup"><option value="monitor" selected>Monitor only</option><option value="setup">Set up assigned displays</option></select></label><label><input id="autoReconnect" type="checkbox" checked> Auto reconnect every 10s</label><button id="selectVisible">Select visible</button><button id="selectNone">Clear selection</button><button id="recoverAll">Recover selected</button></div><div class="bar"><label><input type="checkbox" id="live" checked> Live previews</label><label>Refresh <select id="interval"><option value="0">Realtime (as fast as available)</option><option value="2000" selected>2 seconds</option><option value="5000">5 seconds</option><option value="10000">10 seconds</option></select></label><label><input type="checkbox" id="mirror"> Open scrcpy during setup</label><button id="refresh">Refresh previews</button></div><div id="urlPreview" style="color:#95afcb;margin-bottom:10px;overflow-wrap:anywhere"></div><div id="notice"></div><div class="tray" id="tray" aria-label="Minimized devices"></div><div class="grid" id="grid"></div><div class="footer">Minimize unused devices with −; restore them from the tray. Group actions apply to selected visible devices. Preview refresh applies to visible devices. Startup preferences apply on the next controller launch; recovery uses each device’s last assigned URL. Leave the controller's Terminal window open. Closing a scrcpy window does not stop the display. Realtime requests the next screenshot as soon as the previous one finishes; actual speed depends on Wi-Fi and the stick. Open scrcpy for continuous video and live control.</div></main>
<script>
const token='__TOKEN__',devices=[100,101,102,103,104,105,106],pending=new Set(),timers=new Map();
const api=(path)=>path+(path.includes('?')?'&':'?')+'token='+encodeURIComponent(token);
function displayURL(){const base=document.getElementById('server').value.trim().replace(/\/+$/,'');const event=document.getElementById('event').value.trim();if(!event)throw new Error('Enter an event code');const server=new URL(base);if(!['http:','https:'].includes(server.protocol))throw new Error('Server must begin with http:// or https://');return base+'/event/'+encodeURIComponent(event)+'/display/?type='+encodeURIComponent(document.getElementById('displayType').value)}
function updateURLPreview(){try{document.getElementById('urlPreview').textContent=displayURL()}catch(e){document.getElementById('urlPreview').textContent=e.message}}
for(const id of ['server','event','displayType'])document.getElementById(id).addEventListener('input',updateURLPreview);updateURLPreview();
const minimized=new Set(),selected=new Set(devices),locations=new Map();
function visibleDevices(){return devices.filter(n=>!minimized.has(n))}
function selectedDevices(){return visibleDevices().filter(n=>selected.has(n))}
async function config(data){const r=await fetch(api('/config'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});const d=await r.json();if(!r.ok)throw Error(d.error);return d}
function renderTray(){const tray=document.getElementById('tray');tray.textContent='';for(const n of devices){document.getElementById('card'+n).hidden=minimized.has(n);if(minimized.has(n)){const b=document.createElement('button');b.textContent='Restore .'+n+(locations.get(n)?' · '+locations.get(n):'');b.onclick=()=>restore(n);tray.appendChild(b)}}}
function minimize(n){minimized.add(n);clearTimeout(timers.get(n));timers.delete(n);renderTray();config({n,minimized:true}).catch(report)}
function restore(n){minimized.delete(n);renderTray();config({n,minimized:false}).catch(report);screen(n)}
function report(e){document.getElementById('notice').textContent=String(e)}

for(const n of devices){const model=n===105?'K2R2TE':n===106?'M3N6RA':'E9L29Y';const card=document.createElement('section');card.className='card';card.id='card'+n;card.innerHTML=`<div class="heading"><strong><input id="select${n}" type="checkbox" checked aria-label="Select device ${n}"> 192.168.86.${n}</strong><span><span class="model">${model}</span><button data-minimize="true" title="Minimize this device">−</button></span></div><div class="screen"><img id="img${n}" alt="Screen preview for ${n}"><span class="empty" id="empty${n}">Connecting…</span></div><div class="status" id="status${n}">Connecting</div><div class="health" id="health${n}">Checking connection</div><div class="controls"><input class="location" id="location${n}" type="text" placeholder="Location e.g. Main gym audience" aria-label="Device location"><label><input id="restore${n}" type="checkbox"> Restore assigned display after reconnect</label><div class="actions" style="margin-top:10px"><button class="primary" data-action="setup">Set up display</button><button data-action="mirror">Open scrcpy</button><button data-action="connect">Reconnect</button><button data-action="recover">Recover display</button></div><div class="remote">${[['Wake',224],['Home',3],['Back',4],['Menu',82],['↑',19],['←',21],['OK',23],['→',22],['↓',20]].map(([label,key])=>`<button data-key="${key}">${label}</button>`).join('')}</div></div><details><summary>Activity log</summary><pre id="log${n}"></pre></details>`;card.addEventListener('click',e=>{const b=e.target.closest('button');if(b){if(b.dataset.minimize)minimize(n);else act(n,b.dataset.action||'key',b.dataset.key?Number(b.dataset.key):null)}});document.getElementById('grid').appendChild(card);document.getElementById('select'+n).onchange=e=>{e.target.checked?selected.add(n):selected.delete(n);config({n,selected:e.target.checked}).catch(report)};document.getElementById('location'+n).onchange=e=>{locations.set(n,e.target.value);renderTray();config({n,location:e.target.value}).catch(report)};document.getElementById('restore'+n).onchange=e=>config({n,auto_restore:e.target.checked}).catch(report)}
async function act(n,action,key=null){let url='';if(action==='setup'){try{url=displayURL()}catch(e){document.getElementById('notice').textContent=e.message;return}}try{const r=await fetch(api('/action'),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({n,action,key,url,mirror:document.getElementById('mirror').checked})});const d=await r.json();if(!r.ok)throw new Error(d.error);document.getElementById('notice').textContent=d.message;poll()}catch(e){document.getElementById('notice').textContent=String(e)}}
for(const [id,action] of [['setupAll','setup'],['connectAll','connect'],['mirrorAll','mirror'],['recoverAll','recover']])document.getElementById(id).onclick=()=>selectedDevices().forEach(n=>act(n,action));
let initialized=false;
async function poll(){try{const r=await fetch(api('/state'));if(!r.ok)throw Error('State unavailable');const state=await r.json();if(!initialized){document.getElementById('startup').value=state.options.startup;document.getElementById('autoReconnect').checked=state.options.auto_reconnect;for(const d of state.devices){if(d.minimized)minimized.add(d.n);d.selected?selected.add(d.n):selected.delete(d.n);document.getElementById('select'+d.n).checked=d.selected;document.getElementById('location'+d.n).value=d.location;locations.set(d.n,d.location);document.getElementById('restore'+d.n).checked=d.auto_restore}renderTray();initialized=true;await fetch(api('/startup'),{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});refresh()}for(const d of state.devices){document.getElementById('status'+d.n).textContent=d.status+(d.busy?' · Working…':'');document.getElementById('log'+d.n).textContent=d.logs.join('\n');const age=d.last_preview?Math.max(0,Math.floor(Date.now()/1000-d.last_preview)):null;const health=document.getElementById('health'+d.n);health.textContent=d.health.toUpperCase()+' · '+(age===null?'No preview yet':'Last preview '+age+'s ago'+(age>Math.max(15,Number(document.getElementById('interval').value)/1000*3)?' · STALE':''));health.style.color=d.health==='connected'?'#80d6cb':d.health==='unauthorized'?'#e8b77a':'#f29a9a';document.querySelectorAll('#card'+d.n+' button').forEach(b=>b.disabled=b.dataset.minimize?false:d.busy)}}catch(e){document.getElementById('notice').textContent='Controller unavailable: '+e.message}}

async function screen(n){if(minimized.has(n)||pending.has(n))return;clearTimeout(timers.get(n));pending.add(n);const started=Date.now();try{const r=await fetch(api('/screen?n='+n));if(!r.ok)throw new Error(await r.text());const blob=await r.blob(),img=document.getElementById('img'+n),old=img.dataset.object;const object=URL.createObjectURL(blob);img.src=object;img.dataset.object=object;if(old)URL.revokeObjectURL(old);document.getElementById('empty'+n).textContent='';img.style.opacity='1'}catch(e){document.getElementById('empty'+n).textContent='Preview unavailable · reconnect or authorize ADB';document.getElementById('img'+n).style.opacity='.2'}finally{pending.delete(n);if(!minimized.has(n)&&document.getElementById('live').checked){const interval=Number(document.getElementById('interval').value);timers.set(n,setTimeout(()=>screen(n),Math.max(100,interval-(Date.now()-started))))}}}
function refresh(){visibleDevices().forEach(screen)}document.getElementById('refresh').onclick=refresh;
function restartPreviews(){for(const timer of timers.values())clearTimeout(timer);timers.clear();if(document.getElementById('live').checked)refresh()}
document.getElementById('live').onchange=restartPreviews;document.getElementById('interval').onchange=restartPreviews;
document.getElementById('startup').onchange=e=>config({startup:e.target.value}).catch(report);
document.getElementById('autoReconnect').onchange=e=>config({auto_reconnect:e.target.checked}).catch(report);
for(const [id,on] of [['selectVisible',true],['selectNone',false]])document.getElementById(id).onclick=()=>visibleDevices().forEach(n=>{on?selected.add(n):selected.delete(n);document.getElementById('select'+n).checked=on;config({n,selected:on}).catch(report)});
renderTray();setInterval(poll,1500);poll();
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
            return self.respond(200, state_data())
        if route == '/screen':
            try:
                n = int(parse_qs(urlparse(self.path).query)['n'][0])
                if n not in DEVICES: raise ValueError('Unknown device')
                with DEVICES[n]['screen_lock']:
                    data = call(['-s', serial(n), 'exec-out', 'screencap', '-p'], timeout=8)
                if not data.startswith(b'\x89PNG\r\n\x1a\n'): raise RuntimeError('No screenshot received')
                with STATE_LOCK: DEVICES[n]['last_preview'] = time.time()
                return self.respond(200, data, 'image/png')
            except Exception as exc: return self.respond(503, str(exc), 'text/plain')
        self.respond(404, {'error':'Not found'})
    def do_POST(self):
        if not self.authorized(): return self.respond(403, {'error':'Unauthorized'})
        if urlparse(self.path).path not in ('/action','/config','/startup'): return self.respond(404, {'error':'Not found'})
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 8192: raise ValueError('Invalid request size')
            data = json.loads(self.rfile.read(length))
            if urlparse(self.path).path == '/startup':
                startup_once()
                return self.respond(200, {'message':'Startup behavior applied once for this controller session.'})
            if urlparse(self.path).path == '/config':
                with STATE_LOCK:
                    if 'startup' in data:
                        if data['startup'] not in ('monitor','setup'): raise ValueError('Invalid startup mode')
                        OPTIONS['startup'] = data['startup']
                    if 'auto_reconnect' in data: OPTIONS['auto_reconnect'] = bool(data['auto_reconnect'])
                    if 'n' in data:
                        n = int(data['n'])
                        if n not in DEVICES: raise ValueError('Unknown device')
                        if 'location' in data: DEVICES[n]['location'] = str(data['location'])[:80]
                        for k in ('minimized','selected','auto_restore'):
                            if k in data: DEVICES[n][k] = bool(data[k])
                save_config()
                return self.respond(200, {'message':'Preferences saved'})
            n = int(data['n']); action = data['action']
            if n not in DEVICES or action not in ('setup','recover','connect','mirror','key'): raise ValueError('Unknown action or device')
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
    threading.Thread(target=monitor_connections, daemon=True).start()
    webbrowser.open(address)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        STOP.set()
        server.server_close()
        POOL.shutdown(wait=False)
PY
