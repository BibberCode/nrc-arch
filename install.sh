#!/usr/bin/env bash
# NoRisk Client - Ein-Skript-Installation (Arch / CachyOS).
#
# Ablauf für neue Nutzer:
#   1. Aus GitHub-Releases `install.sh` + `.pkg.tar.zst` laden
#      (oder nur install.sh - das Paket wird dann automatisch geladen).
#   2. `bash install.sh` ausführen. Fertig.
#
# Kein Flatpak, kein makepkg nötig.
set -euo pipefail

REPO="${REPO:-BibberCode/nrc-arch}"
# ^ Eigenes Release-Repo (enthält .pkg.tar.zst + install.sh).
#   Alternativ per Env überschreiben: REPO=... bash install.sh

PKG_GLOB="no-risk-launcher-*.pkg.tar.zst"
WITH_REPO=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: bash install.sh [--with-repo] [--dry-run] [--help]

  ohne Option : installiert .pkg.tar.zst aus dem gleichen Ordner,
                sonst lädt es das neueste Release-Paket herunter,
                dann: sudo pacman -U <paket>
  --with-repo : richtet zusätzlich [norisk] in /etc/pacman.conf ein,
                damit Updates per `sudo pacman -Syu` kommen
  --dry-run   : zeigt nur was passieren würde (kein sudo, kein pacman)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-repo) WITH_REPO=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unbekannte Option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}

if ! command -v pacman >/dev/null 2>&1; then
  echo "Fehler: kein pacman gefunden (nur Arch/CachyOS)." >&2
  exit 1
fi

# 1. Paket finden: erst lokal im Skript-Ordner, dann Download.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$(ls -1 "$SCRIPT_DIR"/$PKG_GLOB 2>/dev/null | head -n 1 || true)"

if [ -z "${PKG_FILE:-}" ]; then
  echo "Kein $PKG_GLOB im Ordner, lade neuestes Release von $REPO ..."
  API="https://api.github.com/repos/${REPO}/releases/latest"
  URL="$(curl -fsSL "$API" | python3 -c "import json,sys,glob; rel=json.load(sys.stdin); ms=[a['browser_download_url'] for a in rel.get('assets',[]) if a.get('name','').endswith('.pkg.tar.zst')]; print(ms[0] if ms else '')")"
  if [ -z "$URL" ]; then
    echo "Fehler: kein .pkg.tar.zst im latest Release von $REPO gefunden." >&2
    echo "Tipp: lade die Datei manuell aus Releases neben install.sh und starte erneut." >&2
    exit 1
  fi
  PKG_FILE="/tmp/$(basename "$URL")"
  echo "Lade $URL ..."
  if [ "$DRY_RUN" = 1 ]; then
    echo "+ curl -fL $URL -o $PKG_FILE"
  else
    curl -fL "$URL" -o "$PKG_FILE"
  fi
else
  echo "Gefunden: $PKG_FILE"
fi

# 2. Installieren.
echo "Installiere $PKG_FILE ..."
run sudo pacman -U --noconfirm "$PKG_FILE"

# 3. Optional: Repo für pacman -Syu Updates.
if [ "$WITH_REPO" = 1 ]; then
  REPO_URL="${REPO_URL:-https://bibbercode.github.io/nrc-arch/$arch}"
  if grep -q "^\[norisk\]" /etc/pacman.conf 2>/dev/null; then
    echo "[norisk] bereits eingerichtet."
  else
    echo "Richte [norisk]-Repo ein ..."
    if [ "$DRY_RUN" = 1 ]; then
      echo "+ (Backup /etc/pacman.conf, anhängen [norisk] Server = $REPO_URL)"
    else
      sudo cp /etc/pacman.conf "/etc/pacman.conf.bak.$(date +%Y%m%d-%H%M%S)"
      printf '\n[norisk]\nServer = %s\nSigLevel = Never\n' "$REPO_URL" | sudo tee -a /etc/pacman.conf >/dev/null
      sudo pacman -Sy
    fi
  fi
  echo "Updates ab jetzt via: sudo pacman -Syu"
else
  echo "Fertig. Für automatische Updates erneut install.sh --with-repo ausführen"
  echo "oder manuell: sudo pacman -Syu (nur mit Repo), sonst Skript erneut laden."
fi
