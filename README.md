# Nanobot on Android (Termux + Debian)

Install [Nanobot](https://pypi.org/project/nanobot-ai/) in **proot Debian** on **ARM64 Termux**, plus boot/loop scripts for a Telegram gateway on your phone.

Based on the [setup write-up](https://github.com/gianfrancodemarco/site/blob/main/content/posts/nanobot-android-termux.md) (paths may vary).

## Prerequisites

- **ARM64 Termux** (`uname -m` and `dpkg --print-architecture` → `aarch64`)
- Network on the device

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
6. **Interactive (tmux):** prompts for **OpenAI API key**, **Telegram bot token**, optional **chat model** (default `gpt-4.1-mini`) and **Whisper language** (default `it`), then patches config (mode `600`)  
7. Installs `~/bin/nanobot-loop` and `~/.termux/boot/00-start-nanobot`

Secrets stay on the device; only the example config is in git. Non-interactive runs (`curl | bash`) skip prompts — edit config in Debian afterward.

## Layout

| Path | Role |
| --- | --- |
| `setup.sh` | Full install (Termux + Debian) |
| `config/config.json.example` | Template for `/root/.nanobot/config.json` |
| `scripts/nanobot-loop` | Gateway restart loop (Termux) |
| `scripts/00-start-nanobot` | Termux:Boot entry |

## After install

- Whitelist **Termux** in battery / background settings.  
- Install **Termux:Boot** and launch it once.  
- Edit config inside Debian: `proot-distro login debian` → `/root/.nanobot/config.json`  
- Test: `tmux new -s nanobot-host ~/bin/nanobot-loop` → `tail -f ~/nanobot-logs/gateway.log`

## License

MIT — see [LICENSE](LICENSE).
