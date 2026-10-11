# Nanobot on Android (Termux + Debian)

Install [Nanobot](https://pypi.org/project/nanobot-ai/) in **proot Debian** on **ARM64 Termux**, plus boot/loop scripts for a Telegram gateway on your phone.

Based on the [setup write-up](https://github.com/gianfrancodemarco/site/blob/main/content/posts/nanobot-android-termux.md).

## Prerequisites

- **ARM64 Termux** (`uname -m` and `dpkg --print-architecture` → `aarch64`)
- Network on the device

### APKs (install before `setup.sh`)

The installer does **not** download APKs. Install **both** from the **same release** so signing keys match (required for boot on Android 14+ per the blog).

**Release page (pick assets on phone if a direct link 404s):**  
[oswaldlow/termux-boot — v0.8.1-boot-fix](https://github.com/oswaldlow/termux-boot/releases/tag/v0.8.1-boot-fix)

| Order | App | Asset filename | Direct download |
| ---: | --- | --- | --- |
| 1 | **Termux** (matching-key) | `termux-app_matching-key_universal-debug.apk` | [download](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-app_matching-key_universal-debug.apk) |
| 2 | **Termux:Boot** (boot-fix) | `termux-boot-app_v0.8.1-boot-fix_debug.apk` | [download](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-boot-app_v0.8.1-boot-fix_debug.apk) |

Open **Termux** once, then **Termux:Boot** once.

The blog also records the official **arm64** debug build `termux-app_v0.119.0-beta.3+apt-android-7-github-debug_arm64-v8a.apk` from [termux/termux-app v0.119.0-beta.3](https://github.com/termux/termux-app/releases/tag/v0.119.0-beta.3) — use that only if you are **not** using the boot-fix add-on (different signing key; boot scripts will not pair with matching-key Boot). Direct link: [arm64-v8a API 7 debug](https://github.com/termux/termux-app/releases/download/v0.119.0-beta.3/termux-app_v0.119.0-beta.3+apt-android-7-github-debug_arm64-v8a.apk).

## One-shot setup (tmux)

From a fresh Termux session:

```bash
pkg update && pkg install -y git tmux
tmux new -s setup
git clone https://github.com/gianfrancodemarco/nanobot-android-termux.git
cd nanobot-android-termux
chmod +x setup.sh
./setup.sh
```

Or without cloning first (script clones into `~/nanobot-android-termux`):

```bash
export NANOBOT_ANDROID_REPO='https://github.com/gianfrancodemarco/nanobot-android-termux.git'
curl -fsSL "$NANOBOT_ANDROID_REPO/raw/main/setup.sh" -o setup.sh
bash setup.sh
```

## What `setup.sh` does

1. Verifies **aarch64** Termux  
2. Installs `proot-distro`, `tmux`, `git`, `curl`  
3. Installs **Debian** rootfs if missing  
4. Creates `/root/nanobot-env`, installs **nanobot-ai** (and binary wheels for **rapidfuzz**)  
5. Copies `config/config.json.example` → `/root/.nanobot/config.json` if none exists  
6. **Interactive (tmux):** prompts only for **OpenAI API key** and **Telegram bot token** (hidden); chat model `gpt-4.1-mini` and Whisper language `it` are applied automatically  
7. Installs `~/bin/nanobot-loop` and `~/.termux/boot/00-start-nanobot`  
8. Writes a timestamped **STEP N/9** transcript to `~/nanobot-logs/setup.log` (banner per step + all command output via `tee`)

Secrets stay on the device; only the example config is in git. Non-interactive runs (`curl | bash`) skip key prompts — edit config in Debian afterward. Package installs use `-y` / non-interactive flags throughout.

## Layout

| Path | Role |
| --- | --- |
| `setup.sh` | Full install (Termux + Debian) |
| `config/config.json.example` | Template for `/root/.nanobot/config.json` |
| `scripts/nanobot-loop` | Gateway restart loop (Termux) |
| `scripts/start-nanobot-host` | Start/restart tmux session + attach |
| `scripts/00-start-nanobot` | Termux:Boot entry |

## Troubleshooting gateway restarts

If `gateway.log` shows *Starting nanobot gateway* → *Registered 23 tools* → exit every ~10s:

1. Run **`~/bin/debug-gateway`** (or `./scripts/debug-gateway`) and watch for errors after startup.  
2. Inside Debian: **`tail -f /root/.nanobot/logs/gateway.log`** (Nanobot’s own log; often has Telegram/API errors).  
3. Confirm token: in Debian, `curl -s "https://api.telegram.org/bot<TOKEN>/getMe"` should return `"ok":true`.  
4. On the **emulator**, check internet/DNS; Telegram must reach `api.telegram.org`.  
5. **`gateway exit rc=132`** = **SIGILL** (illegal instruction). If **`getMe ok: True`** but the gateway still dies right after “Registered 23 tools”, config/Telegram are fine — the crash is usually **proot + emulator + Python 3.13 wheels**. Try a **physical phone**, or recreate the venv on **Python 3.12**: `NANOBOT_RECREATE_VENV=1 ./setup.sh` (after `git pull`). Emulator is still fine for testing the installer only.
6. `proot info: vpid 1: terminated with signal 4` often appears when the proot session ends; focus on **why `nanobot gateway` exits** (lines above it in the log).

Update Termux packages if proot misbehaves: `pkg upgrade -y proot proot-distro`.

**Shareable log bundle** (stops nothing; redacts API keys/tokens in config):

```bash
tmux kill-session -t nanobot-host 2>/dev/null   # optional: stop the loop first
~/bin/collect-nanobot-logs
```

Output: `~/nanobot-logs/debug-report-YYYYMMDD-HHMMSS.txt` — paste or send that file.

## After install

- Whitelist **Termux** in battery / background settings.  
- **Termux:Boot** APK must be installed and opened once (see APK table above).  
- Edit config inside Debian: `proot-distro login debian` → `/root/.nanobot/config.json`  
- Test: `~/bin/start-nanobot-host` or `./start-nanobot-host` from the cloned repo (after `source ~/.bashrc`, plain `start-nanobot-host` works too)  
- Installer trace: `tail -f ~/nanobot-logs/setup.log`

## License

MIT — see [LICENSE](LICENSE).
