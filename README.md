# Nanobot on Android (Termux + Debian)

Install [Nanobot](https://pypi.org/project/nanobot-ai/) in **proot Debian** on **ARM64 Termux**, with boot and loop scripts for a Telegram gateway on your phone.

Based on the [setup write-up](https://github.com/gianfrancodemarco/site/blob/main/content/posts/nanobot-android-termux.md).

## Prerequisites

- **ARM64 Termux**: `uname -m` and `dpkg --print-architecture` both print `aarch64`.
- Network on the device.
- Two APKs from the **same release**, so the signing keys match (required for boot on Android 14+). The installer does not download them. Install Termux first, then Termux:Boot, and open each once.

| App | Asset |
| --- | --- |
| **Termux** (matching-key) | [`termux-app_matching-key_universal-debug.apk`](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-app_matching-key_universal-debug.apk) |
| **Termux:Boot** (boot-fix) | [`termux-boot-app_v0.8.1-boot-fix_debug.apk`](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-boot-app_v0.8.1-boot-fix_debug.apk) |

Release page: [oswaldlow/termux-boot v0.8.1-boot-fix](https://github.com/oswaldlow/termux-boot/releases/tag/v0.8.1-boot-fix). The official [termux-app v0.119.0-beta.3](https://github.com/termux/termux-app/releases/tag/v0.119.0-beta.3) arm64 build uses a different signing key, so use it only without the boot-fix Termux:Boot.

## Install

Run these as two separate blocks. Pasting `tmux new` together with other commands sends the rest of the paste into tmux.

```bash
pkg update -y && pkg install -y git tmux
tmux new -s setup
```

Then, inside tmux:

```bash
git clone https://github.com/gianfrancodemarco/nanobot-android-termux.git
cd nanobot-android-termux
./setup.sh
```

Setup prompts for your **OpenAI API key** and **Telegram bot token** (hidden input). It applies the defaults `gpt-4.1-mini` and Whisper language `it`. Non-interactive runs skip the prompts, so edit `/root/.nanobot/config.json` in Debian afterwards. Secrets stay on the device.

### Options

Set these before `./setup.sh`:

| Variable | Effect |
| --- | --- |
| `NANOBOT_DISTRO=nanobot` | Install a second Debian rootfs under that alias and leave an existing `debian` untouched. Default is `debian`. |
| `NANOBOT_SOURCE_URL=<url>` | Install nanobot from a source tarball (`pip install -e`) instead of PyPI. The URL is saved to `~/.nanobot-source-url`. |
| `NANOBOT_RECREATE_VENV=1` | Delete and recreate `/root/nanobot-env`. |

To update an install from a tarball, re-publish it at the same URL and run `update-nanobot-src`. It reinstalls the source and restarts the gateway.

## What `setup.sh` does

1. Checks for aarch64 Termux.
2. Installs `proot-distro`, `tmux`, `git` and `curl`.
3. Installs the Debian rootfs if missing.
4. Creates `/root/nanobot-env` and installs nanobot, pinning `cryptography<47` (see Troubleshooting).
5. Copies `config/config.json.example` to `/root/.nanobot/config.json` if none exists.
6. Prompts for the API key and bot token.
7. Installs the scripts in `~/bin` and the Termux:Boot entry.
8. Logs every step to `~/nanobot-logs/setup.log`.

| Script | Role |
| --- | --- |
| `scripts/nanobot-loop` | Gateway restart loop |
| `scripts/start-nanobot-host` | Start or restart the tmux session and attach |
| `scripts/00-start-nanobot` | Termux:Boot entry |
| `scripts/update-nanobot-src` | Re-pull the source tarball and restart the gateway |
| `scripts/debug-gateway` | Run the gateway in the foreground with checks |
| `scripts/collect-nanobot-logs` | Write a shareable, redacted log bundle |

## After install

- Allow Termux to run in the background in your battery settings.
- Start the gateway with `~/bin/start-nanobot-host`. Detach with Ctrl+B then D.
- After a reboot, Termux:Boot starts the gateway in the `nanobot-host` tmux session by itself. Check `~/nanobot-logs/boot.log`.
- Logs: `~/nanobot-logs/gateway.log`, `setup.log` and `boot.log`.
- Config: `proot-distro login debian`, then `/root/.nanobot/config.json`. Use your alias instead of `debian` if you set `NANOBOT_DISTRO`.

## Troubleshooting

If `gateway.log` shows *Registered 23 tools* and then the gateway exits every ~10s:

1. Run `~/bin/debug-gateway` and watch for errors after startup.
2. In Debian, read `/root/.nanobot/logs/gateway.log`. It often has Telegram or API errors.
3. Check the token: `curl -s "https://api.telegram.org/bot<TOKEN>/getMe"` should return `"ok":true`.
4. **`rc=132` (SIGILL)** is usually a native wheel that crashes under proot. The known case is `cryptography` 50.x, which setup pins below 47. On an older install, run `pip install "cryptography<47"` in `/root/nanobot-env`. For another culprit, run `python -c "import <module>"` per dependency in Debian and see which one dies.
5. `proot info: vpid 1: terminated with signal 4` appears when the proot session ends. Look at the lines above it for why the gateway exited.

If proot misbehaves, run `pkg upgrade -y proot proot-distro` from a plain Termux shell, not from inside `setup.sh`.

For a shareable report, optionally stop the loop first, then collect the logs. Config keys and tokens are redacted.

```bash
tmux kill-session -t nanobot-host 2>/dev/null
~/bin/collect-nanobot-logs
```

The report is written to `~/nanobot-logs/debug-report-YYYYMMDD-HHMMSS.txt`.

## License

MIT, see [LICENSE](LICENSE).
