#!/usr/bin/env bash
# =============================================================================
#  Noctalia v5 Dotfiles – setup.sh   (getestet für: CachyOS/Arch + KDE Plasma/KWin)
#  Liest dein System aus, installiert Noctalia v5, spielt deine Config ein
#  und trägt den Autostart in Plasma ein. ENTER = Vorschlag übernehmen.
#
#  Nutzung:  bash setup.sh            interaktives Menü
#            bash setup.sh status     nur System/Config auslesen
#            bash setup.sh export     aktuelle Config ins Repo übernehmen
#            bash setup.sh install    nur Noctalia installieren
#            bash setup.sh apply      Wallpaper laden, Config aktivieren, Autostart
#  (läuft auch aus fish, das Skript startet selbst mit bash)
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$REPO_DIR/config"
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
CFG_DIR="$XDG_CONFIG/noctalia"          # handgeschriebene *.toml
STATE_DIR="$XDG_STATE/noctalia"         # GUI-Einstellungen: settings.toml
AUTOSTART="$XDG_CONFIG/autostart/noctalia.desktop"
META="$CONF/meta.env"
TS="$(date +%Y%m%d-%H%M%S)"
DOCS_INSTALL="https://docs.noctalia.dev/noctalia/getting-started/installation/"

C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[1m'; C_0=$'\e[0m'
log()  { printf '%s==>%s %s\n' "$C_G" "$C_0" "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '%s!!%s  %s\n' "$C_Y" "$C_0" "$*" >&2; }
die()  { printf '%sFehler:%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ask() {  # ask "Frage" "default"
  local ans=""
  read -r -p "$1${2:+ [$2]}: " ans </dev/tty || true
  printf '%s' "${ans:-${2:-}}"
}
yesno() { local a; a="$(ask "$1 (j/n)" "${2:-j}")"; [[ $a =~ ^[jJyY] ]]; }

# ---------------------------------------------------------------- Erkennung --
DISTRO_ID=unknown; FAMILY=other; DESKTOP="${XDG_CURRENT_DESKTOP:-unknown}"; SESSION="${XDG_SESSION_TYPE:-unknown}"

detect_system() {
  if [[ -r /etc/os-release ]]; then
    DISTRO_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
    local like; like="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    case " $DISTRO_ID $like " in
      *" arch "*|*" cachyos "*|*" endeavouros "*|*" manjaro "*) FAMILY=arch ;;
      *" fedora "*) FAMILY=fedora ;;
      *" suse "*|*opensuse*) FAMILY=suse ;;
      *" nixos "*) FAMILY=nixos ;;
      *" debian "*|*" ubuntu "*) FAMILY=debian ;;
      *) FAMILY=other ;;
    esac
  fi
}
is_kde() { [[ ${DESKTOP,,} == *kde* ]]; }

pkg_ver() { if have pacman; then pacman -Q "$1" 2>/dev/null || true; fi; }

# /home/<user> im Repo als __HOME__ speichern, beim Aktivieren wieder einsetzen
templatize() { grep -rIlF "$HOME" "$1" 2>/dev/null | xargs -r sed -i "s|$HOME|__HOME__|g"; }
render()     { grep -rIlF "__HOME__" "$1" 2>/dev/null | xargs -r sed -i "s|__HOME__|$HOME|g"; }

copy_tree() {  # copy_tree src dst
  rm -rf "$2"; mkdir -p "$2"; cp -a "$1"/. "$2"/
}

install_path() {  # install_path src dst  (Backup + Kopie + Pfade einsetzen)
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e $dst || -L $dst ]]; then mv "$dst" "$dst.bak-$TS"; info "Backup: $dst.bak-$TS"; fi
  cp -a "$src" "$dst"; render "$dst"; info "Aktiviert: $dst"
}

WALL_DIR="$HOME/Wallpaper"
WALL_FILE="$WALL_DIR/Wallpaper.jpg"

# Roh-URL einer Repo-Datei (aus dem git-Remote abgeleitet, überschreibbar mit NOCTALIA_RAW_BASE)
raw_url() {
  if [[ -n ${NOCTALIA_RAW_BASE:-} ]]; then echo "${NOCTALIA_RAW_BASE%/}/$1"; return 0; fi
  have git || return 0
  local remote slug branch
  remote="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)" || return 0
  slug="$(sed -E 's#^(git@github\.com:|ssh://git@github\.com/|https?://github\.com/)##; s#\.git$##' <<<"$remote")"
  [[ $slug =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 0
  branch="$(git -C "$REPO_DIR" symbolic-ref --short HEAD 2>/dev/null)" || branch=""
  [[ -n $branch ]] || branch=main
  echo "https://raw.githubusercontent.com/$slug/$branch/$1"
}

# Wallpaper.jpg aus dem Repo nach ~/Wallpaper/Wallpaper.jpg laden
fetch_wallpaper() {
  mkdir -p "$WALL_DIR"
  if [[ -f $WALL_FILE ]]; then
    yesno "$WALL_FILE existiert schon. Neu herunterladen/überschreiben?" n || return 0
  fi
  local url tmp; url="$(raw_url Wallpaper.jpg)"; tmp="$WALL_FILE.part"
  if [[ -n $url ]] && have curl && curl -fsSL "$url" -o "$tmp" && [[ -s $tmp ]]; then
    mv "$tmp" "$WALL_FILE"; info "Wallpaper heruntergeladen: $url"
  elif [[ -f $REPO_DIR/Wallpaper.jpg ]]; then
    rm -f "$tmp"; cp -a "$REPO_DIR/Wallpaper.jpg" "$WALL_FILE"; info "Download nicht möglich – Wallpaper aus dem lokalen Repo kopiert."
  else
    rm -f "$tmp"; warn "Kein Wallpaper.jpg im Repo gefunden. Lege es in die Repo-Wurzel (neben setup.sh) und pushe es."
    return 0
  fi
  info "Gespeichert: $WALL_FILE"
}

# Macht eine settings.toml portabel: keine Monitor-/Geräte-Bindungen, nichts gepinnt, festes Wallpaper
portabilize() {
  local f="$1" tmp; tmp="$(mktemp)"
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    /^[ \t]*\[/ && !inarr {
      cur = trim($0)
      skip = (cur ~ /^\[(desktop_widgets|lockscreen_widgets)/ || cur ~ /^\[wallpaper\.monitor/ || cur ~ /^\[battery\.device/)
    }
    skip { next }
    inarr { if ($0 ~ /^[ \t]*\][ \t]*$/) inarr = 0; next }
    cur == "[shell.launcher]" && $0 ~ /^[ \t]*pinned[ \t]*=/ {
      print "    pinned = [ ]"
      if ($0 !~ /\]/) inarr = 1
      next
    }
    $0 ~ /^[ \t]*monitors[ \t]*=/ { next }
    cur == "[wallpaper]" && $0 ~ /^[ \t]*directory[ \t]*=/ { print "directory = \"__HOME__/Wallpaper\""; next }
    (cur == "[wallpaper.default]" || cur == "[wallpaper.last]") && $0 ~ /^[ \t]*path[ \t]*=/ { print "    path = \"__HOME__/Wallpaper/Wallpaper.jpg\""; next }
    { print }
  ' "$f" > "$tmp"
  cat -s "$tmp" > "$f"; rm -f "$tmp"
}

validate_cfg() {
  have noctalia || return 0
  if timeout 15 noctalia config validate "$1" >/dev/null 2>&1; then info "Validierung OK: $1"
  else warn "Validierung meldet Probleme (oder Befehl nicht verfügbar). Selbst prüfen: noctalia config validate $1"; fi
}

# ------------------------------------------------------------------- Status --
do_status() {
  detect_system
  log "Systemcheck"
  info "Distro:        $DISTRO_ID (Familie: $FAMILY)"
  info "Desktop:       $DESKTOP  | Session: $SESSION"
  info "Noctalia v5:   $(pkg_ver noctalia | grep . || echo 'nicht per pacman installiert')"
  local v4; v4="$( { pkg_ver noctalia-shell; pkg_ver noctalia-qs; } | grep . || true)"
  [[ -n $v4 ]] && info "Noctalia v4:   $(echo $v4)  (alt, kann parallel installiert bleiben)"
  info "Läuft gerade:  $(pgrep -x noctalia >/dev/null 2>&1 && echo ja || echo nein)"
  info "Wallpaper:     $([[ -f $WALL_FILE ]] && echo "$WALL_FILE" || echo 'noch nicht geladen')"
  info "Autostart:     $([[ -f $AUTOSTART ]] && echo "$AUTOSTART" || echo 'nicht eingerichtet')"
  log "Deine aktuelle Config"
  info "GUI-Einstellungen: $([[ -f $STATE_DIR/settings.toml ]] && echo "$STATE_DIR/settings.toml" || echo 'keine settings.toml')"
  local f; for f in "$CFG_DIR"/*.toml; do [[ -f $f ]] && info "Handgeschrieben:   $f"; done
  log "Config im Repo"
  find "$CONF" -type f ! -name .gitkeep 2>/dev/null | sed "s|$CONF/|    |" || true
  return 0
}

# ------------------------------------------------------------------- Export --
do_export() {
  detect_system
  [[ -f $STATE_DIR/settings.toml ]] || die "Keine $STATE_DIR/settings.toml gefunden. Ändere etwas in den Noctalia-Einstellungen, dann existiert sie."
  log "Lese Noctalia-Config aus"
  mkdir -p "$CONF/state" "$CONF/user"
  cp -a "$STATE_DIR/settings.toml" "$CONF/state/settings.toml"
  info "GUI-Einstellungen -> config/state/settings.toml"

  # aktuelles Wallpaper als Wallpaper.jpg ins Repo (vor dem Portabel-Machen auslesen)
  local wp; wp="$(awk '/^[ \t]*\[wallpaper\.default\]/{f=1;next} /^[ \t]*\[/{f=0} f && /path[ \t]*=/{gsub(/^[^"]*"|"[ \t]*$/,"");print;exit}' "$CONF/state/settings.toml")"
  if [[ -f $wp && ${wp,,} =~ \.jpe?g$ ]]; then
    yesno "Aktuelles Wallpaper ($wp) als Wallpaper.jpg ins Repo kopieren?" j && { cp -a "$wp" "$REPO_DIR/Wallpaper.jpg"; info "Wallpaper -> Wallpaper.jpg"; }
  elif [[ -n $wp ]]; then
    warn "Wallpaper '$wp' ist keine .jpg oder nicht vorhanden – bitte selbst als Wallpaper.jpg ins Repo legen."
  fi
  templatize "$CONF/state/settings.toml"
  cp -a "$CONF/state/settings.toml" "$CONF/reference/settings.original.toml" 2>/dev/null || { mkdir -p "$CONF/reference"; cp -a "$CONF/state/settings.toml" "$CONF/reference/settings.original.toml"; }
  portabilize "$CONF/state/settings.toml"
  info "Portabel gemacht (ohne Monitor-Bindungen/Pins), Original: config/reference/settings.original.toml"

  local f n=0
  for f in "$CFG_DIR"/*.toml; do
    [[ -f $f ]] && { cp -a "$f" "$CONF/user/"; info "Handgeschrieben -> config/user/$(basename "$f")"; n=$((n+1)); }
  done
  (( n )) || info "Keine handgeschriebenen *.toml in $CFG_DIR (nur GUI-Config)."

  if [[ -d $STATE_DIR/plugins ]] && [[ -n "$(ls -A "$STATE_DIR/plugins" 2>/dev/null)" ]]; then
    info "Plugins gefunden: $(ls "$STATE_DIR/plugins" | tr '\n' ' ')"
    if yesno "Installierte Plugin-Dateien mit ins Repo übernehmen?" j; then
      copy_tree "$STATE_DIR/plugins" "$CONF/state/plugins"; info "Plugins -> config/state/plugins"
    fi
  fi

  templatize "$CONF"
  cat > "$META" <<META_EOF
# automatisch von setup.sh erzeugt
EXPORTED_AT="$(date -Iseconds)"
EXPORT_HOST="$(hostname)"
DISTRO_ID="$DISTRO_ID"
FAMILY="$FAMILY"
DESKTOP="$DESKTOP"
NOCTALIA_PKG="$(pkg_ver noctalia)"
META_EOF

  log "Datenschutz-Check (bevor du auf GitHub pushst!)"
  grep -rniE '^[[:space:]]*(api_?key|token|secret|password|passwd|latitude|longitude|lat|lon|city|address)[[:space:]]*=' \
    "$CONF" --include='*.toml' 2>/dev/null | head -n 15 | sed 's/^/    /' \
    && warn "Obige Zeilen prüfen." || info "Nichts Auffälliges gefunden (Standort ist auf auto_locate gestellt, keine feste Stadt)."

  echo
  info "Fertig. Jetzt:  cd '$REPO_DIR' && git add -A && git commit -m 'Noctalia config' && git push"
}

# ------------------------------------------------------------------ Install --
do_install() {
  detect_system
  if have noctalia; then
    info "Noctalia ist schon installiert ($(pkg_ver noctalia | grep . || echo 'ohne pacman'))."
    yesno "Trotzdem neu installieren/aktualisieren?" n || return 0
  fi
  log "Installiere Noctalia v5 (Distro: $DISTRO_ID / $FAMILY)"
  case "$FAMILY" in
    arch)
      if pacman -Si noctalia >/dev/null 2>&1; then
        sudo pacman -S --needed noctalia
      else
        local helper=""; have paru && helper=paru; have yay && helper=${helper:-yay}
        [[ -n $helper ]] || die "Paket 'noctalia' nicht in den Repos und kein AUR-Helper (yay/paru) da."
        warn "Nicht in den Repos – nehme das AUR-Paket noctalia-git (Entwicklungsstand)."
        "$helper" -S --needed noctalia-git
      fi ;;
    fedora)
      warn "Laut Doku: COPR lionheartp/Hyprland, Paket noctalia-git (Community-Repo)."
      yesno "COPR aktivieren und installieren?" j || return 0
      sudo dnf copr enable lionheartp/Hyprland
      sudo dnf install noctalia-git ;;
    *)
      warn "Für $DISTRO_ID kein automatischer Weg. Anleitung: $DOCS_INSTALL"
      return 0 ;;
  esac
  [[ -n "$(pkg_ver noctalia-shell)" ]] && info "Hinweis: Noctalia v4 (noctalia-shell) ist noch installiert – stört nicht, startet aber nicht von selbst."
  info "Optionale Abhängigkeiten zeigt pacman oben an (z.B. für einzelne Widgets)."
}

# -------------------------------------------------------------------- Apply --
add_autostart() {
  if [[ -f $AUTOSTART ]]; then info "Autostart existiert schon: $AUTOSTART"; return; fi
  mkdir -p "$(dirname "$AUTOSTART")"
  cat > "$AUTOSTART" <<'DESK'
[Desktop Entry]
Type=Application
Name=Noctalia
Comment=Noctalia Shell
Exec=noctalia
X-KDE-autostart-after=panel
DESK
  info "Autostart angelegt: $AUTOSTART"
}

kwin_notes() {
  cat <<'NOTE'
    Hinweis zu KDE/KWin (laut Noctalia-Doku). Diese Teile deiner Config laufen unter KWin nicht oder nur eingeschränkt:
      - Bar-Widgets "clipboard", "screenshot", "keyboard_layout" (fehlende Wayland-Protokolle)
      - Nachtlicht von Noctalia (nutze Plasmas "Night Color"), Screen Time, Blur
      - Taskbar/Dock laufen über ein KWin-Skript und sind weniger stabil
NOTE
}

do_apply() {
  detect_system; local ref="$CONF/state/settings.toml"
  [[ -f $ref ]] || die "config/state/settings.toml fehlt im Repo."
  if pgrep -x noctalia >/dev/null 2>&1; then
    warn "Noctalia läuft. Beim Beenden kann es die Einstellungen überschreiben."
    yesno "Noctalia jetzt beenden?" j && { pkill -x noctalia || true; sleep 1; }
  fi

  log "Wallpaper"
  fetch_wallpaper

  log "Aktiviere Config"
  install_path "$ref" "$STATE_DIR/settings.toml"
  local f; for f in "$CONF"/user/*.toml; do [[ -f $f ]] && install_path "$f" "$CFG_DIR/$(basename "$f")"; done
  [[ -d $CONF/state/plugins ]] && install_path "$CONF/state/plugins" "$STATE_DIR/plugins"
  validate_cfg "$STATE_DIR/settings.toml"

  if is_kde; then
    yesno "Noctalia automatisch beim Plasma-Login starten?" j && add_autostart
    kwin_notes
  else
    warn "Kein KDE erkannt – Autostart in deinem Compositor selbst eintragen (Befehl: noctalia)."
  fi
  log "Fertig. Zum Testen: Terminal öffnen und 'noctalia' starten (oder abmelden/anmelden)."
}

# --------------------------------------------------------------------- Main --
menu() {
  do_status; echo
  cat <<MENU
${C_B}Was möchtest du tun?${C_0}
  1) Meine aktuelle Config auslesen & ins Repo übernehmen  (Hauptrechner)
  2) Noctalia installieren & Config aktivieren              (neuer Rechner)
  3) Nur Noctalia installieren
  4) Nur Config aktivieren + Autostart
  q) Beenden
MENU
  case "$(ask "Auswahl" 2)" in
    1) do_export ;;
    2) do_install; do_apply ;;
    3) do_install ;;
    4) do_apply ;;
    *) exit 0 ;;
  esac
}

case "${1:-menu}" in
  status)  do_status ;;
  export)  do_export ;;
  install) do_install ;;
  apply)   do_apply ;;
  portabilize) portabilize "${2:?Datei angeben}" ;;
  menu|"") menu ;;
  *) die "Unbekannter Befehl '$1' (status|export|install|apply)" ;;
esac
