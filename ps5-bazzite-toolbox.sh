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
#    reboot, HDMI fix, disk, firewall, Brave, Edge, NAS, the monitor in a phone's browser, zram swap size, the GPU's 40 compute units). Each explains what it changes, why and how to undo it, and asks.
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
#   bash ps5-bazzite-toolbox.sh --run Juego.exe          # start a game as --add-game left it (isolated or not); asks nothing
#   bash ps5-bazzite-toolbox.sh --pp-collection [--dry-run|--yes]   # sync Steam's "PortProton" collection
#   bash ps5-bazzite-toolbox.sh --space [DIR]           # space taken by each folder in DIR (also the "espacio" command)
#   bash ps5-bazzite-toolbox.sh --self-update [v1.1.0]  # update this toolbox from its GitHub releases
#   bash ps5-bazzite-toolbox.sh --backup                # save your home folder (or what you pick) to another disk, the NAS, a folder
#   bash ps5-bazzite-toolbox.sh --restore [DIR]         # bring a copy back, or another install's home folder (another disk)
#   bash ps5-bazzite-toolbox.sh --install | --uninstall # command ~/.local/bin/ps5-bazzite-toolbox + applications menu
#   bash ps5-bazzite-toolbox.sh --version
# Setup blocks: locale cmdline wifi updates vram gpu40 zram fans warmreboot hdmi bt disk firewall brave edge nas bios media esde portproton atajos monitorweb
set -uo pipefail

TOOLBOX_VERSION=1.9.0                    # bump on every release (see CHANGELOG.md and release.sh)
TOOLBOX_REPO=fitamix/ps5-bazzite-toolbox
TOOLBOX_BIN=$HOME/.local/bin/ps5-bazzite-toolbox                      # where --install puts it
TOOLBOX_DESKTOP=$HOME/.local/share/applications/ps5-bazzite-toolbox.desktop

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
        -V|--version) echo "ps5-bazzite-toolbox $TOOLBOX_VERSION"; exit 0 ;;
        --add-game|--remove-game|--change-level|--games|--run|--pp-collection|--space)       # the rest of the line goes to that tool
                  MODE=${1#--}; shift; ARGS=("$@"); break ;;
        -h|--help) awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
done
if [ -z "$MODE" ]; then if [ -t 0 ]; then MODE=menu; else MODE=check; fi; fi

[ "$(id -u)" != 0 ] || { echo "Ejecútalo con tu usuario, no como root (pedirá sudo cuando haga falta)." >&2; exit 1; }
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
        read -e -rp "¿Guardar $what? Intro = en $dest, escribe otra carpeta, o n = no: " a
        case $a in
            [nN]|[nN][oO]) rm -f "$tmp"; echo "No lo guardo."; return 1 ;;
            '') ;;
            *) dest=${a/#\~/$HOME} ;;
        esac
    fi
    if mkdir -p "$dest" 2>/dev/null && mv "$tmp" "$dest/$name"; then SAVED=$dest/$name; echo "Guardado: $SAVED"
    else echo "No puedo guardarlo en $dest; se queda en $tmp (se borra al apagar)." >&2; return 1; fi
}
# sudo is asked for only when an option needs it (the journal, /efi, polkit's rules, SDDM, systemd, /etc), once:
# a background loop then keeps it valid until the toolbox closes (Fedora forgets it after 5 minutes).
SUDO_KEEP=''
need_sudo() {
    [ -n "$SUDO_KEEP" ] && kill -0 "$SUDO_KEEP" 2>/dev/null && return 0
    if ! sudo -n true 2>/dev/null; then
        echo "Esto necesita permisos de administrador: te pido la contraseña de sudo una vez, hasta que cierres la caja de herramientas."
        sudo -v || { echo "Sin sudo no puedo hacerlo." >&2; return 1; }
    fi
    ( trap '' INT; while kill -0 $$ 2>/dev/null && sudo -n -v 2>/dev/null; do sleep 60; done ) &   # Ctrl+C mustn't stop it
    SUDO_KEEP=$!
    trap '[ -z "$SUDO_KEEP" ] || kill "$SUDO_KEEP" 2>/dev/null' EXIT
}

CONF=$HOME/.config/ps5-bazzite-toolbox.conf
OLD_CONF=$HOME/.config/ps5-bazzite-postinstall.conf      # its name before v1.0.0
CMDLINE=/efi/cmdline.txt
VRAMTXT=/efi/vram.txt
PERFCONF=/etc/ps5-bazzite-deck/perf.conf
TOOLS_REPO=https://github.com/ps5-linux/ps5-linux-tools
TOOLS_COMMIT=f1fa98a                     # the revision reviewed on 2026-10-27
POLKIT_RULE=/etc/polkit-1/rules.d/50-ps5-no-kde-smart.rules
MONWEB_PORT=${MONWEB_PORT:-8765}
MONWEB_PY=$HOME/.local/share/ps5-bazzite-toolbox/monitor-web.py
MONWEB_UNIT=$HOME/.config/systemd/user/ps5-monitor-web.service
BRAVE_FLAGS=$HOME/.var/app/com.brave.Browser/config/brave-flags.conf
EDGE_FLAGS=$HOME/.var/app/com.microsoft.Edge/config/edge-flags.conf
BLOCKS="locale cmdline wifi updates vram gpu40 zram fans warmreboot hdmi bt disk firewall brave edge nas bios media esde portproton atajos monitorweb"

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
    if [ "$d" = S ]; then read -rp "$1 [S/n] " a </dev/tty; [[ $a != [nN]* ]]
    else read -rp "$1 [s/N] " a </dev/tty; [[ $a == [sS]* ]]; fi
}
value() {                                # value VAR "question" default -> asks, keeps the answer
    local cur=${!1:-$3} a
    if [ $ALL = 1 ]; then a=$cur; else read -rp "  $2 [$cur]: " a </dev/tty; a=${a:-$cur}; fi
    [ "$a" = - ] && a=                   # "-" = empty
    remember "$1" "$a"
}
say() { printf '  %s\n' "$@"; }
section() { printf '\n  QUÉ HACE:\n'; }

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
usb_errors() { journalctl -b -k --no-pager 2>/dev/null | grep -cE 'uas_eh_abort|timing out command|reset (SuperSpeed|high-speed).*USB device'; }
warm_on() { command -v ps5-warm-reboot >/dev/null && ps5-warm-reboot status 2>/dev/null | grep >/dev/null ': on'; }
REBOOT=0 COLD=0

# Each block: desc_X (what, why, undo), check_X (0 done, 1 pending, 2 not applicable), apply_X.

# --- locale --------------------------------------------------------------------------------------
LANG_WANT=${SYS_LANG:-es_ES.UTF-8} KEYMAP_WANT=${SYS_KEYMAP:-es} TZ_WANT=${SYS_TZ:-Europe/Madrid}
desc_locale() {
    section
    say "Idioma del sistema, teclado (consola y escritorio) y zona horaria, con hora por NTP."
    say "Ahora: $(localectl status 2>/dev/null | sed -n 's/.*LANG=//p' | head -1), teclado $(localectl status 2>/dev/null | sed -n 's/.*VC Keymap: //p'), $(timedatectl show -p Timezone --value)"
    say "POR QUÉ: la imagen viene en inglés, con teclado US y hora UTC."
    say "DESHACER: vuelve a ejecutar el bloque con otros valores."
    say "Steam tiene su propio idioma y zona horaria: cámbialos también en sus ajustes."
}
check_locale() {
    local l; l=$(localectl status 2>/dev/null)
    grep -q "LANG=$LANG_WANT" <<<"$l" && grep -q "VC Keymap: $KEYMAP_WANT\$" <<<"$l" &&
        [ "$(timedatectl show -p Timezone --value)" = "$TZ_WANT" ]
}
apply_locale() {
    value SYS_LANG "Idioma (p. ej. es_ES.UTF-8, en_US.UTF-8)" "$LANG_WANT"
    value SYS_KEYMAP "Teclado (p. ej. es, us, latam)" "$KEYMAP_WANT"
    value SYS_TZ "Zona horaria (p. ej. Europe/Madrid, America/Mexico_City)" "$TZ_WANT"
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
    say "Añade parámetros de arranque a $CMDLINE (con copia previa en $CMDLINE.bak-FECHA):"
    say "- locale.LANG / vconsole.keymap: idioma y teclado ya desde el arranque, no solo en el escritorio."
    if [ -n "$u" ]; then
        say "- Disco de arranque por USB: ${u%% *} (driver ${u#* }), $(usb_errors) errores USB en este arranque."
        say "  usb-storage.quirks=${u%% *}:LETRAS cambia cómo se le habla: u = sin UAS (algunos adaptadores"
        say "  USB-NVMe dan errores y resets con UAS), m = transferencias de 32 KB. Recomendado: ${q:-ninguno}."
    fi
    ver_ge 1.5.0 && say "- Quita module_blacklist=moal si está: desde la v1.5.0 el Wi-Fi IW620 ya no se cuelga."
    say "POR QUÉ: consola en tu idioma y un disco USB estable."
    say "DESHACER: copia un $CMDLINE.bak-* sobre $CMDLINE (con sudo)."
    say "Cuenta a partir del siguiente arranque."
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
        value USB_QUIRK "Letras para usb-storage.quirks (u, um, o - para ninguna)" "${q:-}"
    fi
    sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
    cmd_set locale.LANG "$LANG_WANT" && cmd_set vconsole.keymap "$KEYMAP_WANT" || return 1
    if [ -n "$u" ] && [ -n "${USB_QUIRK:-}" ]; then cmd_set usb-storage.quirks "${u%% *}:$USB_QUIRK" || return 1; fi
    ver_ge 1.5.0 && sudo sed -i 's| module_blacklist=moal||' "$CMDLINE"
    say "Ahora: $(sudo cat "$CMDLINE")"
    REBOOT=1
}

# --- wifi ----------------------------------------------------------------------------------------
NOWIFI=/etc/NetworkManager/conf.d/99-ps5-no-wifi.conf
wifi_blocked() { grep -qs 'unmanaged-devices=type:wifi' "$NOWIFI"; }
desc_wifi() {
    section
    if ver_ge 1.5.0; then
        say "Vuelve a activar el Wi-Fi: borra $NOWIFI y desenmascara wpa_supplicant."
        say "POR QUÉ: en imágenes anteriores a la v1.5.0 el driver moal (IW620) se colgaba con el Wi-Fi"
        say "activo y había que apagarlo. Desde la v1.5.0 funciona (probado: 1 GB a ~54 MB/s, sin cuelgues)."
        say "Si vas solo por cable puedes dejarlo apagado (responde no)."
    else
        say "Apaga el Wi-Fi sin bloquear el driver moal, que también lleva el Bluetooth: NetworkManager"
        say "ignora la interfaz Wi-Fi y wpa_supplicant queda enmascarado."
        say "POR QUÉ: con esta versión ($VERSION) el driver moal se cuelga con el Wi-Fi activo"
        say "(woal_set_get_tx_power, procesos en estado D). Usa cable, o actualiza a la v1.5.0 o posterior."
    fi
    say "DESHACER: vuelve a ejecutar el bloque tras cambiar de versión, o borra/crea $NOWIFI a mano."
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
    say "Desactiva las actualizaciones automáticas (uupd, rpm-ostree) e impide que dnf actualice el kernel,"
    say "Mesa, linux-firmware o gamescope (/etc/dnf/libdnf5.conf.d/90-ps5-hold.conf)."
    say "POR QUÉ: la imagen no es ostree (ujust update y rpm-ostree no sirven) y esos paquetes llevan"
    say "parches para la PS5: un dnf upgrade los sustituiría por los normales y podría no arrancar."
    say "Las actualizaciones de la imagen se hacen con su propio update.sh (ver el README del autor)."
    say "En una instalación bootc no aplica: ahí las actualizaciones son las del autor (opción 17) y se deshacen."
    say "DESHACER: sudo systemctl unmask uupd.timer rpm-ostreed-automatic.timer; borra 90-ps5-hold.conf."
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
    say "Memoria de vídeo que el cargador reserva para la gráfica (${VRAMTXT}, hexadecimal)."
    say "Ahora: ${cur:-sin fichero}${cur:+ ($(vram_gb "$cur"); Linux con $(vram_left "$cur") de RAM)}."
    say "La PS5 tiene 16 GB compartidos: lo que va a la gráfica lo pierde Linux. Puedes poner cualquier cantidad"
    say "entre $(vram_gb $VRAM_MIN) y $(vram_gb $VRAM_MAX) (en pasos de 256 MB); recomendado 4 GB."
    say "POR QUÉ: con 512 MB (lo que pone el cargador) los juegos DirectX 12 / Unreal Engine 5 se caen a los"
    say "pocos segundos ('radv/amdgpu: Not enough memory for command submission', VK_ERROR_DEVICE_LOST) y en el"
    say "modo juego la gráfica se reinicia. Con 4 GB funcionan y a Linux le quedan ~10,6 GB. Más de 6 GB solo"
    say "si un juego se queda corto de VRAM (la gráfica también toma RAM prestada cuando le falta)."
    say "DESHACER: sudo cp $VRAMTXT.orig $VRAMTXT (o elige 512 MB aquí)."
    say "Cuenta solo tras APAGAR y arrancar con el cargador (un reinicio en caliente no la cambia)."
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
            say "$(printf '%-7s' "$(vram_gb "$bytes")") → Linux con $(vram_left "$bytes") de RAM$([ "$g" = 4 ] && echo '   (recomendado)')"
        done
        while :; do
            read -rp "  ¿Cuánta VRAM? (p. ej. 4, 3G, 1536M; Intro = $(vram_gb "$VRAM_WANT")): " c </dev/tty
            bytes=$(vram_parse "${c:-$VRAM_WANT}")
            if [ -z "$bytes" ]; then say "No entiendo «$c»."
            elif [ "$bytes" -lt $VRAM_MIN ] || [ "$bytes" -gt $VRAM_MAX ]; then
                say "Tiene que estar entre $(vram_gb $VRAM_MIN) y $(vram_gb $VRAM_MAX)."
            elif [ $(( bytes % VRAM_STEP )) != 0 ]; then say "Tiene que ser múltiplo de 256 MB (p. ej. 3G, 3.25G, 1536M)."
            else break; fi
        done
    fi
    VRAM_WANT=$(printf '0x%x' "$bytes")
    remember VRAM_SIZE "$VRAM_WANT"
    sudo test -f "$VRAMTXT.orig" || { [ -n "$cur" ] && sudo cp "$VRAMTXT" "$VRAMTXT.orig"; }
    echo "$VRAM_WANT" | sudo tee "$VRAMTXT" >/dev/null || return 1
    say "VRAM: $(vram_gb "$VRAM_WANT") ($VRAM_WANT); Linux tendrá $(vram_left "$VRAM_WANT") de RAM tras el próximo arranque en frío."
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
    say "Las 40 unidades de cálculo (CU) de la GPU en vez de 36 (amdgpu.ps5_cu_unlock=3 en $CMDLINE)."
    say "Ahora: ${now:-?} activas en este arranque; en el próximo, $(gpu_cu_set && echo 40 || echo 36)."
    say "POR QUÉ: Sony apaga 4 de las 40 en fábrica, en parte porque en algunos chips alguna sale defectuosa."
    say "Es la «lotería del silicio»: en muchas consolas las 40 funcionan y la GPU rinde más (~11 % más"
    say "unidades); en otras salen puntitos verdes u otros fallos gráficos, un tinte morado o cuelgues."
    say "Pruébalo con varios juegos exigentes un buen rato; si ves algo de eso, vuelve a 36 aquí mismo."
    say "Solo PS5 original y Slim (en la Pro ya están todas activas). Las actualizaciones de la imagen lo respetan."
    say "DESHACER: vuelve a este bloque (menú 16 → gpu40) y elige 36, o copia un $CMDLINE.bak-* encima."
    say "Cuenta solo tras APAGAR y arrancar con el cargador. Comprobar: sudo dmesg | grep active_cu_number"
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
    say "  40 = desbloquear las 4 unidades extra · 36 = como viene de fábrica"
    while :; do
        read -rp "  ¿Cuántas unidades? (40 o 36, Intro = $def): " c </dev/tty
        c=${c:-$def}
        case $c in 40|36) break ;; *) say "Escribe 40 o 36." ;; esac
    done
    sudo cp "$CMDLINE" "$CMDLINE.bak-$(date +%Y%m%d-%H%M%S)" || return 1
    if [ "$c" = 40 ]; then cmd_set amdgpu.ps5_cu_unlock 3 || return 1
    else sudo sed -i -E 's/ *amdgpu\.ps5_cu_unlock=[0-9]+//' "$CMDLINE" || return 1; fi
    remember GPU_CU "$c"
    say "GPU: $c unidades tras el próximo arranque en frío. Comprueba luego: sudo dmesg | grep active_cu_number"
    COLD=1
}

# --- zram ----------------------------------------------------------------------------------------
# Bazzite's swap is zram (compressed RAM) of half the RAM; a game that fills it has nowhere left to go.
# A drop-in overrides only the size and leaves Bazzite's own file alone.
ZRAM_DROPIN=/etc/systemd/zram-generator.conf.d/90-ps5-bazzite-toolbox.conf
ZRAM_OLD=/etc/systemd/zram-generator.conf.d/90-ps5-toolbox.conf          # its name before v1.0.0
ZRAM_WANT=${ZRAM_SIZE:-ram}
zram_now() { swapon --show=NAME,SIZE,USED --noheadings 2>/dev/null | awk '$1 ~ /zram/ { print $2 " (usada " $3 ")" }'; }
desc_zram() {
    local now conf
    now=$(zram_now) conf=$(sed -n 's/^zram-size *= *//p' /etc/systemd/zram-generator.conf "$ZRAM_OLD" "$ZRAM_DROPIN" 2>/dev/null | tail -1)
    section
    say "Tamaño de la swap zram: memoria que se comprime dentro de la propia RAM cuando falta."
    say "Ahora: ${now:-sin zram}${conf:+, configurada como zram-size = $conf}."
    say "Propuesta: zram-size = $ZRAM_WANT (toda la RAM de Linux, como SteamOS) en $ZRAM_DROPIN."
    say "POR QUÉ: Bazzite pone la mitad de la RAM. Un juego grande (p. ej. un Unreal Engine 5 con 6 GB de VRAM)"
    say "la llena y a partir de ahí, sin swap libre, el sistema cierra el juego si pide más. Con zstd se comprime"
    say "~2:1: llena del todo ocupa la mitad de su tamaño en RAM y guarda el doble. No reserva nada: solo gasta"
    say "RAM cuando se usa. No se añade swap en el disco USB (los atascos del USB colgarían el sistema)."
    say "DESHACER: sudo rm $ZRAM_DROPIN y reinicia."
    say "Cuenta tras reiniciar (cambiarla en marcha obliga a vaciar la swap en la RAM)."
}
check_zram() {
    [ -x /usr/lib/systemd/system-generators/zram-generator ] || return 2
    grep -qs "^zram-size = $ZRAM_WANT\$" "$ZRAM_DROPIN" "$ZRAM_OLD" || return 1
}
apply_zram() {
    value ZRAM_SIZE "Tamaño (ram = toda la RAM; ram / 2 = lo de Bazzite; o en MB, p. ej. 6144)" "$ZRAM_WANT"
    ZRAM_WANT=${ZRAM_SIZE:-ram}
    sudo mkdir -p "$(dirname "$ZRAM_DROPIN")" &&
        printf '# ps5-bazzite-toolbox (bloque zram): overrides the size in /etc/systemd/zram-generator.conf\n[zram0]\nzram-size = %s\n' \
            "$ZRAM_WANT" | sudo tee "$ZRAM_DROPIN" >/dev/null && sudo rm -f "$ZRAM_OLD" || return 1
    say "zram: $ZRAM_WANT tras el próximo reinicio."
    REBOOT=1
}

# --- fans ----------------------------------------------------------------------------------------
# Two separate knobs: ps5fan (ps5-linux-tools) only switches the console's own fan controller on (servo
# pattern 1 via /dev/icc); how hard it cools is that controller's target temperature (the image's ps5-fan
# driver, /sys/.../target_temp, 80 °C from the factory), which the image's ps5-perf sets from FAN_TARGET.
# So ps5fan and ps5-perf don't fight over the fan: with ps5fan, ps5-perf is kept for the target only
# (CPU_BOOST=0, ps5boost does the boost).
FAN_SYS=/sys/bus/platform/devices/ps5-fan/target_temp
has_perf() { command -v ps5-perf >/dev/null; }
fan_mode() { echo "${FAN_MODE:-$(systemctl is-enabled -q ps5fan.service 2>/dev/null && echo tools || { has_perf && echo perf || echo tools; })}"; }
fan_now() { cat "$FAN_SYS" 2>/dev/null; }
perf_set() {                             # perf_set KEY [VALUE] -> sets (or with no value removes) KEY in perf.conf
    sudo mkdir -p "$(dirname "$PERFCONF")" && sudo touch "$PERFCONF" && sudo sed -i "/^$1=/d" "$PERFCONF" || return 1
    [ $# -lt 2 ] || [ -z "$2" ] || echo "$1=$2" | sudo tee -a "$PERFCONF" >/dev/null
}
desc_fans() {
    section
    say "Ventilador y frecuencia de la CPU. Dos formas de encender el control del ventilador, no a la vez:"
    has_perf && say "- perf: ps5-perf, el que trae la imagen (v1.5.0+): boost de CPU y temperatura objetivo del" \
                    "  ventilador. Nada que instalar y se actualiza con la imagen. Ajustes en $PERFCONF."
    say "- tools: ps5fan y ps5boost de ps5-linux-tools ($TOOLS_REPO, revisión $TOOLS_COMMIT): encienden el"
    say "  control del ventilador de la consola (~45 °C en reposo) y ponen CPU/GPU al máximo. Se compila aquí"
    say "  (instala gcc, make y git con dnf)."
    say "Y en los dos casos, la TEMPERATURA OBJETIVO: el ventilador acelera para no pasar de ella. La de fábrica"
    say "es 80 °C (silencioso, el chip llega a ~80 jugando); 70 °C enfría más con algo más de ruido."
    has_perf && say "  Con tools, ps5-perf solo fija esa temperatura (CPU_BOOST=0: el boost lo hace ps5boost)."
    say "Ahora: $(fan_mode), objetivo $(fan_now || echo '?') °C${FAN_TARGET:+ (elegido: $FAN_TARGET)}."
    say "DESHACER: perf → ps5-perf off; tools → sudo systemctl disable --now ps5fan ps5boost; objetivo → vacío aquí."
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
    [ -z "${FAN_TARGET:-}" ] || [ "$(fan_now)" = "$FAN_TARGET" ]
}
apply_fans() {
    local m; m=$(fan_mode)
    has_perf && value FAN_MODE "¿perf o tools?" "$m"; m=${FAN_MODE:-tools}
    if has_perf && [ -e "$FAN_SYS" ]; then
        local t
        while :; do
            value FAN_TARGET "Temperatura objetivo del ventilador en °C (60-85; '-' = la de fábrica, 80)" "${FAN_TARGET:-80}"
            t=$FAN_TARGET; [ "$t" = 80 ] && { remember FAN_TARGET ''; t=''; }
            [ -z "$t" ] || { [[ $t =~ ^[0-9]+$ ]] && [ "$t" -ge 60 ] && [ "$t" -le 85 ]; } && break
            say "Tiene que ser un número entre 60 y 85."
        done
    fi
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
    say "Objetivo del ventilador ahora: $(fan_now || echo '?') °C."
}

# --- warmreboot ----------------------------------------------------------------------------------
desc_warmreboot() {
    section
    say "Reinicio en caliente (ps5-warm-reboot on): al reiniciar desde Steam, el escritorio o sudo reboot,"
    say "vuelve directo a Linux en ~20 s, sin pasar por el sistema de la PS5 ni el cargador."
    say "Apagar sigue siendo apagar: tras un apagado hace falta el cargador."
    say "POR QUÉ: comodidad. Es experimental: en algunas consolas la imagen sale en negro o corrupta"
    say "(el bloque hdmi lo arregla) y tras actualizar el kernel hay que APAGAR, no reiniciar."
    say "DESHACER: ps5-warm-reboot off."
}
check_warmreboot() {
    command -v ps5-warm-reboot >/dev/null || return 2
    if [ "${WARM_REBOOT:-}" = off ]; then ! warm_on; else warm_on; fi
}
apply_warmreboot() { remember WARM_REBOOT on; ps5-warm-reboot on; }

# --- hdmi ----------------------------------------------------------------------------------------
desc_hdmi() {
    section
    say "Instala ps5-hdmi-kick: en cada arranque, cuando aparece el modo juego, cambia a otra consola"
    say "de texto y vuelve (chvt 2; chvt 1)."
    say "POR QUÉ: tras un reinicio en caliente la salida HDMI a veces se queda en negro aunque todo"
    say "funcione; ese cambio de consola la recupera (es el truco del README del autor)."
    say "Recomendado solo si usas el reinicio en caliente ($(warm_on && echo 'lo tienes activado' || echo 'no lo tienes activado'))."
    say "DESHACER: sudo systemctl disable ps5-hdmi-kick."
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

# --- bt ------------------------------------------------------------------------------------------
# The IW620's Bluetooth can fail its first reset at boot ("hci0: Opcode 0x0c03 failed: -110"): bluetoothd
# then starts with no adapter. The image's ps5-bt-revive only looks for "command ... tx timeout", so it says
# "adapter OK" and nothing happens. ps5-bt-guard checks what matters - does bluetoothd have a controller? -
# and reloads btusb if not (an adapter you switched off still counts as present, so it's left alone).
bt_present() { timeout 5 bluetoothctl list 2>/dev/null | grep >/dev/null '^Controller'; }
desc_bt() {
    section
    say "Instala ps5-bt-guard: al arrancar y al despertar comprueba que el Bluetooth tiene adaptador y, si"
    say "no, recarga su driver (btusb) hasta dos veces. Si lo apagaste tú, no lo toca."
    say "POR QUÉ: a veces el chip IW620 no responde a su primer reinicio al arrancar ('hci0: Opcode 0x0c03"
    say "failed: -110') y el Bluetooth se queda sin adaptador: el mando no conecta y 'bluetoothctl' dice"
    say "'No default controller available'. El ps5-bt-revive de la imagen no reconoce ese error."
    say "Ahora: adaptador $(bt_present && echo presente || echo AUSENTE)."
    say "DESHACER: sudo systemctl disable ps5-bt-guard."
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

# --- disk ----------------------------------------------------------------------------------------
desc_disk() {
    section
    say "Impide que el monitor de discos de KDE (plasma-disks) consulte el SMART del disco: una regla"
    say "de polkit que lo deniega ($POLKIT_RULE), smartd desactivado y el módulo 'smart' de kded apagado."
    say "POR QUÉ: muchos adaptadores USB-NVMe se bloquean ~60 s con esa consulta (en el log del kernel:"
    say "'timing out command, waited 60s') y el paso del modo juego al escritorio tarda casi un minuto."
    say "Con la regla, unos 5 s. Solo desactivar el módulo no basta. Pierdes los avisos SMART de KDE."
    say "DESHACER: sudo rm $POLKIT_RULE; sudo systemctl restart polkit; sudo systemctl enable --now smartd."
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
    say "Arregla el cortafuegos (firewalld), que arranca «fallido»: funciona con una zona mínima en vez de la suya"
    say "($(fw_zone)) y no admite cambios (abrir un puerto da RUNNING_BUT_FAILED)."
    if [ -n "$bad" ]; then
        say "Causa: la zona $(fw_zone) usa $(echo $bad), y el kernel de la PS5 no trae ese módulo. Lo quita de la zona"
        say "(firewall-offline-cmd --zone=$(fw_zone) --remove-service-from-zone=…) y reinicia firewalld."
        say "samba-client sirve para encontrar equipos Windows por su nombre; el NAS por su IP no lo necesita."
    else
        say "No encuentro la causa conocida (un servicio cuyo módulo falta): lo mira firewall-offline-cmd --check-config."
    fi
    [ "$(fw_zone)" = FedoraWorkstation ] && say "Con la zona funcionando quedan abiertos a tu red los puertos 1025-65535, como en Bazzite de escritorio" &&
        say "(KDE Connect, transmisión de Steam, el monitor web). Más cerrado: sudo firewall-offline-cmd --set-default-zone=public."
    say "POR QUÉ: con el cortafuegos fallido, lo que abran otros ajustes o programas no se guarda."
    say "DESHACER: sudo rm /etc/firewalld/zones/$(fw_zone).xml; sudo systemctl restart firewalld"
}
check_firewall() {
    systemctl is-active -q firewalld 2>/dev/null || return 2
    [ "$(fw_state)" = running ]
}
apply_firewall() {
    local z s bad; z=$(fw_zone); bad=$(fw_bad)
    if [ -z "$bad" ]; then
        sudo firewall-offline-cmd --check-config; echo "  No sé arreglarlo solo: revisa lo de arriba y sudo tail -40 /var/log/firewalld."
        return 1
    fi
    for s in $(awk '{ print $1 }' <<<"$bad"); do
        sudo firewall-offline-cmd --zone="$z" --remove-service-from-zone="$s" >/dev/null || return 1
    done
    sudo systemctl restart firewalld && sleep 2
    [ "$(fw_state)" = running ] && say "Cortafuegos funcionando, zona $(sudo firewall-cmd --get-default-zone)." ||
        { echo "  Sigue fallido: sudo tail -40 /var/log/firewalld"; return 1; }
}

# --- brave ---------------------------------------------------------------------------------------
desc_brave() {
    section
    say "Brave (Flatpak) guarda sus claves sin la Cartera de KDE (--password-store=basic en $BRAVE_FLAGS)."
    say "POR QUÉ: como la sesión entra sola, la Cartera de KDE no se abre y Brave pide su contraseña cada vez."
    say "Ojo: las sesiones y contraseñas ya guardadas en Brave dejan de leerse (hay que volver a entrar)."
    say "DESHACER: borra esa línea del fichero."
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
    say "Microsoft Edge (Flatpak) guarda sus claves sin la Cartera de KDE (--password-store=basic en $EDGE_FLAGS)."
    say "POR QUÉ: como la sesión entra sola, la Cartera de KDE no se abre y Edge pide su contraseña cada vez."
    say "Ojo: las sesiones y contraseñas ya guardadas en Edge dejan de leerse (hay que volver a entrar)."
    say "DESHACER: borra esa línea del fichero."
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
    say "ROMs de EmuDeck desde un NAS por SMB: monta la carpeta compartida en $NAS_MNT (al primer uso;"
    say "si el NAS está apagado no bloquea el arranque) y ~/Emulation/roms pasa a ser un enlace a la"
    say "carpeta de ROMs del NAS (la local queda como ~/Emulation/roms.local). Da acceso a los Flatpak."
    say "Pide IP, carpeta compartida, usuario y ruta de las ROMs; la contraseña queda en /etc/samba (solo root)."
    say "POR QUÉ: no ocupar el disco de la PS5 y compartir las ROMs con otros equipos (p. ej. una Steam Deck)."
    say "Las BIOS y las partidas guardadas siguen en local. Requiere EmuDeck ya instalado."
    say "DESHACER: rm ~/Emulation/roms && mv ~/Emulation/roms.local ~/Emulation/roms; quita la línea de /etc/fstab."
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
        say "Ya hay un montaje del NAS: //$src en $mnt${cur:+ (ROMs en $cur)}."
    fi
    [ $ALL = 1 ] && [ -z "${NAS_IP:-}" ] && { say "Sin datos del NAS: ejecútalo sin --all para responder las preguntas."; return 1; }
    value NAS_IP "IP del NAS (p. ej. 192.168.1.x)" "${NAS_IP:-}"
    value NAS_SHARE "Carpeta compartida (como en \\\\NAS\\carpeta)" "${NAS_SHARE:-}"
    value NAS_USER "Usuario del NAS" "${NAS_USER:-}"
    value NAS_ROMS "Ruta de la carpeta roms dentro de la compartida" "${NAS_ROMS:-${cur:-Emulation/roms}}"
    local cred=/etc/samba/nas-$NAS_USER.cred
    rpm -q cifs-utils >/dev/null || sudo dnf5 install -y cifs-utils || return 1
    if ! sudo test -s "$cred"; then
        local P
        read -rsp "  Contraseña de $NAS_USER en el NAS (no se muestra): " P </dev/tty; echo
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
        { say "No puedo leer $NAS_MNT/$NAS_ROMS (¿NAS apagado, ruta o contraseña mal? Borra $cred y repite)."; return 1; }
    if [ -L ~/Emulation/roms ]; then             # already a link: point it at the (new) ROM path
        [ "$(readlink ~/Emulation/roms)" = "$NAS_MNT/$NAS_ROMS" ] ||
            { say "Enlace ~/Emulation/roms: $(readlink ~/Emulation/roms) → $NAS_MNT/$NAS_ROMS"
              ln -sfn "$NAS_MNT/$NAS_ROMS" ~/Emulation/roms || return 1; }
    else
        [ ! -e ~/Emulation/roms.local ] || { say "Ya existe ~/Emulation/roms.local; revísalo a mano."; return 1; }
        [ ! -e ~/Emulation/roms ] || mv ~/Emulation/roms ~/Emulation/roms.local || return 1
        ln -s "$NAS_MNT/$NAS_ROMS" ~/Emulation/roms || return 1
    fi
    flatpak override --user --filesystem="$NAS_MNT" || return 1
    local bios; bios="$NAS_MNT/$(dirname "$NAS_ROMS")/bios"
    if [ -d "$bios" ] && ask "  ¿Copiar al disco local las BIOS que falten desde el NAS ($bios)?"; then
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
            say "$only ficheros de $local_dir no están en el NAS."
            if ask "  ¿Copiarlos al NAS antes de enlazar (no se sobrescribe nada de allí)?"; then
                # regular files only: the share (SMB) can't hold links, and EmuDeck's bios folder has some
                # (e.g. ryujinx/keys -> the emulator's own folder)
                (cd "$local_dir" && find . -type f -print0 | while IFS= read -r -d '' f; do
                    [ -e "$nas/$f" ] || { mkdir -p "$nas/$(dirname "$f")" && cp -p "$f" "$nas/$f"; } || exit 1
                done) || return 1
            fi
        fi
    fi
    if [ -d "$local_dir" ]; then
        [ ! -e "$local_dir.local" ] || { say "Ya existe $local_dir.local; revísalo a mano."; return 1; }
        mv "$local_dir" "$local_dir.local" || return 1
    fi
    mkdir -p "$(dirname "$local_dir")" && ln -s "$nas" "$local_dir"
}

# --- bios ----------------------------------------------------------------------------------------
bios_nas() { local r; r=$(nas_roms_rel); echo "${NAS_BIOS:-${r%/roms}/bios}"; }
desc_bios() {
    section
    say "La carpeta ~/Emulation/bios pasa a ser un enlace a las BIOS del NAS ($(nas_mnt)/$(bios_nas)), como"
    say "ya lo es ~/Emulation/roms. La carpeta local queda como ~/Emulation/bios.local; antes de enlazar ofrece"
    say "copiar al NAS las BIOS que solo estén aquí."
    say "POR QUÉ: una sola copia de las BIOS para la PS5 y la Steam Deck. No añade riesgo: sin NAS tampoco hay ROMs."
    say "DESHACER: rm ~/Emulation/bios && mv ~/Emulation/bios.local ~/Emulation/bios"
}
check_bios() {
    [ -d ~/Emulation ] && check_nas >/dev/null 2>&1 || return 2
    local m; m=$(nas_mnt)
    [ "$(readlink ~/Emulation/bios 2>/dev/null)" = "$m/$(bios_nas)" ] && nas_dir_ok "$m/$(bios_nas)"
}
apply_bios() {
    local m; m=$(nas_mnt) || { say "Primero el bloque nas."; return 1; }
    value NAS_BIOS "Carpeta de BIOS dentro de la compartida" "$(bios_nas)"
    nas_dir_ok "$m/$NAS_BIOS" || mkdir -p "$m/$NAS_BIOS" || { say "No puedo usar $m/$NAS_BIOS (¿NAS apagado?)."; return 1; }
    link_to_nas ~/Emulation/bios "$m/$NAS_BIOS" || return 1
    say "BIOS: ~/Emulation/bios → $m/$NAS_BIOS ($(find -L ~/Emulation/bios -type f 2>/dev/null | wc -l) ficheros)"
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
    say "La carpeta de imágenes y vídeos de ES-DE ($d) pasa a ser un enlace a la del NAS"
    say "($(nas_mnt)/$(media_nas)), como ya lo es ~/Emulation/roms. No copia nada: usa lo que ya hay en el NAS."
    say "ES-DE no se toca: sigue leyendo de la misma ruta. La carpeta local queda como $d.local"
    say "($(du -sh "$d" 2>/dev/null | cut -f1 || echo 'vacía')); bórrala cuando veas que todo va bien."
    say "POR QUÉ: es lo que más ocupa de ES-DE; en el NAS lo comparten la PS5 y la Steam Deck."
    say "DESHACER: rm '$d' && mv '$d.local' '$d'"
}
check_media() {
    [ -d ~/ES-DE ] && check_nas >/dev/null 2>&1 || return 2
    local m; m=$(nas_mnt)
    [ "$(readlink "$(media_now)" 2>/dev/null)" = "$m/$(media_nas)" ] && nas_dir_ok "$m/$(media_nas)"
}
apply_media() {
    local m d; m=$(nas_mnt) || { say "Primero el bloque nas."; return 1; }
    pgrep -f -i 'es-de|emulationstation' >/dev/null && { say "ES-DE está abierto: ciérralo y repite."; return 1; }
    value NAS_MEDIA "Carpeta de medios dentro de la compartida" "$(media_nas)"
    nas_dir_ok "$m/$NAS_MEDIA" || { say "No encuentro $m/$NAS_MEDIA en el NAS (¿ruta o NAS apagado?)."; return 1; }
    d=$(media_now)
    link_to_nas "$d" "$m/$NAS_MEDIA" nocopy || return 1
    say "Medios de ES-DE: $d → $m/$NAS_MEDIA ($(ls "$m/$NAS_MEDIA" | wc -l) sistemas)"
    [ -d "$d.local" ] && say "Cuando compruebes que ES-DE muestra las imágenes: rm -rf '$d.local'"
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
    say "Repara la lista de sistemas que EmuDeck deja a ES-DE ($ESDE_SYSTEMS):"
    say "- líneas de Windows: '%CORE_RETROARCH%\\xxx_libretro.dll' → '/xxx_libretro.so', y '< command>' → '</command>'"
    say "  (ahora hay $(esde_windows_lines || echo 0));"
    say "- si Citra está instalado (~/Applications/citra-qt*.AppImage), añade 'Citra (Standalone)' a Nintendo 3DS"
    say "  ($(citra_installed && { esde_citra_missing && echo 'falta' || echo 'ya está'; } || echo 'Citra no instalado'))."
    say "POR QUÉ: con esas líneas ES-DE busca un .dll que en Linux no existe ('citra_libretro.dll'), y las listas"
    say "de una Steam Deck que usaba Citra (Azahar no abre ROMs cifradas) piden 'Citra (Standalone)'."
    say "EmuDeck puede volver a escribir el fichero al actualizarse: si 3DS vuelve a fallar, repite este bloque."
    say "DESHACER: copia sobre él el $ESDE_SYSTEMS.bak-* más reciente."
}
check_esde() {
    [ -f "$ESDE_SYSTEMS" ] || return 2
    [ "$(esde_windows_lines)" = 0 ] && ! esde_citra_missing
}
apply_esde() {
    pgrep -f -i 'es-de|emulationstation' >/dev/null && { say "ES-DE está abierto: ciérralo y repite."; return 1; }
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
        say "El fichero no ha quedado como XML válido: restauro la copia ($bak)."
        cp "$bak" "$ESDE_SYSTEMS"; return 1
    fi
    say "Líneas de Windows que quedan: $(esde_windows_lines). 3DS: $(awk '/<name>n3ds<\/name>/,/<\/system>/' "$ESDE_SYSTEMS" |
        sed -n 's/.*label="\([^"]*\)".*/\1/p' | paste -sd, -)."
    say "En ES-DE: Otros ajustes → Emuladores alternativos → Nintendo 3DS → Citra (Standalone), si no lo tenía ya."
}

# --- portproton -----------------------------------------------------------------------------------
# Defaults for every PortProton game, in its global settings (data/user.conf). PortProton reads user.conf AFTER a
# game's .ppdb (start.sh: pw_init_db, then source user.conf), so a plain export would beat the game's own setting:
# each default applies only when the game's .ppdb doesn't set that variable.
PP_USERCONF=$HOME/.var/app/ru.linux_gaming.PortProton/data/user.conf
PP_DEFAULTS='PW_USE_FSYNC=1 PW_USE_ESYNC=1 PW_USE_RAY_TRACING=1'
desc_portproton() {
    section
    say "Ajustes por defecto para TODOS los juegos de PortProton (en $PP_USERCONF), salvo los que el .ppdb"
    say "de un juego fije él mismo:"
    say "- PW_USE_FSYNC=1 y PW_USE_ESYNC=1: sincronización rápida entre los hilos del juego. PortProton la trae"
    say "  apagada; el Proton de Steam (y la Steam Deck) la lleva encendida. Menos tirones en juegos que cargan la CPU."
    say "- PW_USE_RAY_TRACING=1: trazado de rayos en DX12 (vkd3d «dxr»). PortProton lo apaga en AMD aunque el driver"
    say "  de la PS5 lo tiene, y los juegos que lo exigen dicen que la gráfica no vale."
    say "  Ojo: algún juego, al verlo, lo enciende en su calidad por defecto y va más lento: bájalo en sus opciones"
    say "  gráficas, o apágalo solo para él con export PW_USE_RAY_TRACING=\"0\" en su .ppdb."
    say "POR QUÉ: la máxima compatibilidad sin tocar nada juego a juego."
    say "DESHACER: borra en ese fichero el bloque entre «# >>> ps5-bazzite-toolbox» y «# <<< ps5-bazzite-toolbox»."
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
    bash -n "$PP_USERCONF" || { say "El fichero no ha quedado bien: restaura la copia .bak."; return 1; }
    say "Ajustes globales de PortProton: $PP_DEFAULTS (los juegos abiertos los cogen al volver a abrirlos)."
}

# --- monitorweb ----------------------------------------------------------------------------------
# The live monitor (option 4) in a phone's browser, always reachable at http://<console>:8765 with nothing to start:
# a small Python server, a user service (no root) and a firewall rule for the home network only. It only measures
# while a page asks for it ("Empezar"); unwatched for 30 s it stops by itself. The script is kept here as text.
monweb_script() { cat <<'__MONWEB__'
#!/usr/bin/env python3
# PS5 Bazzite toolbox — the live monitor (menu option 4) in a phone's browser: http://<PS5 address>:PORT
# Waiting it does nothing (blocked on the socket). "Empezar" on the page starts a sample every 2 s; with no page
# asking for 30 s (phone locked, tab closed) it stops by itself. Read-only: it shows numbers, it changes nothing.
# Only answers private addresses (home network); the firewall rule of the toolbox's block "monitorweb" does the same.
import glob, ipaddress, json, os, re, subprocess, sys, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[sys.argv.index("--port") + 1]) if "--port" in sys.argv else 8765
EVERY, IDLE_STOP, KEEP = 2, 30, 1800          # seconds per sample, stop after this long unwatched, samples kept (1 h)
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
T_GPU, T_CPU = hwmon("amdgpu"), hwmon("k10temp")

def meminfo():
    m = {}
    for l in rd("/proc/meminfo").splitlines():
        k, v = l.split(":", 1); m[k] = int(v.split()[0]) // 1024
    return m

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

    def info(self):
        m = meminfo()
        return {"vt": num(DEV + "/mem_info_vram_total") >> 20 if DEV else 0, "gt": num(DEV + "/mem_info_gtt_total") >> 20 if DEV else 0,
                "rt": m.get("MemTotal", 0), "st": m.get("SwapTotal", 0), "threads": os.cpu_count(),
                "zram": bool(glob.glob("/sys/block/zram*")), "host": os.uname().nodename}

    def begin(self):
        with self.lock:
            self.seen = time.time()
            if self.running: return
            self.running = True; self.samples = []; self.total = 0; self.errors = []; self.vmref = 0; self.first += 1
            self.start = time.strftime("%Y-%m-%d %H:%M:%S")
            self.thread = threading.Thread(target=self.loop, daemon=True); self.thread.start()

    def end(self):
        with self.lock: self.running = False

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
                 "swap": m.get("SwapTotal", 0) - m.get("SwapFree", 0), "zram": zr,
                 "tgpu": num(T_GPU) // 1000 if T_GPU else None, "tcpu": num(T_CPU) // 1000 if T_CPU else None,
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
            v.append("La swap se llenó: si el juego pide más memoria, el sistema lo cierra. Agrándala (ajuste zram).")
        if ram_short and vram_full:
            v.append("Van justas las dos (VRAM llena y Linux tirando de swap): baja texturas o calidad en el juego.")
        elif ram_short:
            v.append("Se acabó la RAM, no la VRAM: baja la VRAM a su pico + 1 GB (ajuste vram) y las texturas del juego.")
        elif vram_full:
            v.append("La VRAM se llenó y a Linux le sobra RAM: sube la VRAM (ajuste vram) o baja la resolución.")
        if sum(1 for x in S if x["gpu"] >= 95) * 2 >= n:
            v.append("La GPU va al máximo casi siempre: ella marca los FPS. Baja resolución o calidad, o usa reescalado.")
        elif sum(1 for x in S if x["cpumax"] >= 95 and x["gpu"] < 85) * 10 >= n * 3:
            v.append("Un hilo de la CPU va lleno mientras la GPU espera: baja distancia de visión, multitudes o físicas.")
        return {"vram": pk("vram"), "gtt": pk("gtt"), "ram": pk("ram"), "minavail": minav, "swap": pk("swap"), "swap0": s0,
                "zram": pk("zram"), "cpu": pk("cpu"), "cpuavg": round(sum(x["cpu"] for x in S) / n),
                "gpu": pk("gpu"), "gpuavg": round(sum(x["gpu"] for x in S) / n), "tgpu": pk("tgpu"), "tcpu": pk("tcpu"),
                "verdict": v, "vmref": self.vmref}

    def data(self, since):                   # since = how many samples of this session the page already has
        info = self.info()
        with self.lock:
            if self.running: self.seen = time.time()
            base = self.total - len(self.samples); off = since - base
            reset = off < 0 or off > len(self.samples)
            return {"running": self.running, "session": self.first, "start": self.start, "info": info,
                    "total": self.total, "reset": reset, "samples": self.samples if reset else self.samples[off:],
                    "summary": self.summary(info), "errors": self.errors}

    def csv(self):
        head = "hora,cpu_pct,cpu_hilo_max_pct,gpu_pct,vram_usada_mb,gtt_mb,ram_usada_mb,ram_disponible_mb,swap_usada_mb,zram_en_ram_mb,temp_cpu_c,temp_gpu_c,errores_gpu,top_vram,top_ram"
        with self.lock: S = list(self.samples)
        rows = [head] + [",".join(map(str, [x["t"], x["cpu"], x["cpumax"], x["gpu"], x["vram"], x["gtt"], x["ram"], x["avail"],
                        x["swap"], x["zram"], x["tcpu"] if x["tcpu"] is not None else "", x["tgpu"] if x["tgpu"] is not None else "",
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
        if not self.ok_client(): return self.send(403, "Solo desde tu red de casa.\n", "text/plain; charset=utf-8")
        path, _, q = self.path.partition("?")
        if path == "/": return self.send(200, PAGE, "text/html; charset=utf-8")
        if path == "/data":
            m = re.search(r"since=(-?\d+)", q)
            return self.send(200, json.dumps(MON.data(int(m.group(1)) if m else 0)), "application/json")
        if path == "/csv":
            return self.send(200, MON.csv(), "text/csv; charset=utf-8",
                             [("Content-Disposition", f'attachment; filename="ps5-mem-{time.strftime("%Y%m%d-%H%M%S")}.csv"')])
        if path == "/manifest.json":
            return self.send(200, json.dumps({"name": "Monitor PS5", "short_name": "Monitor PS5", "start_url": "/",
                                              "display": "standalone", "background_color": "#101418", "theme_color": "#101418"}),
                             "application/manifest+json")
        self.send(404, "No existe.\n", "text/plain; charset=utf-8")

    def do_POST(self):
        if not self.ok_client(): return self.send(403, "", "text/plain")
        if self.path == "/start": MON.begin()
        elif self.path == "/stop": MON.end()
        else: return self.send(404, "", "text/plain")
        self.send(200, "{}", "application/json")

PAGE = r"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#101418">
<link rel="manifest" href="/manifest.json"><title>Monitor PS5</title>
<style>
:root{--bg:#101418;--card:#1a2027;--line:#2a323b;--tx:#e6ebf0;--mu:#8b98a5;--ok:#3fb950;--warn:#d29922;--bad:#f85149;--acc:#58a6ff}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--tx);font:15px/1.4 system-ui,-apple-system,sans-serif;padding:12px 12px 40px}
h1{font-size:18px;margin:4px 0 2px}.sub{color:var(--mu);font-size:13px;margin-bottom:12px}
.row{display:flex;gap:8px;margin-bottom:12px}button,.btn{flex:1;border:0;border-radius:10px;padding:12px;font:600 16px system-ui;color:#fff;background:var(--acc);text-align:center;text-decoration:none}
button.stop{background:#30363d}.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:10px}
.k{color:var(--mu);font-size:12px;text-transform:uppercase;letter-spacing:.04em}.v{font-size:22px;font-weight:700;margin:2px 0}
.v small{font-size:13px;color:var(--mu);font-weight:500}canvas{width:100%;height:42px;display:block}
.ok{color:var(--ok)}.warn{color:var(--warn)}.bad{color:var(--bad)}.full{grid-column:1/-1}
ul{margin:6px 0 0;padding-left:18px}li{margin:3px 0}.mu{color:var(--mu)}
</style></head><body>
<h1>Monitor PS5</h1><div class="sub" id="sub">conectando…</div>
<div class="row"><button id="go">Empezar</button><a class="btn" id="csv" href="/csv" style="display:none;background:#30363d">CSV</a></div>
<div class="grid" id="tiles"></div>
<div class="card full" style="margin-top:8px"><div class="k">Más VRAM</div><div id="top" class="mu">—</div></div>
<div class="card full" style="margin-top:8px"><div class="k">Picos y veredicto</div><div id="sum" class="mu">Pulsa Empezar y juega: aquí saldrá qué te limita.</div></div>
<script>
const T=[["cpu","CPU","%"],["gpu","GPU","%"],["vram","VRAM","GB"],["gtt","GTT","GB"],["ram","RAM","GB"],["swap","Swap","GB"],["tcpu","Temp. CPU","°C"],["tgpu","Temp. GPU","°C"]];
let S=[],got=0,info={},running=false,session=0,timer=null;
const g=b=>(b/1024).toFixed(1), $=id=>document.getElementById(id);
$("tiles").innerHTML=T.map(([k,n])=>`<div class="card"><div class="k">${n}</div><div class="v" id="v_${k}">—</div><canvas id="c_${k}"></canvas></div>`).join("");
function cls(k,x){const vt=info.vt||1;if(k=="vram")return x.vram/vt>=.9?"bad":x.vram/vt>=.8?"warn":"ok";
 if(k=="ram")return x.avail<512?"bad":x.avail<1024?"warn":"ok";if(k=="gpu")return x.gpu>=95?"warn":"ok";
 if(k=="cpu")return x.cpumax>=95?"warn":"ok";if(k=="tgpu"||k=="tcpu")return (x[k]||0)>=90?"bad":(x[k]||0)>=80?"warn":"ok";
 if(k=="swap")return info.st&&x.swap>=info.st-64?"bad":"ok";return"ok"}
function text(k,x){switch(k){case"cpu":return`${x.cpu}% <small>hilo ${x.cpumax}%</small>`;case"gpu":return`${x.gpu}%`;
 case"vram":return`${g(x.vram)} <small>/ ${g(info.vt)}</small>`;case"gtt":return`${g(x.gtt)} <small>/ ${g(info.gt)}</small>`;
 case"ram":return`${g(x.ram)} <small>/ ${g(info.rt)}</small>`;case"swap":return`${g(x.swap)} <small>/ ${g(info.st)}${info.zram?` · en RAM ${g(x.zram)}`:""}</small>`;
 default:return x[k]==null?"—":`${x[k]}°`}}
function max(k){return {cpu:100,gpu:100,vram:info.vt,gtt:info.gt,ram:info.rt,swap:info.st||1,tcpu:100,tgpu:100}[k]||1}
function spark(k){const c=$("c_"+k),w=c.width=c.clientWidth*devicePixelRatio,h=c.height=42*devicePixelRatio,x=c.getContext("2d");
 const d=S.slice(-150),m=max(k);x.clearRect(0,0,w,h);if(d.length<2)return;x.beginPath();
 d.forEach((s,i)=>{const px=i*w/(d.length-1),py=h-(Math.min(s[k]||0,m)/m)*(h-4)-2;i?x.lineTo(px,py):x.moveTo(px,py)});
 x.strokeStyle=getComputedStyle(document.body).getPropertyValue("--acc");x.lineWidth=2*devicePixelRatio;x.stroke()}
function draw(){const x=S[S.length-1];
 $("sub").textContent=`${info.host||"PS5"} · ${running?"midiendo cada 2 s desde "+(window._start||""):S.length?"parado ("+S.length+" medidas)":"en espera"}`;
 $("go").textContent=running?"Parar":"Empezar";$("go").className=running?"stop":"";$("csv").style.display=S.length?"":"none";
 if(!x)return;T.forEach(([k])=>{const e=$("v_"+k);e.innerHTML=text(k,x);e.className="v "+cls(k,x);spark(k)});
 $("top").innerHTML=x.top.length?x.top.map(([c,m])=>`${c} <b>${(m/1024).toFixed(1)} GB</b>`).join(" · ")+`<br><span class="mu">más RAM: ${x.ramtop[0]} ${(x.ramtop[1]/1024).toFixed(1)} GB</span>`:"ningún programa usa la GPU"}
function summary(s,err){if(!s||!s.vram&&s.vram!==0){return}
 let h=`<ul><li>VRAM ${g(s.vram)} de ${g(info.vt)} GB · GTT ${g(s.gtt)} GB</li><li>RAM ${g(s.ram)} de ${g(info.rt)} GB (libre como mínimo ${g(s.minavail)})</li>
 <li>Swap ${g(s.swap)} GB (al empezar ${g(s.swap0)})</li><li>CPU ${s.cpuavg}% de media, ${s.cpu}% máx. · GPU ${s.gpuavg}% de media, ${s.gpu}% máx.</li>
 <li>Temperatura CPU ${s.tcpu||"?"}° · GPU ${s.tgpu||"?"}°</li></ul>`;
 if(err&&err.length)h+=`<div class="bad" style="margin-top:6px">Errores de memoria de la GPU:</div><ul class="bad">${err.map(e=>`<li>${e.replace(/</g,"&lt;")}</li>`).join("")}</ul>`;
 if(s.vmref)h+=`<div class="mu" style="margin-top:6px">${s.vmref} reservas de memoria rechazadas (no son de la GPU; los emuladores lo hacen y siguen).</div>`;
 h+=s.verdict.length?`<ul>${s.verdict.map(v=>`<li class="warn">${v}</li>`).join("")}</ul>`:`<div class="ok" style="margin-top:6px">Sin aprietos por ahora.</div>`;
 $("sum").innerHTML=h}
async function poll(){try{const same=session&&got,r=await fetch("/data?since="+(same?got:-1)),d=await r.json();
 info=d.info;running=d.running;window._start=(d.start||"").slice(11);
 if(d.session!=session||d.reset||!same){session=d.session;S=d.samples}else S=S.concat(d.samples).slice(-1800);
 got=d.total;draw();summary(d.summary,d.errors)}catch(e){$("sub").textContent="sin conexión con la PS5…"}
 clearTimeout(timer);if(document.visibilityState=="visible")timer=setTimeout(poll,running?2000:5000)}
$("go").onclick=async()=>{await fetch(running?"/stop":"/start",{method:"POST"});setTimeout(poll,300)};
document.addEventListener("visibilitychange",()=>{if(document.visibilityState=="visible")poll()});poll();
</script></body></html>"""

if __name__ == "__main__":
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), H); srv.daemon_threads = True
    print(f"Monitor PS5 en http://<dirección de la consola>:{PORT}", flush=True)
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
    say "El monitor en directo (opción 4) en el navegador del móvil: http://$(lan_ip || echo '<IP de la consola>'):$MONWEB_PORT"
    say "Guárdalo en la pantalla de inicio. «Empezar» mide cada 2 s (CPU, GPU, VRAM, RAM, swap, temperaturas,"
    say "qué gasta más, picos y qué te limita) y deja bajar el CSV; sin nadie mirando 30 s, para solo."
    say "Instala $MONWEB_PY y el servicio de tu usuario ps5-monitor-web (arranca con la sesión, sin root), y abre"
    say "el puerto $MONWEB_PORT en el cortafuegos solo para tu red ($(lan_net)). Solo enseña datos; no tiene clave:"
    say "cualquiera en tu red que sepa la dirección lo puede ver. Esperando gasta ~25 MB de RAM y nada de CPU."
    say "POR QUÉ: ver cómo va un juego desde el móvil, sin SSH ni abrir nada en la consola."
    say "DESHACER: systemctl --user disable --now ps5-monitor-web; rm $MONWEB_UNIT $MONWEB_PY;"
    say "  sudo firewall-cmd --permanent --remove-rich-rule='$(monweb_rule)'; sudo firewall-cmd --reload"
}
check_monitorweb() {
    command -v python3 >/dev/null || return 2
    cmp -s <(monweb_script) "$MONWEB_PY" || return 1          # missing, or an older toolbox's version
    systemctl --user is-enabled -q ps5-monitor-web 2>/dev/null && systemctl --user is-active -q ps5-monitor-web || return 1
    ! monweb_fw || sudo firewall-cmd --query-rich-rule="$(monweb_rule)" >/dev/null 2>&1
}
apply_monitorweb() {
    mkdir -p "$(dirname "$MONWEB_PY")" "$(dirname "$MONWEB_UNIT")" || return 1
    monweb_script >"$MONWEB_PY" || return 1
    cat >"$MONWEB_UNIT" <<EOF || return 1
[Unit]
Description=Monitor de la PS5 en el navegador (ps5-bazzite-toolbox, bloque monitorweb)

[Service]
ExecStart=/usr/bin/python3 $MONWEB_PY --port $MONWEB_PORT
Restart=on-failure
Nice=10
NoNewPrivileges=yes

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload && systemctl --user enable ps5-monitor-web && systemctl --user restart ps5-monitor-web || return 1
    if monweb_fw && [ "$(fw_state)" != running ]; then
        echo "  El cortafuegos está fallido y no admite abrir el puerto: aplica antes el bloque firewall (opción 16 → firewall)."
        return 1
    fi
    if monweb_fw; then
        sudo firewall-cmd --permanent --add-rich-rule="$(monweb_rule)" >/dev/null && sudo firewall-cmd --reload >/dev/null || return 1
    fi
    sleep 1
    curl -fs -o /dev/null "http://127.0.0.1:$MONWEB_PORT/" || { echo "  El servicio no responde: journalctl --user -u ps5-monitor-web"; return 1; }
    say "Ábrelo en el móvil (conectado a tu wifi): http://$(lan_ip):$MONWEB_PORT"
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
    local secs=$1; shift
    printf '%s' "bash \"$TOOLBOX_SELF\" $*; rc=\$?; if [ \$rc = 0 ]; then echo; echo \"Se cierra en $secs s…\"; sleep $secs; else echo; echo \"Error (\$rc). Pulsa Intro para cerrar.\"; read -r _; fi"
}
COLL_DESKTOP="$(desk_dir)/portproton-collection.desktop"
desc_atajos() {
    section
    say "Atajos que llaman a este toolbox ($TOOLBOX_SELF):"
    say "- Dolphin, botón derecho sobre un .exe: «Instalar en PortProton y Steam», «Cambiar aislamiento» y «Desinstalar» ($SM_GAME);"
    say "- Dolphin, botón derecho sobre una carpeta: «Ver lo que ocupa cada carpeta» ($SM_SPACE);"
    say "- el comando «espacio [carpeta]» en cualquier terminal ($SPACE_BIN);"
    say "- en el escritorio, «Colección PortProton» ($COLL_DESKTOP): sincroniza la colección de Steam."
    say "POR QUÉ: tenerlos tras instalar desde cero; antes eran scripts sueltos en ~ (add-proton-game.sh,"
    say "portproton-collection.sh, verEspacioCadaDirectorio.sh), que este bloque ya no necesita."
    say "Si mueves el toolbox de sitio, repite este bloque. DESHACER: rm '$SM_GAME' '$SM_SPACE' '$COLL_DESKTOP'; sudo rm $SPACE_BIN"
}
check_atajos() {
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] || return 2       # run from a pipe: nothing to point at
    # a missing file makes grep return 2, which here means "doesn't apply": anything missing is pending (1)
    grep -qs -F "$TOOLBOX_SELF" "$SM_GAME" && grep -qs -F "$TOOLBOX_SELF" "$SM_SPACE" &&
        grep -qs -F "$TOOLBOX_SELF" "$SPACE_BIN" && grep -qs -F "$TOOLBOX_SELF" "$COLL_DESKTOP" &&
        grep -qs 'Se cierra en' "$SM_GAME" && grep -qs 'Se cierra en' "$COLL_DESKTOP" &&
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
Name=Instalar en PortProton y Steam (normal o aislado)
Icon=ru.linux_gaming.PortProton
Exec=konsole -e bash -c '$(run_then_close 5 '--add-game "$1"')' _ %f

[Desktop Action changeProtonGame]
Name=Cambiar aislamiento (normal, aislado con red o sin red)
Icon=security-medium
Exec=konsole -e bash -c '$(run_then_close 5 '--change-level "$1"')' _ %f

[Desktop Action removeProtonGame]
Name=Desinstalar (de Steam, PortProton y el disco; pregunta cada paso)
Icon=edit-delete
Exec=konsole -e bash -c '$(run_then_close 5 '--remove-game "$1"')' _ %f
EOF
    cat >"$SM_SPACE" <<EOF
[Desktop Entry]
Type=Service
MimeType=inode/directory;
Actions=space;

[Desktop Action space]
Name=Ver lo que ocupa cada carpeta
Icon=filelight
Exec=konsole --hold -e bash "$TOOLBOX_SELF" --space %f
EOF
    chmod +x "$SM_GAME" "$SM_SPACE"      # Plasma 6 ignores service menus that aren't executable
    printf '#!/bin/sh\n# espacio [CARPETA]: lo que ocupa cada carpeta de CARPETA (ps5-bazzite-toolbox.sh --space)\nexec bash "%s" --space "$@"\n' \
        "$TOOLBOX_SELF" | sudo tee "$SPACE_BIN" >/dev/null && sudo chmod 755 "$SPACE_BIN" || return 1
    cat >"$COLL_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Colección PortProton
Comment=Sincroniza la colección PortProton de Steam (cierra Steam si está abierto)
Icon=steam
Terminal=true
Exec=bash -c '$(run_then_close 3 --pp-collection --yes)'
EOF
    chmod +x "$COLL_DESKTOP"
    # the stand-alone versions this replaces (made by hand or by add-proton-game.sh --install)
    rm -f "$SM_DIR/add-proton-game.desktop" "$HOME/.local/bin/add-proton-game.sh" \
        "$SM_DIR/ps5-toolbox-add-game.desktop" "$SM_DIR/ps5-toolbox-space.desktop"    # names before v1.0.0
    local old; old=$(cd ~ && ls portproton-collection.sh verEspacioCadaDirectorio.sh parpadeoVideo.sh 2>/dev/null | tr '\n' ' ')
    [ -n "$old" ] && say "Ya no hacen falta (bórralos si quieres): ~/${old// / ~/}"
    say "Si Dolphin estaba abierto, ciérralo y ábrelo para ver las acciones nuevas."
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
    echo "Vigilando el kernel (disco, GPU, cuelgues, memoria, Wi-Fi, Bluetooth, USB). Ctrl+C para salir."
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
    echo "== Sesión configurada"
    if [ -f "$OVERRIDE" ]; then grep Session "$OVERRIDE"; else echo "Session=modo juego (la de la imagen)"; fi
    echo "== Sesiones gráficas"
    loginctl list-sessions --no-legend | awk '$4 == "seat0"' | while read -r id _; do
        # a session can vanish between list and show while sddm relaunches it
        loginctl show-session "$id" -p Id -p Type -p Active -p State -p VTNr 2>/dev/null | tr '\n' ' ' || true; echo
    done
    echo "== Compositores"
    pgrep -a -u "$U" -x 'kwin_wayland|plasmashell|gamescope|gamescope-wl' || echo "(ninguno)"
    echo "== SDDM: $(systemctl is-active sddm)"
    sudo journalctl -b -u sddm --no-pager -o short 2>/dev/null | grep 'Starting Wayland' | tail -3
}
session_restart() {
    echo "==> Parando SDDM y cerrando la sesión gráfica anterior…"
    sudo systemctl stop sddm
    for id in $(loginctl list-sessions --no-legend | awk '$4 == "seat0" {print $1}'); do
        sudo loginctl terminate-session "$id" 2>/dev/null || true
    done
    sleep 2
    sudo pkill -u "$U" -x "$COMPOSITORS" 2>/dev/null || true
    sleep 2
    sudo pkill -9 -u "$U" -x "$COMPOSITORS" 2>/dev/null || true
    if compositor_alive; then
        echo "Sigue vivo un compositor:"; pgrep -a -u "$U" -x 'kwin_wayland|gamescope|gamescope-wl'
        return 1
    fi
    echo "==> Arrancando SDDM…"
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
        *) echo "Uso: --session status|restart|desktop|gamemode" >&2; return 2 ;;
    esac
}

run_checks() {
NEED_SESSION=0 NEED_BT=0
LOG=$(mktemp "${TMPDIR:-/tmp}/ps5-diag.XXXXXX") REPORT=ps5-diag-$(date +%Y%m%d-%H%M%S).txt
OK=0 WARN=0 BAD=0
log() { printf '%s\n' "$@" >>"$LOG"; }
head_() { printf '\n%s== %s ==%s\n' "$B" "$1" "$N"; log "" "== $1 =="; }
ok()   { OK=$((OK + 1));     printf '  %s✔%s %s\n' "$G" "$N" "$1"; log "  OK    $1"; }
warn() { WARN=$((WARN + 1)); printf '  %s!%s %s\n' "$Y" "$N" "$1"; log "  AVISO $1"; }
bad()  { BAD=$((BAD + 1));   printf '  %s✘%s %s\n' "$R" "$N" "$1"; log "  MAL   $1"; }
info() { printf '    %s\n' "$1"; log "    $1"; }
raw()  { log "  --- $1"; sed 's/^/    | /' >>"$LOG"; }       # stdin -> report only

KLOG=$(sudo journalctl -k -b "$BOOT" --no-pager -o short-precise 2>/dev/null)
kcount() { grep -ciE "$1" <<<"$KLOG"; }
kshow() { grep -iE "$1" <<<"$KLOG" | tail -"${2:-15}"; }
check_k() {                              # check_k "area" pattern ok|warn|bad -> count, last lines to the report
    local n; n=$(kcount "$2")
    if [ "$n" = 0 ]; then ok "$1: nada"
    else
        "$3" "$1: $n mensajes"; kshow "$2" 3 | while IFS= read -r l; do info "${l:0:150}"; done
        kshow "$2" 30 | raw "$1 (últimos 30)"
    fi
}

# --- system ----------------------------------------------------------------------------------------
head_ "Sistema"
info "Imagen $(cat /etc/ps5-bazzite-deck-version 2>/dev/null || echo '?'), kernel $(uname -r), arrancado $(uptime -p)"
info "Arranque analizado: $BOOT ($(sudo journalctl --list-boots --no-pager 2>/dev/null | awk -v b="$BOOT" '$1 == b { $1 = $2 = ""; print }' | sed 's/^ *//'))"
log "cmdline: $(cat /proc/cmdline)"
log "vram.txt: $(sudo cat /efi/vram.txt 2>/dev/null)"
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' |
    grep -vE '^(bootloader-update|greenboot-healthcheck|ublue-os-media-automount)\.service$')
if [ -z "$failed" ]; then ok "Servicios: ninguno fallido (sin contar los 3 de ostree/automontaje, que no importan)"
else bad "Servicios fallidos: $(echo $failed)"; for u in $failed; do systemctl status "$u" --no-pager -n 20 2>&1 | raw "$u"; done; fi
# did the previous boot end cleanly? a hang + forced power-off leaves no shutdown messages
prev=$((BOOT - 1))
if sudo journalctl -b "$prev" -n 0 >/dev/null 2>&1; then
    if sudo journalctl -b "$prev" --no-pager -n 300 2>/dev/null |
        grep -E >/dev/null 'systemd-shutdown|Reached target .*(Power-Off|Reboot|Halt|kexec)|Shutting down'; then
        ok "El arranque anterior terminó con un apagado o reinicio normal"
    else
        bad "El arranque anterior terminó de golpe (cuelgue o apagado forzado): usa --boot $prev para revisarlo"
        sudo journalctl -b "$prev" --no-pager -n 60 2>/dev/null | raw "últimas líneas del arranque $prev"
    fi
fi
info "Un arranque que se cuelga antes de escribir en el disco no deja rastro (ni siquiera aparece en la lista)."
sudo journalctl --list-boots --no-pager 2>/dev/null | tail -6 | raw "últimos arranques"

# --- boot drive --------------------------------------------------------------------------------------
head_ "Disco de arranque"
src=$(findmnt -no SOURCE / | sed 's/\[.*//'); disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
props=$(udevadm info -q property -n "/dev/$disk" 2>/dev/null)
if grep -q '^ID_BUS=usb' <<<"$props"; then
    info "USB $(sed -n 's/^ID_VENDOR_ID=//p' <<<"$props"):$(sed -n 's/^ID_MODEL_ID=//p' <<<"$props") $(sed -n 's/^ID_MODEL=//p' <<<"$props"), driver $(sed -n 's/^ID_USB_DRIVER=//p' <<<"$props")"
    lsusb -t 2>/dev/null | raw "lsusb -t"
else info "/dev/$disk (no es USB)"; fi
check_k "Atascos y errores del disco" "$P_DISK" bad
use=$(df --output=pcent / | tail -1 | tr -dc 0-9)
if [ "$use" -ge 90 ]; then bad "Espacio: / al $use %"; else ok "Espacio: / al $use % ($(df -h --output=avail / | tail -1 | tr -d ' ') libres)"; fi
if sudo test -f "$POLKIT_RULE"; then ok "Regla anti-SMART de KDE puesta (el escritorio no se atasca)"
elif grep -q '^ID_BUS=usb' <<<"$props"; then warn "Sin la regla anti-SMART de KDE: el paso al escritorio puede tardar ~60 s (bloque disk)"; fi

# --- GPU -----------------------------------------------------------------------------------------------
head_ "Gráfica"
dev=$(ls -d /sys/class/drm/card*/device 2>/dev/null | head -1)
gb() { awk -v v="$(cat "$1" 2>/dev/null || echo 0)" 'BEGIN { printf "%.1f GB", v / 2^30 }'; }
info "VRAM $(gb "$dev/mem_info_vram_total") (usada $(gb "$dev/mem_info_vram_used")), RAM prestada a la GPU (GTT) $(gb "$dev/mem_info_gtt_used")"
vt=$(cat "$dev/mem_info_vram_total" 2>/dev/null || echo 0)
[ "$vt" -lt $((1 << 31)) ] && warn "VRAM menor de 2 GB: los juegos DX12/UE5 pueden caerse con 'Not enough memory' (bloque vram)"
check_k "Reinicios y fallos de la GPU" "$P_GPU" warn
[ "$(kcount "$P_GPU")" = 0 ] || info "Al entrar en el modo juego es un fallo conocido de la imagen; si coincide con un juego, es el juego."
[ "$(kcount "$P_GPU")" = 0 ] || [ "$(gpu_cu_now)" != 40 ] ||
    info "Tienes las 40 unidades de la GPU activas (bloque gpu40): si estos fallos son nuevos, prueba a volver a 36."

# --- hangs, memory, crashes ----------------------------------------------------------------------------
head_ "Cuelgues, memoria y cierres"
check_k "Cuelgues del kernel" "$P_HANG" bad
dproc=$(ps -eo stat,pid,comm | awk '$1 ~ /^D/ && $3 != "ext4lazyinit"')
if [ -z "$dproc" ]; then ok "Procesos bloqueados ahora (estado D): ninguno"
else warn "Procesos en estado D ahora (si se repiten, algo está colgado): $(echo $dproc)"; fi
check_k "Falta de memoria (OOM)" "$P_OOM" bad
free -h | raw "free -h"
avail=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$avail" -lt 1024 ]; then warn "Memoria disponible: $avail MB"; else ok "Memoria disponible: $((avail / 1024)) GB"; fi
ps -eo rss,comm --sort=-rss | head -11 | awk 'NR > 1 {printf "%6d MB  %s\n", $1 / 1024, $2}' | raw "procesos con más memoria"
dumps=$(coredumpctl list --since "-24h" --no-legend --no-pager 2>/dev/null)
if [ -z "$dumps" ]; then ok "Programas cerrados de golpe (24 h): ninguno"
else
    warn "Programas cerrados de golpe (24 h): $(awk '{ n = split($(NF - 1), p, "/"); print p[n] }' <<<"$dumps" | sort | uniq -c | sort -rn | awk '{printf "%s×%s ", $1, $2}')"
    raw "coredumpctl (24 h)" <<<"$dumps"
fi

# --- temperature and fans ------------------------------------------------------------------------------
head_ "Temperatura y ventilador"
t=$(sensors 2>/dev/null | awk '/^Tctl:|^edge:/ { gsub(/[+°C]/, "", $2); print int($2); exit }')
if [ -z "$t" ]; then warn "No puedo leer la temperatura (sensors)"
elif [ "$t" -ge 85 ]; then bad "Temperatura: $t °C"
elif [ "$t" -ge 70 ]; then warn "Temperatura: $t °C (en reposo debería rondar 45 °C con ps5fan)"
else ok "Temperatura: $t °C"; fi
for s in ps5fan ps5boost ps5-perf; do
    systemctl list-unit-files "$s.service" >/dev/null 2>&1 &&
        info "$s: $(systemctl is-enabled "$s" 2>/dev/null)/$(systemctl is-active "$s" 2>/dev/null)"
done
command -v ps5-perf >/dev/null && info "$(ps5-perf status 2>/dev/null | head -1)"
[ -r "$FAN_SYS" ] && info "Temperatura objetivo del ventilador: $(cat "$FAN_SYS") °C (de fábrica 80; más baja = más frío y más ruido, bloque fans)"

# --- network, Wi-Fi, Bluetooth, NAS --------------------------------------------------------------------
head_ "Red, Wi-Fi, Bluetooth y NAS"
nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | grep -v ':loopback:' | while IFS=: read -r d ty st; do info "$d ($ty): $st"; done
gw=$(ip route show default | awk '{print $3; exit}')
if [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1; then ok "Router ($gw) responde"; else bad "Sin respuesta del router ${gw:-(no hay ruta por defecto)}"; fi
if getent hosts github.com >/dev/null; then ok "DNS funciona"; else bad "DNS no resuelve github.com"; fi
check_k "Driver Wi-Fi (moal)" "$P_WIFI" warn
check_k "Bluetooth" "$P_BT" warn
if lsusb -d 1286:2059 >/dev/null 2>&1 || [ -e /sys/class/bluetooth/hci0 ]; then
    if bt_present; then ok "Adaptador Bluetooth presente"
    else bad "Bluetooth sin adaptador: el mando no puede conectar ('No default controller available')"; NEED_BT=1; fi
fi
check_k "Dispositivos USB desconectados" "$P_USB" warn
for m in $(awk '$3 == "cifs" { print $2 }' /etc/fstab 2>/dev/null); do
    if timeout 20 ls "$m" >/dev/null 2>&1; then ok "NAS en $m accesible"; else bad "NAS en $m no responde (¿apagado o sin red?)"; fi
done
if systemctl is-active -q firewalld 2>/dev/null; then
    if [ "$(fw_state)" = running ]; then ok "Cortafuegos funcionando (zona $(sudo firewall-cmd --get-default-zone 2>/dev/null))"
    else fw_b=$(fw_bad); bad "Cortafuegos fallido: va con una zona mínima y no admite cambios${fw_b:+ (la zona $(fw_zone) usa $(echo $fw_b))}; bloque firewall"; fi
fi
info "Avisos 'Salina poller' (ruido del parche USB, no es un fallo): $(kcount "$P_SALINA")"

# --- settings (the setup blocks' own checks) ------------------------------------------------------
head_ "Ajustes de la consola"
info "cmdline: $(sed -E 's/root=[^ ]+ //' /proc/cmdline)"
for b in $BLOCKS; do
    check_"$b" >/dev/null 2>&1; st=$?
    skipvar=SKIP_$b
    case $st in
        0) ok "$b: aplicado" ;;
        2) info "$b: no aplica en esta consola" ;;
        *) if [ "${!skipvar:-0}" = 1 ]; then info "$b: no aplicado (lo decidiste)"
           else warn "$b: pendiente (menú 15, o --setup)"; fi ;;
    esac
done
if warm_on && ! check_hdmi; then warn "Reinicio en caliente sin ps5-hdmi-kick: la imagen puede salir en negro (bloque hdmi)"; fi

# --- graphical session ---------------------------------------------------------------------------------
head_ "Sesión gráfica"
if [ "$BOOT" != 0 ]; then info "(solo se revisa en el arranque actual)"
elif [ "$(systemctl is-active sddm)" != active ]; then bad "SDDM no está activo: no hay pantalla de sesión"; NEED_SESSION=1
elif compositor_alive; then ok "Sesión gráfica viva ($(pgrep -u "$U" -x 'gamescope|gamescope-wl' >/dev/null && echo 'modo juego' || echo 'escritorio'))"
else bad "SDDM activo pero sin modo juego ni escritorio: la pantalla estará en negro o en el login"; NEED_SESSION=1; fi
[ -f "$OVERRIDE" ] && info "Arranca siempre en: $(sed -n 's/^Session=//p' "$OVERRIDE")"
session_status 2>&1 | raw "estado de la sesión"

# --- summary -------------------------------------------------------------------------------------------
{ echo; echo "== Resumen: $OK bien, $WARN avisos, $BAD mal =="; } | tee -a "$LOG"
echo
if save_output "$LOG" "$REPORT" "el informe completo (sin contraseñas; sirve para pedir ayuda)"; then
    echo "Para copiarlo a otro ordenador:  scp $(id -un)@$(hostname -I | awk '{print $1}'):$(printf %q "$SAVED") ."
fi
if [ "$NEED_BT" = 1 ] && [ -t 0 ]; then
    echo
    read -rp "El Bluetooth no tiene adaptador. ¿Recargar su driver ahora (btusb)? [S/n] " a
    if [[ $a != [nN]* ]]; then
        sudo modprobe -r btusb && sleep 2 && sudo modprobe btusb && sleep 5
        if bt_present; then echo "Adaptador recuperado. Para que se haga solo en cada arranque: menú 16 → bt."
        else echo "Sigue sin adaptador: apaga y arranca con el cargador (un arranque en frío reinicia el chip)."; fi
    fi
fi
if [ "$NEED_SESSION" = 1 ] && [ -t 0 ]; then
    echo
    read -rp "La sesión gráfica parece caída. ¿Reiniciarla ahora (cierra Steam y lo que esté abierto)? [s/N] " a
    [[ $a == [sS]* ]] && session_restart
fi
}

# --- setup: run the blocks ------------------------------------------------------------------------------------
setup_run() {
if [ -z "$VERSION" ] && [ $STATUS_ONLY = 0 ]; then
    echo "Aviso: no encuentro /etc/ps5-bazzite-deck-version; estos ajustes son para la imagen ps5-bazzite-deck." >&2
    read -rp "¿Continuar de todos modos? [s/N] " a </dev/tty; [[ $a == [sS]* ]] || return 1
fi
echo "Ajustes de la consola ${VERSION:+(v$VERSION)} — respuestas guardadas en $CONF"
REBOOT=0 COLD=0
DONE="" FAILED="" SKIPPED=""
for b in ${ONLY:-$BLOCKS}; do
    declare -F "check_$b" >/dev/null || { echo "Bloque desconocido: $b" >&2; continue; }
    check_"$b"; st=$?
    skipvar=SKIP_$b
    if [ $st = 1 ] && [ "${!skipvar:-0}" = 1 ] && [ -z "$ONLY" ]; then st=3; fi
    case $st in
        0) printf '✔ %-10s aplicado\n' "$b" ;;
        2) printf '– %-10s no aplica en esta consola\n' "$b" ;;
        3) printf '– %-10s no aplicado (lo decidiste; menú 16 o --only %s para volver a preguntar)\n' "$b" "$b" ;;
        *) printf '✘ %-10s pendiente\n' "$b" ;;
    esac
    [ $STATUS_ONLY = 1 ] && continue
    if [ $st = 1 ]; then q="¿Aplicar '$b'?" d=$(default_for "$b")
    elif [ $st = 0 ] && [ -n "$ONLY" ]; then     # asked for by name: allow changing its values
        q="'$b' ya está aplicado. ¿Volver a aplicarlo (para cambiar sus valores)?" d=N
    else continue; fi
    desc_"$b"
    if ask "$q" "$d"; then
        remember "$skipvar" 0
        if apply_"$b"; then DONE="$DONE $b"; say "→ hecho"
        else FAILED="$FAILED $b"; say "→ FALLÓ (revisa los mensajes de arriba)"
        fi
    elif [ $st = 1 ]; then
        [ $ALL = 1 ] || remember "$skipvar" 1
        [ "$b" = warmreboot ] && remember WARM_REBOOT off
        SKIPPED="$SKIPPED $b"
    fi
    echo
done
[ $STATUS_ONLY = 1 ] && return 0

echo "Resumen — aplicados:${DONE:- ninguno} | omitidos:${SKIPPED:- ninguno} | fallidos:${FAILED:- ninguno}"
[ $COLD = 1 ] && echo "APAGA (sudo poweroff) y arranca con el cargador: la VRAM y las unidades de la GPU solo cambian en un arranque en frío."
[ $COLD = 0 ] && [ $REBOOT = 1 ] && echo "Reinicia para que cuenten los cambios (parámetros de arranque, zram)."
[ -z "$ONLY" ] && cat <<'EOF'
A mano (no se puede automatizar desde aquí):
  - passwd, si es una instalación nueva: la contraseña por defecto es ps5 y SSH está abierto en la red.
  - Steam: zona horaria e idioma propios (Ajustes → Sistema), rango RGB "Full" (modo juego y escritorio),
    resolución en Ajustes → Pantalla, salvapantallas/atenuado desactivado.
  - EmuDeck: instalador SteamOS, tipo de dispositivo "Steam Machine", ubicación Internal; después
    el bloque nas y Steam ROM Manager (Parse → Save).
  - DualSense por Bluetooth: emparejar en un perfil propio del mando (PS + Cuadrado).
EOF
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
cpu_load() {                             # cpu_load PREV CUR (/proc/stat "cpu" lines) -> "average busiest" in %
    # busy = everything but idle and iowait; the average alone hides a game held back by one full thread
    awk 'NR == FNR { for (i = 2; i <= 9; i++) t[$1] += $i; id[$1] = $5 + $6; next }
         { T = 0; for (i = 2; i <= 9; i++) T += $i; dt = T - t[$1]; p = dt > 0 ? 100 * (dt - ($5 + $6 - id[$1])) / dt : 0
           if ($1 == "cpu") avg = p; else if (p > max) max = p }
         END { printf "%d %d\n", avg, max }' <(printf '%s\n' "$1") <(printf '%s\n' "$2")
}
gpu_top() {                              # top N programs by VRAM: "name size" lines (MiB)
    grep -s -E '^drm-(client-id|memory-vram):' /proc/[0-9]*/fdinfo/* 2>/dev/null | awk -v n="${1:-3}" '
        { split($1, f, "/"); pid = f[3] }
        /drm-client-id:/ { cid[$1] = $2 }
        /drm-memory-vram:/ { k = $1; sub(/drm-memory-vram:$/, "drm-client-id:", k); v[k] = $2; p[k] = pid }
        END {
            for (k in v) if ((k in cid) && !seen[cid[k]]++) mib[p[k]] += v[k] / 1024
            for (q in mib) { c = ""; getline c < ("/proc/" q "/comm"); close("/proc/" q "/comm"); tot[c] += mib[q] }
            for (c in tot) printf "%d %s\n", tot[c], c
        }' | sort -rn | head -"${1:-3}" | awk '{ printf "%s %.1fG  ", $2, $1 / 1024 }'
}
mem_watch() {
    local stop=0 dev csv csv_name start t vu vt gu gt ra rt ru su st zr tc cc gp cpu0 cpu1 ca cm top ram ev peak_v=0 peak_g=0 min_ra=999999 peak_r=0 peak_s=0 peak_z=0 su0='' peak_t=0 events=0 n=0 ram_top=''
    local peak_ct=0 peak_ca=0 peak_gp=0 sum_ca=0 sum_gp=0 n_gpu=0 n_cpu=0
    dev=$(ls -d /sys/class/drm/card*/device 2>/dev/null | head -1)
    csv=$(mktemp "${TMPDIR:-/tmp}/ps5-mem.XXXXXX") csv_name=ps5-mem-$(date +%Y%m%d-%H%M%S).csv
    start=$(date '+%Y-%m-%d %H:%M:%S')
    echo "hora,vram_usada_mb,vram_total_mb,gtt_mb,gtt_total_mb,ram_usada_mb,ram_total_mb,ram_disponible_mb,swap_usada_mb,swap_total_mb,zram_en_ram_mb,temp_c,errores_gpu,top_vram,top_ram,cpu_pct,cpu_hilo_max_pct,gpu_pct,temp_cpu_c" >"$csv"
    vt=$(( $(cat "$dev/mem_info_vram_total" 2>/dev/null || echo 0) >> 20 ))
    gt=$(( $(cat "$dev/mem_info_gtt_total" 2>/dev/null || echo 0) >> 20 ))
    rt=$(awk '/^MemTotal:/ { print int($2 / 1024) }' /proc/meminfo)
    st=$(awk '/^SwapTotal:/ { print int($2 / 1024) }' /proc/meminfo)
    echo "Memoria en directo: VRAM $((vt / 1024)) GB, RAM de Linux $(awk -v r="$rt" 'BEGIN { printf "%.1f", r / 1024 }') GB, swap $(awk -v s="$st" 'BEGIN { printf "%.1f", s / 1024 }') GB$(ls /sys/block/zram* >/dev/null 2>&1 && echo ' (zram: comprimida en la RAM)')."
    echo "Ctrl+C para parar y ver los picos (al final puedes guardar cada medida en un CSV)."
    systemctl --user is-active -q ps5-monitor-web 2>/dev/null && echo "También en el móvil: http://$(lan_ip):$MONWEB_PORT"
    echo "CPU: media de los $(nproc) hilos y, entre paréntesis, el hilo más cargado. temp: CPU/GPU."
    printf '%-8s %-10s %-5s %-15s %-13s %-14s %-21s %-8s %s\n' hora CPU GPU VRAM GTT RAM "swap (en RAM)" temp "más VRAM"
    cpu0=$(grep '^cpu' /proc/stat)
    trap 'stop=1' INT                    # Ctrl+C: finish this sample, then show the peaks
    while [ $stop = 0 ]; do
        t=$(date +%T)
        vu=$(( $(cat "$dev/mem_info_vram_used" 2>/dev/null || echo 0) >> 20 ))
        gu=$(( $(cat "$dev/mem_info_gtt_used" 2>/dev/null || echo 0) >> 20 ))
        ra=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)
        ru=$((rt - ra))
        zr=$(zram_mb)
        su=$(awk '/^SwapTotal:/ { t = $2 } /^SwapFree:/ { f = $2 } END { print int((t - f) / 1024) }' /proc/meminfo)
        tc=$(sensors 2>/dev/null | awk '/^edge:/ { gsub(/[+°C]/, "", $2); print int($2); exit }')    # GPU
        cc=$(sensors 2>/dev/null | awk '/^Tctl:/ { gsub(/[+°C]/, "", $2); print int($2); exit }')    # CPU
        gp=$(cat "$dev/gpu_busy_percent" 2>/dev/null || echo 0)
        cpu1=$(grep '^cpu' /proc/stat); read -r ca cm < <(cpu_load "$cpu0" "$cpu1"); cpu0=$cpu1
        top=$(gpu_top 3)
        ram=$(ps -eo rss=,comm= --sort=-rss | head -1 | awk '{ printf "%s %.1fG", $2, $1 / 2^20 }')
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
        [ "${tc:-0}" -gt "$peak_t" ] && peak_t=${tc:-0}
        [ "${cc:-0}" -gt "$peak_ct" ] && peak_ct=${cc:-0}
        [ "$ca" -gt "$peak_ca" ] && peak_ca=$ca
        [ "$gp" -gt "$peak_gp" ] && peak_gp=$gp
        sum_ca=$((sum_ca + ca)) sum_gp=$((sum_gp + gp))
        [ "$gp" -ge 95 ] && n_gpu=$((n_gpu + 1))                    # GPU flat out: it sets the frame rate
        [ "$cm" -ge 95 ] && [ "$gp" -lt 85 ] && n_cpu=$((n_cpu + 1))  # one thread full and the GPU waiting
        ev=''; [ "$events" -gt 0 ] && ev="  ${R}errores GPU: $events${N}"
        local col=$G rcol=$G; [ "$vt" -gt 0 ] && [ $((vu * 100 / vt)) -ge 90 ] && col=$R
        [ "$ra" -lt 512 ] && rcol=$R                # under 512 MB available: Linux is about to swap hard
        printf '%-8s %-10s %-5s %s%-15s%s %-13s %s%-14s%s %-21s %-8s %s%s\n' "$t" "$ca% ($cm)" "$gp%" "$col" "$(awk -v u="$vu" -v t="$vt" 'BEGIN { printf "%.2f/%.1f GB", u / 1024, t / 1024 }')" "$N" \
            "$(awk -v g="$gu" -v t="$gt" 'BEGIN { printf "%.2f/%.1f GB", g / 1024, t / 1024 }')" \
            "$rcol" "$(awk -v u="$ru" -v t="$rt" 'BEGIN { printf "%.1f/%.1f GB", u / 1024, t / 1024 }')" "$N" \
            "$(awk -v s="$su" -v t="$st" -v z="$zr" 'BEGIN { printf "%.1f/%.1f GB (%.1f)", s / 1024, t / 1024, z / 1024 }')" "${cc:-?}/${tc:-?}°C" "$top" "$ev"
        echo "$t,$vu,$vt,$gu,$gt,$ru,$rt,$ra,$su,$st,$zr,${tc:-},$events,\"$top\",\"$ram\",$ca,$cm,$gp,${cc:-}" >>"$csv"
        sleep 2 || true
    done
    trap - INT
    echo
    echo "== Picos =="
    echo "  VRAM usada:   $(awk -v u="$peak_v" -v t="$vt" 'BEGIN { printf "%.2f de %.1f GB (%d %%)", u / 1024, t / 1024, t ? u * 100 / t : 0 }')"
    echo "  GTT:          $(awk -v g="$peak_g" -v t="$gt" 'BEGIN { printf "%.2f de %.1f GB (RAM que la gráfica toma prestada)", g / 1024, t / 1024 }')"
    echo "  RAM usada:    $(awk -v u="$peak_r" -v t="$rt" -v r="$min_ra" 'BEGIN { printf "%.1f de %.1f GB (%d %%; libre como mínimo %.1f GB)", u / 1024, t / 1024, t ? u * 100 / t : 0, r / 1024 }') (entonces gastaba más: $ram_top)"
    echo "  Swap:         $(awk -v a="${su0:-0}" -v b="$peak_s" -v t="$st" -v z="$peak_z" 'BEGIN { printf "%.1f de %.1f GB como máximo (al empezar %.1f); ocupaba %.1f GB de RAM (zram)", b / 1024, t / 1024, a / 1024, z / 1024 }')"
    echo "  CPU:          $((sum_ca / (n > 0 ? n : 1))) % de media, ${peak_ca} % como máximo (de los $(nproc) hilos)"
    echo "  GPU:          $((sum_gp / (n > 0 ? n : 1))) % de media, ${peak_gp} % como máximo"
    echo "  Temperatura:  CPU ${peak_ct} °C, GPU ${peak_t} °C como máximo"
    if [ "$events" -gt 0 ]; then
        echo "  ${R}Errores de memoria de la GPU: $events${N}"
        sudo journalctl -k --since "$start" --no-pager 2>/dev/null | grep -iE "$P_GPUMEM" | grep -vF "$P_VMREF" | tail -5 | sed 's/^/    /'
    else echo "  Errores de memoria de la GPU: ninguno"; fi
    local vr vr_n vr_pid vr_c vr_gb vr_exe
    vr=$(vm_refused "$start")
    if [ -n "$vr" ]; then
        IFS='|' read -r vr_n vr_pid vr_c vr_gb <<<"$vr"
        # an AppImage is "AppRun.wrapped" in the log: its real program, if it's still running
        vr_exe=$(basename "$(readlink "/proc/$vr_pid/exe" 2>/dev/null)" 2>/dev/null)
        echo "  Reservas de memoria rechazadas (no son de la GPU): $vr_n, de $vr_c${vr_exe:+ ($vr_exe)}, de $vr_gb GB de una vez"
        echo "    Pidió de golpe más memoria de la que hay (RAM + swap) y Linux se lo negó. Los emuladores (p. ej. RPCS3)"
        echo "    reservan así espacio de direcciones y siguen de otra forma: si el juego no se cerró, no es un fallo."
    fi
    local ram_short=0 vram_full=0
    { [ "$min_ra" -lt 512 ] || [ "$peak_s" -gt $(( ${su0:-0} + 512 )) ]; } && ram_short=1
    [ "$vt" -gt 0 ] && [ $((peak_v * 100 / vt)) -ge 90 ] && vram_full=1
    [ "$st" -gt 0 ] && [ "$peak_s" -ge $((st - 64)) ] &&
        echo "  → La swap se llenó: si el juego pide más memoria, el sistema lo cierra. Agrándala (menú 16 → zram)."
    if [ $ram_short = 1 ] && [ $vram_full = 1 ]; then
        echo "  → Van justas las dos (VRAM llena y Linux tirando de swap): moverlas no ayuda, la memoria total no da"
        echo "    para más con esta calidad. Baja texturas o calidad en el juego. Sin errores de la GPU, puede valer así."
    elif [ $ram_short = 1 ]; then
        echo "  → Se acabó la RAM (no la VRAM): Linux tiró de swap. Baja la VRAM a su pico + 1 GB (menú 16 → vram)"
        echo "    para dar esa memoria a Linux, y la calidad de texturas del juego."
    elif [ $vram_full = 1 ]; then
        echo "  → La VRAM se llenó y a Linux le sobra RAM: sube la VRAM (menú 16 → vram) o baja la resolución del juego."
    fi
    if [ $n -gt 0 ] && [ $((n_gpu * 100 / n)) -ge 50 ]; then
        echo "  → La GPU va al máximo la mayor parte del tiempo: ella marca los FPS. Para ganar, baja resolución o"
        echo "    calidad gráfica (o usa reescalado: TSR, FSR); la CPU no es el límite."
    elif [ $n -gt 0 ] && [ $((n_cpu * 100 / n)) -ge 30 ]; then
        echo "  → Un hilo de la CPU va lleno mientras la GPU espera: el límite es la CPU (un solo hilo). Bajar gráficos"
        echo "    apenas ayuda; baja lo que carga la CPU (distancia de visión, multitudes, físicas) o limita los FPS."
    fi
    echo
    save_output "$csv" "$csv_name" "cada medida en un CSV (para una hoja de cálculo)"
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
    if [ "$d" = S ]; then read -rp "$1 [S/n] " a; [[ $a != [nN]* ]]; else read -rp "$1 [s/N] " a; [[ $a == [sS]* ]]; fi
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
        printf '%s  Hay una versión nueva de esta caja de herramientas: %s (tienes v%s). Opción 18 para actualizarla.%s\n' \
            "$Y" "$tag" "$TOOLBOX_VERSION" "$N"
    fi
    rm -rf "$tmp"
}
self_update() {                          # self_update [TAG] -> download, check and replace this script (asks first)
    local want=${1:-} tmp tag url sha target
    command -v python3 >/dev/null || { echo "Falta python3." >&2; return 1; }
    [ -z "$want" ] || [[ $want == v* ]] || want=v$want
    tmp=$(mktemp -d)
    echo "==> Consultando las versiones de $TOOLBOX_REPO en GitHub…"
    toolbox_release "$want" "$tmp" ||
        { echo "No encuentro ${want:-la última versión} (¿hay red? ¿existe esa versión?)." >&2; rm -rf "$tmp"; return 1; }
    tag=$(<"$tmp/tag") url=$(<"$tmp/url") sha=$(<"$tmp/sha")
    printf '\nTienes v%s. %s: %s\n' "$TOOLBOX_VERSION" "$([ -n "$want" ] && echo Elegida || echo Última)" "$tag"
    if [ -z "$want" ] && ! toolbox_newer "$tag"; then echo "Ya tienes la última versión."; rm -rf "$tmp"; return 1; fi
    toolbox_newer "$tag" || [ "${tag#v}" = "$TOOLBOX_VERSION" ] || echo "${Y}Ojo: $tag es más antigua que la tuya.$N"
    [ -n "$url" ] && [ -n "$sha" ] || { echo "Esa versión no trae ps5-bazzite-toolbox.sh y su .sha256." >&2; rm -rf "$tmp"; return 1; }
    printf '\n%sNovedades de %s:%s\n' "$B" "$tag" "$N"; sed 's/^/  /' "$tmp/notes"
    # Where to write: the installed command if there is one, else this file when it can be replaced, else install it
    target=$TOOLBOX_SELF
    if [ -f "$TOOLBOX_BIN" ] || [ ! -f "$target" ] || [ ! -w "$(dirname "$target")" ]; then target=$TOOLBOX_BIN; fi
    section
    say "Descarga ps5-bazzite-toolbox.sh de $tag, comprueba su SHA-256 y que bash lo lee bien, y sustituye $target." \
        "Tus respuestas guardadas ($CONF) se conservan." \
        "DESHACER: la copia anterior queda en $target.v$TOOLBOX_VERSION (cp $target.v$TOOLBOX_VERSION $target)."
    yesno "¿Actualizar a $tag?" S || { rm -rf "$tmp"; return 1; }
    curl -fsSL --retry 3 -o "$tmp/ps5-bazzite-toolbox.sh" "$url" && curl -fsSL --retry 3 -o "$tmp/ps5-bazzite-toolbox.sh.sha256" "$sha" ||
        { echo "Falló la descarga." >&2; rm -rf "$tmp"; return 1; }
    (cd "$tmp" && sha256sum -c ps5-bazzite-toolbox.sh.sha256) || { echo "${R}El SHA-256 no coincide: no cambio nada.$N" >&2; rm -rf "$tmp"; return 1; }
    bash -n "$tmp/ps5-bazzite-toolbox.sh" || { echo "${R}El fichero descargado no es válido: no cambio nada.$N" >&2; rm -rf "$tmp"; return 1; }
    rm -f "$target".v*                   # keep only the copy of the version being replaced
    [ -f "$target" ] && cp -p "$target" "$target.v$TOOLBOX_VERSION"
    mkdir -p "$(dirname "$target")"
    install -m 755 "$tmp/ps5-bazzite-toolbox.sh" "$target" || { echo "No puedo escribir $target." >&2; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    [ "$target" = "$TOOLBOX_BIN" ] && desktop_entry
    echo "${G}Hecho:$N $target es ahora $tag. Ábrela de nuevo para usarla: $([ "$target" = "$TOOLBOX_BIN" ] && echo ps5-bazzite-toolbox || echo "bash $target")"
}

# --- installed as a command ------------------------------------------------------------------------------------
# ~/.local/bin is the user's own (no sudo), is in Bazzite's PATH and survives image updates (/home is kept).
desktop_entry() {                        # the applications menu entry (KDE opens it in Konsole)
    mkdir -p "$(dirname "$TOOLBOX_DESKTOP")"
    cat >"$TOOLBOX_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Caja de herramientas PS5
GenericName=ps5-bazzite-toolbox
Comment=Diagnóstico, ajustes y utilidades para Bazzite en la PS5
Icon=utilities-terminal
Terminal=true
Exec="$TOOLBOX_BIN"
Categories=System;Utility;
EOF
}
atajos_used() { [ -e "$SM_GAME" ] || [ -e "$SM_SPACE" ] || [ -e "$SPACE_BIN" ] || [ -e "$COLL_DESKTOP" ] ||
                [ -e "$SM_DIR/ps5-toolbox-add-game.desktop" ]; }
install_self() {
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] || {
        echo "Ejecutada desde una tubería: descárgala primero (curl -LO …/ps5-bazzite-toolbox.sh) y ejecuta ese fichero." >&2
        return 1; }
    if [ "$TOOLBOX_SELF" = "$TOOLBOX_BIN" ]; then echo "Ya está instalada en $TOOLBOX_BIN."; desktop_entry; return 0; fi
    section
    say "Copia este fichero ($TOOLBOX_SELF, v$TOOLBOX_VERSION) a $TOOLBOX_BIN y añade «Caja de herramientas PS5»"
    say "al menú de aplicaciones de KDE ($TOOLBOX_DESKTOP)."
    [ -f "$TOOLBOX_BIN" ] && say "Sustituye la que ya hay instalada ($("$TOOLBOX_BIN" --version 2>/dev/null))."
    say "POR QUÉ: abrirla desde cualquier terminal con «ps5-bazzite-toolbox» o desde el menú, sin acordarte de la"
    say "ruta. Las actualizaciones (opción 18) y los atajos del bloque atajos usan siempre esa copia."
    say "DESHACER: ps5-bazzite-toolbox --uninstall (o rm $TOOLBOX_BIN $TOOLBOX_DESKTOP)."
    yesno "¿Instalarla?" S || return 1
    mkdir -p "$(dirname "$TOOLBOX_BIN")" && install -m 755 "$TOOLBOX_SELF" "$TOOLBOX_BIN" || return 1
    desktop_entry
    remember INSTALL_ASKED yes
    echo "${G}Instalada.$N Ábrela con: ps5-bazzite-toolbox (o desde el menú de aplicaciones)."
    case :$PATH: in *":$HOME/.local/bin:"*) ;; *) echo "  ($HOME/.local/bin no está en tu PATH: usa $TOOLBOX_BIN)" ;; esac
    local src=$TOOLBOX_SELF               # the downloaded file (TOOLBOX_SELF changes below, for the shortcuts)
    TOOLBOX_SELF=$TOOLBOX_BIN
    if atajos_used && ! check_atajos; then
        echo "Tus atajos (Dolphin, «espacio», «Colección PortProton») usan otra copia de la caja de herramientas."
        yesno "¿Los cambio para que usen la instalada ($TOOLBOX_BIN)?" S && need_sudo && apply_atajos
    fi
    TOOLBOX_SELF=$src
    # The downloaded file is no longer needed; a copy inside a git checkout is someone's working copy: leave it
    if ! git -C "$(dirname "$src")" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
        yesno "¿Borro el fichero descargado ($src)? Ya no hace falta." S; then
        rm -f "$src" && echo "Borrado."
    fi
}
uninstall_self() {
    [ -f "$TOOLBOX_BIN" ] || [ -f "$TOOLBOX_DESKTOP" ] || { echo "No está instalada."; return 0; }
    section
    say "Borra $TOOLBOX_BIN y la entrada del menú ($TOOLBOX_DESKTOP)."
    say "Tus respuestas guardadas ($CONF) y los ajustes aplicados se quedan como están."
    say "DESHACER: vuelve a descargarla e instálala (ver el README)."
    yesno "¿Desinstalarla?" N || return 1
    rm -f "$TOOLBOX_BIN" "$TOOLBOX_DESKTOP" "$TOOLBOX_BIN".v*
    echo "Desinstalada."
    grep -qs -F "$TOOLBOX_BIN" "$SM_GAME" "$SPACE_BIN" "$COLL_DESKTOP" &&
        echo "Los atajos (Dolphin, «espacio», «Colección PortProton») la usaban: quítalos con rm '$SM_GAME' '$SM_SPACE' '$COLL_DESKTOP'; sudo rm $SPACE_BIN"
    return 0
}
offer_install() {                        # once, from the menu: run from a downloaded file and not installed yet
    [ -n "$TOOLBOX_SELF" ] && [ -f "$TOOLBOX_SELF" ] && [ "$TOOLBOX_SELF" != "$TOOLBOX_BIN" ] || return 0
    if [ -f "$TOOLBOX_BIN" ]; then
        printf '%s  Estás usando %s; la instalada es %s («ps5-bazzite-toolbox»). Opción 19 para sustituirla por esta.%s\n' \
            "$Y" "$TOOLBOX_SELF" "$("$TOOLBOX_BIN" --version 2>/dev/null)" "$N"
        return 0
    fi
    [ "${INSTALL_ASKED:-}" = no ] && return 0
    install_self || remember INSTALL_ASKED no
}

update_image() {
    local want=${1:-} tmp n i c tag date kind type url sha title src lfile lsha def='' dir log rc online=1 d
    if [ $IS_BOOTC = 1 ]; then if [ -n "$want" ]; then bootc_menu switch "$want"; else bootc_menu upgrade; fi; return; fi
    command -v python3 >/dev/null || { echo "Falta python3." >&2; return 1; }
    tmp=$(mktemp -d)
    echo "==> Consultando las versiones de $REPO en GitHub…"
    if ! curl -fsSL --retry 3 "https://api.github.com/repos/$REPO/releases?per_page=100" -o "$tmp/rel.json"; then
        online=0; echo '[]' >"$tmp/rel.json"
        echo "No puedo conectar con GitHub (¿hay red?): solo las versiones de tus carpetas." >&2
    fi
    # the bundles in your folders (up to 3 levels down; an unreachable NAS gives up after 30 s)
    : >"$tmp/local"
    local IFS_OLD=$IFS; IFS=:
    for d in $IMG_LOCAL; do
        IFS=$IFS_OLD
        [ -d "$d" ] || { echo "Aviso: no encuentro la carpeta $d (¿NAS apagado o sin montar?)." >&2; continue; }
        echo "==> Buscando versiones descargadas en $d…"
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
    [ -s "$tmp/list" ] || { echo "No encuentro versiones con paquete de actualización." >&2; rm -rf "$tmp"; return 1; }
    def=$(awk -F'\037' '$3 == "stable" && $4 == "full" { print $1; exit }' "$tmp/list")
    [ -n "$def" ] || def=$(awk -F'\037' '$4 == "full" { print $1; exit }' "$tmp/list")
    if [ -z "$want" ]; then
        printf '\nInstalada: %s\n' "${VERSION:+v$VERSION}"
        i=0
        while IFS=$'\037' read -r tag date kind type _ _ title src _; do
            i=$((i + 1)); n=''
            [ "$kind" = pre ] && n="$n [preliminar]"
            [ "$type" = quick ] && n="$n [rápida: solo kernel]"
            case $src in
                both) n="$n [descargada]" ;;
                local) n="$n [descargada$([ $online = 1 ] && echo ', ya no está en GitHub')]" ;;
            esac
            [ -n "$title" ] && n="$n  $title"
            [ "$tag" = "$def" ] && n="$n ← estable más reciente"
            [ "$tag" = "v$VERSION" ] && n="$n (instalada)"
            printf '  %2d) %-8s %s%s\n' "$i" "$tag" "$date" "$n"
        done <"$tmp/list"
        [ -n "$IMG_LOCAL" ] && echo "  Carpetas con versiones descargadas: ${IMG_LOCAL//:/, }"
        read -rp "¿Qué versión? (número o etiqueta, Intro = $def, l = añadir una carpeta con versiones descargadas, 0 = cancelar): " c
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
    [ -n "${url:-}${lfile:-}" ] || { echo "No hay paquete de actualización para $want." >&2; rm -rf "$tmp"; return 1; }

    echo; echo "== Novedades de $tag ($date) =="
    # the release's own notes; for one only in your folder, its NOTAS.md or notes.md if it has one
    python3 -I - "$tmp/rel.json" "$tag" "$(dirname "${lfile:-/x/x}")" <<'PY' | tee "$tmp/notes"
import json, os, sys
body = next((r["body"] for r in json.load(open(sys.argv[1])) if r["tag_name"] == sys.argv[2]), None)
if body is None:
    for n in ("NOTAS.md", "notes.md", "RELEASE.md"):
        f = os.path.join(sys.argv[3], n)
        if os.path.isfile(f):
            body = open(f, errors="replace").read(); break
if body is None:
    print("(sin notas: ni en GitHub ni junto al paquete)")
else:
    body = body.split("## Updating")[0].split("## VRR test")[0].strip().splitlines()
    print("\n".join(body[:40]) + ("\n…" if len(body) > 40 else ""))
PY
    echo
    [ -n "$lfile" ] && echo "Se instala desde tu copia: $lfile"
    [ "$kind" = pre ] && echo "Aviso: $tag es PRELIMINAR (de pruebas); la estable más reciente es $def."
    [[ ${title:-} == *PRO* ]] && echo "Aviso: según su título es SOLO para la PS5 Pro ($title)."
    if [ "$type" = quick ]; then
        echo "Aviso: es una actualización RÁPIDA (solo el kernel), que va encima de una versión base:"
        python3 -I - "$tmp/rel.json" "$tag" <<'PY'
import json, sys
for r in json.load(open(sys.argv[1])):
    if r["tag_name"] == sys.argv[2] and "## Updating" in r["body"]:
        print("  " + r["body"].split("## Updating", 1)[1].strip().split("\n")[0])
PY
    fi
    if [ "$tag" = "v$VERSION" ]; then echo "Aviso: $tag ya está instalada; se volvería a instalar."
    elif [ -n "$VERSION" ] && ! printf '%s\n%s\n' "$VERSION" "${tag#v}" | sort -V -C; then
        echo "Aviso: $tag es ANTERIOR a la instalada (v$VERSION): sería volver atrás."
    fi
    yesno "¿Actualizar a $tag?" N || { rm -rf "$tmp"; return 0; }

    # room: ~150 MB download + ~1 GB unpacked; the boot partition takes a new kernel + initrd (~115 MB)
    if [ "$(df --output=avail -k "$HOME" | tail -1)" -lt 2000000 ]; then
        echo "Menos de 2 GB libres en $HOME; libera espacio antes." >&2; rm -rf "$tmp"; return 1
    fi
    sudo df -h /efi | tail -1 | awk '{ print "Partición de arranque: " $4 " libres de " $2 }'

    dir=$HOME/ps5-update-$tag; log=$(mktemp "${TMPDIR:-/tmp}/ps5-update.XXXXXX")
    mkdir -p "$dir" || { rm -rf "$tmp"; return 1; }
    local file sumf=''
    if [ -n "$lfile" ]; then
        file="$dir/${lfile##*/}"
        echo "==> Copiando ${lfile##*/} desde tu carpeta…"
        cp "$lfile" "$file" || { echo "No se ha podido copiar (¿NAS?)." >&2; rm -rf "$tmp"; return 1; }
        if [ -n "$lsha" ]; then cp "$lsha" "$dir/" && sumf=${lsha##*/}
        elif [ -n "$sha" ]; then curl -fsSL --retry 3 -o "$dir/${sha##*/}" "$sha" && sumf=${sha##*/}; fi
    else
        file="$dir/${url##*/}"
        echo "==> Descargando ${url##*/}…"
        curl -fL -C - --retry 5 -o "$file" "$url" || { echo "Falló la descarga (repite: se reanuda)." >&2; rm -rf "$tmp"; return 1; }
        [ -n "$sha" ] && curl -fsSL --retry 3 -o "$dir/${sha##*/}" "$sha" && sumf=${sha##*/}
    fi
    if [ -n "$sumf" ]; then
        (cd "$dir" && sha256sum -c "$sumf") ||
            { echo "El SHA-256 NO coincide: no se instala. Borra $dir y repite." >&2; rm -rf "$tmp"; return 1; }
    else
        echo "Aviso: no hay SHA-256 de esta versión; no se puede comprobar el paquete."
        yesno "¿Seguir de todos modos?" N || { rm -rf "$tmp"; return 1; }
    fi
    # a download goes to your folder too, so it stays installable when the author withdraws it
    if [ -z "$lfile" ] && [ -n "$IMG_LOCAL" ]; then
        local keep=${IMG_LOCAL%%:*}/$tag
        if yesno "¿Guardar también el paquete en $keep (por si lo retiran de GitHub)?" S; then
            mkdir -p "$keep" && cp "$file" "$keep/" && { [ -z "$sumf" ] || cp "$dir/$sumf" "$keep/"; } &&
                cp "$tmp/notes" "$keep/NOTAS.md" && echo "    Guardado en $keep." ||
                echo "    No se ha podido guardar en $keep (sigue la actualización)." >&2
        fi
    fi
    rm -rf "$tmp"
    echo "==> Descomprimiendo…"
    case $file in *.tar.gz) tar xzf "$file" -C "$dir" ;; *) tar xJf "$file" -C "$dir" ;; esac || return 1
    local up script=update.sh; [ "$type" = quick ] && script=install.sh
    up=$(find "$dir" -maxdepth 2 -name "$script" | head -1)
    [ -n "$up" ] || { echo "No encuentro $script en el paquete." >&2; return 1; }
    # the author's update.sh up to v2.4 only installs a bundle whose kernel has the running kernel's name
    local bk; bk=$(cat "$(dirname "$up")/KERNEL" 2>/dev/null)
    if [ -n "$bk" ] && [ "$bk" != "$(uname -r)" ] && ! grep -q 'OLD=\$(uname -r)' "$up"; then
        echo "El actualizador de $tag solo se instala sobre su kernel ($bk) y ahora tienes $(uname -r)." >&2
        if img_snap_list | awk -F'\t' -v k="$bk" '$3 == k { f = 1 } END { exit !f }'; then
            echo "Tienes una copia guardada con ese kernel: vuelve antes a ella (opción 17 → volver), apaga, arranca" >&2
            echo "con el cargador y repite esto." >&2
        else echo "No hay ninguna copia guardada con ese kernel: así no se puede instalar." >&2; fi
        echo "Los ficheros descargados siguen en $dir." >&2
        return 1
    fi
    echo "==> Copia de la imagen actual (para poder volver a ella con la opción 17)…"
    img_snap_take "$(dirname "$up")" ||
        { yesno "No se ha podido guardar la copia. ¿Actualizar de todos modos (sin poder volver)?" N || return 1; }

    echo "==> Ejecutando el actualizador del autor…"
    bash "$up" 2>&1 | tee "$log"; rc=${PIPESTATUS[0]}
    if [ "$rc" != 0 ] || { [ "$type" = full ] && ! grep -q '^DONE' "$log"; }; then
        echo; echo "${R}La actualización NO terminó bien.${N} Los ficheros siguen en $dir." >&2
        save_output "$log" "update-$tag.log" "la salida de la actualización (para revisarla o pedir ayuda)"
        return 1
    fi
    echo; echo "${G}Actualizado a $tag.${N} Para deshacerlo (con este comando, antes de apagar o tras arrancar):"
    grep -i 'undo' "$log" | sed 's/^/  /'
    save_output "$log" "update-$tag.log" "la salida de la actualización (incluye ese comando para deshacerla)"

    yesno "¿Borrar la descarga ($(du -sh "$dir" | cut -f1), en $dir)?" S && rm -rf "$dir"
    local olds; olds=$(sudo ls -1d /var/lib/ps5-update-backup/*/ 2>/dev/null | sort | head -n -1)
    if [ -n "$olds" ]; then
        echo "Copias de actualizaciones anteriores (la última, la de ahora, se queda):"
        for o in $olds; do echo "  $(sudo du -sh "$o" | cut -f1)  $o"; done
        yesno "¿Borrarlas?" N && sudo rm -rf $olds
    fi

    echo; echo "== Ajustes tras la actualización =="
    VERSION=${tag#v}
    STATUS_ONLY=1 ALL=0 ONLY=''; setup_run; STATUS_ONLY=0
    echo
    echo "Ahora hay que APAGAR y arrancar con el cargador (no reiniciar: el kernel nuevo necesita un arranque en frío)."
    yesno "¿Apagar ahora?" N && sudo poweroff
    return 0
}

img_local_add() {                        # asks for a folder with downloaded releases and adds it to IMG_LOCAL
    local d
    say "Una carpeta con versiones descargadas de la imagen: los ficheros tal como vienen en la release" \
        "(ps5-bazzite-deck-<versión>-update.tar.xz con su .sha256, o ps5-quick-<versión>.tar.gz), en ella o hasta" \
        "3 niveles por debajo (p. ej. <carpeta>/v1.8.4/…). Puede estar en el NAS (montado con el bloque nas)."
    read -r -e -p "Carpeta: " d || return 1
    d=${d%/}; d=${d/#\~/$HOME}
    [ -n "$d" ] && [ -d "$d" ] || { echo "No existe: $d" >&2; return 1; }
    case ":$IMG_LOCAL:" in *":$d:"*) echo "Ya está en la lista."; return 0 ;; esac
    remember IMG_LOCAL "${IMG_LOCAL:+$IMG_LOCAL:}$d"
    echo "Añadida. Las descargas de GitHub también se ofrecerán guardar en ${IMG_LOCAL%%:*}."
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
        { echo "No encuentro la partición de arranque (etiqueta «boot»): ¿está la memoria USB?" >&2; return 1; }
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
    [ "$free" -gt "$need" ] || { echo "Hacen falta $((need / 1024)) MB libres en /var y hay $((free / 1024))." >&2; return 1; }
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
    echo "    Guardada: $SNAP ($(sudo du -sh "$SNAP" | cut -f1)): v${VERSION:-?}, kernel $k."
    # if even the new kernel doesn't start, nothing on the console can help: the current one also goes to the
    # boot partition (FAT: any computer reads it), with the steps in LEEME.txt
    if [ -n "$bundle" ]; then
        local sz; sz=$(sudo find /efi -maxdepth 1 -type f ! -name '*.txt' -exec du -ck {} + 2>/dev/null | tail -1 | cut -f1)
        if [ "$(df --output=avail -k /efi | tail -1)" -gt $(( ${sz:-0} + 30000 )) ]; then
            sudo rm -rf "/efi/$IMG_PREV_EFI" && sudo mkdir -p "/efi/$IMG_PREV_EFI" &&
                sudo find /efi -maxdepth 1 -type f -exec cp --preserve=timestamps {} "/efi/$IMG_PREV_EFI/" \; &&
                printf '%s\r\n' "Copia de la imagen v${VERSION:-?} (kernel $k), guardada por ps5-bazzite-toolbox el $(date '+%Y-%m-%d %H:%M')" \
                    "antes de actualizar. Si la version nueva no arranca:" \
                    "  1. Conecta esta memoria USB a un ordenador." \
                    "  2. Copia los ficheros de esta carpeta a la raiz de la particion (sustituyendo los que hay)." \
                    "  3. Vuelve a ponerla en la PS5 y arranca con el cargador: arrancara el kernel $k." \
                    "  4. Ya en Linux, ejecuta la caja de herramientas, opcion 17 -> volver, para dejarlo todo como estaba." |
                    sudo tee "/efi/$IMG_PREV_EFI/LEEME.txt" >/dev/null &&
                echo "    Y el kernel actual, en la partición de arranque: /efi/$IMG_PREV_EFI (por si el nuevo no arranca; ver LEEME.txt)."
        else
            echo "    (No cabe una copia del kernel en la partición de arranque: si el nuevo no arranca, habrá que reflashear.)"
        fi
    fi
    # keep the newest 3 (each one is the size of the kernel's modules); not while going back (it could be that one)
    local olds=''; [ -z "$bundle" ] || olds=$(img_snap_list | tail -n +4 | cut -f1)
    if [ -n "$olds" ]; then
        echo "    Copias más antiguas (se guardan las 3 últimas):"
        for f in $olds; do echo "      $(sudo du -sh "$f" | cut -f1)  $f"; done
        yesno "    ¿Borrarlas?" S && sudo rm -rf $olds
    fi
    return 0
}
img_rollback() {
    local list n i c d v k dt cur_k f st
    [ $IS_BOOTC = 1 ] && { bootc_menu rollback; return; }
    need_sudo || return 1
    list=$(img_snap_list)
    if [ -z "$list" ]; then
        echo "No hay copias guardadas. Se hacen solas al actualizar con la opción 17 (desde la v1.5.0 de esta caja)."
        local bk; bk=$(sudo ls -1d /var/lib/ps5-update-backup/*/ 2>/dev/null | sort | tail -1)
        [ -n "$bk" ] && echo "Queda la copia del actualizador del autor ($bk): solo kernel y módulos. Su comando para" \
            "deshacer está en el registro de la actualización (update-<versión>.log), si lo guardaste."
        return 0
    fi
    cur_k=$(uname -r)
    printf '\nAhora: %s, kernel %s\nCopias guardadas (cada una es la imagen tal como estaba antes de una actualización):\n' "${VERSION:+v$VERSION}" "$cur_k"
    i=0
    while IFS=$'\t' read -r d v k dt; do
        i=$((i + 1))
        printf '  %d) %-8s kernel %-14s guardada el %s  (%s)\n' "$i" "$v" "$k" "$dt" "$(sudo du -sh "$d" | cut -f1)"
    done <<<"$list"
    read -rp "¿A cuál vuelves? (número, Intro = 1, 0 = cancelar): " c
    case ${c:-1} in 0) return 0 ;; *[!0-9]*) echo "Opción no válida"; return 1 ;; esac
    IFS=$'\t' read -r d v k dt < <(sed -n "${c:-1}p" <<<"$list")
    [ -n "${d:-}" ] || { echo "Opción no válida"; return 1; }
    echo
    say "Vuelve a $v (kernel $k), tal como estaba el $dt: kernel, initrd, cmdline.txt, módulos, los scripts y" \
        "servicios de la imagen y /etc/ps5-bazzite-deck. Lo que la versión actual añadió se borra."
    say "Los ajustes de esas partes cambiados después de esa fecha (p. ej. con el bloque gpu40 o fans) vuelven" \
        "a como estaban; revísalos luego con la opción 14. Bazzite, Steam, juegos y tus ficheros no se tocan."
    say "Antes se guarda una copia de cómo está ahora, así que también esto se puede deshacer (opción 17 → volver)."
    say "EN PRUEBAS: la vuelta aún no se ha probado en una consola de verdad. Si algo falla, la copia de antes" \
        "queda en $IMG_SNAPS y el kernel anterior, si cupo, en /efi/$IMG_PREV_EFI."
    yesno "¿Volver a $v?" N || return 0
    efi_ready || return 1
    echo "==> Copia de la imagen actual…"
    img_snap_take '' "antes de volver a $v" "$d" || { yesno "Sin esa copia no podrás deshacerlo. ¿Seguir?" N || return 1; }
    echo "==> Restaurando $v…"
    sudo cp -r --preserve=timestamps "$d/efi/." /efi/ ||   # FAT: no owners to keep (cp -a would fail)
        { echo "Falló al copiar a la partición de arranque: NO apagues; pide ayuda." >&2; return 1; }
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
        yesno "¿Borrar los módulos del kernel $cur_k? (ya no arranca; $(sudo du -sh "/usr/lib/modules/$cur_k" | cut -f1))" S &&
            sudo rm -rf "/usr/lib/modules/$cur_k"
    fi
    sync
    VERSION=${v#v}
    sudo test -e /etc/ps5-bazzite-deck/warm-reboot && sudo touch /run/ps5-reboot-to-ps5   # the kernel needs a cold start
    echo; echo "${G}Vuelto a $v.${N} Para deshacerlo: opción 17 → volver, y elige la copia «antes de volver a $v»."
    echo "Ahora hay que APAGAR y arrancar con el cargador (el kernel cambia: hace falta un arranque en frío)."
    yesno "¿Apagar ahora?" N && sudo poweroff
    return 0
}
# --- bootc: the image is updated, rolled back and switched by bootc itself -----------------------------------------
BOOTC_IMG=ghcr.io/vivalavent/ps5-bazzite-bootc
bootc_ref() { sudo bootc status --format=json 2>/dev/null | jq -r '.spec.image.image // .status.booted.image.image.image // empty'; }
bootc_after() {
    echo "  Al reiniciar, la PS5 pasa primero por su sistema: luego lanza el cargador bazzite-bootc-loader como siempre."
    echo "  Si la nueva no te convence: opción 17 → volver a la anterior (sudo bootc rollback)."
}
bootc_v25_fix() {                        # v2.5's image breaks every update (its notes for v2.5.1): offer the author's fix
    [ "$VERSION" = 2.5 ] || return 0
    grep -qs 'No greenboot rollbacks' /etc/systemd/system/greenboot-set-rollback-trigger.service && return 0
    section
    say "La v2.5 tiene un fallo: toda actualización termina en «Failed to start ostree-finalize-staged.service»."
    say "El arreglo del autor (notas de la v2.5.1) cambia el servicio greenboot-set-rollback-trigger por uno que"
    say "no hace nada, una vez; las versiones siguientes lo respetan."
    say "DESHACER: sudo rm /etc/systemd/system/greenboot-set-rollback-trigger.service; sudo systemctl daemon-reload"
    yesno "¿Lo aplico ahora (hace falta para actualizar)?" S || return 1
    sudo rm -f /etc/systemd/system/greenboot-set-rollback-trigger.service
    printf '[Unit]\nDescription=No greenboot rollbacks on the PS5\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/true\nRemainAfterExit=yes\n' |
        sudo tee /etc/systemd/system/greenboot-set-rollback-trigger.service >/dev/null &&
        sudo systemctl daemon-reload && sudo systemctl start ostree-finalize-staged.service && echo "  Listo para actualizar."
}
bootc_menu() {                           # bootc_menu [upgrade|rollback|switch [TAG]]
    local c=${1:-} tag=${2:-} ref tags
    need_sudo || return 1
    ref=$(bootc_ref)
    echo
    echo "${B}Imagen bootc${N}: el sistema entero es una imagen; bootc la actualiza y guarda la anterior en el disco."
    echo "  Sigue: ${ref:-?}  (stable = las versiones estables, cada semana; vX.Y = esa versión fija)"
    sudo bootc status 2>/dev/null | grep -E '^(●|  )?(Booted|Staged|Rollback)|image:|Version' | sed 's/^/  /' | head -12
    if [ -z "$c" ]; then
        echo "  1) Actualizar: descarga la siguiente del canal que sigues (sudo bootc upgrade); entra al reiniciar"
        echo "  2) Volver a la versión anterior (sudo bootc rollback); entra al reiniciar"
        echo "  3) Cambiar de canal o fijar una versión (sudo bootc switch $BOOTC_IMG:<etiqueta>)"
        read -rp "Elige (0 = cancelar): " c
        case $c in 1) c=upgrade ;; 2) c=rollback ;; 3) c=switch ;; *) return 0 ;; esac
    fi
    case $c in
        upgrade) bootc_v25_fix || return 1
                 sudo bootc upgrade && bootc_after ;;
        rollback) section
                  say "Al reiniciar arranca la versión que había antes de la última actualización o cambio; la de"
                  say "ahora se queda como «anterior», así que esto también se deshace igual. Tus ficheros no cambian."
                  yesno "¿Vuelvo a la anterior?" S && sudo bootc rollback && bootc_after ;;
        switch) if [ -z "$tag" ]; then
                    tags=$(curl -fsSL --retry 2 "https://api.github.com/repos/$REPO/releases?per_page=100" 2>/dev/null |
                        jq -r '.[] | .tag_name + (if .prerelease then " (preliminar)" else "" end)' 2>/dev/null |
                        awk '{ v = $1; sub(/^v/, "", v); split(v, a, "."); if (a[1] > 2 || (a[1] == 2 && a[2] >= 5)) print "  " $0 }')
                    echo "  Etiquetas: stable (recomendada) o una versión de bootc:"; echo "${tags:-  (sin red: no puedo listarlas)}"
                    read -rp "  ¿Cuál? (Intro = stable): " tag; tag=${tag:-stable}
                fi
                bootc_v25_fix || return 1
                section
                say "Cambia la imagen que sigue esta consola a $BOOTC_IMG:$tag y la descarga; entra al reiniciar."
                say "Con una versión fija (vX.Y) ya no recibe las semanales: vuelve con «stable»."
                say "DESHACER: opción 17 → volver a la anterior, o cambiar otra vez."
                yesno "¿Cambio a $tag?" S && sudo bootc switch "$BOOTC_IMG:$tag" && bootc_after ;;
    esac
}

img_menu() {
    [ $IS_BOOTC = 1 ] && { bootc_menu; return; }
    local c n; n=$(img_snap_list | wc -l)
    echo "  1) Instalar una versión de GitHub (la más nueva u otra, también anterior)"
    echo "  2) Volver a como estaba la imagen antes de una actualización ($n copia(s) guardada(s)) [EN PRUEBAS]"
    echo "  3) Guardar ahora una copia de la imagen tal como está (la opción 1 ya la hace sola antes de instalar)"
    read -rp "Elige (Intro = 1, 0 = cancelar): " c
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

PP_ID=ru.linux_gaming.PortProton
PP="${PORT_WINE_PATH:-$HOME/.var/app/$PP_ID}"
STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
COLLECTION_SCRIPT="${COLLECTION_SCRIPT:-$HOME/portproton-collection.sh}"
TOOLBOX_CMD=${TOOLBOX_CMD:-} ISO_LIST=${ISO_LIST:-} ISO_SB=${ISO_SB:-}
EXE= NAME= TEST=1 YES=0 CHANGE=0

say() { printf '%s\n' "$*"; }
ask() {                                   # ask "question" [default S|N] -> 0 for yes
    local def=${2:-S} ans
    [ $YES = 1 ] && { [ "$def" = S ]; return; }
    read -r -p "$1 [$([ "$def" = S ] && echo S/n || echo s/N)] " ans
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
        -*) say "Opción desconocida: $1" >&2; exit 2 ;;
        *) EXE=$1; shift ;;
    esac
done
[ -n "$EXE" ] || { say "Falta la ruta del .exe del juego." >&2; exit 2; }
[ -f "$EXE" ] || { say "No existe: $EXE" >&2; exit 1; }
EXE=$(realpath "$EXE")
flatpak info "$PP_ID" >/dev/null 2>&1 || { say "PortProton (flatpak $PP_ID) no está instalado." >&2; exit 1; }
[ -d "$PP/data/scripts" ] || { say "No encuentro PortProton en $PP (ábrelo una vez)." >&2; exit 1; }

# --- name -------------------------------------------------------------------------------------------
# An existing PortProton shortcut for this exe keeps its name; otherwise the game's folder, skipping
# engine folders (Binaries/Win64...) and a "(2025)" year: ".../Tempest Rising (2025)/Tempest Rising/Tempest.exe"
existing=$(grep -l -F "\"$EXE\"" "$PP"/*.desktop 2>/dev/null | grep -v '/PortProton.desktop$' | head -1 || true)
[ -n "$NAME" ] || NAME=$(awk -F'\t' -v e="$EXE" '$2 == e && $3 != "" { n = $3 } END { print n }' "$ISO_LIST" 2>/dev/null || true)
[ -n "$NAME" ] || NAME=$({ grep -l -F "\"$EXE\"" "$PP"/steam_scripts/*.sh 2>/dev/null | head -1 | xargs -r -d '\n' basename -s .sh; } || true)
[ $CHANGE = 0 ] || [ -n "$NAME$existing" ] || { say "Este juego no está instalado: instálalo primero." >&2; exit 1; }
if [ -z "$NAME" ] && [ -n "$existing" ]; then
    NAME=$(sed -n 's/^Name=//p' "$existing" | head -1)
fi
if [ -z "$NAME" ]; then
    d=$(dirname "$EXE")
    while [[ $(basename "$d") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do d=$(dirname "$d"); done
    NAME=$(basename "$d" | sed -E 's/ *\([0-9]{4}\)$//')
fi
section "Juego"
say "Ejecutable: $EXE"
if [ $YES = 0 ] && [ $CHANGE = 0 ]; then
    # editable proposal in a terminal; Enter (or no terminal) keeps it
    if [ -t 0 ]; then read -r -e -i "$NAME" -p "Nombre (Steam, escritorio y PortProton): " ans
    else read -r -p "Nombre [$NAME]: " ans || true; fi
    NAME=${ans:-$NAME}
fi
NAME=$(printf '%s' "$NAME" | tr -d '`"'"'"'!/')
[ -n "$NAME" ] || { say "Nombre vacío." >&2; exit 1; }
[ -n "$existing" ] && say "PortProton ya tiene un acceso para este exe: $(basename "$existing")"

# --- isolation --------------------------------------------------------------------------------------
PPDB="$EXE.ppdb"
SH="$PP/steam_scripts/$NAME.sh"
iso_cur() { awk -F'\t' -v e="$EXE" '$2 == e { l = $1 } END { print (l ? l : "normal") }' "$ISO_LIST" 2>/dev/null || echo normal; }
new_pfx() { printf '%s' "$NAME" | tr ' ' '_' | tr -cd 'A-Za-z0-9_-' | tr '[:lower:]' '[:upper:]' | cut -c1-40; }   # PortProton upper-cases them
pfx_of() { sed -n 's/^export PW_PREFIX_NAME="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$PPDB" 2>/dev/null | tail -1 || true; }
CUR=normal LEVEL=normal UNDO=()
if [ -n "$TOOLBOX_CMD" ] && [ -n "$ISO_LIST" ] && [ -n "$ISO_SB" ]; then
    CUR=$(iso_cur)
    section "Cómo se ejecuta"
    say "1) Normal: con acceso a todo (tu carpeta personal, el NAS, tus otros juegos). Para juegos de tiendas fiables."
    say "2) Aislado con red: sin tu carpeta personal, el NAS ni tus otros juegos; tu PortProton en solo lectura,"
    say "   con un prefijo propio. Con red (juegos online, launchers)."
    say "3) Aislado sin red: lo mismo, sin red. Lo más seguro para un juego de origen dudoso."
    say "Los aislados no van en la lista de juegos de PortProton (desde ahí se abrirían sin aislar): escritorio y Steam."
    case $CUR in red) def=2 ;; sin-red) def=3 ;; *) if [ -n "$existing" ] || [ -f "$SH" ]; then def=1; else def=2; fi ;; esac
    [ "$CUR" != normal ] || [ -z "$existing" ] || say "Ahora mismo es normal."
    [ "$CUR" = normal ] || say "Ahora mismo: aislado $([ "$CUR" = red ] && echo con red || echo sin red)."
    c=$def
    [ $YES = 1 ] || { read -r -p "¿Cuál? [1-3, Intro = $def] " c || true; c=${c:-$def}; }
    case $c in 1) LEVEL=normal ;; 3) LEVEL=sin-red ;; *) LEVEL=red ;; esac
    [ $CHANGE = 0 ] || [ "$LEVEL" != "$CUR" ] || { say "Sigue igual: no cambio nada."; exit 0; }
fi
GTOP=$(dirname "$EXE")
while [[ $(basename "$GTOP") =~ ^([Bb]in(aries)?|[Ww]in(32|64)|x64|x86|[Gg]ame|[Rr]etail)$ ]]; do GTOP=$(dirname "$GTOP"); done
[ -d "$GTOP/../Engine" ] && GTOP=$(dirname "$GTOP")
# the folder kept for it earlier wins over the guess
ROOT_SAVED=$(awk -F'\t' -v e="$EXE" '$2 == e && $4 != "" { r = $4 } END { print r }' "$ISO_LIST" 2>/dev/null || true)
[ -z "$ROOT_SAVED" ] || GTOP=$ROOT_SAVED
if [ "$LEVEL" != normal ]; then
    say "Carpeta del juego que podrá ver (y escribir) aislado: $GTOP"
    say "  Si sus datos están más arriba (p. ej. el .exe va en una subcarpeta como sp26/ o bin/), pon la de arriba."
    if [ $YES = 0 ] && [ -t 0 ]; then read -r -e -i "$GTOP" -p "Carpeta del juego: " ans || true
    elif [ $YES = 0 ]; then read -r -p "Carpeta del juego [$GTOP]: " ans || true; fi
    GTOP=$(realpath -m "${ans:-$GTOP}"); ans=
    case $EXE in "$GTOP"/*) ;; *) say "El .exe no está dentro de $GTOP." >&2; exit 1 ;; esac
    case $HOME/ in "$GTOP"/*) say "El juego está directamente en $GTOP: muévelo a su propia carpeta (p. ej. ~/Juegos/Juego/) para aislarlo." >&2; exit 1 ;; esac
    case $GTOP/ in "$PP"/*|/var/mnt/*|/mnt/*|/run/media/*)
        say "Para aislarlo, la carpeta del juego ($GTOP) tiene que ser una carpeta local propia (p. ej. ~/Juegos/Juego/)," >&2
        say "no PortProton, el NAS ni un disco externo: queda escribible para él. Cópialo allí y añádelo desde la copia." >&2; exit 1 ;;
    esac
fi
# The prefix follows the level: normal ones live in PortProton, isolated ones in ISO_SB (moved, asking).
PFX=$(pfx_of)
if [ "$LEVEL" != "$CUR" ] && { [ "$LEVEL" = normal ] || [ "$CUR" = normal ]; }; then
    [ -f "$PPDB" ] && cp -p "$PPDB" "$PPDB.bak-iso" && UNDO+=("mv -f '$PPDB.bak-iso' '$PPDB'")
    mkdir -p "$ISO_SB/data/prefixes"
    if [ "$LEVEL" != normal ]; then
        if [ -n "$PFX" ] && [ "$PFX" != DEFAULT ] && [ "$PFX" != DOTNET ] && [ -d "$PP/data/prefixes/$PFX" ] &&
            ask "Su prefijo $PFX (con sus partidas) está en tu PortProton. ¿Lo paso a la copia aislada? (si otro juego lo usa, dejará de encontrarlo)" S; then
            mv "$PP/data/prefixes/$PFX" "$ISO_SB/data/prefixes/" && UNDO+=("mv '$ISO_SB/data/prefixes/$PFX' '$PP/data/prefixes/'")
        else
            [ -n "$PFX" ] && say "Estaba en el prefijo $PFX, que se queda en tu PortProton con sus partidas (cópialas a mano si las quieres)."
            PFX=$(new_pfx)
            say "Prefijo aislado nuevo: $PFX."
        fi
    elif [ -n "$PFX" ] && [ -d "$ISO_SB/data/prefixes/$PFX" ]; then
        if [ -d "$PP/data/prefixes/$PFX" ]; then
            say "Tu PortProton ya tiene un prefijo $PFX: el aislado se queda en $ISO_SB/data/prefixes/$PFX."
        elif ask "Su prefijo aislado $PFX (con sus partidas) ¿pasa a tu PortProton? Lo que el juego haya dejado en él dejará de estar aislado" S; then
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
        printf '[Desktop Entry]\nName=%s\nComment=Aislado (ps5-bazzite-toolbox)\nExec=bash "%s" --run "%s"\nType=Application\nCategories=Game\nIcon=%s\n' \
            "$NAME" "$TOOLBOX_CMD" "$EXE" "$ICON" >"$1"
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
# Aislado ($LEVEL) por ps5-bazzite-toolbox: lo lanza en el Flatpak de PortProton con menos permisos.
exec bash "$TOOLBOX_CMD" --run "$EXE"
EOF
    fi
    chmod u+x "$SH"
}
undo_level() {                            # stopped after changing the level: put the prefix and .ppdb back
    local i
    for ((i = ${#UNDO[@]} - 1; i >= 0; i--)); do eval "${UNDO[$i]}"; done
    [ ${#UNDO[@]} = 0 ] || say "Deshecho el cambio de aislamiento (prefijo y .ppdb como estaban)."
}

# --- 1. test ----------------------------------------------------------------------------------------
new_prefix() { [ "$LEVEL" != normal ] && [ ! -d "$ISO_SB/data/prefixes/$PFX" ]; }   # this test would make it
NEW_PFX=0; new_prefix && NEW_PFX=1
section "1. Probar el juego con PortProton"
say "Se abre PortProton con este exe: elige la versión de Proton si hace falta, pulsa Iniciar, prueba el juego"
say "y ciérralo (el juego y la ventana de PortProton). PortProton guarda sus ajustes en $(basename "$PPDB")."
[ "$LEVEL" = normal ] || say "Se abre aislado ($([ "$LEVEL" = red ] && echo con red || echo sin red)), con el prefijo $PFX: elígelo si te pregunta."
if [ "$LEVEL" != normal ]; then
    say "Antes, si no te fías del juego, busca su huella en VirusTotal (sin subir nada):"
    say "  https://www.virustotal.com/gui/file/$(sha256sum "$EXE" | cut -d' ' -f1)"
    say "Aislado no es una máquina virtual: comparte pantalla, sonido y mandos. Cierra Steam y el navegador antes de"
    say "probarlo (un programa de X11 puede leer lo que se teclea en otras ventanas X11), y no le des tu contraseña."
fi
if [ $TEST = 1 ] && ask "¿Abrirlo ahora?" "$([ -f "$PPDB" ] && [ "$LEVEL" = "$CUR" ] && echo N || echo S)"; then
  while :; do
    PPLS=$(ls -A "$PP")
    if [ "$LEVEL" = normal ]; then flatpak run "$PP_ID" "$EXE" >/dev/null 2>&1 || true
    else bash "$TOOLBOX_CMD" --run "$EXE" --gui --level "$LEVEL" --root "$GTOP" || true; fi
    if [ "$LEVEL" != normal ]; then            # only the top of PortProton's folder stays writable in the sandbox
        NEWF=$(comm -13 <(sort <<<"$PPLS") <(ls -A "$PP" | sort) || true)
        if [ -n "$NEWF" ]; then
            say "Ojo: han aparecido ficheros nuevos en tu PortProton ($PP):"; printf '  %s\n' "$NEWF"
            if ask "¿Los borro? (un .desktop nuevo ahí saldría en la lista de PortProton, sin aislar)" S; then
                while IFS= read -r f; do rm -rf "${PP:?}/$f"; done <<<"$NEWF"
            fi
        fi
    fi
    # PortProton closes after preparing a new prefix (recommended libraries...): "r" opens it again
    ans=s
    [ $YES = 1 ] || { read -r -p "¿Ha arrancado bien? (s = sí, sigue · r = vuelve a abrirlo · n = no, para) [S/r/n] " ans || ans=; }
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
            if ask "¿Borro el prefijo aislado $p ($(du -sh "$ISO_SB/data/prefixes/$p" 2>/dev/null | cut -f1)), que ha usado esta prueba?" S; then
                rm -rf "${ISO_SB:?}/data/prefixes/$p"
            fi
        done
    fi
    if [ "$CUR" = normal ] && [ -z "$existing" ] && [ ! -f "$SH" ] && ask "¿No te convence? ¿Borro la carpeta del juego ($GTOP, $(du -sh "$GTOP" 2>/dev/null | cut -f1))?" N; then
        read -r -p "  Para confirmar, escribe el nombre de la carpeta ($(basename "$GTOP")): " c || c=
        if [ "$c" = "$(basename "$GTOP")" ]; then rm -rf -- "$GTOP" && say "  Borrada."; else say "  No coincide: no borro nada."; fi
    fi
    [ $PPDB_NEW = 0 ] || rm -f "$PPDB"
    say "Parado. $([ $CHANGE = 1 ] && echo "No se ha cambiado nada." || echo "No se ha añadido nada.")"; exit 0
  done
fi
[ -z "$ISO_LIST" ] || {                    # keep the game and its level ("Mis juegos" lists them)
    tmp=$(mktemp); awk -F'\t' -v e="$EXE" '$2 != e' "$ISO_LIST" 2>/dev/null >"$tmp" || true
    printf '%s\t%s\t%s\t%s\n' "$LEVEL" "$EXE" "$NAME" "$([ "$LEVEL" = normal ] || echo "$GTOP")" >>"$tmp"
    mkdir -p "$(dirname "$ISO_LIST")"; mv "$tmp" "$ISO_LIST"; rm -f "$PPDB.bak-iso"
}
[ -f "$PPDB" ] || { say "No hay $PPDB: abre el juego una vez con PortProton antes (sin --no-test)." >&2; exit 1; }
# shellcheck disable=SC1090
PORTPROTON_NAME=$(. "$PPDB" >/dev/null 2>&1; echo "${PORTPROTON_NAME:-}")
PW_WINE_USE=$(. "$PPDB" >/dev/null 2>&1; echo "${PW_WINE_USE:-}")
say "Ajustes de PortProton: Proton ${PW_WINE_USE:-por defecto}, nombre interno ${PORTPROTON_NAME:-?}"

# icon: PortProton names it after PORTPROTON_NAME, spaces -> _, without ! % $ & <
png=${PORTPROTON_NAME:-$(basename "${EXE%.*}")}; png=${png// /_}; png=$(printf '%s' "$png" | tr -d '!%$&<')
ICON="$PP/data/img/$png.png"
# an isolated run leaves the icon in the copy, which the next sync clears: keep it next to the others
[ -f "$ICON" ] || [ ! -f "$ISO_SB/data/img/$png.png" ] || cp "$ISO_SB/data/img/$png.png" "$ICON"
[ -f "$ICON" ] || { say "(sin icono propio en data/img: se usa el de PortProton)"; ICON=$PP_ID; }

# --- --change: only the shortcuts and the Steam script follow the new level ----------------------------
if [ $CHANGE = 1 ]; then
    section "Accesos y Steam"
    DESK_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
    if [ "$LEVEL" != normal ]; then
        [ -z "$existing" ] || { rm -f "$existing"; say "Quitado de la lista de juegos de PortProton (desde ahí se abriría sin aislar)."; }
    else
        desk_entry "$PP/$NAME.desktop"; say "En la lista de juegos de PortProton: $PP/$NAME.desktop"
    fi
    for f in "$DESK_DIR/$NAME.desktop" "$HOME/.local/share/applications/$NAME.desktop"; do
        [ -f "$f" ] && desk_entry "$f" && say "Acceso actualizado: $f"
    done
    if [ -f "$SH" ]; then
        write_sh; say "Steam: es el mismo juego (tiempo jugado, carátulas y colección siguen); ahora se lanza $([ "$LEVEL" = normal ] && echo normal || echo aislado)."
    else
        say "No está en Steam (no hay $SH)."
    fi
    section "Listo"
    say "«$NAME» queda $(case $LEVEL in normal) echo normal ;; red) echo "aislado con red" ;; *) echo "aislado sin red" ;; esac)."
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
    section "Idioma"
    for f in "${LFILES[@]}"; do
        rel=${f#"$GROOT"/}
        if [[ $f == *force_language.txt ]]; then cur=$(tr -d '\r\n ' < "$f")
        else cur=$(grep -a -i -m1 -E '^[[:space:]]*language[[:space:]]*=' "$f" | sed 's/^[^=]*=[[:space:]]*//' | tr -d '\r '); fi
        if [ -z "$cur" ]; then say "$rel: no fija idioma."; continue; fi
        if [ "$cur" = "$WANT" ]; then say "$rel: idioma $cur (bien)."; continue; fi
        say "$rel: el emulador de Steam le dice al juego que el idioma es «$cur»; el del sistema es «$WANT»."
        say "  Muchos juegos solo muestran ese idioma (no tienen selector propio). Copia en $(basename "$f").bak-<fecha>."
        if ask "  ¿Cambiarlo a «$WANT»?" S; then
            cp -p "$f" "$f.bak-$(date +%Y%m%d-%H%M%S)"
            if [[ $f == *force_language.txt ]]; then printf '%s\n' "$WANT" > "$f"
            else sed -i -E "0,/^[[:space:]]*[Ll][Aa][Nn][Gg][Uu][Aa][Gg][Ee][[:space:]]*=/s/^([[:space:]]*[Ll][Aa][Nn][Gg][Uu][Aa][Gg][Ee][[:space:]]*=[[:space:]]*)[^\r]*/\1$WANT/" "$f"; fi
            say "  Hecho: $(grep -a -i -m1 -E '^[[:space:]]*language[[:space:]]*=|^[a-z]+$' "$f" | tr -d '\r')"
        fi
    done
    if [ -n "$LPACK" ]; then
        say "El juego trae paquetes de idioma en «${LPACK#"$GROOT"/}»: $(ls "$LPACK" | tr '\n' ',' | sed 's/,$//; s/,/, /g')."
        # the pack for the system language: its folder name, as these packs name them ("Spanish - Spain"...)
        case $WANT in
            spanish) pat='^(spanish( - spain)?|español|espanol|es[-_]es)$' ;; latam) pat='latin|^es[-_](mx|419)$' ;;
            brazilian) pat='brazil|^pt[-_]br$' ;; schinese) pat='simplified' ;; tchinese) pat='traditional' ;;
            koreana) pat='^korean' ;; *) pat="^$WANT" ;;
        esac
        mine=$(ls "$LPACK" | grep -i -E -m1 "$pat" || true)
        if [ -z "$mine" ]; then
            say "  No veo el de «$WANT»: si está con otro nombre, copia su contenido encima de la carpeta del juego."
        elif (cd "$LPACK/$mine" && find . -type f | while read -r f; do cmp -s "$f" "$GROOT/$f" || { echo x; break; }; done) | grep -q x; then
            say "  El de tu idioma es «$mine» y no está copiado en el juego (su contenido va encima de la carpeta del juego)."
            if ask "  ¿Copiarlo ahora ($(du -sh "$LPACK/$mine" | cut -f1))?" S; then
                cp -r "$LPACK/$mine/." "$GROOT/" && say "  Copiado."
            fi
        else
            say "  El de tu idioma («$mine») ya está copiado."
        fi
    fi
fi

# --- 2. shortcuts -----------------------------------------------------------------------------------
DESKTOP_FILE="$PP/$NAME.desktop"
DESK_DIR=$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")
section "2. Accesos directos"
if [ "$LEVEL" != normal ]; then
    say "Aislado: va solo en el escritorio ($DESK_DIR/$NAME.desktop), que lo abre aislado. Deshacer: borra ese fichero."
    if [ -n "$existing" ] && ask "  Está en la lista de juegos de PortProton, que lo abriría SIN aislar. ¿Lo quito de ahí?" S; then
        rm -f "$existing"; say "  Quitado: $(basename "$existing")"
    fi
    if ask "¿Crear el acceso del escritorio?" S; then
        mkdir -p "$DESK_DIR"
        desk_entry "$DESK_DIR/$NAME.desktop"
        say "  $DESK_DIR/$NAME.desktop"
    fi
elif say "Crea «$NAME.desktop» en la carpeta de PortProton (su lista de juegos) y en el escritorio ($DESK_DIR),"
    say "igual que los que hace PortProton. Deshacer: borra los dos ficheros."
    ask "¿Crearlos?" S; then
    desk_entry "$DESKTOP_FILE"
    if [ -n "$existing" ] && [ "$existing" != "$DESKTOP_FILE" ]; then
        say "  (el acceso anterior, $(basename "$existing"), se queda; bórralo si sobra)"
    fi
    if ask "  ¿También en el escritorio?" S; then
        mkdir -p "$DESK_DIR" && cp -f "$DESKTOP_FILE" "$DESK_DIR/" && chmod +x "$DESK_DIR/$NAME.desktop"
        say "  $DESK_DIR/$NAME.desktop"
    fi
    say "  $DESKTOP_FILE"
fi

# --- 3. Steam ---------------------------------------------------------------------------------------
section "3. Steam"
if [ -f "$SH" ] && [ "$LEVEL" != "$CUR" ]; then
    write_sh; say "Ya estaba en Steam: $SH lo lanza ahora $([ "$LEVEL" = normal ] && echo normal || echo aislado). Steam no cambia."
fi
say "Crea $SH (lo que lanza Steam$([ "$LEVEL" = normal ] && echo ", igual que el de PortProton" || echo ": la caja de herramientas, aislado")) y lo añade a Steam como juego no-Steam"
say "«$NAME». Steam tiene que estar cerrado: al cerrarse reescribe su lista y borraría el juego nuevo."
say "Deshacer: quitar el juego en Steam (o restaurar shortcuts.vdf.bak-<fecha>) y borrar el .sh."
[ "$LEVEL" = normal ] || [ "$TOOLBOX_CMD" = "$HOME/.local/bin/ps5-bazzite-toolbox" ] ||
    say "Ojo: Steam llamará a $TOOLBOX_CMD; si lo mueves o lo borras, el juego no arranca (instálala: opción 19)."
if ask "¿Añadirlo a Steam?" S; then
    write_sh
    if pgrep -x steam >/dev/null 2>&1; then
        if ask "  Steam está abierto. ¿Cerrarlo ahora?" S; then
            steam -shutdown >/dev/null 2>&1 || true
            for _ in $(seq 1 30); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
        fi
        pgrep -x steam >/dev/null 2>&1 && { say "  Steam sigue abierto: ciérralo y repite (el .sh ya está creado)." >&2; exit 1; }
    fi
    STEAM_DIR="$STEAM_DIR" GAME_NAME="$NAME" GAME_SH="$SH" GAME_ICON="$ICON" GAME_DIR="$(dirname "$EXE")" \
        python3 - <<'PY'
# shortcuts.vdf is binary VDF: parsed into (type, key, value) lists and written back exactly as read
# (checked byte for byte before touching it), plus one new entry.
import glob, os, shutil, struct, sys, time, zlib

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
            raise ValueError(f"tipo VDF 0x{t:02x} desconocido en {i - 1}")
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
    sys.exit("  No encuentro usuarios de Steam en userdata/")
exe_q = f'"{sh}"'
# Steam's own id for a non-Steam game: crc32(exe + name) with the top bit set (artwork in grid/ uses it)
appid = (zlib.crc32((exe_q + name).encode()) | 0x80000000) & 0xFFFFFFFF
for u in users:
    path = os.path.join(u, "config", "shortcuts.vdf")
    if os.path.exists(path):
        data = open(path, "rb").read()
        root, _ = parse(data, 0)
        if dump(root) != data:
            sys.exit(f"  {path}: no lo leo de forma exacta; no lo toco.")
    else:
        root = [(0, b"shortcuts", [])]
    sc = field(root, b"shortcuts")
    if any((field(e, b"exe") or b"").decode("utf-8", "replace").strip('"') == sh for t, k, e in sc if t == 0):
        print(f"  Usuario {os.path.basename(u)}: ya estaba en Steam.")
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
    print(f"  Usuario {os.path.basename(u)}: añadido «{name}» (id {appid}).")
PY
fi

# --- 4. collection ----------------------------------------------------------------------------------
section "4. Colección «PortProton» de Steam"
if [ -x "$COLLECTION_SCRIPT" ] || [ -f "$COLLECTION_SCRIPT" ]; then
    say "Mete el juego en la colección «PortProton» de Steam (lo mismo que esa opción del toolbox)."
    if ask "¿Actualizar la colección?" S; then
        bash "$COLLECTION_SCRIPT" --yes || say "  La colección no se actualizó (mira el mensaje de arriba)."
    fi
else
    say "No encuentro el sincronizador de la colección: se salta."
fi

section "Listo"
say "Terminado con «$NAME». Si lo has añadido a Steam, ábrelo (o el Modo Juego) para verlo."
if ! pgrep -x steam >/dev/null 2>&1 && ask "¿Abrir Steam ahora?" N; then
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

STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
COLLECTION_NAME="${COLLECTION_NAME:-PortProton}"
DRY_RUN=0 YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y|--yes) YES=1 ;;
    *) echo "Opción desconocida: $arg" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$STEAM_DIR/userdata" ]]; then
  echo "No encuentro $STEAM_DIR/userdata" >&2
  exit 1
fi

if [[ $DRY_RUN -eq 0 ]] && pgrep -x steam >/dev/null 2>&1; then
  echo "Steam está abierto. Hay que cerrarlo para que no pise los cambios."
  if [[ $YES -eq 1 ]]; then
    ans=s; echo "Cerrando Steam…"
  else
    read -r -p "¿Cerrar Steam ahora? [s/N] " ans
  fi
  if [[ "$ans" =~ ^[sSyY]$ ]]; then
    steam -shutdown >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      pgrep -x steam >/dev/null 2>&1 || break
      sleep 1
    done
    if pgrep -x steam >/dev/null 2>&1; then
      echo "Steam no se ha cerrado. Ciérralo manualmente y vuelve a intentarlo." >&2
      exit 1
    fi
  else
    echo "Cancelado."
    exit 1
  fi
fi

export STEAM_DIR COLLECTION_NAME DRY_RUN

python3 - <<'PY'
import json, os, shutil, struct, sys, time, zlib, glob

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
            raise ValueError(f"tipo VDF desconocido 0x{t:02x} en offset {i-1}")
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
    print(f"\n== Usuario {os.path.basename(udir)} ==")

    games = sh_shortcuts(vdf)
    for appid, name in sorted(games.items(), key=lambda x: x[1].lower()):
        print(f"  [.sh] {name}  ({appid})")
    if not games:
        print("  (ningún acceso directo .sh)")

    if not os.path.exists(ns_file):
        print(f"  No existe {ns_file}. Abre Steam una vez y crea cualquier colección, luego reintenta.")
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
    print(f"  Colección '{NAME}': +{len(added)} / -{len(removed)} (total {len(new_ids)})")

    if old is not None and not added and not removed:
        print("  Sin cambios.")
        return
    if DRY:
        print("  (dry-run: no se escribe nada)")
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

    print("  ✔ Colección actualizada.")


users = [d for d in glob.glob(os.path.join(STEAM_DIR, "userdata", "*"))
         if os.path.basename(d).isdigit() and os.path.basename(d) != "0"]
if not users:
    sys.exit("No hay usuarios en userdata/")
for u in users:
    process_user(u)
print("\nListo. Vuelve a abrir Steam (o Modo Juego) y mira en Biblioteca → Colecciones.")
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

PP_ID=ru.linux_gaming.PortProton
PP="${PORT_WINE_PATH:-$HOME/.var/app/$PP_ID}"
STEAM_DIR="${STEAM_DIR:-$HOME/.local/share/Steam}"
ARG=${1:-}
ISO_LIST=${ISO_LIST:-} ISO_SB=${ISO_SB:-}

say() { printf '%s\n' "$*"; }
ask() {                                   # ask "question" [default S|N] -> 0 for yes
    local def=${2:-N} ans
    read -r -p "$1 [$([ "$def" = S ] && echo S/n || echo s/N)] " ans || ans=
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
    [ ${#DESKS[@]} -gt 0 ] || [ ${#ISOS[@]} -gt 0 ] || { say "PortProton no tiene juegos."; exit 0; }
    say "Juegos:"
    for i in "${!DESKS[@]}"; do
        e=$(exe_of "${DESKS[$i]}")
        printf '  %2d) %-40s %s\n' $((i + 1)) "$(basename "${DESKS[$i]}" .desktop)" "$([ -f "$e" ] || echo '(el .exe ya no está)')"
    done
    for i in "${!ISOS[@]}"; do
        e=${ISOS[$i]} nm=$(sh_name "${ISOS[$i]}")
        lv=$(awk -F'\t' -v e="$e" '$2 == e { print $1 }' "$ISO_LIST" | tail -1)
        printf '  %2d) %-40s %s\n' $((${#DESKS[@]} + i + 1)) "${nm:-$(basename "${e%.*}")}" "($lv)$([ -f "$e" ] || echo ' (el .exe ya no está)')"
    done
    read -r -p "¿Cuál quitas? (número, Intro = ninguno): " n || n=
    [[ $n =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le $((${#DESKS[@]} + ${#ISOS[@]})) ] || { say "Nada que hacer."; exit 0; }
    if [ "$n" -le ${#DESKS[@]} ]; then DESK=${DESKS[$((n - 1))]}; else EXE=${ISOS[$((n - ${#DESKS[@]} - 1))]}; fi
elif [ -f "$ARG" ]; then                  # an .exe (Dolphin): its PortProton shortcut, if any
    EXE=$(realpath "$ARG")
    for d in "${DESKS[@]}"; do [ "$(exe_of "$d")" = "$EXE" ] && { DESK=$d; break; }; done
else                                      # a name
    [ -f "$PP/$ARG.desktop" ] && DESK="$PP/$ARG.desktop" || { say "No encuentro «$ARG» en PortProton." >&2; exit 1; }
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
section "Juego: $NAME"
say "Ejecutable: ${EXE:-?}"
[ -n "$DESK" ] || say "(PortProton no tiene acceso directo para este .exe)"

# --- 1. Steam -------------------------------------------------------------------------------------------
section "1. Steam"
# entries whose target is this game's steam_scripts .sh, or any .sh that launches this exe
mapfile -t SHS < <({ [ -f "$SH" ] && echo "$SH"; [ -n "$EXE" ] && grep -l -F "\"$EXE\"" "$PP"/steam_scripts/*.sh 2>/dev/null; } | sort -u)
if [ ${#SHS[@]} = 0 ]; then
    say "No tiene script de Steam (steam_scripts): nada que quitar en Steam."
else
    say "Quita de Steam las entradas que lanzan: ${SHS[*]##*/} (con copia de shortcuts.vdf) y sus carátulas."
    if ask "¿Quitarlo de Steam?" S; then
        if pgrep -x steam >/dev/null 2>&1; then
            if ask "  Steam está abierto y hay que cerrarlo (si no, al cerrarse vuelve a escribir el juego). ¿Cerrarlo?" S; then
                steam -shutdown >/dev/null 2>&1 || true
                for _ in $(seq 1 30); do pgrep -x steam >/dev/null 2>&1 || break; sleep 1; done
            fi
            pgrep -x steam >/dev/null 2>&1 && { say "  Steam sigue abierto: ciérralo y repite." >&2; exit 1; }
        fi
        STEAM_DIR="$STEAM_DIR" GAME_SHS="$(printf '%s\n' "${SHS[@]}")" python3 - <<'PY'
# shortcuts.vdf is binary VDF: parsed into (type, key, value) lists and written back exactly as read
# (checked byte for byte), without the game's entries; the rest are renumbered 0, 1, 2...
import glob, os, shutil, struct, sys, time

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
            raise ValueError(f"tipo VDF 0x{t:02x} desconocido en {i - 1}")
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
        print(f"  {path}: no lo leo de forma exacta; no lo toco."); continue
    sc = field(root, b"shortcuts")
    keep, gone = [], []
    for t, k, e in sc:
        exe = (field(e, b"exe") or b"").decode("utf-8", "replace").strip('"') if t == 0 else ""
        (gone if exe in targets else keep).append((t, k, e))
    if not gone:
        print(f"  Usuario {path.split(os.sep)[-3]}: no estaba en Steam."); continue
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
        print(f"  Usuario {path.split(os.sep)[-3]}: quitado «{name}» (id {appid}; {len(art)} imágenes).")
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
    say "No hay accesos directos ni scripts suyos."
else
    say "Borra sus accesos directos y su script de Steam:"; printf '  %s\n' "${PPF[@]}"
    say "(sus ajustes, $( [ -n "$EXE" ] && echo "${EXE##*/}.ppdb" || echo '.ppdb'), van con la carpeta del juego; las partidas del prefijo de PortProton se quedan)"
    if ask "¿Borrarlos?" S; then rm -f -- "${PPF[@]}" && say "  Borrados."; fi
fi

# --- 3. disk -------------------------------------------------------------------------------------------------
section "3. Disco"
if [ -z "$EXE" ] || [ ! -e "$EXE" ]; then
    say "El juego ya no está en el disco."
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
        say "No sé qué carpeta borrar sin riesgo${others:+ (también tiene: $others)}: bórrala tú a mano si quieres."
    else
        say "Carpeta del juego: $root ($(du -sh "$root" 2>/dev/null | cut -f1))"
        if ask "¿Borrarla del disco? (no se puede deshacer)" N; then
            read -r -p "  Para confirmar, escribe el nombre de la carpeta ($(basename "$root")): " c || c=
            if [ "$c" = "$(basename "$root")" ]; then rm -rf -- "$root" && say "  Borrada."
            else say "  No coincide: no se borra."; fi
        fi
    fi
fi

# --- the toolbox's list: forget it, and an isolated game's prefix if wanted ------------------------------------
if [ -n "$EXE" ] && [ -n "$ISO_LIST" ] && cut -f2 "$ISO_LIST" 2>/dev/null | grep -qxF -- "$EXE"; then
    pfx=$ISO_PFX
    tmp=$(mktemp); awk -F'\t' -v e="$EXE" '$2 != e' "$ISO_LIST" >"$tmp" && mv "$tmp" "$ISO_LIST"
    if [ -n "$pfx" ] && [ -d "$ISO_SB/data/prefixes/$pfx" ]; then
        section "Prefijo aislado"
        say "Su prefijo aislado, con sus partidas, está en $ISO_SB/data/prefixes/$pfx ($(du -sh "$ISO_SB/data/prefixes/$pfx" | cut -f1))."
        if ask "¿Borrarlo? (no se puede deshacer)" N; then rm -rf -- "${ISO_SB:?}/data/prefixes/$pfx" && say "  Borrado."; fi
    fi
fi

# --- 4. collection -----------------------------------------------------------------------------------------
section "4. Colección «PortProton» de Steam"
if [ -n "${COLLECTION_SCRIPT:-}" ] && [ -f "$COLLECTION_SCRIPT" ]; then
    if ask "¿Actualizar la colección (quita las entradas que ya no existen)?" S; then
        bash "$COLLECTION_SCRIPT" --yes || say "  La colección no se actualizó (mira el mensaje de arriba)."
    fi
else
    say "No encuentro el sincronizador de la colección: se salta."
fi
section "Listo"
say "Terminado con «$NAME»."
if ! pgrep -x steam >/dev/null 2>&1 && ask "¿Abrir Steam ahora?" N; then
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
    [ -n "$exe" ] || { echo "Uso: --change-level Juego.exe" >&2; return 2; }
    tmp=$(mktemp) && pp_collection_script >"$tmp"
    COLLECTION_SCRIPT=$tmp TOOLBOX_CMD=$(toolbox_cmd) ISO_LIST=$ISO_LIST ISO_SB=$ISO_SB \
        bash <(pp_add_game_script) --change "$exe"; rc=$?
    rm -f "$tmp"; return $rc
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
    [ ${#rows[@]} -gt 0 ] || { echo "No hay juegos instalados (opción 10 o, en Dolphin, «Instalar en PortProton y Steam»)."; return 0; }
    echo
    for i in "${!rows[@]}"; do
        IFS=$'\t' read -r nm lv e <<<"${rows[$i]}"
        case $lv in red) lv="aislado con red" ;; sin-red) lv="aislado sin red" ;; esac
        printf '  %2d) %-40s %s%s\n' $((i + 1)) "$nm" "$lv" "$([ -f "$e" ] || echo '  (el .exe ya no está)')"
    done
    read -rp "¿Cuál? (número, Intro = volver): " a
    [[ $a =~ ^[0-9]+$ ]] && [ "$a" -ge 1 ] && [ "$a" -le ${#rows[@]} ] || return 0
    IFS=$'\t' read -r nm lv e <<<"${rows[$((a - 1))]}"
    echo "$nm:  1) Cambiar aislamiento   2) Desinstalar   0) Volver"
    read -rp "Elige: " c
    case $c in
        1) if [ -f "$e" ]; then pp_change_level "$e"; else echo "El .exe ya no está: solo se puede desinstalar."; fi ;;
        2) if [ -f "$e" ]; then pp_remove_game "$e"; else pp_remove_game "$nm"; fi ;;
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
        read -e -rp "Ruta del .exe del juego (puedes arrastrarlo aquí desde Dolphin): " exe
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
    case $HOME/ in "$1"/*) echo "El juego está directamente en $1: muévelo a su propia carpeta (p. ej. ~/Juegos/Juego/)." >&2; return 1 ;; esac
    case $1/ in "$PP_APP"/*|/var/mnt/*|/mnt/*|/run/media/*)
        echo "La carpeta del juego ($1) queda escribible para él: tiene que ser una carpeta local propia" >&2
        echo "(p. ej. ~/Juegos/Juego/), no PortProton, el NAS ni un disco externo. Cópialo allí antes." >&2; return 1 ;;
    esac
}
iso_sync() {                             # the copy of PortProton: everything but its prefixes; rsync undoes any change
    [ -d "$ISO_SB/data/scripts" ] ||
        echo "Primera vez: copio PortProton sin los prefijos ($(du -sh --exclude=prefixes "$PP_APP/data" 2>/dev/null | cut -f1)) a $ISO_SB, tarda un poco…"
    mkdir -p "$ISO_SB/data" "$ISO_SB/cache" "$ISO_SB/config" &&
        rsync -a --delete --exclude=/prefixes/ "$PP_APP/data/" "$ISO_SB/data/" &&
        rsync -a --delete "$PP_APP/config/" "$ISO_SB/config/" || { echo "No pude preparar la copia en $ISO_SB." >&2; return 1; }
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
    [ -f "$exe" ] || { echo "No existe: $exe" >&2; return 1; }
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
    cd "$d" 2>/dev/null || { echo "No existe la carpeta: $d" >&2; return 1; }
    echo "Lo que ocupa cada carpeta de $(pwd):"
    du -bsh -- */ .[!.]*/ 2>/dev/null | sort -h
    echo "Total: $(du -bsh . 2>/dev/null | cut -f1)"
}

# Black screen with the console still running: moving to another virtual console and back makes the GPU set
# the picture up again (what ps5-hdmi-kick does once after a warm reboot). Nothing is closed.
screen_kick() {
    local vt; vt=$(sudo fgconsole 2>/dev/null || echo 1); [ "$vt" = 2 ] && vt=1
    echo "Cambiando a la consola 2 y volviendo a la $vt…"
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
    bk_k .cache 0 "cachés de los programas: se rehacen solas"
    bk_k .local/share/Trash 0 "la papelera"
    bk_k .local/share/Steam/steamapps/common 1 "juegos de Steam instalados (sin ellos, Steam los vuelve a descargar)"
    bk_k .local/share/Steam/steamapps/compatdata 1 "prefijos de Proton de Steam (partidas de algunos juegos)"
    bk_k .local/share/Steam/steamapps/shadercache 0 "sombreadores de Steam: se rehacen"
    bk_k .config/rpcs3/dev_hdd1 0 "caché de RPCS3: se rehace"
    bk_k Emulation/storage/rpcs3/dev_hdd0/game 1 "juegos de PS3 instalados en RPCS3"
    bk_k Games 1 "juegos (portables, de Heroic…): sin ellos, sus accesos de Steam y PortProton no abren"
    bk_k Games/Heroic 1 "juegos instalados con Heroic"
    for p in "$r"/.var/app/ru.linux_gaming.PortProton/data/prefixes/*/ "$r"/.local/share/ps5-bazzite-toolbox/aislado/data/prefixes/*/; do
        [ -d "$p" ] || continue; p=${p%/}; p=${p#"$r"/}
        bk_k "$p" 1 "prefijo de PortProton ${p##*/} (programas y partidas de sus juegos)"
        bk_k "$p/drive_c/Games" 1 "juegos instalados en el prefijo ${p##*/}"
    done
    dl=$(xdg-user-dir DOWNLOAD 2>/dev/null); dl=${dl#"$HOME"/}
    [ -n "$dl" ] && [ "$dl" != "$HOME" ] && bk_k "$dl" 1 "descargas"
    true
}

bk_scan() {                              # bk_scan ROOT [ONLY-THESE] -> fills BK_*: big top folders + the known places inside them
    local r=$1 only=${2:-} p sz small=0 n=0 rest=0 kp kon kds
    BK_P=() BK_ON=() BK_SZ=() BK_DS=()
    echo "Midiendo lo que ocupa cada carpeta de $r (la primera vez puede tardar un par de minutos)…"
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
        printf '\n  %s (marca o desmarca con su número):\n' "$what"
        for n in "${!BK_P[@]}"; do
            d=0; for i in "${!BK_P[@]}"; do [[ ${BK_P[$n]} == "${BK_P[$i]}"/* ]] && d=$((d + 1)); done; c='[x]'; [ "${BK_ON[$n]}" = 0 ] && c='[ ]'; bk_parent_off "$n" && c=' - '
            printf '  %3d %*s%s %8s  %s%s\n' $((n + 1)) $((d * 2)) '' "$c" "$(hsize "${BK_SZ[$n]}")" "${BK_P[$n]}" \
                "${BK_DS[$n]:+  — ${BK_DS[$n]}}"
        done
        [ "${BK_SMALL:-0}" = 0 ] || printf '      [x] %8s  %s carpetas pequeñas y los ficheros sueltos (van siempre)\n' "$(hsize "$BK_REST")" "$BK_SMALL"
        printf '  Total marcado: %s\n' "$(hsize "$(bk_total)")"
        read -rp "  Números (p. ej. 1 4), a N = elegir dentro de la carpeta N, Intro = seguir, 0 = cancelar: " a
        case $a in
            '') return 0 ;;
            0) return 1 ;;
            a\ *|A\ *) n=$(( ${a#* } - 1 ))
                [ "$n" -ge 0 ] 2>/dev/null && [ -n "${BK_P[$n]:-}" ] || { echo "  No hay carpeta ${a#* }"; continue; }
                bk_open "$r" "$n" ;;
            *) for i in $a; do
                   [[ $i =~ ^[0-9]+$ ]] && [ -n "${BK_P[$((i - 1))]:-}" ] || { echo "  No hay carpeta $i"; continue; }
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
    [ ${#new[@]} -gt 0 ] || { echo "  No tiene carpetas de más de 10 MB que no estén ya en la lista."; return; }
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
    echo "  ¿Dónde la guardo? Se crea dentro la carpeta ps5-copia-$U."
    for n in "${!c[@]}"; do
        printf '  %d) %s  (%s libres, %s)\n' $((n + 1)) "${c[$n]}" "$(df -h --output=avail "${c[$n]}" 2>/dev/null | tail -1 | tr -d ' ')" \
            "$(findmnt -no FSTYPE -T "${c[$n]}" 2>/dev/null | tail -1)"
    done
    read -e -rp "  Número, u otra carpeta (Intro = cancelar): " a
    [ -n "$a" ] || return 1
    if [[ $a =~ ^[0-9]+$ ]] && [ -n "${c[$((a - 1))]:-}" ]; then a=${c[$((a - 1))]}; fi
    a=${a/#\~/$HOME}
    timeout 20 test -d "$a" || { echo "  No existe o no responde: $a"; return 1; }
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
    local mode free need ex list a p rc=0 n
    echo
    echo "${B}Copia de seguridad de tu carpeta personal ($HOME)${N}"
    section
    say "Copia tu carpeta personal, entera o lo que elijas, a otro disco, al NAS o a una carpeta, para recuperarla"
    say "aquí o en otra instalación (la opción 20 → recuperar). Se guardan también el servicio de Decky y la lista de"
    say "Flatpaks del sistema. Los enlaces que salen de tu carpeta (ROMs en el NAS) se guardan como enlace."
    say "POR QUÉ: para cambiar de disco o de instalación (p. ej. a bootc) sin perder juegos, partidas ni ajustes."
    say "No cambia nada en tu carpeta. DESHACER: borra la carpeta de la copia."
    bk_dest_pick || return 1
    mode=$(bk_mode "$(dirname "$BK_DEST")")
    [ "$mode" != no ] || { echo "  Ese disco es FAT: no admite ficheros de más de 4 GB. Usa otro (ext4 o exFAT) o el NAS."; return 1; }
    case $BK_DEST/ in "$HOME"/*) [ "$(stat -c %d "$(dirname "$BK_DEST")")" != "$(stat -c %d "$HOME")" ] ||
        { echo "  La copia no puede ir dentro de tu propia carpeta, en el mismo disco."; return 1; } ;; esac
    BK_SRC_ROOT=$HOME
    bk_scan "$HOME" || return 1
    bk_pick "$HOME" "Qué se guarda de $HOME" || return 1
    list=$(mktemp); bk_excluded >"$list"
    a=$(bk_orphans "$list")
    [ -z "$a" ] || { echo "  Ojo: estos juegos de PortProton quedan fuera de la copia (al recuperarla no abrirán hasta que copies sus ficheros):"
                     sed 's/^/    /' <<<"$a"; }
    echo "  Buscando enlaces a otros discos o al NAS…"
    p=$(bk_links "$HOME" | head -20)
    [ -z "$p" ] || { echo "  Enlaces a otros discos o al NAS: se guarda el enlace, no lo que hay al otro lado (al recuperar, el enlace vuelve):"
                     sed 's/\t/ -> /; s/^/    /' <<<"$p"; }
    need=$(bk_total); free=$(df -B1 --output=avail "$(dirname "$BK_DEST")" | tail -1)
    [ "$mode" = rsync ] && [ -d "$BK_DEST/casa" ] && free=$((free + $(bk_du "$BK_DEST/casa")))   # an update replaces the old copy
    echo "  Copia: $(hsize "$need") en $BK_DEST ($([ "$mode" = rsync ] && echo "carpeta normal; si ya había una, solo copia lo que ha cambiado" || echo "un .tar.zst por carpeta"))."
    if [ "$need" -gt "$free" ]; then
        echo "  ${Y}No cabe: hay $(hsize "$free") libres.${N} Desmarca algo (los juegos ocupan lo que más) o elige otro sitio."
        rm -f "$list"; return 1
    fi
    pgrep -u "$U" -x steam >/dev/null && echo "  Steam está abierto: mejor ciérralo, para que sus ficheros no cambien mientras se copian."
    yesno "  ¿Hago la copia?" S || { rm -f "$list"; return 1; }
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
            echo "  Comprobando la copia (compara de nuevo con tu carpeta)…"
            n=$(rsync -aHAXn --one-file-system --delete --exclude-from="$ex" --out-format='%n' "$HOME"/ "$BK_DEST/casa/" | grep -vc '/$')
            [ "$n" = 0 ] && echo "  ${G}✔${N} La copia es igual a tu carpeta." ||
                echo "  ${Y}!${N} $n ficheros han cambiado mientras se copiaba (algo estaba abierto); repite la copia para ponerlos al día."
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
    if [ "$rc" = 0 ]; then echo "  ${G}Copia hecha${N} en $BK_DEST. Para recuperarla: opción 20 → recuperar, y esa carpeta."
    else echo "  ${R}La copia ha terminado con errores (código $rc).${N} Lo que ha fallado sale arriba; repítela."; fi
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
    echo "  Montado (solo lectura) en $BK_MP."
}
bk_umount() {
    [ -n "$BK_MDEV" ] || return 0
    if [ "$BK_MSUDO" = 1 ]; then sudo umount "$BK_MP"; else udisksctl unmount -b "$BK_MDEV" --no-user-interaction >/dev/null; fi &&
        echo "  Desmontado $BK_MDEV."
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
    say "Este disco ($vp) va ahora con UAS, y su sistema lo usaba con usb-storage.quirks=$vp:$q: con UAS daba"
    say "errores y atascos, justo lo que no quieres en una copia larga. Lo pongo para este disco hasta que reinicies"
    say "(no cambia el arranque de nadie) y lo vuelves a enchufar."
    yesno "¿Lo pongo?" S || return 0
    need_sudo || return 1
    uuid=$(lsblk -no UUID "$dev" 2>/dev/null)
    bk_umount
    cur=$(cat /sys/module/usb_storage/parameters/quirks 2>/dev/null)
    [[ ,$cur, == *",$vp:"* ]] || printf '%s' "${cur:+$cur,}$vp:$q" | sudo tee /sys/module/usb_storage/parameters/quirks >/dev/null || return 1
    read -rp "  Desenchufa el disco, vuelve a enchufarlo y pulsa Intro… " _
    for i in $(seq 60); do
        dev=$(lsblk -rnpo NAME,UUID 2>/dev/null | awk -v u="$uuid" '$2 == u { print $1; exit }'); [ -n "$dev" ] && break; sleep 1
    done
    [ -n "$dev" ] || { echo "  No vuelve a aparecer el disco."; return 1; }
    disk=/dev/$(lsblk -no PKNAME "$dev" | head -1)
    drv=$(udevadm info -q property -n "$disk" 2>/dev/null | sed -n 's/^ID_USB_DRIVER=//p')
    [ "$drv" = usb-storage ] && echo "  ${G}✔${N} Ahora va sin UAS." || echo "  ${Y}!${N} Sigue con $drv: puede dar errores."
    BK_DEV=$dev
}

bk_restore() {                           # bk_restore [DIR] -> picks where from (a copy, another disk), then bk_restore_do
    local a=${1:-} c=() d n rc
    BK_DEV=''
    if [ -z "$a" ]; then
        echo
        echo "${B}Recuperar tu carpeta personal${N}: ¿de dónde?"
        while read -r d; do [ -n "$d" ] && c+=("copy	${d%/*}"); done < <(timeout 20 find /run/media/"$U" /var/mnt /mnt -maxdepth 3 -name "$BK_INFO" 2>/dev/null)
        while IFS=$'\t' read -r d n; do [ -n "$d" ] && c+=("disk	$d	$n"); done < <(bk_disks | awk -F'\t' '{ print $1 "\t" $2 " " $3 " «" $4 "» " $5 " (" $6 ")" ($7 ? " en " $7 : ", sin montar") }')
        for n in "${!c[@]}"; do
            IFS=$'\t' read -r d a rc <<<"${c[$n]}"
            if [ "$d" = copy ]; then printf '  %d) copia en %s (%s)\n' $((n + 1)) "$a" "$(sed -n 's/^fecha=//p' "$a/$BK_INFO")"
            else printf '  %d) disco %s %s\n' $((n + 1)) "$a" "$rc"; fi
        done
        [ ${#c[@]} -gt 0 ] || echo "  (no encuentro copias ni otros discos Linux enchufados)"
        read -e -rp "  Número, o escribe una carpeta (Intro = cancelar): " a
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
    echo "${B}Recuperar tu carpeta personal${N}"
    section
    say "Trae a $BK_TO lo que elijas de una copia (opción 20 → guardar) o de la carpeta personal de otro disco"
    say "(p. ej. el de tu instalación anterior, enchufado ahora). Sobrescribe los ficheros que se llamen igual; lo"
    say "demás de tu carpeta se queda. Después ofrece reinstalar Decky y los Flatpaks del sistema y aplicar tus ajustes."
    say "POR QUÉ: para tener en esta instalación tus juegos, partidas y ajustes como estaban."
    say "DESHACER: no se deshace solo; si dudas, haz antes una copia de esta carpeta."
    a=${1/#\~/$HOME}; a=${a%/}
    bk_find "$a" || { echo "  Ahí no hay una copia ($BK_INFO) ni una carpeta personal de $U."; return 1; }
    p=$(realpath "$BK_SRC")
    [ "$p" != "$(realpath "$BK_TO")" ] || { echo "  Esa es la carpeta en la que estás."; return 1; }
    if [ "$BK_KIND" = copy ]; then
        mode=$(sed -n 's/^modo=//p' "$BK_SRC/$BK_INFO")
        echo "  Copia del $(sed -n 's/^fecha=//p' "$BK_SRC/$BK_INFO") ($(sed -n 's/^equipo=//p' "$BK_SRC/$BK_INFO"), imagen v$(sed -n 's/^imagen=//p' "$BK_SRC/$BK_INFO"), $mode)."
        [ "$(sed -n 's/^resultado=//p' "$BK_SRC/$BK_INFO")" = 0 ] || echo "  ${Y}!${N} Esa copia terminó con errores: puede faltar algo."
        a=$(sed -n 's/^usuario=//p' "$BK_SRC/$BK_INFO")
    else
        mode=rsync; a=$(stat -c %U "$BK_SRC" 2>/dev/null)
        echo "  Carpeta personal de otra instalación: $BK_SRC"
    fi
    p=$(sed -n 's/^casa=//p' "$BK_SRC/$BK_INFO" 2>/dev/null)
    if [ -n "$p" ] && [ "$p" != "$HOME" ]; then
        echo "  ${Y}!${N} Era de $p y ahora estás en $HOME: los enlaces y ajustes con la ruta"
        echo "    vieja no funcionarán. Lo normal es usar el mismo nombre de usuario en la instalación nueva."
        yesno "  ¿Seguir igualmente?" N || return 1
    fi
    if [ "$mode" = tar ]; then           # a copy in .tar.zst: one line per saved folder
        BK_P=() BK_ON=() BK_SZ=() BK_DS=() BK_REST=0 BK_SMALL=0
        for p in "$BK_SRC"/casa/*.tar.zst; do
            [ -f "$p" ] || continue; p=${p##*/}; p=${p%.tar.zst}
            local sz; sz=$(awk -F'\t' -v p="$(tr '%' '/' <<<"$p")" '$1 == p { print $2 }' "$BK_SRC/sistema/tamanos.txt" 2>/dev/null)
            BK_P+=("$(tr '%' '/' <<<"$p")") BK_ON+=(1) BK_SZ+=("${sz:-$(stat -c %s "$BK_SRC/casa/$p.tar.zst")}")
            if [ "$p" = _resto ]; then BK_DS+=("carpetas pequeñas y ficheros sueltos"); else BK_DS+=(""); fi
        done
        bk_pick "$BK_SRC" "Qué se recupera" || return 1
    else
        local root=$BK_SRC; [ "$BK_KIND" = copy ] && root=$BK_SRC/casa
        bk_scan "$root"
        bk_pick "$root" "Qué se recupera" || return 1
    fi
    n=$(bk_total); a=$(df -B1 --output=avail "$BK_TO" | tail -1)
    [ "$n" -lt "$a" ] || { echo "  ${Y}No cabe:${N} hacen falta $(hsize "$n") y hay $(hsize "$a") libres."; return 1; }
    if pgrep -u "$U" -x steam >/dev/null; then
        echo "  Steam está abierto: hay que cerrarlo, o reescribirá sus ficheros al salir."
        yesno "  ¿Lo cierro?" S && { steam -shutdown >/dev/null 2>&1 & sleep 10; pkill -u "$U" -x steam; }
    fi
    [ -z "${SSH_CONNECTION:-}" ] && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] &&
        echo "  Ojo: lo lanzas desde la sesión gráfica. KDE puede volver a guardar algunos de sus ajustes al cerrar sesión; si"
    [ -z "${SSH_CONNECTION:-}" ] && [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] &&
        echo "  quieres que queden exactamente los de la copia, hazlo por SSH o en una consola de texto (Ctrl+Alt+F3)."
    echo "  Se recuperan $(hsize "$n") en $BK_TO."
    yesno "  ¿Sigo?" S || return 1
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
    [ "$rc" = 0 ] && echo "  ${G}✔${N} Recuperado." || echo "  ${R}✘${N} Ha habido errores (código $rc): salen arriba."
    if command -v selinuxenabled >/dev/null && selinuxenabled && yesno "  ¿Repongo las etiquetas de SELinux de lo recuperado (restorecon)?" S && need_sudo; then
        sudo restorecon -RF "$BK_TO"
    fi
    bk_restore_system
    p=$(bk_links "$BK_TO" | while IFS=$'\t' read -r l t; do [ -e "$BK_TO/$l" ] || echo "$l -> $t"; done | head -20)
    [ -z "$p" ] || { echo "  Estos enlaces apuntan a sitios que ahora no están (el NAS sin montar, otro disco):"; sed 's/^/    /' <<<"$p"
                     echo "  Los del NAS funcionan en cuanto se monte: bloque nas de los ajustes (opción 16 → nas)."; }
    if yesno "  ¿Aplico ahora tus ajustes guardados (la opción 15, uno a uno, preguntando)?" S; then
        # shellcheck disable=SC1090
        need_sudo && { . "$CONF"; STATUS_ONLY=0 ALL=0 ONLY=''; setup_run; }
    fi
    echo "  Reinicia la consola (o al menos la sesión) para que todo lea lo recuperado."
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
        echo "  Decky: sus plugins ya están en ~/homebrew, pero falta el servicio que lo arranca con Steam."
        if yesno "  ¿Instalo el servicio de Decky (/etc/systemd/system/plugin_loader.service)?" S && need_sudo; then
            sudo cp "$svc" /etc/systemd/system/plugin_loader.service && sudo systemctl daemon-reload &&
                sudo systemctl enable --now plugin_loader && echo "  ${G}✔${N} Decky activo (sale en Steam al reiniciarlo)."
        fi
    fi
    miss=$(for a in $fl; do flatpak info --system "$a" >/dev/null 2>&1 || echo "$a"; done)
    if [ -n "$miss" ]; then
        echo "  Flatpaks del sistema que tenías y aquí faltan: $(echo $miss)"
        if yesno "  ¿Los instalo desde Flathub (hace falta red)?" S && need_sudo; then
            # shellcheck disable=SC2086
            sudo flatpak install --system -y --noninteractive flathub $miss
        fi
    fi
}

bk_menu() {
    local c
    echo "  1) Guardar una copia de tu carpeta personal (en otro disco, el NAS o una carpeta)"
    echo "  2) Recuperar una copia, o la carpeta personal de otra instalación (otro disco enchufado)"
    read -rp "Elige (0 = cancelar): " c
    case $c in 1) bk_save ;; 2) bk_restore ;; esac
}

# --- menu ----------------------------------------------------------------------------------------------------
menu() {
    local c a notice_done=''
    while :; do
        printf '\n%sPS5 Bazzite Deck — caja de herramientas v%s%s (imagen %s%s, kernel %s)\n' \
            "$B" "$TOOLBOX_VERSION" "$N" "${VERSION:+v$VERSION}" "$([ $IS_BOOTC = 1 ] && echo ' bootc')" "$(uname -r)"
        [ -n "$notice_done" ] || { offer_install; toolbox_notice; notice_done=1; }
        cat <<'MENU'
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
  11) Mis juegos: cambiar su aislamiento o desinstalarlos (de Steam, PortProton y el disco)
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
        read -rp "Elige: " c
        case $c in [1-9]|1[4-7]) need_sudo || continue ;; esac       # 10-13, 18 and 19 don't need it
        case $c in
            1) BOOT=0; run_checks ;;
            2) BOOT=-1; run_checks ;;
            3) trap ':' INT; watch_kernel; trap - INT ;;
            4) mem_watch ;;
            5) session_status ;;
            6) screen_kick ;;
            7|8|9) read -rp "Se cerrará Steam y todo lo abierto en pantalla. ¿Seguir? [s/N] " a
                   [[ $a == [sS]* ]] || continue
                   case $c in 7) session restart ;; 8) session desktop ;; 9) session gamemode ;; esac ;;
            10) pp_add_game ;;
            11) pp_my_games ;;
            12) pp_collection ;;
            13) read -e -rp "Carpeta (Intro = $HOME): " a; space_report "${a:-$HOME}" ;;
            14) STATUS_ONLY=1 ALL=0 ONLY=''; setup_run; STATUS_ONLY=0 ;;
            15) STATUS_ONLY=0 ALL=0 ONLY=''; setup_run ;;
            16) echo "Ajustes: $BLOCKS"
                read -rp "¿Cuáles? (separados por espacios o comas): " a
                [ -n "$a" ] && { STATUS_ONLY=0 ALL=0 ONLY=${a//,/ }; setup_run; ONLY=''; } ;;
            17) img_menu ;;
            18) self_update && { echo "Saliendo para que abras la versión nueva."; return 0; } ;;
            20) bk_menu ;;
            19) if [ "$TOOLBOX_SELF" = "$TOOLBOX_BIN" ]; then uninstall_self && return 0; else install_self; fi ;;
            0|q|'') return 0 ;;
            *) echo "Opción no válida" ;;
        esac
    done
}

case $MODE in                            # these need no root
    add-game) pp_add_game "${ARGS[@]}"; exit ;;
    remove-game) pp_remove_game "${ARGS[@]}"; exit ;;
    run) pp_run_game "${ARGS[@]}"; exit ;;
    change-level) pp_change_level "${ARGS[@]}"; exit ;;
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
