import urllib.request, json
auth = open(r'D:\Develop\wewe-rss\apps\server\.env.local', encoding='utf-8').read()
auth = __import__('re').search(r'^AUTH_CODE=(.+)$', auth, __import__('re').MULTILINE).group(1).strip()
req = urllib.request.Request('http://localhost:4000/trpc/platform.createLoginUrl', data=b'{}', headers={'Content-Type':'application/json','Authorization':auth}, method='POST')
with urllib.request.urlopen(req, timeout=30) as r:
    data = json.loads(r.read().decode('utf-8'))
res = data.get('result', {})
inner = res.get('data', res) if isinstance(res, dict) else res
print('UUID=' + str(inner.get('uuid','')))
print('SCANURL=' + str(inner.get('scanUrl','')))
