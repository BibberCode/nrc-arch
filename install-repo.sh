#!/usr/bin/env bash
# Einmal-Installer für neue Nutzer (Arch / CachyOS).
# Idempotent, mit Backup von /etc/pacman.conf.
set -euo pipefail

# TODO: nach Repo-Erstellung ersetzen, z.B.:
# REPO_URL="https://bjornl.github.io/nrc-arch/$arch"
REPO_URL="${REPO_URL:-https://<GITHUB_USER>.github.io/<REPO>/$arch}"
REPO_NAME="norisk"

if ! command -v pacman >/dev/null 2>&1; then
  echo "Fehler: kein pacman gefunden (nur Arch/CachyOS)." >&2
  exit 1
fi

if grep -q "^\[${REPO_NAME}\]" /etc/pacman.conf 2>/dev/null; then
  echo "[${REPO_NAME}] bereits in /etc/pacman.conf"
else
  echo "Trage [${REPO_NAME}] in /etc/pacman.conf ein (Backup wird angelegt)..."
  sudo cp /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%Y%m%d-%H%M%S)"
  printf '\n[%s]\nServer = %s\nSigLevel = Never\n' "${REPO_NAME}" "${REPO_URL}" | sudo tee -a /etc/pacman.conf >/dev/null
fi

sudo pacman -Sy
sudo pacman -S --noconfirm no-risk-launcher
echo "Fertig. Updates ab jetzt via: sudo pacman -Syu"
