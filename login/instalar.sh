#!/usr/bin/env bash
# La pantalla de inicio de sesión de macOS Catalina: instala slick-greeter-mac
# (el fork de slick-greeter de mint-macos) al lado del slick-greeter de Mint.
# Necesita sudo: todo lo de aquí es del sistema.
#
#   sudo login/instalar.sh [--fuente DIR]   instala, SIN cambiar el login
#   sudo login/instalar.sh --activar        además, lo pone como pantalla de inicio
#   sudo login/instalar.sh --deshacer       quita todo y vuelve al de Mint
#
#   --fuente  la carpeta del fork (rama «mac» de slick-greeter). Sin ella,
#             ../slick-greeter al lado de mint-macos.
#
# Antes, sin sudo: ./desde-mac.sh --login (el fondo y la foto de la Mac en
# ~/.local/share/constanza/login) y las SF en ~/.local/share/fonts.
#
# La vuelta atrás es UN archivo, /etc/lightdm/lightdm.conf.d/90-mint-macos-login.conf,
# y un comando que se instala primero: si la pantalla de inicio no sale,
# Ctrl+Alt+F2, entrar y
#     sudo login-mac-revertir
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
MINT_MACOS="$(dirname "$AQUI")"
FUENTE="$(dirname "$MINT_MACOS")/slick-greeter"
ACCION=instalar
while [ $# -gt 0 ]; do
  case "$1" in
    --fuente) FUENTE="$2"; shift 2 ;;
    --activar) ACCION=activar; shift ;;
    --deshacer) ACCION=deshacer; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $1" >&2; exit 2 ;;
  esac
done

[ "$(id -u)" -eq 0 ] || { echo "Hay que correrlo con sudo." >&2; exit 1; }
USUARIO="${SUDO_USER:-}"
[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "Córrelo con sudo desde tu usuario (no como root directo)." >&2; exit 1; }
HOGAR="$(getent passwd "$USUARIO" | cut -d: -f6)"

BINARIO=/usr/local/sbin/slick-greeter-mac
DESKTOP=/usr/local/share/xgreeters/slick-greeter-mac.desktop
DATOS=/usr/local/share/slick-greeter-mac
CONF=/etc/lightdm/slick-greeter-mac.conf
ACTIVA=/etc/lightdm/lightdm.conf.d/90-mint-macos-login.conf
REVERTIR=/usr/local/sbin/login-mac-revertir
FUENTES=/usr/local/share/fonts/mint-macos

paso() { printf '\n== %s\n' "$1"; }

if [ "$ACCION" = deshacer ]; then
  paso "Quitar slick-greeter-mac"
  rm -f "$ACTIVA" "$BINARIO" "$DESKTOP" "$CONF" "$REVERTIR"
  rm -rf "$DATOS" "$FUENTES"
  fc-cache -f >/dev/null 2>&1 || true
  echo "  listo: el login es el slick-greeter de Mint."
  echo "  La foto de la cuenta (AccountsService) se queda; se cambia en Configuración > Cuentas."
  exit 0
fi

paso "Respaldo de /etc/lightdm"
RESPALDO="/var/backups/mint-macos/lightdm-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESPALDO"
cp -a /etc/lightdm/. "$RESPALDO/"
echo "  $RESPALDO"

paso "La vuelta atrás, antes que nada"
install -Dm755 "$AQUI/login-mac-revertir" "$REVERTIR"
echo "  $REVERTIR  (si el login no sale: Ctrl+Alt+F2 y sudo login-mac-revertir)"

paso "Compilar slick-greeter-mac (como $USUARIO)"
[ -f "$FUENTE/src/login-mac.vala" ] || { echo "  ✗ $FUENTE no es el fork (falta src/login-mac.vala); usa --fuente" >&2; exit 1; }
if [ ! -d "$FUENTE/build" ]; then
  sudo -u "$USUARIO" meson setup "$FUENTE/build" "$FUENTE" --prefix=/usr/local >/dev/null
fi
sudo -u "$USUARIO" ninja -C "$FUENTE/build" >/dev/null
echo "  $(sudo -u "$USUARIO" git -C "$FUENTE" log --oneline -1)"

paso "Instalar el greeter (aparte del de Mint)"
install -Dm755 "$FUENTE/build/src/slick-greeter-mac" "$BINARIO"
install -Dm644 "$FUENTE/data/slick-greeter-mac.desktop" "$DESKTOP"
install -d "$DATOS"
for f in "$FUENTE"/data/*.svg "$FUENTE"/data/*.png; do install -m644 "$f" "$DATOS/"; done
echo "  $BINARIO"
echo "  $DESKTOP"

paso "La SF, donde el usuario lightdm la lea"
SF="$HOGAR/.local/share/fonts/san-francisco"
if [ -f "$SF/SFNS.ttf" ]; then
  install -d "$FUENTES"
  install -m644 "$SF/SFNS.ttf" "$FUENTES/"
  [ -f "$SF/SFNSItalic.ttf" ] && install -m644 "$SF/SFNSItalic.ttf" "$FUENTES/"
  fc-cache -f "$FUENTES" >/dev/null
  echo "  $FUENTES"
else
  echo "  ✗ no está $SF/SFNS.ttf: el login saldría en otra letra. Corre antes ./desde-mac.sh"
fi

paso "El fondo y la foto de la Mac"
LOCAL="$HOGAR/.local/share/constanza/login"
FONDO_CONF=""
if [ -f "$LOCAL/fondo.jpg" ]; then
  install -m644 "$LOCAL/fondo.jpg" "$DATOS/fondo.jpg"
  FONDO_CONF="$DATOS/fondo.jpg"
  echo "  fondo: $DATOS/fondo.jpg"
else
  echo "  ✗ sin fondo ($LOCAL/fondo.jpg): saldrá negro. Corre antes ./desde-mac.sh --login"
fi
if [ -f "$LOCAL/avatar.png" ]; then
  # Por AccountsService, que la copia a /var/lib/AccountsService/icons y la
  # anota en la cuenta: es la misma foto que enseña Cinnamon.
  RUTA="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
          org.freedesktop.Accounts FindUserByName s "$USUARIO" | awk '{print $2}' | tr -d '"')"
  busctl --system call org.freedesktop.Accounts "$RUTA" org.freedesktop.Accounts.User \
         SetIconFile s "$LOCAL/avatar.png"
  echo "  foto de $USUARIO puesta en AccountsService"
else
  echo "  sin foto ($LOCAL/avatar.png): sale la silueta"
fi

paso "Configuración: $CONF"
cat > "$CONF" <<CONF
# slick-greeter-mac (mint-macos, login/instalar.sh). La del slick-greeter de
# Mint es /etc/lightdm/slick-greeter.conf y no se toca.
[Greeter]
background=$FONDO_CONF
background-color=#000000
draw-user-backgrounds=false
draw-grid=false
theme-name=WhiteSur-Dark
icon-theme-name=WhiteSur-dark
cursor-theme-name=McMojave-cursors
font-name=.SF NS 10
xft-antialias=true
xft-hintstyle=hintnone
show-hostname=false
show-power=false
show-a11y=false
show-keyboard=true
show-clock=true
show-quit=false
clock-format=%a %-d %b  %-I:%M %p
CONF
echo "  escrita"

if [ "$ACCION" = activar ]; then
  paso "Activar: $ACTIVA"
  cat > "$ACTIVA" <<CONF
# mint-macos: la pantalla de inicio de Catalina. Para volver al de Mint:
#   sudo login-mac-revertir   (o borrar este archivo)
[Seat:*]
greeter-session=slick-greeter-mac
CONF
  echo "  activado: sale en el próximo inicio de sesión o al bloquear y cambiar de usuario."
else
  paso "Instalado, sin activar"
  echo "  El login sigue siendo el de Mint. Para ponerlo: sudo $0 --activar"
fi
