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
VERSION="" # z.B. 0.6.28 oder 0.6.29-beta.5 (Upstream-Form, v-Präfix ok)
CHANNEL="auto" # auto | beta | stable
# auto liest ~/.local/share/noriskclientv3/launcher_config.json (check_beta_channel
# aus dem offiziellen Launcher) und nimmt danach beta oder stable.

usage() {
  cat <<'EOF'
Usage: bash install.sh [--with-repo] [--dry-run] [--channel=auto|beta|stable] [--version=X] [--help]

  ohne Option : installiert .pkg.tar.zst aus dem gleichen Ordner,
                sonst lädt es das passende Release-Paket herunter
                (Kanal aus dem Launcher: check_beta_channel),
                dann: sudo pacman -U <paket>
  --version   : bestimmte Version installieren, z.B. --version=0.6.28
                oder --version=0.6.29-beta.5 (setzt Kanalwahl außer Kraft)
  --channel   : auto (Launcher-Einstellung lesen, Standard),
                beta (inkl. Pre-Releases) oder stable (nur finales Release)
  --with-repo : richtet zusätzlich [norisk] in /etc/pacman.conf ein,
                damit Updates per `sudo pacman -Syu` kommen
  --dry-run   : zeigt nur was passieren würde (kein sudo, kein pacman)
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-repo) WITH_REPO=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --channel=*) CHANNEL="${arg#--channel=}";;
    --version=*) VERSION="${arg#--version=}";;
    --help|-h) usage; exit 0 ;;
    *) echo "Unbekannte Option: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

case "$CHANNEL" in
  auto|beta|stable) ;;
  *) echo "Fehler: --channel muss auto, beta oder stable sein." >&2; exit 1 ;;
esac

# Kanal aus dem offiziellen Launcher lesen (Backend-Key check_beta_channel,
# Datei: ~/.local/share/noriskclientv3/launcher_config.json).
detect_channel() {
  local cfg="$HOME/.local/share/noriskclientv3/launcher_config.json"
  if [ "$CHANNEL" != "auto" ]; then echo "$CHANNEL"; return; fi
  if [ -f "$cfg" ]; then
    local v
    v="$(python3 -c "import json;print(json.load(open('$cfg')).get('check_beta_channel', False))" 2>/dev/null || echo ERROR)"
    if [ "$v" = "True" ]; then echo "beta"; return; fi
    if [ "$v" = "False" ]; then echo "stable"; return; fi
  fi
  echo "beta" # Fallback wie bisher, wenn keine Launcher-Config da ist
}

run() {
  if [ "$DRY_RUN" = 1 ]; then echo "+ $*"; else "$@"; fi
}

if ! command -v pacman >/dev/null 2>&1; then
  echo "Fehler: kein pacman gefunden (nur Arch/CachyOS)." >&2
  exit 1
fi

# 1. Paket finden: --version, sonst lokal im Skript-Ordner, sonst Download.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE=""
URL=""
if [ -n "$VERSION" ]; then
  norm="$(printf '%s' "$VERSION" | sed 's/^v//; s/-/_/g')"
  PKG_FILE="$(ls -1 "$SCRIPT_DIR"/no-risk-launcher-*"${norm}"*.pkg.tar.zst 2>/dev/null | head -n 1 || true)"
  if [ -z "${PKG_FILE:-}" ]; then
    tag="arch-v${norm}-1"
    echo "Version $VERSION gewünscht (Release $tag) ..."
    URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${tag}" 2>/dev/null | python3 -c "import json,sys; rel=json.load(sys.stdin); ms=[a['browser_download_url'] for a in rel.get('assets',[]) if a.get('name','').endswith('.pkg.tar.zst')]; print(ms[0] if ms else '')" 2>/dev/null || true)"
    if [ -z "$URL" ]; then
      echo "Fehler: Release $tag hat kein .pkg.tar.zst (oder existiert nicht)." >&2
      exit 1
    fi
  fi
else
  PKG_FILE="$(ls -1 "$SCRIPT_DIR"/$PKG_GLOB 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${PKG_FILE:-}" ] && [ -z "${URL:-}" ]; then
  EFFECTIVE_CHANNEL="$(detect_channel)"
  echo "Kanal: $EFFECTIVE_CHANNEL"
  if [ "$EFFECTIVE_CHANNEL" = "stable" ]; then
    echo "Suche neuestes finales Release von $REPO ..."
    URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases?per_page=20" | python3 -c "
import json,sys
for rel in json.load(sys.stdin):
    if rel.get('draft') or rel.get('prerelease'): continue
    if '_beta' in (rel.get('tag_name') or ''): continue
    ms=[a['browser_download_url'] for a in rel.get('assets',[]) if a.get('name','').endswith('.pkg.tar.zst')]
    if ms: print(ms[0]); break
")"
    if [ -z "$URL" ]; then
      echo "Fehler: kein finales (stable) Release mit .pkg.tar.zst bei $REPO gefunden." >&2
      echo "Entweder im Launcher Beta-Updates einschalten oder .pkg.tar.zst manuell neben install.sh legen." >&2
      exit 1
    fi
  else
    echo "Kein $PKG_GLOB im Ordner, lade neuestes Release (inkl. Beta) von $REPO ..."
    API="https://api.github.com/repos/${REPO}/releases/latest"
    URL="$(curl -fsSL "$API" | python3 -c "import json,sys,glob; rel=json.load(sys.stdin); ms=[a['browser_download_url'] for a in rel.get('assets',[]) if a.get('name','').endswith('.pkg.tar.zst')]; print(ms[0] if ms else '')")"
    if [ -z "$URL" ]; then
      echo "Fehler: kein .pkg.tar.zst im latest Release von $REPO gefunden." >&2
      echo "Tipp: lade die Datei manuell aus Releases neben install.sh und starte erneut." >&2
      exit 1
    fi
  fi
fi
if [ -z "${PKG_FILE:-}" ]; then
  if [ -z "${URL:-}" ]; then
    echo "Fehler: kein Paket bestimmt." >&2; exit 1
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
