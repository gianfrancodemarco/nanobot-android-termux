#!/data/data/com.termux/files/usr/bin/bash
# Nanobot on Android: Termux + proot Debian. Run from Termux (tmux is fine).
set -euo pipefail

# Override before curl|bash if your clone URL differs:
DEFAULT_REPO="${NANOBOT_ANDROID_REPO:-https://github.com/gianfrancodemarco/nanobot-android-termux.git}"
INSTALL_DIR="${NANOBOT_ANDROID_DIR:-$HOME/nanobot-android-termux}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

script_dir() {
  if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
  else
    echo "$INSTALL_DIR"
  fi
}

ensure_repo_files() {
  local dir
  dir="$(script_dir)"
  if [[ -f "$dir/config/config.json.example" && -f "$dir/scripts/nanobot-loop" ]]; then
    INSTALL_DIR="$dir"
    return 0
  fi
  log "Fetching repo into $INSTALL_DIR"
  command -v git >/dev/null 2>&1 || pkg install -y git
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    git -C "$INSTALL_DIR" pull --ff-only || true
  else
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 "$DEFAULT_REPO" "$INSTALL_DIR"
  fi
  [[ -f "$INSTALL_DIR/config/config.json.example" ]] || die "clone failed or repo layout changed"
}

check_termux_arch() {
  local m a
  m="$(uname -m)"
  a="$(dpkg --print-architecture 2>/dev/null || echo unknown)"
  log "Termux: uname -m=$m dpkg arch=$a"
  if [[ "$m" != "aarch64" || "$a" != "aarch64" ]]; then
    die "Need 64-bit Termux (aarch64). Reinstall ARM64 Termux APK before continuing."
  fi
}

termux_bootstrap() {
  log "Termux packages"
  pkg update -y
  pkg upgrade -y
  pkg install -y proot-distro tmux git curl
}

ensure_debian() {
  if proot-distro list 2>/dev/null | grep -q '^debian$'; then
    log "Debian rootfs already installed"
    return 0
  fi
  log "Installing Debian via proot-distro (first time only)"
  proot-distro install debian
}

debian_setup() {
  log "Nanobot venv and packages inside Debian"
  proot-distro login debian -- /bin/bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 python3-venv python3-pip git curl build-essential

if [[ ! -d /root/nanobot-env ]]; then
  python3 -m venv /root/nanobot-env
fi
# shellcheck disable=SC1091
source /root/nanobot-env/bin/activate
python -m pip install -q --upgrade pip
python -m pip install -q --only-binary=:all: rapidfuzz
python -m pip install -q nanobot-ai
command -v nanobot >/dev/null
echo "nanobot: $(nanobot --version 2>/dev/null || nanobot --help 2>&1 | head -1)"
'
}

install_config_example() {
  local example="$1"
  proot-distro login debian -- /bin/bash -lc "
set -euo pipefail
mkdir -p /root/.nanobot
if [[ ! -f /root/.nanobot/config.json ]]; then
  cp '$example' /root/.nanobot/config.json
  echo 'Wrote /root/.nanobot/config.json from example — edit API keys and Telegram token.'
else
  echo 'Keeping existing /root/.nanobot/config.json'
fi
"
}

install_termux_scripts() {
  local repo="$1"
  log "Termux loop + boot scripts"
  mkdir -p "$HOME/bin" "$HOME/.termux/boot" "$HOME/nanobot-logs"
  install -m 700 "$repo/scripts/nanobot-loop" "$HOME/bin/nanobot-loop"
  install -m 700 "$repo/scripts/00-start-nanobot" "$HOME/.termux/boot/00-start-nanobot"
}

# OpenAI + Telegram + chat model + Whisper language (matches config/config.json.example).
configure_secrets() {
  if [[ ! -t 0 ]]; then
    log "Non-interactive: config.json unchanged — edit /root/.nanobot/config.json in Debian"
    return 0
  fi

  if proot-distro login debian -- /bin/bash -lc 'test -f /root/.nanobot/config.json'; then
    if ! proot-distro login debian -- /bin/bash -lc 'grep -q PASTE_YOUR_ /root/.nanobot/config.json 2>/dev/null'; then
      read -r -p "Config already has secrets. Re-enter OpenAI key and Telegram token? [y/N] " ans
      [[ "$ans" =~ ^[yY]$ ]] || {
        log "Keeping existing /root/.nanobot/config.json"
        return 0
      }
    fi
  fi

  log "Nanobot secrets (hidden input). Defaults: model gpt-4.1-mini, Whisper language it"

  proot-distro login debian -- /bin/bash -lc '
set -euo pipefail
CFG=/root/.nanobot/config.json
[[ -f "$CFG" ]] || { echo "missing $CFG" >&2; exit 1; }

OPENAI_KEY=""
while [[ -z "$OPENAI_KEY" ]]; do
  read -r -s -p "OpenAI API key: " OPENAI_KEY
  echo
done

TELEGRAM_TOKEN=""
while [[ -z "$TELEGRAM_TOKEN" ]]; do
  read -r -s -p "Telegram bot token: " TELEGRAM_TOKEN
  echo
done

read -r -p "Chat model [gpt-4.1-mini]: " CHAT_MODEL
CHAT_MODEL=${CHAT_MODEL:-gpt-4.1-mini}

read -r -p "Voice note language (Whisper) [it]: " TRANS_LANG
TRANS_LANG=${TRANS_LANG:-it}

export OPENAI_KEY TELEGRAM_TOKEN CHAT_MODEL TRANS_LANG
python3 <<'"'"'PY'"'"'
import json, os

path = "/root/.nanobot/config.json"
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)

cfg.setdefault("agents", {}).setdefault("defaults", {})
cfg["agents"]["defaults"]["model"] = os.environ["CHAT_MODEL"]
cfg["agents"]["defaults"]["provider"] = "openai"

cfg.setdefault("providers", {}).setdefault("openai", {})
cfg["providers"]["openai"]["apiKey"] = os.environ["OPENAI_KEY"]

cfg.setdefault("channels", {}).setdefault("telegram", {})
cfg["channels"]["telegram"]["enabled"] = True
cfg["channels"]["telegram"]["token"] = os.environ["TELEGRAM_TOKEN"]

cfg.setdefault("transcription", {})
cfg["transcription"].update(
    {
        "enabled": True,
        "provider": "openai",
        "model": "whisper-1",
        "language": os.environ["TRANS_LANG"],
        "maxDurationSec": 120,
        "maxUploadMb": 25,
    }
)

with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PY
unset OPENAI_KEY TELEGRAM_TOKEN CHAT_MODEL TRANS_LANG
echo "Wrote $CFG (mode 600)"
'
}

print_next_steps() {
  cat <<'EOF'

Done.

Manual steps Android cannot automate:
  1. Allow Termux to run in the background (OEM battery / app launch settings).
  2. APKs (matching-key pair): https://github.com/oswaldlow/termux-boot/releases/tag/v0.8.1-boot-fix
     termux-app_matching-key_universal-debug.apk then termux-boot-app_v0.8.1-boot-fix_debug.apk; open Boot once.

Start gateway now (foreground test):
  proot-distro login debian
  source /root/nanobot-env/bin/activate
  nanobot gateway

Or host session + loop:
  tmux new -s nanobot-host ~/bin/nanobot-loop

Logs:
  tail -f ~/nanobot-logs/gateway.log
  tail -f ~/nanobot-logs/boot.log

EOF
}

main() {
  [[ "$(uname -o 2>/dev/null || true)" == *Android* ]] || [[ -d /data/data/com.termux ]] || \
    die "Run this script in Termux on Android."

  ensure_repo_files
  REPO="$INSTALL_DIR"

  check_termux_arch
  termux_bootstrap
  ensure_debian
  debian_setup
  install_config_example "$REPO/config/config.json.example"
  configure_secrets
  install_termux_scripts "$REPO"
  print_next_steps
}

main "$@"
