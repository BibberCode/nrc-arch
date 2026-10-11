# NoRisk Client für Arch Linux / CachyOS

Natives `pacman`-Paket aus dem offiziellen Upstream-`.deb`
(`NoRiskClient/noriskclient-launcher`), ohne Flatpak, ohne eigenen Build-PC.

* Installieren: `install-repo.sh` oder `docs/INSTALL.md`
* Updates: automatisch via `sudo pacman -Syu`
* Automation: `.github/workflows/update-publish.yml` (alle 6h, inkl. Betas),
  `build.yml` prüft jeden PR. Roter Build → kein Release, kein Repo-Update.
* Paketquelle: `no-risk-launcher/PKGBUILD` (SHA256 statt `SKIP`,
  `StartupWMClass`-Fix für KDE).

## Struktur

```text
no-risk-launcher/PKGBUILD   Paket (makepkg -si geht auch manuell)
scripts/check-upstream.py   Tag -> pkgver, Asset- + Digest-Check
.github/workflows/          build + update-publish (repo-add -> gh-pages)
docs/INSTALL.md             Anleitung für neue Nutzer
install-repo.sh             Einmal-Setup fürs pacman-Repo
norisk-pkg/                 LEGACY lokal, wird ignoriert, nicht pushen
```

## Noch zu tun vor `git push`

1. In `install-repo.sh` + `docs/pacman-norisk.conf.example` echte
   `https://<USER>.github.io/<REPO>` URL eintragen.
2. Repo auf GitHub erstellen, pushen, unter Settings → Pages → Branch `gh-pages` aktivieren.
3. Workflow einmal per `workflow_dispatch` starten, Release + `x86_64/norisk.db` prüfen.
4. Optional Phase 2: GPG-Signierung (`repo-add -s`, Secret `REPO_GPG_PRIVATE_KEY`).

## Lokales Bauen ohne Repo

```bash
cd no-risk-launcher
makepkg -si
```
