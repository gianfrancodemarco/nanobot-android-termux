#!/data/data/com.termux/files/usr/bin/bash
# Nanobot on Android: Termux + proot Debian. Run from Termux (tmux is fine).
set -euo pipefail

# Override before curl|bash if your clone URL differs:
DEFAULT_REPO="${NANOBOT_ANDROID_REPO:-https://github.com/gianfrancodemarco/nanobot-android-termux.git}"
INSTALL_DIR="${NANOBOT_ANDROID_DIR:-$HOME/nanobot-android-termux}"
TOTAL_STEPS=9
STEP=0
SETUP_LOG=""

export DEBIAN_FRONTEND=noninteractive
export GIT_TERMINAL_PROMPT=0
export PIP_NO_INPUT=1
export PIP_ROOT_USER_ACTION=ignore

if [[ -t 1 ]]; then
  _C_BOLD=$'\033[1m'
  _C_CYAN=$'\033[36m'
  _C_GREEN=$'\033[32m'
  _C_RED=$'\033[31m'
  _C_RESET=$'\033[0m'
else
  _C_BOLD= _C_CYAN= _C_GREEN= _C_RED= _C_RESET=
fi

_hr() { printf '%s\n' '============================================================'; }

log() { printf '[%s]   · %s\n' "$(date '+%H:%M:%S')" "$*"; }

step() {
  STEP=$((STEP + 1))
  printf '\n'
  _hr
  printf '%s[%s] STEP %s / %s%s\n' "$_C_BOLD" "$(date '+%H:%M:%S')" "$STEP" "$TOTAL_STEPS" "$_C_RESET"
  printf '%s  %s%s\n' "$_C_CYAN" "$*" "$_C_RESET"
  _hr
  printf '\n'
}

die() {
  printf '\n'
  _hr
  printf '%s[%s] SETUP FAILED%s\n' "$_C_RED" "$(date '+%H:%M:%S')" "$_C_RESET"
  printf '%s  %s%s\n' "$_C_RED" "$*" "$_C_RESET"
  _hr
  printf '\n'
  exit 1
}

init_logging() {
  mkdir -p "$HOME/nanobot-logs"
  SETUP_LOG="$HOME/nanobot-logs/setup.log"
  printf '\n===== setup %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$SETUP_LOG"
  exec > >(tee -a "$SETUP_LOG") 2>&1
  printf '\n'
  _hr
  printf '%s  Nanobot Android installer%s\n' "$_C_BOLD" "$_C_RESET"
  printf '  Log file: %s\n' "$HOME/nanobot-logs/setup.log"
  _hr
  printf '\n'
}

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
    log "Using repo at $INSTALL_DIR"
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
  log "Installing Termux packages (non-interactive)"
  pkg update -y
  pkg upgrade -y
  pkg install -y proot-distro tmux git curl
}

ensure_debian() {
  if proot-distro list 2>/dev/null | grep -q '^debian$'; then
    log "Debian rootfs already installed"
    return 0
  fi
  log "Installing Debian via proot-distro"
  # Do not pipe `yes` here: with pipefail, yes exits 141 (SIGPIPE) after install
  # finishes and the whole setup script stops before the next step.
  proot-distro install debian
  log "Debian rootfs ready"
}

debian_setup() {
  log "Nanobot venv and packages inside Debian"
  proot-distro login debian -- /bin/bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export PIP_NO_INPUT=1
export PIP_ROOT_USER_ACTION=ignore
APT_OPTS="-y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
apt-get update -qq
apt-get install $APT_OPTS python3 python3-venv python3-pip git curl build-essential

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
  echo 'Wrote /root/.nanobot/config.json from example'
else
  echo 'Keeping existing /root/.nanobot/config.json'
fi
"
}

install_termux_scripts() {
  local repo="$1"
  log "Installing Termux loop and boot scripts"
  mkdir -p "$HOME/bin" "$HOME/.termux/boot" "$HOME/nanobot-logs"
  install -m 700 "$repo/scripts/nanobot-loop" "$HOME/bin/nanobot-loop"
  install -m 700 "$repo/scripts/start-nanobot-host" "$HOME/bin/start-nanobot-host"
  install -m 700 "$repo/scripts/debug-gateway" "$HOME/bin/debug-gateway"
  install -m 700 "$repo/scripts/00-start-nanobot" "$HOME/.termux/boot/00-start-nanobot"
  if ! grep -q 'HOME/bin' "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# nanobot-android-termux\nexport PATH="$HOME/bin:$PATH"\n' >>"$HOME/.bashrc"
    log "Added ~/bin to PATH in ~/.bashrc (open a new Termux session or: source ~/.bashrc)"
  fi
  export PATH="$HOME/bin:$PATH"
}

verify_install() {
  log "Checking ~/bin/nanobot-loop and nanobot in Debian venv"
  [[ -x "$HOME/bin/nanobot-loop" ]] || die "Missing ~/bin/nanobot-loop (setup did not finish step 8)"
  proot-distro login debian -- /bin/bash -lc '
set -euo pipefail
test -d /root/nanobot-env
source /root/nanobot-env/bin/activate
command -v nanobot >/dev/null
nanobot --version 2>/dev/null || true
' || die "Nanobot not installed in /root/nanobot-env — see setup.log for apt/pip errors"
  log "Verify OK"
}

# Prompts only for OpenAI + Telegram keys; model/language use config defaults.
configure_secrets() {
  if [[ ! -t 0 ]]; then
    log "Non-interactive session: skipping secret prompts (edit /root/.nanobot/config.json in Debian)"
    return 0
  fi

  if proot-distro login debian -- /bin/bash -lc 'test -f /root/.nanobot/config.json'; then
    if ! proot-distro login debian -- /bin/bash -lc 'grep -q PASTE_YOUR_ /root/.nanobot/config.json 2>/dev/null'; then
      log "Config already has secrets; skipping key prompts"
      return 0
    fi
  fi

  log "Prompting for OpenAI API key and Telegram bot token (hidden input)"
  log "Using defaults: chat model gpt-4.1-mini, Whisper language it"

  proot-distro login debian -- /bin/bash -lc '
set -euo pipefail
CFG=/root/.nanobot/config.json
[[ -f "$CFG" ]] || { echo "missing $CFG" >&2; exit 1; }

OPENAI_KEY=""
while [[ -z "$OPENAI_KEY" ]]; do
  read -r -s -p "OpenAI API key: " OPENAI_KEY < /dev/tty
  echo
done

TELEGRAM_TOKEN=""
while [[ -z "$TELEGRAM_TOKEN" ]]; do
  read -r -s -p "Telegram bot token: " TELEGRAM_TOKEN < /dev/tty
  echo
done

CHAT_MODEL=gpt-4.1-mini
TRANS_LANG=it

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
  cat <<EOF

Done.

Manual steps Android cannot automate:
  1. Allow Termux to run in the background (OEM battery / app launch settings).
  2. APKs (matching-key pair): https://github.com/oswaldlow/termux-boot/releases/tag/v0.8.1-boot-fix
     termux-app_matching-key_universal-debug.apk then termux-boot-app_v0.8.1-boot-fix_debug.apk; open Boot once.

Start gateway now (foreground test):
  proot-distro login debian
  source /root/nanobot-env/bin/activate
  nanobot gateway

Or start gateway in tmux (recommended — replaces an old nanobot-host session if needed):
  ~/bin/start-nanobot-host
  # or from repo: ./start-nanobot-host

  The pane shows gateway output; if it looks idle, tail -f ~/nanobot-logs/gateway.log
  Do not run: tmux new -s nanobot-host ...  (fails if session already exists)

Logs:
  tail -f ~/nanobot-logs/setup.log
  tail -f ~/nanobot-logs/gateway.log
  tail -f ~/nanobot-logs/boot.log

EOF
}

main() {
  [[ "$(uname -o 2>/dev/null || true)" == *Android* ]] || [[ -d /data/data/com.termux ]] || \
    die "Run this script in Termux on Android."

  init_logging

  step "Locate or clone installer repo"
  ensure_repo_files
  REPO="$INSTALL_DIR"

  step "Check Termux is aarch64"
  check_termux_arch

  step "Install Termux packages"
  termux_bootstrap

  step "Ensure Debian rootfs (proot-distro)"
  ensure_debian

  step "Install Nanobot inside Debian"
  debian_setup

  step "Install Nanobot config template"
  install_config_example "$REPO/config/config.json.example"

  step "Configure API keys (prompt if needed)"
  configure_secrets

  step "Install gateway loop and boot scripts"
  install_termux_scripts "$REPO"

  step "Verify Nanobot and loop script"
  verify_install

  step "Finish"
  printf '\n'
  _hr
  printf '%s[%s] SETUP COMPLETE (%s/%s)%s\n' "$_C_GREEN" "$(date '+%H:%M:%S')" "$STEP" "$TOTAL_STEPS" "$_C_RESET"
  _hr
  printf '\n'
  print_next_steps
}

main "$@"
