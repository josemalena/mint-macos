#!/usr/bin/env bash
# La pantalla de inicio de sesión de macOS Catalina: instala slick-greeter-mac
# (el fork de slick-greeter de mint-macos) al lado del slick-greeter de Mint.
# Necesita sudo: todo lo de aquí es del sistema.
#
#   sudo login/instalar.sh [--fuente DIR]   instala, SIN cambiar el login
#   sudo login/instalar.sh --activar        además, lo pone como pantalla de inicio
#   sudo login/instalar.sh --deshacer       quita todo y vuelve al de Mint
#
#   --fuente  una carpeta con el fork, para probar cambios sin publicar. Sin
#             ella se clona josemalena/mint-macos-greeter en el hash fijo de
#             GREETER_HASH (lo que se instala es lo que se probó), en
#             ~/.cache/mint-macos/src/mint-macos-greeter del usuario.
#
# Antes, sin sudo: ./desde-mac.sh --login (el fondo y la foto de la Mac en
# ~/.local/share/constanza/login) y las SF en ~/.local/share/fonts.
# Después, sin sudo: login/bloqueo.sh, para bloquear con esta misma pantalla.
#
# La vuelta atrás es UN archivo, /etc/lightdm/lightdm.conf.d/90-mint-macos-login.conf,
# y un comando que se instala primero: si la pantalla de inicio no sale,
# Ctrl+Alt+F2, entrar y
#     sudo login-mac-revertir
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
MINT_MACOS="$(dirname "$AQUI")"
GREETER_REPO=https://github.com/josemalena/mint-macos-greeter.git
GREETER_HASH=5254f6093010aab16c20611fb6c5fd892a8355b5
FUENTE=""
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

paso "Paquetes: xss-lock (el bloqueo por inactividad, login/bloqueo.sh)"
if dpkg -s xss-lock >/dev/null 2>&1; then
  echo "  ya está"
else
  apt-get install -y xss-lock >/dev/null && echo "  instalado"
fi

paso "Compilar slick-greeter-mac (como $USUARIO)"
if [ -z "$FUENTE" ]; then
  FUENTE="$HOGAR/.cache/mint-macos/src/mint-macos-greeter"
  [ -d "$FUENTE/.git" ] || sudo -u "$USUARIO" git clone -q --filter=blob:none "$GREETER_REPO" "$FUENTE"
  sudo -u "$USUARIO" git -C "$FUENTE" fetch -q origin "$GREETER_HASH" 2>/dev/null || sudo -u "$USUARIO" git -C "$FUENTE" fetch -q origin
  sudo -u "$USUARIO" git -C "$FUENTE" checkout -q --detach "$GREETER_HASH"
  [ "$(sudo -u "$USUARIO" git -C "$FUENTE" rev-parse HEAD)" = "$GREETER_HASH" ] || { echo "  ✗ no quedó en $GREETER_HASH" >&2; exit 1; }
fi
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
# El fondo es el del sistema: la pantalla de inicio sale con el escritorio de
# José y, al elegir usuario, pasa a su variante oscura. Si el escritorio es el de
# Catalina (el par claro/oscuro que saca desde-mac.sh --login) se usan los dos;
# si es otra imagen, esa misma sirve para los dos estados (no tiene variante
# oscura: no se inventa una).
FONDO_CLARO=""; FONDO_OSCURO=""
SISTEMA="$(sudo -u "$USUARIO" env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$USUARIO")/bus" \
           gsettings get org.cinnamon.desktop.background picture-uri 2>/dev/null | sed "s/^'file:\/\///; s/'\$//" || true)"
if [ -n "$SISTEMA" ] && [ -f "$SISTEMA" ] && ! echo "$SISTEMA" | grep -qi catalina; then
  convert "$SISTEMA" -resize 1920x1200^ -gravity center -extent 1920x1200 -quality 92 "$DATOS/fondo-sistema.jpg"
  FONDO_CLARO="$DATOS/fondo-sistema.jpg"; FONDO_OSCURO="$FONDO_CLARO"
  echo "  fondo del sistema ($SISTEMA): $FONDO_CLARO, sin variante oscura"
elif [ -f "$LOCAL/fondo-claro.jpg" ] && [ -f "$LOCAL/fondo-oscuro.jpg" ]; then
  install -m644 "$LOCAL/fondo-claro.jpg" "$LOCAL/fondo-oscuro.jpg" "$DATOS/"
  FONDO_CLARO="$DATOS/fondo-claro.jpg"; FONDO_OSCURO="$DATOS/fondo-oscuro.jpg"
  echo "  fondos de Catalina: claro para la lista, oscuro al elegir"
else
  echo "  ✗ sin fondos ($LOCAL/fondo-claro.jpg y fondo-oscuro.jpg): saldrá negro. Corre antes ./desde-mac.sh --login"
fi
if [ -d "$LOCAL/iconos" ]; then
  install -d "$DATOS/mac"
  install -m644 "$LOCAL"/iconos/*.png "$DATOS/mac/"
  echo "  botones de la Mac: $DATOS/mac"
else
  echo "  sin los botones de la Mac: van dibujados"
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

# El estilo de la cuenta: oscuro si su tema de Cinnamon es oscuro o su
# color-scheme es prefer-dark. Al elegirla en el login, el fondo pasa al oscuro
# solo si está aquí (como la Mac: depende de la apariencia del usuario).
GS="sudo -u $USUARIO env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u "$USUARIO")/bus gsettings get"
ESTILO="$($GS org.cinnamon.desktop.interface gtk-theme 2>/dev/null) $($GS org.gnome.desktop.interface color-scheme 2>/dev/null)"
OSCUROS=""
if echo "$ESTILO" | grep -qiE 'dark|oscuro'; then OSCUROS="$USUARIO;"; fi
echo "  estilo de $USUARIO:${OSCUROS:+ oscuro}${OSCUROS:- claro} ($ESTILO)"

paso "Configuración: $CONF"
cat > "$CONF" <<CONF
# slick-greeter-mac (mint-macos, login/instalar.sh). La del slick-greeter de
# Mint es /etc/lightdm/slick-greeter.conf y no se toca.
[Greeter]
background=$FONDO_CLARO
background-claro=$FONDO_CLARO
background-oscuro=$FONDO_OSCURO
usuarios-oscuros=$OSCUROS
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
  echo "  activado: sale en el próximo inicio de sesión y al cambiar de usuario."
  echo "  Para bloquear también con ella: $AQUI/bloqueo.sh (sin sudo)"
else
  paso "Instalado, sin activar"
  echo "  El login sigue siendo el de Mint. Para ponerlo: sudo $0 --activar"
fi
