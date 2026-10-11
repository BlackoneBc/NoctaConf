# Noctalia v5 Dotfiles (CachyOS + KDE Plasma / KWin)

Installiert [Noctalia v5](https://docs.noctalia.dev) und spielt meine Config ein.

## Ein Befehl für alles

```bash
git clone https://github.com/BlackoneBc/NoctaConf ~/noctalia-dotfiles && bash ~/noctalia-dotfiles/setup.sh
```

Funktioniert auch aus **fish**, das Skript läuft selbst mit bash. Es liest zuerst das System aus (Distro, Desktop, Pakete, vorhandene Config, Monitore) und fragt dann, was passieren soll.

| Befehl | Wirkung |
|---|---|
| `bash setup.sh` | Menü |
| `bash setup.sh status` | nur auslesen |
| `bash setup.sh export` | aktuelle Config ins Repo übernehmen |
| `bash setup.sh install` | Noctalia installieren (`pacman -S noctalia`) |
| `bash setup.sh apply` | Config aktivieren + Plasma-Autostart |

## Struktur

```
setup.sh
Wallpaper.jpg                <- DEIN Bild hier ablegen (Repo-Wurzel); wird nach ~/Wallpaper/Wallpaper.jpg geladen
config/state/settings.toml   -> ~/.local/state/noctalia/settings.toml  (portable GUI-Einstellungen)
config/state/plugins/        -> ~/.local/state/noctalia/plugins/       (optional, vom Export)
config/user/*.toml           -> ~/.config/noctalia/*.toml              (handgeschrieben, optional)
config/reference/            Original-Config mit Monitor-Layout (wird NICHT aktiviert)
config/meta.env              erkanntes System
```

## Wallpaper

`setup.sh apply` lädt `Wallpaper.jpg` aus diesem Repo (GitHub-Raw-URL, aus dem git-Remote abgeleitet) nach `~/Wallpaper/Wallpaper.jpg`. Klappt der Download nicht (z. B. privates Repo), wird die Datei aus dem lokalen Klon kopiert. Die Config zeigt fest auf diesen Pfad. `setup.sh export` kopiert dein aktuelles Wallpaper (wenn .jpg) als `Wallpaper.jpg` ins Repo.

## Portabel (monitor- und geräteunabhängig)

In `config/state/settings.toml` sind entfernt: Desktop-Widgets, Lockscreen-Widget-Positionen, Wallpaper-Einstellungen pro Monitor (`DP-1`, `HDMI-A-1`), Dock-Monitorauswahl und die Batterie-Schwelle für ein bestimmtes Funkgerät (Maus). Angepinnte Apps im Launcher sind leer (`pinned = [ ]`). `setup.sh export` macht das automatisch bei jedem Export; manuell geht es mit `bash setup.sh portabilize <datei>`.

## Wichtig zu wissen

- **Plugins:** `settings.toml` aktiviert `arch-updater`, `calculator`, `cmd-runner`, `file-search`, `ip-monitor`, `bongocat`, `wallhaven`. Fehlen sie auf dem neuen Rechner, in den Noctalia-Einstellungen unter Plugins installieren (oder beim `export` die Plugin-Dateien mit ins Repo nehmen). Da die Desktop-Widgets fehlen, hat `ip-monitor:desktop` keine Wirkung, bis du es dort neu platzierst.
- **KWin-Einschränkungen** (laut Noctalia-Doku): Die Bar-Widgets clipboard, screenshot und keyboard_layout gehen nicht. Nachtlicht, Screen Time und Blur sind eingeschränkt, Taskbar/Dock laufen über ein KWin-Skript.
- **Noctalia v4** (`noctalia-shell`, `noctalia-qs`) kann installiert bleiben, wird aber nicht gestartet. Der Autostart ruft `noctalia` (v5) auf.
