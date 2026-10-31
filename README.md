# 🤖📱 Nanobot on Android

![Android](https://img.shields.io/badge/Android-ARM64-3DDC84?logo=android&logoColor=white)
![Termux](https://img.shields.io/badge/Termux-proot%20Debian-000000?logo=gnubash&logoColor=white)
![Telegram](https://img.shields.io/badge/Telegram-gateway-26A5E4?logo=telegram&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

Run [Nanobot](https://pypi.org/project/nanobot-ai/) as a Telegram bot on your phone. It runs 24/7 and starts again by itself after a reboot.

📝 Full story: [the setup write-up](https://github.com/gianfrancodemarco/site/blob/main/content/posts/nanobot-android-termux.md)

```mermaid
flowchart TB
    you(["👤 You"]) <-->|chat| tg["💬 Telegram"]

    subgraph phone["📱 Android phone · Termux"]
        boot["⚡ Termux:Boot<br/><small>on every reboot</small>"] -->|starts| loop["🔁 nanobot-loop<br/><small>tmux · nanobot-host</small>"]
        gw["🤖 nanobot gateway<br/><small>🐧 proot Debian · keys stay here</small>"]
        loop -->|runs & restarts| gw
    end

    tg <-->|Bot API| gw
    gw <-->|LLM + Whisper| ai["🧠 OpenAI"]

    classDef ext fill:#E8F4FD,stroke:#26A5E4,stroke-width:2px,color:#0B3D5C
    classDef ai fill:#F0EBFF,stroke:#7C5CFF,stroke-width:2px,color:#2E1A7A
    classDef host fill:#FFF4E5,stroke:#F59E0B,stroke-width:2px,color:#5C3A00
    classDef bot fill:#E7F8EE,stroke:#22A55A,stroke-width:2px,color:#0F4D2A
    class you,tg ext
    class ai ai
    class boot,loop host
    class gw bot

    style phone fill:transparent,stroke:#3DDC84,stroke-width:3px,stroke-dasharray:6 4
```

## 1️⃣ Install the apps

Install both APKs from the **same release**, so their signing keys match (Android 14+ needs this for boot). Install Termux first, then open each app once.

| App | Download |
| --- | --- |
| **Termux** | [termux-app_matching-key_universal-debug.apk](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-app_matching-key_universal-debug.apk) |
| **Termux:Boot** | [termux-boot-app_v0.8.1-boot-fix_debug.apk](https://github.com/oswaldlow/termux-boot/releases/download/v0.8.1-boot-fix/termux-boot-app_v0.8.1-boot-fix_debug.apk) |

> [!IMPORTANT]
> You need **64-bit** Termux: `uname -m` must print `aarch64`. Then allow Termux to run in the background in your battery settings.

## 2️⃣ Run the installer

In Termux:

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

> [!TIP]
> Paste the two blocks separately. Anything pasted after `tmux new` ends up inside tmux.

Setup asks for your 🔑 **OpenAI API key** and 🤖 **Telegram bot token**. Your secrets stay on the phone.

## 3️⃣ Start the bot

```bash
~/bin/nanobot-ctl start
```

That's it. After a reboot, Termux:Boot starts the bot by itself.

## 🧰 `nanobot-ctl`

One command controls everything. Open a new Termux session after setup and it's on your PATH.

| I want to… | Run |
| --- | --- |
| ▶️ Start or restart the bot | `nanobot-ctl start` |
| ⏹️ Stop it (all of it) | `nanobot-ctl stop` |
| 🟢 Check if it's running | `nanobot-ctl status` |
| 👀 Watch the logs | `nanobot-ctl logs` |
| 🖥️ See the live session | `nanobot-ctl attach` (leave with `Ctrl+B` then `D`) |
| ⬆️ Update nanobot | `nanobot-ctl update` |
| 🐞 See why it crashes | `nanobot-ctl debug` |
| ⚙️ Edit the config | `nanobot-ctl config`, then `nanobot-ctl start` |

> [!NOTE]
> `stop` kills every process running in Debian, including gateways you started by hand and any Debian shell you have open. Run `nanobot-ctl` from plain Termux, not from inside Debian.

## ⬆️ Updating

```bash
nanobot-ctl update
```

```mermaid
flowchart LR
    stop["⏹️ Stop every gateway"] --> up["📦 Upgrade nanobot-ai<br/><small>keeps cryptography&lt;47</small>"] --> start["▶️ Start the bot again"]

    classDef step fill:#FFF4E5,stroke:#F59E0B,stroke-width:2px,color:#5C3A00
    classDef done fill:#E7F8EE,stroke:#22A55A,stroke-width:2px,color:#0F4D2A
    class stop,up step
    class start done
```

It prints the current version and the new one. Your config and keys aren't touched.

To update **this repo's scripts**, run `git pull && ./setup.sh` in `~/nanobot-android-termux`. Setup keeps your config and keys.

## 🩺 Troubleshooting

<details>
<summary><b>The gateway restarts every ~10 seconds</b></summary>

1. Run `nanobot-ctl debug` and read the error.
2. Test the token: `curl -s "https://api.telegram.org/bot<TOKEN>/getMe"` should return `"ok":true`.

</details>

<details>
<summary><b><code>rc=132</code> (SIGILL)</b></summary>

A native package is crashing under proot. The known case is `cryptography` 50.x, which setup and `update` pin below 47.

Run `nanobot-ctl debug`. The crash dump's `site-packages/<package>/` lines name the package to pin.

</details>

<details>
<summary><b><code>Address already in use</code></b></summary>

Another gateway is still running. Run `nanobot-ctl stop`, then start again.

</details>

<details>
<summary><b>proot misbehaves</b></summary>

From plain Termux, run `pkg upgrade -y proot proot-distro`.

</details>

## 🔧 Advanced

<details>
<summary><b>What <code>setup.sh</code> does</b></summary>

1. Installs `proot-distro`, `tmux`, `git` and `curl` in Termux.
2. Installs Debian if it's missing.
3. Creates `/root/nanobot-env` and installs nanobot.
4. Writes `/root/.nanobot/config.json` from [the example](config/config.json.example) and asks for your keys. The defaults are model `gpt-4.1-mini` and Whisper language `it`.
5. Installs `nanobot-ctl` and the Termux:Boot entry.

It's safe to run again. Set `NANOBOT_RECREATE_VENV=1` to rebuild the Python environment from scratch. The log is in `~/nanobot-logs/setup.log`.

</details>

<details>
<summary><b>Files</b></summary>

| File | Role |
| --- | --- |
| `scripts/nanobot-ctl` | The control command |
| `scripts/nanobot-loop` | Keeps the gateway running, restarting it if it exits |
| `scripts/00-start-nanobot` | Termux:Boot entry |

Logs: `~/nanobot-logs/gateway.log` and `boot.log`.

</details>

## 📄 License

MIT, see [LICENSE](LICENSE).
