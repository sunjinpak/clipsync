#!/usr/bin/env python3
"""clipsync hub (runs on one always-on Mac). Holds only the latest copied text
in memory, never on disk or in logs. Accepts Tailscale (100.64.0.0/10) and
localhost only, plus a shared token. Also serves the one-line client installer:
  curl -fsS "http://<hub-tailscale-ip>:8377/install?t=TOKEN" | bash
"""
import ipaddress, json, os, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN = open(os.path.expanduser('~/.config/clipsync/token')).read().strip()
TAILNET = ipaddress.ip_network('100.64.0.0/10')
# ids start at the clock so a hub restart never goes below ids clients already saw
state = {'id': int(time.time()), 'text': '', 'from': ''}
cond = threading.Condition()


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):  # never log clipboard traffic
        pass

    def send(self, code, obj=None, raw=None, ctype='application/json'):
        body = raw if raw is not None else (json.dumps(obj).encode() if obj is not None else b'')
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def ok(self, q={}):
        ip = ipaddress.ip_address(self.client_address[0])
        if not (ip.is_loopback or ip in TAILNET):
            return False
        return (self.headers.get('X-Token') or q.get('t', [''])[0]) == TOKEN

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self.ok(q):
            return self.send(403)
        if u.path == '/id':
            return self.send(200, {'id': state['id']})
        if u.path == '/wait':
            since = int(q.get('since', ['0'])[0])
            with cond:
                cond.wait_for(lambda: state['id'] > since and state['text'], timeout=30)
                snap = dict(state)
            return self.send(200, snap) if snap['id'] > since and snap['text'] else self.send(204)
        if u.path == '/install':
            sh = (open(os.path.join(HERE, 'install.sh')).read().replace('__TOKEN__', TOKEN)
                  .replace('__HUB__', 'http://' + self.headers.get('Host', '')))
            return self.send(200, raw=sh.encode(), ctype='text/plain')
        if u.path == '/bin':
            return self.send(200, raw=open(os.path.join(HERE, 'clipsync'), 'rb').read(),
                             ctype='application/octet-stream')
        self.send(404)

    def do_POST(self):
        if not self.ok() or urlparse(self.path).path != '/push':
            return self.send(403)
        d = json.loads(self.rfile.read(int(self.headers.get('Content-Length', 0))) or b'{}')
        text = d.get('text', '')
        with cond:
            if text and text != state['text']:
                state.update(id=state['id'] + 1, text=text, **{'from': d.get('from', '')})
                cond.notify_all()
            sid = state['id']
        self.send(200, {'id': sid})


ThreadingHTTPServer.daemon_threads = True
ThreadingHTTPServer(('0.0.0.0', int(os.environ.get('CLIPSYNC_PORT', 8377))), H).serve_forever()
