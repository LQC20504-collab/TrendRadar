import urllib.request, urllib.parse, json, time, qrcode, os, re, sys

LOG = r'D:\Develop\TrendRadar\login.log'

def log(msg):
    line = time.strftime('%H:%M:%S') + ' ' + msg
    with open(LOG, 'a', encoding='utf-8') as f:
        f.write(line + '\n')
    print(line, flush=True)

def get_auth():
    return re.search(r'^AUTH_CODE=(.+)$', open(r'D:\Develop\wewe-rss\apps\server\.env.local', encoding='utf-8').read(), re.MULTILINE).group(1).strip()

def create_qr(a):
    """生成一个新的登录二维码并立即弹窗，返回 (uuid, scanurl)。"""
    req = urllib.request.Request('http://localhost:4000/trpc/platform.createLoginUrl', data=b'{}',
                                 headers={'Content-Type': 'application/json', 'Authorization': a}, method='POST')
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode('utf-8'))
        res = data.get('result', {})
        inner = res.get('data', res) if isinstance(res, dict) else res
        uuid = str(inner.get('uuid', ''))
        scanurl = str(inner.get('scanUrl', ''))
        log('UUID=' + uuid)
        out = r'D:\Develop\TrendRadar\wewe-login-qr-' + uuid + '.png'
        qrcode.make(scanurl).save(out)
        # os.startfile(out)  # 已屏蔽：永不弹窗二维码，改为静默保存
        log('QR_SAVED: ' + out + ' (double-click to view if needed)')
        log('SCAN_URL: ' + scanurl)
        return uuid, scanurl

def get_result(a, uuid):
    url = 'http://localhost:4000/trpc/platform.getLoginResult?input=' + urllib.parse.quote(json.dumps({'id': uuid}))
    req = urllib.request.Request(url, headers={'Authorization': a})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read().decode('utf-8'))
    res = data.get('result', {})
    inner = res.get('data', res) if isinstance(res, dict) else res
    return inner

open(LOG, 'w', encoding='utf-8').close()

MAX_POLLS = 150          # 总轮询上限（约 150*3s = 7.5 分钟）
ERR_THRESHOLD = 3        # 连续失败几次后换一个新二维码
MAX_REGEN = 12           # 最多重新生成二维码次数（防止无限弹窗）

a = get_auth()
uuid, _ = create_qr(a)
consecutive_err = 0
regen_count = 0

for i in range(MAX_POLLS):
    try:
        inner = get_result(a, uuid)
        token = inner.get('token', '')
        vid = inner.get('vid', inner.get('id', ''))
        username = inner.get('username', '')
        if token:
            log('LOGIN_OK vid=' + str(vid) + ' username=' + str(username))
            log('TOKEN=' + str(token))
            # 自动持久化 token + status=1（account.edit 的 id 必须是字符串）
            body = json.dumps({'id': str(vid), 'data': {'token': token, 'status': 1}}).encode('utf-8')
            req2 = urllib.request.Request('http://localhost:4000/trpc/account.edit', data=body,
                                          headers={'Content-Type': 'application/json', 'Authorization': a}, method='POST')
            with urllib.request.urlopen(req2, timeout=30) as r2:
                d2 = json.loads(r2.read().decode('utf-8'))
            log('PERSIST_OK: ' + json.dumps(d2)[:300])
            sys.exit(0)
        log('poll %d: waiting' % (i + 1))
        consecutive_err = 0
    except Exception as e:
        log('poll %d: err %s' % (i + 1, e))
        consecutive_err += 1
        if consecutive_err >= ERR_THRESHOLD and regen_count < MAX_REGEN:
            regen_count += 1
            log('连续失败，重新生成二维码 (#%d)...' % regen_count)
            uuid, _ = create_qr(a)
            consecutive_err = 0
    time.sleep(3)

log('TIMEOUT')
