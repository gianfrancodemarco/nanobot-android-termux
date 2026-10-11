#!/bin/bash
set +e
source /root/nanobot-env/bin/activate 2>/dev/null
echo "nanobot: $(command -v nanobot 2>/dev/null || echo missing)"
nanobot --version 2>/dev/null || true
python3 --version 2>/dev/null || true
echo "--- curl api.telegram.org ---"
curl -fsS -o /dev/null -w "HTTP %{http_code}\n" --connect-timeout 15 https://api.telegram.org 2>&1 || echo "curl failed"
echo "--- getMe (ok/error only, token not printed) ---"
python3 <<'PY'
import json
import urllib.error
import urllib.request

path = "/root/.nanobot/config.json"
try:
    with open(path, encoding="utf-8") as f:
        cfg = json.load(f)
except OSError as e:
    print("config:", e)
    cfg = {}

token = (cfg.get("channels") or {}).get("telegram", {}).get("token") or ""
if not token or "PASTE" in token:
    print("telegram token: missing or placeholder")
else:
    url = f"https://api.telegram.org/bot{token}/getMe"
    try:
        with urllib.request.urlopen(url, timeout=15) as r:
            body = json.loads(r.read().decode())
        print("getMe ok:", body.get("ok"), "username:", (body.get("result") or {}).get("username"))
    except urllib.error.HTTPError as e:
        print("getMe HTTP", e.code)
    except Exception as e:
        print("getMe failed:", type(e).__name__, e)

print("--- config.json (redacted) ---")


def redact(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            lk = k.lower()
            if lk in ("apikey", "token", "password", "secret"):
                out[k] = "REDACTED" if v else v
            else:
                out[k] = redact(v)
        return out
    if isinstance(obj, list):
        return [redact(x) for x in obj]
    return obj


print(json.dumps(redact(cfg), indent=2))
PY
echo "--- /root/.nanobot/logs/gateway.log (last 60 lines) ---"
tail -n 60 /root/.nanobot/logs/gateway.log 2>/dev/null || echo "(no debian gateway.log)"
echo "--- pip show nanobot-ai ---"
pip show nanobot-ai 2>/dev/null | grep -E '^Name:|^Version:|^Location:' || true
echo "--- nanobot gateway quick test (5s timeout) ---"
timeout 5 nanobot gateway 2>&1 | tail -n 15 || echo "gateway test ended (rc=$?)"
