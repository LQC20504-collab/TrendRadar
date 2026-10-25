"""手动把微信读书 token 写回 wewe-rss 数据库（脚本化兜底，正常情况下用 login_and_persist.py）。

用法：
    python save_token.py <TOKEN> [VID]
    python save_token.py <TOKEN>          # VID 默认 936122071

token 从命令行传入，不写死在文件里 —— 避免把凭据提交进 git 仓库。
AUTH_CODE 仍从 wewe-rss 的 .env.local 读取（该文件不进版本库）。
"""

import json
import re
import sys
import urllib.request

ENV_LOCAL = r"D:\Develop\wewe-rss\apps\server\.env.local"
DEFAULT_VID = "936122071"
TRPC = "http://localhost:4000/trpc/account.edit"


def get_auth():
    text = open(ENV_LOCAL, encoding="utf-8").read()
    m = re.search(r"^AUTH_CODE=(.+)$", text, re.MULTILINE)
    if not m:
        sys.exit("ERROR: 未在 .env.local 中找到 AUTH_CODE")
    return m.group(1).strip()


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    token = sys.argv[1].strip()
    vid = sys.argv[2].strip() if len(sys.argv) > 2 else DEFAULT_VID

    body = json.dumps({"id": vid, "data": {"token": token, "status": 1}}).encode("utf-8")
    req = urllib.request.Request(
        TRPC,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": get_auth()},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print("PERSIST_OK:", json.dumps(json.loads(r.read().decode("utf-8")))[:500])
    except Exception as e:
        print("PERSIST_ERR:", e)
        try:
            print(e.read().decode("utf-8")[:500])
        except Exception:
            pass
        sys.exit(1)


if __name__ == "__main__":
    main()
