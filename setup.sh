#!/data/data/com.termux/files/usr/bin/bash
# Nanobot on Android: Termux + proot Debian. Run from the cloned repo in Termux (tmux is fine).
# Safe to re-run: keeps the existing config and secrets, reinstalls the scripts.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_LOG="$HOME/nanobot-logs/setup.log"

export DEBIAN_FRONTEND=noninteractive
export PIP_NO_INPUT=1
export PIP_ROOT_USER_ACTION=ignore

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\nSETUP FAILED: %s\n' "$*" >&2; exit 1; }
in_debian() { proot-distro login debian -- /bin/bash -lc "$1"; }

check_termux() {
  [[ -d /data/data/com.termux ]] || die "Run this script in Termux on Android."
  [[ "$(uname -m)" == aarch64 && "$(dpkg --print-architecture)" == aarch64 ]] ||
    die "Need 64-bit Termux (aarch64). Reinstall the ARM64 Termux APK."
}

termux_packages() {
  # No `pkg upgrade`: it replaces bash/termux-exec under the running script and kills the session.
  pkg update -y
  pkg install -y proot-distro tmux git curl
}

ensure_debian() {
  if proot-distro list 2>/dev/null | grep -Fxq debian; then
    echo "Debian already installed"
  else
    proot-distro install debian
  fi
}

install_nanobot() {
  in_debian "export NANOBOT_RECREATE_VENV='${NANOBOT_RECREATE_VENV:-}'; "'
set -euo pipefail
APT_OPTS="-y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
apt-get update -qq
apt-get install $APT_OPTS python3 python3-venv python3-pip git curl nano build-essential
apt-get install $APT_OPTS python3.12 python3.12-venv 2>/dev/null || true
apt-get install $APT_OPTS python3.11 python3.11-venv 2>/dev/null || true

PY=python3
for cand in python3.12 python3.11 python3; do
  command -v "$cand" >/dev/null 2>&1 && { PY=$cand; break; }
done
echo "Using $PY ($($PY --version 2>&1))"

[[ "$NANOBOT_RECREATE_VENV" == 1 ]] && rm -rf /root/nanobot-env
[[ -d /root/nanobot-env ]] || "$PY" -m venv /root/nanobot-env
source /root/nanobot-env/bin/activate
python -m pip install -q --upgrade pip
python -m pip install -q --only-binary=:all: rapidfuzz
# cryptography 50.x wheels die with SIGILL (rc=132) under proot; 43-46 import fine.
python -m pip install -q --only-binary=:all: "cryptography<47"
python -m pip install -q nanobot-ai
echo "nanobot $(nanobot --version)"
'
}

install_config() {
  in_debian "
set -euo pipefail
mkdir -p /root/.nanobot
if [[ -f /root/.nanobot/config.json ]]; then
  echo 'Keeping existing /root/.nanobot/config.json'
else
  cp '$REPO/config/config.json.example' /root/.nanobot/config.json
  echo 'Wrote /root/.nanobot/config.json from the example'
fi
"
}

# Prompts only for the OpenAI key and Telegram token; model and language come from the example.
configure_secrets() {
  if [[ ! -t 0 ]]; then
    echo "Non-interactive: skipping prompts. Edit the config later with: nanobot-ctl config"
    return 0
  fi
  if ! in_debian 'grep -q PASTE_YOUR_ /root/.nanobot/config.json'; then
    echo "Config already has secrets; skipping prompts"
    return 0
  fi

  in_debian '
set -euo pipefail
OPENAI_KEY="" TELEGRAM_TOKEN=""
while [[ -z "$OPENAI_KEY" ]]; do read -r -s -p "OpenAI API key: " OPENAI_KEY </dev/tty; echo; done
while [[ -z "$TELEGRAM_TOKEN" ]]; do read -r -s -p "Telegram bot token: " TELEGRAM_TOKEN </dev/tty; echo; done
export OPENAI_KEY TELEGRAM_TOKEN
python3 <<'"'"'PY'"'"'
import json, os

path = "/root/.nanobot/config.json"
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
cfg["providers"]["openai"]["apiKey"] = os.environ["OPENAI_KEY"]
cfg["channels"]["telegram"]["token"] = os.environ["TELEGRAM_TOKEN"]
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
os.chmod(path, 0o600)
PY
echo "Saved keys to /root/.nanobot/config.json (mode 600)"
'
}

install_scripts() {
  mkdir -p "$HOME/bin" "$HOME/.termux/boot"
  install -m 700 "$REPO/scripts/nanobot-ctl" "$REPO/scripts/nanobot-loop" "$HOME/bin/"
  install -m 700 "$REPO/scripts/00-start-nanobot" "$HOME/.termux/boot/"
  # Scripts from older versions of this repo.
  rm -f "$HOME"/bin/{start-nanobot-host,update-nanobot,update-nanobot-src,debug-gateway} \
    "$HOME"/bin/{collect-nanobot-logs,collect-debian-inner.sh,nanobot-distro.sh} \
    "$HOME"/{.nanobot-distro,.nanobot-source-url}
  if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# nanobot-android-termux\nexport PATH="$HOME/bin:$PATH"\n' >>"$HOME/.bashrc"
  fi
}

main() {
  check_termux
  mkdir -p "$HOME/nanobot-logs"
  exec > >(tee -a "$SETUP_LOG") 2>&1
  echo "===== setup $(date '+%Y-%m-%d %H:%M:%S') (log: $SETUP_LOG) ====="

  step "Installing Termux packages"
  termux_packages
  step "Installing Debian"
  ensure_debian
  step "Installing nanobot in Debian"
  install_nanobot
  step "Installing the config"
  install_config
  step "Configuring API keys"
  configure_secrets
  step "Installing nanobot-ctl and the boot entry"
  install_scripts

  cat <<'EOF'

==> Done.

Start the bot:   ~/bin/nanobot-ctl start
All commands:    ~/bin/nanobot-ctl

Open a new Termux session to use plain `nanobot-ctl` (~/bin is now on your PATH).
Allow Termux to run in the background in your battery settings.
EOF
}

main "$@"
