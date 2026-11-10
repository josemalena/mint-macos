#!/usr/bin/env bash
# install-sapos/instalar-todo.sh — sapOS en una Mac, de un solo paso (José, 10-11-2026).
#
# Se corre UNA vez, después de instalar Linux Mint desde la memoria «Install sapOS», como el
# usuario (no con sudo), desde la carpeta del paquete en la memoria:
#
#   cd /media/$USER/Ventoy/mint-macos-paquete && ./instalar-todo.sh
#
# La clave se pide una sola vez. Los pasos:
#   1. Los drivers de la Mac, si es una (en la MacBook5,1: el Wi-Fi Broadcom BCM4322):
#      - el Wi-Fi (bcmwl-kernel-source) y lm-sensors, del ISO que está en la misma memoria, sin
#        internet;
#      - el abanico: mbpfan (viene en drivers/), con applesmc y coretemp al arrancar.
#      El video de la 9400M lo maneja nouveau, que ya viene: el driver de NVIDIA (340) no existe
#      para los kernels de ahora.
#   2. Internet: si no hay, ofrece conectar el Wi-Fi ahí mismo (nmcli pide la clave de la red).
#   3. mint-macos: instalar-aqui.sh (el tema, Fynder, el Dock, la pantalla de inicio…).
#   4. Los acentos con ⌥ si el teclado es en inglés (macbook/acentos-option.sh).
#   5. El arranque y el apagado sin texto (silencio.sh), y el ícono y el nombre del disco
#      (icono-disco.sh, «sapOS»).
#
# Se puede volver a correr: lo que ya está se salta. Todo queda en
# ~/.cache/mint-macos/instalar-todo-<fecha>.log; si algo falla, dice en qué paso y con qué comando.
#   SAPOS_NOMBRE="Macintosh HD" ./instalar-todo.sh   otro nombre debajo del ícono
#   ISO=/ruta/linuxmint.iso ./instalar-todo.sh       el ISO, si no está en la memoria
set -eEuo pipefail

PAQ="$(cd "$(dirname "$0")" && pwd)"
REPO="$HOME/mint-macos"
NOMBRE="${SAPOS_NOMBRE:-sapOS}"
LOG="$HOME/.cache/mint-macos/instalar-todo-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

PASO="inicio"
paso() { PASO="$*"; printf '\n■ %s\n' "$*"; }
fallo() { printf '\n✗ Falló «%s», línea %s: %s\n  El registro completo: %s\n' "$PASO" "$1" "$2" "$LOG"; }
trap 'fallo "$LINENO" "$BASH_COMMAND"' ERR

[ "$(id -u)" != 0 ] || { echo "✗ córrelo como tu usuario, sin sudo: ./instalar-todo.sh"; exit 1; }
[ -x "$PAQ/instalar-aqui.sh" ] || { echo "✗ no está instalar-aqui.sh al lado: córrelo desde la carpeta del paquete"; exit 1; }

echo "sapOS: instalación completa ($(date '+%d-%m-%Y %I:%M %p'))"
sudo -v
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &

# ── 1. Los drivers de la Mac ──────────────────────────────────────────────────
MODELO="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo desconocido)"
paso "1. Los drivers ($MODELO)"
ES_MAC=0; case "$MODELO" in MacBook*|iMac*|Macmini*|MacPro*) ES_MAC=1 ;; esac
BROADCOM=0
if lspci -nn 2>/dev/null | grep -i 'network controller' | grep -q '\[14e4:43'; then BROADCOM=1; fi

FALTAN=()
if [ "$BROADCOM" = 1 ] && ! dpkg -s bcmwl-kernel-source >/dev/null 2>&1; then FALTAN+=(bcmwl-kernel-source); fi
if [ "$ES_MAC" = 1 ] && ! dpkg -s lm-sensors >/dev/null 2>&1; then FALTAN+=(lm-sensors); fi

if [ ${#FALTAN[@]} -gt 0 ]; then
  if [[ " ${FALTAN[*]} " == *" bcmwl-kernel-source "* ]] && ! dpkg -s "linux-headers-$(uname -r)" >/dev/null 2>&1; then
    # Sin los headers no se compila el driver: se sigue sin Wi-Fi y el paso 2 pide el cable.
    echo "  ⚠ faltan los headers del kernel (linux-headers-$(uname -r)): el Wi-Fi queda para después."
    echo "    Con internet por cable: sudo apt install linux-headers-$(uname -r), y vuelve a correr esto."
    SIN_WL=(); for p in "${FALTAN[@]}"; do [ "$p" = bcmwl-kernel-source ] || SIN_WL+=("$p"); done
    FALTAN=("${SIN_WL[@]}")
  fi
fi
if [ ${#FALTAN[@]} -gt 0 ]; then
  # El ISO de Mint trae un repositorio (pool y dists) con estos paquetes: se usa sin internet.
  if [ -z "${ISO:-}" ]; then
    ISO="$(ls "$PAQ"/../linuxmint-*.iso /media/"$USER"/*/linuxmint-*.iso 2>/dev/null | head -1 || true)"
  fi
  [ -f "${ISO:-}" ] || { echo "✗ no encuentro el ISO de Linux Mint en la memoria (ISO=/ruta/…iso)"; exit 1; }
  echo "  del ISO: $(basename "$ISO") → ${FALTAN[*]}"
  MNT=/mnt/sapos-iso; LISTA=/etc/apt/sources.list.d/sapos-iso.list
  sudo mkdir -p "$MNT"
  mountpoint -q "$MNT" || sudo mount -o loop,ro "$ISO" "$MNT"
  quitar_iso() { sudo rm -f "$LISTA"; sudo umount "$MNT" 2>/dev/null || true; }
  trap quitar_iso EXIT
  CODENAME="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
  echo "deb [trusted=yes] file:$MNT $CODENAME main contrib" | sudo tee "$LISTA" >/dev/null
  # Solo esta fuente: sin internet, las otras fallarían y dejarían candidatos que no se pueden bajar.
  SOLO_ISO=(-o "Dir::Etc::sourcelist=$LISTA" -o "Dir::Etc::sourceparts=-" -o "APT::Get::List-Cleanup=0")
  sudo apt-get "${SOLO_ISO[@]}" update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get "${SOLO_ISO[@]}" install -y "${FALTAN[@]}"
  quitar_iso; trap - EXIT
else
  echo "  el Wi-Fi y los sensores: ya estaban (o no hacen falta)"
fi

if [ "$BROADCOM" = 1 ] && ! lsmod | grep -q '^wl '; then
  sudo modprobe -r b43 bcma ssb 2>/dev/null || true
  sudo modprobe wl && echo "  Wi-Fi: el driver wl ya está cargado"
fi

if [ "$ES_MAC" = 1 ]; then
  if ! dpkg -s mbpfan >/dev/null 2>&1; then
    DEB="$(ls "$PAQ"/drivers/mbpfan_*.deb 2>/dev/null | head -1 || true)"
    if [ -n "$DEB" ]; then sudo apt-get install -y "$DEB"; else echo "  ⚠ no está drivers/mbpfan_*.deb: el abanico se instala en el paso 3 si hay internet"; fi
  fi
  printf 'applesmc\ncoretemp\n' | sudo tee /etc/modules-load.d/sapos-mac.conf >/dev/null
  sudo modprobe applesmc 2>/dev/null || true; sudo modprobe coretemp 2>/dev/null || true
  if dpkg -s mbpfan >/dev/null 2>&1; then sudo systemctl enable --now mbpfan >/dev/null 2>&1 && echo "  el abanico: mbpfan lo regula según la temperatura"; fi
fi

# ── 2. Internet ───────────────────────────────────────────────────────────────
paso "2. Internet"
hay_internet() { curl -sfI --max-time 6 https://github.com >/dev/null 2>&1; }
until hay_internet; do
  echo "  no hay internet. Redes Wi-Fi que se ven:"
  nmcli -t -f SSID,SIGNAL device wifi list --rescan yes 2>/dev/null | awk -F: '$1 != "" {printf "    %-32s %s%%\n", $1, $2}' | sort -u | head -15
  read -r -p "  Escribe el nombre de la red (o Enter si ya conectaste por cable): " RED </dev/tty
  if [ -n "$RED" ]; then nmcli --ask device wifi connect "$RED" </dev/tty || true; fi
  sleep 3
done
echo "  conectada"
if [ "$ES_MAC" = 1 ] && ! dpkg -s mbpfan >/dev/null 2>&1; then
  sudo apt-get install -y mbpfan && sudo systemctl enable --now mbpfan
fi

# ── 3. mint-macos ─────────────────────────────────────────────────────────────
paso "3. mint-macos (instalar-aqui.sh; tiene su propio registro)"
( cd "$PAQ" && ./instalar-aqui.sh )

# ── 4. El teclado ─────────────────────────────────────────────────────────────
paso "4. El teclado"
DISTRIBUCION="$(localectl status 2>/dev/null | awk -F': *' '/X11 Layout/ {print $2}')"
if [ "$ES_MAC" = 1 ] && [[ "${DISTRIBUCION:-}" == us* ]]; then
  bash "$REPO/install-sapos/macbook/acentos-option.sh"
else
  echo "  el teclado no es en inglés (${DISTRIBUCION:-?}): los acentos se quedan como vienen"
fi

# ── 5. El arranque, el apagado y el disco ─────────────────────────────────────
paso "5. Arranque sin texto, el fondo al apagar, y el ícono y el nombre del disco"
sudo "$REPO/tema/arranque/silencio.sh"
IMAGEN="$PAQ/icono-disco.png"
mkdir -p "$HOME/.local/share/mint-macos/arranque"
[ ! -f "$IMAGEN" ] || cp "$IMAGEN" "$HOME/.local/share/mint-macos/arranque/icono-disco.png"
sudo "$REPO/install-sapos/icono-disco.sh" --etiqueta "$NOMBRE"

paso "Listo"
echo "  Reinicia para verlo todo: la manzana sin texto, y con ⌥ al encender, el disco «$NOMBRE»."
echo "  El registro: $LOG"
read -r -p "  ¿Reiniciar ahora? [s/N] " R </dev/tty || true
case "${R:-}" in s|S|si|sí|Sí) systemctl reboot ;; esac
