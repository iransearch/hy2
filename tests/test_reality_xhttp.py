"""Real-core integration: XRAY_BINARY=/path/to/xray python3 tests/test_reality_xhttp.py.
Uses only temporary files, loopback listeners and an isolated test CA. No systemd,
root certificate store, installed services or repository credentials are changed.
"""
import contextlib, http.server, json, os, pathlib, re, socket, subprocess, tempfile, threading, time
from urllib.parse import urlsplit, parse_qs

ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = os.environ.get('XRAY_BINARY', '/tmp/gecko-xray/xray')
SCRIPT = (ROOT / 'GECKO.sh').read_text()

def run(*args, **kw):
    return subprocess.run(args, check=True, text=True, capture_output=True, **kw).stdout

def freeport():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0)); return s.getsockname()[1]

def definitions():
    result=SCRIPT.split('# BEGIN GECKO REALITY XHTTP PAIRS\n',1)[1].split('# END GECKO REALITY XHTTP PAIRS',1)[0]
    for name in ['gecko_warp_apply_xray_json', 'reality_run_vlessenc', 'reality_generate_vless_encryption_pair']:
        result += '\n' + re.search(r'^'+name+r'\(\) \{.*?^\}', SCRIPT, re.M|re.S)[0]+'\n'
    return result + '\nanytls_valid_id() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$ ]]; }\ngecko_warp_is_enabled() { return 1; }\ntui_error() { echo "$*" >&2; }\n'

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(b'gecko-pair-traffic-ok')
    def log_message(self,*args): pass

@contextlib.contextmanager
def core(config, directory, env):
    with open(directory / (config.stem+'.log'), 'w+') as log:
        p=subprocess.Popen([CORE,'run','-c',str(config)],stdout=log,stderr=log,env=env)
        try:
            time.sleep(.5)
            if p.poll() is not None:
                log.seek(0); raise AssertionError(log.read())
            yield p
        finally:
            p.terminate()
            try: p.wait(timeout=5)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
            log.seek(0)
            if os.environ.get('RX_DEBUG'): print(log.read())

with tempfile.TemporaryDirectory(prefix='gecko-rx-test-') as folder:
    d=pathlib.Path(folder)
    run('openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(d/'ca.key'),'-out',str(d/'ca.pem'),'-days','2','-subj','/CN=GECKO test CA')
    run('openssl','req','-newkey','rsa:2048','-nodes','-keyout',str(d/'server.key'),'-out',str(d/'server.csr'),'-subj','/CN=pair.example.test')
    (d/'ext').write_text('subjectAltName=DNS:pair.example.test\nextendedKeyUsage=serverAuth\n')
    run('openssl','x509','-req','-in',str(d/'server.csr'),'-CA',str(d/'ca.pem'),'-CAkey',str(d/'ca.key'),'-CAcreateserial','-out',str(d/'server.pem'),'-days','2','-extfile',str(d/'ext'))
    env=dict(os.environ,SSL_CERT_FILE=str(d/'ca.pem'))
    harness=d/'functions.sh';harness.write_text(definitions())
    def bash(code): return run('bash','-c','source "$1"\n'+code,'test',str(harness),env=env)
    keys=run(CORE,'x25519')
    private=re.search(r'PrivateKey: (.+)',keys)[1]
    public=re.search(r'(?:Password \(PublicKey\)|PublicKey): (.+)',keys)[1]
    m=dict(id='test',address='127.0.0.1',domain='pair.example.test',port=freeport(),backend_port=freeport(),path='/news',
           cert=str(d/'server.pem'),key=str(d/'server.key'),private_key=private,public_key=public,short_id='aabbccdd',
           users=[dict(name='alice',id=run(CORE,'uuid').strip()),dict(name='bob',id=run(CORE,'uuid').strip())])
    meta=d/'meta.json';meta.write_text(json.dumps(m))
    http=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    thread=threading.Thread(target=http.serve_forever,daemon=True);thread.start()
    try:
        for mode in ['none','mlkem768']:
            out=d/mode;out.mkdir()
            bash(f'rx_generate_encryption "{meta}" "{CORE}" {mode} && rx_validate "{meta}" "{out}" "{CORE}"')
            mm=json.loads(meta.read_text()); server=json.loads((out/'config.json').read_text())
            assert server['inbounds'][1]['listen']=='127.0.0.1'
            assert server['inbounds'][0]['streamSettings']['realitySettings']['target']==f"127.0.0.1:{m['backend_port']}"
            links=(out/'links.txt').read_text().splitlines();assert len(links)==4
            for link in links:
                q=parse_qs(urlsplit(link).query)
                assert q['encryption'][0]==mm[('reality' if q['security']==['reality'] else 'xhttp')+'_encryption']
            with core(out/'config.json',out,env):
                for kind in ['reality','xhttp']:
                    path=out/('alice-'+kind+'.json'); c=json.loads(path.read_text()); socks=freeport();c['inbounds'][0]['port']=socks;path.write_text(json.dumps(c))
                    with core(path,out,env):
                        response=run('curl','--noproxy','','--socks5-hostname',f'127.0.0.1:{socks}','--max-time','12','-fsS',f'http://127.0.0.1:{http.server_port}/',env=env)
                        assert response=='gecko-pair-traffic-ok',(mode,kind,response)
                    print('PASS real traffic:',mode,kind)
        # Transaction failures restore all generated files; stopped services stay stopped.
        lifecycle = d/'lifecycle.sh'
        lifecycle.write_text(r'''set -e
RX_ROOT="$2/pairs"
# Capture the test core path without overriding production variables.
TEST_CORE="$3"
rx_bin() { printf '%s' "$TEST_CORE"; }
mkdir -p "$RX_ROOT/test"
cp "$2/meta.json" "$RX_ROOT/test/meta.json"
rx_build "$RX_ROOT/test/meta.json" "$RX_ROOT/test"
cp -a "$RX_ROOT/test" "$2/before"
jq '.path="/changed"' "$2/meta.json" >"$2/changed.json"
STATE_DIR="$2"
systemctl() {
  case "$1" in
    is-active) return 0 ;;
    restart)
      if [[ ! -f "$STATE_DIR/failed-once" ]]; then touch "$STATE_DIR/failed-once"; return 1; fi
      return 0 ;;
    *) return 0 ;;
  esac
}
if rx_commit test "$2/changed.json"; then echo 'Expected activation failure' >&2; exit 1; fi
diff -r "$2/before" "$RX_ROOT/test"
systemctl() {
  case "$1" in
    is-active) return 1 ;;
    restart|start) echo 'Stopped service unexpectedly started' >&2; return 1 ;;
    *) return 0 ;;
  esac
}
jq '.users |= map(select(.name!="bob"))' "$2/meta.json" >"$2/changed.json"
rx_commit test "$2/changed.json"
[[ ! -e "$RX_ROOT/test/bob-reality.json" && ! -e "$RX_ROOT/test/bob-xhttp.json" ]]
[[ $(wc -l <"$RX_ROOT/test/links.txt") == 2 ]]
''')
        run('bash','-c','source "$1"; source "$2/lifecycle.sh"','test',str(harness),str(d),CORE,env=env)
        print('PASS rollback, inactive service preservation and stale user export removal')
        # Both WARP modes and IPv6 URIs are generated from the same pair metadata.
        extra=d/'extra';extra.mkdir()
        extra_meta=d/'extra.json'; em=json.loads(meta.read_text());em['address']='2001:db8::1';extra_meta.write_text(json.dumps(em))
        bash(f'rx_build "{extra_meta}" "{extra}"')
        assert urlsplit((extra/'links.txt').read_text().splitlines()[0]).hostname=='2001:db8::1'
        for mode in ['selective','all']:
            bash(f'''gecko_warp_is_enabled() {{ return 0; }}
gecko_warp_proxy_port() {{ echo 40000; }}
gecko_warp_mode() {{ echo {mode}; }}
gecko_warp_domain_sets_json() {{ echo '{{"exact":[],"suffix":["example.com"]}}'; }}
rx_build "{meta}" "{extra}"
"{CORE}" run -test -c "{extra}/config.json"''')
            cfg=json.loads((extra/'config.json').read_text());assert cfg['routing']['rules'][0]['outboundTag']=='warp'
            if mode=='all': assert cfg['routing']['rules'][0]['network']=='tcp,udp'
        print('PASS IPv6 exports and selective/all WARP configuration')
        # An invalid certificate/domain must be rejected, not silently insecure.
        wrong=json.loads(meta.read_text());wrong['domain']='wrong.example.test';meta.write_text(json.dumps(wrong))
        try: bash(f'rx_certificate_check "{meta}"')
        except subprocess.CalledProcessError: print('PASS certificate hostname rejection')
        else: raise AssertionError('invalid hostname accepted')
    finally: http.shutdown();http.server_close()
print('All integration checks passed.')
