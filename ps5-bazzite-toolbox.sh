#!/bin/bash
# PS5 Bazzite Deck toolbox (VivaLaVent/ps5-bazzite-deck image), for any console and any boot drive.
# One self-contained file that runs ON the PS5 (terminal or SSH). With no options it shows a menu.
#  - Diagnosis (READ-ONLY): looks for the problems seen on this setup (USB drive stalls and resets, GPU ring
#    resets, hung tasks, Wi-Fi driver hangs, OOM kills, crashes, unclean shutdowns, heat, NAS mount, a dead
#    graphical session) and the state of the settings; saves a full report (no passwords) to send for help.
#  - Screen and graphical session: get the picture back, restart the session, start in desktop/game mode.
#  - PortProton and Steam: add or remove a Windows game (PortProton + Desktop + Steam + "PortProton" collection),
#    sync the collection; global PortProton defaults (setup block "portproton"). Tools: space taken by each folder,
#    a backup of the home folder (picking what goes) that restores here or on another install.
#  - Settings (setup): blocks that adapt the image (language, boot options, Wi-Fi, updates, VRAM, fans, warm
#    reboot, HDMI fix, disk, firewall, Brave, Edge, NAS, the monitor in a phone's browser, zram swap size and compressor, swap on disk, the GPU's 40 compute units). Each explains what it changes, why and how to undo it, and asks.
#    Answers are kept in ~/.config/ps5-bazzite-toolbox.conf; running it again only offers what is pending.
#
#   bash ps5-bazzite-toolbox.sh                         # menu (the first time it offers to install itself as the
#                                               command "ps5-bazzite-toolbox" and in the applications menu)
#   bash ps5-bazzite-toolbox.sh --check [--boot -1]     # diagnosis of this (or the previous) boot + report
#   bash ps5-bazzite-toolbox.sh --watch                 # live kernel problems (Ctrl+C to stop)
#   bash ps5-bazzite-toolbox.sh --mem                   # live CPU/GPU load, VRAM/GTT/RAM/swap (used/total), temperatures, top VRAM users
#   bash ps5-bazzite-toolbox.sh --session status|restart|desktop|gamemode
#   bash ps5-bazzite-toolbox.sh --setup                 # settings, block by block, asking
#   bash ps5-bazzite-toolbox.sh --setup --status | --all | --only vram,nas
#   bash ps5-bazzite-toolbox.sh --update [v1.7.2]       # update the image from GitHub (asks which version)
#   bash ps5-bazzite-toolbox.sh --rollback              # go back to the image as it was before an update (saved copy)
#   bash ps5-bazzite-toolbox.sh --screen                # black screen: switch to another console and back
#   bash ps5-bazzite-toolbox.sh --add-game [Juego.exe]  # add a Windows game to PortProton and Steam
#   bash ps5-bazzite-toolbox.sh --remove-game [Juego.exe|"Nombre"]   # remove it (Steam, PortProton, disk), asking each step
#   bash ps5-bazzite-toolbox.sh --games                  # my games: change isolation or uninstall, from a list
#   bash ps5-bazzite-toolbox.sh --change-level Juego.exe # change how an installed game runs (normal / isolated)
#   bash ps5-bazzite-toolbox.sh --framegen Juego.exe     # frame generation (Lossless Scaling) for one game: on, off, tune
#   bash ps5-bazzite-toolbox.sh --run Juego.exe          # start a game as --add-game left it (isolated or not); asks nothing
#   bash ps5-bazzite-toolbox.sh --pp-collection [--dry-run|--yes]   # sync Steam's "PortProton" collection
#   bash ps5-bazzite-toolbox.sh --space [DIR]           # space taken by each folder in DIR (also the "espacio" command)
#   bash ps5-bazzite-toolbox.sh --self-update [v1.1.0]  # update this toolbox from its GitHub releases
#   bash ps5-bazzite-toolbox.sh --backup                # save your home folder (or what you pick) to another disk, the NAS, a folder
#   bash ps5-bazzite-toolbox.sh --restore [DIR]         # bring a copy back, or another install's home folder (another disk)
#   bash ps5-bazzite-toolbox.sh --install | --uninstall # command ~/.local/bin/ps5-bazzite-toolbox + applications menu
#   bash ps5-bazzite-toolbox.sh --version
#   bash ps5-bazzite-toolbox.sh --lang es|en [...]      # interface language (before the other options); saved. Default: the system
#                                               locale (LANG/LC_ALL/LC_MESSAGES starting with "es" = Spanish, else English)
# Setup blocks: locale cmdline wifi updates vram gpu40 zram swapdisco fans cpufreq warmreboot hdmi arranque bt steambt disk firewall brave edge nas bios media esde portproton atajos monitorweb
set -uo pipefail

TOOLBOX_VERSION=1.11.0                   # bump on every release (see CHANGELOG.md and release.sh)
TOOLBOX_REPO=fitamix/ps5-bazzite-toolbox
TOOLBOX_BIN=$HOME/.local/bin/ps5-bazzite-toolbox                      # where --install puts it
TOOLBOX_DESKTOP=$HOME/.local/share/applications/ps5-bazzite-toolbox.desktop

# Interface language (es|en): --lang > TOOLBOX_LANG saved in the config file > the system locale. Exported so the
# standalone scripts the toolbox launches speak the same language. L 'español' 'English' prints the right one.
TB_LANG=''; LANG_SAVE=0
if [ -r "$HOME/.config/ps5-bazzite-toolbox.conf" ]; then
    TB_LANG=$(sed -n 's/^TOOLBOX_LANG=//p' "$HOME/.config/ps5-bazzite-toolbox.conf" | tail -1)
fi
case $TB_LANG in es|en) ;; *)
    case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in es*) TB_LANG=es ;; *) TB_LANG=en ;; esac ;;
esac
L() { if [ "$TB_LANG" = es ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

MODE='' BOOT=0 SESSION_CMD='' STATUS_ONLY=0 ALL=0 ONLY='' UPDATE_TAG='' ARGS=()
while [ $# -gt 0 ]; do
    case $1 in
        --check) MODE=check; shift ;;
        --boot) BOOT=$2; MODE=check; shift 2 ;;
        --watch) MODE=watch; shift ;;
        --mem) MODE=mem; shift ;;
        --session) MODE=session; SESSION_CMD=${2:-status}; shift; [ $# -gt 0 ] && shift ;;
        --setup) MODE=setup; shift ;;
        --status) MODE=setup; STATUS_ONLY=1; shift ;;
        --all) MODE=setup; ALL=1; shift ;;
        --only) MODE=setup; ONLY=${2//,/ }; shift 2 ;;
        --update) MODE=update; UPDATE_TAG=''
                  if [ $# -gt 1 ] && [[ $2 != -* ]]; then UPDATE_TAG=$2; shift; fi; shift ;;
        --rollback) MODE=rollback; shift ;;
        --screen) MODE=screen; shift ;;
        --self-update) MODE=self-update; UPDATE_TAG=''
                  if [ $# -gt 1 ] && [[ $2 != -* ]]; then UPDATE_TAG=$2; shift; fi; shift ;;
        --backup) MODE=backup; shift ;;
        --restore) MODE=restore; UPDATE_TAG=''
                  if [ $# -gt 1 ] && [[ $2 != -* ]]; then UPDATE_TAG=$2; shift; fi; shift ;;
        --install) MODE=install; shift ;;
        --uninstall) MODE=uninstall; shift ;;
        --lang) case ${2:-} in es|en) TB_LANG=$2; LANG_SAVE=1 ;;
                    *) echo "$(L 'Uso: --lang es|en' 'Usage: --lang es|en')" >&2; exit 2 ;; esac; shift 2 ;;
        -V|--version) echo "ps5-bazzite-toolbox $TOOLBOX_VERSION"; exit 0 ;;
        --add-game|--remove-game|--change-level|--framegen|--games|--run|--pp-collection|--space)       # the rest of the line goes to that tool
                  MODE=${1#--}; shift; ARGS=("$@"); break ;;
        -h|--help) awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) echo "$(L "Opción desconocida: $1" "Unknown option: $1")" >&2; exit 2 ;;
    esac
done
if [ -z "$MODE" ]; then if [ -t 0 ]; then MODE=menu; else MODE=check; fi; fi

export TB_LANG
[ "$(id -u)" != 0 ] || { echo "$(L 'Ejecútalo con tu usuario, no como root (pedirá sudo cuando haga falta).' 'Run it as your own user, not as root (it asks for sudo when needed).')" >&2; exit 1; }
U=$(id -un)
if [ -t 1 ]; then G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' N=$'\e[0m'; else G='' Y='' R='' B='' N=''; fi
VERSION=$(awk 'NR == 1 { sub(/^v/, "", $1); print $1 }' /etc/ps5-bazzite-deck-version 2>/dev/null)
# A bootc install (from v2.5: the whole system is one image; bootc updates it and keeps the previous one) writes
# "<build> (bootc, ps5-bazzite-deck vX.Y)" there: its version is the deck= of the image's own VERSION file.
IS_BOOTC=0; [ -e /run/ostree-booted ] && IS_BOOTC=1
if [ $IS_BOOTC = 1 ]; then
    v=$(sed -n 's/^deck=v\{0,1\}\([0-9][0-9.]*\).*/\1/p' /usr/share/ps5-bazzite-bootc/VERSION 2>/dev/null); v=${v%.}
    [ -n "$v" ] && VERSION=$v
fi
ver_ge() { [ -n "$VERSION" ] && printf '%s\n%s\n' "$1" "$VERSION" | sort -V -C; }   # image version >= $1
# Reports, the monitor's CSV and the image update's log are written to a temporary file; at the end the toolbox
# asks whether to keep it and where (Enter = the current folder). Nothing is left behind unasked.
SAVED=''
save_output() {                          # save_output TMPFILE NAME "what" -> 0 and SAVED=path if kept
    local tmp=$1 name=$2 what=$3 dest=$PWD a
    [ -w "$dest" ] || dest=$HOME
    if [ -t 0 ]; then                    # no terminal (run from another script): keep it in the current folder
        read -e -rp "$(L "¿Guardar $what? Intro = en $dest, escribe otra carpeta, o n = no: " "Save $what? Enter = in $dest, type another folder, or n = no: ")" a
        case $a in
            [nN]|[nN][oO]) rm -f "$tmp"; echo "$(L 'No lo guardo.' "Not saving it.")"; return 1 ;;
            '') ;;
            *) dest=${a/#\~/$HOME} ;;
        esac
    fi
    if mkdir -p "$dest" 2>/dev/null && mv "$tmp" "$dest/$name"; then SAVED=$dest/$name; echo "$(L "Guardado: $SAVED" "Saved: $SAVED")"
    else echo "$(L "No puedo guardarlo en $dest; se queda en $tmp (se borra al apagar)." "Cannot save it in $dest; it stays at $tmp (deleted at power off).")" >&2; return 1; fi
}
# sudo is asked for only when an option needs it (the journal, the boot partition, polkit's rules, SDDM, systemd, /etc), once:
# a background loop then keeps it valid until the toolbox closes (Fedora forgets it after 5 minutes).
SUDO_KEEP=''
need_sudo() {
    [ -n "$SUDO_KEEP" ] && kill -0 "$SUDO_KEEP" 2>/dev/null && return 0
    if ! sudo -n true 2>/dev/null; then
        echo "$(L 'Esto necesita permisos de administrador: te pido la contraseña de sudo una vez, hasta que cierres la caja de herramientas.' 'This needs administrator rights: I ask for your sudo password once, until you close the toolbox.')"
        sudo -v || { echo "$(L 'Sin sudo no puedo hacerlo.' "I can't do it without sudo.")" >&2; return 1; }
    fi
    ( trap '' INT; while kill -0 $$ 2>/dev/null && sudo -n -v 2>/dev/null; do sleep 60; done ) &   # Ctrl+C mustn't stop it
    SUDO_KEEP=$!
    trap '[ -z "$SUDO_KEEP" ] || kill "$SUDO_KEEP" 2>/dev/null' EXIT
}

CONF=$HOME/.config/ps5-bazzite-toolbox.conf
OLD_CONF=$HOME/.config/ps5-bazzite-postinstall.conf      # its name before v1.0.0
EFI=/efi; [ $IS_BOOTC = 1 ] && EFI=/boot/efi   # the boot partition: bootc mounts it at /boot/efi
CMDLINE=$EFI/cmdline.txt                 # on bootc, options added here are kept across updates (ps5-bootc-sync)
VRAMTXT=$EFI/vram.txt
PERFCONF=/etc/ps5-bazzite-deck/perf.conf
TOOLS_REPO=https://github.com/ps5-linux/ps5-linux-tools
TOOLS_COMMIT=f1fa98a                     # the revision reviewed on 2026-10-27
POLKIT_RULE=/etc/polkit-1/rules.d/50-ps5-no-kde-smart.rules
MONWEB_PORT=${MONWEB_PORT:-8765}
MONWEB_PY=$HOME/.local/share/ps5-bazzite-toolbox/monitor-web.py
MONWEB_UNIT=$HOME/.config/systemd/user/ps5-monitor-web.service
MONWEB_CSV_DIR=${MONWEB_CSV_DIR:-$HOME/.local/share/ps5-bazzite-toolbox/monitor}   # a session's CSV, when you say so
BRAVE_FLAGS=$HOME/.var/app/com.brave.Browser/config/brave-flags.conf
EDGE_FLAGS=$HOME/.var/app/com.microsoft.Edge/config/edge-flags.conf
BLOCKS="locale cmdline wifi updates vram gpu40 zram swapdisco fans cpufreq warmreboot hdmi arranque bt steambt disk firewall brave edge nas bios media esde portproton atajos monitorweb"

# ======================================== settings (setup) ========================================
# --- saved answers -------------------------------------------------------------------------------
mkdir -p "$(dirname "$CONF")"
[ -e "$CONF" ] || [ ! -f "$OLD_CONF" ] || mv "$OLD_CONF" "$CONF"
touch "$CONF"
# shellcheck disable=SC1090
. "$CONF"
NAS_MNT=${NAS_MNT:-/var/mnt/nas}         # where the NAS share is mounted
remember() {                             # remember KEY VALUE -> kept in $CONF and in this run
    sed -i "/^$1=/d" "$CONF"; printf '%s=%q\n' "$1" "$2" >>"$CONF"; printf -v "$1" '%s' "$2"
}
ask() {                                  # ask "question" S|N -> 0 = yes; N makes "no" the default
    local d=${2:-S} a
    [ $ALL = 1 ] && { [ "$d" = S ]; return; }
    if [ "$TB_LANG" = es ]; then
        if [ "$d" = S ]; then read -rp "$1 [S/n] " a </dev/tty; [[ $a != [nN]* ]]
        else read -rp "$1 [s/N] " a </dev/tty; [[ $a == [sS]* ]]; fi
    else
        if [ "$d" = S ]; then read -rp "$1 [Y/n] " a </dev/tty; [[ $a != [nN]* ]]
        else read -rp "$1 [y/N] " a </dev/tty; [[ $a == [yYsS]* ]]; fi
    fi
}
value() {                                # value VAR "question" default -> asks, keeps the answer
    local cur=${!1:-$3} a
    if [ $ALL = 1 ]; then a=$cur; else read -rp "  $2 [$cur]: " a </dev/tty; a=${a:-$cur}; fi
    [ "$a" = - ] && a=                   # "-" = empty
    remember "$1" "$a"
}
say() { printf '  %s\n' "$@"; }
[ "$LANG_SAVE" = 1 ] && remember TOOLBOX_LANG "$TB_LANG"
section() { printf '\n  %s\n' "$(L 'QUÉ HACE:' 'WHAT IT DOES:')"; }

# --- helpers -------------------------------------------------------------------------------------
cmd_has() { sudo grep -qw -- "$1" "$CMDLINE"; }
cmd_set() {                              # cmd_set key value -> key=value in cmdline.txt (replaces any old value)
    if sudo grep -qE "(^| )$1=" "$CMDLINE"; then sudo sed -i -E "s#(^| )$1=[^ ]*#\1$1=$2#" "$CMDLINE"
    else sudo sed -i -E "s#[[:space:]]*\$# $1=$2#" "$CMDLINE"; fi
}
root_disk() {                            # the whole disk the system runs from, e.g. sda
    local src; src=$(findmnt -no SOURCE / | sed 's/\[.*//')
    lsblk -no PKNAME "$src" 2>/dev/null | head -1
}
root_usb() {                             # "vid:pid driver" of the boot drive when it is on USB
    local d p; d=$(root_disk); [ -n "$d" ] || return 1
    p=$(udevadm info -q property -n "/dev/$d" 2>/dev/null)
    grep -q '^ID_BUS=usb' <<<"$p" || return 1
    echo "$(sed -n 's/^ID_VENDOR_ID=//p' <<<"$p"):$(sed -n 's/^ID_MODEL_ID=//p' <<<"$p") $(sed -n 's/^ID_USB_DRIVER=//p' <<<"$p")"
}
gpu_dev() {                              # the GPU's sysfs dir; newer kernels also give each connector
    local d                              # (card0-DP-1/device) a device link, without the mem_info files
    for d in /sys/class/drm/card*/device; do [ -e "$d/mem_info_vram_total" ] && { echo "$d"; return; }; done
}
usb_errors() { journalctl -b -k --no-pager 2>/dev/null | grep -cE 'uas_eh_abort|timing out command|reset (SuperSpeed|high-speed).*USB device'; }
warm_on() { command -v ps5-warm-reboot >/dev/null && ps5-warm-reboot status 2>/dev/null | grep >/dev/null ': on'; }
REBOOT=0 COLD=0

# Each block: desc_X (what, why, undo), check_X (0 done, 1 pending, 2 not applicable), apply_X.

# --- locale --------------------------------------------------------------------------------------
LANG_WANT=${SYS_LANG:-es_ES.UTF-8} KEYMAP_WANT=${SYS_KEYMAP:-es} TZ_WANT=${SYS_TZ:-Europe/Madrid}
desc_locale() {
    section
    say "$(L "Idioma del sistema, teclado (consola y escritorio) y zona horaria, con hora por NTP." "System language, keyboard (console and desktop) and time zone, with time from NTP.")"
    say "$(L "Ahora: $(localectl status 2>/dev/null | sed -n 's/.*LANG=//p' | head -1), teclado $(localectl status 2>/dev/null | sed -n 's/.*VC Keymap: //p'), $(timedatectl show -p Timezone --value)" "Now: $(localectl status 2>/dev/null | sed -n 's/.*LANG=//p' | head -1), keyboard $(localectl status 2>/dev/null | sed -n 's/.*VC Keymap: //p'), $(timedatectl show -p Timezone --value)")"
    say "$(L "POR QUÉ: la imagen viene en inglés, con teclado US y hora UTC." "WHY: the image ships in English, with a US keyboard and UTC time.")"
    say "$(L "DESHACER: vuelve a ejecutar el bloque con otros valores." "UNDO: run the block again with other values.")"
    say "$(L "Steam tiene su propio idioma y zona horaria: cámbialos también en sus ajustes." "Steam has its own language and time zone: change them in its settings too.")"
}
check_locale() {
    local l; l=$(localectl status 2>/dev/null)
    grep -q "LANG=$LANG_WANT" <<<"$l" && grep -q "VC Keymap: $KEYMAP_WANT\$" <<<"$l" &&
        [ "$(timedatectl show -p Timezone --value)" = "$TZ_WANT" ]
}
apply_locale() {
    value SYS_LANG "$(L "Idioma (p. ej. es_ES.UTF-8, en_US.UTF-8)" "Language (e.g. es_ES.UTF-8, en_US.UTF-8)")" "$LANG_WANT"
    value SYS_KEYMAP "$(L "Teclado (p. ej. es, us, latam)" "Keyboard (e.g. es, us, latam)")" "$KEYMAP_WANT"
    value SYS_TZ "$(L "Zona horaria (p. ej. Europe/Madrid, America/Mexico_City)" "Time zone (e.g. Europe/Madrid, America/Mexico_City)")" "$TZ_WANT"
    LANG_WANT=$SYS_LANG KEYMAP_WANT=$SYS_KEYMAP TZ_WANT=$SYS_TZ
    sudo localectl set-locale "LANG=$SYS_LANG" && sudo localectl set-keymap "$SYS_KEYMAP" &&
        sudo localectl set-x11-keymap "$SYS_KEYMAP" && sudo timedatectl set-timezone "$SYS_TZ" &&
        sudo timedatectl set-ntp true
}

# --- cmdline -------------------------------------------------------------------------------------
quirk_for() {                            # quirk_for VID:PID -> the letters a drive known here needs (1 if none)
    case $1 in 21c4:0003) echo um ;;     # Lexar ES3: UAS errors and resets
               *) return 1 ;; esac
}
want_quirk() {                           # quirk letters for the boot drive: saved answer, else a guess
    [ -n "${USB_QUIRK+x}" ] && { echo "$USB_QUIRK"; return; }
    local u; u=$(root_usb) || return 0
    quirk_for "${u%% *}" && return
    [ "${u#* }" = uas ] && [ "$(usb_errors)" -gt 0 ] && echo u
}
desc_cmdline() {
    local u q; u=$(root_usb); q=$(want_quirk)
    section
    say "$(L "Añade parámetros de arranque a $CMDLINE (con copia previa en $CMDLINE.bak-FECHA):" "Adds boot parameters to $CMDLINE (backed up first to $CMDLINE.bak-DATE):")"
    say "$(L "- locale.LANG / vconsole.keymap: idioma y teclado ya desde el arranque, no solo en el escritorio." "- locale.LANG / vconsole.keymap: language and keyboard from boot, not only on the desktop.")"
    if [ -n "$u" ]; then
        say "$(L "- Disco de arranque por USB: ${u%% *} (driver ${u#* }), $(usb_errors) errores USB en este arranque." "- Boot drive over USB: ${u%% *} (driver ${u#* }), $(usb_errors) USB errors this boot.")"
        say "$(L "  usb-storage.quirks=${u%% *}:LETRAS cambia cómo se le habla: u = sin UAS (algunos adaptadores" "  usb-storage.quirks=${u%% *}:LETTERS changes how it is talked to: u = no UAS (some adapters")"
        say "$(L "  USB-NVMe dan errores y resets con UAS), m = transferencias de 32 KB. Recomendado: ${q:-ninguno}." "  USB-NVMe give errors and resets with UAS), m = 32 KB transfers. Recommended: ${q:-none}.")"
    fi
    ver_ge 1.5.0 && say "$(L "- Quita module_blacklist=moal si está: desde la v1.5.0 el Wi-Fi IW620 ya no se cuelga." "- Removes module_blacklist=moal if present: since v1.5.0 the IW620 Wi-Fi no longer hangs.")"
    say "$(L "POR QUÉ: consola en tu idioma y un disco USB estable." "WHY: console in your language and a stable USB drive.")"
    say "$(L "DESHACER: copia un $CMDLINE.bak-* sobre $CMDLINE (con sudo)." "UNDO: copy a $CMDLINE.bak-* over $CMDLINE (with sudo).")"
    say "$(L "Cuenta a partir del siguiente arranque." "Takes effect from the next boot.")"
}
check_cmdline() {
    sudo test -f "$CMDLINE" || return 2
    local q; q=$(want_quirk)
    cmd_has "locale.LANG=$LANG_WANT" && cmd_has "vconsole.keymap=$KEYMAP_WANT" || return 1
    if [ -n "$q" ]; then local u; u=$(root_usb); cmd_has "usb-storage.quirks=${u%% *}:$q" || return 1; fi
    ! { ver_ge 1.5.0 && sudo grep -q 'module_blacklist=moal' "$CMDLINE"; }
}
apply_cmdline() {
    local u; u=$(root_usb)
    if [ -n "$u" ]; then
        local q; q=$(want_quirk)
        value USB_QUIRK "$(L "Letras para usb-storage.quirks (u, um, o - para ninguna)" "Letters for usb-storage.quirks (u, um, or - for none)")" "${q:-}"
    fi
    sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
    cmd_set locale.LANG "$LANG_WANT" && cmd_set vconsole.keymap "$KEYMAP_WANT" || return 1
    if [ -n "$u" ] && [ -n "${USB_QUIRK:-}" ]; then cmd_set usb-storage.quirks "${u%% *}:$USB_QUIRK" || return 1; fi
    ver_ge 1.5.0 && sudo sed -i 's| module_blacklist=moal||' "$CMDLINE"
    say "$(L "Ahora: $(sudo cat "$CMDLINE")" "Now: $(sudo cat "$CMDLINE")")"
    REBOOT=1
}

# --- wifi ----------------------------------------------------------------------------------------
NOWIFI=/etc/NetworkManager/conf.d/99-ps5-no-wifi.conf
wifi_blocked() { grep -qs 'unmanaged-devices=type:wifi' "$NOWIFI"; }
desc_wifi() {
    section
    if ver_ge 1.5.0; then
        say "$(L "Vuelve a activar el Wi-Fi: borra $NOWIFI y desenmascara wpa_supplicant." "Turns Wi-Fi back on: deletes $NOWIFI and unmasks wpa_supplicant.")"
        say "$(L "POR QUÉ: en imágenes anteriores a la v1.5.0 el driver moal (IW620) se colgaba con el Wi-Fi" "WHY: in images before v1.5.0 the moal driver (IW620) hung with Wi-Fi")"
        say "$(L "activo y había que apagarlo. Desde la v1.5.0 funciona (probado: 1 GB a ~54 MB/s, sin cuelgues)." "on and it had to be turned off. Since v1.5.0 it works (tested: 1 GB at ~54 MB/s, no hangs).")"
        say "$(L "Si vas solo por cable puedes dejarlo apagado (responde no)." "If you only use a cable you can leave it off (answer no).")"
    else
        say "$(L "Apaga el Wi-Fi sin bloquear el driver moal, que también lleva el Bluetooth: NetworkManager" "Turns Wi-Fi off without blocking the moal driver, which also runs Bluetooth: NetworkManager")"
        say "$(L "ignora la interfaz Wi-Fi y wpa_supplicant queda enmascarado." "ignores the Wi-Fi interface and wpa_supplicant is masked.")"
        say "$(L "POR QUÉ: con esta versión ($VERSION) el driver moal se cuelga con el Wi-Fi activo" "WHY: with this version ($VERSION) the moal driver hangs with Wi-Fi on")"
        say "$(L "(woal_set_get_tx_power, procesos en estado D). Usa cable, o actualiza a la v1.5.0 o posterior." "(woal_set_get_tx_power, processes in D state). Use a cable, or update to v1.5.0 or later.")"
    fi
    say "$(L "DESHACER: vuelve a ejecutar el bloque tras cambiar de versión, o borra/crea $NOWIFI a mano." "UNDO: run the block again after changing version, or delete/create $NOWIFI by hand.")"
}
check_wifi() {
    ls /sys/class/net/*/wireless >/dev/null 2>&1 || wifi_blocked || return 2
    if ver_ge 1.5.0; then ! wifi_blocked
    else wifi_blocked && [ "$(systemctl is-enabled wpa_supplicant.service 2>/dev/null)" = masked ]; fi
}
apply_wifi() {
    if ver_ge 1.5.0; then
        sudo rm -f "$NOWIFI" && sudo systemctl unmask wpa_supplicant.service && sudo systemctl restart NetworkManager
    else
        printf '[keyfile]\nunmanaged-devices=type:wifi\n' | sudo tee "$NOWIFI" >/dev/null || return 1
        sudo systemctl mask --now wpa_supplicant.service && sudo systemctl reload NetworkManager
    fi
}

# --- updates -------------------------------------------------------------------------------------
desc_updates() {
    section
    say "$(L "Desactiva las actualizaciones automáticas (uupd, rpm-ostree) e impide que dnf actualice el kernel," "Disables automatic updates (uupd, rpm-ostree) and stops dnf from updating the kernel,")"
    say "$(L "Mesa, linux-firmware o gamescope (/etc/dnf/libdnf5.conf.d/90-ps5-hold.conf)." "Mesa, linux-firmware or gamescope (/etc/dnf/libdnf5.conf.d/90-ps5-hold.conf).")"
    say "$(L "POR QUÉ: la imagen no es ostree (ujust update y rpm-ostree no sirven) y esos paquetes llevan" "WHY: the image is not ostree (ujust update and rpm-ostree don't work) and those packages carry")"
    say "$(L "parches para la PS5: un dnf upgrade los sustituiría por los normales y podría no arrancar." "PS5 patches: a dnf upgrade would replace them with the stock ones and it might not boot.")"
    say "$(L "Las actualizaciones de la imagen se hacen con su propio update.sh (ver el README del autor)." "Image updates are done with its own update.sh (see the author's README).")"
    say "$(L "En una instalación bootc no aplica: ahí las actualizaciones son las del autor (opción 17) y se deshacen." "On a bootc install it does not apply: there updates are the author's (option 17) and can be undone.")"
    say "$(L "DESHACER: sudo systemctl unmask uupd.timer rpm-ostreed-automatic.timer; borra 90-ps5-hold.conf." "UNDO: sudo systemctl unmask uupd.timer rpm-ostreed-automatic.timer; delete 90-ps5-hold.conf.")"
}
check_updates() {
    [ $IS_BOOTC = 1 ] && return 2        # bootc updates are the image's own, whole and undoable: never block them
    [ "$(systemctl is-enabled uupd.timer 2>/dev/null)" = masked ] &&
        [ "$(systemctl is-enabled rpm-ostreed-automatic.timer 2>/dev/null)" = masked ] &&
        grep -qs '^excludepkgs=kernel\*,mesa-\*,linux-firmware\*,gamescope\*' /etc/dnf/libdnf5.conf.d/90-ps5-hold.conf || return 1     # grep says 2 for a missing file: that is pending, not "doesn't apply"
}
apply_updates() {
    sudo systemctl mask --now uupd.timer rpm-ostreed-automatic.timer || return 1
    sudo mkdir -p /etc/dnf/libdnf5.conf.d &&
        printf '[main]\nexcludepkgs=kernel*,mesa-*,linux-firmware*,gamescope*\n' |
        sudo tee /etc/dnf/libdnf5.conf.d/90-ps5-hold.conf >/dev/null
}

# --- vram ----------------------------------------------------------------------------------------
VRAM_WANT=${VRAM_SIZE:-0x100000000}         # 4 GB unless you chose another amount
VRAM_MIN=$((512 << 20)) VRAM_MAX=$((8 << 30)) VRAM_STEP=$((256 << 20))
LINUX_TOTAL_MB=14950                     # RAM Linux sees with no VRAM carved out (14.4 GB at 512 MB, 10.9 at 4 GB)
vram_gb() { awk -v v="$(( $1 ))" 'BEGIN { printf "%g GB", v / 2^30 }'; }
vram_left() { awk -v v="$(( $1 ))" -v t="$LINUX_TOTAL_MB" 'BEGIN { printf "~%.1f GB", (t - v / 2^20) / 1024 }'; }
vram_cur() { sudo cat "$VRAMTXT" 2>/dev/null | tr -d '[:space:]'; }
vram_parse() {                           # "4", "4G", "3.5GB", "1536M", "0x100000000" -> bytes (empty if invalid)
    local v; v=$(tr '[:lower:],' '[:upper:].' <<<"$1" | tr -d ' B')
    case $v in
        0X*) printf '%d' "$v" 2>/dev/null ;;
        *M) awk -v n="${v%M}" 'BEGIN { if (n ~ /^[0-9.]+$/) printf "%d", n * 2^20 }' ;;
        *G|*) awk -v n="${v%G}" 'BEGIN { if (n ~ /^[0-9.]+$/) printf "%d", n * 2^30 }' ;;
    esac
}
desc_vram() {
    local cur; cur=$(vram_cur)
    section
    say "$(L "Memoria de vídeo que el cargador reserva para la gráfica (${VRAMTXT}, hexadecimal)." "Video memory the loader reserves for the GPU (${VRAMTXT}, hexadecimal).")"
    say "$(L "Ahora: ${cur:-sin fichero}${cur:+ ($(vram_gb "$cur"); Linux con $(vram_left "$cur") de RAM)}." "Now: ${cur:-no file}${cur:+ ($(vram_gb "$cur"); Linux with $(vram_left "$cur") of RAM)}.")"
    say "$(L "La PS5 tiene 16 GB compartidos: lo que va a la gráfica lo pierde Linux. Puedes poner cualquier cantidad" "The PS5 has 16 GB shared: what goes to the GPU is lost to Linux. You can set any amount")"
    say "$(L "entre $(vram_gb $VRAM_MIN) y $(vram_gb $VRAM_MAX) (en pasos de 256 MB); recomendado 4 GB." "between $(vram_gb $VRAM_MIN) and $(vram_gb $VRAM_MAX) (in 256 MB steps); 4 GB recommended.")"
    say "$(L "POR QUÉ: con 512 MB (lo que pone el cargador) los juegos DirectX 12 / Unreal Engine 5 se caen a los" "WHY: with 512 MB (what the loader sets) DirectX 12 / Unreal Engine 5 games crash within")"
    say "$(L "pocos segundos ('radv/amdgpu: Not enough memory for command submission', VK_ERROR_DEVICE_LOST) y en el" "a few seconds ('radv/amdgpu: Not enough memory for command submission', VK_ERROR_DEVICE_LOST) and in")"
    say "$(L "modo juego la gráfica se reinicia. Con 4 GB funcionan y a Linux le quedan ~10,6 GB. Más de 6 GB solo" "game mode the GPU resets. With 4 GB they work and Linux keeps ~10.6 GB. More than 6 GB only")"
    say "$(L "si un juego se queda corto de VRAM (la gráfica también toma RAM prestada cuando le falta)." "if a game runs short of VRAM (the GPU also borrows RAM when it runs out).")"
    say "$(L "DESHACER: sudo cp $VRAMTXT.orig $VRAMTXT (o elige 512 MB aquí)." "UNDO: sudo cp $VRAMTXT.orig $VRAMTXT (or choose 512 MB here).")"
    say "$(L "Cuenta solo tras APAGAR y arrancar con el cargador (un reinicio en caliente no la cambia)." "Takes effect only after POWERING OFF and booting with the loader (a warm reboot does not change it).")"
}
check_vram() {
    sudo test -f "$CMDLINE" || return 2
    local cur; cur=$(vram_cur)
    if [ -n "${VRAM_SIZE:-}" ]; then [ "$cur" = "$VRAM_SIZE" ]   # the amount you chose here
    else [ -n "$cur" ] && [ "$(( cur ))" -ge $((2 << 30)) ]; fi  # nothing chosen: any 2 GB or more counts as done
}
apply_vram() {
    local c bytes cur; cur=$(vram_cur)
    if [ $ALL = 1 ]; then bytes=$(( VRAM_WANT ))
    else
        local g
        for g in 0.5 2 4 6 8; do
            bytes=$(vram_parse "$g")
            say "$(L "$(printf '%-7s' "$(vram_gb "$bytes")") → Linux con $(vram_left "$bytes") de RAM$([ "$g" = 4 ] && echo '   (recomendado)')" "$(printf '%-7s' "$(vram_gb "$bytes")") → Linux with $(vram_left "$bytes") of RAM$([ "$g" = 4 ] && echo '   (recommended)')")"
        done
        while :; do
            read -rp "$(L "  ¿Cuánta VRAM? (p. ej. 4, 3G, 1536M; Intro = $(vram_gb "$VRAM_WANT")): " "  How much VRAM? (e.g. 4, 3G, 1536M; Enter = $(vram_gb "$VRAM_WANT")): ")" c </dev/tty
            bytes=$(vram_parse "${c:-$VRAM_WANT}")
            if [ -z "$bytes" ]; then say "$(L "No entiendo «$c»." "I don't understand '$c'.")"
            elif [ "$bytes" -lt $VRAM_MIN ] || [ "$bytes" -gt $VRAM_MAX ]; then
                say "$(L "Tiene que estar entre $(vram_gb $VRAM_MIN) y $(vram_gb $VRAM_MAX)." "It must be between $(vram_gb $VRAM_MIN) and $(vram_gb $VRAM_MAX).")"
            elif [ $(( bytes % VRAM_STEP )) != 0 ]; then say "$(L "Tiene que ser múltiplo de 256 MB (p. ej. 3G, 3.25G, 1536M)." "It must be a multiple of 256 MB (e.g. 3G, 3.25G, 1536M).")"
            else break; fi
        done
    fi
    VRAM_WANT=$(printf '0x%x' "$bytes")
    remember VRAM_SIZE "$VRAM_WANT"
    sudo test -f "$VRAMTXT.orig" || { [ -n "$cur" ] && sudo cp "$VRAMTXT" "$VRAMTXT.orig"; }
    echo "$VRAM_WANT" | sudo tee "$VRAMTXT" >/dev/null || return 1
    say "$(L "VRAM: $(vram_gb "$VRAM_WANT") ($VRAM_WANT); Linux tendrá $(vram_left "$VRAM_WANT") de RAM tras el próximo arranque en frío." "VRAM: $(vram_gb "$VRAM_WANT") ($VRAM_WANT); Linux will have $(vram_left "$VRAM_WANT") of RAM after the next cold boot.")"
    COLD=1
}

# --- gpu40 ---------------------------------------------------------------------------------------
# The PS5's GPU has 40 compute units; Sony enables 36. The image's kernel can switch the other 4 on with
# amdgpu.ps5_cu_unlock=3 in cmdline.txt (its README, "40 GPU compute units"): silicon lottery, on some consoles
# they give green dots, a purple tint or crashes. Original PS5 and Slim only (a Pro's 60 are all active).
# GPU_CU (40 or 36) is what you chose here; "applied" means the console is set that way.
GPU_CU_PARAM=/sys/module/amdgpu/parameters/ps5_cu_unlock
gpu_cu_now() {                           # active compute units this boot (amdgpu logs active_cu_number)
    sudo journalctl -k -b --no-pager 2>/dev/null | grep -o 'active_cu_number[^0-9]*[0-9]\+' | tail -1 | grep -o '[0-9]\+$'
}
gpu_cu_set() { sudo grep -qE '(^| )amdgpu\.ps5_cu_unlock=[1-9]' "$CMDLINE"; }   # unlock asked for at the next boot
desc_gpu40() {
    local now; now=$(gpu_cu_now)
    section
    say "$(L "Las 40 unidades de cálculo (CU) de la GPU en vez de 36 (amdgpu.ps5_cu_unlock=3 en $CMDLINE)." "All 40 GPU compute units (CU) instead of 36 (amdgpu.ps5_cu_unlock=3 in $CMDLINE).")"
    say "$(L "Ahora: ${now:-?} activas en este arranque; en el próximo, $(gpu_cu_set && echo 40 || echo 36)." "Now: ${now:-?} active this boot; next boot, $(gpu_cu_set && echo 40 || echo 36).")"
    say "$(L "POR QUÉ: Sony apaga 4 de las 40 en fábrica, en parte porque en algunos chips alguna sale defectuosa." "WHY: Sony turns off 4 of the 40 at the factory, partly because on some chips one comes out defective.")"
    say "$(L "Es la «lotería del silicio»: en muchas consolas las 40 funcionan y la GPU rinde más (~11 % más" "It is the \"silicon lottery\": on many consoles all 40 work and the GPU performs better (~11% more")"
    say "$(L "unidades); en otras salen puntitos verdes u otros fallos gráficos, un tinte morado o cuelgues." "units); on others you get green dots or other graphical glitches, a purple tint or crashes.")"
    say "$(L "Pruébalo con varios juegos exigentes un buen rato; si ves algo de eso, vuelve a 36 aquí mismo." "Try it with several demanding games for a good while; if you see any of that, go back to 36 right here.")"
    say "$(L "Solo PS5 original y Slim (en la Pro ya están todas activas). Las actualizaciones de la imagen lo respetan." "Original PS5 and Slim only (on a Pro all are already active). Image updates respect it.")"
    say "$(L "DESHACER: vuelve a este bloque (menú 16 → gpu40) y elige 36, o copia un $CMDLINE.bak-* encima." "UNDO: come back to this block (menu 16 → gpu40) and choose 36, or copy a $CMDLINE.bak-* over it.")"
    say "$(L "Cuenta solo tras APAGAR y arrancar con el cargador. Comprobar: sudo dmesg | grep active_cu_number" "Takes effect only after POWERING OFF and booting with the loader. Check: sudo dmesg | grep active_cu_number")"
}
check_gpu40() {
    [ -e "$GPU_CU_PARAM" ] && sudo test -f "$CMDLINE" || return 2   # a kernel without the option
    local now; now=$(gpu_cu_now)
    [ -z "$now" ] || [ "$now" -lt 60 ] || return 2                  # a PS5 Pro: all its units are on
    case ${GPU_CU:-} in
        40) gpu_cu_set ;;
        36) ! gpu_cu_set ;;
        *) return 1 ;;                                              # not chosen yet
    esac
}
apply_gpu40() {
    local c def=40
    gpu_cu_set && def=36                  # asked again while on: the likely wish is to go back
    say "$(L "  40 = desbloquear las 4 unidades extra · 36 = como viene de fábrica" "  40 = unlock the 4 extra units · 36 = as it comes from the factory")"
    while :; do
        read -rp "$(L "  ¿Cuántas unidades? (40 o 36, Intro = $def): " "  How many units? (40 or 36, Enter = $def): ")" c </dev/tty
        c=${c:-$def}
        case $c in 40|36) break ;; *) say "$(L "Escribe 40 o 36." "Type 40 or 36.")" ;; esac
    done
    sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
    if [ "$c" = 40 ]; then cmd_set amdgpu.ps5_cu_unlock 3 || return 1
    else sudo sed -i -E 's/ *amdgpu\.ps5_cu_unlock=[0-9]+//' "$CMDLINE" || return 1; fi
    remember GPU_CU "$c"
    say "$(L "GPU: $c unidades tras el próximo arranque en frío. Comprueba luego: sudo dmesg | grep active_cu_number" "GPU: $c units after the next cold boot. Check afterwards: sudo dmesg | grep active_cu_number")"
    COLD=1
}

# --- zram ----------------------------------------------------------------------------------------
# Bazzite's swap is zram (compressed RAM) of half the RAM, compressed with zstd; a game that fills it has nowhere
# left to go. A drop-in overrides only the size and the compressor and leaves Bazzite's own file alone.
# Compressor, measured 2026-11-08 with Lichii (Switch 2) and Zelda OoT, RAM full: zstd stores ~2.5-3:1 but every
# page it compresses takes long enough that the game stopped at 2-5 FPS every ~25 s; lz4 stores ~1.7:1 and those
# stops went away (RAM free on average 458 MB instead of 54). zram has to compress exactly when RAM runs out.
ZRAM_DROPIN=/etc/systemd/zram-generator.conf.d/90-ps5-bazzite-toolbox.conf
ZRAM_OLD=/etc/systemd/zram-generator.conf.d/90-ps5-toolbox.conf          # its name before v1.0.0
ZRAM_LZ4_HAND=/etc/systemd/zram-generator.conf.d/91-lz4.conf             # the lz4 test by hand that this block replaces
ZRAM_WANT=${ZRAM_SIZE:-ram}
ZRAM_ALGO_WANT=${ZRAM_ALGO:-lz4}
zram_now() { swapon --show=NAME,SIZE,USED --noheadings 2>/dev/null | awk -v u="$(L usada used)" '$1 ~ /zram/ { print $2 " (" u " " $3 ")" }'; }
zram_algo_now() { sed -n 's/.*\[\([^]]*\)\].*/\1/p' /sys/block/zram0/comp_algorithm 2>/dev/null; }   # the one in [brackets]
zram_algos() { tr -d '[]' </sys/block/zram0/comp_algorithm 2>/dev/null; }    # what this kernel offers
desc_zram() {
    local now conf algo
    now=$(zram_now) algo=$(zram_algo_now)
    conf=$(sed -n 's/^zram-size *= *//p' /etc/systemd/zram-generator.conf "$ZRAM_OLD" "$ZRAM_DROPIN" 2>/dev/null | tail -1)
    section
    say "$(L "La swap zram: memoria que se comprime dentro de la propia RAM cuando falta. Dos cosas: su tamaño y el" "The zram swap: memory that is compressed inside the RAM itself when it runs short. Two things: its size and the")"
    say "$(L "compresor." "compressor.")"
    say "$(L "Ahora: ${now:-sin zram}${conf:+, configurada como zram-size = $conf}${algo:+, comprime con $algo}." "Now: ${now:-no zram}${conf:+, set as zram-size = $conf}${algo:+, compresses with $algo}.")"
    say "$(L "Propuesta: zram-size = $ZRAM_WANT (toda la RAM de Linux, como SteamOS) y compresor $ZRAM_ALGO_WANT, en $ZRAM_DROPIN." "Proposal: zram-size = $ZRAM_WANT (all of Linux's RAM, like SteamOS) and compressor $ZRAM_ALGO_WANT, in $ZRAM_DROPIN.")"
    say "$(L "POR QUÉ el tamaño: Bazzite pone la mitad. Un juego grande (p. ej. un Unreal Engine 5 con 6 GB de VRAM) la" "WHY the size: Bazzite sets half. A big game (e.g. an Unreal Engine 5 one with 6 GB of VRAM) fills it")"
    say "$(L "llena y a partir de ahí, sin swap libre, el sistema cierra el juego si pide más. No reserva nada: solo gasta" "and from then on, with no free swap, the system kills the game if it asks for more. It reserves nothing: it only uses")"
    say "$(L "RAM cuando se usa. No se añade swap en el disco USB aquí (eso es el bloque swapdisco, aparte)." "RAM when used. No swap is added on the USB disk here (that is the swapdisco block, separate).")"
    say "$(L "POR QUÉ el compresor: la zram comprime justo cuando se acaba la RAM, normalmente jugando, y mientras" "WHY the compressor: zram compresses exactly when RAM runs out, usually while gaming, and while")"
    say "$(L "comprime el juego espera. Los que hay:" "it compresses the game waits. The options:")"
    say "$(L "  lz4     muy rápido (varias veces más que zstd) y guarda menos (~1,7-2 a 1). Los tirones por memoria se" "  lz4     very fast (several times faster than zstd) and stores less (~1.7-2 to 1). Memory stutters")"
    say "$(L "          quedan en casi nada. RECOMENDADO para jugar: con Zelda OoT en Lichii quitó las caídas a 2-5 FPS." "          almost vanish. RECOMMENDED for gaming: with Zelda OoT on Lichii it removed the drops to 2-5 FPS.")"
    say "$(L "  zstd    el de Bazzite: guarda más (~2,5-3 a 1), pero cada compresión tarda más; con la RAM llena se nota" "  zstd    Bazzite's: stores more (~2.5-3 to 1), but each compression takes longer; with RAM full it shows")"
    say "$(L "          como tirones. Mejor si usas el escritorio con muchas cosas abiertas y la CPU va sobrada." "          as stutters. Better if you use the desktop with lots open and the CPU has headroom.")"
    say "$(L "  lzo-rle el del kernel: rápido (algo menos que lz4) y guarda parecido a lz4. Alternativa a lz4." "  lzo-rle the kernel's: fast (slightly less than lz4) and stores similar to lz4. Alternative to lz4.")"
    say "$(L "DESHACER: sudo rm $ZRAM_DROPIN y reinicia (vuelve a la mitad de la RAM y zstd)." "UNDO: sudo rm $ZRAM_DROPIN and reboot (back to half the RAM and zstd).")"
    say "$(L "Cuenta tras reiniciar (también el reinicio en caliente): la zram se crea al arrancar." "Takes effect after a reboot (a warm reboot too): zram is created at boot.")"
}
check_zram() {
    [ -x /usr/lib/systemd/system-generators/zram-generator ] || return 2
    grep -qs "^zram-size = $ZRAM_WANT\$" "$ZRAM_DROPIN" "$ZRAM_OLD" || return 1
    grep -qs "^compression-algorithm = $ZRAM_ALGO_WANT\$" "$ZRAM_DROPIN" || return 1
    [ ! -e "$ZRAM_LZ4_HAND" ]                # a later drop-in would override this one's compressor
}
apply_zram() {
    local avail
    value ZRAM_SIZE "$(L "Tamaño (ram = toda la RAM; ram / 2 = lo de Bazzite; o en MB, p. ej. 6144)" "Size (ram = all the RAM; ram / 2 = Bazzite's; or in MB, e.g. 6144)")" "$ZRAM_WANT"
    ZRAM_WANT=${ZRAM_SIZE:-ram}
    avail=$(zram_algos)
    value ZRAM_ALGO "$(L "Compresor (lz4 = menos tirones, recomendado; zstd = guarda más, el de Bazzite; lzo-rle)" "Compressor (lz4 = fewer stutters, recommended; zstd = stores more, Bazzite's; lzo-rle)")" "$ZRAM_ALGO_WANT"
    ZRAM_ALGO_WANT=${ZRAM_ALGO:-lz4}
    if [ -n "$avail" ] && ! grep -qw -- "$ZRAM_ALGO_WANT" <<<"$avail"; then
        say "$(L "Este kernel no tiene «$ZRAM_ALGO_WANT». Disponibles: $avail" "This kernel has no '$ZRAM_ALGO_WANT'. Available: $avail")"; return 1
    fi
    sudo mkdir -p "$(dirname "$ZRAM_DROPIN")" &&
        printf '# ps5-bazzite-toolbox (bloque zram): overrides the size and compressor in /etc/systemd/zram-generator.conf\n[zram0]\nzram-size = %s\ncompression-algorithm = %s\n' \
            "$ZRAM_WANT" "$ZRAM_ALGO_WANT" | sudo tee "$ZRAM_DROPIN" >/dev/null && sudo rm -f "$ZRAM_OLD" "$ZRAM_LZ4_HAND" || return 1
    say "$(L "zram: $ZRAM_WANT con $ZRAM_ALGO_WANT tras el próximo reinicio (ahora: $(zram_algo_now || echo '?'))." "zram: $ZRAM_WANT with $ZRAM_ALGO_WANT after the next reboot (now: $(zram_algo_now || echo '?')).")"
    REBOOT=1
}

# --- swap on disk ----------------------------------------------------------------------------------
# A swap file behind the zram (lower priority): used only once the zram is full, so a game that runs out of
# memory slows down instead of being killed by the kernel (OOM). Off by default: on a USB boot drive heavy
# swapping can stall the whole system. Measured 2026-11-08 (Lichii, Zelda OoT): without it OOM-killed after
# 9 min; with it the 16 GB file took only the peak (31 MB) and nothing stalled.
SWAPFILE=/var/swapfile
SWAP_MARK='# ps5-bazzite-toolbox (bloque swapdisco)'
SWAP_GB=${SWAP_GB:-16}
swapfile_gb() {                          # size of the active swap file in GB, or nothing
    awk -v f="$SWAPFILE" '$1 == f { printf "%d\n", $3 / 1048576 + 0.5 }' /proc/swaps 2>/dev/null
}
desc_swapdisco() {
    local now usb fs
    now=$(swapfile_gb) usb=$(root_usb) fs=$(findmnt -no FSTYPE -T /var 2>/dev/null)
    section
    say "$(L "Swap en el disco: un fichero de intercambio ($SWAPFILE) DETRÁS de la zram. La zram se sigue usando" "Swap on disk: a swap file ($SWAPFILE) BEHIND the zram. The zram is still used")"
    say "$(L "primero (prioridad 100); el disco (prioridad 10) solo cuando la zram se ha llenado." "first (priority 100); the disk (priority 10) only once the zram is full.")"
    say "$(L "Ahora: $([ -n "$now" ] && echo "$now GB activos" || echo 'sin swap en disco'); disco del sistema: ${fs:-?}$([ -n "$usb" ] && echo ', por USB')." "Now: $([ -n "$now" ] && echo "$now GB active" || echo 'no disk swap'); system disk: ${fs:-?}$([ -n "$usb" ] && echo ', over USB').")"
    say "$(L "POR QUÉ: con la zram llena, si un programa pide más memoria el sistema lo cierra («escasez de memoria" "WHY: with the zram full, if a program asks for more memory the system kills it (\"out of memory")"
    say "$(L "evitada»). Con swap en disco el juego va más lento en esos picos, pero no se cierra. Útil para emuladores" "avoided\"). With disk swap the game runs slower at those peaks, but is not killed. Useful for emulators")"
    say "$(L "que se pasan de memoria (Switch 2: Lichii con Zelda OoT pide más de 14 GB)." "that overrun memory (Switch 2: Lichii with Zelda OoT asks for more than 14 GB).")"
    say "$(L "RIESGO: si el disco va por USB y se escribe mucho en la swap, los atascos del USB pueden congelar todo el" "RISK: if the disk is on USB and a lot is written to swap, USB stalls can freeze the whole")"
    say "$(L "sistema unos segundos. Si notas eso (ratón parado), quítala. Ocupa en el disco el tamaño que elijas." "system for a few seconds. If you notice that (mouse stuck), remove it. It takes the size you choose on the disk.")"
    say "$(L "DESHACER: este bloque con tamaño 0 (menú 16 → swapdisco), o a mano: sudo swapoff $SWAPFILE;" "UNDO: this block with size 0 (menu 16 → swapdisco), or by hand: sudo swapoff $SWAPFILE;")"
    say "sudo sed -i '\\|^$SWAP_MARK\$|,+1d' /etc/fstab; sudo rm $SWAPFILE"
}
check_swapdisco() {
    case $(findmnt -no FSTYPE -T /var 2>/dev/null) in ext4|xfs|btrfs) ;; *) return 2 ;; esac
    [ "${SWAP_GB:-16}" = 0 ] && { [ -z "$(swapfile_gb)" ]; return; }
    [ "$(swapfile_gb)" = "$SWAP_GB" ] && grep -qs "^$SWAPFILE " /etc/fstab
}
apply_swapdisco() {
    local fs free
    value SWAP_GB "$(L "Tamaño en GB (8, 16, 24 o 32; 16 recomendado; 0 = quitarla)" "Size in GB (8, 16, 24 or 32; 16 recommended; 0 = remove it)")" "$SWAP_GB"
    [[ $SWAP_GB =~ ^[0-9]+$ ]] || { say "$(L "Tamaño no válido: $SWAP_GB" "Invalid size: $SWAP_GB")"; return 1; }
    if [ -e "$SWAPFILE" ] || grep -qs "^$SWAPFILE " /etc/fstab; then
        say "$(L "Quitando la swap en disco que había..." "Removing the existing disk swap...")"
        sudo swapoff "$SWAPFILE" 2>/dev/null
        sudo sed -i -e "\\|^# .*swap.*\$|{N;\\|\\n$SWAPFILE |d}" -e "\\|^$SWAPFILE |d" /etc/fstab || return 1
        sudo rm -f "$SWAPFILE" || return 1
    fi
    [ "$SWAP_GB" = 0 ] && { say "$(L "Swap en disco quitada." "Disk swap removed.")"; return 0; }
    fs=$(findmnt -no FSTYPE -T /var) free=$(df -BG --output=avail /var | tail -1 | tr -dc 0-9)
    [ "$free" -gt $((SWAP_GB + 20)) ] || { say "$(L "No hay sitio: $free GB libres y hacen falta $SWAP_GB + 20 de margen." "Not enough room: $free GB free and $SWAP_GB + 20 of margin are needed.")"; return 1; }
    say "$(L "Creando $SWAPFILE de $SWAP_GB GB (un par de minutos)..." "Creating $SWAPFILE of $SWAP_GB GB (a couple of minutes)...")"
    if [ "$fs" = btrfs ]; then           # btrfs needs it without copy-on-write; its own tool does that
        sudo btrfs filesystem mkswapfile --size "${SWAP_GB}g" "$SWAPFILE" >/dev/null || return 1
    else                                 # dd, not fallocate: a swap file must have no holes
        sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((SWAP_GB * 1024)) status=progress || return 1
        sudo chmod 600 "$SWAPFILE" && sudo mkswap "$SWAPFILE" >/dev/null || return 1
    fi
    sudo swapon -p 10 "$SWAPFILE" || return 1
    printf '%s\n%s none swap defaults,pri=10,nofail 0 0\n' "$SWAP_MARK" "$SWAPFILE" | sudo tee -a /etc/fstab >/dev/null || return 1
    say "$(L "Swap en disco: $SWAP_GB GB activos, detrás de la zram (se mantiene al reiniciar)." "Disk swap: $SWAP_GB GB active, behind the zram (kept across reboots).")"
}

# --- fans ----------------------------------------------------------------------------------------
# Two separate knobs: ps5fan (ps5-linux-tools) only switches the console's own fan controller on (servo
# pattern 1 via /dev/icc); how hard it cools is that controller's target temperature (the image's ps5-fan
# driver, /sys/.../target_temp, 80 °C from the factory), which the image's ps5-perf sets from FAN_TARGET.
# So ps5fan and ps5-perf don't fight over the fan: with ps5fan, ps5-perf is kept for the target only
# (CPU_BOOST=0, ps5boost does the boost).
# v2.8 took target_temp and `ps5-perf fan` out; v2.8.1+ has the target as a boot parameter instead,
# ps5_fan.target= in cmdline.txt (40 to Sony's 91, 0 = Sony's; 80 when absent), read-only once booted.
FAN_SYS=/sys/bus/platform/devices/ps5-fan/target_temp
FAN_PARAM=/sys/module/ps5_fan/parameters/target
has_perf() { command -v ps5-perf >/dev/null; }
fan_mode() { echo "${FAN_MODE:-$(systemctl is-enabled -q ps5fan.service 2>/dev/null && echo tools || { has_perf && echo perf || echo tools; })}"; }
fan_now() { if [ -e "$FAN_PARAM" ]; then cat "$FAN_PARAM"; else cat "$FAN_SYS"; fi 2>/dev/null; }
fan_cmdline_ok() {                       # the boot parameter matches FAN_TARGET (none for the image's 80)
    if [ -n "${FAN_TARGET:-}" ]; then cmd_has "ps5_fan.target=$FAN_TARGET"; else ! sudo grep -q 'ps5_fan\.target=' "$CMDLINE"; fi
}
perf_set() {                             # perf_set KEY [VALUE] -> sets (or with no value removes) KEY in perf.conf
    sudo mkdir -p "$(dirname "$PERFCONF")" && sudo touch "$PERFCONF" && sudo sed -i "/^$1=/d" "$PERFCONF" || return 1
    [ $# -lt 2 ] || [ -z "$2" ] || echo "$1=$2" | sudo tee -a "$PERFCONF" >/dev/null
}
desc_fans() {
    section
    say "$(L "Ventilador y frecuencia de la CPU. Dos formas de encender el control del ventilador, no a la vez:" "Fan and CPU frequency. Two ways to turn on fan control, not at the same time:")"
    has_perf && say "$(L "- perf: ps5-perf, el que trae la imagen (v1.5.0+): boost de CPU y temperatura objetivo del" "- perf: ps5-perf, the one the image ships (v1.5.0+): CPU boost and fan target temperature.")" \
                    "$(L "  ventilador. Nada que instalar y se actualiza con la imagen. Ajustes en $PERFCONF." "  Nothing to install and it updates with the image. Settings in $PERFCONF.")"
    say "$(L "- tools: ps5fan y ps5boost de ps5-linux-tools ($TOOLS_REPO, revisión $TOOLS_COMMIT): encienden el" "- tools: ps5fan and ps5boost from ps5-linux-tools ($TOOLS_REPO, revision $TOOLS_COMMIT): turn on the")"
    say "$(L "  control del ventilador de la consola (~45 °C en reposo) y ponen CPU/GPU al máximo. Se compila aquí" "  console's fan control (~45 °C at idle) and set CPU/GPU to the maximum. Built here")"
    say "$(L "  (instala gcc, make y git con dnf)." "  (installs gcc, make and git with dnf).")"
    say "$(L "Y en los dos casos, la TEMPERATURA OBJETIVO: el ventilador acelera para no pasar de ella. La de fábrica" "And in both cases, the TARGET TEMPERATURE: the fan speeds up to stay under it. The factory one")"
    say "$(L "es 80 °C (silencioso, el chip llega a ~80 jugando); 70 °C enfría más con algo más de ruido." "is 80 °C (quiet, the chip reaches ~80 while gaming); 70 °C cools more with a bit more noise.")"
    has_perf && [ ! -e "$FAN_PARAM" ] && say "$(L "  Con tools, ps5-perf solo fija esa temperatura (CPU_BOOST=0: el boost lo hace ps5boost)." "  With tools, ps5-perf only sets that temperature (CPU_BOOST=0: ps5boost does the boost).")"
    [ -e "$FAN_PARAM" ] && say "$(L "  En esta imagen (v2.8.1+) el objetivo es un parámetro de arranque, ps5_fan.target= en $CMDLINE" "  On this image (v2.8.1+) the target is a boot parameter, ps5_fan.target= in $CMDLINE")" \
                             "$(L "  (con copia previa): cuenta desde el siguiente reinicio. Sin él, la imagen usa 80 °C." "  (backed up first): takes effect from the next reboot. Without it, the image uses 80 °C.")"
    say "$(L "Ahora: $(fan_mode), objetivo $(fan_now || echo '?') °C${FAN_TARGET:+ (elegido: $FAN_TARGET)}." "Now: $(fan_mode), target $(fan_now || echo '?') °C${FAN_TARGET:+ (chosen: $FAN_TARGET)}.")"
    say "$(L "DESHACER: perf → ps5-perf off; tools → sudo systemctl disable --now ps5fan ps5boost; objetivo → vacío aquí." "UNDO: perf → ps5-perf off; tools → sudo systemctl disable --now ps5fan ps5boost; target → empty here.")"
}
fan_target_ask() {                       # fan_target_ask LO HI -> FAN_TARGET in range, or empty for the default 80
    local t
    while :; do
        value FAN_TARGET "$(L "Temperatura objetivo del ventilador en °C ($1-$2; '-' = la de fábrica, 80)" "Fan target temperature in °C ($1-$2; '-' = factory default, 80)")" "${FAN_TARGET:-80}"
        t=$FAN_TARGET; [ "$t" = 80 ] && { remember FAN_TARGET ''; t=''; }
        [ -z "$t" ] || { [[ $t =~ ^[0-9]+$ ]] && [ "$t" -ge "$1" ] && [ "$t" -le "$2" ]; } && break
        say "$(L "Tiene que ser un número entre $1 y $2." "It must be a number between $1 and $2.")"
    done
}
check_fans() {
    local m; m=$(fan_mode)
    if [ "$m" = perf ]; then
        has_perf || return 1
        ! systemctl is-enabled -q ps5fan.service 2>/dev/null && ps5-perf status 2>/dev/null | grep >/dev/null ': on' || return 1
    else
        systemctl is-enabled -q ps5fan.service 2>/dev/null && systemctl is-enabled -q ps5boost.service 2>/dev/null || return 1
        # ps5-perf off, or on only for the fan target
        ! has_perf || ps5-perf status 2>/dev/null | grep >/dev/null ': off' ||
            sudo grep -qx 'CPU_BOOST=0' "$PERFCONF" 2>/dev/null || return 1
    fi
    if [ -e "$FAN_PARAM" ]; then fan_cmdline_ok
    else [ -z "${FAN_TARGET:-}" ] || [ "$(fan_now)" = "$FAN_TARGET" ]; fi
}
apply_fans() {
    local m; m=$(fan_mode)
    has_perf && value FAN_MODE "$(L "¿perf o tools?" "perf or tools?")" "$m"; m=${FAN_MODE:-tools}
    if [ -e "$FAN_PARAM" ]; then fan_target_ask 60 91
    elif has_perf && [ -e "$FAN_SYS" ]; then fan_target_ask 60 85; fi
    if [ "$m" = perf ]; then
        sudo systemctl disable --now ps5fan.service ps5boost.service 2>/dev/null
        perf_set CPU_BOOST && perf_set FAN_TARGET "${FAN_TARGET:-}" || return 1
        ps5-perf on && sudo systemctl enable ps5-perf.service
    else
        remember FAN_MODE tools
        if [ ! -x /usr/local/sbin/ps5_control ]; then
            sudo dnf5 install -y gcc make git || return 1
            [ -d ~/ps5-linux-tools/.git ] || git clone "$TOOLS_REPO" ~/ps5-linux-tools || return 1
            git -C ~/ps5-linux-tools checkout -q "$TOOLS_COMMIT" || return 1
            (cd ~/ps5-linux-tools && sudo ./install.sh) || return 1
        fi
        sudo systemctl enable --now ps5fan.service ps5boost.service || return 1
        if has_perf; then
            if [ -n "${FAN_TARGET:-}" ]; then      # ps5-perf only for the target: no CPU boost of its own
                perf_set CPU_BOOST 0 && perf_set FAN_TARGET "$FAN_TARGET" && ps5-perf on >/dev/null &&
                    sudo systemctl enable ps5-perf.service
            else
                perf_set FAN_TARGET && perf_set CPU_BOOST && ps5-perf off >/dev/null
            fi
        fi
    fi
    if [ -e "$FAN_PARAM" ] && ! fan_cmdline_ok; then
        sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
        if [ -n "${FAN_TARGET:-}" ]; then cmd_set ps5_fan.target "$FAN_TARGET" || return 1
        else sudo sed -i -E 's/ *ps5_fan\.target=[^ ]*//' "$CMDLINE" || return 1; fi
        say "$(L "Objetivo ahora: $(fan_now || echo '?') °C; desde el siguiente reinicio: ${FAN_TARGET:-80} °C." "Target now: $(fan_now || echo '?') °C; from the next reboot: ${FAN_TARGET:-80} °C.")"
        REBOOT=1
        return 0
    fi
    say "$(L "Objetivo del ventilador ahora: $(fan_now || echo '?') °C." "Fan target now: $(fan_now || echo '?') °C.")"
}

# --- cpufreq -------------------------------------------------------------------------------------
# The image's CPU frequency driver (ps5-cpufreq) lets schedutil re-evaluate every 75 us. At rest that is ~275
# frequency changes a second; the governor's kthread (sugov:0) takes ~20 % of a core and the cores hover at
# 2.3-2.6 GHz instead of resting at 800 MHz: heat the fan has to remove. With 10 ms: ~90 changes a second,
# sugov ~8 %, cores at ~1.25 GHz on average (v2.10, 2026-11-10). Games still get full speed.
# It is a kernel setting that resets at every boot, so a small service writes it at startup.
CPUFREQ_RATE=10000
CPUFREQ_KNOB=/sys/devices/system/cpu/cpufreq/schedutil/rate_limit_us
cpufreq_now() { cat "$CPUFREQ_KNOB" 2>/dev/null; }
desc_cpufreq() {
    section
    say "$(L "Instala ps5-cpufreq-calm: al arrancar pone el regulador de frecuencia de la CPU (schedutil) a revisar" "Installs ps5-cpufreq-calm: at boot it sets the CPU frequency governor (schedutil) to re-evaluate")"
    say "$(L "la frecuencia como mucho cada $((CPUFREQ_RATE / 1000)) ms ($CPUFREQ_KNOB = $CPUFREQ_RATE)." "the frequency at most every $((CPUFREQ_RATE / 1000)) ms ($CPUFREQ_KNOB = $CPUFREQ_RATE).")"
    say "$(L "POR QUÉ: el driver de la imagen le deja revisarla cada 0,075 ms. En reposo eso son unos 275 cambios" "WHY: the image's driver lets it re-evaluate every 0.075 ms. At idle that is about 275 frequency")"
    say "$(L "de frecuencia por segundo: el propio regulador (sugov:0) gasta ~20 % de un núcleo y los núcleos no" "changes per second: the governor itself (sugov:0) uses ~20% of a core and the cores do not")"
    say "$(L "bajan de 2,3-2,6 GHz. Con $((CPUFREQ_RATE / 1000)) ms: ~90 cambios por segundo, ~8 % y ~1,25 GHz de media," "drop below 2.3-2.6 GHz. With $((CPUFREQ_RATE / 1000)) ms: ~90 changes per second, ~8% and ~1.25 GHz on average,")"
    say "$(L "así que hay menos calor y menos ventilador en reposo. Jugando, la CPU sigue subiendo a su máximo." "so there is less heat and less fan at idle. While gaming, the CPU still goes up to its maximum.")"
    say "$(L "Ahora: $(cpufreq_now) µs." "Now: $(cpufreq_now) µs.")"
    say "$(L "DESHACER: sudo systemctl disable ps5-cpufreq-calm (cuenta desde el siguiente arranque)." "UNDO: sudo systemctl disable ps5-cpufreq-calm (takes effect from the next boot).")"
}
check_cpufreq() {
    [ -e "$CPUFREQ_KNOB" ] || return 2   # another governor, or a kernel without the knob
    [ -x /usr/local/sbin/ps5-cpufreq-calm ] && systemctl is-enabled -q ps5-cpufreq-calm.service 2>/dev/null &&
        [ "$(cpufreq_now)" = "$CPUFREQ_RATE" ]
}
apply_cpufreq() {
    sudo tee /usr/local/sbin/ps5-cpufreq-calm >/dev/null <<CALM || return 1
#!/bin/bash
# Let schedutil re-evaluate the CPU frequency at most every $CPUFREQ_RATE us instead of the driver's 75 us.
# Installed by ps5-bazzite-toolbox.sh (block cpufreq). Log: journalctl -b -u ps5-cpufreq-calm
K=$CPUFREQ_KNOB
for _ in \$(seq 30); do [ -w "\$K" ] && break; sleep 1; done
[ -w "\$K" ] || { echo "\$K isn't there (governor not schedutil?): nothing to do"; exit 0; }
echo $CPUFREQ_RATE >"\$K" && echo "schedutil rate_limit_us: \$(cat "\$K")"
CALM
    sudo chmod 755 /usr/local/sbin/ps5-cpufreq-calm &&
    sudo tee /etc/systemd/system/ps5-cpufreq-calm.service >/dev/null <<'UNIT' || return 1
[Unit]
Description=Calm the CPU frequency governor (schedutil rate limit, ps5-bazzite-toolbox)
After=systemd-modules-load.service ps5-perf.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ps5-cpufreq-calm
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    sudo systemctl daemon-reload && sudo systemctl enable --now ps5-cpufreq-calm.service
}

# --- warmreboot ----------------------------------------------------------------------------------
desc_warmreboot() {
    section
    say "$(L "Reinicio en caliente (ps5-warm-reboot on): al reiniciar desde Steam, el escritorio o sudo reboot," "Warm reboot (ps5-warm-reboot on): when you reboot from Steam, the desktop or sudo reboot,")"
    say "$(L "vuelve directo a Linux en ~20 s, sin pasar por el sistema de la PS5 ni el cargador." "it comes straight back to Linux in ~20 s, without going through the PS5 system or the loader.")"
    say "$(L "Apagar sigue siendo apagar: tras un apagado hace falta el cargador." "Power off is still power off: after a shutdown you need the loader.")"
    say "$(L "POR QUÉ: comodidad. Es experimental: en algunas consolas la imagen sale en negro o corrupta" "WHY: convenience. It is experimental: on some consoles the picture comes up black or corrupt")"
    say "$(L "(el bloque hdmi lo arregla) y tras actualizar el kernel hay que APAGAR, no reiniciar." "(the hdmi block fixes that) and after a kernel update you must POWER OFF, not reboot.")"
    say "$(L "DESHACER: ps5-warm-reboot off." "UNDO: ps5-warm-reboot off.")"
}
check_warmreboot() {
    command -v ps5-warm-reboot >/dev/null || return 2
    if [ "${WARM_REBOOT:-}" = off ]; then ! warm_on; else warm_on; fi
}
apply_warmreboot() { remember WARM_REBOOT on; ps5-warm-reboot on; }

# --- hdmi ----------------------------------------------------------------------------------------
desc_hdmi() {
    section
    say "$(L "Instala ps5-hdmi-kick: en cada arranque, cuando aparece el modo juego, cambia a otra consola" "Installs ps5-hdmi-kick: on every boot, once Game Mode is up, it switches to another text console")"
    say "$(L "de texto y vuelve (chvt 2; chvt 1)." "and back (chvt 2; chvt 1).")"
    say "$(L "POR QUÉ: tras un reinicio en caliente la salida HDMI a veces se queda en negro aunque todo" "WHY: after a warm reboot the HDMI output sometimes stays black although everything is")"
    say "$(L "funcione; ese cambio de consola la recupera (es el truco del README del autor)." "running; that console switch recovers it (it is the trick from the author's README).")"
    say "$(L "Recomendado solo si usas el reinicio en caliente ($(warm_on && echo 'lo tienes activado' || echo 'no lo tienes activado'))." "Recommended only if you use warm reboot ($(warm_on && echo 'you have it enabled' || echo 'you do not have it enabled')).")"
    say "$(L "DESHACER: sudo systemctl disable ps5-hdmi-kick." "UNDO: sudo systemctl disable ps5-hdmi-kick.")"
}
check_hdmi() {
    [ -x /usr/local/sbin/ps5-hdmi-kick ] && systemctl is-enabled -q ps5-hdmi-kick.service 2>/dev/null
}
apply_hdmi() {
    sudo tee /usr/local/sbin/ps5-hdmi-kick >/dev/null <<'EOF' || return 1
#!/bin/sh
# After a warm reboot (kexec) the PS5's HDMI output sometimes comes up black although the system
# and Game Mode are running; switching to another VT and back sets the picture up again (README of
# VivaLaVent/ps5-bazzite-deck). Do that once per boot, automatically, when gamescope is up.
# Log: journalctl -b -u ps5-hdmi-kick
for _ in $(seq 90); do                      # wait up to 90 s for Game Mode (or the desktop)
    pgrep -x gamescope-wl >/dev/null || pgrep -x kwin_wayland >/dev/null && break
    sleep 1
done
sleep 5                                     # let the session take the display first
VT=$(fgconsole 2>/dev/null || echo 1)
[ "$VT" = 2 ] && VT=1
echo "switching VT $VT -> 2 -> $VT to re-arm HDMI"
chvt 2
sleep 3
chvt "$VT"
EOF
    sudo chmod 755 /usr/local/sbin/ps5-hdmi-kick &&
    sudo tee /etc/systemd/system/ps5-hdmi-kick.service >/dev/null <<'EOF' || return 1
[Unit]
Description=Re-arm the PS5 HDMI output once Game Mode is up (VT switch)
After=graphical.target sddm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ps5-hdmi-kick
TimeoutStartSec=150

[Install]
WantedBy=graphical.target
EOF
    sudo systemctl daemon-reload && sudo systemctl enable ps5-hdmi-kick.service
}

# --- arranque ------------------------------------------------------------------------------------
# Plymouth's splash only shows the logo, and once held a boot for 3 minutes until a VT switch. NOT cardwired, although
# it delays graphical.target ~10 s: Game Mode starts Steam through "cardwire launch" (gamescope-session-plus), which
# needs the daemon; without it the session dies, Bazzite resets Steam and falls back to the desktop.
# Earlier test builds masked it: unmask it here.
cardwired_masked() { [ "$(systemctl is-enabled cardwired.service 2>/dev/null)" = masked ]; }
desc_arranque() {
    section
    say "$(L "Arranque sin la pantalla de carga (plymouth): solo pone el logo. Con plymouth.enable=0 rd.plymouth=0 en" "Boot without the loading screen (plymouth): it only shows the logo. With plymouth.enable=0 rd.plymouth=0 in")"
    say "$(L "$CMDLINE verás el texto del arranque en su lugar." "$CMDLINE you will see the boot text instead.")"
    cardwired_masked && say "$(L "Y vuelve a activar cardwired, que una versión de prueba quitaba: el modo juego lo necesita." "It also re-enables cardwired, which a test build removed: Game Mode needs it.")"
    say "$(L "POR QUÉ: una vez dejó el arranque parado 3 minutos hasta pulsar Ctrl+Alt+F3, y no aporta nada." "WHY: once it left the boot stuck for 3 minutes until Ctrl+Alt+F3 was pressed, and it adds nothing.")"
    say "$(L "DESHACER: quita plymouth.enable=0 rd.plymouth=0 de $CMDLINE (o copia un $CMDLINE.bak-* encima)." "UNDO: remove plymouth.enable=0 rd.plymouth=0 from $CMDLINE (or copy a $CMDLINE.bak-* over it).")"
    say "$(L "Cuenta a partir del siguiente arranque." "Takes effect from the next boot.")"
}
check_arranque() {
    sudo test -f "$CMDLINE" || return 2
    cmd_has plymouth.enable=0 && cmd_has rd.plymouth=0 && ! cardwired_masked
}
apply_arranque() {
    if sudo test -f "$CMDLINE" && ! { cmd_has plymouth.enable=0 && cmd_has rd.plymouth=0; }; then
        sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
        cmd_set plymouth.enable 0 && cmd_set rd.plymouth 0 || return 1
        say "$(L "Ahora: $(sudo cat "$CMDLINE")" "Now: $(sudo cat "$CMDLINE")")"
    fi
    if cardwired_masked; then sudo systemctl unmask cardwired.service && sudo systemctl start cardwired.service || return 1; fi
    REBOOT=1
}

# --- bt ------------------------------------------------------------------------------------------
# The IW620's Bluetooth can fail its first reset at boot ("hci0: Opcode 0x0c03 failed: -110"): bluetoothd
# then starts with no adapter. The image's ps5-bt-revive only looks for "command ... tx timeout", so it says
# "adapter OK" and nothing happens. ps5-bt-guard checks what matters - does bluetoothd have a controller? -
# and reloads btusb if not (an adapter you switched off still counts as present, so it's left alone).
bt_present() { timeout 5 bluetoothctl list 2>/dev/null | grep >/dev/null '^Controller'; }
desc_bt() {
    section
    say "$(L "Instala ps5-bt-guard: al arrancar y al despertar comprueba que el Bluetooth tiene adaptador y, si" "Installs ps5-bt-guard: at boot and on wake it checks that Bluetooth has an adapter and, if")"
    say "$(L "no, recarga su driver (btusb) hasta dos veces. Si lo apagaste tú, no lo toca." "not, reloads its driver (btusb) up to twice. If you switched it off yourself, it leaves it alone.")"
    say "$(L "POR QUÉ: a veces el chip IW620 no responde a su primer reinicio al arrancar ('hci0: Opcode 0x0c03" "WHY: sometimes the IW620 chip does not answer its first reset at boot ('hci0: Opcode 0x0c03")"
    say "$(L "failed: -110') y el Bluetooth se queda sin adaptador: el mando no conecta y 'bluetoothctl' dice" "failed: -110') and Bluetooth is left with no adapter: the controller can't connect and 'bluetoothctl' says")"
    say "$(L "'No default controller available'. El ps5-bt-revive de la imagen no reconoce ese error." "'No default controller available'. The image's ps5-bt-revive does not recognise that error.")"
    say "$(L "Ahora: adaptador $(bt_present && echo presente || echo AUSENTE)." "Now: adapter $(bt_present && echo present || echo ABSENT).")"
    say "$(L "DESHACER: sudo systemctl disable ps5-bt-guard." "UNDO: sudo systemctl disable ps5-bt-guard.")"
}
check_bt() {
    lsusb -d 1286:2059 >/dev/null 2>&1 || return 2   # only the IW620 (original PS5)
    [ -x /usr/local/sbin/ps5-bt-guard ] && systemctl is-enabled -q ps5-bt-guard.service 2>/dev/null
}
apply_bt() {
    sudo tee /usr/local/sbin/ps5-bt-guard >/dev/null <<'EOF' || return 1
#!/bin/bash
# Make sure bluetoothd has an adapter; if the IW620 failed its reset at boot (or after sleep), reload btusb.
# Installed by ps5-bazzite-toolbox.sh (block bt). Log: journalctl -b -u ps5-bt-guard
present() { timeout 5 bluetoothctl list 2>/dev/null | grep >/dev/null '^Controller'; }
for _ in $(seq 6); do present && { echo "Bluetooth adapter present"; exit 0; }; sleep 5; done
for try in 1 2; do
    echo "No Bluetooth adapter: reloading btusb (attempt $try)"
    modprobe -r btusb 2>/dev/null || { echo "btusb can't be unloaded"; exit 0; }
    sleep 2
    modprobe btusb
    for _ in $(seq 6); do sleep 5; present && { echo "Bluetooth adapter back"; exit 0; }; done
done
echo "Bluetooth adapter still missing: power off and start with the loader (a cold start resets the chip)"
EOF
    sudo chmod 755 /usr/local/sbin/ps5-bt-guard &&
    sudo tee /etc/systemd/system/ps5-bt-guard.service >/dev/null <<'EOF' || return 1
[Unit]
Description=Reload btusb if Bluetooth has no adapter (IW620 failed reset at boot or after sleep)
After=bluetooth.service ps5-bt-revive.service suspend.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/ps5-bt-guard
TimeoutStartSec=150

[Install]
WantedBy=multi-user.target suspend.target
EOF
    sudo systemctl daemon-reload && sudo systemctl enable ps5-bt-guard.service
}

# --- steambt -------------------------------------------------------------------------------------
# Steam keeps its Bluetooth switch in config.vdf ("System" > "Bluetooth" > "Enabled") and, with "0", powers the
# adapter down every time Game Mode starts: the controller can't connect. A Steam reset (gamescope-session-plus's
# short_session_recover after 5 quick crashes) leaves it at "0". Steam rewrites config.vdf on exit, so it is put
# back to "1" by a user unit that runs before each Game Mode session, while Steam is closed.
STEAM_CFG=$HOME/.local/share/Steam/config/config.vdf
STEAMBT_SH=$HOME/.local/share/ps5-bazzite-toolbox/steam-bt-on.sh
STEAMBT_UNIT=$HOME/.config/systemd/user/ps5-steam-bt.service
steambt_now() { awk '/"Bluetooth"/{b=1} b && /"Enabled"/{gsub(/[^0-9]/,""); print; exit}' "$STEAM_CFG" 2>/dev/null; }
desc_steambt() {
    section
    say "$(L "Deja el Bluetooth de Steam siempre activado: antes de cada arranque del modo juego, si en su" "Keeps Steam's Bluetooth always on: before each Game Mode start, if it is off in its")"
    say "$(L "configuración está desactivado, lo vuelve a activar (Steam cerrado, para que no lo pise)." "settings, it turns it back on (Steam closed, so it can't overwrite it).")"
    say "$(L "POR QUÉ: con el Bluetooth desactivado en Steam (Ajustes → Bluetooth), Steam apaga el adaptador al" "WHY: with Bluetooth off in Steam (Settings → Bluetooth), Steam powers the adapter down when")"
    say "$(L "entrar al modo juego y el mando no conecta. Si Bazzite reinicia Steam (tras varias caídas seguidas del" "entering Game Mode and the controller can't connect. If Bazzite resets Steam (after several consecutive")"
    say "$(L "modo juego), se queda desactivado sin que tú lo toques." "Game Mode crashes), it stays off without you touching it.")"
    local sb; case $(steambt_now) in 1) sb=$(L activado enabled) ;; 0) sb=$(L DESACTIVADO DISABLED) ;; *) sb=$(L "sin ajuste guardado" "no saved setting") ;; esac
    say "$(L "Ahora en Steam: $sb." "Now in Steam: $sb.")"
    say "$(L "Si alguna vez quieres apagarlo en Steam, se volverá a activar en el siguiente arranque: desactiva este bloque." "If you ever want to turn it off in Steam, it will be turned on again at the next boot: disable this block.")"
    say "$(L "DESHACER: systemctl --user disable ps5-steam-bt; rm $STEAMBT_UNIT $STEAMBT_SH" "UNDO: systemctl --user disable ps5-steam-bt; rm $STEAMBT_UNIT $STEAMBT_SH")"
}
check_steambt() {
    [ -d "$HOME/.local/share/Steam" ] || return 2
    [ -x "$STEAMBT_SH" ] && systemctl --user is-enabled -q ps5-steam-bt.service 2>/dev/null
}
apply_steambt() {
    mkdir -p "$(dirname "$STEAMBT_SH")" "$(dirname "$STEAMBT_UNIT")" || return 1
    cat >"$STEAMBT_SH" <<'EOF' || return 1
#!/bin/sh
# Steam's Bluetooth switch back on before Game Mode starts (ps5-bazzite-toolbox, block steambt).
# Log: journalctl --user -b -u ps5-steam-bt
CFG=$HOME/.local/share/Steam/config/config.vdf
[ -f "$CFG" ] || exit 0
if awk '/"Bluetooth"/{b=1} b && /"Enabled"/{r=/"0"/?0:1; exit} b && /}/{exit} END{exit (r=="" ? 1 : r)}' "$CFG"; then
    sed -i -E '/"Bluetooth"/,/}/ s/("Enabled"[[:space:]]+)"0"/\1"1"/' "$CFG" && echo "Steam Bluetooth was off: switched on"
fi
EOF
    chmod 755 "$STEAMBT_SH" &&
    cat >"$STEAMBT_UNIT" <<EOF || return 1
[Unit]
Description=Steam's Bluetooth switch on before Game Mode (ps5-bazzite-toolbox)
Before=gamescope-session-plus@ogui-steam.service

[Service]
Type=oneshot
ExecStart=$STEAMBT_SH

[Install]
WantedBy=gamescope-session-plus@ogui-steam.service
EOF
    systemctl --user daemon-reload && systemctl --user enable ps5-steam-bt.service || return 1
    [ "$(steambt_now)" = 0 ] && say "$(L "Ahora está desactivado en Steam: se activará la próxima vez que entres al modo juego." "It is currently off in Steam: it will be turned on the next time you enter Game Mode.")"
    return 0
}

# --- disk ----------------------------------------------------------------------------------------
desc_disk() {
    section
    say "$(L "Impide que el monitor de discos de KDE (plasma-disks) consulte el SMART del disco: una regla" "Stops KDE's disk monitor (plasma-disks) from querying the disk's SMART: a polkit rule")"
    say "$(L "de polkit que lo deniega ($POLKIT_RULE), smartd desactivado y el módulo 'smart' de kded apagado." "that denies it ($POLKIT_RULE), smartd disabled and kded's 'smart' module switched off.")"
    say "$(L "POR QUÉ: muchos adaptadores USB-NVMe se bloquean ~60 s con esa consulta (en el log del kernel:" "WHY: many USB-NVMe adapters hang ~60 s on that query (in the kernel log:")"
    say "$(L "'timing out command, waited 60s') y el paso del modo juego al escritorio tarda casi un minuto." "'timing out command, waited 60s') and the switch from Game Mode to the desktop takes almost a minute.")"
    say "$(L "Con la regla, unos 5 s. Solo desactivar el módulo no basta. Pierdes los avisos SMART de KDE." "With the rule, about 5 s. Just disabling the module is not enough. You lose KDE's SMART warnings.")"
    say "$(L "DESHACER: sudo rm $POLKIT_RULE; sudo systemctl restart polkit; sudo systemctl enable --now smartd." "UNDO: sudo rm $POLKIT_RULE; sudo systemctl restart polkit; sudo systemctl enable --now smartd.")"
}
check_disk() {
    root_usb >/dev/null || sudo test -f "$POLKIT_RULE" || return 2
    sudo test -f "$POLKIT_RULE" && ! systemctl is-enabled -q smartd.service 2>/dev/null
}
apply_disk() {
    sudo tee "$POLKIT_RULE" >/dev/null <<'EOF' || return 1
// USB-NVMe bridges can stall ~60 s on SMART queries: never let KDE's disk monitor run smartctl.
polkit.addRule(function (action, subject) {
    if (action.id == "org.kde.kded.smart.smartctl") return polkit.Result.NO;
});
EOF
    sudo systemctl restart polkit || return 1
    sudo systemctl disable --now smartd.service 2>/dev/null
    command -v kwriteconfig6 >/dev/null && kwriteconfig6 --file kded6rc --group Module-smart --key autoload false
    return 0
}

# --- firewall ------------------------------------------------------------------------------------
# Bazzite's zone FedoraWorkstation has samba-client, whose NetBIOS conntrack helper (nf_conntrack_netbios_ns) the PS5
# kernel lacks: firewalld can't build its rules ("Could not process rule: No such file or directory"), falls back to
# a minimal zone and refuses every permanent change (RUNNING_BUT_FAILED). This finds such services in the default
# zone by their helper's module and takes them out of the zone (firewall-offline-cmd works while firewalld failed).
fw_zone() { sed -n 's/^DefaultZone=//p' /etc/firewalld/firewalld.conf 2>/dev/null | tail -1; }   # the configured one, not the fallback
fw_xml() {                               # fw_xml zones|services|helpers NAME -> the file firewalld reads (/etc first)
    local f; for f in "/etc/firewalld/$1/$2.xml" "/usr/lib/firewalld/$1/$2.xml"; do sudo test -f "$f" && { echo "$f"; return 0; }; done
    return 1
}
fw_helpers() {                           # fw_helpers SERVICE -> its conntrack helpers, also through <include service=…>
    local f s; f=$(fw_xml services "$1") || return 0
    sudo sed -n 's/.*<helper name="\([^"]*\)".*/\1/p' "$f"
    for s in $(sudo sed -n 's/.*<include service="\([^"]*\)".*/\1/p' "$f"); do [ "$s" != "$1" ] && fw_helpers "$s"; done
}
fw_bad() {                               # services of the default zone whose helper module this kernel hasn't got
    local z f s h hf mod; z=$(fw_zone); f=$(fw_xml zones "$z") || return 0
    for s in $(sudo sed -n 's/.*<service name="\([^"]*\)".*/\1/p' "$f"); do
        for h in $(fw_helpers "$s"); do
            hf=$(fw_xml helpers "$h") || continue
            mod=$(sudo sed -n 's/.*module="\([^"]*\)".*/\1/p' "$hf" | head -1)
            [ -n "$mod" ] && ! modinfo -n "$mod" >/dev/null 2>&1 && { echo "$s ($mod)"; break; }
        done
    done
}
fw_state() { sudo firewall-cmd --state 2>/dev/null; }
desc_firewall() {
    local bad; bad=$(fw_bad)
    section
    say "$(L "Arregla el cortafuegos (firewalld), que arranca «fallido»: funciona con una zona mínima en vez de la suya" "Fixes the firewall (firewalld), which starts as \"failed\": it runs with a minimal zone instead of yours")"
    say "$(L "($(fw_zone)) y no admite cambios (abrir un puerto da RUNNING_BUT_FAILED)." "($(fw_zone)) and accepts no changes (opening a port gives RUNNING_BUT_FAILED).")"
    if [ -n "$bad" ]; then
        say "$(L "Causa: la zona $(fw_zone) usa $(echo $bad), y el kernel de la PS5 no trae ese módulo. Lo quita de la zona" "Cause: zone $(fw_zone) uses $(echo $bad), and the PS5 kernel lacks that module. It removes it from the zone")"
        say "$(L "(firewall-offline-cmd --zone=$(fw_zone) --remove-service-from-zone=…) y reinicia firewalld." "(firewall-offline-cmd --zone=$(fw_zone) --remove-service-from-zone=…) and restarts firewalld.")"
        say "$(L "samba-client sirve para encontrar equipos Windows por su nombre; el NAS por su IP no lo necesita." "samba-client is used to find Windows machines by name; the NAS by its IP doesn't need it.")"
    else
        say "$(L "No encuentro la causa conocida (un servicio cuyo módulo falta): lo mira firewall-offline-cmd --check-config." "I can't find the known cause (a service whose module is missing): firewall-offline-cmd --check-config looks at it.")"
    fi
    [ "$(fw_zone)" = FedoraWorkstation ] && say "$(L "Con la zona funcionando quedan abiertos a tu red los puertos 1025-65535, como en Bazzite de escritorio" "With the zone working, ports 1025-65535 stay open to your network, as in desktop Bazzite")" &&
        say "$(L "(KDE Connect, transmisión de Steam, el monitor web). Más cerrado: sudo firewall-offline-cmd --set-default-zone=public." "(KDE Connect, Steam streaming, the web monitor). Tighter: sudo firewall-offline-cmd --set-default-zone=public.")"
    say "$(L "POR QUÉ: con el cortafuegos fallido, lo que abran otros ajustes o programas no se guarda." "WHY: with the firewall failed, whatever other settings or programs open is not saved.")"
    say "$(L "DESHACER: sudo rm /etc/firewalld/zones/$(fw_zone).xml; sudo systemctl restart firewalld" "UNDO: sudo rm /etc/firewalld/zones/$(fw_zone).xml; sudo systemctl restart firewalld")"
}
check_firewall() {
    systemctl is-active -q firewalld 2>/dev/null || return 2
    [ "$(fw_state)" = running ]
}
apply_firewall() {
    local z s bad; z=$(fw_zone); bad=$(fw_bad)
    if [ -z "$bad" ]; then
        sudo firewall-offline-cmd --check-config; echo "  $(L "No sé arreglarlo solo: revisa lo de arriba y sudo tail -40 /var/log/firewalld." "I can't fix it by myself: check the above and sudo tail -40 /var/log/firewalld.")"
        return 1
    fi
    for s in $(awk '{ print $1 }' <<<"$bad"); do
        sudo firewall-offline-cmd --zone="$z" --remove-service-from-zone="$s" >/dev/null || return 1
    done
    sudo systemctl restart firewalld && sleep 2
    [ "$(fw_state)" = running ] && say "$(L "Cortafuegos funcionando, zona $(sudo firewall-cmd --get-default-zone)." "Firewall running, zone $(sudo firewall-cmd --get-default-zone).")" ||
        { echo "  $(L "Sigue fallido: sudo tail -40 /var/log/firewalld" "Still failed: sudo tail -40 /var/log/firewalld")"; return 1; }
}

# --- brave ---------------------------------------------------------------------------------------
desc_brave() {
    section
    say "$(L "Brave (Flatpak) guarda sus claves sin la Cartera de KDE (--password-store=basic en $BRAVE_FLAGS)." "Brave (Flatpak) stores its keys without the KDE Wallet (--password-store=basic in $BRAVE_FLAGS).")"
    say "$(L "POR QUÉ: como la sesión entra sola, la Cartera de KDE no se abre y Brave pide su contraseña cada vez." "WHY: since the session logs in by itself, the KDE Wallet doesn't open and Brave asks for its password every time.")"
    say "$(L "Ojo: las sesiones y contraseñas ya guardadas en Brave dejan de leerse (hay que volver a entrar)." "Note: sessions and passwords already saved in Brave stop being readable (you have to sign in again).")"
    say "$(L "DESHACER: borra esa línea del fichero." "UNDO: delete that line from the file.")"
}
check_brave() {
    flatpak info com.brave.Browser >/dev/null 2>&1 || return 2
    grep -qs -- '--password-store=basic' "$BRAVE_FLAGS" || return 1     # grep says 2 for a missing file: that is pending, not "doesn't apply"
}
apply_brave() {
    mkdir -p "$(dirname "$BRAVE_FLAGS")" && echo '--password-store=basic' >>"$BRAVE_FLAGS" &&
        { flatpak kill com.brave.Browser 2>/dev/null; true; }
}

# --- edge ----------------------------------------------------------------------------------------
desc_edge() {
    section
    say "$(L "Microsoft Edge (Flatpak) guarda sus claves sin la Cartera de KDE (--password-store=basic en $EDGE_FLAGS)." "Microsoft Edge (Flatpak) stores its keys without the KDE Wallet (--password-store=basic in $EDGE_FLAGS).")"
    say "$(L "POR QUÉ: como la sesión entra sola, la Cartera de KDE no se abre y Edge pide su contraseña cada vez." "WHY: since the session logs in by itself, the KDE Wallet doesn't open and Edge asks for its password every time.")"
    say "$(L "Ojo: las sesiones y contraseñas ya guardadas en Edge dejan de leerse (hay que volver a entrar)." "Note: sessions and passwords already saved in Edge stop being readable (you have to sign in again).")"
    say "$(L "DESHACER: borra esa línea del fichero." "UNDO: delete that line from the file.")"
}
check_edge() {
    flatpak info com.microsoft.Edge >/dev/null 2>&1 || return 2
    grep -qs -- '--password-store=basic' "$EDGE_FLAGS" || return 1
}
apply_edge() {
    mkdir -p "$(dirname "$EDGE_FLAGS")" && echo '--password-store=basic' >>"$EDGE_FLAGS" &&
        { flatpak kill com.microsoft.Edge 2>/dev/null; true; }
}

# --- nas -----------------------------------------------------------------------------------------
desc_nas() {
    section
    say "$(L "ROMs de EmuDeck desde un NAS por SMB: monta la carpeta compartida en $NAS_MNT (al primer uso;" "EmuDeck ROMs from a NAS over SMB: mounts the shared folder at $NAS_MNT (on first use;")"
    say "$(L "si el NAS está apagado no bloquea el arranque) y ~/Emulation/roms pasa a ser un enlace a la" "if the NAS is off it doesn't block boot) and ~/Emulation/roms becomes a link to the")"
    say "$(L "carpeta de ROMs del NAS (la local queda como ~/Emulation/roms.local). Da acceso a los Flatpak." "NAS's ROM folder (the local one stays as ~/Emulation/roms.local). Gives Flatpaks access.")"
    say "$(L "Pide IP, carpeta compartida, usuario y ruta de las ROMs; la contraseña queda en /etc/samba (solo root)." "Asks for IP, shared folder, user and ROM path; the password is kept in /etc/samba (root only).")"
    say "$(L "POR QUÉ: no ocupar el disco de la PS5 y compartir las ROMs con otros equipos (p. ej. una Steam Deck)." "WHY: not to fill the PS5's disk and to share the ROMs with other machines (e.g. a Steam Deck).")"
    say "$(L "Las BIOS y las partidas guardadas siguen en local. Requiere EmuDeck ya instalado." "BIOS files and save games stay local. Requires EmuDeck already installed.")"
    say "$(L "DESHACER: rm ~/Emulation/roms && mv ~/Emulation/roms.local ~/Emulation/roms; quita la línea de /etc/fstab." "UNDO: rm ~/Emulation/roms && mv ~/Emulation/roms.local ~/Emulation/roms; remove the line from /etc/fstab.")"
}
nas_mount_of_roms() {                    # the cifs mount point in fstab that ~/Emulation/roms points into
    local t m; t=$(readlink ~/Emulation/roms 2>/dev/null) || return 1
    for m in $(awk '$3 == "cifs" { print $2 }' /etc/fstab); do
        case $t in "$m"/*) echo "$m"; return 0 ;; esac
    done
    return 1
}
nas_existing() {                         # first cifs line of fstab: "//IP/SHARE MOUNTPOINT"
    awk '$3 == "cifs" { print $1, $2; exit }' /etc/fstab 2>/dev/null
}
check_nas() {
    [ -d ~/Emulation ] || return 2
    local m t; m=$(nas_mount_of_roms) || return 1
    t=$(readlink ~/Emulation/roms)
    # the link must lead to a real folder (the NAS may have been reorganised) and match the path you chose
    timeout 20 test -d "$t" || return 1
    [ -z "${NAS_ROMS:-}" ] || [ "$t" = "$m/$NAS_ROMS" ] || return 1
    grep -qs "$m" ~/.local/share/flatpak/overrides/global || return 1     # grep says 2 for a missing file: that is pending, not "doesn't apply"
}
apply_nas() {
    # an existing cifs mount (set up by hand or by an earlier run) is reused: its share, mount point, user
    # and current ROM path become the defaults, so no second fstab line is added
    local ex src mnt t cur=''
    ex=$(nas_existing)
    if [ -n "$ex" ]; then
        src=${ex%% *}; mnt=${ex#* }; src=${src#//}
        [ -n "${NAS_IP:-}" ] || NAS_IP=${src%%/*}
        [ -n "${NAS_SHARE:-}" ] || NAS_SHARE=${src#*/}
        NAS_MNT=$mnt; remember NAS_MNT "$mnt"
        [ -n "${NAS_USER:-}" ] || NAS_USER=$(sudo sed -n 's/^username=//p' "$(awk '$3 == "cifs" { print $4; exit }' /etc/fstab |
            tr ',' '\n' | sed -n 's/^credentials=//p')" 2>/dev/null)
        t=$(readlink ~/Emulation/roms 2>/dev/null); case $t in "$mnt"/*) cur=${t#"$mnt"/} ;; esac
        say "$(L "Ya hay un montaje del NAS: //$src en $mnt${cur:+ (ROMs en $cur)}." "A NAS mount already exists: //$src at $mnt${cur:+ (ROMs in $cur)}.")"
    fi
    [ $ALL = 1 ] && [ -z "${NAS_IP:-}" ] && { say "$(L "Sin datos del NAS: ejecútalo sin --all para responder las preguntas." "No NAS details: run it without --all to answer the questions.")"; return 1; }
    value NAS_IP "$(L "IP del NAS (p. ej. 192.168.1.x)" "NAS IP (e.g. 192.168.1.x)")" "${NAS_IP:-}"
    value NAS_SHARE "$(L "Carpeta compartida (como en \\\\NAS\\carpeta)" "Shared folder (as in \\\\NAS\\folder)")" "${NAS_SHARE:-}"
    value NAS_USER "$(L "Usuario del NAS" "NAS user")" "${NAS_USER:-}"
    value NAS_ROMS "$(L "Ruta de la carpeta roms dentro de la compartida" "Path of the roms folder inside the share")" "${NAS_ROMS:-${cur:-Emulation/roms}}"
    local cred=/etc/samba/nas-$NAS_USER.cred
    rpm -q cifs-utils >/dev/null || sudo dnf5 install -y cifs-utils || return 1
    if ! sudo test -s "$cred"; then
        local P
        read -rsp "$(L "  Contraseña de $NAS_USER en el NAS (no se muestra): " "  Password of $NAS_USER on the NAS (not shown): ")" P </dev/tty; echo
        sudo mkdir -p /etc/samba &&
            printf 'username=%s\npassword=%s\n' "$NAS_USER" "$P" | sudo tee "$cred" >/dev/null
        unset P
        sudo chmod 600 "$cred" || return 1
    fi
    sudo mkdir -p "$NAS_MNT" || return 1
    [ -n "$ex" ] || grep -q " $NAS_MNT cifs " /etc/fstab ||
        echo "//$NAS_IP/$NAS_SHARE $NAS_MNT cifs credentials=$cred,uid=$(id -u),gid=$(id -g),vers=3.0,iocharset=utf8,_netdev,nofail,noauto,x-systemd.automount,x-systemd.mount-timeout=15 0 0" |
        sudo tee -a /etc/fstab >/dev/null || return 1
    sudo systemctl daemon-reload && sudo systemctl restart remote-fs.target || return 1
    ls "$NAS_MNT/$NAS_ROMS" >/dev/null ||
        { say "$(L "No puedo leer $NAS_MNT/$NAS_ROMS (¿NAS apagado, ruta o contraseña mal? Borra $cred y repite)." "Can't read $NAS_MNT/$NAS_ROMS (NAS off, wrong path or password? Delete $cred and retry).")"; return 1; }
    if [ -L ~/Emulation/roms ]; then             # already a link: point it at the (new) ROM path
        [ "$(readlink ~/Emulation/roms)" = "$NAS_MNT/$NAS_ROMS" ] ||
            { say "$(L "Enlace ~/Emulation/roms: $(readlink ~/Emulation/roms) → $NAS_MNT/$NAS_ROMS" "Link ~/Emulation/roms: $(readlink ~/Emulation/roms) → $NAS_MNT/$NAS_ROMS")"
              ln -sfn "$NAS_MNT/$NAS_ROMS" ~/Emulation/roms || return 1; }
    else
        # shellcheck disable=SC2088
        [ ! -e ~/Emulation/roms.local ] || { say "$(L "Ya existe ~/Emulation/roms.local; revísalo a mano." "~/Emulation/roms.local already exists; check it by hand.")"; return 1; }
        [ ! -e ~/Emulation/roms ] || mv ~/Emulation/roms ~/Emulation/roms.local || return 1
        ln -s "$NAS_MNT/$NAS_ROMS" ~/Emulation/roms || return 1
    fi
    flatpak override --user --filesystem="$NAS_MNT" || return 1
    local bios; bios="$NAS_MNT/$(dirname "$NAS_ROMS")/bios"
    if [ -d "$bios" ] && ask "$(L "  ¿Copiar al disco local las BIOS que falten desde el NAS ($bios)?" "  Copy the missing BIOS files from the NAS ($bios) to the local disk?")"; then
        cp -rn "$bios/." ~/Emulation/bios/
    fi
    return 0
}

# --- shared NAS folders (bios, media) -----------------------------------------------------------------
# Both need the NAS block: they reuse its mount. The NAS keeps the three shared folders side by side:
# <base>/Emulation/{roms,bios,downloaded_media}; on the PS5 each goes where it's used (~/Emulation/roms and
# ~/Emulation/bios as links, the media through ES-DE's MediaDirectory).
nas_mnt() { nas_mount_of_roms 2>/dev/null || { local e; e=$(nas_existing); [ -n "$e" ] && echo "${e#* }"; }; }
nas_roms_rel() { local m t; m=$(nas_mnt) && t=$(readlink ~/Emulation/roms 2>/dev/null) && echo "${t#"$m"/}"; }
nas_dir_ok() { timeout 20 test -d "$1"; }    # the share mounts on first use: give it time, never hang
link_to_nas() {                          # link_to_nas LOCAL NASDIR [nocopy] -> LOCAL becomes a link (kept as LOCAL.local)
    local local_dir=$1 nas=$2 nocopy=${3:-}
    if [ -L "$local_dir" ]; then ln -sfn "$nas" "$local_dir"; return; fi
    if [ -d "$local_dir" ] && [ -z "$nocopy" ]; then
        local only; only=$(cd "$local_dir" && find . -type f 2>/dev/null | while read -r f; do [ -e "$nas/$f" ] || echo "$f"; done | wc -l)
        if [ "$only" -gt 0 ]; then
            say "$(L "$only ficheros de $local_dir no están en el NAS." "$only files from $local_dir are not on the NAS.")"
            if ask "$(L "  ¿Copiarlos al NAS antes de enlazar (no se sobrescribe nada de allí)?" "  Copy them to the NAS before linking (nothing there is overwritten)?")"; then
                # regular files only: the share (SMB) can't hold links, and EmuDeck's bios folder has some
                # (e.g. ryujinx/keys -> the emulator's own folder)
                (cd "$local_dir" && find . -type f -print0 | while IFS= read -r -d '' f; do
                    [ -e "$nas/$f" ] || { mkdir -p "$nas/$(dirname "$f")" && cp -p "$f" "$nas/$f"; } || exit 1
                done) || return 1
            fi
        fi
    fi
    if [ -d "$local_dir" ]; then
        [ ! -e "$local_dir.local" ] || { say "$(L "Ya existe $local_dir.local; revísalo a mano." "$local_dir.local already exists; check it by hand.")"; return 1; }
        mv "$local_dir" "$local_dir.local" || return 1
    fi
    mkdir -p "$(dirname "$local_dir")" && ln -s "$nas" "$local_dir"
}

# --- bios ----------------------------------------------------------------------------------------
bios_nas() { local r; r=$(nas_roms_rel); echo "${NAS_BIOS:-${r%/roms}/bios}"; }
desc_bios() {
    section
    say "$(L "La carpeta ~/Emulation/bios pasa a ser un enlace a las BIOS del NAS ($(nas_mnt)/$(bios_nas)), como" "The ~/Emulation/bios folder becomes a link to the NAS BIOS ($(nas_mnt)/$(bios_nas)), as")"
        # shellcheck disable=SC2088
    say "$(L "ya lo es ~/Emulation/roms. La carpeta local queda como ~/Emulation/bios.local; antes de enlazar ofrece" "~/Emulation/roms already is. The local folder stays as ~/Emulation/bios.local; before linking it offers to")"
    say "$(L "copiar al NAS las BIOS que solo estén aquí." "copy to the NAS the BIOS files that exist only here.")"
    say "$(L "POR QUÉ: una sola copia de las BIOS para la PS5 y la Steam Deck. No añade riesgo: sin NAS tampoco hay ROMs." "WHY: a single copy of the BIOS for the PS5 and the Steam Deck. No added risk: without the NAS there are no ROMs either.")"
    say "$(L "DESHACER: rm ~/Emulation/bios && mv ~/Emulation/bios.local ~/Emulation/bios" "UNDO: rm ~/Emulation/bios && mv ~/Emulation/bios.local ~/Emulation/bios")"
}
check_bios() {
    [ -d ~/Emulation ] && check_nas >/dev/null 2>&1 || return 2
    local m; m=$(nas_mnt)
    [ "$(readlink ~/Emulation/bios 2>/dev/null)" = "$m/$(bios_nas)" ] && nas_dir_ok "$m/$(bios_nas)"
}
apply_bios() {
    local m; m=$(nas_mnt) || { say "$(L "Primero el bloque nas." "First the nas block.")"; return 1; }
    value NAS_BIOS "$(L "Carpeta de BIOS dentro de la compartida" "BIOS folder inside the share")" "$(bios_nas)"
    nas_dir_ok "$m/$NAS_BIOS" || mkdir -p "$m/$NAS_BIOS" || { say "$(L "No puedo usar $m/$NAS_BIOS (¿NAS apagado?)." "Can't use $m/$NAS_BIOS (NAS off?).")"; return 1; }
    link_to_nas ~/Emulation/bios "$m/$NAS_BIOS" || return 1
    say "$(L "BIOS: ~/Emulation/bios → $m/$NAS_BIOS ($(find -L ~/Emulation/bios -type f 2>/dev/null | wc -l) ficheros)" "BIOS: ~/Emulation/bios → $m/$NAS_BIOS ($(find -L ~/Emulation/bios -type f 2>/dev/null | wc -l) files)")"
}

# --- media ---------------------------------------------------------------------------------------
# ES-DE reads its scraped images/videos from MediaDirectory (es_settings.xml; empty = ~/ES-DE/downloaded_media,
# EmuDeck sets ~/Emulation/tools/downloaded_media). Like the ROMs, that folder becomes a link to the NAS's
# downloaded_media, so ES-DE's setting stays as it is. Nothing is copied: the NAS is assumed to have them.
ESDE_SETTINGS=$HOME/ES-DE/settings/es_settings.xml
media_nas() { local r; r=$(nas_roms_rel); echo "${NAS_MEDIA:-${r%/roms}/downloaded_media}"; }
media_now() {                            # the folder ES-DE reads media from
    local v; v=$(sed -n 's/.*name="MediaDirectory" value="\([^"]*\)".*/\1/p' "$ESDE_SETTINGS" 2>/dev/null)
    v=${v/#\~/$HOME}; echo "${v:-$HOME/ES-DE/downloaded_media}"
}
desc_media() {
    local d; d=$(media_now)
    section
    say "$(L "La carpeta de imágenes y vídeos de ES-DE ($d) pasa a ser un enlace a la del NAS" "ES-DE's images and videos folder ($d) becomes a link to the NAS one")"
    say "$(L "($(nas_mnt)/$(media_nas)), como ya lo es ~/Emulation/roms. No copia nada: usa lo que ya hay en el NAS." "($(nas_mnt)/$(media_nas)), as ~/Emulation/roms already is. It copies nothing: it uses what is already on the NAS.")"
    say "$(L "ES-DE no se toca: sigue leyendo de la misma ruta. La carpeta local queda como $d.local" "ES-DE is not touched: it keeps reading from the same path. The local folder stays as $d.local")"
    say "$(L "($(du -sh "$d" 2>/dev/null | cut -f1 || echo 'vacía')); bórrala cuando veas que todo va bien." "($(du -sh "$d" 2>/dev/null | cut -f1 || echo 'empty')); delete it once you see everything works.")"
    say "$(L "POR QUÉ: es lo que más ocupa de ES-DE; en el NAS lo comparten la PS5 y la Steam Deck." "WHY: it is the biggest part of ES-DE; on the NAS the PS5 and the Steam Deck share it.")"
    say "$(L "DESHACER: rm '$d' && mv '$d.local' '$d'" "UNDO: rm '$d' && mv '$d.local' '$d'")"
}
check_media() {
    [ -d ~/ES-DE ] && check_nas >/dev/null 2>&1 || return 2
    local m; m=$(nas_mnt)
    [ "$(readlink "$(media_now)" 2>/dev/null)" = "$m/$(media_nas)" ] && nas_dir_ok "$m/$(media_nas)"
}
apply_media() {
    local m d; m=$(nas_mnt) || { say "$(L "Primero el bloque nas." "First the nas block.")"; return 1; }
    pgrep -f -i 'es-de|emulationstation' >/dev/null && { say "$(L "ES-DE está abierto: ciérralo y repite." "ES-DE is open: close it and retry.")"; return 1; }
    value NAS_MEDIA "$(L "Carpeta de medios dentro de la compartida" "Media folder inside the share")" "$(media_nas)"
    nas_dir_ok "$m/$NAS_MEDIA" || { say "$(L "No encuentro $m/$NAS_MEDIA en el NAS (¿ruta o NAS apagado?)." "Can't find $m/$NAS_MEDIA on the NAS (wrong path or NAS off?).")"; return 1; }
    d=$(media_now)
    link_to_nas "$d" "$m/$NAS_MEDIA" nocopy || return 1
    say "$(L "Medios de ES-DE: $d → $m/$NAS_MEDIA ($(ls "$m/$NAS_MEDIA" | wc -l) sistemas)" "ES-DE media: $d → $m/$NAS_MEDIA ($(ls "$m/$NAS_MEDIA" | wc -l) systems)")"
    [ -d "$d.local" ] && say "$(L "Cuando compruebes que ES-DE muestra las imágenes: rm -rf '$d.local'" "Once you check that ES-DE shows the images: rm -rf '$d.local'")"
    return 0
}

# --- esde ----------------------------------------------------------------------------------------
# EmuDeck writes its own ES-DE system list (~/ES-DE/custom_systems/es_systems.xml). Seen on the PS5 (2026-10-30):
# Windows lines in it ("%CORE_RETROARCH%\citra_libretro.dll", a "< command>" typo) and no "Citra (Standalone)"
# for n3ds, so lists coming from a Steam Deck that used Citra fail ("citra_libretro.dll" missing). EmuDeck can
# write the file again when it updates: this block checks and repairs it.
ESDE_SYSTEMS=$HOME/ES-DE/custom_systems/es_systems.xml
CITRA_LINE='<command label="Citra (Standalone)">%EMULATOR_CITRA% %ROM%</command>'
citra_installed() { compgen -G "$HOME/Applications/citra-qt*.AppImage" >/dev/null || flatpak info org.citra_emu.citra >/dev/null 2>&1; }
esde_windows_lines() { grep -c -E '_libretro\.dll|< command>' "$ESDE_SYSTEMS" 2>/dev/null; }
esde_citra_missing() {
    citra_installed && ! awk '/<name>n3ds<\/name>/,/<\/system>/' "$ESDE_SYSTEMS" | grep >/dev/null 'label="Citra (Standalone)"'
}
desc_esde() {
    section
    say "$(L "Repara la lista de sistemas que EmuDeck deja a ES-DE ($ESDE_SYSTEMS):" "Repairs the system list EmuDeck leaves for ES-DE ($ESDE_SYSTEMS):")"
    say "$(L "- líneas de Windows: '%CORE_RETROARCH%\\xxx_libretro.dll' → '/xxx_libretro.so', y '< command>' → '</command>'" "- Windows lines: '%CORE_RETROARCH%\\xxx_libretro.dll' → '/xxx_libretro.so', and '< command>' → '</command>'")"
    say "$(L "  (ahora hay $(esde_windows_lines || echo 0));" "  (now there are $(esde_windows_lines || echo 0));")"
    say "$(L "- si Citra está instalado (~/Applications/citra-qt*.AppImage), añade 'Citra (Standalone)' a Nintendo 3DS" "- if Citra is installed (~/Applications/citra-qt*.AppImage), adds 'Citra (Standalone)' to Nintendo 3DS")"
    say "$(L "  ($(citra_installed && { esde_citra_missing && echo 'falta' || echo 'ya está'; } || echo 'Citra no instalado'))." "  ($(citra_installed && { esde_citra_missing && echo 'missing' || echo 'already there'; } || echo 'Citra not installed')).")"
    say "$(L "POR QUÉ: con esas líneas ES-DE busca un .dll que en Linux no existe ('citra_libretro.dll'), y las listas" "WHY: with those lines ES-DE looks for a .dll that doesn't exist on Linux ('citra_libretro.dll'), and lists")"
    say "$(L "de una Steam Deck que usaba Citra (Azahar no abre ROMs cifradas) piden 'Citra (Standalone)'." "from a Steam Deck that used Citra (Azahar doesn't open encrypted ROMs) ask for 'Citra (Standalone)'.")"
    say "$(L "EmuDeck puede volver a escribir el fichero al actualizarse: si 3DS vuelve a fallar, repite este bloque." "EmuDeck may rewrite the file when it updates: if 3DS fails again, repeat this block.")"
    say "$(L "DESHACER: copia sobre él el $ESDE_SYSTEMS.bak-* más reciente." "UNDO: copy the most recent $ESDE_SYSTEMS.bak-* over it.")"
}
check_esde() {
    [ -f "$ESDE_SYSTEMS" ] || return 2
    [ "$(esde_windows_lines)" = 0 ] && ! esde_citra_missing
}
apply_esde() {
    pgrep -f -i 'es-de|emulationstation' >/dev/null && { say "$(L "ES-DE está abierto: ciérralo y repite." "ES-DE is open: close it and retry.")"; return 1; }
    local bak; bak="$ESDE_SYSTEMS.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$ESDE_SYSTEMS" "$bak" || return 1
    sed -i -e 's#%CORE_RETROARCH%\\\([A-Za-z0-9_]*\)_libretro\.dll#%CORE_RETROARCH%/\1_libretro.so#g' \
           -e 's#< command>#</command>#g' "$ESDE_SYSTEMS" || return 1
    if esde_citra_missing; then         # insert it just before n3ds's <platform> line
        awk -v line="$CITRA_LINE" '/<name>n3ds<\/name>/ { n3ds = 1 }
            n3ds && /<platform>n3ds<\/platform>/ { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) line; n3ds = 0 }
            { print }' "$ESDE_SYSTEMS" >"$ESDE_SYSTEMS.tmp" && mv "$ESDE_SYSTEMS.tmp" "$ESDE_SYSTEMS" || return 1
    fi
    if ! python3 -I -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$ESDE_SYSTEMS" 2>/dev/null; then
        say "$(L "El fichero no ha quedado como XML válido: restauro la copia ($bak)." "The file did not end up as valid XML: restoring the copy ($bak).")"
        cp "$bak" "$ESDE_SYSTEMS"; return 1
    fi
    say "$(L "Líneas de Windows que quedan: $(esde_windows_lines). 3DS: $(awk '/<name>n3ds<\/name>/,/<\/system>/' "$ESDE_SYSTEMS" |
        sed -n 's/.*label="\([^"]*\)".*/\1/p' | paste -sd, -)." "Windows lines left: $(esde_windows_lines). 3DS: $(awk '/<name>n3ds<\/name>/,/<\/system>/' "$ESDE_SYSTEMS" | sed -n 's/.*label="\([^"]*\)".*/\1/p' | paste -sd, -).")"
    say "$(L "En ES-DE: Otros ajustes → Emuladores alternativos → Nintendo 3DS → Citra (Standalone), si no lo tenía ya." "In ES-DE: Other settings → Alternative emulators → Nintendo 3DS → Citra (Standalone), if it didn't have it already.")"
}

# --- portproton -----------------------------------------------------------------------------------
# Defaults for every PortProton game, in its global settings (data/user.conf). PortProton reads user.conf AFTER a
# game's .ppdb (start.sh: pw_init_db, then source user.conf), so a plain export would beat the game's own setting:
# each default applies only when the game's .ppdb doesn't set that variable.
PP_USERCONF=$HOME/.var/app/ru.linux_gaming.PortProton/data/user.conf
PP_DEFAULTS='PW_USE_FSYNC=1 PW_USE_ESYNC=1 PW_USE_RAY_TRACING=1'
desc_portproton() {
    section
    say "$(L "Ajustes por defecto para TODOS los juegos de PortProton (en $PP_USERCONF), salvo los que el .ppdb" "Default settings for ALL PortProton games (in $PP_USERCONF), except those the game's own .ppdb")"
    say "$(L "de un juego fije él mismo:" "sets itself:")"
    say "$(L "- PW_USE_FSYNC=1 y PW_USE_ESYNC=1: sincronización rápida entre los hilos del juego. PortProton la trae" "- PW_USE_FSYNC=1 and PW_USE_ESYNC=1: fast synchronisation between the game's threads. PortProton ships it")"
    say "$(L "  apagada; el Proton de Steam (y la Steam Deck) la lleva encendida. Menos tirones en juegos que cargan la CPU." "  off; Steam's Proton (and the Steam Deck) has it on. Less stutter in CPU-heavy games.")"
    say "$(L "- PW_USE_RAY_TRACING=1: trazado de rayos en DX12 (vkd3d «dxr»). PortProton lo apaga en AMD aunque el driver" "- PW_USE_RAY_TRACING=1: ray tracing in DX12 (vkd3d «dxr»). PortProton turns it off on AMD even though the PS5")"
    say "$(L "  de la PS5 lo tiene, y los juegos que lo exigen dicen que la gráfica no vale." "  driver supports it, and games that require it say the graphics card isn't good enough.")"
    say "$(L "  Ojo: algún juego, al verlo, lo enciende en su calidad por defecto y va más lento: bájalo en sus opciones" "  Note: some games, on seeing it, turn it on in their default quality and run slower: lower it in their graphics")"
    say "$(L "  gráficas, o apágalo solo para él con export PW_USE_RAY_TRACING=\"0\" en su .ppdb." "  options, or turn it off just for that game with export PW_USE_RAY_TRACING=\"0\" in its .ppdb.")"
    say "$(L "POR QUÉ: la máxima compatibilidad sin tocar nada juego a juego." "WHY: maximum compatibility without touching games one by one.")"
    say "$(L "DESHACER: borra en ese fichero el bloque entre «# >>> ps5-bazzite-toolbox» y «# <<< ps5-bazzite-toolbox»." "UNDO: delete in that file the block between «# >>> ps5-bazzite-toolbox» and «# <<< ps5-bazzite-toolbox».")"
}
check_portproton() {
    flatpak info ru.linux_gaming.PortProton >/dev/null 2>&1 || return 2
    [ -f "$PP_USERCONF" ] || return 2            # PortProton not opened yet: it creates the file the first time
    grep -qs -F "PP_DEFAULTS: $PP_DEFAULTS" "$PP_USERCONF" || return 1
}
apply_portproton() {
    local bak; bak="$PP_USERCONF.bak-$(date +%Y%m%d-%H%M%S)"
    [ -e "$bak" ] || cp "$PP_USERCONF" "$bak" || return 1    # never over an earlier copy
    sed -i -E '/^# >>> ps5-(bazzite-)?toolbox/,/^# <<< ps5-(bazzite-)?toolbox/d' "$PP_USERCONF"
    cat >>"$PP_USERCONF" <<EOF
# >>> ps5-bazzite-toolbox (bloque portproton) PP_DEFAULTS: $PP_DEFAULTS
# Defaults for every game unless its .ppdb sets the variable (this file is read after the .ppdb).
for _pp_kv in $PP_DEFAULTS; do
    grep -qs "^export \${_pp_kv%%=*}=" "\${PORTWINE_DB_FILE:-/nonexistent}" || export "\${_pp_kv%%=*}=\${_pp_kv#*=}"
done
unset _pp_kv
# <<< ps5-bazzite-toolbox
EOF
    bash -n "$PP_USERCONF" || { say "$(L "El fichero no ha quedado bien: restaura la copia .bak." "The file did not end up right: restore the .bak copy.")"; return 1; }
    say "$(L "Ajustes globales de PortProton: $PP_DEFAULTS (los juegos abiertos los cogen al volver a abrirlos)." "PortProton global settings: $PP_DEFAULTS (open games pick them up when reopened).")"
}

# --- monitorweb ----------------------------------------------------------------------------------
# The live monitor (option 4) in a phone's browser, always reachable at http://<console>:8765 with nothing to start:
# a small Python server, a user service (no root) and a firewall rule for the home network only. It only measures
# while a page asks for it ("Empezar"); unwatched for 10 min it stops by itself, and then the page asks whether to
# keep the session's CSV on the console. The script is kept here as text.
monweb_script() { cat <<'__MONWEB__'
#!/usr/bin/env python3
# PS5 Bazzite toolbox — the live monitor (menu option 4) in a phone's browser: http://<PS5 address>:PORT
# Waiting it does nothing (blocked on the socket). "Empezar" on the page starts a sample every 2 s; with no page
# asking for 10 min (phone locked, tab or browser closed) it stops by itself. A page in a background tab keeps
# asking every 15 s (browsers may slow that to once a minute), so looking at another tab doesn't stop it. Once stopped, the page asks whether to keep the
# session's CSV on the console (--csv-dir, default the home folder, ps5-mem-DATE.csv); nothing is saved unasked.
# Read-only: besides that file it changes nothing.
# Only answers private addresses (home network); the firewall rule of the toolbox's block "monitorweb" does the same.
import glob, ipaddress, json, os, re, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 8765
CSV_DIR = sys.argv[sys.argv.index("--csv-dir") + 1] if "--csv-dir" in sys.argv else os.path.expanduser("~")
LANG = sys.argv[sys.argv.index("--lang") + 1] if "--lang" in sys.argv else os.environ.get("TB_LANG", "en")
LANG = "es" if LANG == "es" else "en"
L = lambda es, en: es if LANG == "es" else en   # UI language: TB_LANG from the environment (the unit sets it), or --lang
MIN_SAVE = 5                                   # samples (10 s) before a session is worth a file
EVERY, IDLE_STOP, KEEP = 2, 600, 1800         # seconds per sample, stop after this long unwatched, samples kept (1 h)
P_GPUMEM = re.compile(r"ENOMEM|Not enough memory|Failed to pin|ring [a-z_0-9.]+ (timeout|reset)|page fault", re.I)
P_VMREF = "__vm_enough_memory"                 # a program refused address space (e.g. RPCS3): not the GPU

def rd(path, default=""):
    try:
        with open(path) as f: return f.read().strip()
    except OSError: return default

def num(path):
    try: return int(rd(path, "0").split()[0])
    except (ValueError, IndexError): return 0

DEV = next((d for d in sorted(glob.glob("/sys/class/drm/card*/device")) if os.path.exists(d + "/mem_info_vram_total")), "")

def hwmon(name, label="temp1_input"):
    for h in glob.glob("/sys/class/hwmon/hwmon*"):
        if rd(h + "/name") == name: return h + "/" + label
    return ""
T_CHIP = hwmon("k10temp") or hwmon("amdgpu")   # CPU and GPU are one chip: both sensors read the same

def meminfo():
    m = {}
    for l in rd("/proc/meminfo").splitlines():
        k, v = l.split(":", 1); m[k] = int(v.split()[0]) // 1024
    return m

def disk_swap():                              # swap that isn't zram (a file or partition on disk): size, used (MiB)
    size = used = 0
    for l in rd("/proc/swaps").splitlines()[1:]:
        f = l.split()
        if len(f) >= 4 and "zram" not in f[0]: size += int(f[2]) // 1024; used += int(f[3]) // 1024
    return size, used

def cpu_times():
    out = {}
    for l in rd("/proc/stat").splitlines():
        if l.startswith("cpu"):
            f = l.split(); v = list(map(int, f[1:9])); out[f[0]] = (sum(v), v[3] + v[4])
    return out

def cpu_load(a, b):                           # average and the busiest thread, in %
    avg, mx = 0, 0
    for k, (t, i) in b.items():
        if k not in a: continue
        dt = t - a[k][0]; p = 100 * (dt - (i - a[k][1])) / dt if dt > 0 else 0
        if k == "cpu": avg = p
        else: mx = max(mx, p)
    return round(avg), round(mx)

def gpu_top(n=3):                             # programs by VRAM (amdgpu's per-client counters), MiB
    seen, per = set(), {}
    for fi in glob.glob("/proc/[0-9]*/fdinfo/*"):
        try:
            with open(fi) as f: t = f.read()
        except OSError: continue
        if "drm-memory-vram" not in t: continue
        cid = re.search(r"drm-client-id:\s*(\d+)", t); v = re.search(r"drm-memory-vram:\s*(\d+)", t)
        if not cid or not v or cid.group(1) in seen: continue
        seen.add(cid.group(1)); pid = fi.split("/")[2]
        c = rd(f"/proc/{pid}/comm", "?"); per[c] = per.get(c, 0) + int(v.group(1)) / 1024
    return sorted(([c, round(m)] for c, m in per.items()), key=lambda x: -x[1])[:n]

def ram_top():                                # the process with the most RAM
    best = (0, "?")
    for s in glob.glob("/proc/[0-9]*/statm"):
        try: r = int(rd(s, "0 0").split()[1]) * 4096
        except (ValueError, IndexError): continue
        if r > best[0]: best = (r, rd(s[:-5] + "comm", "?"))
    return [best[1], round(best[0] / 2**20)]

class Monitor:
    def __init__(self):
        self.lock = threading.Lock(); self.running = False; self.thread = None
        self.samples = []; self.total = 0; self.seen = 0.0; self.start = ""; self.errors = []; self.vmref = 0; self.first = 0
        self.saved = ""; self.stamp = ""; self.discarded = False

    def info(self):
        m = meminfo()
        return {"vt": num(DEV + "/mem_info_vram_total") >> 20 if DEV else 0, "gt": num(DEV + "/mem_info_gtt_total") >> 20 if DEV else 0,
                "rt": m.get("MemTotal", 0), "st": m.get("SwapTotal", 0), "sd": disk_swap()[0], "threads": os.cpu_count(),
                "zram": bool(glob.glob("/sys/block/zram*")), "host": os.uname().nodename}

    def begin(self):
        with self.lock:
            self.seen = time.time()
            if self.running: return
            self.running = True; self.samples = []; self.total = 0; self.errors = []; self.vmref = 0; self.first += 1
            self.start = time.strftime("%Y-%m-%d %H:%M:%S"); self.stamp = time.strftime("%Y%m%d-%H%M%S"); self.saved = ""; self.discarded = False
            self.thread = threading.Thread(target=self.loop, daemon=True); self.thread.start()

    def end(self):
        with self.lock: self.running = False

    def discard(self):
        with self.lock: self.discarded = True

    def save(self):                           # the session's CSV on the console, when the page says so
        with self.lock:
            if self.running or len(self.samples) < MIN_SAVE or self.saved: return
        path = os.path.join(CSV_DIR, f"ps5-mem-{self.stamp}.csv")
        try:
            os.makedirs(CSV_DIR, exist_ok=True)
            with open(path + ".tmp", "w") as f: f.write(self.csv())
            os.replace(path + ".tmp", path)
            with self.lock: self.saved = path
        except OSError as e:
            with self.lock: self.saved = L(f"no se pudo guardar: {e}", f"could not save: {e}")

    def loop(self):
        prev, n, top, rtop = cpu_times(), 0, [], ["?", 0]
        while True:
            time.sleep(EVERY)
            with self.lock:
                if not self.running: return
                if time.time() - self.seen > IDLE_STOP: self.running = False; return
            m = meminfo(); cur = cpu_times(); ca, cm = cpu_load(prev, cur); prev = cur
            if n % 3 == 0:                    # the heavier looks every 6 s
                top, rtop = gpu_top(), ram_top()
                try:
                    log = subprocess.run(["journalctl", "-k", "--since", self.start, "--no-pager", "-o", "cat"],
                                         capture_output=True, text=True, timeout=10).stdout.splitlines()
                    errs = [l for l in log if P_GPUMEM.search(l) and P_VMREF not in l]
                    vm = sum(1 for l in log if P_VMREF in l)
                except (OSError, subprocess.SubprocessError): errs, vm = self.errors, self.vmref
            n += 1
            zr = sum(int(rd(z, "0 0 0").split()[2]) for z in glob.glob("/sys/block/zram*/mm_stat")) // 2**20
            s = {"t": time.strftime("%H:%M:%S"), "cpu": ca, "cpumax": cm, "gpu": num(DEV + "/gpu_busy_percent") if DEV else 0,
                 "vram": num(DEV + "/mem_info_vram_used") >> 20 if DEV else 0, "gtt": num(DEV + "/mem_info_gtt_used") >> 20 if DEV else 0,
                 "ram": m.get("MemTotal", 0) - m.get("MemAvailable", 0), "avail": m.get("MemAvailable", 0),
                 "swap": m.get("SwapTotal", 0) - m.get("SwapFree", 0), "zram": zr, "disk": disk_swap()[1],
                 "temp": num(T_CHIP) // 1000 if T_CHIP else None,
                 "top": top, "ramtop": rtop, "errors": len(errs)}
            with self.lock:
                self.samples.append(s); self.total += 1; self.samples = self.samples[-KEEP:]; self.errors = errs[-5:]; self.vmref = vm

    def summary(self, info):                 # the peaks and the same verdict as the terminal monitor
        S = self.samples
        if not S: return {}
        pk = lambda k: max((x[k] or 0) for x in S)
        n = len(S); minav = min(x["avail"] for x in S); s0 = S[0]["swap"]
        v = []
        ram_short = minav < 512 or pk("swap") > s0 + 512
        vram_full = info["vt"] > 0 and pk("vram") * 100 / info["vt"] >= 90
        if info["st"] > 0 and pk("swap") >= info["st"] - 64:
            v.append(L("La swap se llenó: si el juego pide más memoria, el sistema lo cierra. Agrándala (ajuste zram) o añade swap en disco (ajuste swapdisco).",
                       "The swap filled up: if the game asks for more memory, the system kills it. Make it bigger (setting zram) or add disk swap (setting swapdisco)."))
        if pk("disk") >= 256:
            v.append(L(f"Usó {pk('disk') / 1024:.1f} GB de swap en disco: el juego siguió, pero más lento en esos momentos. Si el sistema entero se congeló, quítala (ajuste swapdisco).",
                       f"Used {pk('disk') / 1024:.1f} GB of disk swap: the game kept going, but slower at those moments. If the whole system froze, remove it (setting swapdisco)."))
        if ram_short and vram_full:
            v.append(L("Van justas las dos (VRAM llena y Linux tirando de swap): baja texturas o calidad en el juego.",
                       "Both are tight (VRAM full and Linux leaning on swap): lower textures or quality in the game."))
        elif ram_short:
            v.append(L("Se acabó la RAM, no la VRAM: baja la VRAM a su pico + 1 GB (ajuste vram) y las texturas del juego.",
                       "RAM ran out, not VRAM: lower the VRAM to its peak + 1 GB (setting vram) and the game's textures."))
        elif vram_full:
            v.append(L("La VRAM se llenó y a Linux le sobra RAM: sube la VRAM (ajuste vram) o baja la resolución.",
                       "VRAM filled up and Linux has RAM to spare: raise the VRAM (setting vram) or lower the resolution."))
        if sum(1 for x in S if x["gpu"] >= 95) * 2 >= n:
            v.append(L("La GPU va al máximo casi siempre: ella marca los FPS. Baja resolución o calidad, o usa reescalado.",
                       "The GPU is maxed out almost all the time: it sets the FPS. Lower resolution or quality, or use upscaling."))
        elif sum(1 for x in S if x["cpumax"] >= 95 and x["gpu"] < 85) * 10 >= n * 3:
            v.append(L("Un hilo de la CPU va lleno mientras la GPU espera: baja distancia de visión, multitudes o físicas.",
                       "One CPU thread is maxed out while the GPU waits: lower view distance, crowds or physics."))
        return {"vram": pk("vram"), "gtt": pk("gtt"), "ram": pk("ram"), "minavail": minav, "swap": pk("swap"), "swap0": s0,
                "zram": pk("zram"), "disk": pk("disk"), "cpu": pk("cpu"), "cpuavg": round(sum(x["cpu"] for x in S) / n),
                "gpu": pk("gpu"), "gpuavg": round(sum(x["gpu"] for x in S) / n), "temp": pk("temp"),
                "verdict": v, "vmref": self.vmref}

    def data(self, since):                   # since = how many samples of this session the page already has
        info = self.info()
        with self.lock:
            if self.running: self.seen = time.time()
            base = self.total - len(self.samples); off = since - base
            reset = off < 0 or off > len(self.samples)
            return {"running": self.running, "session": self.first, "start": self.start, "info": info, "saved": self.saved,
                    "ask": not self.running and len(self.samples) >= MIN_SAVE and not self.saved and not self.discarded,
                    "total": self.total, "reset": reset, "samples": self.samples if reset else self.samples[off:],
                    "summary": self.summary(info), "errors": self.errors}

    def csv(self):
        head = "hora,cpu_pct,cpu_hilo_max_pct,gpu_pct,vram_usada_mb,gtt_mb,ram_usada_mb,ram_disponible_mb,swap_usada_mb,zram_en_ram_mb,swap_disco_mb,temp_c,errores_gpu,top_vram,top_ram"
        with self.lock: S = list(self.samples)
        rows = [head] + [",".join(map(str, [x["t"], x["cpu"], x["cpumax"], x["gpu"], x["vram"], x["gtt"], x["ram"], x["avail"],
                        x["swap"], x["zram"], x["disk"], x["temp"] if x["temp"] is not None else "",
                        x["errors"], '"' + " ".join(f"{c} {m}M" for c, m in x["top"]) + '"', f'"{x["ramtop"][0]} {x["ramtop"][1]}M"'])) for x in S]
        return "\n".join(rows) + "\n"

MON = Monitor()

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass

    def ok_client(self):
        try: a = ipaddress.ip_address(self.client_address[0])
        except ValueError: return False
        if a.version == 6 and a.ipv4_mapped: a = a.ipv4_mapped
        return a.is_private or a.is_loopback

    def send(self, code, body, ctype, extra=()):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        for k, v in extra: self.send_header(k, v)
        self.end_headers(); self.wfile.write(b)

    def do_GET(self):
        if not self.ok_client(): return self.send(403, L("Solo desde tu red de casa.\n", "Only from your home network.\n"), "text/plain; charset=utf-8")
        path, _, q = self.path.partition("?")
        if path == "/": return self.send(200, PAGE, "text/html; charset=utf-8")
        if path == "/data":
            m = re.search(r"since=(-?\d+)", q)
            return self.send(200, json.dumps(MON.data(int(m.group(1)) if m else 0)), "application/json")
        if path == "/manifest.json":
            return self.send(200, json.dumps({"name": "Monitor PS5", "short_name": "Monitor PS5", "start_url": "/",
                                              "display": "standalone", "background_color": "#101418", "theme_color": "#101418"}),
                             "application/manifest+json")
        self.send(404, L("No existe.\n", "Not found.\n"), "text/plain; charset=utf-8")

    def do_POST(self):
        if not self.ok_client(): return self.send(403, "", "text/plain")
        if self.path == "/start": MON.begin()
        elif self.path == "/stop": MON.end()
        elif self.path == "/save": MON.save()
        elif self.path == "/discard": MON.discard()
        else: return self.send(404, "", "text/plain")
        self.send(200, "{}", "application/json")

TX = {
    "connecting": L("conectando…", "connecting…"),
    "start": L("Empezar", "Start"), "stop": L("Parar", "Stop"),
    "ask": L("¿Guardar las medidas de esta sesión en la PS5 (CSV)?", "Save this session's measurements on the PS5 (CSV)?"),
    "save": L("Guardar", "Save"), "no": L("No", "No"),
    "top_title": L("Más VRAM", "Most VRAM"), "peaks": L("Picos y veredicto", "Peaks and verdict"),
    "idle": L("Pulsa Empezar y juega: aquí saldrá qué te limita.", "Press Start and play: what is limiting you will show up here."),
    "legend_title": L("¿Qué es cada cosa?", "What is what?"),
    "legend_hint": L("También: pulsa (o pasa el ratón por) cualquier recuadro.", "Also: tap (or hover over) any box."),
    "temperature": L("Temperatura", "Temperature"), "thread": L("hilo", "thread"),
    "zram_used": L("ocupa {0} de RAM", "uses {0} of RAM"), "on_disk": L("en disco {0} de {1}", "on disk {0} of {1}"),
    "measuring": L("midiendo cada 2 s desde {0}", "sampling every 2 s since {0}"),
    "stopped": L("parado ({0} medidas)", "stopped ({0} samples)"), "waiting": L("en espera", "waiting"),
    "more_ram": L("más RAM: {0} {1} GB", "most RAM: {0} {1} GB"),
    "no_gpu_prog": L("ningún programa usa la GPU", "no program is using the GPU"),
    "s_vram": L("VRAM {0} de {1} GB · GTT {2} GB", "VRAM {0} of {1} GB · GTT {2} GB"),
    "s_ram": L("RAM {0} de {1} GB (libre como mínimo {2})", "RAM {0} of {1} GB (at least {2} free)"),
    "s_swap": L("Swap {0} GB (al empezar {1})", "Swap {0} GB (at start {1})"),
    "s_swapdisk": L(" · en disco {0} GB", " · on disk {0} GB"),
    "s_cpugpu": L("CPU {0}% de media, {1}% máx. · GPU {2}% de media, {3}% máx.", "CPU {0}% average, {1}% max. · GPU {2}% average, {3}% max."),
    "s_temp": L("Temperatura máx. {0}°", "Max. temperature {0}°"),
    "gpu_errors": L("Errores de memoria de la GPU:", "GPU memory errors:"),
    "vmref": L("{0} reservas de memoria rechazadas (no son de la GPU; los emuladores lo hacen y siguen).", "{0} memory reservations refused (not from the GPU; emulators do this and carry on)."),
    "ok_now": L("Sin aprietos por ahora.", "No squeeze for now."),
    "saved_at": L("Guardado en la PS5: ", "Saved on the PS5: "),
    "offline": L("sin conexión con la PS5…", "no connection to the PS5…"),
    "h_cpu": L("Uso medio del procesador (sus 16 hilos). «Hilo» es el más cargado: si llega al 100 % y la GPU no, la CPU frena el juego.",
               "Average processor use (its 16 threads). \"Thread\" is the busiest one: if it hits 100 % and the GPU doesn't, the CPU is holding the game back."),
    "h_gpu": L("Cuánto tiempo está trabajando la gráfica. Cerca del 100 % casi siempre: ella marca los FPS (baja resolución o calidad).",
               "How much of the time the graphics chip is working. Near 100 % almost always: it sets the FPS (lower resolution or quality)."),
    "h_vram": L("Memoria de la gráfica. El cargador la aparta de los 16 GB al arrancar (vram.txt) y Linux no la puede usar. Llena: tirones o cierres.",
                "Graphics memory. The loader sets it aside from the 16 GB at boot (vram.txt) and Linux can't use it. When full: stutter or crashes."),
    "h_gtt": L("RAM normal que la gráfica toma prestada cuando le falta VRAM o para datos que comparte con la CPU. Sale de la RAM de Linux.",
               "Normal RAM that the GPU borrows when it runs short of VRAM or for data it shares with the CPU. It comes out of Linux's RAM."),
    "h_ram": L("Memoria de Linux en uso: los 16 GB menos la VRAM. Con menos de 1 GB libre el sistema empieza a tirar de swap.",
               "Linux memory in use: the 16 GB minus the VRAM. With less than 1 GB free the system starts leaning on swap."),
    "h_swap": L("Memoria que el sistema aparta para hacer sitio en la RAM. Primero zram: comprimida en la propia RAM («ocupa»). Si hay swap en disco, solo se usa con la zram llena («en disco»): más lenta, pero el juego no se cierra. Si crece mientras juegas: tirones y cortes de sonido.",
                "Memory the system sets aside to make room in RAM. First zram: compressed in RAM itself (\"uses\"). If there is disk swap, it is only used when zram is full (\"on disk\"): slower, but the game doesn't get killed. If it grows while you play: stutter and audio dropouts."),
    "h_temp": L("Temperatura del chip. CPU y GPU son el mismo chip, con un solo sensor. El ventilador apunta a 80 °C; más de 90 °C es demasiado.",
                "Chip temperature. CPU and GPU are the same chip, with a single sensor. The fan aims for 80 °C; over 90 °C is too much."),
    "h_top": L("Los programas que más VRAM usan ahora, y el que más RAM.", "The programs using the most VRAM right now, and the one using the most RAM."),
}

PAGE = r"""<!doctype html><html lang="@@LANG@@"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#101418">
<link rel="manifest" href="/manifest.json"><title>Monitor PS5</title>
<style>
:root{--bg:#101418;--card:#1a2027;--line:#2a323b;--tx:#e6ebf0;--mu:#8b98a5;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--acc:#58a6ff}
*{box-sizing:border-box}html,body{overflow-x:hidden}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.4 system-ui,-apple-system,sans-serif;padding:12px 12px 40px}
h1{font-size:18px;margin:4px 0 2px}.sub{color:var(--mu);font-size:13px;margin-bottom:12px}
.row{display:flex;gap:8px;margin-bottom:12px}button,.btn{flex:1;border:0;border-radius:10px;padding:12px;font:600 16px system-ui;color:#fff;background:var(--acc);text-align:center;text-decoration:none}
button.stop{background:#30363d}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px;min-width:0;overflow-wrap:anywhere}
.k{color:var(--mu);font-size:12px;text-transform:uppercase;letter-spacing:.04em}.v{font-size:22px;font-weight:700;margin:2px 0}
.v small{font-size:13px;color:var(--mu);font-weight:500}canvas{width:100%;height:42px;display:block}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.full{grid-column:1/-1}
ul{margin:6px 0 0;padding-left:18px}li{margin:3px 0}.mu{color:var(--mu)}
.card[title]{cursor:help}.help{display:none;color:var(--mu);font-size:13px;margin-top:6px}.card.open .help{display:block}
.k .q{opacity:.6}details summary{cursor:pointer}dl{margin:6px 0 0}dt{font-weight:600;margin-top:8px}dd{margin:2px 0 0;color:var(--mu)}
</style></head><body>
<h1>Monitor PS5</h1><div class="sub" id="sub">@@connecting@@</div>
<div class="row"><button id="go">@@start@@</button></div>
<div class="card full" id="ask" style="display:none;margin-bottom:12px"><div style="margin-bottom:8px">@@ask@@</div>
<div class="row" style="margin:0"><button id="yes">@@save@@</button><button id="no" class="stop">@@no@@</button></div></div>
<div class="grid" id="tiles"></div>
<div class="card full" style="margin-top:8px" id="t_top"><div class="k">@@top_title@@ <span class="q">ⓘ</span></div><div id="top" class="mu">—</div></div>
<div class="mu" id="saved" style="margin:0 2px 8px;font-size:13px"></div>
<div class="card full" style="margin-top:8px"><div class="k">@@peaks@@</div><div id="sum" class="mu">@@idle@@</div></div>
<details class="card full" style="margin-top:8px"><summary class="k">@@legend_title@@</summary><dl id="legend"></dl>
<div class="mu" style="font-size:13px;margin-top:8px">@@legend_hint@@</div></details>
<script>
const X=@@TX@@;
const f=(s,...a)=>s.replace(/\{(\d)\}/g,(_,i)=>a[i]);
const T=[["cpu","CPU","%"],["gpu","GPU","%"],["vram","VRAM","GB"],["gtt","GTT","GB"],["ram","RAM","GB"],["swap","Swap","GB"],["temp",X.temperature,"°C"]];
const HELP={cpu:X.h_cpu,gpu:X.h_gpu,vram:X.h_vram,gtt:X.h_gtt,ram:X.h_ram,swap:X.h_swap,temp:X.h_temp,top:X.h_top};
const $=id=>document.getElementById(id);
let S=[],got=0,info={},running=false,session=0,timer=null;
const g=b=>(b/1024).toFixed(1);
$("tiles").innerHTML=T.map(([k,n])=>`<div class="card${k=="temp"?" full":""}" id="t_${k}"><div class="k">${n} <span class="q">ⓘ</span></div><div class="v" id="v_${k}">—</div><canvas id="c_${k}"></canvas></div>`).join("");
$("legend").innerHTML=T.concat([["top",X.top_title]]).map(([k,n])=>`<dt>${n}</dt><dd>${HELP[k]}</dd>`).join("");
Object.keys(HELP).forEach(k=>{const c=$("t_"+k);if(!c)return;c.title=HELP[k];c.insertAdjacentHTML("beforeend",`<div class="help">${HELP[k]}</div>`);
 c.onclick=()=>c.classList.toggle("open")});
function cls(k,x){const vt=info.vt||1;if(k=="vram")return x.vram/vt>=.9?"bad":x.vram/vt>=.8?"warn":"ok";
 if(k=="ram")return x.avail<512?"bad":x.avail<1024?"warn":"ok";if(k=="gpu")return x.gpu>=95?"warn":"ok";
 if(k=="cpu")return x.cpumax>=95?"warn":"ok";if(k=="temp")return (x.temp||0)>=90?"bad":(x.temp||0)>=80?"warn":"ok";
 if(k=="swap")return info.st&&x.swap>=info.st-64?"bad":"ok";return"ok"}
function text(k,x){switch(k){case"cpu":return`${x.cpu}% <small>${X.thread} ${x.cpumax}%</small>`;case"gpu":return`${x.gpu}%`;
 case"vram":return`${g(x.vram)} <small>/ ${g(info.vt)}</small>`;case"gtt":return`${g(x.gtt)} <small>/ ${g(info.gt)}</small>`;
 case"ram":return`${g(x.ram)} <small>/ ${g(info.rt)}</small>`;case"swap":return`${g(x.swap)} <small>/ ${g(info.st)}</small>${info.zram?`<br><small>${f(X.zram_used,g(x.zram))}</small>`:""}${info.sd?`<br><small>${f(X.on_disk,g(x.disk||0),g(info.sd))}</small>`:""}`;
 default:return x[k]==null?"—":`${x[k]}°`}}
function max(k){return {cpu:100,gpu:100,vram:info.vt,gtt:info.gt,ram:info.rt,swap:info.st||1,temp:100}[k]||1}
function spark(k){const c=$("c_"+k),w=c.width=c.clientWidth*devicePixelRatio,h=c.height=42*devicePixelRatio,x=c.getContext("2d");
 const d=S.slice(-150),m=max(k);x.clearRect(0,0,w,h);if(d.length<2)return;x.beginPath();
 d.forEach((s,i)=>{const px=i*w/(d.length-1),py=h-(Math.min(s[k]||0,m)/m)*(h-4)-2;i?x.lineTo(px,py):x.moveTo(px,py)});
 x.strokeStyle=getComputedStyle(document.body).getPropertyValue("--acc");x.lineWidth=2*devicePixelRatio;x.stroke()}
function draw(){const x=S[S.length-1];
 $("sub").textContent=`${info.host||"PS5"} · ${running?f(X.measuring,window._start||""):S.length?f(X.stopped,S.length):X.waiting}`;
 $("go").textContent=running?X.stop:X.start;$("go").className=running?"stop":"";
 if(!x)return;T.forEach(([k])=>{const e=$("v_"+k);e.innerHTML=text(k,x);e.className="v "+cls(k,x);spark(k)});
 $("top").innerHTML=x.top.length?x.top.map(([c,m])=>`${c} <b>${(m/1024).toFixed(1)} GB</b>`).join(" · ")+`<br><span class="mu">${f(X.more_ram,x.ramtop[0],(x.ramtop[1]/1024).toFixed(1))}</span>`:X.no_gpu_prog}
function summary(s,err){if(!s||!s.vram&&s.vram!==0){return}
 let h=`<ul><li>${f(X.s_vram,g(s.vram),g(info.vt),g(s.gtt))}</li><li>${f(X.s_ram,g(s.ram),g(info.rt),g(s.minavail))}</li>
 <li>${f(X.s_swap,g(s.swap),g(s.swap0))}${info.sd?f(X.s_swapdisk,g(s.disk||0)):""}</li><li>${f(X.s_cpugpu,s.cpuavg,s.cpu,s.gpuavg,s.gpu)}</li>
 <li>${f(X.s_temp,s.temp||"?")}</li></ul>`;
 if(err&&err.length)h+=`<div class="bad" style="margin-top:6px">${X.gpu_errors}</div><ul class="bad">${err.map(e=>`<li>${e.replace(/</g,"&lt;")}</li>`).join("")}</ul>`;
 if(s.vmref)h+=`<div class="mu" style="margin-top:6px">${f(X.vmref,s.vmref)}</div>`;
 h+=s.verdict.length?`<ul>${s.verdict.map(v=>`<li class="warn">${v}</li>`).join("")}</ul>`:`<div class="ok" style="margin-top:6px">${X.ok_now}</div>`;
 $("sum").innerHTML=h}
async function poll(){try{const same=session&&got,r=await fetch("/data?since="+(same?got:-1)),d=await r.json();
 info=d.info;running=d.running;window._start=(d.start||"").slice(11);
 if(d.session!=session||d.reset||!same){session=d.session;S=d.samples}else S=S.concat(d.samples).slice(-1800);
 got=d.total;draw();summary(d.summary,d.errors);
 $("ask").style.display=d.ask?"":"none";
 $("saved").textContent=d.saved?(d.saved.startsWith("/")?X.saved_at+d.saved:d.saved):""}catch(e){$("sub").textContent=X.offline}
 clearTimeout(timer);timer=setTimeout(poll,document.visibilityState=="visible"?(running?2000:5000):15000)}
$("yes").onclick=async()=>{await fetch("/save",{method:"POST"});setTimeout(poll,300)};
$("no").onclick=async()=>{await fetch("/discard",{method:"POST"});setTimeout(poll,300)};
$("go").onclick=async()=>{await fetch(running?"/stop":"/start",{method:"POST"});setTimeout(poll,300)};
document.addEventListener("visibilitychange",()=>{if(document.visibilityState=="visible")poll()});poll();
</script></body></html>"""
PAGE = PAGE.replace("@@LANG@@", LANG)
for _k, _v in TX.items(): PAGE = PAGE.replace(f"@@{_k}@@", _v)
PAGE = PAGE.replace("@@TX@@", json.dumps(TX, ensure_ascii=False).replace("</", "<\\/"))

if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H); srv.daemon_threads = True
    print(L(f"Monitor PS5 en http://<dirección de la consola>:{PORT}", f"Monitor PS5 at http://<console address>:{PORT}"), flush=True)
    srv.serve_forever()
__MONWEB__
}
lan_dev() { ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'; }
lan_net() { ip -o -4 route show dev "$(lan_dev)" scope link 2>/dev/null | awk '{ print $1; exit }'; }
lan_ip() { ip -o -4 addr show dev "$(lan_dev)" 2>/dev/null | awk '{ sub(/\/.*/, "", $4); print $4; exit }'; }
monweb_rule() { printf 'rule family="ipv4" source address="%s" port port="%s" protocol="tcp" accept' "$(lan_net)" "$MONWEB_PORT"; }
monweb_fw() { systemctl is-active -q firewalld; }
desc_monitorweb() {
    section
    case $TB_LANG in
        es)
    say "El monitor en directo (opción 4) en el navegador del móvil: http://$(lan_ip || echo '<IP de la consola>'):$MONWEB_PORT"
    say "Guárdalo en la pantalla de inicio. «Empezar» mide cada 2 s (CPU, GPU, VRAM, RAM, swap, temperatura,"
    say "qué gasta más, picos y qué te limita); sin ninguna página abierta 10 min, para solo. Al parar pregunta si guardar"
    say "las medidas en la PS5 ($MONWEB_CSV_DIR/ps5-mem-FECHA.csv)."
    say "Instala $MONWEB_PY y el servicio de tu usuario ps5-monitor-web (arranca con la sesión, sin root), y abre"
    say "el puerto $MONWEB_PORT en el cortafuegos solo para tu red ($(lan_net)). Solo enseña datos; no tiene clave:"
    say "cualquiera en tu red que sepa la dirección lo puede ver. Esperando gasta ~25 MB de RAM y nada de CPU."
    say "POR QUÉ: ver cómo va un juego desde el móvil, sin SSH ni abrir nada en la consola."
    say "DESHACER: systemctl --user disable --now ps5-monitor-web; rm $MONWEB_UNIT $MONWEB_PY;"
    say "  sudo firewall-cmd --permanent --remove-rich-rule='$(monweb_rule)'; sudo firewall-cmd --reload"
            ;;
        *)
    say "The live monitor (option 4) in your phone's browser: http://$(lan_ip || echo '<console IP>'):$MONWEB_PORT"
    say "Save it to the home screen. \"Start\" samples every 2 s (CPU, GPU, VRAM, RAM, swap, temperature,"
    say "what uses the most, peaks and what limits you); with no page open for 10 min, it stops by itself. When stopped it asks whether to save"
    say "the measurements on the PS5 ($MONWEB_CSV_DIR/ps5-mem-DATE.csv)."
    say "Installs $MONWEB_PY and the ps5-monitor-web service for your user (starts with the session, no root), and opens"
    say "port $MONWEB_PORT in the firewall for your network only ($(lan_net)). It only shows data; it has no password:"
    say "anyone on your network who knows the address can see it. While waiting it uses ~25 MB of RAM and no CPU."
    say "WHY: to see how a game is doing from your phone, without SSH or opening anything on the console."
    say "UNDO: systemctl --user disable --now ps5-monitor-web; rm $MONWEB_UNIT $MONWEB_PY;"
    say "  sudo firewall-cmd --permanent --remove-rich-rule='$(monweb_rule)'; sudo firewall-cmd --reload"
            ;;
    esac
}
check_monitorweb() {
    command -v python3 >/dev/null || return 2
    cmp -s <(monweb_script) "$MONWEB_PY" || return 1          # missing, or an older toolbox's version
    grep -qsx "Environment=TB_LANG=$TB_LANG" "$MONWEB_UNIT" || return 1   # the service speaks the language chosen at install time
    systemctl --user is-enabled -q ps5-monitor-web 2>/dev/null && systemctl --user is-active -q ps5-monitor-web || return 1
    ! monweb_fw || sudo firewall-cmd --query-rich-rule="$(monweb_rule)" >/dev/null 2>&1
}
apply_monitorweb() {
    mkdir -p "$(dirname "$MONWEB_PY")" "$(dirname "$MONWEB_UNIT")" || return 1
    monweb_script >"$MONWEB_PY" || return 1
    cat >"$MONWEB_UNIT" <<EOF || return 1
[Unit]
Description=$(L 'Monitor de la PS5 en el navegador (ps5-bazzite-toolbox, bloque monitorweb)' 'PS5 monitor in the browser (ps5-bazzite-toolbox, block monitorweb)')

[Service]
Environment=TB_LANG=$TB_LANG
ExecStart=/usr/bin/python3 $MONWEB_PY --port $MONWEB_PORT --csv-dir $MONWEB_CSV_DIR
Restart=on-failure
Nice=10
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload && systemctl --user enable ps5-monitor-web && systemctl --user restart ps5-monitor-web || return 1
    if monweb_fw && [ "$(fw_state)" != running ]; then
        echo "  $(L 'El cortafuegos está fallido y no admite abrir el puerto: aplica antes el bloque firewall (opción 16 → firewall).' 'The firewall is in a failed state and cannot open the port: apply the firewall block first (option 16 → firewall).')"
        return 1
    fi
    if monweb_fw; then
        sudo firewall-cmd --permanent --add-rich-rule="$(monweb_rule)" >/dev/null && sudo firewall-cmd --reload >/dev/null || return 1
    fi
    sleep 1
    curl -fs -o /dev/null "http://127.0.0.1:$MONWEB_PORT/" || { echo "  $(L 'El servicio no responde' 'The service does not respond'): journalctl --user -u ps5-monitor-web"; return 1; }
    say "$(L "Ábrelo en el móvil (conectado a tu wifi): http://$(lan_ip):$MONWEB_PORT" "Open it on your phone (connected to your wifi): http://$(lan_ip):$MONWEB_PORT")"
}

# --- atajos --------------------------------------------------------------------------------------
# Desktop shortcuts that call this toolbox, so they follow it when it is updated.
TOOLBOX_SELF=$(realpath "$0" 2>/dev/null)
SM_DIR=$HOME/.local/share/kio/servicemenus
SM_GAME=$SM_DIR/ps5-bazzite-toolbox-add-game.desktop
SM_SPACE=$SM_DIR/ps5-bazzite-toolbox-space.desktop
SPACE_BIN=/usr/local/bin/espacio
desk_dir() { xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop"; }
# run_then_close SECONDS ARGS... -> the shell command a launcher runs: the toolbox with ARGS, then the window
# closes after SECONDS if it went well, or waits for Enter so an error can be read
run_then_close() {
    local secs=$1 closing errmsg; shift
    closing=$(L "Se cierra en $secs s…" "Closes in $secs s…")
    errmsg=$(L 'Pulsa Intro para cerrar.' 'Press Enter to close.')
    printf '%s' "bash \"$TOOLBOX_SELF\" $*; rc=\$?; if [ \$rc = 0 ]; then echo; echo \"$closing\"; sleep $secs; else echo; echo \"Error (\$rc). $errmsg\"; read -r _; fi"
}
# The desktop "Colección PortProton" shortcut of v1.x: no longer made (adding, changing and removing a game already
# sync the collection; menu option 12 does it by hand). apply_atajos removes it.
COLL_DESKTOP="$(desk_dir)/portproton-collection.desktop"
desc_atajos() {
    section
    case $TB_LANG in
        es)
    say "Atajos que llaman a este toolbox ($TOOLBOX_SELF):"
    say "- Dolphin, botón derecho sobre un .exe: «Instalar en PortProton y Steam», «Cambiar aislamiento» y «Desinstalar» ($SM_GAME);"
    say "- Dolphin, botón derecho sobre una carpeta: «Ver lo que ocupa cada carpeta» ($SM_SPACE);"
    say "- el comando «espacio [carpeta]» en cualquier terminal ($SPACE_BIN);"
    say "La colección «PortProton» de Steam se actualiza sola al instalar, cambiar o desinstalar un juego (y a mano,"
    say "opción 12): el acceso «Colección PortProton» del escritorio ya no hace falta y este bloque lo quita si lo hay."
    say "POR QUÉ: tenerlos tras instalar desde cero; antes eran scripts sueltos en ~ (add-proton-game.sh,"
    say "portproton-collection.sh, verEspacioCadaDirectorio.sh), que este bloque ya no necesita."
    say "Si mueves el toolbox de sitio, repite este bloque. DESHACER: rm '$SM_GAME' '$SM_SPACE'; sudo rm $SPACE_BIN"
            ;;
        *)
    say "Shortcuts that call this toolbox ($TOOLBOX_SELF):"
    say "- Dolphin, right-click on an .exe: \"Install in PortProton and Steam\", \"Change isolation\" and \"Uninstall\" ($SM_GAME);"
    say "- Dolphin, right-click on a folder: \"See what each folder takes up\" ($SM_SPACE);"
    say "- the command \"espacio [folder]\" in any terminal ($SPACE_BIN);"
    say "The Steam \"PortProton\" collection updates itself when you install, change or uninstall a game (and by hand,"
    say "option 12): the desktop \"PortProton Collection\" shortcut is no longer needed and this block removes it if present."
    say "WHY: to have them after a fresh install; they used to be loose scripts in ~ (add-proton-game.sh,"
    say "portproton-collection.sh, verEspacioCadaDirectorio.sh), which this block no longer needs."
    say "If you move the toolbox, repeat this block. UNDO: rm '$SM_GAME' '$SM_SPACE'; sudo rm $SPACE_BIN"
            ;;
    esac
}
check_atajos() {
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] || return 2       # run from a pipe: nothing to point at
    # a missing file makes grep return 2, which here means "doesn't apply": anything missing is pending (1)
    grep -qs -F "$TOOLBOX_SELF" "$SM_GAME" && grep -qs -F "$TOOLBOX_SELF" "$SM_SPACE" &&
        grep -qs -F "$TOOLBOX_SELF" "$SPACE_BIN" && [ ! -e "$COLL_DESKTOP" ] && grep -qs -F "$(L 'Se cierra en' 'Closes in')" "$SM_GAME" &&
        grep -qs -- '--remove-game' "$SM_GAME" && grep -qs -- '--change-level' "$SM_GAME" || return 1   # launchers that close by themselves
}
apply_atajos() {
    mkdir -p "$SM_DIR" "$(desk_dir)" || return 1
    cat >"$SM_GAME" <<EOF
[Desktop Entry]
Type=Service
MimeType=application/vnd.microsoft.portable-executable;application/x-ms-dos-executable;application/x-msdownload;
Actions=addProtonGame;changeProtonGame;removeProtonGame;
X-KDE-Priority=TopLevel

[Desktop Action addProtonGame]
Name=$(L 'Instalar en PortProton y Steam (normal o aislado)' 'Install in PortProton and Steam (normal or isolated)')
Icon=ru.linux_gaming.PortProton
Exec=konsole -e bash -c '$(run_then_close 5 '--add-game "$1"')' _ %f

[Desktop Action changeProtonGame]
Name=$(L 'Cambiar aislamiento (normal, aislado con red o sin red)' 'Change isolation (normal, isolated with network or without network)')
Icon=security-medium
Exec=konsole -e bash -c '$(run_then_close 5 '--change-level "$1"')' _ %f

[Desktop Action removeProtonGame]
Name=$(L 'Desinstalar (de Steam, PortProton y el disco; pregunta cada paso)' 'Uninstall (from Steam, PortProton and disk; asks at each step)')
Icon=edit-delete
Exec=konsole -e bash -c '$(run_then_close 5 '--remove-game "$1"')' _ %f
EOF
    cat >"$SM_SPACE" <<EOF
[Desktop Entry]
Type=Service
MimeType=inode/directory;
Actions=space;

[Desktop Action space]
Name=$(L 'Ver lo que ocupa cada carpeta' 'See what each folder takes up')
Icon=filelight
Exec=konsole --hold -e bash "$TOOLBOX_SELF" --space %f
EOF
    chmod +x "$SM_GAME" "$SM_SPACE"      # Plasma 6 ignores service menus that aren't executable
    printf '#!/bin/sh\n# espacio [CARPETA]: lo que ocupa cada carpeta de CARPETA (ps5-bazzite-toolbox.sh --space)\nexec bash "%s" --space "$@"\n' \
        "$TOOLBOX_SELF" | sudo tee "$SPACE_BIN" >/dev/null && sudo chmod 755 "$SPACE_BIN" || return 1
    # the stand-alone versions this replaces (made by hand or by add-proton-game.sh --install)
    rm -f "$SM_DIR/add-proton-game.desktop" "$HOME/.local/bin/add-proton-game.sh" "$COLL_DESKTOP" \
        "$SM_DIR/ps5-toolbox-add-game.desktop" "$SM_DIR/ps5-toolbox-space.desktop"    # names before v1.0.0
    local old; old=$(cd ~ && ls portproton-collection.sh verEspacioCadaDirectorio.sh parpadeoVideo.sh 2>/dev/null | tr '\n' ' ')
    [ -n "$old" ] && say "$(L "Ya no hacen falta (bórralos si quieres): ~/${old// / ~/}" "No longer needed (delete them if you like): ~/${old// / ~/}")"
    say "$(L 'Si Dolphin estaba abierto, ciérralo y ábrelo para ver las acciones nuevas.' 'If Dolphin was open, close it and reopen it to see the new actions.')"
}

# --- recommended answer per block ------------------------------------------------------------------
default_for() {
    case $1 in
        warmreboot) echo N ;;
        hdmi) warm_on && echo S || echo N ;;
        brave|edge) echo N ;;
        monitorweb) echo N ;;            # a server always listening: only if you want it            # loses the browser's saved logins: only if the wallet prompt bothers you
        nas) [ -n "${NAS_IP:-}" ] && echo S || echo N ;;
        bios|media) echo N ;;            # a choice, not a fix: only if you want them shared from the NAS
        gpu40) echo N ;;                 # silicon lottery: only if you want to try it
        swapdisco) echo N ;;             # disk space and, on USB, stall risk: only if games get killed for memory
        *) echo S ;;
    esac
}

# ======================================== diagnosis ========================================
# Kernel messages worth knowing about, by area (extended regexes, case-insensitive)
P_DISK='timing out command|uas_eh_abort|I/O error|blk_update_request|EXT4-fs error|reset (SuperSpeed|high-speed)[^,]* USB device'
P_GPU='ring [a-z_0-9.]+ timeout|ring [a-z_0-9.]+ reset|gpu reset|page fault|PROTECTION_FAULT|amdgpu.*\*ERROR\*'
P_HANG='blocked for more than|hung_task|soft lockup|hard LOCKUP|watchdog: BUG|kernel BUG|Oops|general protection fault'
P_OOM='Out of memory|oom-kill|Killed process'
P_WIFI='woal_[a-z_]+.*(fail|timeout|error)|Firmware Init Failed|WLAN FW already running|moal.*(fail|error)'
P_BT='Bluetooth: hci[0-9]+: .*(timeout|failed)'
P_USB='USB disconnect'
P_SALINA='Salina poller'

watch_kernel() {
    echo "$(L "Vigilando el kernel (disco, GPU, cuelgues, memoria, Wi-Fi, Bluetooth, USB). Ctrl+C para salir." "Watching the kernel (disk, GPU, hangs, memory, Wi-Fi, Bluetooth, USB). Ctrl+C to quit.")"
    sudo journalctl -k -f -n 0 --no-pager |
        grep --line-buffered -iE "$P_DISK|$P_GPU|$P_HANG|$P_OOM|$P_WIFI|$P_BT|$P_USB"
}

# --- graphical session (was ps5-session.sh) ----------------------------------------------------------------
# Why restart this way: "systemctl restart sddm" leaves the previous kwin_wayland/gamescope alive (Plasma runs
# under the persistent systemd user manager), still holding the DRM output and wayland-0, so the new session
# stays black. Stop, close the sessions, kill leftovers, then start.
OVERRIDE=/etc/sddm.conf.d/zzz-ps5-session.conf     # sorts after zz-holo-autologin.conf
# process names are truncated to 15 chars (kwin_wayland_wrapper -> kwin_wayland_wr)
COMPOSITORS='kwin_wayland|kwin_wayland_wr|plasmashell|gamescope|gamescope-wl|gamescope-sessi|steam'
compositor_alive() { pgrep -u "$U" -x 'kwin_wayland|gamescope|gamescope-wl' >/dev/null; }
session_status() {
    echo "$(L "== Sesión configurada" "== Configured session")"
    if [ -f "$OVERRIDE" ]; then grep Session "$OVERRIDE"; else echo "$(L "Session=modo juego (la de la imagen)" "Session=game mode (the image default)")"; fi
    echo "$(L "== Sesiones gráficas" "== Graphical sessions")"
    loginctl list-sessions --no-legend | awk '$4 == "seat0"' | while read -r id _; do
        # a session can vanish between list and show while sddm relaunches it
        loginctl show-session "$id" -p Id -p Type -p Active -p State -p VTNr 2>/dev/null | tr '\n' ' ' || true; echo
    done
    echo "$(L "== Compositores" "== Compositors")"
    pgrep -a -u "$U" -x 'kwin_wayland|plasmashell|gamescope|gamescope-wl' || echo "$(L "(ninguno)" "(none)")"
    echo "== SDDM: $(systemctl is-active sddm)"
    sudo journalctl -b -u sddm --no-pager -o short 2>/dev/null | grep 'Starting Wayland' | tail -3
}
session_restart() {
    echo "$(L "==> Parando SDDM y cerrando la sesión gráfica anterior…" "==> Stopping SDDM and closing the previous graphical session…")"
    sudo systemctl stop sddm
    for id in $(loginctl list-sessions --no-legend | awk '$4 == "seat0" {print $1}'); do
        sudo loginctl terminate-session "$id" 2>/dev/null || true
    done
    sleep 2
    sudo pkill -u "$U" -x "$COMPOSITORS" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -u "$U" -x "$COMPOSITORS" 2>/dev/null || true
    if compositor_alive; then
        echo "$(L "Sigue vivo un compositor:" "A compositor is still alive:")"; pgrep -a -u "$U" -x 'kwin_wayland|gamescope|gamescope-wl'
        return 1
    fi
    echo "$(L "==> Arrancando SDDM…" "==> Starting SDDM…")"
    sudo systemctl start sddm
    sleep 8
    session_status
}
session() {
    case $1 in
        status) session_status ;;
        restart) session_restart ;;
        desktop|plasma)
            printf '[Autologin]\nUser=%s\nSession=plasma.desktop\n' "$U" | sudo tee "$OVERRIDE" >/dev/null
            session_restart ;;
        gamemode) sudo rm -f "$OVERRIDE"; session_restart ;;
        *) echo "$(L "Uso: --session status|restart|desktop|gamemode" "Usage: --session status|restart|desktop|gamemode")" >&2; return 2 ;;
    esac
}

run_checks() {
NEED_SESSION=0 NEED_BT=0
LOG=$(mktemp "${TMPDIR:-/tmp}/ps5-diag.XXXXXX") REPORT=ps5-diag-$(date +%Y%m%d-%H%M%S).txt
OK=0 WARN=0 BAD=0
log() { printf '%s\n' "$@" >>"$LOG"; }
head_() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; log "" "== $1 =="; }
ok()   { OK=$((OK + 1));     printf '  %s✔%s %s\n' "$G" "$N" "$1"; log "  OK    $1"; }
warn() { WARN=$((WARN + 1)); printf '  %s!%s %s\n' "$Y" "$N" "$1"; log "  $(L AVISO WARN) $1"; }
bad()  { BAD=$((BAD + 1));   printf '  %s✘%s %s\n' "$R" "$N" "$1"; log "  $(L "MAL  " "BAD  ") $1"; }
info() { printf '    %s\n' "$1"; log "    $1"; }
raw()  { log "  --- $1"; sed 's/^/    | /' >>"$LOG"; }       # stdin -> report only

KLOG=$(sudo journalctl -k -b "$BOOT" --no-pager -o short-precise 2>/dev/null)
kcount() { grep -ciE "$1" <<<"$KLOG"; }
kshow() { grep -iE "$1" <<<"$KLOG" | tail -"${2:-15}"; }
check_k() {                              # check_k "area" pattern ok|warn|bad -> count, last lines to the report
    local n; n=$(kcount "$2")
    if [ "$n" = 0 ]; then ok "$(L "$1: nada" "$1: nothing")"
    else
        "$3" "$(L "$1: $n mensajes" "$1: $n messages")"; kshow "$2" 3 | while IFS= read -r l; do info "${l:0:150}"; done
        kshow "$2" 30 | raw "$(L "$1 (últimos 30)" "$1 (last 30)")"
    fi
}

# --- system ----------------------------------------------------------------------------------------
head_ "$(L "Sistema" "System")"
info "$(L Imagen Image) $(cat /etc/ps5-bazzite-deck-version 2>/dev/null || echo '?'), kernel $(uname -r), $(L arrancado booted) $(uptime -p)"
info "$(L 'Arranque analizado' 'Boot analysed'): $BOOT ($(sudo journalctl --list-boots --no-pager 2>/dev/null | awk -v b="$BOOT" '$1 == b { $1 = $2 = ""; print }' | sed 's/^ *//'))"
log "cmdline: $(cat /proc/cmdline)"
log "vram.txt: $(sudo cat "$VRAMTXT" 2>/dev/null)"
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' |
    grep -vE '^(bootloader-update|greenboot-healthcheck|ublue-os-media-automount)\.service$')
if [ -z "$failed" ]; then ok "$(L "Servicios: ninguno fallido (sin contar los 3 de ostree/automontaje, que no importan)" "Services: none failed (not counting the 3 ostree/automount ones, which don't matter)")"
else bad "$(L 'Servicios fallidos' 'Failed services'): $(echo $failed)"; for u in $failed; do systemctl status "$u" --no-pager -n 20 2>&1 | raw "$u"; done; fi
# did the previous boot end cleanly? a hang + forced power-off leaves no shutdown messages
prev=$((BOOT - 1))
if sudo journalctl -b "$prev" -n 0 >/dev/null 2>&1; then
    if sudo journalctl -b "$prev" --no-pager -n 300 2>/dev/null |
        grep -E >/dev/null 'systemd-shutdown|Reached target .*(Power-Off|Reboot|Halt|kexec)|Shutting down'; then
        ok "$(L "El arranque anterior terminó con un apagado o reinicio normal" "The previous boot ended with a normal shutdown or reboot")"
    else
        bad "$(L "El arranque anterior terminó de golpe (cuelgue o apagado forzado): usa --boot $prev para revisarlo" "The previous boot ended abruptly (hang or forced power-off): use --boot $prev to review it")"
        sudo journalctl -b "$prev" --no-pager -n 60 2>/dev/null | raw "$(L "últimas líneas del arranque $prev" "last lines of boot $prev")"
    fi
fi
info "$(L "Un arranque que se cuelga antes de escribir en el disco no deja rastro (ni siquiera aparece en la lista)." "A boot that hangs before writing to the disk leaves no trace (it does not even show up in the list).")"
sudo journalctl --list-boots --no-pager 2>/dev/null | tail -6 | raw "$(L "últimos arranques" "last boots")"

# --- boot drive --------------------------------------------------------------------------------------
head_ "$(L "Disco de arranque" "Boot drive")"
src=$(findmnt -no SOURCE / | sed 's/\[.*//'); disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
props=$(udevadm info -q property -n "/dev/$disk" 2>/dev/null)
if grep -q '^ID_BUS=usb' <<<"$props"; then
    info "USB $(sed -n 's/^ID_VENDOR_ID=//p' <<<"$props"):$(sed -n 's/^ID_MODEL_ID=//p' <<<"$props") $(sed -n 's/^ID_MODEL=//p' <<<"$props"), driver $(sed -n 's/^ID_USB_DRIVER=//p' <<<"$props")"
    lsusb -t 2>/dev/null | raw "lsusb -t"
else info "$(L "/dev/$disk (no es USB)" "/dev/$disk (not USB)")"; fi
check_k "$(L "Atascos y errores del disco" "Disk stalls and errors")" "$P_DISK" bad
use=$(df --output=pcent / | tail -1 | tr -dc 0-9)
if [ "$use" -ge 90 ]; then bad "$(L "Espacio: / al $use %" "Space: / at $use %")"; else ok "$(L "Espacio: / al $use % ($(df -h --output=avail / | tail -1 | tr -d ' ') libres)" "Space: / at $use % ($(df -h --output=avail / | tail -1 | tr -d ' ') free)")"; fi
if sudo test -f "$POLKIT_RULE"; then ok "$(L "Regla anti-SMART de KDE puesta (el escritorio no se atasca)" "KDE anti-SMART rule in place (the desktop does not stall)")"
elif grep -q '^ID_BUS=usb' <<<"$props"; then warn "$(L "Sin la regla anti-SMART de KDE: el paso al escritorio puede tardar ~60 s (bloque disk)" "No KDE anti-SMART rule: switching to the desktop can take ~60 s (block disk)")"; fi

# --- GPU -----------------------------------------------------------------------------------------------
head_ "$(L "Gráfica" "Graphics")"
dev=$(gpu_dev)
gb() { awk -v v="$(cat "$1" 2>/dev/null || echo 0)" 'BEGIN { printf "%.1f GB", v / 2^30 }'; }
info "$(L "VRAM $(gb "$dev/mem_info_vram_total") (usada $(gb "$dev/mem_info_vram_used")), RAM prestada a la GPU (GTT) $(gb "$dev/mem_info_gtt_used")" "VRAM $(gb "$dev/mem_info_vram_total") (used $(gb "$dev/mem_info_vram_used")), RAM lent to the GPU (GTT) $(gb "$dev/mem_info_gtt_used")")"
vt=$(cat "$dev/mem_info_vram_total" 2>/dev/null || echo 0)
[ "$vt" -lt $((1 << 31)) ] && warn "$(L "VRAM menor de 2 GB: los juegos DX12/UE5 pueden caerse con 'Not enough memory' (bloque vram)" "VRAM below 2 GB: DX12/UE5 games may crash with 'Not enough memory' (block vram)")"
check_k "$(L "Reinicios y fallos de la GPU" "GPU resets and failures")" "$P_GPU" warn
[ "$(kcount "$P_GPU")" = 0 ] || info "$(L "Al entrar en el modo juego es un fallo conocido de la imagen; si coincide con un juego, es el juego." "On entering game mode this is a known image issue; if it coincides with a game, it's the game.")"
[ "$(kcount "$P_GPU")" = 0 ] || [ "$(gpu_cu_now)" != 40 ] ||
    info "$(L "Tienes las 40 unidades de la GPU activas (bloque gpu40): si estos fallos son nuevos, prueba a volver a 36." "You have all 40 GPU units active (block gpu40): if these failures are new, try going back to 36.")"

# --- hangs, memory, crashes ----------------------------------------------------------------------------
head_ "$(L "Cuelgues, memoria y cierres" "Hangs, memory and crashes")"
check_k "$(L "Cuelgues del kernel" "Kernel hangs")" "$P_HANG" bad
dproc=$(ps -eo stat,pid,comm | awk '$1 ~ /^D/ && $3 != "ext4lazyinit"')
if [ -z "$dproc" ]; then ok "$(L "Procesos bloqueados ahora (estado D): ninguno" "Blocked processes right now (state D): none")"
else warn "$(L "Procesos en estado D ahora (si se repiten, algo está colgado): $(echo $dproc)" "Processes in state D right now (if they keep showing up, something is stuck): $(echo $dproc)")"; fi
check_k "$(L "Falta de memoria (OOM)" "Out of memory (OOM)")" "$P_OOM" bad
free -h | raw "free -h"
avail=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$avail" -lt 1024 ]; then warn "$(L "Memoria disponible: $avail MB" "Available memory: $avail MB")"; else ok "$(L "Memoria disponible: $((avail / 1024)) GB" "Available memory: $((avail / 1024)) GB")"; fi
ps -eo rss,comm --sort=-rss | head -11 | awk 'NR > 1 {printf "%6d MB  %s\n", $1 / 1024, $2}' | raw "$(L "procesos con más memoria" "processes using the most memory")"
dumps=$(coredumpctl list --since "-24h" --no-legend --no-pager 2>/dev/null)
if [ -z "$dumps" ]; then ok "$(L "Programas cerrados de golpe (24 h): ninguno" "Programs that crashed (24 h): none")"
else
    warn "$(L 'Programas cerrados de golpe (24 h)' 'Programs that crashed (24 h)'): $(awk '{ n = split($(NF - 1), p, "/"); print p[n] }' <<<"$dumps" | sort | uniq -c | sort -rn | awk '{printf "%s×%s ", $1, $2}')"
    raw "coredumpctl (24 h)" <<<"$dumps"
fi

# --- temperature and fans ------------------------------------------------------------------------------
head_ "$(L "Temperatura y ventilador" "Temperature and fan")"
t=$(sensors 2>/dev/null | awk '/^Tctl:|^edge:/ { gsub(/[+°C]/, "", $2); print int($2); exit }')
if [ -z "$t" ]; then warn "$(L "No puedo leer la temperatura (sensors)" "Cannot read the temperature (sensors)")"
elif [ "$t" -ge 85 ]; then bad "$(L "Temperatura: $t °C" "Temperature: $t °C")"
elif [ "$t" -ge 70 ]; then warn "$(L "Temperatura: $t °C (en reposo debería rondar 45 °C con ps5fan)" "Temperature: $t °C (at idle it should be around 45 °C with ps5fan)")"
else ok "$(L "Temperatura: $t °C" "Temperature: $t °C")"; fi
for s in ps5fan ps5boost ps5-perf; do
    systemctl list-unit-files "$s.service" >/dev/null 2>&1 &&
        info "$s: $(systemctl is-enabled "$s" 2>/dev/null)/$(systemctl is-active "$s" 2>/dev/null)"
done
command -v ps5-perf >/dev/null && info "$(ps5-perf status 2>/dev/null | head -1)"
[ -r "$FAN_SYS" ] && info "$(L 'Temperatura objetivo del ventilador' 'Fan target temperature'): $(cat "$FAN_SYS") °C $(L '(de fábrica 80; más baja = más frío y más ruido, bloque fans)' '(factory 80; lower = cooler and noisier, block fans)')"

# --- network, Wi-Fi, Bluetooth, NAS --------------------------------------------------------------------
head_ "$(L "Red, Wi-Fi, Bluetooth y NAS" "Network, Wi-Fi, Bluetooth and NAS")"
nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -v ':loopback:' | while IFS=: read -r d ty st; do info "$d ($ty): $st"; done
gw=$(ip route show default | awk '{print $3; exit}')
if [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1; then ok "$(L "Router ($gw) responde" "Router ($gw) responds")"; else bad "$(L "Sin respuesta del router ${gw:-(no hay ruta por defecto)}" "No response from the router ${gw:-(no default route)}")"; fi
if getent hosts github.com >/dev/null; then ok "$(L "DNS funciona" "DNS works")"; else bad "$(L "DNS no resuelve github.com" "DNS does not resolve github.com")"; fi
check_k "Driver Wi-Fi (moal)" "$P_WIFI" warn
check_k "Bluetooth" "$P_BT" warn
if lsusb -d 1286:2059 >/dev/null 2>&1 || [ -e /sys/class/bluetooth/hci0 ]; then
    if bt_present; then ok "$(L "Adaptador Bluetooth presente" "Bluetooth adapter present")"
    else bad "$(L "Bluetooth sin adaptador: el mando no puede conectar ('No default controller available')" "Bluetooth without adapter: the controller cannot connect ('No default controller available')")"; NEED_BT=1; fi
fi
check_k "$(L "Dispositivos USB desconectados" "USB devices disconnected")" "$P_USB" warn
for m in $(awk '$3 == "cifs" { print $2 }' /etc/fstab 2>/dev/null); do
    if timeout 20 ls "$m" >/dev/null 2>&1; then ok "$(L "NAS en $m accesible" "NAS at $m reachable")"; else bad "$(L "NAS en $m no responde (¿apagado o sin red?)" "NAS at $m not responding (powered off or no network?)")"; fi
done
if systemctl is-active -q firewalld 2>/dev/null; then
    if [ "$(fw_state)" = running ]; then ok "$(L "Cortafuegos funcionando (zona $(sudo firewall-cmd --get-default-zone 2>/dev/null))" "Firewall running (zone $(sudo firewall-cmd --get-default-zone 2>/dev/null))")"
    else fw_b=$(fw_bad); bad "$(L "Cortafuegos fallido: va con una zona mínima y no admite cambios${fw_b:+ (la zona $(fw_zone) usa $(echo $fw_b))}; bloque firewall" "Firewall failed: running with a minimal zone and accepting no changes${fw_b:+ (zone $(fw_zone) uses $(echo $fw_b))}; block firewall")"; fi
fi
info "$(L "Avisos 'Salina poller' (ruido del parche USB, no es un fallo): $(kcount "$P_SALINA")" "'Salina poller' warnings (USB patch noise, not a failure): $(kcount "$P_SALINA")")"

# --- settings (the setup blocks' own checks) ------------------------------------------------------
head_ "$(L "Ajustes de la consola" "Console settings")"
info "cmdline: $(sed -E 's/root=[^ ]+ //' /proc/cmdline)"
for b in $BLOCKS; do
    check_"$b" >/dev/null 2>&1; st=$?
    skipvar=SKIP_$b
    case $st in
        0) ok "$(L "$b: aplicado" "$b: applied")" ;;
        2) info "$(L "$b: no aplica en esta consola" "$b: not applicable on this console")" ;;
        *) if [ "${!skipvar:-0}" = 1 ]; then info "$(L "$b: no aplicado (lo decidiste)" "$b: not applied (your choice)")"
           else warn "$(L "$b: pendiente (menú 15, o --setup)" "$b: pending (menu 15, or --setup)")"; fi ;;
    esac
done
if warm_on && ! check_hdmi; then warn "$(L "Reinicio en caliente sin ps5-hdmi-kick: la imagen puede salir en negro (bloque hdmi)" "Warm reboot without ps5-hdmi-kick: the picture may come up black (block hdmi)")"; fi

# --- graphical session ---------------------------------------------------------------------------------
head_ "$(L "Sesión gráfica" "Graphical session")"
if [ "$BOOT" != 0 ]; then info "$(L "(solo se revisa en el arranque actual)" "(only checked on the current boot)")"
elif [ "$(systemctl is-active sddm)" != active ]; then bad "$(L "SDDM no está activo: no hay pantalla de sesión" "SDDM is not active: there is no session screen")"; NEED_SESSION=1
elif compositor_alive; then ok "$(L 'Sesión gráfica viva' 'Graphical session alive') ($(pgrep -u "$U" -x 'gamescope|gamescope-wl' >/dev/null && echo "$(L 'modo juego' 'game mode')" || echo "$(L escritorio desktop)"))"
else bad "$(L "SDDM activo pero sin modo juego ni escritorio: la pantalla estará en negro o en el login" "SDDM active but neither game mode nor desktop: the screen will be black or at the login")"; NEED_SESSION=1; fi
[ -f "$OVERRIDE" ] && info "$(L "Arranca siempre en: $(sed -n 's/^Session=//p' "$OVERRIDE")" "Always starts in: $(sed -n 's/^Session=//p' "$OVERRIDE")")"
session_status 2>&1 | raw "$(L "estado de la sesión" "session status")"

# --- summary -------------------------------------------------------------------------------------------
{ echo; echo "$(L "== Resumen: $OK bien, $WARN avisos, $BAD mal ==" "== Summary: $OK good, $WARN warnings, $BAD bad ==")"; } | tee -a "$LOG"
echo
if save_output "$LOG" "$REPORT" "$(L "el informe completo (sin contraseñas; sirve para pedir ayuda)" "the full report (no passwords; useful for asking for help)")"; then
    echo "$(L 'Para copiarlo a otro ordenador:' 'To copy it to another computer:')  scp $(id -un)@$(hostname -I | awk '{print $1}'):$(printf %q "$SAVED") ."
fi
if [ "$NEED_BT" = 1 ] && [ -t 0 ]; then
    echo
    read -rp "$(L 'El Bluetooth no tiene adaptador. ¿Recargar su driver ahora (btusb)? [S/n] ' 'Bluetooth has no adapter. Reload its driver now (btusb)? [Y/n] ')" a
    if [[ $a != [nN]* ]]; then
        sudo modprobe -r btusb && sleep 2 && sudo modprobe btusb && sleep 5
        if bt_present; then echo "$(L "Adaptador recuperado. Para que se haga solo en cada arranque: menú 16 → bt." "Adapter recovered. To make it happen by itself on every boot: menu 16 → bt.")"
        else echo "$(L "Sigue sin adaptador: apaga y arranca con el cargador (un arranque en frío reinicia el chip)." "Still no adapter: power off and boot with the charger (a cold boot resets the chip).")"; fi
    fi
fi
if [ "$NEED_SESSION" = 1 ] && [ -t 0 ]; then
    echo
    read -rp "$(L 'La sesión gráfica parece caída. ¿Reiniciarla ahora (cierra Steam y lo que esté abierto)? [s/N] ' 'The graphical session looks down. Restart it now (closes Steam and anything open)? [y/N] ')" a
    [[ $a == [sSyY]* ]] && session_restart
fi
}

# --- setup: run the blocks ------------------------------------------------------------------------------------
setup_run() {
if [ -z "$VERSION" ] && [ $STATUS_ONLY = 0 ]; then
    echo "$(L "Aviso: no encuentro /etc/ps5-bazzite-deck-version; estos ajustes son para la imagen ps5-bazzite-deck." "Warning: I cannot find /etc/ps5-bazzite-deck-version; these settings are for the ps5-bazzite-deck image.")" >&2
    read -rp "$(L '¿Continuar de todos modos? [s/N] ' 'Continue anyway? [y/N] ')" a </dev/tty; [[ $a == [sSyY]* ]] || return 1
fi
echo "$(L "Ajustes de la consola ${VERSION:+(v$VERSION)} — respuestas guardadas en $CONF" "Console settings ${VERSION:+(v$VERSION)} — answers saved in $CONF")"
REBOOT=0 COLD=0
DONE="" FAILED="" SKIPPED=""
for b in ${ONLY:-$BLOCKS}; do
    declare -F "check_$b" >/dev/null || { echo "$(L "Bloque desconocido: $b" "Unknown block: $b")" >&2; continue; }
    check_"$b"; st=$?
    skipvar=SKIP_$b
    if [ $st = 1 ] && [ "${!skipvar:-0}" = 1 ] && [ -z "$ONLY" ]; then st=3; fi
    case $st in
        0) printf "$(L '✔ %-10s aplicado\n' '✔ %-10s applied\n')" "$b" ;;
        2) printf "$(L '– %-10s no aplica en esta consola\n' '– %-10s not applicable on this console\n')" "$b" ;;
        3) printf "$(L '– %-10s no aplicado (lo decidiste; menú 16 o --only %s para volver a preguntar)\n' '– %-10s not applied (your choice; menu 16 or --only %s to ask again)\n')" "$b" "$b" ;;
        *) printf "$(L '✘ %-10s pendiente\n' '✘ %-10s pending\n')" "$b" ;;
    esac
    [ $STATUS_ONLY = 1 ] && continue
    if [ $st = 1 ]; then q="$(L "¿Aplicar '$b'?" "Apply '$b'?")" d=$(default_for "$b")
        # you said yes to it before (SKIP_x=0 is only saved on a yes): that answer wins over the block's default,
        # so --all on a new install applies the opt-in blocks you had (gpu40, monitorweb, swapdisco...)
        [ "${!skipvar:-}" = 0 ] && d=S
    elif [ $st = 0 ] && [ -n "$ONLY" ]; then     # asked for by name: allow changing its values
        q="$(L "'$b' ya está aplicado. ¿Volver a aplicarlo (para cambiar sus valores)?" "'$b' is already applied. Apply it again (to change its values)?")" d=N
    else continue; fi
    desc_"$b"
    if ask "$q" "$d"; then
        remember "$skipvar" 0
        if apply_"$b"; then DONE="$DONE $b"; say "$(L "→ hecho" "→ done")"
        else FAILED="$FAILED $b"; say "$(L "→ FALLÓ (revisa los mensajes de arriba)" "→ FAILED (check the messages above)")"
        fi
    elif [ $st = 1 ]; then
        [ $ALL = 1 ] || remember "$skipvar" 1
        [ "$b" = warmreboot ] && remember WARM_REBOOT off
        SKIPPED="$SKIPPED $b"
    fi
    echo
done
[ $STATUS_ONLY = 1 ] && return 0

echo "$(L "Resumen — aplicados:${DONE:- ninguno} | omitidos:${SKIPPED:- ninguno} | fallidos:${FAILED:- ninguno}" "Summary — applied:${DONE:- none} | skipped:${SKIPPED:- none} | failed:${FAILED:- none}")"
[ $COLD = 1 ] && echo "$(L "APAGA (sudo poweroff) y arranca con el cargador: la VRAM y las unidades de la GPU solo cambian en un arranque en frío." "POWER OFF (sudo poweroff) and boot with the charger: VRAM and GPU units only change on a cold boot.")"
[ $COLD = 0 ] && [ $REBOOT = 1 ] && echo "$(L "Reinicia para que cuenten los cambios (parámetros de arranque, zram)." "Reboot for the changes to take effect (boot parameters, zram).")"
if [ -z "$ONLY" ]; then
case $TB_LANG in
es) cat <<'EOF'
A mano (no se puede automatizar desde aquí):
  - passwd, si es una instalación nueva: la contraseña por defecto es ps5 y SSH está abierto en la red.
  - Steam: zona horaria e idioma propios (Ajustes → Sistema), rango RGB "Full" (modo juego y escritorio),
    resolución en Ajustes → Pantalla, salvapantallas/atenuado desactivado.
  - EmuDeck: instalador SteamOS, tipo de dispositivo "Steam Machine", ubicación Internal; después
    el bloque nas y Steam ROM Manager (Parse → Save).
  - DualSense por Bluetooth: emparejar en un perfil propio del mando (PS + Cuadrado).
EOF
;;
*) cat <<'EOF'
By hand (cannot be automated from here):
  - passwd, if it is a fresh install: the default password is ps5 and SSH is open on the network.
  - Steam: its own time zone and language (Settings → System), RGB range "Full" (game mode and desktop),
    resolution in Settings → Display, screensaver/dimming disabled.
  - EmuDeck: SteamOS installer, device type "Steam Machine", location Internal; afterwards
    the nas block and Steam ROM Manager (Parse → Save).
  - DualSense over Bluetooth: pair it in the controller's own profile (PS + Square).
EOF
;;
esac
fi
[ -z "$FAILED" ]
}

# ======================================== live memory monitor ========================================
# Every 2 s: VRAM, GTT (RAM lent to the GPU), RAM and swap (used/total each), temperature, the programs using
# the most VRAM (amdgpu's per-client counters in /proc/PID/fdinfo) and new GPU memory errors in the kernel log.
# RAM used = MemTotal - MemAvailable (what can't be freed: caches don't count). Bazzite's swap is zram, i.e.
# compressed RAM: "swap 2.6/4.3 (en RAM 0.8)" means 2.6 GB swapped out taking 0.8 GB of RAM.
# Ctrl+C stops it and prints the peaks; every sample also goes to a CSV it offers to keep (ps5-mem-FECHA.csv).
P_GPUMEM='ENOMEM|Not enough memory|Failed to pin|ring [a-z_0-9.]+ (timeout|reset)|page fault'
# "__vm_enough_memory: … not enough memory for the allocation" also matches it, but it isn't the GPU: a program asked
# for more address space at once than RAM + swap (overcommit heuristic), e.g. RPCS3 reserving 32 GB, which then
# carries on another way. Counted apart (vm_refused).
P_VMREF='__vm_enough_memory'
vm_refused() {                           # vm_refused SINCE: "count|program|GB" of refused reservations, or nothing
    sudo journalctl -k --since "$1" --no-pager 2>/dev/null | grep -F "$P_VMREF" | awk '
        { for (i = 1; i <= NF; i++) { if ($i == "pid:") pid = $(i + 1); if ($i == "comm:") c = $(i + 1); if ($i == "bytes:") b = $(i + 1) }
          sub(/,$/, "", pid); sub(/,$/, "", c); n++ }
        END { if (n) printf "%d|%s|%s|%.0f\n", n, pid, c, b / 2^30 }'
}
zram_mb() {                              # RAM taken by zram swap (mm_stat field 3: mem_used_total, bytes)
    cat /sys/block/zram*/mm_stat 2>/dev/null | awk '{ s += $3 } END { print int(s / 1048576) }'
}
disk_swap_mb() {                         # swap that isn't zram (bloque swapdisco): "size used" in MiB
    awk 'NR > 1 && $1 !~ /zram/ { s += $3; u += $4 } END { printf "%d %d\n", s / 1024, u / 1024 }' /proc/swaps 2>/dev/null
}
cpu_load() {                             # cpu_load PREV CUR (/proc/stat "cpu" lines) -> "average busiest" in %
    # busy = everything but idle and iowait; the average alone hides a game held back by one full thread
    awk 'NR == FNR { for (i = 2; i <= 9; i++) t[$1] += $i; id[$1] = $5 + $6; next }
         { T = 0; for (i = 2; i <= 9; i++) T += $i; dt = T - t[$1]; p = dt > 0 ? 100 * (dt - ($5 + $6 - id[$1])) / dt : 0
           if ($1 == "cpu") avg = p; else if (p > max) max = p }
         END { printf "%d %d\n", avg, max }' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}
chip_temp_path() {                       # CPU and GPU are one chip: k10temp and amdgpu read the same (as monitor-web.py)
    local h
    for h in /sys/class/hwmon/hwmon*; do [ "$(cat "$h/name" 2>/dev/null)" = k10temp ] && { echo "$h/temp1_input"; return; }; done
    for h in /sys/class/hwmon/hwmon*; do [ "$(cat "$h/name" 2>/dev/null)" = amdgpu ] && { echo "$h/temp1_input"; return; }; done
}
gpu_top_mib() {                          # top N programs by VRAM: "name MiB" lines
    grep -s -E '^drm-(client-id|memory-vram):' /proc/[0-9]*/fdinfo/* 2>/dev/null | awk -v n="${1:-3}" '
        { split($1, f, "/"); pid = f[3] }
        /drm-client-id:/ { cid[$1] = $2 }
        /drm-memory-vram:/ { k = $1; sub(/drm-memory-vram:$/, "drm-client-id:", k); v[k] = $2; p[k] = pid }
        END {
            for (k in v) if ((k in cid) && !seen[cid[k]]++) mib[p[k]] += v[k] / 1024
            for (q in mib) { c = ""; getline c < ("/proc/" q "/comm"); close("/proc/" q "/comm"); tot[c] += mib[q] }
            for (c in tot) printf "%d %s\n", tot[c], c
        }' | sort -rn | head -"${1:-3}" | awk '{ print $2, $1 }'
}
mem_watch() {
    local stop=0 dev csv csv_name start t vu vt gu gt ra rt ru su st zr sdt sd peak_d=0 tc gp cpu0 cpu1 ca cm top top_mib ram ram_mib ev peak_v=0 peak_g=0 min_ra=999999 peak_r=0 peak_s=0 peak_z=0 su0='' peak_t=0 events=0 n=0 ram_top=''
    local peak_ca=0 peak_gp=0 sum_ca=0 sum_gp=0 n_gpu=0 n_cpu=0 tpath
    dev=$(gpu_dev)
    csv=$(mktemp "${TMPDIR:-/tmp}/ps5-mem.XXXXXX") csv_name=ps5-mem-$(date +%Y%m%d-%H%M%S).csv
    start=$(date '+%Y-%m-%d %H:%M:%S')
    tpath=$(chip_temp_path)
    # the same columns as the web monitor's CSV (monitor-web.py), so both sessions compare directly
    echo "hora,cpu_pct,cpu_hilo_max_pct,gpu_pct,vram_usada_mb,gtt_mb,ram_usada_mb,ram_disponible_mb,swap_usada_mb,zram_en_ram_mb,swap_disco_mb,temp_c,errores_gpu,top_vram,top_ram" >"$csv"
    vt=$(( $(cat "$dev/mem_info_vram_total" 2>/dev/null || echo 0) >> 20 ))
    gt=$(( $(cat "$dev/mem_info_gtt_total" 2>/dev/null || echo 0) >> 20 ))
    rt=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
    st=$(awk '/^SwapTotal:/ { print int($2 / 1024) }' /proc/meminfo)
    read -r sdt _ < <(disk_swap_mb)
    echo "$(L 'Memoria en directo: VRAM' 'Live memory: VRAM') $((vt / 1024)) GB$(L ', RAM de Linux ' ', Linux RAM ')$(awk -v r="$rt" 'BEGIN { printf "%.1f", r / 1024 }') GB, swap $(awk -v s="$st" 'BEGIN { printf "%.1f", s / 1024 }') GB$(ls /sys/block/zram* >/dev/null 2>&1 && echo "$(L ' (zram: comprimida en la RAM)' ' (zram: compressed in RAM)')")$([ "${sdt:-0}" -gt 0 ] && awk -v d="$sdt" -v f="$(L ', %.0f GB de ellos en disco (solo con la zram llena)' ', %.0f GB of them on disk (only when zram is full)')" 'BEGIN { printf f, d / 1024 }')."
    echo "$(L "Ctrl+C para parar y ver los picos (al final puedes guardar cada medida en un CSV)." "Ctrl+C to stop and see the peaks (at the end you can save every sample to a CSV).")"
    systemctl --user is-active -q ps5-monitor-web 2>/dev/null && echo "$(L 'También en el móvil:' 'Also on your phone:') http://$(lan_ip):$MONWEB_PORT"
    echo "$(L "CPU: media de los $(nproc) hilos y, entre paréntesis, el hilo más cargado. temp: el chip (CPU y GPU son el mismo)." "CPU: average of the $(nproc) threads and, in parentheses, the busiest thread. temp: the chip (CPU and GPU are the same).")"
    printf '%-8s %-10s %-5s %-15s %-13s %-14s %-24s %-8s %s\n' "$(L hora time)" CPU GPU VRAM GTT RAM "$([ "${sdt:-0}" -gt 0 ] && echo "$(L 'swap (en RAM, disco)' 'swap (in RAM, disk)')" || echo "$(L 'swap (en RAM)' 'swap (in RAM)')")" temp "$(L 'más VRAM' 'top VRAM')"
    cpu0=$(grep '^cpu' /proc/stat)
    trap 'stop=1' INT                    # Ctrl+C: finish this sample, then show the peaks
    while [ $stop = 0 ]; do
        t=$(date +%T)
        vu=$(( $(cat "$dev/mem_info_vram_used" 2>/dev/null || echo 0) >> 20 ))
        gu=$(( $(cat "$dev/mem_info_gtt_used" 2>/dev/null || echo 0) >> 20 ))
        ra=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
        ru=$((rt - ra))
        zr=$(zram_mb)
        read -r _ sd < <(disk_swap_mb)
        su=$(awk '/^SwapTotal:/ { t = $2 } /^SwapFree:/ { f = $2 } END { print int((t - f) / 1024) }' /proc/meminfo)
        tc=''; [ -n "$tpath" ] && tc=$(( $(cat "$tpath" 2>/dev/null || echo 0) / 1000 ))
        gp=$(cat "$dev/gpu_busy_percent" 2>/dev/null || echo 0)
        cpu1=$(grep '^cpu' /proc/stat); read -r ca cm < <(cpu_load "$cpu0" "$cpu1"); cpu0=$cpu1
        top_mib=$(gpu_top_mib 3)
        top=$(awk '{ printf "%s %.1fG  ", $1, $2 / 1024 }' <<<"$top_mib")
        ram_mib=$(ps -eo rss=,comm= --sort=-rss | head -1 | awk '{ printf "%s %d", $2, $1 / 1024 }')
        ram=$(awk '{ printf "%s %.1fG", $1, $2 / 1024 }' <<<"$ram_mib")
        [ -n "$su0" ] || su0=$su
        if [ $((n % 3)) = 0 ]; then     # the kernel log every 6 s is enough
            events=$(sudo journalctl -k --since "$start" --no-pager 2>/dev/null | grep -iE "$P_GPUMEM" | grep -vcF "$P_VMREF")
        fi
        n=$((n + 1))
        [ "$vu" -gt "$peak_v" ] && peak_v=$vu
        [ "$gu" -gt "$peak_g" ] && peak_g=$gu
        [ "$ra" -lt "$min_ra" ] && { min_ra=$ra; ram_top=$ram; }
        [ "$ru" -gt "$peak_r" ] && peak_r=$ru
        [ "$su" -gt "$peak_s" ] && peak_s=$su
        [ "$zr" -gt "$peak_z" ] && peak_z=$zr
        [ "${sd:-0}" -gt "$peak_d" ] && peak_d=${sd:-0}
        [ "${tc:-0}" -gt "$peak_t" ] && peak_t=${tc:-0}
        [ "$ca" -gt "$peak_ca" ] && peak_ca=$ca
        [ "$gp" -gt "$peak_gp" ] && peak_gp=$gp
        sum_ca=$((sum_ca + ca)) sum_gp=$((sum_gp + gp))
        [ "$gp" -ge 95 ] && n_gpu=$((n_gpu + 1))                    # GPU flat out: it sets the frame rate
        [ "$cm" -ge 95 ] && [ "$gp" -lt 85 ] && n_cpu=$((n_cpu + 1))  # one thread full and the GPU waiting
        ev=''; [ "$events" -gt 0 ] && ev="$(L "  ${R}errores GPU: $events${N}" "  ${R}GPU errors: $events${N}")"
        local col=$G rcol=$G; [ "$vt" -gt 0 ] && [ $((vu * 100 / vt)) -ge 90 ] && col=$R
        [ "$ra" -lt 512 ] && rcol=$R                # under 512 MB available: Linux is about to swap hard
        printf '%-8s %-10s %-5s %s%-15s%s %-13s %s%-14s%s %-24s %-8s %s%s\n' "$t" "$ca% ($cm)" "$gp%" "$col" "$(awk -v u="$vu" -v t="$vt" 'BEGIN { printf "%.2f/%.1f GB", u / 1024, t / 1024 }')" "$N" \
            "$(awk -v g="$gu" -v t="$gt" 'BEGIN { printf "%.2f/%.1f GB", g / 1024, t / 1024 }')" \
            "$rcol" "$(awk -v u="$ru" -v t="$rt" 'BEGIN { printf "%.1f/%.1f GB", u / 1024, t / 1024 }')" "$N" \
            "$(awk -v s="$su" -v t="$st" -v z="$zr" -v d="${sd:-0}" -v dt="${sdt:-0}" 'BEGIN { printf "%.1f/%.1f GB (%.1f", s / 1024, t / 1024, z / 1024; if (dt > 0) printf ", %.1f", d / 1024; printf ")" }')" "${tc:-?}°C" "$top" "$ev"
        echo "$t,$ca,$cm,$gp,$vu,$gu,$ru,$ra,$su,$zr,${sd:-0},${tc:-},$events,\"$(awk '{ printf "%s%s %dM", (NR > 1 ? " " : ""), $1, $2 }' <<<"$top_mib")\",\"$(awk '{ printf "%s %dM", $1, $2 }' <<<"$ram_mib")\"" >>"$csv"
        sleep 2 || true
    done
    trap - INT
    echo
    echo "$(L "== Picos ==" "== Peaks ==")"
    echo "$(L '  VRAM usada:   ' '  VRAM used:    ')$(awk -v u="$peak_v" -v t="$vt" -v f="$(L '%.2f de %.1f GB (%d %%)' '%.2f of %.1f GB (%d %%)')" 'BEGIN { printf f, u / 1024, t / 1024, t ? u * 100 / t : 0 }')"
    echo "  GTT:          $(awk -v g="$peak_g" -v t="$gt" -v f="$(L '%.2f de %.1f GB (RAM que la gráfica toma prestada)' '%.2f of %.1f GB (RAM the GPU borrows)')" 'BEGIN { printf f, g / 1024, t / 1024 }')"
    echo "$(L '  RAM usada:    ' '  RAM used:     ')$(awk -v u="$peak_r" -v t="$rt" -v r="$min_ra" -v f="$(L '%.1f de %.1f GB (%d %%; libre como mínimo %.1f GB)' '%.1f of %.1f GB (%d %%; free at minimum %.1f GB)')" 'BEGIN { printf f, u / 1024, t / 1024, t ? u * 100 / t : 0, r / 1024 }') $(L "(entonces gastaba más: $ram_top)" "(biggest user then: $ram_top)")"
    echo "  Swap:         $(awk -v a="${su0:-0}" -v b="$peak_s" -v t="$st" -v z="$peak_z" -v f="$(L '%.1f de %.1f GB como máximo (al empezar %.1f); ocupaba %.1f GB de RAM (zram)' '%.1f of %.1f GB at most (at start %.1f); took %.1f GB of RAM (zram)')" 'BEGIN { printf f, b / 1024, t / 1024, a / 1024, z / 1024 }')$([ "${sdt:-0}" -gt 0 ] && awk -v d="$peak_d" -v t="$sdt" -v f="$(L '; en disco %.1f de %.1f GB' '; on disk %.1f of %.1f GB')" 'BEGIN { printf f, d / 1024, t / 1024 }')"
    echo "$(L "  CPU:          $((sum_ca / (n > 0 ? n : 1))) % de media, ${peak_ca} % como máximo (de los $(nproc) hilos)" "  CPU:          $((sum_ca / (n > 0 ? n : 1))) % on average, ${peak_ca} % at most (of the $(nproc) threads)")"
    echo "$(L "  GPU:          $((sum_gp / (n > 0 ? n : 1))) % de media, ${peak_gp} % como máximo" "  GPU:          $((sum_gp / (n > 0 ? n : 1))) % on average, ${peak_gp} % at most")"
    echo "$(L "  Temperatura:  ${peak_t} °C como máximo (el chip: CPU y GPU son el mismo)" "  Temperature:  ${peak_t} °C at most (the chip: CPU and GPU are the same)")"
    if [ "$events" -gt 0 ]; then
        echo "$(L "  ${R}Errores de memoria de la GPU: $events${N}" "  ${R}GPU memory errors: $events${N}")"
        sudo journalctl -k --since "$start" --no-pager 2>/dev/null | grep -iE "$P_GPUMEM" | grep -vF "$P_VMREF" | tail -5 | sed 's/^/    /'
    else echo "$(L "  Errores de memoria de la GPU: ninguno" "  GPU memory errors: none")"; fi
    local vr vr_n vr_pid vr_c vr_gb vr_exe
    vr=$(vm_refused "$start")
    if [ -n "$vr" ]; then
        IFS='|' read -r vr_n vr_pid vr_c vr_gb <<<"$vr"
        # an AppImage is "AppRun.wrapped" in the log: its real program, if it's still running
        vr_exe=$(basename "$(readlink "/proc/$vr_pid/exe" 2>/dev/null)" 2>/dev/null)
        echo "$(L "  Reservas de memoria rechazadas (no son de la GPU): $vr_n, de $vr_c${vr_exe:+ ($vr_exe)}, de $vr_gb GB de una vez" "  Memory reservations refused (not the GPU's): $vr_n, from $vr_c${vr_exe:+ ($vr_exe)}, of $vr_gb GB at once")"
        echo "$(L "    Pidió de golpe más memoria de la que hay (RAM + swap) y Linux se lo negó. Los emuladores (p. ej. RPCS3)" "    It asked for more memory at once than there is (RAM + swap) and Linux refused. Emulators (e.g. RPCS3)")"
        echo "$(L "    reservan así espacio de direcciones y siguen de otra forma: si el juego no se cerró, no es un fallo." "    reserve address space like this and carry on another way: if the game did not close, it is not a failure.")"
    fi
    local ram_short=0 vram_full=0
    { [ "$min_ra" -lt 512 ] || [ "$peak_s" -gt $(( ${su0:-0} + 512 )) ]; } && ram_short=1
    [ "$vt" -gt 0 ] && [ $((peak_v * 100 / vt)) -ge 90 ] && vram_full=1
    if [ "$st" -gt 0 ] && [ "$peak_s" -ge $((st - 64)) ]; then
        echo "$(L "  → La swap se llenó: si el juego pide más memoria, el sistema lo cierra. Agrándala (menú 16 → zram)" "  → Swap filled up: if the game asks for more memory, the system kills it. Enlarge it (menu 16 → zram)")"
        echo "$(L "    o añade swap en disco (menú 16 → swapdisco)." "    or add disk swap (menu 16 → swapdisco).")"
    fi
    [ "$peak_d" -ge 256 ] && awk -v d="$peak_d" -v f="$(L '  → Usó %.1f GB de swap en disco: el juego siguió, pero más lento en esos momentos. Si el sistema\n    entero se congeló (ratón parado), quítala (menú 16 → swapdisco, tamaño 0).\n' '  → It used %.1f GB of disk swap: the game kept going, but slower at those moments. If the whole\n    system froze (mouse stuck), remove it (menu 16 → swapdisco, size 0).\n')" 'BEGIN { printf f, d / 1024 }'
    if [ $ram_short = 1 ] && [ $vram_full = 1 ]; then
        echo "$(L "  → Van justas las dos (VRAM llena y Linux tirando de swap): moverlas no ayuda, la memoria total no da" "  → Both are tight (VRAM full and Linux using swap): moving them doesn't help, total memory isn't enough")"
        echo "$(L "    para más con esta calidad. Baja texturas o calidad en el juego. Sin errores de la GPU, puede valer así." "    for more at this quality. Lower textures or quality in the game. With no GPU errors, it may be fine as is.")"
    elif [ $ram_short = 1 ]; then
        echo "$(L "  → Se acabó la RAM (no la VRAM): Linux tiró de swap. Baja la VRAM a su pico + 1 GB (menú 16 → vram)" "  → RAM ran out (not VRAM): Linux used swap. Lower VRAM to its peak + 1 GB (menu 16 → vram)")"
        echo "$(L "    para dar esa memoria a Linux, y la calidad de texturas del juego." "    to give that memory to Linux, and lower the game's texture quality.")"
    elif [ $vram_full = 1 ]; then
        echo "$(L "  → La VRAM se llenó y a Linux le sobra RAM: sube la VRAM (menú 16 → vram) o baja la resolución del juego." "  → VRAM filled up and Linux has RAM to spare: raise VRAM (menu 16 → vram) or lower the game's resolution.")"
    fi
    if [ $n -gt 0 ] && [ $((n_gpu * 100 / n)) -ge 50 ]; then
        echo "$(L "  → La GPU va al máximo la mayor parte del tiempo: ella marca los FPS. Para ganar, baja resolución o" "  → The GPU is maxed out most of the time: it sets the FPS. To gain, lower resolution or")"
        echo "$(L "    calidad gráfica (o usa reescalado: TSR, FSR); la CPU no es el límite." "    graphics quality (or use upscaling: TSR, FSR); the CPU is not the limit.")"
    elif [ $n -gt 0 ] && [ $((n_cpu * 100 / n)) -ge 30 ]; then
        echo "$(L "  → Un hilo de la CPU va lleno mientras la GPU espera: el límite es la CPU (un solo hilo). Bajar gráficos" "  → One CPU thread is full while the GPU waits: the CPU is the limit (a single thread). Lowering graphics")"
        echo "$(L "    apenas ayuda; baja lo que carga la CPU (distancia de visión, multitudes, físicas) o limita los FPS." "    barely helps; lower what loads the CPU (view distance, crowds, physics) or cap the FPS.")"
    fi
    echo
    save_output "$csv" "$csv_name" "$(L "cada medida en un CSV (para una hoja de cálculo)" "every sample in a CSV (for a spreadsheet)")"
    return 0
}

# ======================================== image update ========================================
# Same steps as by hand: pick a release, download its update bundle, check its SHA-256, run the author's
# update.sh (it backs up the kernel and modules and prints an undo command), then power off + loader.
# Before that, a full copy of what the update changes (img_snap_take), so img_rollback can put it all back.
# Besides GitHub's releases it lists the ones you keep in your own folders (IMG_LOCAL, e.g. on the NAS): the author
# withdraws releases, and a saved one still installs from there, also without network.
REPO=VivaLaVent/ps5-bazzite-deck
IMG_LOCAL=${IMG_LOCAL:-}                 # folders with downloaded releases, separated by ":" (kept in CONF)
yesno() {                                # yesno "question" S|N -> 0 = yes
    local a d=${2:-N}
    if [ "$TB_LANG" = es ]; then
        if [ "$d" = S ]; then read -rp "$1 [S/n] " a; [[ $a != [nN]* ]]; else read -rp "$1 [s/N] " a; [[ $a == [sS]* ]]; fi
    else
        if [ "$d" = S ]; then read -rp "$1 [Y/n] " a; [[ $a != [nN]* ]]; else read -rp "$1 [y/N] " a; [[ $a == [yYsS]* ]]; fi
    fi
}
# --- this toolbox's own releases ----------------------------------------------------------------------------
# Each release on GitHub carries ps5-bazzite-toolbox.sh and ps5-bazzite-toolbox.sh.sha256 (made by release.sh).
toolbox_release() {                      # toolbox_release TAG|'' DIR [TIMEOUT] -> DIR/{tag,notes,url,sha} of that (or the latest) release
    local api="https://api.github.com/repos/$TOOLBOX_REPO/releases"
    if [ -n "$1" ]; then api="$api/tags/$1"; else api="$api/latest"; fi
    curl -fsSL --max-time "${3:-20}" "$api" -o "$2/rel.json" 2>/dev/null || return 1
    python3 -I - "$2/rel.json" "$2" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); d = sys.argv[2]
a = {x["name"]: x["browser_download_url"] for x in r.get("assets", [])}
for name, value in (("tag", r["tag_name"]), ("notes", r.get("body") or ""),
                    ("url", a.get("ps5-bazzite-toolbox.sh", "")), ("sha", a.get("ps5-bazzite-toolbox.sh.sha256", ""))):
    open(f"{d}/{name}", "w").write(value + "\n")
PY
}
toolbox_newer() {                        # toolbox_newer TAG -> 0 if TAG is newer than this script
    local v=${1#v}
    [ "$v" != "$TOOLBOX_VERSION" ] && printf '%s\n%s\n' "$TOOLBOX_VERSION" "$v" | sort -V -C
}
toolbox_notice() {                       # one line in the menu when a newer release exists (quick, silent offline)
    local tmp tag
    command -v python3 >/dev/null || return 0
    tmp=$(mktemp -d)
    if toolbox_release '' "$tmp" 4 && tag=$(<"$tmp/tag") && toolbox_newer "$tag"; then
        printf "%s$(L '  Hay una versión nueva de esta caja de herramientas: %s (tienes v%s). Opción 18 para actualizarla.' '  A newer version of this toolbox is available: %s (you have v%s). Option 18 to update it.')%s\n" \
            "$Y" "$tag" "$TOOLBOX_VERSION" "$N"
    fi
    rm -rf "$tmp"
}
self_update() {                          # self_update [TAG] -> download, check and replace this script (asks first)
    local want=${1:-} tmp tag url sha target
    command -v python3 >/dev/null || { echo "$(L 'Falta python3.' 'python3 is missing.')" >&2; return 1; }
    [ -z "$want" ] || [[ $want == v* ]] || want=v$want
    tmp=$(mktemp -d)
    echo "$(L "==> Consultando las versiones de $TOOLBOX_REPO en GitHub…" "==> Checking the $TOOLBOX_REPO releases on GitHub…")"
    toolbox_release "$want" "$tmp" ||
        { echo "$(L "No encuentro ${want:-la última versión} (¿hay red? ¿existe esa versión?)." "Cannot find ${want:-the latest version} (is there network? does that version exist?).")" >&2; rm -rf "$tmp"; return 1; }
    tag=$(<"$tmp/tag") url=$(<"$tmp/url") sha=$(<"$tmp/sha")
    printf '\n%s\n' "$(L "Tienes v$TOOLBOX_VERSION. $([ -n "$want" ] && echo Elegida || echo Última): $tag" "You have v$TOOLBOX_VERSION. $([ -n "$want" ] && echo Chosen || echo Latest): $tag")"
    if [ -z "$want" ] && ! toolbox_newer "$tag"; then echo "$(L 'Ya tienes la última versión.' 'You already have the latest version.')"; rm -rf "$tmp"; return 1; fi
    toolbox_newer "$tag" || [ "${tag#v}" = "$TOOLBOX_VERSION" ] || echo "$(L "${Y}Ojo: $tag es más antigua que la tuya.$N" "${Y}Note: $tag is older than yours.$N")"
    [ -n "$url" ] && [ -n "$sha" ] || { echo "$(L 'Esa versión no trae ps5-bazzite-toolbox.sh y su .sha256.' 'That release does not include ps5-bazzite-toolbox.sh and its .sha256.')" >&2; rm -rf "$tmp"; return 1; }
    printf "\n%s$(L 'Novedades de %s:' 'Release notes for %s:')%s\n" "$B" "$tag" "$N"; sed 's/^/  /' "$tmp/notes"
    # Where to write: the installed command if there is one, else this file when it can be replaced, else install it
    target=$TOOLBOX_SELF
    if [ -f "$TOOLBOX_BIN" ] || [ ! -f "$target" ] || [ ! -w "$(dirname "$target")" ]; then target=$TOOLBOX_BIN; fi
    section
    say "$(L "Descarga ps5-bazzite-toolbox.sh de $tag, comprueba su SHA-256 y que bash lo lee bien, y sustituye $target." "Downloads ps5-bazzite-toolbox.sh from $tag, checks its SHA-256 and that bash parses it fine, and replaces $target.")" \
        "$(L "Tus respuestas guardadas ($CONF) se conservan." "Your saved answers ($CONF) are kept.")" \
        "$(L "DESHACER: la copia anterior queda en $target.v$TOOLBOX_VERSION (cp $target.v$TOOLBOX_VERSION $target)." "UNDO: the previous copy stays in $target.v$TOOLBOX_VERSION (cp $target.v$TOOLBOX_VERSION $target).")"
    yesno "$(L "¿Actualizar a $tag?" "Update to $tag?")" S || { rm -rf "$tmp"; return 1; }
    curl -fsSL --retry 3 -o "$tmp/ps5-bazzite-toolbox.sh" "$url" && curl -fsSL --retry 3 -o "$tmp/ps5-bazzite-toolbox.sh.sha256" "$sha" ||
        { echo "$(L 'Falló la descarga.' 'Download failed.')" >&2; rm -rf "$tmp"; return 1; }
    (cd "$tmp" && sha256sum -c ps5-bazzite-toolbox.sh.sha256) || { echo "$(L "${R}El SHA-256 no coincide: no cambio nada.$N" "${R}The SHA-256 does not match: nothing was changed.$N")" >&2; rm -rf "$tmp"; return 1; }
    bash -n "$tmp/ps5-bazzite-toolbox.sh" || { echo "$(L "${R}El fichero descargado no es válido: no cambio nada.$N" "${R}The downloaded file is not valid: nothing was changed.$N")" >&2; rm -rf "$tmp"; return 1; }
    rm -f "$target".v*                   # keep only the copy of the version being replaced
    [ -f "$target" ] && cp -p "$target" "$target.v$TOOLBOX_VERSION"
    mkdir -p "$(dirname "$target")"
    install -m 755 "$tmp/ps5-bazzite-toolbox.sh" "$target" || { echo "$(L "No puedo escribir $target." "Cannot write $target.")" >&2; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    [ "$target" = "$TOOLBOX_BIN" ] && desktop_entry
    echo "$(L "${G}Hecho:$N $target es ahora $tag. Ábrela de nuevo para usarla: $([ "$target" = "$TOOLBOX_BIN" ] && echo ps5-bazzite-toolbox || echo "bash $target")" "${G}Done:$N $target is now $tag. Open it again to use it: $([ "$target" = "$TOOLBOX_BIN" ] && echo ps5-bazzite-toolbox || echo "bash $target")")"
}

# --- installed as a command ------------------------------------------------------------------------------------
# ~/.local/bin is the user's own (no sudo), is in Bazzite's PATH and survives image updates (/home is kept).
desktop_entry() {                        # the applications menu entry (KDE opens it in Konsole)
    mkdir -p "$(dirname "$TOOLBOX_DESKTOP")"
    cat >"$TOOLBOX_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=$(L 'Caja de herramientas PS5' 'PS5 Toolbox')
GenericName=ps5-bazzite-toolbox
Comment=$(L 'Diagnóstico, ajustes y utilidades para Bazzite en la PS5' 'Diagnostics, settings and utilities for Bazzite on the PS5')
Icon=utilities-terminal
Terminal=true
Exec="$TOOLBOX_BIN"
Categories=System;Utility;
EOF
}
atajos_used() { [ -e "$SM_GAME" ] || [ -e "$SM_SPACE" ] || [ -e "$SPACE_BIN" ] ||
                [ -e "$SM_DIR/ps5-toolbox-add-game.desktop" ]; }
install_self() {
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] || {
        echo "$(L 'Ejecutada desde una tubería: descárgala primero (curl -LO …/ps5-bazzite-toolbox.sh) y ejecuta ese fichero.' 'Run from a pipe: download it first (curl -LO …/ps5-bazzite-toolbox.sh) and run that file.')" >&2
        return 1; }
    if [ "$TOOLBOX_SELF" = "$TOOLBOX_BIN" ]; then echo "$(L "Ya está instalada en $TOOLBOX_BIN." "Already installed at $TOOLBOX_BIN.")"; desktop_entry; return 0; fi
    section
    say "$(L "Copia este fichero ($TOOLBOX_SELF, v$TOOLBOX_VERSION) a $TOOLBOX_BIN y añade «Caja de herramientas PS5»" "Copies this file ($TOOLBOX_SELF, v$TOOLBOX_VERSION) to $TOOLBOX_BIN and adds \"PS5 Toolbox\"")"
    say "$(L "al menú de aplicaciones de KDE ($TOOLBOX_DESKTOP)." "to the KDE applications menu ($TOOLBOX_DESKTOP).")"
    [ -f "$TOOLBOX_BIN" ] && say "$(L "Sustituye la que ya hay instalada ($("$TOOLBOX_BIN" --version 2>/dev/null))." "It replaces the one already installed ($("$TOOLBOX_BIN" --version 2>/dev/null)).")"
    say "$(L 'POR QUÉ: abrirla desde cualquier terminal con «ps5-bazzite-toolbox» o desde el menú, sin acordarte de la' 'WHY: open it from any terminal with "ps5-bazzite-toolbox" or from the menu, without having to remember the')"
    say "$(L 'ruta. Las actualizaciones (opción 18) y los atajos del bloque atajos usan siempre esa copia.' 'path. Updates (option 18) and the shortcuts of the atajos block always use that copy.')"
    say "$(L "DESHACER: ps5-bazzite-toolbox --uninstall (o rm $TOOLBOX_BIN $TOOLBOX_DESKTOP)." "UNDO: ps5-bazzite-toolbox --uninstall (or rm $TOOLBOX_BIN $TOOLBOX_DESKTOP).")"
    yesno "$(L '¿Instalarla?' 'Install it?')" S || return 1
    mkdir -p "$(dirname "$TOOLBOX_BIN")" && install -m 755 "$TOOLBOX_SELF" "$TOOLBOX_BIN" || return 1
    desktop_entry
    remember INSTALL_ASKED yes
    echo "$(L "${G}Instalada.$N Ábrela con: ps5-bazzite-toolbox (o desde el menú de aplicaciones)." "${G}Installed.$N Open it with: ps5-bazzite-toolbox (or from the applications menu).")"
    case :$PATH: in *":$HOME/.local/bin:"*) ;; *) echo "$(L "  ($HOME/.local/bin no está en tu PATH: usa $TOOLBOX_BIN)" "  ($HOME/.local/bin is not in your PATH: use $TOOLBOX_BIN)")" ;; esac
    local src=$TOOLBOX_SELF               # the downloaded file (TOOLBOX_SELF changes below, for the shortcuts)
    TOOLBOX_SELF=$TOOLBOX_BIN
    if atajos_used && ! check_atajos; then
        echo "$(L 'Tus atajos (Dolphin, «espacio») usan otra copia de la caja de herramientas.' 'Your shortcuts (Dolphin, "espacio") use another copy of the toolbox.')"
        yesno "$(L "¿Los cambio para que usen la instalada ($TOOLBOX_BIN)?" "Change them to use the installed one ($TOOLBOX_BIN)?")" S && need_sudo && apply_atajos
    fi
    TOOLBOX_SELF=$src
    # The downloaded file is no longer needed; a copy inside a git checkout is someone's working copy: leave it
    if ! git -C "$(dirname "$src")" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        yesno "$(L "¿Borro el fichero descargado ($src)? Ya no hace falta." "Delete the downloaded file ($src)? It is no longer needed.")" S; then
        rm -f "$src" && echo "$(L 'Borrado.' 'Deleted.')"
    fi
}
uninstall_self() {
    [ -f "$TOOLBOX_BIN" ] || [ -f "$TOOLBOX_DESKTOP" ] || { echo "$(L 'No está instalada.' 'It is not installed.')"; return 0; }
    section
    say "$(L "Borra $TOOLBOX_BIN y la entrada del menú ($TOOLBOX_DESKTOP)." "Deletes $TOOLBOX_BIN and the menu entry ($TOOLBOX_DESKTOP).")"
    say "$(L "Tus respuestas guardadas ($CONF) y los ajustes aplicados se quedan como están." "Your saved answers ($CONF) and the settings already applied stay as they are.")"
    say "$(L 'DESHACER: vuelve a descargarla e instálala (ver el README).' 'UNDO: download it again and install it (see the README).')"
    yesno "$(L '¿Desinstalarla?' 'Uninstall it?')" N || return 1
    rm -f "$TOOLBOX_BIN" "$TOOLBOX_DESKTOP" "$TOOLBOX_BIN".v*
    echo "$(L 'Desinstalada.' 'Uninstalled.')"
    grep -qs -F "$TOOLBOX_BIN" "$SM_GAME" "$SPACE_BIN" &&
        echo "$(L "Los atajos (Dolphin, «espacio») la usaban: quítalos con rm '$SM_GAME' '$SM_SPACE'; sudo rm $SPACE_BIN" "The shortcuts (Dolphin, \"espacio\") used it: remove them with rm '$SM_GAME' '$SM_SPACE'; sudo rm $SPACE_BIN")"
    return 0
}
offer_install() {                        # once, from the menu: run from a downloaded file and not installed yet
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] && [ "$TOOLBOX_SELF" != "$TOOLBOX_BIN" ] || return 0
    if [ -f "$TOOLBOX_BIN" ]; then
        printf "%s$(L '  Estás usando %s; la instalada es %s («ps5-bazzite-toolbox»). Opción 19 para sustituirla por esta.' '  You are using %s; the installed one is %s ("ps5-bazzite-toolbox"). Option 19 to replace it with this one.')%s\n" \
            "$Y" "$TOOLBOX_SELF" "$("$TOOLBOX_BIN" --version 2>/dev/null)" "$N"
        return 0
    fi
    [ "${INSTALL_ASKED:-}" = no ] && return 0
    install_self || remember INSTALL_ASKED no
}

update_image() {
    local want=${1:-} tmp n i c tag date kind type url sha title src lfile lsha def='' dir log rc online=1 d
    if [ $IS_BOOTC = 1 ]; then if [ -n "$want" ]; then bootc_menu switch "$want"; else bootc_menu upgrade; fi; return; fi
    command -v python3 >/dev/null || { echo "$(L 'Falta python3.' 'python3 is missing.')" >&2; return 1; }
    tmp=$(mktemp -d)
    echo "$(L "==> Consultando las versiones de $REPO en GitHub…" "==> Checking the $REPO versions on GitHub…")"
    if ! curl -fsSL --retry 3 "https://api.github.com/repos/$REPO/releases?per_page=100" -o "$tmp/rel.json"; then
        online=0; echo '[]' >"$tmp/rel.json"
        echo "$(L 'No puedo conectar con GitHub (¿hay red?): solo las versiones de tus carpetas.' 'Cannot connect to GitHub (is there network?): only the releases in your folders.')" >&2
    fi
    # the bundles in your folders (up to 3 levels down; an unreachable NAS gives up after 30 s)
    : >"$tmp/local"
    local IFS_OLD=$IFS; IFS=:
    for d in $IMG_LOCAL; do
        IFS=$IFS_OLD
        [ -d "$d" ] || { echo "$(L "Aviso: no encuentro la carpeta $d (¿NAS apagado o sin montar?)." "Warning: cannot find the folder $d (NAS off or not mounted?).")" >&2; continue; }
        echo "$(L "==> Buscando versiones descargadas en $d…" "==> Looking for downloaded releases in $d…")"
        timeout 30 find "$d" -maxdepth 3 -type f \( -name 'ps5-bazzite-deck-v*-update.tar.xz' -o -name 'ps5-quick-v*.tar.gz' \) \
            >>"$tmp/local" 2>/dev/null
    done
    IFS=$IFS_OLD
    # tag, date, stable|pre|local, full|quick, bundle URL, checksum URL, title, source (github|local|both), local
    # bundle, local checksum (separated by \x1f, which unlike a tab keeps empty fields when read), newest first.
    # Full = *-update.tar.xz (update.sh, any older version); quick = ps5-quick-*.tar.gz (install.sh, kernel only, on
    # top of a given base version). A local copy wins over the download (same file: its SHA-256 is checked alike).
    python3 -I - "$tmp/rel.json" "$tmp/local" >"$tmp/list" <<'PY'
import datetime, json, os, re, sys
rows = {}
for r in json.load(open(sys.argv[1])):
    a = {x["name"]: x["browser_download_url"] for x in r.get("assets", [])}
    full = [k for k in a if k.endswith("-update.tar.xz")]
    quick = [k for k in a if k.startswith("ps5-quick-") and k.endswith(".tar.gz")]
    if not (full or quick):
        continue
    k, kind = (full[0], "full") if full else (quick[0], "quick")
    title = (r.get("name") or "").replace(r["tag_name"], "", 1).strip(" -–—:")
    rows[r["tag_name"]] = [r["tag_name"], r["published_at"][:10], "pre" if r["prerelease"] else "stable", kind,
                           a[k], a.get(k + ".sha256", ""), title.replace("\x1f", " "), "github", "", ""]
for f in open(sys.argv[2]).read().splitlines():
    m = re.match(r"ps5-bazzite-deck-(v[^/]+)-update\.tar\.xz$|ps5-quick-(v[^/]+)\.tar\.gz$", os.path.basename(f))
    if not m:
        continue
    tag, typ = (m.group(1), "full") if m.group(1) else (m.group(2), "quick")
    sha = f + ".sha256" if os.path.isfile(f + ".sha256") else ""
    r = rows.get(tag)
    if r and r[3] == "full" and typ == "quick" or r and r[8]:
        continue                                   # a full bundle beats a quick one; one local copy is enough
    if r:
        r[3:4] = [typ]; r[7:10] = ["both", f, sha]
    else:
        date = datetime.date.fromtimestamp(os.path.getmtime(f)).isoformat()
        rows[tag] = [tag, date, "local", typ, "", "", "", "local", f, sha]
def key(t):
    return [int(x) for x in re.findall(r"\d+", t)]
for t in sorted(rows, key=key, reverse=True):
    print("\x1f".join(rows[t]))
PY
    [ -s "$tmp/list" ] || { echo "$(L 'No encuentro versiones con paquete de actualización.' 'No releases with an update bundle found.')" >&2; rm -rf "$tmp"; return 1; }
    def=$(awk -F'\037' '$3 == "stable" && $4 == "full" { print $1; exit }' "$tmp/list")
    [ -n "$def" ] || def=$(awk -F'\037' '$4 == "full" { print $1; exit }' "$tmp/list")
    if [ -z "$want" ]; then
        printf "\n$(L 'Instalada' 'Installed'): %s\n" "${VERSION:+v$VERSION}"
        i=0
        while IFS=$'\037' read -r tag date kind type _ _ title src _; do
            i=$((i + 1)); n=''
            [ "$kind" = pre ] && n="$n [$(L 'preliminar' 'prerelease')]"
            [ "$type" = quick ] && n="$n [$(L 'rápida: solo kernel' 'quick: kernel only')]"
            case $src in
                both) n="$n [$(L 'descargada' 'downloaded')]" ;;
                local) n="$n [$(L 'descargada' 'downloaded')$([ $online = 1 ] && L ', ya no está en GitHub' ', no longer on GitHub')]" ;;
            esac
            [ -n "$title" ] && n="$n  $title"
            [ "$tag" = "$def" ] && n="$n ← $(L 'estable más reciente' 'latest stable')"
            [ "$tag" = "v$VERSION" ] && n="$n ($(L 'instalada' 'installed'))"
            printf '  %2d) %-8s %s%s\n' "$i" "$tag" "$date" "$n"
        done <"$tmp/list"
        [ -n "$IMG_LOCAL" ] && echo "$(L "  Carpetas con versiones descargadas: ${IMG_LOCAL//:/, }" "  Folders with downloaded releases: ${IMG_LOCAL//:/, }")"
        read -rp "$(L "¿Qué versión? (número o etiqueta, Intro = $def, l = añadir una carpeta con versiones descargadas, 0 = cancelar):" "Which release? (number or tag, Enter = $def, l = add a folder with downloaded releases, 0 = cancel):") " c
        case $c in
            0) rm -rf "$tmp"; return 0 ;;
            l|L) rm -rf "$tmp"; img_local_add && update_image; return ;;
            '') want=$def ;;
            *[!0-9]*) want=$c ;;
            *) want=$(sed -n "${c}p" "$tmp/list" | cut -d$'\037' -f1) ;;
        esac
    fi
    [[ $want == v* ]] || want=v$want
    IFS=$'\037' read -r tag date kind type url sha title src lfile lsha < <(awk -F'\037' -v t="$want" '$1 == t' "$tmp/list")
    [ -n "${url:-}${lfile:-}" ] || { echo "$(L "No hay paquete de actualización para $want." "There is no update bundle for $want.")" >&2; rm -rf "$tmp"; return 1; }

    echo; echo "$(L "== Novedades de $tag ($date) ==" "== Release notes for $tag ($date) ==")"
    # the release's own notes; for one only in your folder, its NOTAS.md or notes.md if it has one
    python3 -I - "$tmp/rel.json" "$tag" "$(dirname "${lfile:-/x/x}")" <<'PY' | tee "$tmp/notes"
import json, os, sys
L = lambda es, en: es if os.environ.get("TB_LANG", "en") == "es" else en
body = next((r["body"] for r in json.load(open(sys.argv[1])) if r["tag_name"] == sys.argv[2]), None)
if body is None:
    for n in ("NOTAS.md", "notes.md", "RELEASE.md"):
        f = os.path.join(sys.argv[3], n)
        if os.path.isfile(f):
            body = open(f, errors="replace").read(); break
if body is None:
    print(L("(sin notas: ni en GitHub ni junto al paquete)", "(no notes: neither on GitHub nor next to the bundle)"))
else:
    body = body.split("## Updating")[0].split("## VRR test")[0].strip().splitlines()
    print("\n".join(body[:40]) + ("\n…" if len(body) > 40 else ""))
PY
    echo
    [ -n "$lfile" ] && echo "$(L "Se instala desde tu copia: $lfile" "It will be installed from your copy: $lfile")"
    [ "$kind" = pre ] && echo "$(L "Aviso: $tag es PRELIMINAR (de pruebas); la estable más reciente es $def." "Warning: $tag is a PRERELEASE (for testing); the latest stable is $def.")"
    [[ ${title:-} == *PRO* ]] && echo "$(L "Aviso: según su título es SOLO para la PS5 Pro ($title)." "Warning: according to its title it is ONLY for the PS5 Pro ($title).")"
    if [ "$type" = quick ]; then
        echo "$(L 'Aviso: es una actualización RÁPIDA (solo el kernel), que va encima de una versión base:' 'Warning: this is a QUICK update (kernel only), which goes on top of a base release:')"
        python3 -I - "$tmp/rel.json" "$tag" <<'PY'
import json, sys
for r in json.load(open(sys.argv[1])):
    if r["tag_name"] == sys.argv[2] and "## Updating" in r["body"]:
        print("  " + r["body"].split("## Updating", 1)[1].strip().split("\n")[0])
PY
    fi
    if [ "$tag" = "v$VERSION" ]; then echo "$(L "Aviso: $tag ya está instalada; se volvería a instalar." "Warning: $tag is already installed; it would be reinstalled.")"
    elif [ -n "$VERSION" ] && ! printf '%s\n%s\n' "$VERSION" "${tag#v}" | sort -V -C; then
        echo "$(L "Aviso: $tag es ANTERIOR a la instalada (v$VERSION): sería volver atrás." "Warning: $tag is OLDER than the installed one (v$VERSION): this would be going back.")"
    fi
    yesno "$(L "¿Actualizar a $tag?" "Update to $tag?")" N || { rm -rf "$tmp"; return 0; }

    # room: ~150 MB download + ~1 GB unpacked; the boot partition takes a new kernel + initrd (~115 MB)
    if [ "$(df --output=avail -k "$HOME" | tail -1)" -lt 2000000 ]; then
        echo "$(L "Menos de 2 GB libres en $HOME; libera espacio antes." "Less than 2 GB free in $HOME; free some space first.")" >&2; rm -rf "$tmp"; return 1
    fi
    sudo df -h /efi | tail -1 | awk -v p="$(L 'Partición de arranque:' 'Boot partition:')" -v m="$(L 'libres de' 'free of')" '{ print p " " $4 " " m " " $2 }'

    dir=$HOME/ps5-update-$tag; log=$(mktemp "${TMPDIR:-/tmp}/ps5-update.XXXXXX")
    mkdir -p "$dir" || { rm -rf "$tmp"; return 1; }
    local file sumf=''
    if [ -n "$lfile" ]; then
        file="$dir/${lfile##*/}"
        echo "$(L "==> Copiando ${lfile##*/} desde tu carpeta…" "==> Copying ${lfile##*/} from your folder…")"
        cp "$lfile" "$file" || { echo "$(L 'No se ha podido copiar (¿NAS?).' 'Could not copy it (NAS?).')" >&2; rm -rf "$tmp"; return 1; }
        if [ -n "$lsha" ]; then cp "$lsha" "$dir/" && sumf=${lsha##*/}
        elif [ -n "$sha" ]; then curl -fsSL --retry 3 -o "$dir/${sha##*/}" "$sha" && sumf=${sha##*/}; fi
    else
        file="$dir/${url##*/}"
        echo "$(L "==> Descargando ${url##*/}…" "==> Downloading ${url##*/}…")"
        curl -fL -C - --retry 5 -o "$file" "$url" || { echo "$(L 'Falló la descarga (repite: se reanuda).' 'Download failed (run it again: it resumes).')" >&2; rm -rf "$tmp"; return 1; }
        [ -n "$sha" ] && curl -fsSL --retry 3 -o "$dir/${sha##*/}" "$sha" && sumf=${sha##*/}
    fi
    if [ -n "$sumf" ]; then
        (cd "$dir" && sha256sum -c "$sumf") ||
            { echo "$(L "El SHA-256 NO coincide: no se instala. Borra $dir y repite." "The SHA-256 does NOT match: not installing. Delete $dir and try again.")" >&2; rm -rf "$tmp"; return 1; }
    else
        echo "$(L 'Aviso: no hay SHA-256 de esta versión; no se puede comprobar el paquete.' 'Warning: there is no SHA-256 for this release; the bundle cannot be checked.')"
        yesno "$(L '¿Seguir de todos modos?' 'Continue anyway?')" N || { rm -rf "$tmp"; return 1; }
    fi
    # a download goes to your folder too, so it stays installable when the author withdraws it
    if [ -z "$lfile" ] && [ -n "$IMG_LOCAL" ]; then
        local keep=${IMG_LOCAL%%:*}/$tag
        if yesno "$(L "¿Guardar también el paquete en $keep (por si lo retiran de GitHub)?" "Also save the bundle in $keep (in case it is withdrawn from GitHub)?")" S; then
            mkdir -p "$keep" && cp "$file" "$keep/" && { [ -z "$sumf" ] || cp "$dir/$sumf" "$keep/"; } &&
                cp "$tmp/notes" "$keep/NOTAS.md" && echo "$(L "    Guardado en $keep." "    Saved in $keep.")" ||
                echo "$(L "    No se ha podido guardar en $keep (sigue la actualización)." "    Could not save in $keep (the update goes on).")" >&2
        fi
    fi
    rm -rf "$tmp"
    echo "$(L '==> Descomprimiendo…' '==> Unpacking…')"
    case $file in *.tar.gz) tar xzf "$file" -C "$dir" ;; *) tar xJf "$file" -C "$dir" ;; esac || return 1
    local up script=update.sh; [ "$type" = quick ] && script=install.sh
    up=$(find "$dir" -maxdepth 2 -name "$script" | head -1)
    [ -n "$up" ] || { echo "$(L "No encuentro $script en el paquete." "Cannot find $script in the bundle.")" >&2; return 1; }
    # the author's update.sh up to v2.4 only installs a bundle whose kernel has the running kernel's name
    local bk; bk=$(cat "$(dirname "$up")/KERNEL" 2>/dev/null)
    if [ -n "$bk" ] && [ "$bk" != "$(uname -r)" ] && ! grep -q 'OLD=\$(uname -r)' "$up"; then
        echo "$(L "El actualizador de $tag solo se instala sobre su kernel ($bk) y ahora tienes $(uname -r)." "The updater of $tag only installs on top of its own kernel ($bk) and you now have $(uname -r).")" >&2
        if img_snap_list | awk -F'\t' -v k="$bk" '$3 == k { f = 1 } END { exit !f }'; then
            echo "$(L 'Tienes una copia guardada con ese kernel: vuelve antes a ella (opción 17 → volver), apaga, arranca' 'You have a saved copy with that kernel: first go back to it (option 17 → go back), power off, boot')" >&2
            echo "$(L 'con el cargador y repite esto.' 'with the loader and repeat this.')" >&2
        else echo "$(L 'No hay ninguna copia guardada con ese kernel: así no se puede instalar.' 'There is no saved copy with that kernel: it cannot be installed this way.')" >&2; fi
        echo "$(L "Los ficheros descargados siguen en $dir." "The downloaded files are still in $dir.")" >&2
        return 1
    fi
    echo "$(L '==> Copia de la imagen actual (para poder volver a ella con la opción 17)…' '==> Copy of the current image (so you can go back to it with option 17)…')"
    img_snap_take "$(dirname "$up")" ||
        { yesno "$(L 'No se ha podido guardar la copia. ¿Actualizar de todos modos (sin poder volver)?' 'Could not save the copy. Update anyway (without being able to go back)?')" N || return 1; }

    echo "$(L '==> Ejecutando el actualizador del autor…' '==> Running the author'"'"'s updater…')"
    bash "$up" 2>&1 | tee "$log"; rc=${PIPESTATUS[0]}
    if [ "$rc" != 0 ] || { [ "$type" = full ] && ! grep -q '^DONE' "$log"; }; then
        echo; echo "$(L "${R}La actualización NO terminó bien.${N} Los ficheros siguen en $dir." "${R}The update did NOT finish properly.${N} The files are still in $dir.")" >&2
        save_output "$log" "update-$tag.log" "$(L 'la salida de la actualización (para revisarla o pedir ayuda)' 'the update output (to review it or ask for help)')"
        return 1
    fi
    echo; echo "$(L "${G}Actualizado a $tag.${N} Para deshacerlo (con este comando, antes de apagar o tras arrancar):" "${G}Updated to $tag.${N} To undo it (with this command, before powering off or after booting):")"
    grep -i 'undo' "$log" | sed 's/^/  /'
    save_output "$log" "update-$tag.log" "$(L 'la salida de la actualización (incluye ese comando para deshacerla)' 'the update output (includes that command to undo it)')"

    yesno "$(L "¿Borrar la descarga ($(du -sh "$dir" | cut -f1), en $dir)?" "Delete the download ($(du -sh "$dir" | cut -f1), in $dir)?")" S && rm -rf "$dir"
    local olds; olds=$(sudo ls -1d /var/lib/ps5-update-backup/*/ 2>/dev/null | sort | head -n -1)
    if [ -n "$olds" ]; then
        echo "$(L 'Copias de actualizaciones anteriores (la última, la de ahora, se queda):' 'Copies of previous updates (the latest one, the current one, is kept):')"
        for o in $olds; do echo "  $(sudo du -sh "$o" | cut -f1)  $o"; done
        yesno "$(L '¿Borrarlas?' 'Delete them?')" N && sudo rm -rf $olds
    fi

    echo; echo "$(L '== Ajustes tras la actualización ==' '== Settings after the update ==')"
    VERSION=${tag#v}
    STATUS_ONLY=1 ALL=0 ONLY=''; setup_run; STATUS_ONLY=0
    echo
    echo "$(L 'Ahora hay que APAGAR y arrancar con el cargador (no reiniciar: el kernel nuevo necesita un arranque en frío).' 'Now you must POWER OFF and boot with the loader (do not reboot: the new kernel needs a cold start).')"
    yesno "$(L '¿Apagar ahora?' 'Power off now?')" N && sudo poweroff
    return 0
}

img_local_add() {                        # asks for a folder with downloaded releases and adds it to IMG_LOCAL
    local d
    say "$(L 'Una carpeta con versiones descargadas de la imagen: los ficheros tal como vienen en la release' 'A folder with downloaded image releases: the files exactly as they come in the release')" \
        "$(L '(ps5-bazzite-deck-<versión>-update.tar.xz con su .sha256, o ps5-quick-<versión>.tar.gz), en ella o hasta' '(ps5-bazzite-deck-<version>-update.tar.xz with its .sha256, or ps5-quick-<version>.tar.gz), in it or up to')" \
        "$(L '3 niveles por debajo (p. ej. <carpeta>/v1.8.4/…). Puede estar en el NAS (montado con el bloque nas).' '3 levels below (e.g. <folder>/v1.8.4/…). It can be on the NAS (mounted with the nas block).')"
    read -r -e -p "$(L 'Carpeta:' 'Folder:') " d || return 1
    d=${d%/}; d=${d/#\~/$HOME}
    [ -n "$d" ] && [ -d "$d" ] || { echo "$(L "No existe: $d" "Does not exist: $d")" >&2; return 1; }
    case ":$IMG_LOCAL:" in *":$d:"*) echo "$(L 'Ya está en la lista.' 'Already in the list.')"; return 0 ;; esac
    remember IMG_LOCAL "${IMG_LOCAL:+$IMG_LOCAL:}$d"
    echo "$(L "Añadida. Las descargas de GitHub también se ofrecerán guardar en ${IMG_LOCAL%%:*}." "Added. Downloads from GitHub will also be offered to be saved in ${IMG_LOCAL%%:*}.")"
}

# --- going back: full copies of the image taken before each update ---------------------------------------
# The author's backup (/var/lib/ps5-update-backup) holds the boot files and the modules only: its undo leaves the
# new version's scripts, services and version file. A copy here holds everything an update changes, so a restore
# puts the console back exactly as it was before it, whatever the kernel:
#   efi/      the boot partition's top-level files (kernel, initrd, cmdline.txt)
#   modules/  /usr/lib/modules/<kernel>
#   root/     every file the bundle installs (its FILES list), the image's ps5-* scripts and units,
#             /etc/ps5-bazzite-deck (warm reboot, Bluetooth address, perf.conf…) and a few files update.sh edits
#   absent    those paths that didn't exist then (the new version's own files: a restore deletes them)
#   units     whether each ps5-* service/timer was enabled
#   info      version, kernel, date
# Only the image's own parts: Bazzite itself, Steam, games and your files aren't in it (no update touches them).
IMG_SNAPS=/var/lib/ps5-bazzite-toolbox/imagen
IMG_PREV_EFI=anterior-toolbox            # folder on the boot partition with the previous kernel (see img_snap_take)
efi_ready() {                            # mounts the boot partition at /efi if it isn't (an M.2 install)
    sudo test -f "$CMDLINE" && return 0
    sudo mkdir -p /efi && sudo mount LABEL=boot /efi 2>/dev/null && sudo test -f "$CMDLINE" ||
        { echo "$(L 'No encuentro la partición de arranque (etiqueta «boot»): ¿está la memoria USB?' 'Cannot find the boot partition (label "boot"): is the USB drive there?')" >&2; return 1; }
}
img_paths() {                            # img_paths [BUNDLE_DIR]: the system paths a copy keeps, one per line
    { [ -n "${1:-}" ] && [ -f "$1/FILES" ] && awk 'NF >= 2 { print $2 }' "$1/FILES"
      ls -1d /usr/local/sbin/ps5-* /usr/local/bin/ps5-report /usr/local/bin/vrr-report \
             /etc/systemd/system/ps5-* /etc/udev/rules.d/*ps5* /etc/modprobe.d/*ps5* /etc/modules-load.d/ps5-* \
             /etc/NetworkManager/conf.d/99-ps5-* /etc/NetworkManager/dispatcher.d/90-ps5-* 2>/dev/null
      printf '%s\n' /etc/ps5-bazzite-deck /etc/ps5-bazzite-deck-version /etc/bluetooth/main.conf /usr/sbin/kexec \
          /etc/systemd/system/reboot.target /etc/systemd/system/bluetooth.service.d/10-ps5-connectable.conf \
          /usr/local/share/ps5-bazzite-deck
    } | sort -u
}
img_snap_list() {                        # one line per copy, newest first: dir<TAB>version<TAB>kernel<TAB>date
    local d
    for d in $(sudo ls -1d "$IMG_SNAPS"/*/ 2>/dev/null | sort -r); do
        d=${d%/}
        sudo test -f "$d/info" || continue
        printf '%s\t%s\t%s\t%s\n' "$d" "$(sudo awk -F= '$1 == "version" { print $2 }' "$d/info")" \
            "$(sudo awk -F= '$1 == "kernel" { print $2 }' "$d/info")" "$(sudo awk -F= '$1 == "date" { print $2 }' "$d/info")"
    done
}
img_snap_take() {                        # img_snap_take [BUNDLE_DIR [NOTE [PATHS_FROM_COPY]]] -> SNAP=its folder
    local bundle=${1:-} note=${2:-} from=${3:-} k need free f u
    efi_ready || return 1
    k=$(uname -r)
    need=$(( $(sudo du -sk "/usr/lib/modules/$k" | cut -f1) + $(sudo du -sk /efi --max-depth=0 2>/dev/null | cut -f1) + 50000 ))
    free=$(df --output=avail -k /var | tail -1)
    [ "$free" -gt "$need" ] || { echo "$(L "Hacen falta $((need / 1024)) MB libres en /var y hay $((free / 1024))." "$((need / 1024)) MB free are needed in /var and there are $((free / 1024)).")" >&2; return 1; }
    SNAP=$IMG_SNAPS/$(date +%Y%m%d-%H%M%S)-v${VERSION:-desconocida}
    sudo mkdir -p "$SNAP/efi" "$SNAP/root" || return 1
    # boot partition: its top-level files now, plus the bundle's (if new ones, the restore deletes them)
    { sudo find /efi -maxdepth 1 -type f -printf '%f\n'
      [ -n "$bundle" ] && ls -1 "$bundle/efi" 2>/dev/null
      [ -n "$from" ] && sudo cat "$from/efi.list"; } | sort -u | sudo tee "$SNAP/efi.list" >/dev/null
    while read -r f; do
        if sudo test -f "/efi/$f"; then sudo cp -a "/efi/$f" "$SNAP/efi/" || return 1
        else echo "/efi/$f" | sudo tee -a "$SNAP/absent" >/dev/null; fi
    done < <(sudo cat "$SNAP/efi.list")
    sudo cp -a "/usr/lib/modules/$k" "$SNAP/modules" || return 1
    { img_paths "$bundle"; [ -n "$from" ] && sudo cat "$from/paths"; } | sort -u | sudo tee "$SNAP/paths" >/dev/null
    while read -r f; do
        if sudo test -e "$f" || sudo test -L "$f"; then sudo cp -a --parents "$f" "$SNAP/root/" || return 1
        else echo "$f" | sudo tee -a "$SNAP/absent" >/dev/null; fi
    done < <(sudo cat "$SNAP/paths")
    for u in $(sudo cat "$SNAP/paths" | grep -E '^/etc/systemd/system/ps5-[^/]*\.(service|timer)$' | xargs -rn1 basename); do
        printf '%s %s\n' "$u" "$(systemctl is-enabled "$u" 2>/dev/null || echo disabled)"
    done | sudo tee "$SNAP/units" >/dev/null
    printf 'version=%s\nkernel=%s\ndate=%s\nnote=%s\n' "v${VERSION:-?}" "$k" "$(date '+%Y-%m-%d %H:%M')" "$note" |
        sudo tee "$SNAP/info" >/dev/null
    echo "$(L "    Guardada: $SNAP ($(sudo du -sh "$SNAP" | cut -f1)): v${VERSION:-?}, kernel $k." "    Saved: $SNAP ($(sudo du -sh "$SNAP" | cut -f1)): v${VERSION:-?}, kernel $k.")"
    # if even the new kernel doesn't start, nothing on the console can help: the current one also goes to the
    # boot partition (FAT: any computer reads it), with the steps in LEEME.txt
    if [ -n "$bundle" ]; then
        local sz; sz=$(sudo find /efi -maxdepth 1 -type f ! -name '*.txt' -exec du -ck {} + 2>/dev/null | tail -1 | cut -f1)
        if [ "$(df --output=avail -k /efi | tail -1)" -gt $(( ${sz:-0} + 30000 )) ]; then
            sudo rm -rf "/efi/$IMG_PREV_EFI" && sudo mkdir -p "/efi/$IMG_PREV_EFI" &&
                sudo find /efi -maxdepth 1 -type f -exec cp --preserve=timestamps {} "/efi/$IMG_PREV_EFI/" \; &&
                printf '%s\r\n' "$(L "Copia de la imagen v${VERSION:-?} (kernel $k), guardada por ps5-bazzite-toolbox el $(date '+%Y-%m-%d %H:%M')" "Copy of image v${VERSION:-?} (kernel $k), saved by ps5-bazzite-toolbox on $(date '+%Y-%m-%d %H:%M')")" \
                    "$(L 'antes de actualizar. Si la version nueva no arranca:' 'before updating. If the new version does not boot:')" \
                    "$(L '  1. Conecta esta memoria USB a un ordenador.' '  1. Connect this USB drive to a computer.')" \
                    "$(L '  2. Copia los ficheros de esta carpeta a la raiz de la particion (sustituyendo los que hay).' '  2. Copy the files of this folder to the root of the partition (replacing the existing ones).')" \
                    "$(L "  3. Vuelve a ponerla en la PS5 y arranca con el cargador: arrancara el kernel $k." "  3. Put it back in the PS5 and boot with the loader: kernel $k will boot.")" \
                    "$(L '  4. Ya en Linux, ejecuta la caja de herramientas, opcion 17 -> volver, para dejarlo todo como estaba.' '  4. Once in Linux, run the toolbox, option 17 -> go back, to leave everything as it was.')" |
                    sudo tee "/efi/$IMG_PREV_EFI/LEEME.txt" >/dev/null &&
                echo "$(L "    Y el kernel actual, en la partición de arranque: /efi/$IMG_PREV_EFI (por si el nuevo no arranca; ver LEEME.txt)." "    And the current kernel, on the boot partition: /efi/$IMG_PREV_EFI (in case the new one does not boot; see LEEME.txt).")"
        else
            echo "$(L '    (No cabe una copia del kernel en la partición de arranque: si el nuevo no arranca, habrá que reflashear.)' '    (A copy of the kernel does not fit on the boot partition: if the new one does not boot, you will have to reflash.)')"
        fi
    fi
    # keep the newest 3 (each one is the size of the kernel's modules); not while going back (it could be that one)
    local olds=''; [ -z "$bundle" ] || olds=$(img_snap_list | tail -n +4 | cut -f1)
    if [ -n "$olds" ]; then
        echo "$(L '    Copias más antiguas (se guardan las 3 últimas):' '    Older copies (the latest 3 are kept):')"
        for f in $olds; do echo "      $(sudo du -sh "$f" | cut -f1)  $f"; done
        yesno "$(L '    ¿Borrarlas?' '    Delete them?')" S && sudo rm -rf $olds
    fi
    return 0
}
img_rollback() {
    local list n i c d v k dt cur_k f st
    [ $IS_BOOTC = 1 ] && { bootc_menu rollback; return; }
    need_sudo || return 1
    list=$(img_snap_list)
    if [ -z "$list" ]; then
        echo "$(L 'No hay copias guardadas. Se hacen solas al actualizar con la opción 17 (desde la v1.5.0 de esta caja).' 'There are no saved copies. They are made automatically when updating with option 17 (since v1.5.0 of this toolbox).')"
        local bk; bk=$(sudo ls -1d /var/lib/ps5-update-backup/*/ 2>/dev/null | sort | tail -1)
        [ -n "$bk" ] && echo "$(L "Queda la copia del actualizador del autor ($bk): solo kernel y módulos. Su comando para deshacer está en el registro de la actualización (update-<versión>.log), si lo guardaste." "The author's updater copy remains ($bk): kernel and modules only. Its undo command is in the update log (update-<version>.log), if you saved it.")"
        return 0
    fi
    cur_k=$(uname -r)
    printf "$(L '\nAhora: %s, kernel %s\nCopias guardadas (cada una es la imagen tal como estaba antes de una actualización):\n' '\nNow: %s, kernel %s\nSaved copies (each one is the image as it was before an update):\n')" "${VERSION:+v$VERSION}" "$cur_k"
    i=0
    while IFS=$'\t' read -r d v k dt; do
        i=$((i + 1))
        printf "$(L '  %d) %-8s kernel %-14s guardada el %s  (%s)\n' '  %d) %-8s kernel %-14s saved on %s  (%s)\n')" "$i" "$v" "$k" "$dt" "$(sudo du -sh "$d" | cut -f1)"
    done <<<"$list"
    read -rp "$(L '¿A cuál vuelves? (número, Intro = 1, 0 = cancelar):' 'Which one do you go back to? (number, Enter = 1, 0 = cancel):') " c
    case ${c:-1} in 0) return 0 ;; *[!0-9]*) echo "$(L 'Opción no válida' 'Invalid option')"; return 1 ;; esac
    IFS=$'\t' read -r d v k dt < <(sed -n "${c:-1}p" <<<"$list")
    [ -n "${d:-}" ] || { echo "$(L 'Opción no válida' 'Invalid option')"; return 1; }
    echo
    say "$(L "Vuelve a $v (kernel $k), tal como estaba el $dt: kernel, initrd, cmdline.txt, módulos, los scripts y" "Goes back to $v (kernel $k), as it was on $dt: kernel, initrd, cmdline.txt, modules, the image scripts and")" \
        "$(L 'servicios de la imagen y /etc/ps5-bazzite-deck. Lo que la versión actual añadió se borra.' 'services and /etc/ps5-bazzite-deck. Whatever the current version added is deleted.')"
    say "$(L 'Los ajustes de esas partes cambiados después de esa fecha (p. ej. con el bloque gpu40 o fans) vuelven' 'Settings of those parts changed after that date (e.g. with the gpu40 or fans block) go back')" \
        "$(L 'a como estaban; revísalos luego con la opción 14. Bazzite, Steam, juegos y tus ficheros no se tocan.' 'to how they were; check them afterwards with option 14. Bazzite, Steam, games and your files are not touched.')"
    say "$(L 'Antes se guarda una copia de cómo está ahora, así que también esto se puede deshacer (opción 17 → volver).' 'First a copy of how it is now is saved, so this can also be undone (option 17 → go back).')"
    say "$(L 'EN PRUEBAS: la vuelta aún no se ha probado en una consola de verdad. Si algo falla, la copia de antes' 'EXPERIMENTAL: going back has not been tested on a real console yet. If something fails, the previous copy')" \
        "$(L "queda en $IMG_SNAPS y el kernel anterior, si cupo, en /efi/$IMG_PREV_EFI." "stays in $IMG_SNAPS and the previous kernel, if it fitted, in /efi/$IMG_PREV_EFI.")"
    yesno "$(L "¿Volver a $v?" "Go back to $v?")" N || return 0
    efi_ready || return 1
    echo "$(L '==> Copia de la imagen actual…' '==> Copy of the current image…')"
    img_snap_take '' "antes de volver a $v" "$d" || { yesno "$(L 'Sin esa copia no podrás deshacerlo. ¿Seguir?' 'Without that copy you will not be able to undo it. Continue?')" N || return 1; }
    echo "$(L "==> Restaurando $v…" "==> Restoring $v…")"
    sudo cp -r --preserve=timestamps "$d/efi/." /efi/ ||   # FAT: no owners to keep (cp -a would fail)
        { echo "$(L 'Falló al copiar a la partición de arranque: NO apagues; pide ayuda.' 'Copying to the boot partition failed: do NOT power off; ask for help.')" >&2; return 1; }
    sudo rm -rf "/usr/lib/modules/$k.toolbox" && sudo cp -a "$d/modules" "/usr/lib/modules/$k.toolbox" &&
        sudo rm -rf "/usr/lib/modules/$k" && sudo mv "/usr/lib/modules/$k.toolbox" "/usr/lib/modules/$k" || return 1
    sudo depmod -a "$k"
    # the saved paths: directories are put back whole (files added since then go), files one by one
    while read -r f; do
        sudo test -d "$d/root$f" && sudo rm -rf "$f"
        sudo mkdir -p "$(dirname "$f")" && sudo cp -a "$d/root$f" "$(dirname "$f")/" || return 1
    done < <(sudo cat "$d/paths" | while read -r f; do sudo test -e "$d/root$f" -o -L "$d/root$f" && echo "$f"; done)
    sudo cat "$d/absent" 2>/dev/null | while read -r f; do
        case $f in /efi/*|/etc/*|/usr/local/*|/usr/sbin/kexec) sudo rm -rf "$f" ;; esac   # never anything else
    done
    sudo systemctl daemon-reload
    sudo udevadm control --reload 2>/dev/null || true
    while read -r f st; do
        case $st in enabled) sudo systemctl enable "$f" 2>/dev/null ;; disabled) sudo systemctl disable "$f" 2>/dev/null ;; esac
    done < <(sudo cat "$d/units" 2>/dev/null)
    if [ "$k" != "$cur_k" ] && sudo test -d "/usr/lib/modules/$cur_k"; then
        yesno "$(L "¿Borrar los módulos del kernel $cur_k? (ya no arranca; $(sudo du -sh "/usr/lib/modules/$cur_k" | cut -f1))" "Delete the modules of kernel $cur_k? (it no longer boots; $(sudo du -sh "/usr/lib/modules/$cur_k" | cut -f1))")" S &&
            sudo rm -rf "/usr/lib/modules/$cur_k"
    fi
    sync
    VERSION=${v#v}
    sudo test -e /etc/ps5-bazzite-deck/warm-reboot && sudo touch /run/ps5-reboot-to-ps5   # the kernel needs a cold start
    echo; echo "$(L "${G}Vuelto a $v.${N} Para deshacerlo: opción 17 → volver, y elige la copia «antes de volver a $v»." "${G}Went back to $v.${N} To undo it: option 17 → go back, and pick the copy \"antes de volver a $v\" (before going back).")"
    echo "$(L 'Ahora hay que APAGAR y arrancar con el cargador (el kernel cambia: hace falta un arranque en frío).' 'Now you must POWER OFF and boot with the loader (the kernel changes: a cold start is needed).')"
    yesno "$(L '¿Apagar ahora?' 'Power off now?')" N && sudo poweroff
    return 0
}
# --- bootc: the image is updated, rolled back and switched by bootc itself -----------------------------------------
BOOTC_IMG=ghcr.io/vivalavent/ps5-bazzite-bootc
bootc_ref() { sudo bootc status --format=json 2>/dev/null | jq -r '.spec.image.image // .status.booted.image.image.image // empty'; }
bootc_after() {
    echo "$(L '  Al reiniciar, la PS5 pasa primero por su sistema: luego lanza el cargador bazzite-bootc-loader como siempre.' '  On reboot, the PS5 goes through its own system first: then launch the bazzite-bootc-loader loader as usual.')"
    echo "$(L '  Si la nueva no te convence: opción 17 → volver a la anterior (sudo bootc rollback).' '  If you do not like the new one: option 17 → go back to the previous one (sudo bootc rollback).')"
}
bootc_v25_fix() {                        # v2.5, and some installs from the v2.5.1/v2.6.1 images, can't stage updates
    # (v2.6.3 notes): greenboot's rollback trigger is masked but still required. Offer the author's fix.
    [ "$VERSION" = 2.5 ] || [ "$(systemctl is-enabled greenboot-set-rollback-trigger.service 2>/dev/null)" = masked ] ||
        return 0
    grep -qs 'No greenboot rollbacks' /etc/systemd/system/greenboot-set-rollback-trigger.service && return 0
    section
    say "$(L 'Esta instalación tiene un fallo (v2.5, y algunas instaladas con las imágenes v2.5.1, v2.6.1 y v2.6.2): toda' 'This install has a bug (v2.5, and some installed with the v2.5.1, v2.6.1 and v2.6.2 images): every')"
    say "$(L 'actualización termina en «Failed to start ostree-finalize-staged.service».' 'update ends in "Failed to start ostree-finalize-staged.service".')"
    say "$(L 'El arreglo del autor (notas de la v2.6.3) cambia el servicio greenboot-set-rollback-trigger por uno que' 'The authors fix (v2.6.3 notes) replaces the greenboot-set-rollback-trigger service with one that')"
    say "$(L 'no hace nada, una vez; las versiones siguientes lo respetan.' 'does nothing, once; later releases respect it.')"
    say "$(L 'DESHACER: sudo rm /etc/systemd/system/greenboot-set-rollback-trigger.service; sudo systemctl daemon-reload' 'UNDO: sudo rm /etc/systemd/system/greenboot-set-rollback-trigger.service; sudo systemctl daemon-reload')"
    yesno "$(L '¿Lo aplico ahora (hace falta para actualizar)?' 'Apply it now (needed to update)?')" S || return 1
    sudo rm -f /etc/systemd/system/greenboot-set-rollback-trigger.service
    printf '[Unit]\nDescription=No greenboot rollbacks on the PS5\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\nRemainAfterExit=yes\n' |
        sudo tee /etc/systemd/system/greenboot-set-rollback-trigger.service >/dev/null &&
        sudo systemctl daemon-reload && sudo systemctl start ostree-finalize-staged.service && echo "$(L '  Listo para actualizar.' '  Ready to update.')"
}
bootc_menu() {                           # bootc_menu [upgrade|rollback|switch [TAG]]
    local c=${1:-} tag=${2:-} ref tags
    need_sudo || return 1
    ref=$(bootc_ref)
    echo
    echo "$(L "${B}Imagen bootc${N} ${Y}[EN PRUEBAS]${N}: el sistema entero es una imagen; bootc la actualiza y guarda la anterior." "${B}bootc image${N} ${Y}[EXPERIMENTAL]${N}: the whole system is an image; bootc updates it and keeps the previous one.")"
    echo "$(L '  Esta parte de la caja aún no se ha probado en una consola bootc: si algo falla, sudo bootc status y cuéntalo.' '  This part of the toolbox has not been tested on a bootc console yet: if something fails, run sudo bootc status and report it.')"
    echo "$(L "  Sigue: ${ref:-?}  (stable = las versiones estables, cada semana; vX.Y = esa versión fija)" "  Following: ${ref:-?}  (stable = the stable releases, every week; vX.Y = that fixed release)")"
    sudo bootc status 2>/dev/null | grep -E '^(●|  )?(Booted|Staged|Rollback)|image:|Version' | sed 's/^/  /' | head -12
    if [ -z "$c" ]; then
        echo "$(L '  1) Actualizar: descarga la siguiente del canal que sigues (sudo bootc upgrade); entra al reiniciar' '  1) Update: downloads the next one of the channel you follow (sudo bootc upgrade); takes effect on reboot')"
        echo "$(L '  2) Volver a la versión anterior (sudo bootc rollback); entra al reiniciar' '  2) Go back to the previous release (sudo bootc rollback); takes effect on reboot')"
        echo "$(L "  3) Cambiar de canal o fijar una versión (sudo bootc switch $BOOTC_IMG:<etiqueta>)" "  3) Change channel or pin a release (sudo bootc switch $BOOTC_IMG:<tag>)")"
        read -rp "$(L 'Elige (0 = cancelar):' 'Choose (0 = cancel):') " c
        case $c in 1) c=upgrade ;; 2) c=rollback ;; 3) c=switch ;; *) return 0 ;; esac
    fi
    case $c in
        upgrade) bootc_v25_fix || return 1
                 sudo bootc upgrade && bootc_after ;;
        rollback) section
                  say "$(L 'Al reiniciar arranca la versión que había antes de la última actualización o cambio; la de' 'On reboot, the release that was there before the last update or change boots; the current one')"
                  say "$(L 'ahora se queda como «anterior», así que esto también se deshace igual. Tus ficheros no cambian.' 'stays as "previous", so this can be undone the same way. Your files do not change.')"
                  yesno "$(L '¿Vuelvo a la anterior?' 'Go back to the previous one?')" S && sudo bootc rollback && bootc_after ;;
        switch) if [ -z "$tag" ]; then
                    tags=$(curl -fsSL --retry 2 "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null |
                        jq -r --arg p "$(L 'preliminar' 'prerelease')" '.[] | .tag_name + (if .prerelease then " (" + $p + ")" else "" end)' 2>/dev/null |
                        awk '{ v = $1; sub(/^v/, "", v); split(v, a, "."); if (a[1] > 2 || (a[1] == 2 && a[2] >= 5)) print "  " $0 }')
                    echo "$(L '  Etiquetas: stable (recomendada) o una versión de bootc:' '  Tags: stable (recommended) or a bootc release:')"; echo "${tags:-$(L '  (sin red: no puedo listarlas)' '  (no network: cannot list them)')}"
                    read -rp "$(L '  ¿Cuál? (Intro = stable):' '  Which one? (Enter = stable):') " tag; tag=${tag:-stable}
                fi
                bootc_v25_fix || return 1
                section
                say "$(L "Cambia la imagen que sigue esta consola a $BOOTC_IMG:$tag y la descarga; entra al reiniciar." "Changes the image this console follows to $BOOTC_IMG:$tag and downloads it; takes effect on reboot.")"
                say "$(L 'Con una versión fija (vX.Y) ya no recibe las semanales: vuelve con «stable».' 'With a pinned release (vX.Y) it no longer gets the weekly ones: go back with "stable".')"
                say "$(L 'DESHACER: opción 17 → volver a la anterior, o cambiar otra vez.' 'UNDO: option 17 → go back to the previous one, or switch again.')"
                yesno "$(L "¿Cambio a $tag?" "Switch to $tag?")" S && sudo bootc switch "$BOOTC_IMG:$tag" && bootc_after ;;
    esac
}

img_menu() {
    [ $IS_BOOTC = 1 ] && { bootc_menu; return; }
    local c n; n=$(img_snap_list | wc -l)
    echo "$(L '  1) Instalar una versión de GitHub (la más nueva u otra, también anterior)' '  1) Install a release from GitHub (the newest or another one, also an older one)')"
    echo "$(L "  2) Volver a como estaba la imagen antes de una actualización ($n copia(s) guardada(s)) [EN PRUEBAS]" "  2) Go back to how the image was before an update ($n saved copy(ies)) [EXPERIMENTAL]")"
    echo "$(L '  3) Guardar ahora una copia de la imagen tal como está (la opción 1 ya la hace sola antes de instalar)' '  3) Save a copy of the image as it is now (option 1 already does it by itself before installing)')"
    read -rp "$(L 'Elige (Intro = 1, 0 = cancelar):' 'Choose (Enter = 1, 0 = cancel):') " c
    case ${c:-1} in
        1) update_image ;;
        2) img_rollback ;;
        3) need_sudo && img_snap_take '' "guardada a mano" ;;
        *) return 0 ;;
    esac
}

# ======================================== PortProton, Steam and tools ========================================
# The two PortProton helpers are whole scripts kept here as text and run with bash, so the toolbox stays one file.
pp_add_game_script() { cat <<'__PP_ADD_GAME__'
#!/usr/bin/env bash
# Run by ps5-bazzite-toolbox.sh (menu "Añadir un juego de Windows", --add-game, or Dolphin's right-click action).
# Adds a Windows game to PortProton and Steam, asking before each step (--yes takes every default):
#   1. Test:      opens the .exe with PortProton (flatpak ru.linux_gaming.PortProton). You try it and close it;
#                 PortProton leaves its settings next to the exe (<exe>.ppdb) and the game icon in data/img/.
#   2. Shortcuts: the same .desktop PortProton makes, in its folder (its game list) and on the Desktop.
#   3. Steam:     the same steam_scripts/<Name>.sh PortProton makes, added to Steam as a non-Steam game
#                 (shortcuts.vdf; Steam must be closed or it overwrites the file when it quits).
#   4. Collection: the toolbox's "PortProton" collection sync (COLLECTION_SCRIPT).
# Isolation (asked first): normal, or isolated with/without network (the toolbox's --run, TOOLBOX_CMD). An isolated
# game has its own prefix in the toolbox's copy of PortProton (ISO_SB), no entry in PortProton's own list (it would
# start it unisolated) and its Steam script calls TOOLBOX_CMD --run. Every game it installs is kept in ISO_LIST
# ("level<TAB>exe<TAB>name<TAB>folder it sees"). --change: only the level of an installed game (moves its prefix, tries it, rewrites
# its shortcuts and Steam script; the Steam entry itself stays, with its playtime and artwork).
# Nothing is overwritten without asking; shortcuts.vdf is backed up first. Undo: delete the .desktop files and
# the .sh, and in Steam remove the game (or restore shortcuts.vdf.bak-<date>).
set -euo pipefail
if [ -z "${TB_LANG:-}" ]; then case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in es*) TB_LANG=es ;; *) TB_LANG=en ;; esac; fi
L() { if [ "$TB_LANG" = es ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
export TB_LANG

PP_ID=ru.linux_gaming.PortProton
PP="${PORT_WINE_PATH:-$HOME/.var/app/$PP_ID}"
STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
COLLECTION_SCRIPT="${COLLECTION_SCRIPT:-$HOME/portproton-collection.sh}"
TOOLBOX_CMD=${TOOLBOX_CMD:-} ISO_LIST=${ISO_LIST:-} ISO_SB=${ISO_SB:-}
EXE= NAME= TEST=1 YES=0 CHANGE=0

say() { printf '%s\n' "$*"; }
ask() {                                   # ask "question" [default S|N] -> 0 for yes
    local def=${2:-S} ans yn
    [ $YES = 1 ] && { [ "$def" = S ]; return; }
    if [ "$TB_LANG" = es ]; then yn=$([ "$def" = S ] && echo S/n || echo s/N); else yn=$([ "$def" = S ] && echo Y/n || echo y/N); fi
    read -r -p "$1 [$yn] " ans
    ans=${ans:-$def}
    [[ $ans =~ ^[sSyY] ]]
}
section() { printf '\n== %s\n' "$*"; }

while [ $# -gt 0 ]; do
    case $1 in
        --name) NAME=$2; shift 2 ;;
        --no-test) TEST=0; shift ;;
        --change) CHANGE=1; shift ;;
        -y|--yes) YES=1; shift ;;
        -*) say "$(L "Opción desconocida: $1" "Unknown option: $1")" >&2; exit 2 ;;
        *) EXE=$1; shift ;;
    esac
done
[ -n "$EXE" ] || { say "$(L "Falta la ruta del .exe del juego." "Missing path to the game's .exe.")" >&2; exit 2; }
[ -f "$EXE" ] || { say "$(L "No existe: $EXE" "Does not exist: $EXE")" >&2; exit 1; }
EXE=$(realpath "$EXE")
flatpak info "$PP_ID" >/dev/null 2>&1 || { say "$(L "PortProton (flatpak $PP_ID) no está instalado." "PortProton (flatpak $PP_ID) is not installed.")" >&2; exit 1; }
[ -d "$PP/data/scripts" ] || { say "$(L "No encuentro PortProton en $PP (ábrelo una vez)." "Cannot find PortProton in $PP (open it once).")" >&2; exit 1; }

# --- name -------------------------------------------------------------------------------------------
# An existing PortProton shortcut for this exe keeps its name; otherwise the game's folder, skipping
# engine folders (Binaries/Win64...) and a "(2025)" year: ".../Tempest Rising (2025)/Tempest Rising/Tempest.exe"
existing=$(grep -l -F "\"$EXE\"" "$PP"/*.desktop 2>/dev/null | grep -v '/PortProton.desktop$' | head -1 || true)
[ -n "$NAME" ] || NAME=$(awk -F'\t' -v e="$EXE" '$2 == e && $3 != "" { n = $3 } END { print n }' "$ISO_LIST" 2>/dev/null || true)
[ -n "$NAME" ] || NAME=$({ grep -l -F "\"$EXE\"" "$PP"/steam_scripts/*.sh 2>/dev/null | head -1 | xargs -r -d '\n' basename -s .sh; } || true)
[ $CHANGE = 0 ] || [ -n "$NAME$existing" ] || { say "$(L "Este juego no está instalado: instálalo primero." "This game is not installed: install it first.")" >&2; exit 1; }
if [ -z "$NAME" ] && [ -n "$existing" ]; then
    NAME=$(sed -n 's/^Name=//p' "$existing" | head -1)
fi
if [ -z "$NAME" ]; then
    d=$(dirname "$EXE")
    while [[ $(basename "$d") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do d=$(dirname "$d"); done
    NAME=$(basename "$d" | sed -E 's/ *\([0-9]{4}\)$//')
fi
section "$(L "Juego" "Game")"
say "$(L "Ejecutable: $EXE" "Executable: $EXE")"
if [ $YES = 0 ] && [ $CHANGE = 0 ]; then
    # editable proposal in a terminal; Enter (or no terminal) keeps it
    if [ -t 0 ]; then read -r -e -i "$NAME" -p "$(L "Nombre (Steam, escritorio y PortProton): " "Name (Steam, desktop and PortProton): ")" ans
    else read -r -p "$(L "Nombre [$NAME]: " "Name [$NAME]: ")" ans || true; fi
    NAME=${ans:-$NAME}
fi
NAME=$(printf '%s' "$NAME" | tr -d '`"'"'"'!/')
[ -n "$NAME" ] || { say "$(L "Nombre vacío." "Empty name.")" >&2; exit 1; }
[ -n "$existing" ] && say "$(L "PortProton ya tiene un acceso para este exe: $(basename "$existing")" "PortProton already has a shortcut for this exe: $(basename "$existing")")"

# --- isolation --------------------------------------------------------------------------------------
PPDB="$EXE.ppdb"
SH="$PP/steam_scripts/$NAME.sh"
iso_cur() { awk -F'\t' -v e="$EXE" '$2 == e { l = $1 } END { print (l ? l : "normal") }' "$ISO_LIST" 2>/dev/null || echo normal; }
new_pfx() { printf '%s' "$NAME" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-' | tr '[:lower:]' '[:upper:]' | cut -c1-40; }   # PortProton upper-cases them
pfx_of() { sed -n 's/^export PW_PREFIX_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$PPDB" 2>/dev/null | tail -1 || true; }
CUR=normal LEVEL=normal UNDO=()
if [ -n "$TOOLBOX_CMD" ] && [ -n "$ISO_LIST" ] && [ -n "$ISO_SB" ]; then
    CUR=$(iso_cur)
    section "$(L "Cómo se ejecuta" "How it runs")"
    case $TB_LANG in
        es)
    say "1) Normal: con acceso a todo (tu carpeta personal, el NAS, tus otros juegos). Para juegos de tiendas fiables."
    say "2) Aislado con red: sin tu carpeta personal, el NAS ni tus otros juegos; tu PortProton en solo lectura,"
    say "   con un prefijo propio. Con red (juegos online, launchers)."
    say "3) Aislado sin red: lo mismo, sin red. Lo más seguro para un juego de origen dudoso."
    say "Los aislados no van en la lista de juegos de PortProton (desde ahí se abrirían sin aislar): escritorio y Steam." ;;
        *)
    say "1) Normal: with access to everything (your home folder, the NAS, your other games). For games from trusted stores."
    say "2) Isolated with network: without your home folder, the NAS or your other games; your PortProton read-only,"
    say "   with its own prefix. With network (online games, launchers)."
    say "3) Isolated without network: the same, no network. Safest for a game of dubious origin."
    say "Isolated games do not go in PortProton's game list (from there they would open unisolated): desktop and Steam." ;;
    esac
    case $CUR in red) def=2 ;; sin-red) def=3 ;; *) def=1 ;; esac      # a game keeps its level; a new one: normal
    [ "$CUR" != normal ] || [ -z "$existing" ] || say "$(L "Ahora mismo es normal." "Right now it is normal.")"
    [ "$CUR" = normal ] || say "$(L "Ahora mismo: aislado " "Right now: isolated ")$([ "$CUR" = red ] && L 'con red' 'with network' || L 'sin red' 'without network')."
    c=$def
    [ $YES = 1 ] || { read -r -p "$(L "¿Cuál? [1-3, Intro = $def] " "Which one? [1-3, Enter = $def] ")" c || true; c=${c:-$def}; }
    case $c in 1) LEVEL=normal ;; 3) LEVEL=sin-red ;; *) LEVEL=red ;; esac
    [ $CHANGE = 0 ] || [ "$LEVEL" != "$CUR" ] || { say "$(L "Sigue igual: no cambio nada." "Unchanged: nothing to change.")"; exit 0; }
fi
GTOP=$(dirname "$EXE")
while [[ $(basename "$GTOP") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do GTOP=$(dirname "$GTOP"); done
[ -d "$GTOP/../Engine" ] && GTOP=$(dirname "$GTOP")
# the folder kept for it earlier wins over the guess
ROOT_SAVED=$(awk -F'\t' -v e="$EXE" '$2 == e && $4 != "" { r = $4 } END { print r }' "$ISO_LIST" 2>/dev/null || true)
[ -z "$ROOT_SAVED" ] || GTOP=$ROOT_SAVED
if [ "$LEVEL" != normal ]; then
    say "$(L "Carpeta del juego que podrá ver (y escribir) aislado: $GTOP" "Game folder it will be able to see (and write) when isolated: $GTOP")"
    say "$(L "  Si sus datos están más arriba (p. ej. el .exe va en una subcarpeta como sp26/ o bin/), pon la de arriba." "  If its data is higher up (e.g. the .exe sits in a subfolder like sp26/ or bin/), give the upper one.")"
    if [ $YES = 0 ] && [ -t 0 ]; then read -r -e -i "$GTOP" -p "$(L "Carpeta del juego: " "Game folder: ")" ans || true
    elif [ $YES = 0 ]; then read -r -p "$(L "Carpeta del juego [$GTOP]: " "Game folder [$GTOP]: ")" ans || true; fi
    GTOP=$(realpath -m "${ans:-$GTOP}"); ans=
    case $EXE in "$GTOP"/*) ;; *) say "$(L "El .exe no está dentro de $GTOP." "The .exe is not inside $GTOP.")" >&2; exit 1 ;; esac
    case $HOME/ in "$GTOP"/*) say "$(L "El juego está directamente en $GTOP: muévelo a su propia carpeta (p. ej. ~/Juegos/Juego/) para aislarlo." "The game is directly in $GTOP: move it to its own folder (e.g. ~/Games/Game/) to isolate it.")" >&2; exit 1 ;; esac
    case $GTOP/ in "$PP"/*|/var/mnt/*|/mnt/*|/run/media/*)
        say "$(L "Para aislarlo, la carpeta del juego ($GTOP) tiene que ser una carpeta local propia (p. ej. ~/Juegos/Juego/)," "To isolate it, the game folder ($GTOP) must be its own local folder (e.g. ~/Games/Game/),")" >&2
        say "$(L "no PortProton, el NAS ni un disco externo: queda escribible para él. Cópialo allí y añádelo desde la copia." "not PortProton, the NAS or an external disk: it becomes writable for it. Copy it there and add it from the copy.")" >&2; exit 1 ;;
    esac
fi
# The prefix follows the level: normal ones live in PortProton, isolated ones in ISO_SB (moved, asking).
PFX=$(pfx_of)
if [ "$LEVEL" != "$CUR" ] && { [ "$LEVEL" = normal ] || [ "$CUR" = normal ]; }; then
    [ -f "$PPDB" ] && cp -p "$PPDB" "$PPDB.bak-iso" && UNDO+=("mv -f '$PPDB.bak-iso' '$PPDB'")
    mkdir -p "$ISO_SB/data/prefixes"
    if [ "$LEVEL" != normal ]; then
        if [ -n "$PFX" ] && [ "$PFX" != DEFAULT ] && [ "$PFX" != DOTNET ] && [ -d "$PP/data/prefixes/$PFX" ] &&
            ask "$(L "Su prefijo $PFX (con sus partidas) está en tu PortProton. ¿Lo paso a la copia aislada? (si otro juego lo usa, dejará de encontrarlo)" "Its prefix $PFX (with its saves) is in your PortProton. Move it to the isolated copy? (if another game uses it, it will no longer find it)")" S; then
            mv "$PP/data/prefixes/$PFX" "$ISO_SB/data/prefixes/" && UNDO+=("mv '$ISO_SB/data/prefixes/$PFX' '$PP/data/prefixes/'")
        else
            [ -n "$PFX" ] && say "$(L "Estaba en el prefijo $PFX, que se queda en tu PortProton con sus partidas (cópialas a mano si las quieres)." "It was in prefix $PFX, which stays in your PortProton with its saves (copy them by hand if you want them).")"
            PFX=$(new_pfx)
            say "$(L "Prefijo aislado nuevo: $PFX." "New isolated prefix: $PFX.")"
        fi
    elif [ -n "$PFX" ] && [ -d "$ISO_SB/data/prefixes/$PFX" ]; then
        if [ -d "$PP/data/prefixes/$PFX" ]; then
            say "$(L "Tu PortProton ya tiene un prefijo $PFX: el aislado se queda en $ISO_SB/data/prefixes/$PFX." "Your PortProton already has a prefix $PFX: the isolated one stays in $ISO_SB/data/prefixes/$PFX.")"
        elif ask "$(L "Su prefijo aislado $PFX (con sus partidas) ¿pasa a tu PortProton? Lo que el juego haya dejado en él dejará de estar aislado" "Does its isolated prefix $PFX (with its saves) move to your PortProton? Whatever the game left in it will no longer be isolated")" S; then
            mv "$ISO_SB/data/prefixes/$PFX" "$PP/data/prefixes/" && UNDO+=("mv '$PP/data/prefixes/$PFX' '$ISO_SB/data/prefixes/'")
        fi
    fi
fi
PPDB_NEW=1; [ ! -f "$PPDB" ] || PPDB_NEW=0       # a new game's .ppdb goes too if it is not added after all
if [ "$LEVEL" != normal ]; then
    [ -n "$PFX" ] || PFX=$(new_pfx)
    if grep -qs '^export PW_PREFIX_NAME=' "$PPDB"; then sed -i "s|^export PW_PREFIX_NAME=.*|export PW_PREFIX_NAME=\"$PFX\"|" "$PPDB"
    else printf 'export PW_PREFIX_NAME="%s"\n' "$PFX" >>"$PPDB"; fi
fi
desk_entry() {                            # desk_entry FILE -> PortProton's own shortcut, or the isolated one
    if [ "$LEVEL" = normal ]; then
        printf '[Desktop Entry]\nName=%s\nExec=flatpak run %s "%s"\nType=Application\nCategories=Game\nStartupNotify=true\nPath=%s\nIcon=%s\n' \
            "$NAME" "$PP_ID" "$EXE" "$PP/data/scripts/" "$ICON" >"$1"
    else
        printf '[Desktop Entry]\nName=%s\nComment=%s\nExec=bash "%s" --run "%s"\nType=Application\nCategories=Game\nIcon=%s\n' \
            "$NAME" "$(L 'Aislado (ps5-bazzite-toolbox)' 'Isolated (ps5-bazzite-toolbox)')" "$TOOLBOX_CMD" "$EXE" "$ICON" >"$1"
    fi
    chmod +x "$1"
}
write_sh() {                               # what Steam runs: PortProton's own way, or the toolbox's isolated --run
    mkdir -p "$PP/steam_scripts"
    if [ "$LEVEL" = normal ]; then
        cat > "$SH" <<EOF
#!/usr/bin/env bash
export LD_PRELOAD=
export START_FROM_STEAM=1
export START_FROM_FLATPAK=1
"$PP/data/scripts/start.sh" "$EXE" "\$@"
EOF
    else
        cat > "$SH" <<EOF
#!/usr/bin/env bash
# $(L "Aislado ($LEVEL) por ps5-bazzite-toolbox: lo lanza en el Flatpak de PortProton con menos permisos." "Isolated ($LEVEL) by ps5-bazzite-toolbox: runs it in PortProton's Flatpak with fewer permissions.")
exec bash "$TOOLBOX_CMD" --run "$EXE"
EOF
    fi
    chmod u+x "$SH"
}
undo_level() {                            # stopped after changing the level: put the prefix and .ppdb back
    local i
    for ((i = ${#UNDO[@]} - 1; i >= 0; i--)); do eval "${UNDO[$i]}"; done
    [ ${#UNDO[@]} = 0 ] || say "$(L "Deshecho el cambio de aislamiento (prefijo y .ppdb como estaban)." "Isolation change undone (prefix and .ppdb as they were).")"
}

# --- 1. test ----------------------------------------------------------------------------------------
new_prefix() { [ "$LEVEL" != normal ] && [ ! -d "$ISO_SB/data/prefixes/$PFX" ]; }   # this test would make it
NEW_PFX=0; new_prefix && NEW_PFX=1
section "$(L "1. Probar el juego con PortProton" "1. Test the game with PortProton")"
say "$(L "Se abre PortProton con este exe: elige la versión de Proton si hace falta, pulsa Iniciar, prueba el juego" "PortProton opens with this exe: pick the Proton version if needed, press Start, try the game")"
say "$(L "y ciérralo (el juego y la ventana de PortProton). PortProton guarda sus ajustes en $(basename "$PPDB")." "and close it (the game and the PortProton window). PortProton saves its settings in $(basename "$PPDB").")"
[ "$LEVEL" = normal ] || say "$(L "Se abre aislado (" "It opens isolated (")$([ "$LEVEL" = red ] && L 'con red' 'with network' || L 'sin red' 'without network')$(L "), con el prefijo $PFX: elígelo si te pregunta." "), with prefix $PFX: pick it if it asks.")"
if [ "$LEVEL" != normal ]; then
    say "$(L "Antes, si no te fías del juego, busca su huella en VirusTotal (sin subir nada):" "First, if you do not trust the game, look up its hash on VirusTotal (without uploading anything):")"
    say "  https://www.virustotal.com/gui/file/$(sha256sum "$EXE" | cut -d' ' -f1)"
    say "$(L "Aislado no es una máquina virtual: comparte pantalla, sonido y mandos. Cierra Steam y el navegador antes de" "Isolated is not a virtual machine: it shares screen, sound and controllers. Close Steam and the browser before")"
    say "$(L "probarlo (un programa de X11 puede leer lo que se teclea en otras ventanas X11), y no le des tu contraseña." "testing it (an X11 program can read what is typed in other X11 windows), and do not give it your password.")"
fi
if [ $TEST = 1 ] && ask "$(L "¿Abrirlo ahora?" "Open it now?")" "$([ -f "$PPDB" ] && [ "$LEVEL" = "$CUR" ] && echo N || echo S)"; then
  while :; do
    PPLS=$(ls -A "$PP")
    if [ "$LEVEL" = normal ]; then flatpak run "$PP_ID" "$EXE" >/dev/null 2>&1 || true
    else bash "$TOOLBOX_CMD" --run "$EXE" --gui --level "$LEVEL" --root "$GTOP" || true; fi
    if [ "$LEVEL" != normal ]; then            # only the top of PortProton's folder stays writable in the sandbox
        NEWF=$(comm -13 <(sort <<<"$PPLS") <(ls -A "$PP" | sort) || true)
        if [ -n "$NEWF" ]; then
            say "$(L "Ojo: han aparecido ficheros nuevos en tu PortProton ($PP):" "Careful: new files have appeared in your PortProton ($PP):")"; printf '  %s\n' "$NEWF"
            if ask "$(L "¿Los borro? (un .desktop nuevo ahí saldría en la lista de PortProton, sin aislar)" "Delete them? (a new .desktop there would show up in PortProton's list, unisolated)")" S; then
                while IFS= read -r f; do rm -rf "${PP:?}/$f"; done <<<"$NEWF"
            fi
        fi
    fi
    # PortProton closes after preparing a new prefix (recommended libraries...): "r" opens it again
    ans=s
    [ $YES = 1 ] || { read -r -p "$(L "¿Ha arrancado bien? (s = sí, sigue · r = vuelve a abrirlo · n = no, para) [S/r/n] " "Did it start fine? (y = yes, continue · r = open it again · n = no, stop) [Y/r/n] ")" ans || ans=; }
    case ${ans:-s} in [rR]*) continue ;; [nN]*) ;; *) break ;; esac              # n: stop and undo
    undo_level
    # isolated prefixes this attempt used: the proposed one and whatever PortProton's window left in the .ppdb (it
    # can switch prefix, e.g. when the Wine version is changed). Offered when the game was not installed before
    # (or the prefix is new) and no installed game's .ppdb uses it.
    if [ "$LEVEL" != normal ]; then
        for p in $(printf '%s\n' "$PFX" "$(pfx_of)" | sort -u); do
            [ -n "$p" ] && [ "$p" != DEFAULT ] && [ "$p" != DOTNET ] && [ -d "$ISO_SB/data/prefixes/$p" ] || continue
            [ $NEW_PFX = 1 ] || { [ "$CUR" = normal ] && [ -z "$existing" ] && [ ! -f "$SH" ]; } || continue
            users=$(cut -f2 "$ISO_LIST" 2>/dev/null | grep -vxF -- "$EXE" | while IFS= read -r e; do
                grep -qsx "export PW_PREFIX_NAME=\"$p\"" "$e.ppdb" && echo x; done || true)
            [ -z "$users" ] || continue
            if ask "$(L "¿Borro el prefijo aislado $p ($(du -sh "$ISO_SB/data/prefixes/$p" 2>/dev/null | cut -f1)), que ha usado esta prueba?" "Delete the isolated prefix $p ($(du -sh "$ISO_SB/data/prefixes/$p" 2>/dev/null | cut -f1)) this test used?")" S; then
                rm -rf "${ISO_SB:?}/data/prefixes/$p"
            fi
        done
    fi
    if [ "$CUR" = normal ] && [ -z "$existing" ] && [ ! -f "$SH" ] && ask "$(L "¿No te convence? ¿Borro la carpeta del juego ($GTOP, $(du -sh "$GTOP" 2>/dev/null | cut -f1))?" "Not convinced? Delete the game folder ($GTOP, $(du -sh "$GTOP" 2>/dev/null | cut -f1))?")" N; then
        read -r -p "$(L "  Se borra $GTOP entera. Para confirmar, escribe BORRAR: " "  $GTOP will be deleted entirely. To confirm, type DELETE: ")" c || c=
        if [[ ${c^^} == BORRAR || ${c^^} == DELETE ]]; then rm -rf -- "$GTOP" && say "$(L "  Borrada." "  Deleted.")"; else say "$(L "  No has escrito BORRAR: no borro nada." "  You did not type DELETE: nothing deleted.")"; fi
    fi
    [ $PPDB_NEW = 0 ] || rm -f "$PPDB"
    say "$(L "Parado. " "Stopped. ")$([ $CHANGE = 1 ] && L "No se ha cambiado nada." "Nothing has been changed." || L "No se ha añadido nada." "Nothing has been added.")"; exit 0
  done
fi
[ -z "$ISO_LIST" ] || {                    # keep the game and its level ("Mis juegos" lists them)
    tmp=$(mktemp); awk -F'\t' -v e="$EXE" '$2 != e' "$ISO_LIST" 2>/dev/null >"$tmp" || true
    printf '%s\t%s\t%s\t%s\n' "$LEVEL" "$EXE" "$NAME" "$([ "$LEVEL" = normal ] || echo "$GTOP")" >>"$tmp"
    mkdir -p "$(dirname "$ISO_LIST")"; mv "$tmp" "$ISO_LIST"; rm -f "$PPDB.bak-iso"
}
[ -f "$PPDB" ] || { say "$(L "No hay $PPDB: abre el juego una vez con PortProton antes (sin --no-test)." "There is no $PPDB: open the game once with PortProton first (without --no-test).")" >&2; exit 1; }
# shellcheck disable=SC1090
PORTPROTON_NAME=$(. "$PPDB" >/dev/null 2>&1; echo "${PORTPROTON_NAME:-}")
PW_WINE_USE=$(. "$PPDB" >/dev/null 2>&1; echo "${PW_WINE_USE:-}")
say "$(L "Ajustes de PortProton: Proton ${PW_WINE_USE:-por defecto}, nombre interno ${PORTPROTON_NAME:-?}" "PortProton settings: Proton ${PW_WINE_USE:-default}, internal name ${PORTPROTON_NAME:-?}")"

# icon: PortProton names it after PORTPROTON_NAME, spaces -> _, without ! % $ & <
png=${PORTPROTON_NAME:-$(basename "${EXE%.*}")}; png=${png// /_}; png=$(printf '%s' "$png" | tr -d '!%$&<')
ICON="$PP/data/img/$png.png"
# an isolated run leaves the icon in the copy, which the next sync clears: keep it next to the others
[ -f "$ICON" ] || [ ! -f "$ISO_SB/data/img/$png.png" ] || cp "$ISO_SB/data/img/$png.png" "$ICON"
[ -f "$ICON" ] || { say "$(L "(sin icono propio en data/img: se usa el de PortProton)" "(no own icon in data/img: PortProton's is used)")"; ICON=$PP_ID; }

# --- --change: only the shortcuts and the Steam script follow the new level ----------------------------
if [ $CHANGE = 1 ]; then
    section "$(L "Accesos y Steam" "Shortcuts and Steam")"
    DESK_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    if [ "$LEVEL" != normal ]; then
        [ -z "$existing" ] || { rm -f "$existing"; say "$(L "Quitado de la lista de juegos de PortProton (desde ahí se abriría sin aislar)." "Removed from PortProton's game list (from there it would open unisolated).")"; }
    else
        desk_entry "$PP/$NAME.desktop"; say "$(L "En la lista de juegos de PortProton: $PP/$NAME.desktop" "In PortProton's game list: $PP/$NAME.desktop")"
    fi
    for f in "$DESK_DIR/$NAME.desktop" "$HOME/.local/share/applications/$NAME.desktop"; do
        [ -f "$f" ] && desk_entry "$f" && say "$(L "Acceso actualizado: $f" "Shortcut updated: $f")"
    done
    if [ -f "$SH" ]; then
        write_sh; say "$(L "Steam: es el mismo juego (tiempo jugado, carátulas y colección siguen); ahora se lanza " "Steam: it is the same game (playtime, artwork and collection stay); it now launches ")$([ "$LEVEL" = normal ] && L normal normal || L aislado isolated)."
    else
        say "$(L "No está en Steam (no hay $SH)." "It is not in Steam (there is no $SH).")"
    fi
    section "$(L "Listo" "Done")"
    say "$(L "«$NAME» queda " "«$NAME» is now ")$(case $LEVEL in normal) L normal normal ;; red) L "aislado con red" "isolated with network" ;; *) L "aislado sin red" "isolated without network" ;; esac)."
    exit 0
fi

# --- language ---------------------------------------------------------------------------------------
# Many Steam builds take their language from Steam, i.e. from the Steam emulator's config next to the game,
# often left in English (seen with Gears of War: E-Day, RUNE's steam_emu.ini "Language=english": no Spanish
# option in the game until it said "spanish"). Steam's names for the system language:
steam_lang() {
    case ${LANG:-} in
        es_ES*|es_AD*) echo spanish ;; es_*) echo latam ;; pt_BR*) echo brazilian ;; pt_*) echo portuguese ;;
        fr_*) echo french ;; de_*) echo german ;; it_*) echo italian ;; ru_*) echo russian ;; pl_*) echo polish ;;
        ja_*) echo japanese ;; ko_*) echo koreana ;; zh_TW*|zh_HK*) echo tchinese ;; zh_*) echo schinese ;;
        nl_*) echo dutch ;; tr_*) echo turkish ;; uk_*) echo ukrainian ;; *) echo english ;;
    esac
}
GROOT=$(dirname "$EXE")                     # the game's folder: up through engine folders (Binaries/Win64...)
while [[ $(basename "$GROOT") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do GROOT=$(dirname "$GROOT"); done
[ -d "$GROOT/../Engine" ] && GROOT=$(dirname "$GROOT")          # Unreal: Game/Binaries/Win64 next to Engine/
WANT=$(steam_lang)
# "file|how to read and set it": key=value lines (case-insensitive key), or a whole-file value
mapfile -t LFILES < <(find "$GROOT" -maxdepth 7 \( -iname steam_emu.ini -o -iname SteamConfig.ini -o -iname cream_api.ini \
    -o -ipath '*steam_settings/force_language.txt' -o -ipath '*steam_settings/configs.user.ini' \) -type f 2>/dev/null | head -10)
LPACK=$(find "$GROOT" -maxdepth 2 -type d -iname '*language*' 2>/dev/null | head -1)
if [ ${#LFILES[@]} -gt 0 ] || [ -n "$LPACK" ]; then
    section "$(L "Idioma" "Language")"
    for f in "${LFILES[@]}"; do
        rel=${f#"$GROOT"/}
        if [[ $f == *force_language.txt ]]; then cur=$(tr -d '\r\n ' < "$f")
        else cur=$(grep -a -i -m1 -E '^[[:space:]]*language[[:space:]]*=' "$f" | sed 's/^[^=]*=[[:space:]]*//' | tr -d '\r '); fi
        if [ -z "$cur" ]; then say "$(L "$rel: no fija idioma." "$rel: sets no language.")"; continue; fi
        if [ "$cur" = "$WANT" ]; then say "$(L "$rel: idioma $cur (bien)." "$rel: language $cur (fine).")"; continue; fi
        say "$(L "$rel: el emulador de Steam le dice al juego que el idioma es «$cur»; el del sistema es «$WANT»." "$rel: the Steam emulator tells the game the language is «$cur»; the system's is «$WANT».")"
        say "$(L "  Muchos juegos solo muestran ese idioma (no tienen selector propio). Copia en $(basename "$f").bak-<fecha>." "  Many games only show that language (no selector of their own). Backup in $(basename "$f").bak-<date>.")"
        if ask "$(L "  ¿Cambiarlo a «$WANT»?" "  Change it to «$WANT»?")" S; then
            cp -p "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
            if [[ $f == *force_language.txt ]]; then printf '%s\n' "$WANT" > "$f"
            else sed -i -E "0,/^[[:space:]]*[Ll][Aa][Nn][Gg][Uu][Aa][Gg][Ee][[:space:]]*=/s/^([[:space:]]*[Ll][Aa][Nn][Gg][Uu][Aa][Gg][Ee][[:space:]]*=[[:space:]]*)[^\r]*/\1$WANT/" "$f"; fi
            say "$(L "  Hecho: " "  Done: ")$(grep -a -i -m1 -E '^[[:space:]]*language[[:space:]]*=|^[a-z]+$' "$f" | tr -d '\r')"
        fi
    done
    if [ -n "$LPACK" ]; then
        say "$(L "El juego trae paquetes de idioma en «${LPACK#"$GROOT"/}»: " "The game ships language packs in «${LPACK#"$GROOT"/}»: ")$(ls "$LPACK" | tr '\n' ',' | sed 's/,$//; s/,/, /g')."
        # the pack for the system language: its folder name, as these packs name them ("Spanish - Spain"...)
        case $WANT in
            spanish) pat='^(spanish( - spain)?|español|espanol|es[-_]es)$' ;; latam) pat='latin|^es[-_](mx|419)$' ;;
            brazilian) pat='brazil|^pt[-_]br$' ;; schinese) pat='simplified' ;; tchinese) pat='traditional' ;;
            koreana) pat='^korean' ;; *) pat="^$WANT" ;;
        esac
        mine=$(ls "$LPACK" | grep -i -E -m1 "$pat" || true)
        if [ -z "$mine" ]; then
            say "$(L "  No veo el de «$WANT»: si está con otro nombre, copia su contenido encima de la carpeta del juego." "  I do not see the one for «$WANT»: if it has another name, copy its contents over the game folder.")"
        elif (cd "$LPACK/$mine" && find . -type f | while read -r f; do cmp -s "$f" "$GROOT/$f" || { echo x; break; }; done) | grep -q x; then
            say "$(L "  El de tu idioma es «$mine» y no está copiado en el juego (su contenido va encima de la carpeta del juego)." "  The one for your language is «$mine» and it is not copied into the game (its contents go over the game folder).")"
            if ask "$(L "  ¿Copiarlo ahora ($(du -sh "$LPACK/$mine" | cut -f1))?" "  Copy it now ($(du -sh "$LPACK/$mine" | cut -f1))?")" S; then
                cp -r "$LPACK/$mine/." "$GROOT/" && say "$(L "  Copiado." "  Copied.")"
            fi
        else
            say "$(L "  El de tu idioma («$mine») ya está copiado." "  The one for your language («$mine») is already copied.")"
        fi
    fi
fi

# --- 2. shortcuts -----------------------------------------------------------------------------------
DESKTOP_FILE="$PP/$NAME.desktop"
DESK_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
section "$(L "2. Accesos directos" "2. Shortcuts")"
if [ "$LEVEL" != normal ]; then
    say "$(L "Aislado: va solo en el escritorio ($DESK_DIR/$NAME.desktop), que lo abre aislado. Deshacer: borra ese fichero." "Isolated: goes only on the desktop ($DESK_DIR/$NAME.desktop), which opens it isolated. Undo: delete that file.")"
    if [ -n "$existing" ] && ask "$(L "  Está en la lista de juegos de PortProton, que lo abriría SIN aislar. ¿Lo quito de ahí?" "  It is in PortProton's game list, which would open it UNISOLATED. Remove it from there?")" S; then
        rm -f "$existing"; say "$(L "  Quitado: " "  Removed: ")$(basename "$existing")"
    fi
    if ask "$(L "¿Crear el acceso del escritorio?" "Create the desktop shortcut?")" S; then
        mkdir -p "$DESK_DIR"
        desk_entry "$DESK_DIR/$NAME.desktop"
        say "  $DESK_DIR/$NAME.desktop"
    fi
elif say "$(L "Crea «$NAME.desktop» en la carpeta de PortProton (su lista de juegos) y en el escritorio ($DESK_DIR)," "Creates «$NAME.desktop» in PortProton's folder (its game list) and on the desktop ($DESK_DIR),")"
    say "$(L "igual que los que hace PortProton. Deshacer: borra los dos ficheros." "like the ones PortProton makes. Undo: delete the two files.")"
    ask "$(L "¿Crearlos?" "Create them?")" S; then
    desk_entry "$DESKTOP_FILE"
    if [ -n "$existing" ] && [ "$existing" != "$DESKTOP_FILE" ]; then
        say "$(L "  (el acceso anterior, $(basename "$existing"), se queda; bórralo si sobra)" "  (the previous shortcut, $(basename "$existing"), stays; delete it if it is not needed)")"
    fi
    if ask "$(L "  ¿También en el escritorio?" "  Also on the desktop?")" S; then
        mkdir -p "$DESK_DIR" && cp -f "$DESKTOP_FILE" "$DESK_DIR/" && chmod +x "$DESK_DIR/$NAME.desktop"
        say "  $DESK_DIR/$NAME.desktop"
    fi
    say "  $DESKTOP_FILE"
fi

# --- 3. Steam ---------------------------------------------------------------------------------------
section "3. Steam"
if [ -f "$SH" ] && [ "$LEVEL" != "$CUR" ]; then
    write_sh; say "$(L "Ya estaba en Steam: $SH lo lanza ahora " "It was already in Steam: $SH now launches it ")$([ "$LEVEL" = normal ] && L normal normal || L aislado isolated)$(L ". Steam no cambia." ". Steam does not change.")"
fi
say "$(L "Crea $SH (lo que lanza Steam" "Creates $SH (what Steam runs")$([ "$LEVEL" = normal ] && L ", igual que el de PortProton" ", same as PortProton's" || L ": la caja de herramientas, aislado" ": the toolbox, isolated")$(L ") y lo añade a Steam como juego no-Steam" ") and adds it to Steam as a non-Steam game")"
say "$(L "«$NAME». Steam tiene que estar cerrado: al cerrarse reescribe su lista y borraría el juego nuevo." "«$NAME». Steam must be closed: when it quits it rewrites its list and would delete the new game.")"
say "$(L "Deshacer: quitar el juego en Steam (o restaurar shortcuts.vdf.bak-<fecha>) y borrar el .sh." "Undo: remove the game in Steam (or restore shortcuts.vdf.bak-<date>) and delete the .sh.")"
[ "$LEVEL" = normal ] || [ "$TOOLBOX_CMD" = "$HOME/.local/bin/ps5-bazzite-toolbox" ] ||
    say "$(L "Ojo: Steam llamará a $TOOLBOX_CMD; si lo mueves o lo borras, el juego no arranca (instálala: opción 19)." "Careful: Steam will call $TOOLBOX_CMD; if you move or delete it, the game will not start (install it: option 19).")"
if ask "$(L "¿Añadirlo a Steam?" "Add it to Steam?")" S; then
    write_sh
    if pgrep -x steam >/dev/null 2>&1; then
        if ask "$(L "  Steam está abierto. ¿Cerrarlo ahora?" "  Steam is open. Close it now?")" S; then
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
        fi
        pgrep -x steam >/dev/null 2>&1 && { say "$(L "  Steam sigue abierto: ciérralo y repite (el .sh ya está creado)." "  Steam is still open: close it and repeat (the .sh is already created).")" >&2; exit 1; }
    fi
    STEAM_DIR="$STEAM_DIR" GAME_NAME="$NAME" GAME_SH="$SH" GAME_ICON="$ICON" GAME_DIR="$(dirname "$EXE")" \
        python3 - <<'PY'
# shortcuts.vdf is binary VDF: parsed into (type, key, value) lists and written back exactly as read
# (checked byte for byte before touching it), plus one new entry.
import glob, os, shutil, struct, sys, time, zlib

L = lambda es, en: es if os.environ.get("TB_LANG", "en") == "es" else en

def parse(d, i):
    items = []
    while True:
        t = d[i]; i += 1
        if t == 0x08:
            return items, i
        e = d.index(b"\0", i); k = d[i:e]; i = e + 1
        if t == 0x00:
            v, i = parse(d, i)
        elif t == 0x01:
            e = d.index(b"\0", i); v = d[i:e]; i = e + 1
        elif t == 0x02:
            v = d[i:i + 4]; i += 4
        elif t == 0x07:
            v = d[i:i + 8]; i += 8
        else:
            raise ValueError(L(f"tipo VDF 0x{t:02x} desconocido en {i - 1}", f"unknown VDF type 0x{t:02x} at {i - 1}"))
        items.append((t, k, v))

def dump(items):
    out = bytearray()
    for t, k, v in items:
        out += bytes([t]) + k + b"\0"
        out += dump(v) if t == 0 else (v + b"\0" if t == 1 else v)
    return bytes(out + b"\x08")

def field(entry, key):
    for t, k, v in entry:
        if k.lower() == key.lower():
            return v
    return None

name, sh, icon, gdir = (os.environ[k] for k in ("GAME_NAME", "GAME_SH", "GAME_ICON", "GAME_DIR"))
users = [u for u in glob.glob(os.path.join(os.environ["STEAM_DIR"], "userdata", "*"))
         if os.path.basename(u).isdigit() and os.path.basename(u) != "0"]
if not users:
    sys.exit(L("  No encuentro usuarios de Steam en userdata/", "  Cannot find Steam users in userdata/"))
exe_q = f'"{sh}"'
# Steam's own id for a non-Steam game: crc32(exe + name) with the top bit set (artwork in grid/ uses it)
appid = (zlib.crc32((exe_q + name).encode()) | 0x80000000) & 0xFFFFFFFF
for u in users:
    path = os.path.join(u, "config", "shortcuts.vdf")
    if os.path.exists(path):
        data = open(path, "rb").read()
        root, _ = parse(data, 0)
        if dump(root) != data:
            sys.exit(L(f"  {path}: no lo leo de forma exacta; no lo toco.", f"  {path}: cannot read it exactly; leaving it alone."))
    else:
        root = [(0, b"shortcuts", [])]
    sc = field(root, b"shortcuts")
    if any((field(e, b"exe") or b"").decode("utf-8", "replace").strip('"') == sh for t, k, e in sc if t == 0):
        print(L(f"  Usuario {os.path.basename(u)}: ya estaba en Steam.", f"  User {os.path.basename(u)}: already in Steam."))
        continue
    n = max([int(k) for t, k, e in sc if k.isdigit()], default=-1) + 1
    s = lambda v: v.encode()
    i32 = lambda v: struct.pack("<I", v)
    entry = [(2, b"appid", i32(appid)), (1, b"AppName", s(name)), (1, b"Exe", s(exe_q)),
             (1, b"StartDir", s(os.path.dirname(sh) + "/")), (1, b"icon", s(icon if icon.startswith("/") else "")),
             (1, b"ShortcutPath", b""), (1, b"LaunchOptions", b""), (2, b"IsHidden", i32(0)),
             (2, b"AllowDesktopConfig", i32(1)), (2, b"AllowOverlay", i32(1)), (2, b"OpenVR", i32(0)),
             (2, b"Devkit", i32(0)), (1, b"DevkitGameID", b""), (2, b"DevkitOverrideAppID", i32(0)),
             (2, b"LastPlayTime", i32(0)), (1, b"FlatpakAppID", b""), (0, b"tags", [])]
    sc.append((0, str(n).encode(), entry))
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    open(tmp, "wb").write(dump(root))
    os.replace(tmp, path)
    print(L(f"  Usuario {os.path.basename(u)}: añadido «{name}» (id {appid}).", f"  User {os.path.basename(u)}: added «{name}» (id {appid})."))
PY
fi

# --- 4. collection ----------------------------------------------------------------------------------
section "$(L "4. Colección «PortProton» de Steam" "4. Steam «PortProton» collection")"
if [ -x "$COLLECTION_SCRIPT" ] || [ -f "$COLLECTION_SCRIPT" ]; then
    say "$(L "Mete el juego en la colección «PortProton» de Steam (lo mismo que esa opción del toolbox)." "Puts the game in Steam's «PortProton» collection (same as that toolbox option).")"
    if ask "$(L "¿Actualizar la colección?" "Update the collection?")" S; then
        bash "$COLLECTION_SCRIPT" --yes || say "$(L "  La colección no se actualizó (mira el mensaje de arriba)." "  The collection was not updated (see the message above).")"
    fi
else
    say "$(L "No encuentro el sincronizador de la colección: se salta." "Cannot find the collection syncer: skipping.")"
fi

section "$(L "Listo" "Done")"
say "$(L "Terminado con «$NAME». Si lo has añadido a Steam, ábrelo (o el Modo Juego) para verlo." "Finished with «$NAME». If you added it to Steam, open it (or Game Mode) to see it.")"
if ! pgrep -x steam >/dev/null 2>&1 && ask "$(L "¿Abrir Steam ahora?" "Open Steam now?")" N; then
    setsid steam >/dev/null 2>&1 < /dev/null &
fi
__PP_ADD_GAME__
}
pp_collection_script() { cat <<'__PP_COLLECTION__'
#!/usr/bin/env bash
# Run by ps5-bazzite-toolbox.sh (menu "Colección PortProton", --pp-collection). Was ~/portproton-collection.sh.
# Sincroniza una colección de Steam ("PortProton") con todos los accesos
# directos no-Steam cuyo ejecutable termina en ".sh".
#
#  - Añade los que falten y quita los que ya no existan (la colección
#    queda siempre igual a la lista actual de .sh).
#  - Hace backup de los ficheros que toca.
#  - Steam debe estar CERRADO mientras se ejecuta (si no, sobreescribe
#    los cambios). Úsalo desde el Modo Escritorio.
#
# Opciones: --dry-run (solo muestra qué haría), --yes (cierra Steam sin preguntar);
# COLLECTION_NAME="Otro" para otro nombre de colección.

set -euo pipefail
if [ -z "${TB_LANG:-}" ]; then case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in es*) TB_LANG=es ;; *) TB_LANG=en ;; esac; fi
L() { if [ "$TB_LANG" = es ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
export TB_LANG

STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
COLLECTION_NAME="${COLLECTION_NAME:-PortProton}"
DRY_RUN=0 YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) YES=1 ;;
    *) echo "$(L "Opción desconocida: $arg" "Unknown option: $arg")" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$STEAM_DIR/userdata" ]]; then
  echo "$(L "No encuentro $STEAM_DIR/userdata" "Cannot find $STEAM_DIR/userdata")" >&2
  exit 1
fi

if [[ $DRY_RUN -eq 0 ]] && pgrep -x steam >/dev/null 2>&1; then
  echo "$(L "Steam está abierto. Hay que cerrarlo para que no pise los cambios." "Steam is open. It must be closed so it does not overwrite the changes.")"
  if [[ $YES -eq 1 ]]; then
    ans=s; echo "$(L "Cerrando Steam…" "Closing Steam...")"
  else
    read -r -p "$(L "¿Cerrar Steam ahora? [s/N] " "Close Steam now? [y/N] ")" ans
  fi
  if [[ "$ans" =~ ^[sSyY]$ ]]; then
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      pgrep -x steam >/dev/null 2>&1 || break
      sleep 1
    done
    if pgrep -x steam >/dev/null 2>&1; then
      echo "$(L "Steam no se ha cerrado. Ciérralo manualmente y vuelve a intentarlo." "Steam did not close. Close it manually and try again.")" >&2
      exit 1
    fi
  else
    echo "$(L "Cancelado." "Cancelled.")"
    exit 1
  fi
fi

export STEAM_DIR COLLECTION_NAME DRY_RUN TB_LANG

python3 - <<'PY'
import json, os, shutil, struct, sys, time, zlib, glob

L = lambda es, en: es if os.environ.get("TB_LANG", "en") == "es" else en

STEAM_DIR = os.environ["STEAM_DIR"]
NAME = os.environ["COLLECTION_NAME"]
DRY = os.environ["DRY_RUN"] == "1"
DEFAULT_ID = "uc-PortProtonSH"


# ---------- shortcuts.vdf (VDF binario) ----------
def parse_map(data, i):
    obj = {}
    while True:
        t = data[i]; i += 1
        if t == 0x08:
            return obj, i
        end = data.index(b"\0", i)
        key = data[i:end].decode("utf-8", "replace"); i = end + 1
        if t == 0x00:
            val, i = parse_map(data, i)
        elif t == 0x01:
            end = data.index(b"\0", i)
            val = data[i:end].decode("utf-8", "replace"); i = end + 1
        elif t == 0x02:
            val = struct.unpack_from("<i", data, i)[0]; i += 4
        elif t == 0x07:
            val = struct.unpack_from("<Q", data, i)[0]; i += 8
        else:
            raise ValueError(L(f"tipo VDF desconocido 0x{t:02x} en offset {i-1}", f"unknown VDF type 0x{t:02x} at offset {i-1}"))
        obj[key] = val


def get(d, key, default=None):
    for k, v in d.items():
        if k.lower() == key.lower():
            return v
    return default


def sh_shortcuts(path):
    with open(path, "rb") as f:
        data = f.read()
    root, _ = parse_map(data, 0)
    shortcuts = get(root, "shortcuts", {}) or {}
    found = {}
    for sc in shortcuts.values():
        exe = str(get(sc, "exe", "")).strip().strip('"')
        name = str(get(sc, "appname", ""))
        if not exe.lower().endswith(".sh"):
            continue
        appid = get(sc, "appid")
        if appid is None:  # accesos antiguos sin appid
            appid = zlib.crc32((get(sc, "exe", "") + name).encode()) | 0x80000000
        found[appid & 0xFFFFFFFF] = name
    return found


# ---------- colecciones (cloudstorage) ----------
def load_json(path, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, separators=(",", ":"))
    os.replace(tmp, path)


def backup(path):
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")


def process_user(udir):
    vdf = os.path.join(udir, "config", "shortcuts.vdf")
    cs_dir = os.path.join(udir, "config", "cloudstorage")
    ns_file = os.path.join(cs_dir, "cloud-storage-namespace-1.json")
    if not os.path.exists(vdf):
        return
    print(L(f"\n== Usuario {os.path.basename(udir)} ==", f"\n== User {os.path.basename(udir)} =="))

    games = sh_shortcuts(vdf)
    for appid, name in sorted(games.items(), key=lambda x: x[1].lower()):
        print(f"  [.sh] {name}  ({appid})")
    if not games:
        print(L("  (ningún acceso directo .sh)", "  (no .sh shortcuts)"))

    if not os.path.exists(ns_file):
        print(L(f"  No existe {ns_file}. Abre Steam una vez y crea cualquier colección, luego reintenta.", f"  {ns_file} does not exist. Open Steam once and create any collection, then retry."))
        return

    entries = load_json(ns_file, [])

    # Busca colección existente con ese nombre (por si la creaste a mano)
    idx, coll_id, old = None, DEFAULT_ID, None
    max_version = 0
    for n, (key, meta) in enumerate(entries):
        try:
            max_version = max(max_version, int(meta.get("version", 0)))
        except (TypeError, ValueError):
            pass
        if not key.startswith("user-collections.") or meta.get("is_deleted"):
            continue
        try:
            val = json.loads(meta.get("value", "{}"))
        except json.JSONDecodeError:
            continue
        if val.get("name") == NAME or key == f"user-collections.{DEFAULT_ID}":
            idx, coll_id, old = n, val.get("id", key.split(".", 1)[1]), val

    old_ids = set(old.get("added", [])) if old else set()
    new_ids = set(games)
    added, removed = new_ids - old_ids, old_ids - new_ids
    print(L(f"  Colección '{NAME}': +{len(added)} / -{len(removed)} (total {len(new_ids)})", f"  Collection '{NAME}': +{len(added)} / -{len(removed)} (total {len(new_ids)})"))

    if old is not None and not added and not removed:
        print(L("  Sin cambios.", "  No changes."))
        return
    if DRY:
        print(L("  (dry-run: no se escribe nada)", "  (dry-run: nothing is written)"))
        return

    key = f"user-collections.{coll_id}"
    version = str(max_version + 1)
    value = {"id": coll_id, "name": NAME, "added": sorted(new_ids), "removed": []}
    meta = {
        "key": key,
        "timestamp": int(time.time()),
        "value": json.dumps(value, separators=(",", ":")),
        "version": version,
        "conflictResolutionMethod": "custom",
        "strMethodId": "union-collections",
    }

    backup(ns_file)
    if idx is None:
        entries.append([key, meta])
    else:
        entries[idx] = [key, meta]
    save_json(ns_file, entries)

    # Marca la clave como modificada para que Steam la suba a la nube
    # en vez de sobreescribirla con la versión remota.
    mod_file = os.path.join(cs_dir, "cloud-storage-namespace-1.modified.json")
    mod = load_json(mod_file, [])
    if isinstance(mod, list) and key not in mod:
        backup(mod_file)
        mod.append(key)
        save_json(mod_file, mod)

    ns_versions = os.path.join(cs_dir, "cloud-storage-namespaces.json")
    nsv = load_json(ns_versions, None)
    if isinstance(nsv, list):
        backup(ns_versions)
        for item in nsv:
            if isinstance(item, list) and item and item[0] == 1:
                item[1] = version
        save_json(ns_versions, nsv)

    print(L("  ✔ Colección actualizada.", "  ✔ Collection updated."))


users = [d for d in glob.glob(os.path.join(STEAM_DIR, "userdata", "*"))
         if os.path.basename(d).isdigit() and os.path.basename(d) != "0"]
if not users:
    sys.exit(L("No hay usuarios en userdata/", "No users in userdata/"))
for u in users:
    process_user(u)
print(L("\nListo. Vuelve a abrir Steam (o Modo Juego) y mira en Biblioteca → Colecciones.", "\nDone. Reopen Steam (or Game Mode) and look in Library → Collections."))
PY
__PP_COLLECTION__
}
pp_remove_game_script() { cat <<'__PP_REMOVE_GAME__'
#!/usr/bin/env bash
# Run by ps5-bazzite-toolbox.sh (menu "Quitar un juego", --remove-game, or Dolphin's right-click action on the .exe).
# Removes a Windows game added with PortProton, asking before each part (nothing is removed without a yes):
#   1. Steam:      its non-Steam entry (shortcuts.vdf, backed up first) and its artwork; Steam must be closed.
#   2. PortProton: its .desktop (PortProton's list, the Desktop, the app menu) and steam_scripts/<Name>.sh.
#   3. Disk:       the game's folder (asks which one, shows the size, and wants the folder's name typed).
#   4. Collection: the toolbox's "PortProton" collection sync (COLLECTION_SCRIPT), so the entry leaves it too.
# Saved games inside PortProton's prefix (drive_c/users/...) are kept. The games the toolbox installed (ISO_LIST,
# normal or isolated) are listed first; an isolated one's own prefix (in ISO_SB) is offered for deletion at the
# end, "no" by default.
# Usage: remove-game [Game.exe | "Name"]   (no argument: lists the games PortProton knows and asks)
set -euo pipefail
if [ -z "${TB_LANG:-}" ]; then case ${LC_ALL:-${LC_MESSAGES:-${LANG:-}}} in es*) TB_LANG=es ;; *) TB_LANG=en ;; esac; fi
L() { if [ "$TB_LANG" = es ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
export TB_LANG

PP_ID=ru.linux_gaming.PortProton
PP="${PORT_WINE_PATH:-$HOME/.var/app/$PP_ID}"
STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
ARG=${1:-}
ISO_LIST=${ISO_LIST:-} ISO_SB=${ISO_SB:-}

say() { printf '%s\n' "$*"; }
ask() {                                   # ask "question" [default S|N] -> 0 for yes
    local def=${2:-N} ans
    read -r -p "$1 [$(if [ "$def" = S ]; then L S/n Y/n; else L s/N y/N; fi)] " ans || ans=
    ans=${ans:-$def}
    [[ $ans =~ ^[sSyY] ]]
}
section() { printf '\n== %s\n' "$*"; }
exe_of() { sed -n 's/^Exec=.*PortProton "\(.*\)"$/\1/p' "$1" | head -1; }

# --- which game ---------------------------------------------------------------------------------------
mapfile -t DESKS < <(find "$PP" -maxdepth 1 -name '*.desktop' ! -name 'PortProton.desktop' | sort)
# isolated games have no entry in PortProton's list: their exes come from ISO_LIST
mapfile -t ISOS < <(cut -f2 "$ISO_LIST" 2>/dev/null)
# PortProton entries of games already in that list are not shown twice
mapfile -t DESKS < <(for d in "${DESKS[@]}"; do printf '%s\n' "${ISOS[@]}" | grep -qxF -- "$(exe_of "$d")" || echo "$d"; done)
sh_name() { { grep -l -F "\"$1\"" "$PP"/steam_scripts/*.sh 2>/dev/null | head -1 | xargs -r -d '\n' basename -s .sh; } || true; }
NAME= EXE= DESK=
if [ -z "$ARG" ]; then
    [ ${#DESKS[@]} -gt 0 ] || [ ${#ISOS[@]} -gt 0 ] || { say "$(L "PortProton no tiene juegos." "PortProton has no games.")"; exit 0; }
    say "$(L "Juegos:" "Games:")"
    for i in "${!DESKS[@]}"; do
        e=$(exe_of "${DESKS[$i]}")
        printf '  %2d) %-40s %s\n' $((i + 1)) "$(basename "${DESKS[$i]}" .desktop)" "$([ -f "$e" ] || L '(el .exe ya no está)' '(the .exe is gone)')"
    done
    for i in "${!ISOS[@]}"; do
        e=${ISOS[$i]} nm=$(sh_name "${ISOS[$i]}")
        lv=$(awk -F'\t' -v e="$e" '$2 == e { print $1 }' "$ISO_LIST" | tail -1)
        printf '  %2d) %-40s %s\n' $((${#DESKS[@]} + i + 1)) "${nm:-$(basename "${e%.*}")}" "($lv)$([ -f "$e" ] || L ' (el .exe ya no está)' ' (the .exe is gone)')"
    done
    read -r -p "$(L "¿Cuál quitas? (número, Intro = ninguno): " "Which one to remove? (number, Enter = none): ")" n || n=
    [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le $((${#DESKS[@]} + ${#ISOS[@]})) ] || { say "$(L "Nada que hacer." "Nothing to do.")"; exit 0; }
    if [ "$n" -le ${#DESKS[@]} ]; then DESK=${DESKS[$((n - 1))]}; else EXE=${ISOS[$((n - ${#DESKS[@]} - 1))]}; fi
elif [ -f "$ARG" ]; then                  # an .exe (Dolphin): its PortProton shortcut, if any
    EXE=$(realpath "$ARG")
    for d in "${DESKS[@]}"; do [ "$(exe_of "$d")" = "$EXE" ] && { DESK=$d; break; }; done
else                                      # a name
    [ -f "$PP/$ARG.desktop" ] && DESK="$PP/$ARG.desktop" || { say "$(L "No encuentro «$ARG» en PortProton." "Cannot find «$ARG» in PortProton.")" >&2; exit 1; }
fi
if [ -n "$DESK" ]; then NAME=$(basename "$DESK" .desktop); EXE=${EXE:-$(exe_of "$DESK")}; fi
[ -n "$NAME" ] || [ -z "$EXE" ] || NAME=$(sh_name "$EXE")
NAME=${NAME:-$(basename "${EXE%.*}")}
SH="$PP/steam_scripts/$NAME.sh"
# an isolated game's prefix name is in its .ppdb, inside the folder step 3 may delete: read it now
ISO_PFX=
if [ -n "$EXE" ] && [ -n "$ISO_LIST" ] && cut -f2 "$ISO_LIST" 2>/dev/null | grep -qxF -- "$EXE"; then
    ISO_PFX=$(sed -n 's/^export PW_PREFIX_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$EXE.ppdb" 2>/dev/null | tail -1 || true)
fi
section "$(L "Juego: $NAME" "Game: $NAME")"
say "$(L "Ejecutable: ${EXE:-?}" "Executable: ${EXE:-?}")"
[ -n "$DESK" ] || say "$(L "(PortProton no tiene acceso directo para este .exe)" "(PortProton has no shortcut for this .exe)")"

# --- 1. Steam -------------------------------------------------------------------------------------------
section "1. Steam"
# entries whose target is this game's steam_scripts .sh, or any .sh that launches this exe
mapfile -t SHS < <({ [ -f "$SH" ] && echo "$SH"; [ -n "$EXE" ] && grep -l -F "\"$EXE\"" "$PP"/steam_scripts/*.sh 2>/dev/null; } | sort -u)
if [ ${#SHS[@]} = 0 ]; then
    say "$(L "No tiene script de Steam (steam_scripts): nada que quitar en Steam." "It has no Steam script (steam_scripts): nothing to remove in Steam.")"
else
    say "$(L "Quita de Steam las entradas que lanzan: ${SHS[*]##*/} (con copia de shortcuts.vdf) y sus carátulas." "Removes from Steam the entries that launch: ${SHS[*]##*/} (shortcuts.vdf is backed up) and their artwork.")"
    if ask "$(L "¿Quitarlo de Steam?" "Remove it from Steam?")" S; then
        if pgrep -x steam >/dev/null 2>&1; then
            if ask "$(L "  Steam está abierto y hay que cerrarlo (si no, al cerrarse vuelve a escribir el juego). ¿Cerrarlo?" "  Steam is open and must be closed (otherwise it writes the game back when it exits). Close it?")" S; then
                steam -shutdown >/dev/null 2>&1 || true
                for _ in $(seq 1 30); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
            fi
            pgrep -x steam >/dev/null 2>&1 && { say "$(L "  Steam sigue abierto: ciérralo y repite." "  Steam is still open: close it and try again.")" >&2; exit 1; }
        fi
        STEAM_DIR="$STEAM_DIR" GAME_SHS="$(printf '%s\n' "${SHS[@]}")" python3 - <<'PY'
# shortcuts.vdf is binary VDF: parsed into (type, key, value) lists and written back exactly as read
# (checked byte for byte), without the game's entries; the rest are renumbered 0, 1, 2...
import glob, os, shutil, struct, sys, time

L = lambda es, en: es if os.environ.get("TB_LANG", "en") == "es" else en

def parse(d, i):
    items = []
    while True:
        t = d[i]; i += 1
        if t == 0x08:
            return items, i
        e = d.index(b"\0", i); k = d[i:e]; i = e + 1
        if t == 0x00:
            v, i = parse(d, i)
        elif t == 0x01:
            e = d.index(b"\0", i); v = d[i:e]; i = e + 1
        elif t == 0x02:
            v = d[i:i + 4]; i += 4
        elif t == 0x07:
            v = d[i:i + 8]; i += 8
        else:
            raise ValueError(L(f"tipo VDF 0x{t:02x} desconocido en {i - 1}", f"unknown VDF type 0x{t:02x} at {i - 1}"))
        items.append((t, k, v))

def dump(items):
    out = bytearray()
    for t, k, v in items:
        out += bytes([t]) + k + b"\0"
        out += dump(v) if t == 0 else (v + b"\0" if t == 1 else v)
    return bytes(out + b"\x08")

def field(entry, key):
    for t, k, v in entry:
        if k.lower() == key.lower():
            return v
    return None

targets = {s for s in os.environ["GAME_SHS"].splitlines() if s}
for path in glob.glob(os.path.join(os.environ["STEAM_DIR"], "userdata", "*", "config", "shortcuts.vdf")):
    data = open(path, "rb").read()
    root, _ = parse(data, 0)
    if dump(root) != data:
        print(L(f"  {path}: no lo leo de forma exacta; no lo toco.", f"  {path}: cannot read it exactly; leaving it alone.")); continue
    sc = field(root, b"shortcuts")
    keep, gone = [], []
    for t, k, e in sc:
        exe = (field(e, b"exe") or b"").decode("utf-8", "replace").strip('"') if t == 0 else ""
        (gone if exe in targets else keep).append((t, k, e))
    if not gone:
        print(L(f"  Usuario {path.split(os.sep)[-3]}: no estaba en Steam.", f"  User {path.split(os.sep)[-3]}: it was not in Steam.")); continue
    sc[:] = [(t, str(n).encode(), e) for n, (t, k, e) in enumerate(keep)]
    shutil.copy2(path, f"{path}.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    tmp = path + ".tmp"
    open(tmp, "wb").write(dump(root)); os.replace(tmp, path)
    grid = os.path.join(os.path.dirname(path), "grid")
    for t, k, e in gone:
        appid = struct.unpack("<I", field(e, b"appid"))[0] if field(e, b"appid") else None
        name = (field(e, b"appname") or b"").decode("utf-8", "replace")
        art = glob.glob(os.path.join(grid, f"{appid}*")) if appid else []
        for f in art:
            os.remove(f)
        print(L(f"  Usuario {path.split(os.sep)[-3]}: quitado «{name}» (id {appid}; {len(art)} imágenes).", f"  User {path.split(os.sep)[-3]}: removed «{name}» (id {appid}; {len(art)} images)."))
PY
    fi
fi

# --- 2. PortProton ----------------------------------------------------------------------------------------
section "2. PortProton"
DESK_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
mapfile -t PPF < <({ for f in "$DESK" "$DESK_DIR/$NAME.desktop" "$HOME/.local/share/applications/$NAME.desktop" "${SHS[@]}"; do
    [ -n "$f" ] && [ -f "$f" ] && echo "$f"; done
    [ -z "$EXE" ] || grep -l -F -- "--run \"$EXE\"" "$DESK_DIR"/*.desktop 2>/dev/null; } | sort -u)
if [ ${#PPF[@]} = 0 ]; then
    say "$(L "No hay accesos directos ni scripts suyos." "It has no shortcuts or scripts.")"
else
    say "$(L "Borra sus accesos directos y su script de Steam:" "Deletes its shortcuts and its Steam script:")"; printf '  %s\n' "${PPF[@]}"
    say "$(L "(sus ajustes, $( [ -n "$EXE" ] && echo "${EXE##*/}.ppdb" || echo '.ppdb'), van con la carpeta del juego; las partidas del prefijo de PortProton se quedan)" "(its settings, $( [ -n "$EXE" ] && echo "${EXE##*/}.ppdb" || echo '.ppdb'), go with the game's folder; saved games in PortProton's prefix are kept)")"
    if ask "$(L "¿Borrarlos?" "Delete them?")" S; then rm -f -- "${PPF[@]}" && say "$(L "  Borrados." "  Deleted.")"; fi
fi

# --- 3. disk -------------------------------------------------------------------------------------------------
section "$(L "3. Disco" "3. Disk")"
if [ -z "$EXE" ] || [ ! -e "$EXE" ]; then
    say "$(L "El juego ya no está en el disco." "The game is no longer on disk.")"
else
    # proposal: the folder right under a games library (~/Games, PortProton's drive_c/Games...), else the
    # exe's folder without engine subfolders (Binaries/Win64...)
    d=$(dirname "$EXE") root=
    while [ "$d" != / ] && [ "$d" != "$HOME" ]; do
        case $(basename "$(dirname "$d")") in [Gg]ames|GAMES|[Jj]uegos) root=$d; break ;; esac
        d=$(dirname "$d")
    done
    if [ -z "$root" ]; then
        root=$(dirname "$EXE")
        while [[ $(basename "$root") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do root=$(dirname "$root"); done
    fi
    # never a home, a library itself, or a folder holding another PortProton game
    others=$(for f in "$PP"/*.desktop; do e=$(exe_of "$f"); [ "$e" != "$EXE" ] && [[ $e == "$root"/* ]] && basename "$f" .desktop; done || true)
    case $root in "$HOME"|"$HOME/Games"|"$PP"*/drive_c|"$PP"*/drive_c/Games|/) root= ;; esac
    if [ -z "$root" ] || [ -n "$others" ]; then
        say "$(L "No sé qué carpeta borrar sin riesgo${others:+ (también tiene: $others)}: bórrala tú a mano si quieres." "I cannot tell which folder is safe to delete${others:+ (it also holds: $others)}: delete it yourself if you want.")"
    else
        say "$(L "Carpeta del juego: $root ($(du -sh "$root" 2>/dev/null | cut -f1))" "Game folder: $root ($(du -sh "$root" 2>/dev/null | cut -f1))")"
        if ask "$(L "¿Borrarla del disco? (no se puede deshacer)" "Delete it from disk? (cannot be undone)")" N; then
            read -r -p "$(L "  Se borra $root entera. Para confirmar, escribe BORRAR: " "  $root will be deleted entirely. To confirm, type DELETE: ")" c || c=
            if [[ ${c^^} == BORRAR || ${c^^} == DELETE ]]; then rm -rf -- "$root" && say "$(L "  Borrada." "  Deleted.")"
            else say "$(L "  No has escrito BORRAR: no se borra." "  You did not type DELETE: nothing is deleted.")"; fi
        fi
    fi
fi

# --- the toolbox's list: forget it, and an isolated game's prefix if wanted ------------------------------------
if [ -n "$EXE" ] && [ -n "$ISO_LIST" ] && cut -f2 "$ISO_LIST" 2>/dev/null | grep -qxF -- "$EXE"; then
    pfx=$ISO_PFX
    tmp=$(mktemp); awk -F'\t' -v e="$EXE" '$2 != e' "$ISO_LIST" >"$tmp" && mv "$tmp" "$ISO_LIST"
    if [ -n "$pfx" ] && [ -d "$ISO_SB/data/prefixes/$pfx" ]; then
        section "$(L "Prefijo aislado" "Isolated prefix")"
        say "$(L "Su prefijo aislado, con sus partidas, está en $ISO_SB/data/prefixes/$pfx ($(du -sh "$ISO_SB/data/prefixes/$pfx" | cut -f1))." "Its isolated prefix, with its saved games, is at $ISO_SB/data/prefixes/$pfx ($(du -sh "$ISO_SB/data/prefixes/$pfx" | cut -f1)).")"
        if ask "$(L "¿Borrarlo? (no se puede deshacer)" "Delete it? (cannot be undone)")" N; then rm -rf -- "${ISO_SB:?}/data/prefixes/$pfx" && say "$(L "  Borrado." "  Deleted.")"; fi
    fi
fi

# --- 4. collection -----------------------------------------------------------------------------------------
section "$(L "4. Colección «PortProton» de Steam" "4. Steam collection «PortProton»")"
if [ -n "${COLLECTION_SCRIPT:-}" ] && [ -f "$COLLECTION_SCRIPT" ]; then
    if ask "$(L "¿Actualizar la colección (quita las entradas que ya no existen)?" "Update the collection (removes entries that no longer exist)?")" S; then
        bash "$COLLECTION_SCRIPT" --yes || say "$(L "  La colección no se actualizó (mira el mensaje de arriba)." "  The collection was not updated (see the message above).")"
    fi
else
    say "$(L "No encuentro el sincronizador de la colección: se salta." "Cannot find the collection sync script: skipping.")"
fi
section "$(L "Listo" "Done")"
say "$(L "Terminado con «$NAME»." "Finished with «$NAME».")"
if ! pgrep -x steam >/dev/null 2>&1 && ask "$(L "¿Abrir Steam ahora?" "Open Steam now?")" N; then
    setsid steam >/dev/null 2>&1 < /dev/null &
fi
__PP_REMOVE_GAME__
}
pp_collection() { bash <(pp_collection_script) "$@"; }
pp_remove_game() {
    local tmp rc
    tmp=$(mktemp) && pp_collection_script >"$tmp"
    COLLECTION_SCRIPT=$tmp ISO_LIST=$ISO_LIST ISO_SB=$ISO_SB bash <(pp_remove_game_script) "$@"; rc=$?
    rm -f "$tmp"; return $rc
}
pp_change_level() {
    local exe=${1:-} tmp rc
    [ -n "$exe" ] || { echo "$(L "Uso: --change-level Juego.exe" "Usage: --change-level Game.exe")" >&2; return 2; }
    tmp=$(mktemp) && pp_collection_script >"$tmp"
    COLLECTION_SCRIPT=$tmp TOOLBOX_CMD=$(toolbox_cmd) ISO_LIST=$ISO_LIST ISO_SB=$ISO_SB \
        bash <(pp_add_game_script) --change "$exe"; rc=$?
    rm -f "$tmp"; return $rc
}
# Frame generation (Lossless Scaling) per game: PortProton 1.7.5+ has it built in (lsfg-vk, downloaded on first use)
# and reads it from the game's .ppdb. Its own defaults (flow 0.1, fast model) look worse than ×2 at flow 0.5 with the
# quality model, which kept Gears of War E-Day at ~100 fps on the PS5 (flow 1.0 ran out of GPU and stuttered).
FG_DEFAULTS='PW_USE_LS_FRAME_GEN=1 LSFG_MULTIPLIER=2 LSFG_FLOW_SCALE=0.5 LSFG_PERF_MODE=0'
ppdb_get() { sed -n "s/^export $2=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$1" 2>/dev/null | tail -1; }
ppdb_set() {                             # ppdb_set FILE VAR VALUE: replace its line, or add one
    if grep -qs "^export $2=" "$1"; then sed -i "s|^export $2=.*|export $2=\"$3\"|" "$1"
    else printf 'export %s="%s"\n' "$2" "$3" >>"$1"; fi
}
pp_framegen() {
    local exe=${1:-} lv=${2:-} f kv a
    [ -n "$exe" ] || { echo "$(L "Uso: --framegen Juego.exe" "Usage: --framegen Game.exe")" >&2; return 2; }
    f="$exe.ppdb"
    [ -f "$f" ] || { echo "$(L "No está $f: abre el juego una vez con PortProton (o instálalo con la opción 10)." "$f is missing: open the game once with PortProton (or install it with option 10).")"; return 1; }
    section
    case $TB_LANG in
        es)
    say "Generación de fotogramas (Lossless Scaling, la que trae PortProton): inventa un fotograma entre cada dos"
    say "reales, así que ves el doble de fps (×2) o el triple (×3)."
    say "POR QUÉ: en juegos pesados se ve mucho más fluido (Gears of War E-Day: de ~25 a ~100 fps en pantalla)."
    say "PRECIO: el mando responde algo más tarde (más cuantos menos fps reales dé el juego), algo más de GPU y VRAM,"
    say "y fantasmas en lo que se mueve rápido. No para juegos de reflejos, 2D o con mucho texto. Va mejor con"
    say "40-60 fps reales y la pantalla a 120 Hz sin límite de fps (menú rápido → Rendimiento)."
    say "La primera vez PortProton descarga lsfg-vk: necesita red."
    say "DESHACER: aquí mismo, «Quitar» (borra esas líneas de ${f##*/})."
    [ "$lv" = sin-red ] && say "Ojo: este juego va aislado SIN red; si lsfg-vk no está descargado ya, no podrá bajarlo." ;;
        *)
    say "Frame generation (Lossless Scaling, the one built into PortProton): it invents a frame between every two"
    say "real ones, so you see double the fps (x2) or triple (x3)."
    say "WHY: in heavy games it looks much smoother (Gears of War E-Day: from ~25 to ~100 fps on screen)."
    say "COST: the controller responds a bit later (more so the fewer real fps the game gives), a bit more GPU and VRAM,"
    say "and ghosting on fast-moving things. Not for twitch games, 2D or text-heavy ones. Works best with"
    say "40-60 real fps and the screen at 120 Hz with no fps limit (quick menu → Performance)."
    say "The first time PortProton downloads lsfg-vk: it needs network."
    say "UNDO: right here, \"Remove\" (deletes those lines from ${f##*/})."
    [ "$lv" = sin-red ] && say "Note: this game runs isolated WITHOUT network; if lsfg-vk is not downloaded yet, it will not be able to fetch it." ;;
    esac
    while :; do
        echo
        if [ "$(ppdb_get "$f" PW_USE_LS_FRAME_GEN)" = 1 ]; then
            echo "$(L "  Ahora: activada, ×$(ppdb_get "$f" LSFG_MULTIPLIER) calidad $(ppdb_get "$f" LSFG_FLOW_SCALE)" "  Now: enabled, ×$(ppdb_get "$f" LSFG_MULTIPLIER) quality $(ppdb_get "$f" LSFG_FLOW_SCALE)")" \
                 "$(L modelo model) $([ "$(ppdb_get "$f" LSFG_PERF_MODE)" = 1 ] && L rápido fast || L 'de calidad' quality)"
            echo "$(L "  1) Multiplicador ×2 / ×3   2) Calidad (0.5 / 0.75 / 1.0)   3) Modelo rápido / de calidad   4) Quitar   0) Volver" "  1) Multiplier ×2 / ×3   2) Quality (0.5 / 0.75 / 1.0)   3) Model fast / quality   4) Remove   0) Back")"
            read -rp "$(L '  Elige: ' '  Choose: ')" a
            case $a in
                1) read -rp "$(L "  Multiplicador (2 = el doble; 3 solo si el juego da ~40 fps reales) [2]: " "  Multiplier (2 = double; 3 only if the game gives ~40 real fps) [2]: ")" a
                   [[ ${a:-2} =~ ^[23]$ ]] && ppdb_set "$f" LSFG_MULTIPLIER "${a:-2}" ;;
                2) say "$(L "Resolución a la que calcula el movimiento: más alta, menos fantasmas y más GPU." "Resolution at which it computes motion: higher means less ghosting and more GPU.")" \
                       "$(L "1.0 se le atraganta a la PS5 en juegos pesados (tirones); a 4K, 0.5." "1.0 chokes the PS5 in heavy games (stutter); at 4K, use 0.5.")"
                   read -rp "$(L "  Calidad (0.5 / 0.75 / 1.0) [0.5]: " "  Quality (0.5 / 0.75 / 1.0) [0.5]: ")" a
                   [[ ${a:-0.5} =~ ^(0\.5|0\.75|1\.0)$ ]] && ppdb_set "$f" LSFG_FLOW_SCALE "${a:-0.5}" ;;
                3) if [ "$(ppdb_get "$f" LSFG_PERF_MODE)" = 1 ]; then ppdb_set "$f" LSFG_PERF_MODE 0
                   else ppdb_set "$f" LSFG_PERF_MODE 1; fi ;;
                4) sed -i '/^export PW_USE_LS_FRAME_GEN=/d; /^export LSFG_/d' "$f"; echo "$(L "  Quitada." "  Removed.")" ;;
                *) break ;;
            esac
        else
            echo "$(L "  Ahora: desactivada." "  Now: disabled.")"
            ask "$(L "¿Activarla (×2, calidad 0.5, modelo de calidad)?" "Enable it (×2, quality 0.5, quality model)?")" N || break
            for kv in $FG_DEFAULTS; do ppdb_set "$f" "${kv%%=*}" "${kv#*=}"; done
            echo "$(L "  Activada. Cuenta la próxima vez que abras el juego." "  Enabled. It counts the next time you open the game.")"
        fi
    done
    return 0
}
# "Mis juegos": one list, by name, of the games installed with the toolbox (ISO_LIST, any level) and PortProton's
# other games (normal: PortProton starts them unisolated). Changing the level of one of those adds it to ISO_LIST.
pp_my_games() {
    local list e d nm lv a c i
    local -a rows
    list=$(mktemp)
    while IFS=$'\t' read -r lv e nm _; do
        [ -n "$e" ] && printf '%s\t%s\t%s\n' "${nm:-$(basename "${e%.*}")}" "$lv" "$e"
    done < <(cat "$ISO_LIST" 2>/dev/null) >"$list"
    for d in "$PP_APP"/*.desktop; do
        [ -f "$d" ] && [ "${d##*/}" != PortProton.desktop ] || continue
        e=$(sed -n 's/^Exec=.*PortProton "\(.*\)"$/\1/p' "$d" | head -1)
        [ -n "$e" ] && ! cut -f3 "$list" | grep -qxF -- "$e" || continue
        printf '%s\tnormal\t%s\n' "$(basename "$d" .desktop)" "$e" >>"$list"
    done
    mapfile -t rows < <(sort -f -t$'\t' -k1,1 "$list"); rm -f "$list"
    [ ${#rows[@]} -gt 0 ] || { echo "$(L "No hay juegos instalados (opción 10 o, en Dolphin, «Instalar en PortProton y Steam»)." "No games installed (option 10 or, in Dolphin, «Install in PortProton and Steam»).")"; return 0; }
    echo
    for i in "${!rows[@]}"; do
        IFS=$'\t' read -r nm lv e <<<"${rows[$i]}"
        case $lv in red) lv="$(L "aislado con red" "isolated with network")" ;; sin-red) lv="$(L "aislado sin red" "isolated without network")" ;; esac
        printf '  %2d) %-40s %s%s\n' $((i + 1)) "$nm" "$lv" "$([ -f "$e" ] || L '  (el .exe ya no está)' '  (the .exe is gone)')"
    done
    read -rp "$(L "¿Cuál? (número, Intro = volver): " "Which one? (number, Enter = back)")" a
    [[ $a =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#rows[@]} ] || return 0
    IFS=$'\t' read -r nm lv e <<<"${rows[$((a - 1))]}"
    echo "$(L "$nm:  1) Cambiar aislamiento   2) Desinstalar   3) Generación de fotogramas   0) Volver" "$nm:  1) Change isolation   2) Uninstall   3) Frame generation   0) Back")"
    read -rp "$(L "Elige: " "Choose: ")" c
    case $c in
        1) if [ -f "$e" ]; then pp_change_level "$e"; else echo "$(L "El .exe ya no está: solo se puede desinstalar." "The .exe is gone: it can only be uninstalled.")"; fi ;;
        2) if [ -f "$e" ]; then pp_remove_game "$e"; else pp_remove_game "$nm"; fi ;;
        3) if [ -f "$e" ]; then pp_framegen "$e" "$lv"; else echo "$(L "El .exe ya no está: solo se puede desinstalar." "The .exe is gone: it can only be uninstalled.")"; fi ;;
    esac
    return 0
}
toolbox_cmd() {                          # what Steam scripts and shortcuts call: the installed copy if it is this version
    if [ "$("$TOOLBOX_BIN" --version 2>/dev/null)" = "ps5-bazzite-toolbox $TOOLBOX_VERSION" ]; then echo "$TOOLBOX_BIN"
    else echo "$TOOLBOX_SELF"; fi
}
pp_add_game() {
    local exe=${1:-} tmp rc
    if [ -z "$exe" ]; then
        read -e -rp "$(L "Ruta del .exe del juego (puedes arrastrarlo aquí desde Dolphin): " "Path to the game .exe (you can drag it here from Dolphin): ")" exe
        exe=${exe%'}; exe=${exe#'}       # Dolphin drops paths quoted
        [ -n "$exe" ] || return 1
        set -- "$exe"
    fi
    tmp=$(mktemp) && pp_collection_script >"$tmp"
    COLLECTION_SCRIPT=$tmp TOOLBOX_CMD=$(toolbox_cmd) ISO_LIST=$ISO_LIST ISO_SB=$ISO_SB \
        bash <(pp_add_game_script) "$@"; rc=$?
    rm -f "$tmp"; return $rc
}

# --- isolated games -----------------------------------------------------------------------------------------------
# PortProton's Flatpak has filesystems=host: a Windows program run through it can read, change or delete anything
# the user can (home, NAS, other games' prefixes). An isolated run gets fewer rights from Flatpak itself:
#  - no host/home/NAS (every extra filesystem the app has is taken away), no UDisks2/NetworkManager, and with
#    level "sin-red" no network either;
#  - the real PortProton (~/.var/app/<id>) read-only; it runs from a COPY (ISO_SB, kept in sync with rsync, its
#    own prefixes excluded) by pointing XDG_DATA_HOME there: the wrapper then takes PORT_WINE_PATH from it;
#  - only the game's folder and that copy are writable.
# Not a VM: screen (X11), sound and controllers stay shared, and a kernel or Flatpak escape is not covered.
# Levels: normal, red, sin-red; kept in ISO_LIST as "level<TAB>exe<TAB>name<TAB>folder it sees" (isolated). Each isolated game has its own
# prefix in the copy (PortProton also makes empty DEFAULT and DOTNET there).
ISO_SB=$HOME/.local/share/ps5-bazzite-toolbox/aislado
ISO_LIST=$HOME/.config/ps5-bazzite-toolbox-juegos.conf
ISO_RUNLOG=$HOME/.cache/ps5-bazzite-toolbox-run.log
PP_APP=$HOME/.var/app/ru.linux_gaming.PortProton
iso_level() {                            # iso_level EXE -> normal | red | sin-red
    awk -F'\t' -v e="$1" '$2 == e { l = $1 } END { print (l ? l : "normal") }' "$ISO_LIST" 2>/dev/null || echo normal
}
game_root() {                            # the game's folder: up through engine folders (Binaries/Win64...), as --add-game
    local d; d=$(dirname "$1")
    while [[ $(basename "$d") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do d=$(dirname "$d"); done
    [ -d "$d/../Engine" ] && d=$(dirname "$d")                     # Unreal: Game/Binaries/Win64 next to Engine/
    echo "$d"
}
iso_root_ok() {                          # the game's folder is shared writable: refuse home, PortProton, NAS, disks
    case $HOME/ in "$1"/*) echo "$(L "El juego está directamente en $1: muévelo a su propia carpeta (p. ej. ~/Juegos/Juego/)." "The game is directly in $1: move it to its own folder (e.g. ~/Games/Game/).")" >&2; return 1 ;; esac
    case $1/ in "$PP_APP"/*|/var/mnt/*|/mnt/*|/run/media/*)
        echo "$(L "La carpeta del juego ($1) queda escribible para él: tiene que ser una carpeta local propia" "The game's folder ($1) becomes writable for it: it must be its own local folder")" >&2
        echo "$(L "(p. ej. ~/Juegos/Juego/), no PortProton, el NAS ni un disco externo. Cópialo allí antes." "(e.g. ~/Games/Game/), not PortProton, the NAS or an external disk. Copy it there first.")" >&2; return 1 ;;
    esac
}
iso_sync() {                             # the copy of PortProton: everything but its prefixes; rsync undoes any change
    [ -d "$ISO_SB/data/scripts" ] ||
        echo "$(L "Primera vez: copio PortProton sin los prefijos ($(du -sh --exclude=prefixes "$PP_APP/data" 2>/dev/null | cut -f1)) a $ISO_SB, tarda un poco…" "First time: copying PortProton without the prefixes ($(du -sh --exclude=prefixes "$PP_APP/data" 2>/dev/null | cut -f1)) to $ISO_SB, this takes a while...")"
    mkdir -p "$ISO_SB/data" "$ISO_SB/cache" "$ISO_SB/config" &&
        rsync -a --delete --exclude=/prefixes/ "$PP_APP/data/" "$ISO_SB/data/" &&
        rsync -a --delete "$PP_APP/config/" "$ISO_SB/config/" || { echo "$(L "No pude preparar la copia en $ISO_SB." "Could not prepare the copy in $ISO_SB.")" >&2; return 1; }
}
iso_launch() {                           # iso_launch EXE ROOT red|sin-red gui|steam -> runs it in the sandbox
    local exe=$1 root=$2 level=$3 how=$4 f d
    local -a flags=(--nofilesystem=host --nofilesystem=home
                    --system-no-talk-name=org.freedesktop.UDisks2 --system-no-talk-name=org.freedesktop.NetworkManager)
    [ "$level" = sin-red ] && flags+=(--unshare=network)
    # extra folders the app was given (e.g. the NAS by the "nas" block)
    while IFS= read -r f; do
        case $f in /*|'~'/*) flags+=("--nofilesystem=${f%%:*}") ;; esac
    done < <(flatpak info --show-permissions ru.linux_gaming.PortProton 2>/dev/null | sed -n 's/^filesystems=//p' | tr ';' '\n')
    for d in "$PP_APP"/*/ "$PP_APP"/.[!.]*/; do               # the real PortProton, read-only (its folder itself can't be)
        [ -d "$d" ] && [ ! -L "${d%/}" ] && flags+=("--filesystem=${d%/}:ro")
    done
    flags+=("--filesystem=$ISO_SB" "--filesystem=$root")
    # START_FROM_STEAM=1: PortProton starts the game straight away with its .ppdb, without its window
    flatpak run "${flags[@]}" --command=bash ru.linux_gaming.PortProton -c \
        'export XDG_DATA_HOME=$1 XDG_CACHE_HOME=$2 XDG_CONFIG_HOME=$3; [ "$5" = steam ] && export START_FROM_STEAM=1; /app/bin/portproton "$4"' \
        _ "$ISO_SB/data" "$ISO_SB/cache" "$ISO_SB/config" "$exe" "$how"
}

# --run EXE [--gui] [--level red|sin-red] [--root DIR]: what Steam and the desktop shortcut of an isolated game call. Asks nothing
# (Game Mode has no one to answer); its output goes to ISO_RUNLOG when there is no terminal.
pp_run_game() {
    local exe='' how=steam level='' root=''
    while [ $# -gt 0 ]; do
        case $1 in --gui) how=gui; shift ;; --level) level=$2; shift 2 ;; --root) root=$2; shift 2 ;; *) exe=$1; shift ;; esac
    done
    [ -t 1 ] || { mkdir -p "$(dirname "$ISO_RUNLOG")"; exec >"$ISO_RUNLOG" 2>&1; echo "$(date '+%F %T') --run $exe"; }
    [ -f "$exe" ] || { echo "$(L "No existe: $exe" "Does not exist: $exe")" >&2; return 1; }
    exe=$(realpath "$exe")
    [ -n "$root" ] || root=$(awk -F'\t' -v e="$exe" '$2 == e && $4 != "" { r = $4 } END { print r }' "$ISO_LIST" 2>/dev/null)
    [ -n "$root" ] || root=$(game_root "$exe")
    level=${level:-$(iso_level "$exe")}
    if [ "$level" = normal ]; then                 # not isolated: as PortProton's own Steam script
        START_FROM_STEAM=$([ $how = steam ] && echo 1) flatpak run ru.linux_gaming.PortProton "$exe"; return
    fi
    iso_root_ok "$root" && iso_sync || return 1
    iso_launch "$exe" "$root" "$level" "$how"
}

# Space taken by each folder in DIR (hidden ones too), smallest first, and the total. Was ~/verEspacioCadaDirectorio.sh.
space_report() {
    local d=${1:-.}
    cd "$d" 2>/dev/null || { echo "$(L "No existe la carpeta: $d" "Folder does not exist: $d")" >&2; return 1; }
    echo "$(L "Lo que ocupa cada carpeta de $(pwd):" "Space used by each folder in $(pwd):")"
    du -bsh -- */ .[!.]*/ 2>/dev/null | sort -h
    echo "Total: $(du -bsh . 2>/dev/null | cut -f1)"
}

# Black screen with the console still running: moving to another virtual console and back makes the GPU set
# the picture up again (what ps5-hdmi-kick does once after a warm reboot). Nothing is closed.
screen_kick() {
    local vt; vt=$(sudo fgconsole 2>/dev/null || echo 1); [ "$vt" = 2 ] && vt=1
    echo "$(L "Cambiando a la consola 2 y volviendo a la $vt…" "Switching to console 2 and back to $vt...")"
    sudo chvt 2 && sleep 3 && sudo chvt "$vt"
}

# ======================================== backup of the home folder ========================================
# Saves your home folder, all of it or what you pick, to another disk, the NAS or any folder, and brings it back here
# or on another system (a new install, bootc). What a new install lacks and lives outside it is saved too: Decky's
# service and the list of system Flatpaks. Links that leave the home folder (the ROMs on the NAS) are saved as links,
# not their contents: they work again once the NAS is mounted (block nas).
# On a Linux disk (ext4, btrfs, xfs) the copy is a plain folder updated with rsync (a second run only copies what
# changed); on the NAS or exFAT, one .tar.zst per folder (SMB and exFAT can't keep links and permissions).
# Recovering also works straight from another system's disk (its home folder, or the root of a mounted disk).
BK_INFO=ps5-copia.info
BK_TO=${BK_TO:-$HOME}                    # where a restore writes (only changed to test it)
BK_P=() BK_ON=() BK_SZ=() BK_DS=()       # the list being picked: path (relative), on 1/0, bytes, description

hsize() { awk -v b="${1:-0}" 'BEGIN { split("B KB MB GB TB", u); i = 1; while (b >= 1000 && i < 5) { b /= 1024; i++ }
                                   f = (i > 3 && b < 10) ? "%.1f %s" : "%d %s"; printf f, b, u[i] }' | tr . ,; }
bk_du() { du -sbx -- "$1" 2>/dev/null | cut -f1; }
bk_esc() { sed 's/[][\\*?]/\\&/g' <<<"$1"; }   # a literal path as an rsync pattern

bk_known() {                             # bk_known ROOT -> "path<TAB>1|0<TAB>why" for the places worth their own line
    local r=$1 p dl
    bk_k() { [ -d "$r/$1" ] && [ ! -L "$r/$1" ] && printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }
    bk_k .cache 0 "$(L "cachés de los programas: se rehacen solas" "program caches: they rebuild themselves")"
    bk_k .local/share/Trash 0 "$(L "la papelera" "the trash")"
    bk_k .local/share/Steam/steamapps/common 1 "$(L "juegos de Steam instalados (sin ellos, Steam los vuelve a descargar)" "installed Steam games (without them, Steam downloads them again)")"
    bk_k .local/share/Steam/steamapps/compatdata 1 "$(L "prefijos de Proton de Steam (partidas de algunos juegos)" "Steam Proton prefixes (saves of some games)")"
    bk_k .local/share/Steam/steamapps/shadercache 0 "$(L "sombreadores de Steam: se rehacen" "Steam shader cache: it rebuilds itself")"
    bk_k .config/rpcs3/dev_hdd1 0 "$(L "caché de RPCS3: se rehace" "RPCS3 cache: it rebuilds itself")"
    bk_k Emulation/storage/rpcs3/dev_hdd0/game 1 "$(L "juegos de PS3 instalados en RPCS3" "PS3 games installed in RPCS3")"
    bk_k Games 1 "$(L "juegos (portables, de Heroic…): sin ellos, sus accesos de Steam y PortProton no abren" "games (portable, Heroic…): without them, their Steam and PortProton shortcuts won't open")"
    bk_k Games/Heroic 1 "$(L "juegos instalados con Heroic" "games installed with Heroic")"
    for p in "$r"/.var/app/ru.linux_gaming.PortProton/data/prefixes/*/ "$r"/.local/share/ps5-bazzite-toolbox/aislado/data/prefixes/*/; do
        [ -d "$p" ] || continue; p=${p%/}; p=${p#"$r"/}
        bk_k "$p" 1 "$(L "prefijo de PortProton ${p##*/} (programas y partidas de sus juegos)" "PortProton prefix ${p##*/} (programs and saves of its games)")"
        bk_k "$p/drive_c/Games" 1 "$(L "juegos instalados en el prefijo ${p##*/}" "games installed in the prefix ${p##*/}")"
    done
    dl=$(xdg-user-dir DOWNLOAD 2>/dev/null); dl=${dl#"$HOME"/}
    [ -n "$dl" ] && [ "$dl" != "$HOME" ] && bk_k "$dl" 1 "$(L "descargas" "downloads")"
    true
}

bk_scan() {                              # bk_scan ROOT [ONLY-THESE] -> fills BK_*: big top folders + the known places inside them
    local r=$1 only=${2:-} p sz small=0 n=0 rest=0 kp kon kds
    BK_P=() BK_ON=() BK_SZ=() BK_DS=()
    echo "$(L "Midiendo lo que ocupa cada carpeta de $r (la primera vez puede tardar un par de minutos)…" "Measuring how much each folder of $r takes (the first time it can take a couple of minutes)…")"
    local known; known=$(bk_known "$r")
    while IFS=$'\t' read -r sz p; do
        p=${p#"$r"/}
        if [ "$sz" -lt $((100 << 20)) ] && { [ "$sz" -lt $((1 << 20)) ] || ! awk -F'\t' -v p="$p" '$1 == p { f = 1 } END { exit !f }' <<<"$known"; }; then rest=$((rest + sz)); small=$((small + 1)); continue; fi
        BK_P+=("$p") BK_ON+=(1) BK_SZ+=("$sz") BK_DS+=("")
        while IFS=$'\t' read -r kp kon kds; do
            [ "$kp" = "$p" ] && { BK_ON[-1]=$kon; BK_DS[-1]=$kds; continue; }
            [[ $kp == "$p"/* ]] || continue
            sz=$(bk_du "$r/$kp"); [ "${sz:-0}" -ge $((1 << 20)) ] || continue     # empty ones only make the list longer
            BK_P+=("$kp") BK_ON+=("$kon") BK_SZ+=("$sz") BK_DS+=("$kds")
        done <<<"$known"
    done < <(find "$r" -mindepth 1 -maxdepth 1 -type d ! -name lost+found -exec du -sbx {} + 2>/dev/null | sort -rn)
    BK_REST=$rest BK_SMALL=$small
    if [ -n "$only" ]; then              # a copy: what it holds, as it was picked then
        for n in "${!BK_P[@]}"; do grep -qxF "${BK_P[$n]}" "$only" && BK_ON[n]=1 || BK_ON[n]=0; done
    fi
}

bk_parent_off() {                        # bk_parent_off N -> 0 if a folder holding item N is not saved
    local i
    for i in "${!BK_P[@]}"; do [ "$i" != "$1" ] && [ "${BK_ON[$i]}" = 0 ] && [[ ${BK_P[$1]} == "${BK_P[$i]}"/* ]] && return 0; done
    return 1
}
bk_excluded() {                          # the paths left out, the outermost only
    local n
    for n in "${!BK_P[@]}"; do [ "${BK_ON[$n]}" = 0 ] && ! bk_parent_off "$n" && printf '%s\n' "${BK_P[$n]}"; done
}
bk_total() {                             # bytes picked: the top folders saved, minus what is left out inside them
    local n t=${BK_REST:-0}
    for n in "${!BK_P[@]}"; do
        [[ ${BK_P[$n]} == */* ]] && continue
        [ "${BK_ON[$n]}" = 1 ] && t=$((t + BK_SZ[n]))
    done
    while read -r p; do [ -n "$p" ] && [[ $p == */* ]] && for n in "${!BK_P[@]}"; do [ "${BK_P[$n]}" = "$p" ] && t=$((t - BK_SZ[n])); done; done < <(bk_excluded)
    echo "$t"
}

bk_pick() {                              # bk_pick ROOT WHAT -> the user marks what goes; 1 if cancelled
    local r=$1 what=$2 a n i d c
    while :; do
        printf "$(L '\n  %s (marca o desmarca con su número):\n' '\n  %s (tick or untick with its number):\n')" "$what"
        for n in "${!BK_P[@]}"; do
            d=0; for i in "${!BK_P[@]}"; do [[ ${BK_P[$n]} == "${BK_P[$i]}"/* ]] && d=$((d + 1)); done; c='[x]'; [ "${BK_ON[$n]}" = 0 ] && c='[ ]'; bk_parent_off "$n" && c=' - '
            printf '  %3d %*s%s %8s  %s%s\n' $((n + 1)) $((d * 2)) '' "$c" "$(hsize "${BK_SZ[$n]}")" "${BK_P[$n]}" \
                "${BK_DS[$n]:+  — ${BK_DS[$n]}}"
        done
        [ "${BK_SMALL:-0}" = 0 ] || printf "$(L '      [x] %8s  %s carpetas pequeñas y los ficheros sueltos (van siempre)\n' '      [x] %8s  %s small folders and the loose files (always included)\n')" "$(hsize "$BK_REST")" "$BK_SMALL"
        printf "$(L '  Total marcado: %s\n' '  Total selected: %s\n')" "$(hsize "$(bk_total)")"
        read -rp "$(L "  Números (p. ej. 1 4), a N = elegir dentro de la carpeta N, Intro = seguir, 0 = cancelar: " "  Numbers (e.g. 1 4), a N = pick inside folder N, Enter = continue, 0 = cancel: ")" a
        case $a in
            '') return 0 ;;
            0) return 1 ;;
            a\ *|A\ *) n=$(( ${a#* } - 1 ))
                [ "$n" -ge 0 ] 2>/dev/null && [ -n "${BK_P[$n]:-}" ] || { echo "$(L "  No hay carpeta ${a#* }" "  No such folder ${a#* }")"; continue; }
                bk_open "$r" "$n" ;;
            *) for i in $a; do
                   [[ $i =~ ^[0-9]+$ ]] && [ -n "${BK_P[$((i - 1))]:-}" ] || { echo "$(L "  No hay carpeta $i" "  No such folder $i")"; continue; }
                   BK_ON[i - 1]=$((1 - BK_ON[i - 1]))
               done ;;
        esac
    done
}
bk_open() {                              # bk_open ROOT N -> the folders inside item N (over 10 MB) get their own lines after it
    local r=$1 n=$2 p sz new=() on=() szs=() ds=() i
    while IFS=$'\t' read -r sz p; do
        p=${p#"$r"/}; [ "$sz" -lt $((10 << 20)) ] && continue
        for i in "${BK_P[@]}"; do [ "$i" = "$p" ] && continue 2; done
        new+=("$p") on+=("${BK_ON[$n]}") szs+=("$sz") ds+=("")
    done < <(find "$r/${BK_P[$n]}" -mindepth 1 -maxdepth 1 -type d -exec du -sbx {} + 2>/dev/null | sort -rn)
    [ ${#new[@]} -gt 0 ] || { echo "$(L "  No tiene carpetas de más de 10 MB que no estén ya en la lista." "  It has no folders over 10 MB that are not already in the list.")"; return; }
    BK_P=("${BK_P[@]:0:n+1}" "${new[@]}" "${BK_P[@]:n+1}")
    BK_ON=("${BK_ON[@]:0:n+1}" "${on[@]}" "${BK_ON[@]:n+1}")
    BK_SZ=("${BK_SZ[@]:0:n+1}" "${szs[@]}" "${BK_SZ[@]:n+1}")
    BK_DS=("${BK_DS[@]:0:n+1}" "${ds[@]}" "${BK_DS[@]:n+1}")
}

bk_links() {                             # bk_links ROOT -> "link<TAB>target" for links into another disk or the NAS
    find "$1" -xdev -type l \( -lname '/var/mnt/*' -o -lname '/mnt/*' -o -lname '/run/media/*' -o -lname '/media/*' \) \
        -printf '%P\t%l\n' 2>/dev/null
}
bk_orphans() {                           # PortProton shortcuts whose game would be left out (from the list in $1)
    local f exe p
    for f in "$BK_SRC_ROOT"/PortProton/*.desktop "$BK_SRC_ROOT"/.var/app/ru.linux_gaming.PortProton/*.desktop; do
        [ -f "$f" ] || continue
        exe=$(sed -n 's/^Exec=.*PortProton "\(.*\)"$/\1/p' "$f" | head -1); [ -n "$exe" ] || continue
        exe=${exe#"$HOME"/}
        while read -r p; do [ -n "$p" ] && [[ $exe == "$p"/* ]] && { printf '%s\n' "$(basename "$f" .desktop)"; break; }; done <"$1"
    done | sort -u
}

bk_dest_pick() {                         # asks where the copy goes -> BK_DEST (a folder)
    local c=() m a n
    while read -r m; do [ -n "$m" ] && c+=("$m"); done < <(
        { findmnt -rno TARGET -t ext4,btrfs,xfs,exfat,ntfs,ntfs3,f2fs | grep -E "^/run/media/|^/var/mnt/|^/mnt/"
          awk '$3 == "cifs" || $3 == "nfs" || $3 == "nfs4" { print $2 }' /etc/fstab; } 2>/dev/null | sort -u)
    echo "$(L "  ¿Dónde la guardo? Se crea dentro la carpeta ps5-copia-$U." "  Where do I save it? The folder ps5-copia-$U is created inside.")"
    for n in "${!c[@]}"; do
        printf "$(L '  %d) %s  (%s libres, %s)\n' '  %d) %s  (%s free, %s)\n')" $((n + 1)) "${c[$n]}" "$(df -h --output=avail "${c[$n]}" 2>/dev/null | tail -1 | tr -d ' ')" \
            "$(findmnt -no FSTYPE -T "${c[$n]}" 2>/dev/null | tail -1)"
    done
    read -e -rp "$(L "  Número, u otra carpeta (Intro = cancelar): " "  Number, or another folder (Enter = cancel): ")" a
    [ -n "$a" ] || return 1
    if [[ $a =~ ^[0-9]+$ ]] && [ -n "${c[$((a - 1))]:-}" ]; then a=${c[$((a - 1))]}; fi
    a=${a/#\~/$HOME}
    timeout 20 test -d "$a" || { echo "$(L "  No existe o no responde: $a" "  It does not exist or does not respond: $a")"; return 1; }
    BK_DEST=$(realpath "$a")/ps5-copia-$U
}

bk_mode() {                              # bk_mode DIR -> rsync (Linux filesystem) | tar (SMB, exFAT, NTFS) | no (FAT)
    case $(findmnt -no FSTYPE -T "$1" 2>/dev/null | tail -1) in
        ext4|ext3|btrfs|xfs|f2fs) echo rsync ;;
        vfat|msdos) echo no ;;
        *) echo tar ;;
    esac
}

bk_save() {
    local mode free need ex list a p rc=0 n kind
    echo
    echo "${B}$(L "Copia de seguridad de tu carpeta personal ($HOME)" "Backup of your home folder ($HOME)")${N}"
    section
    case $TB_LANG in
        es)
    say "Copia tu carpeta personal, entera o lo que elijas, a otro disco, al NAS o a una carpeta, para recuperarla"
    say "aquí o en otra instalación (la opción 20 → recuperar). Se guardan también el servicio de Decky y la lista de"
    say "Flatpaks del sistema. Los enlaces que salen de tu carpeta (ROMs en el NAS) se guardan como enlace."
    say "POR QUÉ: para cambiar de disco o de instalación (p. ej. a bootc) sin perder juegos, partidas ni ajustes."
    say "No cambia nada en tu carpeta. DESHACER: borra la carpeta de la copia." ;;
        *)
    say "Copies your home folder, all of it or what you pick, to another disk, the NAS or a folder, to recover it"
    say "here or on another install (option 20 → restore). Decky's service and the list of system Flatpaks are"
    say "saved too. Links that leave your folder (ROMs on the NAS) are saved as links."
    say "WHY: to change disk or install (e.g. to bootc) without losing games, saves or settings."
    say "It changes nothing in your folder. UNDO: delete the copy's folder." ;;
    esac
    bk_dest_pick || return 1
    mode=$(bk_mode "$(dirname "$BK_DEST")")
    [ "$mode" != no ] || { echo "$(L "  Ese disco es FAT: no admite ficheros de más de 4 GB. Usa otro (ext4 o exFAT) o el NAS." "  That disk is FAT: it can't hold files over 4 GB. Use another one (ext4 or exFAT) or the NAS.")"; return 1; }
    case $BK_DEST/ in "$HOME"/*) [ "$(stat -c %d "$(dirname "$BK_DEST")")" != "$(stat -c %d "$HOME")" ] ||
        { echo "$(L "  La copia no puede ir dentro de tu propia carpeta, en el mismo disco." "  The copy can't go inside your own folder, on the same disk.")"; return 1; } ;; esac
    BK_SRC_ROOT=$HOME
    bk_scan "$HOME" || return 1
    bk_pick "$HOME" "$(L "Qué se guarda de $HOME" "What to save from $HOME")" || return 1
    list=$(mktemp); bk_excluded >"$list"
    a=$(bk_orphans "$list")
    [ -z "$a" ] || { echo "$(L "  Ojo: estos juegos de PortProton quedan fuera de la copia (al recuperarla no abrirán hasta que copies sus ficheros):" "  Careful: these PortProton games are left out of the copy (after restoring they won't open until you copy their files):")"
                     sed 's/^/    /' <<<"$a"; }
    echo "$(L "  Buscando enlaces a otros discos o al NAS…" "  Looking for links to other disks or the NAS…")"
    p=$(bk_links "$HOME" | head -20)
    [ -z "$p" ] || { echo "$(L "  Enlaces a otros discos o al NAS: se guarda el enlace, no lo que hay al otro lado (al recuperar, el enlace vuelve):" "  Links to other disks or the NAS: the link is saved, not what is on the other side (when restoring, the link comes back):")"
                     sed 's/\t/ -> /; s/^/    /' <<<"$p"; }
    need=$(bk_total); free=$(df -B1 --output=avail "$(dirname "$BK_DEST")" | tail -1)
    [ "$mode" = rsync ] && [ -d "$BK_DEST/casa" ] && free=$((free + $(bk_du "$BK_DEST/casa")))   # an update replaces the old copy
    kind=$([ "$mode" = rsync ] && echo "$(L "carpeta normal; si ya había una, solo copia lo que ha cambiado" "plain folder; if there already was one, it only copies what changed")" || echo "$(L "un .tar.zst por carpeta" "one .tar.zst per folder")")
    echo "$(L "  Copia: $(hsize "$need") en $BK_DEST ($kind)." "  Copy: $(hsize "$need") in $BK_DEST ($kind).")"
    if [ "$need" -gt "$free" ]; then
        echo "$(L "  ${Y}No cabe: hay $(hsize "$free") libres.${N} Desmarca algo (los juegos ocupan lo que más) o elige otro sitio." "  ${Y}It doesn't fit: only $(hsize "$free") free.${N} Untick something (games take the most) or pick another place.")"
        rm -f "$list"; return 1
    fi
    pgrep -u "$U" -x steam >/dev/null && echo "$(L "  Steam está abierto: mejor ciérralo, para que sus ficheros no cambien mientras se copian." "  Steam is open: better close it, so its files don't change while they are copied.")"
    yesno "$(L "  ¿Hago la copia?" "  Make the copy?")" S || { rm -f "$list"; return 1; }
    mkdir -p "$BK_DEST/sistema" || { rm -f "$list"; return 1; }
    rm -f "$BK_DEST/$BK_INFO"               # until it ends, the copy is not complete
    cp -f "$list" "$BK_DEST/sistema/fuera.txt"
    flatpak list --system --app --columns=application,origin 2>/dev/null >"$BK_DEST/sistema/flatpak-sistema.txt"
    flatpak list --user --app --columns=application,origin 2>/dev/null >"$BK_DEST/sistema/flatpak-usuario.txt"
    [ -f /etc/systemd/system/plugin_loader.service ] && cp -f /etc/systemd/system/plugin_loader.service "$BK_DEST/sistema/"
    if [ "$mode" = rsync ]; then
        ex=$(mktemp); while read -r p; do [ -n "$p" ] && printf '/%s\n' "$(bk_esc "$p")"; done <"$list" >"$ex"
        rsync -aHAX --one-file-system --delete --exclude-from="$ex" --info=progress2 "$HOME"/ "$BK_DEST/casa/" || rc=$?
        if [ "$rc" = 0 ]; then
            echo "$(L "  Comprobando la copia (compara de nuevo con tu carpeta)…" "  Checking the copy (comparing again with your folder)…")"
            n=$(rsync -aHAXn --one-file-system --delete --exclude-from="$ex" --out-format='%n' "$HOME"/ "$BK_DEST/casa/" | grep -vc '/$')
            [ "$n" = 0 ] && echo "$(L "  ${G}✔${N} La copia es igual a tu carpeta." "  ${G}✔${N} The copy matches your folder.")" ||
                echo "$(L "  ${Y}!${N} $n ficheros han cambiado mientras se copiaba (algo estaba abierto); repite la copia para ponerlos al día." "  ${Y}!${N} $n files changed while being copied (something was open); repeat the copy to bring them up to date.")"
        fi
        rm -f "$ex"
    else
        mkdir -p "$BK_DEST/casa"; rm -f "$BK_DEST"/casa/*.tar.zst
        local top=() i
        for i in "${!BK_P[@]}"; do [[ ${BK_P[$i]} == */* ]] || [ "${BK_ON[$i]}" = 0 ] || top+=("${BK_P[$i]}"); done
        { for i in "${!BK_P[@]}"; do [[ ${BK_P[$i]} == */* ]] || printf '%s\t%s\n' "${BK_P[$i]}" "${BK_SZ[$i]}"; done
          printf '_resto\t%s\n' "${BK_REST:-0}"; } >"$BK_DEST/sistema/tamanos.txt"   # unpacked sizes, for the space check
        bk_tar() {                       # bk_tar NAME paths... -> casa/NAME.tar.zst, leaving out what is unmarked
            local name=$1; shift
            local x=(); while read -r p; do [ -n "$p" ] && x+=(--exclude="$p"); done <"$list"
            echo "  → $name"
            tar -C "$HOME" --one-file-system --anchored --no-wildcards "${x[@]}" -I 'zstd -1 -T0' -cf "$BK_DEST/casa/$name.tar.zst" -- "$@" &&
                zstd -tq "$BK_DEST/casa/$name.tar.zst"
        }
        for p in "${top[@]}"; do bk_tar "$(tr '/' '%' <<<"$p")" "$p" || rc=$?; done
        local small=() q
        while IFS= read -r p; do           # loose files, links and the small folders that got no line of their own
            for q in "${BK_P[@]}"; do [ "$q" = "$p" ] && continue 2; done
            small+=("$p")
        done < <(find "$HOME" -mindepth 1 -maxdepth 1 -printf '%P\n')
        [ ${#small[@]} -eq 0 ] || bk_tar _resto "${small[@]}" || rc=$?
    fi
    { echo "fecha=$(date '+%F %T')"; echo "usuario=$U"; echo "uid=$(id -u)"; echo "casa=$HOME"; echo "modo=$mode"
      echo "imagen=${VERSION:-?}"; echo "kernel=$(uname -r)"; echo "toolbox=$TOOLBOX_VERSION"; echo "equipo=$(hostname)"
      echo "tamano=$need"; echo "resultado=$rc"; } >"$BK_DEST/$BK_INFO"
    rm -f "$list"
    if [ "$rc" = 0 ]; then echo "$(L "  ${G}Copia hecha${N} en $BK_DEST. Para recuperarla: opción 20 → recuperar, y esa carpeta." "  ${G}Copy done${N} in $BK_DEST. To restore it: option 20 → restore, and that folder.")"
    else echo "$(L "  ${R}La copia ha terminado con errores (código $rc).${N} Lo que ha fallado sale arriba; repítela." "  ${R}The copy finished with errors (code $rc).${N} What failed is shown above; repeat it.")"; fi
    return "$rc"
}

bk_find() {                              # bk_find PATH -> BK_KIND (copy|home) BK_SRC (the folder) BK_SRC_ROOT (system root, for home)
    local p=$1 h
    if [ -f "$p/$BK_INFO" ]; then BK_KIND=copy BK_SRC=$p; return 0; fi
    if [ -f "$p/ps5-copia-$U/$BK_INFO" ]; then BK_KIND=copy BK_SRC=$p/ps5-copia-$U; return 0; fi
    for h in "$p/var/home/$U" "$p/home/$U" "$p"/ostree/deploy/*/var/home/"$U"; do
        [ -d "$h/.config" ] && { BK_KIND=home BK_SRC=$h BK_SYS=$p; return 0; }
    done
    [ -d "$p/.config" ] && { BK_KIND=home BK_SRC=$p BK_SYS=''; return 0; }
    return 1
}

# --- the other disk: listed, mounted read-only and, if its system needed one, given its USB quirk ----------------
BK_MDEV='' BK_MSUDO=0                    # what bk_mount mounted, to unmount it at the end
bk_disks() {                             # Linux partitions of the other disks: dev, size, fs, label, model, bus, mount point
    lsblk -Jpo NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT,MODEL,TRAN 2>/dev/null | jq -r '
        .blockdevices[] | select([.children[]?.mountpoint // empty | select(test("^/(sysroot|var|boot|efi|var/home)?$"))] | length == 0)
        | . as $d | .children[]? | select((.fstype // "") | test("^(ext4|btrfs|xfs)$"))
        | [.name, .size, .fstype, (.label // "-"), (($d.model // "-") | sub("\\s+$"; "")), ($d.tran // "-"), (.mountpoint // "")] | @tsv'
}
bk_mount() {                             # bk_mount DEV -> BK_MP, mounted read-only (as you with udisks; else with sudo)
    local out
    BK_MP=$(lsblk -no MOUNTPOINT "$1" 2>/dev/null | head -1); [ -n "$BK_MP" ] && return 0
    if out=$(udisksctl mount -b "$1" -o ro --no-user-interaction 2>&1); then
        BK_MP=$(sed -n 's/^Mounted .* at \(.*\)$/\1/p' <<<"$out"); BK_MP=${BK_MP%.}; BK_MDEV=$1 BK_MSUDO=0
    else
        need_sudo || return 1
        BK_MP=/mnt/ps5-origen; sudo mkdir -p "$BK_MP" && sudo mount -o ro "$1" "$BK_MP" || return 1
        BK_MDEV=$1 BK_MSUDO=1
    fi
    echo "$(L "  Montado (solo lectura) en $BK_MP." "  Mounted (read-only) at $BK_MP.")"
}
bk_umount() {
    [ -n "$BK_MDEV" ] || return 0
    if [ "$BK_MSUDO" = 1 ]; then sudo umount "$BK_MP"; else udisksctl unmount -b "$BK_MDEV" --no-user-interaction >/dev/null; fi &&
        echo "$(L "  Desmontado $BK_MDEV." "  Unmounted $BK_MDEV.")"
    BK_MDEV=''
}
bk_usb_quirk() {                         # bk_usb_quirk DEV -> if the drive's own system used it without UAS, the same now
    local dev=$1 disk props vp drv q uuid cur i
    disk=/dev/$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1)
    props=$(udevadm info -q property -n "$disk" 2>/dev/null)
    grep -q '^ID_BUS=usb' <<<"$props" || return 0
    vp=$(sed -n 's/^ID_VENDOR_ID=//p' <<<"$props"):$(sed -n 's/^ID_MODEL_ID=//p' <<<"$props")
    drv=$(sed -n 's/^ID_USB_DRIVER=//p' <<<"$props")
    [ "$drv" = uas ] || return 0         # already without UAS: quirk on, or a plain usb-storage drive
    q=$(sed -n "s/^USB_QUIRK=//p" "$BK_SRC/.config/ps5-bazzite-toolbox.conf" 2>/dev/null | tail -1 | tr -d "'\"")
    [ -n "$q" ] || q=$(quirk_for "$vp") || return 0
    [[ $q == *u* ]] || return 0
    section
    case $TB_LANG in
        es)
    say "Este disco ($vp) va ahora con UAS, y su sistema lo usaba con usb-storage.quirks=$vp:$q: con UAS daba"
    say "errores y atascos, justo lo que no quieres en una copia larga. Lo pongo para este disco hasta que reinicies"
    say "(no cambia el arranque de nadie) y lo vuelves a enchufar." ;;
        *)
    say "This disk ($vp) now runs with UAS, and its system used it with usb-storage.quirks=$vp:$q: with UAS it gave"
    say "errors and stalls, exactly what you don't want in a long copy. I set it for this disk until you reboot"
    say "(it doesn't change anyone's boot) and you plug it in again." ;;
    esac
    yesno "$(L "¿Lo pongo?" "Set it?")" S || return 0
    need_sudo || return 1
    uuid=$(lsblk -no UUID "$dev" 2>/dev/null)
    bk_umount
    cur=$(cat /sys/module/usb_storage/parameters/quirks 2>/dev/null)
    [[ ,$cur, == *",$vp:"* ]] || printf '%s' "${cur:+$cur,}$vp:$q" | sudo tee /sys/module/usb_storage/parameters/quirks >/dev/null || return 1
    read -rp "$(L "  Desenchufa el disco, vuelve a enchufarlo y pulsa Intro… " "  Unplug the disk, plug it in again and press Enter… ")" _
    for i in $(seq 60); do
        dev=$(lsblk -rnpo NAME,UUID 2>/dev/null | awk -v u="$uuid" '$2 == u { print $1; exit }'); [ -n "$dev" ] && break; sleep 1
    done
    [ -n "$dev" ] || { echo "$(L "  No vuelve a aparecer el disco." "  The disk does not show up again.")"; return 1; }
    disk=/dev/$(lsblk -no PKNAME "$dev" | head -1)
    drv=$(udevadm info -q property -n "$disk" 2>/dev/null | sed -n 's/^ID_USB_DRIVER=//p')
    [ "$drv" = usb-storage ] && echo "$(L "  ${G}✔${N} Ahora va sin UAS." "  ${G}✔${N} Now it runs without UAS.")" || echo "$(L "  ${Y}!${N} Sigue con $drv: puede dar errores." "  ${Y}!${N} Still on $drv: it may give errors.")"
    BK_DEV=$dev
}

bk_restore() {                           # bk_restore [DIR] -> picks where from (a copy, another disk), then bk_restore_do
    local a=${1:-} c=() d n rc
    BK_DEV=''
    if [ -z "$a" ]; then
        echo
        echo "${B}$(L "Recuperar tu carpeta personal" "Restore your home folder")${N}$(L ": ¿de dónde?" ": from where?")"
        while read -r d; do [ -n "$d" ] && c+=("copy	${d%/*}"); done < <(timeout 20 find /run/media/"$U" /var/mnt /mnt -maxdepth 3 -name "$BK_INFO" 2>/dev/null)
        while IFS=$'\t' read -r d n; do [ -n "$d" ] && c+=("disk	$d	$n"); done < <(bk_disks | awk -F'\t' -v on="$(L ' en ' ' at ')" -v um="$(L ', sin montar' ', not mounted')" '{ print $1 "\t" $2 " " $3 " «" $4 "» " $5 " (" $6 ")" ($7 ? on $7 : um) }')
        for n in "${!c[@]}"; do
            IFS=$'\t' read -r d a rc <<<"${c[$n]}"
            if [ "$d" = copy ]; then printf "$(L '  %d) copia en %s (%s)\n' '  %d) copy in %s (%s)\n')" $((n + 1)) "$a" "$(sed -n 's/^fecha=//p' "$a/$BK_INFO")"
            else printf "$(L '  %d) disco %s %s [EN PRUEBAS]\n' '  %d) disk %s %s [EXPERIMENTAL]\n')" $((n + 1)) "$a" "$rc"; fi
        done
        [ ${#c[@]} -gt 0 ] || echo "$(L "  (no encuentro copias ni otros discos Linux enchufados)" "  (I find no copies or other Linux disks plugged in)")"
        read -e -rp "$(L "  Número, o escribe una carpeta (Intro = cancelar): " "  Number, or type a folder (Enter = cancel): ")" a
        [ -n "$a" ] || return 1
        if [[ $a =~ ^[0-9]+$ ]] && [ -n "${c[$((a - 1))]:-}" ]; then
            IFS=$'\t' read -r d a _ <<<"${c[$((a - 1))]}"
            if [ "$d" = disk ]; then
                BK_DEV=$a; bk_mount "$a" || return 1
                bk_find "$BK_MP" && bk_usb_quirk "$BK_DEV"
                [ -n "$BK_MDEV" ] || { bk_mount "$BK_DEV" || return 1; }   # unmounted for the quirk: again
                a=$BK_MP
            fi
        fi
    fi
    bk_restore_do "$a"; rc=$?
    bk_umount
    return $rc
}

bk_restore_do() {
    local a p list rc=0 n mode
    echo
    echo "${B}$(L "Recuperar tu carpeta personal" "Restore your home folder")${N}"
    section
    case $TB_LANG in
        es)
    say "Trae a $BK_TO lo que elijas de una copia (opción 20 → guardar) o de la carpeta personal de otro disco"
    say "(p. ej. el de tu instalación anterior, enchufado ahora). Sobrescribe los ficheros que se llamen igual; lo"
    say "demás de tu carpeta se queda. Después ofrece reinstalar Decky y los Flatpaks del sistema y aplicar tus ajustes."
    say "POR QUÉ: para tener en esta instalación tus juegos, partidas y ajustes como estaban."
    say "DESHACER: no se deshace solo; si dudas, haz antes una copia de esta carpeta." ;;
        *)
    say "Brings to $BK_TO what you pick from a copy (option 20 → save) or from another disk's home folder"
    say "(e.g. your previous install's, plugged in now). It overwrites files with the same name; the rest of"
    say "your folder stays. Afterwards it offers to reinstall Decky and the system Flatpaks and to apply your settings."
    say "WHY: to have your games, saves and settings in this install as they were."
    say "UNDO: it can't be undone by itself; if in doubt, make a copy of this folder first." ;;
    esac
    a=${1/#\~/$HOME}; a=${a%/}
    bk_find "$a" || { echo "$(L "  Ahí no hay una copia ($BK_INFO) ni una carpeta personal de $U." "  There is no copy ($BK_INFO) nor a home folder of $U there.")"; return 1; }
    p=$(realpath "$BK_SRC")
    [ "$p" != "$(realpath "$BK_TO")" ] || { echo "$(L "  Esa es la carpeta en la que estás." "  That is the folder you are in.")"; return 1; }
    if [ "$BK_KIND" = copy ]; then
        mode=$(sed -n 's/^modo=//p' "$BK_SRC/$BK_INFO")
        echo "$(L "  Copia del $(sed -n 's/^fecha=//p' "$BK_SRC/$BK_INFO") ($(sed -n 's/^equipo=//p' "$BK_SRC/$BK_INFO"), imagen v$(sed -n 's/^imagen=//p' "$BK_SRC/$BK_INFO"), $mode)." "  Copy from $(sed -n 's/^fecha=//p' "$BK_SRC/$BK_INFO") ($(sed -n 's/^equipo=//p' "$BK_SRC/$BK_INFO"), image v$(sed -n 's/^imagen=//p' "$BK_SRC/$BK_INFO"), $mode).")"
        [ "$(sed -n 's/^resultado=//p' "$BK_SRC/$BK_INFO")" = 0 ] || echo "$(L "  ${Y}!${N} Esa copia terminó con errores: puede faltar algo." "  ${Y}!${N} That copy ended with errors: something may be missing.")"
        a=$(sed -n 's/^usuario=//p' "$BK_SRC/$BK_INFO")
    else
        mode=rsync; a=$(stat -c %U "$BK_SRC" 2>/dev/null)
        echo "$(L "  Carpeta personal de otra instalación: $BK_SRC" "  Home folder of another install: $BK_SRC")"
    fi
    p=$(sed -n 's/^casa=//p' "$BK_SRC/$BK_INFO" 2>/dev/null)
    if [ -n "$p" ] && [ "$p" != "$HOME" ]; then
        echo "$(L "  ${Y}!${N} Era de $p y ahora estás en $HOME: los enlaces y ajustes con la ruta" "  ${Y}!${N} It was from $p and now you are in $HOME: links and settings with the old")"
        echo "$(L "    vieja no funcionarán. Lo normal es usar el mismo nombre de usuario en la instalación nueva." "    path won't work. Normally you use the same username on the new install.")"
        yesno "$(L "  ¿Seguir igualmente?" "  Continue anyway?")" N || return 1
    fi
    if [ "$mode" = tar ]; then           # a copy in .tar.zst: one line per saved folder
        BK_P=() BK_ON=() BK_SZ=() BK_DS=() BK_REST=0 BK_SMALL=0
        for p in "$BK_SRC"/casa/*.tar.zst; do
            [ -f "$p" ] || continue; p=${p##*/}; p=${p%.tar.zst}
            local sz; sz=$(awk -F'\t' -v p="$(tr '%' '/' <<<"$p")" '$1 == p { print $2 }' "$BK_SRC/sistema/tamanos.txt" 2>/dev/null)
            BK_P+=("$(tr '%' '/' <<<"$p")") BK_ON+=(1) BK_SZ+=("${sz:-$(stat -c %s "$BK_SRC/casa/$p.tar.zst")}")
            if [ "$p" = _resto ]; then BK_DS+=("$(L "carpetas pequeñas y ficheros sueltos" "small folders and loose files")"); else BK_DS+=(""); fi
        done
        bk_pick "$BK_SRC" "$(L "Qué se recupera" "What to restore")" || return 1
    else
        local root=$BK_SRC; [ "$BK_KIND" = copy ] && root=$BK_SRC/casa
        bk_scan "$root"
        bk_pick "$root" "$(L "Qué se recupera" "What to restore")" || return 1
    fi
    n=$(bk_total); a=$(df -B1 --output=avail "$BK_TO" | tail -1)
    [ "$n" -lt "$a" ] || { echo "$(L "  ${Y}No cabe:${N} hacen falta $(hsize "$n") y hay $(hsize "$a") libres." "  ${Y}It doesn't fit:${N} $(hsize "$n") needed and only $(hsize "$a") free.")"; return 1; }
    if pgrep -u "$U" -x steam >/dev/null; then
        echo "$(L "  Steam está abierto: hay que cerrarlo, o reescribirá sus ficheros al salir." "  Steam is open: it must be closed, or it will rewrite its files on exit.")"
        yesno "$(L "  ¿Lo cierro?" "  Close it?")" S && { steam -shutdown >/dev/null 2>&1 & sleep 10; pkill -u "$U" -x steam; }
    fi
    [ -z "${SSH_CONNECTION:-}" ] && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] &&
        echo "$(L "  Ojo: lo lanzas desde la sesión gráfica. KDE puede volver a guardar algunos de sus ajustes al cerrar sesión; si" "  Careful: you are running it from the graphical session. KDE may save some of its settings again when logging out; if")"
    [ -z "${SSH_CONNECTION:-}" ] && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] &&
        echo "$(L "  quieres que queden exactamente los de la copia, hazlo por SSH o en una consola de texto (Ctrl+Alt+F3)." "  you want exactly the copy's, do it over SSH or in a text console (Ctrl+Alt+F3).")"
    echo "$(L "  Se recuperan $(hsize "$n") en $BK_TO." "  Restoring $(hsize "$n") into $BK_TO.")"
    yesno "$(L "  ¿Sigo?" "  Continue?")" S || return 1
    list=$(mktemp); bk_excluded >"$list"
    if [ "$mode" = tar ]; then
        for n in "${!BK_P[@]}"; do
            [ "${BK_ON[$n]}" = 1 ] || continue
            echo "  ← ${BK_P[$n]}"
            tar -C "$BK_TO" -I zstd -xf "$BK_SRC/casa/$(tr '/' '%' <<<"${BK_P[$n]}").tar.zst" || rc=$?
        done
    else
        local ex; ex=$(mktemp); while read -r p; do [ -n "$p" ] && printf '/%s\n' "$(bk_esc "$p")"; done <"$list" >"$ex"
        rsync -aHAX --one-file-system --exclude-from="$ex" --info=progress2 "$root"/ "$BK_TO"/ || rc=$?
        rm -f "$ex"
    fi
    rm -f "$list"
    [ "$rc" = 0 ] && echo "$(L "  ${G}✔${N} Recuperado." "  ${G}✔${N} Restored.")" || echo "$(L "  ${R}✘${N} Ha habido errores (código $rc): salen arriba." "  ${R}✘${N} There were errors (code $rc): shown above.")"
    if command -v selinuxenabled >/dev/null && selinuxenabled && yesno "$(L "  ¿Repongo las etiquetas de SELinux de lo recuperado (restorecon)?" "  Reset the SELinux labels of what was restored (restorecon)?")" S && need_sudo; then
        sudo restorecon -RF "$BK_TO"
    fi
    bk_restore_system
    p=$(bk_links "$BK_TO" | while IFS=$'\t' read -r l t; do [ -e "$BK_TO/$l" ] || echo "$l -> $t"; done | head -20)
    [ -z "$p" ] || { echo "$(L "  Estos enlaces apuntan a sitios que ahora no están (el NAS sin montar, otro disco):" "  These links point to places that are not there now (NAS not mounted, another disk):")"; sed 's/^/    /' <<<"$p"
                     echo "$(L "  Los del NAS funcionan en cuanto se monte: bloque nas de los ajustes (opción 16 → nas)." "  The NAS ones work as soon as it is mounted: nas block of the settings (option 16 → nas).")"; }
    if yesno "$(L "  ¿Aplico ahora tus ajustes guardados (la opción 15, uno a uno, preguntando)?" "  Apply your saved settings now (option 15, one by one, asking)?")" S; then
        # shellcheck disable=SC1090
        need_sudo && { . "$CONF"; STATUS_ONLY=0 ALL=0 ONLY=''; setup_run; }
    fi
    echo "$(L "  Reinicia la consola (o al menos la sesión) para que todo lea lo recuperado." "  Reboot the console (or at least the session) so everything reads what was restored.")"
    return "$rc"
}

bk_restore_system() {                    # Decky's service and the system Flatpaks, from the copy or the other disk
    local svc='' fl='' miss a
    if [ "$BK_KIND" = copy ]; then
        [ -f "$BK_SRC/sistema/plugin_loader.service" ] && svc=$BK_SRC/sistema/plugin_loader.service
        [ -s "$BK_SRC/sistema/flatpak-sistema.txt" ] && fl=$(cut -f1 "$BK_SRC/sistema/flatpak-sistema.txt")
    elif [ -n "${BK_SYS:-}" ]; then
        [ -f "$BK_SYS/etc/systemd/system/plugin_loader.service" ] && svc=$BK_SYS/etc/systemd/system/plugin_loader.service
        fl=$(for a in "$BK_SYS"/var/lib/flatpak/app/*.* "$BK_SYS"/ostree/deploy/*/var/lib/flatpak/app/*.*; do [ -d "$a" ] && echo "${a##*/}"; done)
    fi
    if [ -n "$svc" ] && [ -d "$BK_TO/homebrew/services" ] && ! systemctl is-enabled -q plugin_loader 2>/dev/null; then
        echo "$(L "  Decky: sus plugins ya están en ~/homebrew, pero falta el servicio que lo arranca con Steam." "  Decky: its plugins are already in ~/homebrew, but the service that starts it with Steam is missing.")"
        if yesno "$(L "  ¿Instalo el servicio de Decky (/etc/systemd/system/plugin_loader.service)?" "  Install Decky's service (/etc/systemd/system/plugin_loader.service)?")" S && need_sudo; then
            sudo cp "$svc" /etc/systemd/system/plugin_loader.service && sudo systemctl daemon-reload &&
                sudo systemctl enable --now plugin_loader && echo "$(L "  ${G}✔${N} Decky activo (sale en Steam al reiniciarlo)." "  ${G}✔${N} Decky active (it shows up in Steam after restarting it).")"
        fi
    fi
    miss=$(for a in $fl; do flatpak info --system "$a" >/dev/null 2>&1 || echo "$a"; done)
    if [ -n "$miss" ]; then
        echo "$(L "  Flatpaks del sistema que tenías y aquí faltan: $(echo $miss)" "  System Flatpaks you had that are missing here: $(echo $miss)")"
        if yesno "$(L "  ¿Los instalo desde Flathub (hace falta red)?" "  Install them from Flathub (network needed)?")" S && need_sudo; then
            # shellcheck disable=SC2086
            sudo flatpak install --system -y --noninteractive flathub $miss
        fi
    fi
}

bk_menu() {
    local c
    echo "$(L "  1) Guardar una copia de tu carpeta personal (en otro disco, el NAS o una carpeta)" "  1) Save a copy of your home folder (to another disk, the NAS or a folder)")"
    echo "$(L "  2) Recuperar una copia, o la carpeta personal de otra instalación (otro disco enchufado)" "  2) Restore a copy, or the home folder of another install (another disk plugged in)")"
    read -rp "$(L "Elige (0 = cancelar): " "Choose (0 = cancel): ")" c
    case $c in 1) bk_save ;; 2) bk_restore ;; esac
}

# --- menu ----------------------------------------------------------------------------------------------------
menu() {
    local c a notice_done=''
    while :; do
        printf "$(L '\n%sPS5 Bazzite Deck — caja de herramientas v%s%s (imagen %s%s, kernel %s)\n' '\n%sPS5 Bazzite Deck — toolbox v%s%s (image %s%s, kernel %s)\n')" \
            "$B" "$TOOLBOX_VERSION" "$N" "${VERSION:+v$VERSION}" "$([ $IS_BOOTC = 1 ] && echo ' bootc')" "$(uname -r)"
        [ -n "$notice_done" ] || { offer_install; toolbox_notice; notice_done=1; }
        case $TB_LANG in
            es) cat <<'MENU'
 Diagnóstico (solo mira, no cambia nada)
   1) Revisión completa de este arranque (y guarda el informe)
   2) Revisar el arranque anterior (tras un cuelgue o un apagado forzado)
   3) Vigilar el kernel en directo (mientras juegas o copias ficheros; Ctrl+C vuelve aquí)
   4) Vigilar en directo: CPU, GPU, VRAM, RAM, swap, temperatura y qué gasta más (Ctrl+C vuelve aquí)
 Pantalla y sesión gráfica
   5) Ver en qué modo arranca la consola y qué sesión hay ahora
   6) Pantalla en negro: recuperar la imagen (cambia de consola y vuelve; no cierra nada)
   7) Pantalla en negro que no se arregla con el 6: reiniciar la sesión (cierra Steam y lo abierto)
   8) Pasar al escritorio KDE ahora y arrancar siempre en él (cierra lo abierto)
   9) Pasar al modo juego ahora y arrancar siempre en él (cierra lo abierto)
 PortProton y Steam
  10) Instalar un juego de Windows: elige su aislamiento, pruébalo y, si va bien, a Steam y a la colección
  11) Mis juegos: aislamiento, generación de fotogramas, o desinstalarlos (de Steam, PortProton y el disco)
  12) Sincronizar la colección «PortProton» de Steam (cierra Steam si está abierto)
 Utilidades
  13) Ver lo que ocupa cada carpeta (también: comando «espacio», o botón derecho en Dolphin)
 Ajustes de la consola (cambian el sistema; cada uno explica y pregunta)
  14) Ver qué ajustes están aplicados
  15) Aplicar los ajustes pendientes, uno a uno
  16) Revisar o cambiar ajustes concretos (VRAM, idioma, NAS…; también los que dijiste que no)
 Sistema
  17) Imagen: instalar otra versión de GitHub (más nueva o anterior), o volver a como estaba antes de actualizar
  18) Actualizar esta caja de herramientas (muestra las novedades y pregunta)
  19) Instalarla como comando «ps5-bazzite-toolbox» y en el menú de aplicaciones, o desinstalarla
  20) Copia de seguridad de tu carpeta personal: guardar (eligiendo qué) o recuperar, también de otro disco
   0) Salir
MENU
                ;;
            *) cat <<'MENU'
 Diagnostics (look only, change nothing)
   1) Full check of this boot (and save the report)
   2) Check the previous boot (after a hang or a forced shutdown)
   3) Watch the kernel live (while you play or copy files; Ctrl+C returns here)
   4) Watch live: CPU, GPU, VRAM, RAM, swap, temperature and what uses the most (Ctrl+C returns here)
 Screen and graphical session
   5) See which mode the console boots into and which session is running now
   6) Black screen: recover the picture (switches console and back; closes nothing)
   7) Black screen that 6 doesn't fix: restart the session (closes Steam and what is open)
   8) Switch to the KDE desktop now and always boot into it (closes what is open)
   9) Switch to game mode now and always boot into it (closes what is open)
 PortProton and Steam
  10) Install a Windows game: pick its isolation, test it and, if it works, add it to Steam and the collection
  11) My games: isolation, frame generation, or uninstall them (from Steam, PortProton and the disk)
  12) Sync the Steam «PortProton» collection (closes Steam if it is open)
 Utilities
  13) See how much each folder takes (also: «espacio» command, or right-click in Dolphin)
 Console settings (they change the system; each one explains and asks)
  14) See which settings are applied
  15) Apply the pending settings, one by one
  16) Review or change specific settings (VRAM, language, NAS…; also those you said no to)
 System
  17) Image: install another version from GitHub (newer or older), or go back to how it was before updating
  18) Update this toolbox (shows what's new and asks)
  19) Install it as the «ps5-bazzite-toolbox» command and in the applications menu, or uninstall it
  20) Backup of your home folder: save (choosing what) or restore, also from another disk
   0) Quit
MENU
                ;;
        esac
        read -rp "$(L "Elige: " "Choose: ")" c
        case $c in [1-9]|1[4-7]) need_sudo || continue ;; esac       # 10-13, 18 and 19 don't need it
        case $c in
            1) BOOT=0; run_checks ;;
            2) BOOT=-1; run_checks ;;
            3) trap ':' INT; watch_kernel; trap - INT ;;
            4) mem_watch ;;
            5) session_status ;;
            6) screen_kick ;;
            7|8|9) read -rp "$(L "Se cerrará Steam y todo lo abierto en pantalla. ¿Seguir? [s/N] " "Steam and everything open on screen will be closed. Continue? [y/N] ")" a
                   [[ $a == [sSyY]* ]] || continue
                   case $c in 7) session restart ;; 8) session desktop ;; 9) session gamemode ;; esac ;;
            10) pp_add_game ;;
            11) pp_my_games ;;
            12) pp_collection ;;
            13) read -e -rp "$(L "Carpeta (Intro = $HOME): " "Folder (Enter = $HOME): ")" a; space_report "${a:-$HOME}" ;;
            14) STATUS_ONLY=1 ALL=0 ONLY=''; setup_run; STATUS_ONLY=0 ;;
            15) STATUS_ONLY=0 ALL=0 ONLY=''; setup_run ;;
            16) echo "$(L "Ajustes: $BLOCKS" "Settings: $BLOCKS")"
                read -rp "$(L "¿Cuáles? (separados por espacios o comas): " "Which ones? (separated by spaces or commas): ")" a
                [ -n "$a" ] && { STATUS_ONLY=0 ALL=0 ONLY=${a//,/ }; setup_run; ONLY=''; } ;;
            17) img_menu ;;
            18) self_update && { echo "$(L "Saliendo para que abras la versión nueva." "Exiting so you can open the new version.")"; return 0; } ;;
            20) bk_menu ;;
            19) if [ "$TOOLBOX_SELF" = "$TOOLBOX_BIN" ]; then uninstall_self && return 0; else install_self; fi ;;
            0|q|'') return 0 ;;
            *) echo "$(L "Opción no válida" "Invalid option")" ;;
        esac
    done
}

case $MODE in                            # these need no root
    add-game) pp_add_game "${ARGS[@]}"; exit ;;
    remove-game) pp_remove_game "${ARGS[@]}"; exit ;;
    run) pp_run_game "${ARGS[@]}"; exit ;;
    change-level) pp_change_level "${ARGS[@]}"; exit ;;
    framegen) pp_framegen "${ARGS[@]}"; exit ;;
    games) pp_my_games; exit ;;
    pp-collection) pp_collection "${ARGS[@]}"; exit ;;
    space) space_report "${ARGS[@]}"; exit ;;
    self-update) self_update "$UPDATE_TAG"; exit ;;
    backup) bk_save; exit ;;
    restore) bk_restore "$UPDATE_TAG"; exit ;;
esac
case $MODE in menu|install|uninstall) ;; *) need_sudo || exit 1 ;; esac   # the menu asks per option
case $MODE in
    menu) menu ;;
    check) run_checks ;;
    watch) watch_kernel ;;
    mem) mem_watch ;;
    session) session "$SESSION_CMD" ;;
    setup) setup_run ;;
    update) update_image "$UPDATE_TAG" ;;
    rollback) img_rollback ;;
    screen) screen_kick ;;
    install) install_self ;;
    uninstall) uninstall_self ;;
esac
