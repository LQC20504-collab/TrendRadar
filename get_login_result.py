import urllib.request, urllib.parse, json, time
auth = open(r'D:\Develop\wewe-rss\apps\server\.env.local', encoding='utf-8').read()
auth = __import__('re').search(r'^AUTH_CODE=(.+)$', auth, __import__('re').MULTILINE).group(1).strip()
uuid = '031bGQ5C1Lna0005'
for i in range(30):
    url = 'http://localhost:4000/trpc/platform.getLoginResult?input=' + urllib.parse.quote(json.dumps({'id': uuid}))
    req = urllib.request.Request(url, headers={'Authorization': auth})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode('utf-8'))
    res = data.get('result', {})
    inner = res.get('data', res) if isinstance(res, dict) else res
    token = inner.get('token', '')
    vid = inner.get('vid', inner.get('id', ''))
    username = inner.get('username', '')
    status = inner.get('status', '')
    if token:
        print(f'LOGIN_OK uuid={uuid}')
        print(f'VID={vid}')
        print(f'USERNAME={username}')
        print(f'TOKEN={token}')
        print(f'STATUS={status}')
        break
    print(f'attempt {i+1}: status={status}, waiting...')
    time.sleep(5)
else:
    print('TIMEOUT')
