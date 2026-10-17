#!/usr/bin/env bash
# Lo único de mint-macos que necesita sudo, en un solo bloque. Todo lo demás
# (construir.sh, desde-mac.sh, migrar-datos.sh, instalar.sh) corre como el
# usuario y escribe en su $HOME.
#
#   sudo ./requisitos.sh                     instala
#   ./requisitos.sh --simular                dice qué haría, sin tocar nada (apt-get -s)
#   sudo ./requisitos.sh --quitar-rutas-mac  quita /Users, /Volumes y /Applications
#                                            (solo lo que creó él; /Applications, vacía)
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
#     donde udisks monta los discos del usuario (/media/USUARIO); y
#     /Applications como carpeta real del usuario (la llena aplicaciones/).
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
# /Applications no es enlace: es una carpeta real del usuario, porque Fynder
# tiene que verla como /Applications y aplicaciones/ escribe en ella sin sudo.
# La marca dice que la creó mint-macos; sin ella, --quitar-rutas-mac no la toca.
MARCA_APPS="$RAIZ/var/lib/mint-macos/applications-creada"
rutas_mac() { # → «enlace destino» por línea
  local medios="$RAIZ/media/$USUARIO"
  [ -d "$RAIZ/run/media" ] && [ ! -d "$RAIZ/media/$USUARIO" ] && medios="$RAIZ/run/media/$USUARIO"
  printf '%s %s\n' "$RAIZ/Users" "$RAIZ/home" "$RAIZ/Volumes" "$medios"
}
if $QUITAR_RUTAS; then
  paso "Quitando /Users, /Volumes y /Applications"
  [ -n "$RAIZ" ] || [ "$(id -u)" = 0 ] || { echo "  ✗ corre esto con sudo"; exit 1; }
  while read -r enlace destino; do
    if [ -L "$enlace" ] && [ "$(readlink "$enlace")" = "$destino" ]; then
      rm -- "$enlace"; echo "  quitado: $enlace"
    else
      echo "  $enlace no es el enlace de mint-macos; no se toca"
    fi
  done < <(rutas_mac)
  if [ -f "$MARCA_APPS" ] && [ -d "$RAIZ/Applications" ] && [ ! -L "$RAIZ/Applications" ]; then
    if rmdir -- "$RAIZ/Applications" 2>/dev/null; then rm -f -- "$MARCA_APPS"; echo "  quitada: $RAIZ/Applications"
    else echo "  $RAIZ/Applications no está vacía: corre antes aplicaciones/instalar.sh --quitar"; fi
  else
    echo "  $RAIZ/Applications no la creó mint-macos; no se toca"
  fi
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
  # nativo/: el agente de polkit en Vala (mac-polkit); sin ella se compila el resto
  libpolkit-agent-1-dev
  # la pantalla de inicio (slick-greeter-mac, login/instalar.sh)
  liblightdm-gobject-1-dev libpixman-1-dev
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
  # agente de polkit: el binario enlaza la librería; el de Python usa el typelib
  libpolkit-agent-1-0 gir1.2-polkit-1.0
  # System Preferences en Vala (nativo/preferencias): json-glib para pactl e iso-codes; ipptool para Printers & Scanners
  libjson-glib-1.0-0 cups-ipp-utils iso-codes
  # migrar-datos.sh
  rsync
  # capturas/ (⇧⌘3, ⇧⌘4…, la grabación de ⇧⌘5) y la carpeta del escritorio
  gnome-screenshot xdg-user-dirs ffmpeg
  # zsh, el shell de la Mac desde Catalina
  zsh
  # Spotlyte (el fork de Ulauncher): lo que pide el paquete ulauncher
  libkeybinder-3.0-0 gir1.2-keybinder-3.0 gir1.2-webkit2-4.1 gir1.2-notify-0.7
  gir1.2-gdkpixbuf-2.0 python3-gi-cairo python3-dbus python3-levenshtein
  python3-pyinotify python3-websocket python3-xdg gir1.2-ayatanaappindicator3-0.1
  # icloud/icloud.sh: la clave de rclone.conf cifrado en el llavero; unzip
  libsecret-tools unzip
  # tema/iconos/car.py: los íconos que vienen en Assets.car (LZFSE) y los
  # glifos del Finder, que se dibujan de su PDF
  liblzfse1 poppler-utils
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

paso "zsh como shell, como en Catalina"
ZSH_BIN="$(command -v zsh || echo /usr/bin/zsh)"
ACTUAL="$(getent passwd "$USUARIO" | cut -d: -f7)"
if [ "$ACTUAL" = "$ZSH_BIN" ]; then
  echo "  ya está"
elif $SIMULAR; then
  echo "  $USUARIO pasaría de $ACTUAL a $ZSH_BIN"
else
  chsh -s "$ZSH_BIN" "$USUARIO"
  echo "  $USUARIO: $ACTUAL → $ZSH_BIN (vale al volver a entrar; para volver: sudo chsh -s $ACTUAL $USUARIO)"
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

# Firefox publica su menú en la barra solo con widget.gtk.global-menu.enabled.
# menu-global/instalar.sh lo pone en el user.js del perfil, pero en una
# computadora nueva Firefox todavía no tiene perfil (iMac, 15-10-2026): va
# también como política del sistema, con «default» para que se pueda cambiar.
paso "Firefox: el menú en la barra (política del sistema)"
POL=/etc/firefox/policies/policies.json
if $SIMULAR; then
  echo "  se pondría widget.gtk.global-menu.enabled en $POL"
else
  mkdir -p "$(dirname "$POL")"
  python3 - "$POL" <<'PY'
import json, os, sys
f = sys.argv[1]
d = json.load(open(f)) if os.path.exists(f) else {}
pref = d.setdefault("policies", {}).setdefault("Preferences", {})
pref["widget.gtk.global-menu.enabled"] = {"Value": True, "Status": "default"}
json.dump(d, open(f, "w"), indent=2)
PY
  echo "  $POL (Firefox lo toma al abrirlo otra vez)"
fi

paso "Rutas de macOS: /Users, /Volumes y /Applications"
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
GRUPO="$(id -gn "$USUARIO")"
if [ -L "$RAIZ/Applications" ] || { [ -e "$RAIZ/Applications" ] && [ ! -d "$RAIZ/Applications" ]; }; then
  echo "  ⚠ $RAIZ/Applications existe y no es una carpeta: no se toca"
elif [ -d "$RAIZ/Applications" ]; then
  echo "  ya está: $RAIZ/Applications ($(stat -c %U:%G "$RAIZ/Applications"))"
elif $SIMULAR; then
  echo "  se crearía $RAIZ/Applications, carpeta de $USUARIO:$GRUPO"
else
  install -d -o "$USUARIO" -g "$GRUPO" -m 755 "$RAIZ/Applications"
  install -D -m 644 /dev/null "$MARCA_APPS"
  echo "  $RAIZ/Applications, carpeta de $USUARIO:$GRUPO"
fi

paso "Listo"
$SIMULAR && echo "  nada cambió (simulado)" || echo "  ahora, sin sudo: ./instalar.sh --disco /dev/sdX2 --usuario-mac NOMBRE"
