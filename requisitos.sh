#!/usr/bin/env bash
# Lo único de mint-macos que necesita sudo, en un solo bloque. Todo lo demás
# (construir.sh, desde-mac.sh, migrar-datos.sh, instalar.sh) corre como el
# usuario y escribe en su $HOME.
#
#   sudo ./requisitos.sh                     instala
#   ./requisitos.sh --simular                dice qué haría, sin tocar nada (apt-get -s)
#   sudo ./requisitos.sh --quitar-rutas-mac  quita /Users, /Volumes, /Applications y ~/Library
#                                            (solo lo que creó él; /Applications y ~/Library, vacías)
#
# Qué pone:
#   - los paquetes de apt para compilar Fynder (fork de Nemo) y Muelle,
#     y los que usan en ejecución el tema, los applets y el menú global;
#   - keyd (⌘ y ⌥ como en macOS), compilado: no está en Mint 22;
#   - fsapfsinfo y fsapfsmount (leer el disco de la Mac), compilados: la
#     versión de apt (libfsapfs-utils 2020) no lee los APFS de hoy;
#   - con el paquete (instalar-aqui.sh deja en el repo la carpeta compilado/, de
#     paquete/compilar-sistema.sh): Fynder, Muelle, keyd y libfsapfs ya compilados,
#     copiados a /usr/local, y de apt solo lo de ejecución. Nada se compila aquí
#     y sirve cualquier usuario (José, 10-11-2026);
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
# ~/Library: vacía, del usuario (no de root) y 700 como en la Mac; las
# subcarpetas las pone Darling cuando hagan falta. Misma regla de la marca.
LIBRARY="$RAIZ$(getent passwd "$USUARIO" | cut -d: -f6)/Library"
MARCA_LIBRARY="$RAIZ/var/lib/mint-macos/library-creada"
rutas_mac() { # → «enlace destino» por línea
  local medios="$RAIZ/media/$USUARIO"
  [ -d "$RAIZ/run/media" ] && [ ! -d "$RAIZ/media/$USUARIO" ] && medios="$RAIZ/run/media/$USUARIO"
  printf '%s %s\n' "$RAIZ/Users" "$RAIZ/home" "$RAIZ/Volumes" "$medios"
}
if $QUITAR_RUTAS; then
  paso "Quitando /Users, /Volumes, /Applications y ~/Library"
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
  if [ -f "$MARCA_LIBRARY" ] && [ -d "$LIBRARY" ] && [ ! -L "$LIBRARY" ]; then
    if rmdir -- "$LIBRARY" 2>/dev/null; then rm -f -- "$MARCA_LIBRARY"; echo "  quitada: $LIBRARY"
    else echo "  $LIBRARY no está vacía: se deja"; fi
  else
    echo "  $LIBRARY no la creó mint-macos; no se toca"
  fi
  exit 0
fi

# Los paquetes de apt (COMPILAR y EJECUCION) y las versiones de keyd y
# libfsapfs están en el manifiesto.
source "$REPO/versiones.sh"

# Lo ya compilado que trae el paquete (paquete/compilar-sistema.sh; instalar-aqui.sh lo desempaca
# en el repo). Con eso no se compila nada aquí, y de apt va solo lo de ejecución.
COMPILADO="${MINT_MACOS_COMPILADO:-$REPO/compilado}"
HAY_COMPILADO=false; [ -f "$COMPILADO/VERSIONES" ] && HAY_COMPILADO=true
if $HAY_COMPILADO; then APT=("${EJECUCION[@]}" "${EJECUCION_COMPILADO[@]}"); QUE="ya compilado: solo lo de ejecución"
else APT=("${COMPILAR[@]}" "${EJECUCION[@]}"); QUE="${#COMPILAR[@]} para compilar, ${#EJECUCION[@]} en ejecución"; fi

paso "Paquetes de apt ($QUE)"
if $SIMULAR; then
  apt-get -s install "${APT[@]}" 2>&1 | grep -E '^(Inst|E:)' | sed 's/^/  /' | head -60 || true
  echo "  (simulado: $(apt-get -s install "${APT[@]}" 2>/dev/null | grep -c '^Inst') paquetes nuevos)"
else
  [ "$(id -u)" = 0 ] || { echo "  ✗ corre esto con sudo (o con --simular)"; exit 1; }
  apt-get update -q
  apt-get install -y "${APT[@]}"
fi

paso "Fynder y Muelle"
HOGAR_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"
if [ ! -d "$COMPILADO/fynder-muelle/usr/local" ]; then
  echo "  el paquete no los trae: instalar.sh los compila en el home (sin --sin-compilar)"
elif $SIMULAR; then
  echo "  se copiarían a /usr/local, ya compilados: $(ls "$COMPILADO/fynder-muelle/usr/local/bin" | tr '\n' ' ')"
else
  # Sin conservar el dueño: lo desempacó el usuario, y en /usr/local todo es de root.
  cp -dR --preserve=mode,timestamps "$COMPILADO/fynder-muelle/usr/local/." /usr/local/
  ldconfig
  [ -d /usr/local/share/glib-2.0/schemas ] && glib-compile-schemas /usr/local/share/glib-2.0/schemas
  [ -d /usr/local/share/applications ] && { update-desktop-database /usr/local/share/applications 2>/dev/null || true; }
  echo "  en /usr/local, ya compilados ($(grep -E '^(fynder|muelle)=' "$COMPILADO/VERSIONES" | cut -c1-14 | tr '\n' ' '))"
fi
# Una instalación de antes en el home (paquetes de antes del 10-11-2026, o instalar.sh sin
# --sin-compilar) va primero en el PATH y tapa la de /usr/local. No se borra nada: se avisa.
if $HAY_COMPILADO; then
  for b in fynder fynder-desktop muelle; do
    [ -e "$HOGAR_USUARIO/.local/bin/$b" ] && echo "  ⚠ $HOGAR_USUARIO/.local/bin/$b es de una instalación anterior y tapa la de /usr/local: quítalo cuando quieras usar la nueva"
  done
  # El esquema del home también le gana al de /usr/local: con uno más viejo, el Fynder nuevo se cae
  # al leer una clave que ese no tiene.
  ESQ_VIEJO="$HOGAR_USUARIO/.local/share/glib-2.0/schemas/io.github.josemalena.fynder.gschema.xml"
  [ -e "$ESQ_VIEJO" ] && echo "  ⚠ $ESQ_VIEJO también es de antes y le gana al de /usr/local: quítalo con los binarios (y glib-compile-schemas en esa carpeta)"
fi

paso "Un navegador Chromium para las apps web de iCloud"
# Las apps web de iCloud (icloud/apps-web.sh) van en ventanas --app de Chromium: con
# Firefox cada una lleva su perfil y pide la clave de Apple aparte (José, 18-10-2026).
# Solo si no hay Edge, Chrome, Chromium ni Brave, y solo el chromium de Mint (deb): el
# chromium-browser de Ubuntu es el transicional que trae el snap.
NAV_HAY=""
for n in microsoft-edge-stable google-chrome-stable chromium brave-browser; do
  command -v "$n" >/dev/null && { NAV_HAY="$n"; break; }
done
if [ -n "$NAV_HAY" ]; then
  echo "  ya hay uno: $NAV_HAY"
elif ! apt-cache policy chromium 2>/dev/null | grep -q 'Candidate:.*linuxmint'; then
  echo "  ⚠ no hay el chromium de Mint en los repositorios: las apps web de iCloud irán con Firefox"
elif $SIMULAR; then
  echo "  se instalaría chromium ($(apt-cache policy chromium | sed -n 's/ *Candidate: //p'))"
else
  apt-get install -y chromium
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
elif [ -x "$COMPILADO/keyd/usr/local/bin/keyd" ]; then
  if $SIMULAR; then echo "  se copiaría el keyd del paquete ($KEYD_VERSION, ya compilado) a /usr/local"
  else
    cp -dR --preserve=mode,timestamps "$COMPILADO/keyd/usr/local/." /usr/local/
    [ -d /run/systemd/system ] && systemctl daemon-reload
    echo "  el del paquete, ya compilado, en /usr/local"
  fi
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
  if [ -d "$COMPILADO/fsapfs/usr/local" ]; then echo "  se copiaría la libfsapfs del paquete (ya compilada) a /usr/local"
  else echo "  se compilaría libfsapfs con apfs/instalar-fsapfs.sh (en /usr/local)"; fi
elif [ -d "$COMPILADO/fsapfs/usr/local" ]; then
  # La del paquete: instalar-fsapfs.sh la copia y pone lo demás (mount.fsapfs, fuse.conf).
  FSAPFS_COMPILADO="$COMPILADO/fsapfs" bash "$REPO/apfs/instalar-fsapfs.sh"
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

paso "Rutas de macOS: /Users, /Volumes, /Applications y ~/Library"
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
if [ -L "$LIBRARY" ] || { [ -e "$LIBRARY" ] && [ ! -d "$LIBRARY" ]; }; then
  echo "  ⚠ $LIBRARY existe y no es una carpeta: no se toca"
elif [ -d "$LIBRARY" ]; then
  echo "  ya está: $LIBRARY ($(stat -c %U:%G "$LIBRARY"))"
elif $SIMULAR; then
  echo "  se crearía $LIBRARY, vacía, de $USUARIO:$GRUPO"
else
  install -d -o "$USUARIO" -g "$GRUPO" -m 700 "$LIBRARY"
  install -D -m 644 /dev/null "$MARCA_LIBRARY"
  echo "  $LIBRARY, vacía, de $USUARIO:$GRUPO"
fi

paso "Listo"
$SIMULAR && echo "  nada cambió (simulado)" || echo "  ahora, sin sudo: ./instalar.sh --disco /dev/sdX2 --usuario-mac NOMBRE"
