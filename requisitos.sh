#!/usr/bin/env bash
# Lo único de mint-macos que necesita sudo, en un solo bloque. Todo lo demás
# (construir.sh, desde-mac.sh, migrar-datos.sh, instalar.sh) corre como el
# usuario y escribe en su $HOME.
#
#   sudo ./requisitos.sh                     instala
#   ./requisitos.sh --simular                dice qué haría, sin tocar nada (apt-get -s)
#   sudo ./requisitos.sh --quitar-rutas-mac  quita /Users y /Volumes (solo si son nuestros)
#
# Qué pone:
#   - los paquetes de apt para compilar Fynder (fork de Nemo) y mint-macos-dock,
#     y los que usan en ejecución el tema, los applets y el menú global;
#   - keyd (⌘ y ⌥ como en macOS), compilado: no está en Mint 22;
#   - fsapfsinfo y fsapfsmount (leer el disco de la Mac), compilados: la
#     versión de apt (libfsapfs-utils 2020) no lee los APFS de hoy;
#   - /etc/keyd/default.conf, el grupo keyd para el usuario y
#     user_allow_other en /etc/fuse.conf (montar el disco de la Mac desde Nemo);
#   - las rutas de macOS como enlaces: /Users → /home y /Volumes → la carpeta
#     donde udisks monta los discos del usuario (/media/USUARIO).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SIMULAR=false
QUITAR_RUTAS=false
case "${1:-}" in
  --simular) SIMULAR=true ;;
  --quitar-rutas-mac) QUITAR_RUTAS=true ;;
esac
# Para probar los enlaces sin tocar «/»: MINT_MACOS_RAIZ=/tmp/raiz ./requisitos.sh …
RAIZ="${MINT_MACOS_RAIZ:-}"
USUARIO="${SUDO_USER:-${USER:-$(id -un)}}"
KEYD_VERSION=v2.6.0

paso() { printf '\n▸ %s\n' "$*"; }

# Las rutas de macOS. Son enlaces y nada más: los discos se siguen montando
# donde los monta udisks (la ruta viene compilada, no se configura) y $HOME
# sigue en /home; mover cualquiera de las dos rompe fstab, Docker, snaps y
# las rutas guardadas. Con el mismo usuario y uid que en la Mac (jmalena, 501),
# /Users/jmalena/... y /Volumes/<disco>/... valen igual en las dos.
# Nunca se pisa algo que ya exista con ese nombre.
rutas_mac() { # → «enlace destino» por línea
  local medios="$RAIZ/media/$USUARIO"
  [ -d "$RAIZ/run/media" ] && [ ! -d "$RAIZ/media/$USUARIO" ] && medios="$RAIZ/run/media/$USUARIO"
  printf '%s %s\n' "$RAIZ/Users" "$RAIZ/home" "$RAIZ/Volumes" "$medios"
}
if $QUITAR_RUTAS; then
  paso "Quitando /Users y /Volumes"
  [ -n "$RAIZ" ] || [ "$(id -u)" = 0 ] || { echo "  ✗ corre esto con sudo"; exit 1; }
  while read -r enlace destino; do
    if [ -L "$enlace" ] && [ "$(readlink "$enlace")" = "$destino" ]; then
      rm -- "$enlace"; echo "  quitado: $enlace"
    else
      echo "  $enlace no es el enlace de mint-macos; no se toca"
    fi
  done < <(rutas_mac)
  exit 0
fi

# Fynder: lista explícita de nemo-mac-e1 (build-dep nemo pide deb-src y trae
# de más). mint-macos-dock (fork de plank-reloaded): lista de la sesión de Plank.
COMPILAR=(
  build-essential pkg-config git meson ninja-build gettext
  gobject-introspection libgirepository1.0-dev libglib2.0-dev libglib2.0-dev-bin
  libgtk-3-dev libatk1.0-dev libpango1.0-dev libjson-glib-dev libcinnamon-desktop-dev
  libgail-3-dev libx11-dev libxapp-dev libexif-dev libexempi-dev
  valac libgdk-pixbuf-2.0-dev libgee-0.8-dev libbamf3-dev libcairo2-dev libwnck-3-dev
  libgnome-menu-3-dev libcanberra-dev libdbusmenu-glib-dev libdbusmenu-gtk3-dev
  libxi-dev libxfixes-dev
  # keyd y libfsapfs
  python3-xlib autoconf automake autopoint libtool libssl-dev libfuse3-dev fuse3 curl
)
EJECUCION=(
  # Fynder y el dock
  nemo-preview gvfs shared-mime-info bamfdaemon
  # menú global (lado apps; appmenu-registrar ya no hace falta)
  appmenu-gtk2-module appmenu-gtk3-module libdbusmenu-glib4 libdbusmenu-gtk3-4
  # tema Constanza y lo que se saca de la Mac
  sassc imagemagick libheif1 libheif-plugin-libde265 fontconfig
  python3 python3-gi gir1.2-gtk-3.0 python3-pil python3-fonttools
  # applets del menú Apple y Force Quit
  wmctrl xdotool cinnamon-screensaver
  # migrar-datos.sh
  rsync
  # capturas/ (⇧⌘3, ⇧⌘4…) y la carpeta del escritorio
  gnome-screenshot xdg-user-dirs
  # icloud/icloud.sh: la clave de rclone.conf cifrado en el llavero; unzip
  libsecret-tools unzip
)

paso "Paquetes de apt (${#COMPILAR[@]} para compilar, ${#EJECUCION[@]} en ejecución)"
if $SIMULAR; then
  apt-get -s install "${COMPILAR[@]}" "${EJECUCION[@]}" 2>&1 | grep -E '^(Inst|E:)' | sed 's/^/  /' | head -60 || true
  echo "  (simulado: $(apt-get -s install "${COMPILAR[@]}" "${EJECUCION[@]}" 2>/dev/null | grep -c '^Inst') paquetes nuevos)"
else
  [ "$(id -u)" = 0 ] || { echo "  ✗ corre esto con sudo (o con --simular)"; exit 1; }
  apt-get update -q
  apt-get install -y "${COMPILAR[@]}" "${EJECUCION[@]}"
fi

paso "keyd $KEYD_VERSION"
if command -v keyd >/dev/null && keyd --version 2>/dev/null | grep -q "$KEYD_VERSION"; then
  echo "  ya está"
elif $SIMULAR; then
  echo "  se compilaría desde github.com/rvaiya/keyd ($KEYD_VERSION) y se instalaría en /usr/local"
else
  TMP="$(mktemp -d)"
  git clone -q --depth 1 --branch "$KEYD_VERSION" https://github.com/rvaiya/keyd.git "$TMP/keyd"
  make -C "$TMP/keyd"
  make -C "$TMP/keyd" install
fi
if $SIMULAR; then
  echo "  se copiaría keyd/default.conf a /etc/keyd/ y $USUARIO entraría al grupo keyd"
else
  [ -e /etc/keyd/default.conf ] && cp -a /etc/keyd/default.conf "/etc/keyd/default.conf.antes-mint-macos-$(date +%Y%m%d-%H%M%S)"
  keyd check "$REPO/keyd/default.conf"
  install -D -m 644 "$REPO/keyd/default.conf" /etc/keyd/default.conf
  # En un contenedor (sin systemd) se instala igual, pero no se arranca.
  if [ -d /run/systemd/system ]; then systemctl enable --now keyd; keyd reload
  else echo "  sin systemd (¿contenedor?): keyd instalado pero no arrancado"; fi
  groupadd -f keyd
  id -nG "$USUARIO" | grep -qw keyd || { usermod -aG keyd "$USUARIO"; echo "  $USUARIO entra al grupo keyd (vale al volver a entrar)"; }
fi

paso "fsapfsinfo y fsapfsmount (leer el disco APFS de la Mac)"
if command -v fsapfsmount >/dev/null; then
  echo "  ya están: $(command -v fsapfsmount)"
elif $SIMULAR; then
  echo "  se compilaría libfsapfs con apfs/instalar-fsapfs.sh (en /usr/local)"
else
  # instalar-fsapfs.sh usa sudo por dentro; como root no pide clave.
  bash "$REPO/apfs/instalar-fsapfs.sh"
fi
if $SIMULAR; then
  grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null && echo "  user_allow_other ya está en /etc/fuse.conf" \
    || echo "  se activaría user_allow_other en /etc/fuse.conf"
else
  grep -q '^user_allow_other' /etc/fuse.conf || sed -i 's/^#\s*user_allow_other/user_allow_other/' /etc/fuse.conf
  grep -q '^user_allow_other' /etc/fuse.conf || echo 'user_allow_other' >> /etc/fuse.conf
  id -nG "$USUARIO" | grep -qw disk || { usermod -aG disk "$USUARIO"; echo "  $USUARIO entra al grupo disk (leer /dev/sdX sin sudo)"; }
fi

paso "Rutas de macOS: /Users y /Volumes"
while read -r enlace destino; do
  if [ -L "$enlace" ] && [ "$(readlink "$enlace")" = "$destino" ]; then
    echo "  ya está: $enlace → $destino"
  elif [ -e "$enlace" ] || [ -L "$enlace" ]; then
    echo "  ⚠ $enlace ya existe y no es nuestro: no se toca"
  elif $SIMULAR; then
    echo "  se crearía $enlace → $destino"
  else
    ln -s "$destino" "$enlace"; echo "  $enlace → $destino"
  fi
done < <(rutas_mac)

paso "Listo"
$SIMULAR && echo "  nada cambió (simulado)" || echo "  ahora, sin sudo: ./instalar.sh --disco /dev/sdX2 --usuario-mac NOMBRE"
