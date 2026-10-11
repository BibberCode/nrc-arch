# NoRisk Client für Arch / CachyOS – Installieren in 2 Minuten

Kein Flatpak, kein manuelles `.deb`-Entpacken, kein PC zum Bauen nötig.
Updates kommen per `pacman -Syu`.

## Variante A (empfohlen): eigenes pacman-Repo

Einmalig:

```bash
curl -fsSL https://raw.githubusercontent.com/<GITHUB_USER>/<REPO>/main/install-repo.sh | bash
```

Das Skript:
1. prüft `pacman`,
2. trägt `[norisk]` in `/etc/pacman.conf` ein (mit Backup),
3. macht `pacman -Sy`,
4. installiert `no-risk-launcher`.

Danach:

```bash
sudo pacman -Syu
```

## Variante B: manuell aus GitHub-Release

Falls du kein Custom-Repo willst:

```bash
curl -LO https://github.com/<GITHUB_USER>/<REPO>/releases/latest/download/no-risk-launcher-*.pkg.tar.zst
sudo pacman -U no-risk-launcher-*.pkg.tar.zst
```

## Deinstallieren

```bash
sudo pacman -R no-risk-launcher
# Repo wieder entfernen: [norisk]-Block aus /etc/pacman.conf löschen
```

## KDE-Hinweis

Die Desktop-Datei enthält `StartupWMClass=noriskclient-launcher-v3`,
die Taskleiste gruppiert das Fenster korrekt.

## Sicherheit

- Quelle ist immer das offizielle Upstream-`.deb`, SHA256 im PKGBUILD, kein `SKIP`.
- GitHub Actions baut in `archlinux:base-devel`, prüft `namcap`,
  `desktop-file-validate`, `vercmp`-Ordnung.
- Roter Build → kein Release, kein Repo-Update (Jobs mit `needs:`).
- `.sig` von Upstream ist Tauri-, kein PGP-Schlüssel, daher SHA256-Kette.
