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

maybe_onboard() {
  if proot-distro login debian -- /bin/bash -lc 'grep -q PASTE_YOUR_ /root/.nanobot/config.json 2>/dev/null'; then
    log "Config still has placeholders — edit /root/.nanobot/config.json in Debian, then run: nanobot onboard (optional)"
    return 0
  fi
  if [[ -t 0 ]]; then
    log "Running nanobot onboard (interactive)"
    proot-distro login debian -- /bin/bash -lc 'source /root/nanobot-env/bin/activate && nanobot onboard' || true
  else
    log "Non-interactive shell: skip nanobot onboard. Run inside Debian when ready."
  fi
}

print_next_steps() {
  cat <<'EOF'

Done.

Manual steps Android cannot automate:
  1. Allow Termux to run in the background (OEM battery / app launch settings).
  2. Install Termux:Boot; open the Boot app once. On some devices use a matching-key boot-fix build.
  3. Edit secrets: proot-distro login debian — nano /root/.nanobot/config.json

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
  install_termux_scripts "$REPO"
  maybe_onboard
  print_next_steps
}

main "$@"
