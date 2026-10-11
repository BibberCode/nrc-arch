# no-risk-launcher (Arch / CachyOS, ohne Flatpak)

Natives `pacman`-Paket aus dem offiziellen `.deb` von
https://github.com/NoRiskClient/noriskclient-launcher
Aktuell: `v0.6.29-beta.6` → `pkgver 0.6.29_beta.6`.

Dein alter Ordner `norisk-pkg/` bleibt unangetastet. Das hier ist die
saubere Variante daneben (`no-risk-launcher/`).

## Installieren (auf Arch / CachyOS)

```bash
cd no-risk-launcher
makepkg -si
```

Das macht:
1. lädt `NoRiskClient-Linux.deb` von GitHub,
2. prüft SHA256 (kein `SKIP` mehr),
3. entpackt nach `/usr/bin/noriskclient-launcher-v3`,
4. fixt die Desktop-Datei (`StartupWMClass`, `Categories`).

Danach normal updaten:

```bash
cd no-risk-launcher
makepkg -si
# oder nach Versionserhöhung:
sudo pacman -U no-risk-launcher-*.pkg.tar.zst
```

## Deinstallieren

```bash
sudo pacman -R no-risk-launcher
```

## Hinweise

* `base-devel` muss installiert sein: `sudo pacman -S base-devel`
* Kein Flatpak, kein Snap, kein Kompilieren nötig.
* Lizenz: GPL-3.0-only (Upstream).
* Bei KDE: Taskleiste ordnet das Fenster jetzt dem Starter zu.
