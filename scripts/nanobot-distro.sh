# shellcheck shell=bash
# Proot-distro alias for nanobot-android-termux (written by setup.sh).
NANOBOT_DISTRO="$(tr -d '[:space:]' <"${HOME}/.nanobot-distro" 2>/dev/null || true)"
NANOBOT_DISTRO="${NANOBOT_DISTRO:-debian}"
export NANOBOT_DISTRO
