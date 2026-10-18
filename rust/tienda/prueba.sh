#!/usr/bin/env bash
# El motor del App Store de punta a punta, sin tocar nada de José: bus de sesión
# aparte (con la activación por D-Bus de verdad), un PackageKit de mentira en otro
# bus, Flathub y ODRS en un servidor local, catálogos de juguete (DEP-11 y
# appstream.xml) y un repo de Flatpak de juguete en FLATPAK_USER_DIR propio.
#
#   rust/tienda/prueba.sh [BINARIO]   (por defecto rust/target/debug/mint-macos-tienda)
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
BIN="$(realpath "${1:-$AQUI/../target/debug/mint-macos-tienda}")"
[ -x "$BIN" ] || { echo "✗ falta $BIN (cargo build -p mint-macos-tienda)"; exit 1; }
T="$(mktemp -d)"
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$T"' EXIT
export FLATPAK_USER_DIR="$T/inst" FLATPAK_SYSTEM_DIR="$T/sys" TIENDA_RAIZ="$T/raiz" \
  XDG_CACHE_HOME="$T/cache" XDG_DATA_HOME="$T/data" XDG_CONFIG_HOME="$T/config" XDG_STATE_HOME="$T/state" \
  GSETTINGS_BACKEND=memory GIO_USE_VFS=local LANG=C.UTF-8
mkdir -p "$T"/{inst,sys,cache,data,config,state} "$T/raiz/var/lib/swcatalog/yaml" "$T/raiz/var/lib/dpkg" \
  "$T/raiz/etc/linuxmint" "$T/raiz/usr/share/mint-upgrade-info/zena" "$T/raiz/usr/bin"

# APT: tres apps con ficha DEP-11 (libalgo no tiene: es «sistema»).
cat > "$T/dep11.yml" <<'FIN'
---
File: DEP-11
Version: '0.14'
Origin: prueba
MediaBaseUrl: https://media.prueba
---
Type: desktop-application
ID: org.juego.Apt
Package: juego-apt
Name:
  C: Juego de APT
Summary:
  C: Un juego de juguete
Categories:
- Game
---
Type: desktop-application
ID: prohibido.desktop
Package: prohibido
Name:
  C: Prohibido
Summary:
  C: polkit dice que no
---
Type: desktop-application
ID: editor.desktop
Package: editor-viejo
Name:
  C: Editor viejo
Summary:
  C: Instalado con una actualización
FIN
gzip -c "$T/dep11.yml" > "$T/raiz/var/lib/swcatalog/yaml/prueba_dep11_Components-amd64.yml.gz"
printf 'Package: editor-viejo\nStatus: install ok installed\nVersion: 1.0\n\nPackage: libalgo\nStatus: install ok installed\nVersion: 1.0\n\n' > "$T/raiz/var/lib/dpkg/status"
printf 'RELEASE=22.3\nCODENAME=zena\nEDITION="Cinnamon"\n' > "$T/raiz/etc/linuxmint/info"
printf '[general]\ntarget_name = "Linux Mint 22.4 Prueba"\ntarget_codename = prueba\neditions = cinnamon\n' > "$T/raiz/usr/share/mint-upgrade-info/zena/info"
: > "$T/raiz/usr/bin/mint-release-upgrade"

# Flatpak: un runtime y una app de juguete en un repo file:// que se llama flathub.
mkdir -p "$T/rt/usr/bin" "$T/rt/files" "$T/app/files/bin" "$T/app/export"
printf '[Runtime]\nname=org.mintmacos.Juguete.Platform\nruntime=org.mintmacos.Juguete.Platform/x86_64/1\nsdk=org.mintmacos.Juguete.Platform/x86_64/1\n' > "$T/rt/metadata"
printf '[Application]\nname=org.mintmacos.Juguete\nruntime=org.mintmacos.Juguete.Platform/x86_64/1\nsdk=org.mintmacos.Juguete.Platform/x86_64/1\ncommand=hola\n' > "$T/app/metadata"
printf '#!/bin/sh\necho juguete\n' > "$T/app/files/bin/hola"; chmod +x "$T/app/files/bin/hola"
head -c $((1 << 20)) /dev/urandom > "$T/app/files/relleno"
flatpak build-export --runtime "$T/repo" "$T/rt" 1 >/dev/null
flatpak build-export "$T/repo" "$T/app" stable >/dev/null
flatpak --user remote-add --no-gpg-verify flathub "file://$T/repo"
A="$T/inst/appstream/flathub/x86_64/active"
mkdir -p "$A"
cat > "$A/appstream.xml" <<'FIN'
<?xml version="1.0" encoding="UTF-8"?>
<components version="0.8" origin="flathub">
  <component type="desktop-application">
    <id>org.mintmacos.Juguete</id>
    <name>Juguete</name>
    <summary>Una app de juguete</summary>
    <description><p>Para probar el motor.</p></description>
    <categories><category>Utility</category></categories>
    <screenshots><screenshot type="default"><image type="source" width="800">https://img/juguete.png</image></screenshot></screenshots>
    <releases><release version="1" timestamp="1790000000"/></releases>
    <bundle type="flatpak">app/org.mintmacos.Juguete/x86_64/stable</bundle>
  </component>
</components>
FIN

# La activación por D-Bus: el mismo .service que instala instalar.sh.
mkdir -p "$T/data/dbus-1/services"
printf '[D-BUS Service]\nName=org.mintmacos.Tienda1\nExec=%s\n' "$BIN" > "$T/data/dbus-1/services/org.mintmacos.Tienda1.service"

cat > "$T/dentro.sh" <<'FIN'
set -euo pipefail
T="$1"; AQUI="$2"
# El «bus de sistema» de PackageKit: otro dbus-daemon, solo de la prueba.
dbus-daemon --session --nofork --print-address=3 3> "$T/bus-pk" & echo $! > "$T/pid-bus"
for _ in $(seq 50); do [ -s "$T/bus-pk" ] && break; sleep 0.1; done
export TIENDA_BUS_SISTEMA="$(head -1 "$T/bus-pk")"
python3 -I "$AQUI/prueba/falsos.py" pk "$TIENDA_BUS_SISTEMA" "$T/raiz/var/lib/dpkg/status" "$T/pk.log" > "$T/pk.listo" & echo $! > "$T/pid-pk"
python3 -I "$AQUI/prueba/falsos.py" web "$T/puerto" & echo $! > "$T/pid-web"
for _ in $(seq 50); do [ -s "$T/pk.listo" ] && [ -s "$T/puerto" ] && break; sleep 0.1; done
export TIENDA_FLATHUB="http://127.0.0.1:$(cat "$T/puerto")/api/v2" TIENDA_ODRS="http://127.0.0.1:$(cat "$T/puerto")/odrs"
# La activación hereda el entorno del bus; se lo pasamos al daemon.
dbus-update-activation-environment TIENDA_BUS_SISTEMA TIENDA_FLATHUB TIENDA_ODRS TIENDA_RAIZ FLATPAK_USER_DIR FLATPAK_SYSTEM_DIR \
  XDG_CACHE_HOME XDG_DATA_HOME XDG_CONFIG_HOME XDG_STATE_HOME GSETTINGS_BACKEND GIO_USE_VFS LANG
r=0
python3 -I "$AQUI/prueba/cliente.py" "$T" || r=$?
# El servicio activado: si no se cierra, dbus-run-session lo espera 10 minutos.
P=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus GetConnectionUnixProcessID s org.mintmacos.Tienda1 2>/dev/null | awk '{print $2}')
[ -n "$P" ] && kill "$P" 2>/dev/null
kill "$(cat "$T/pid-pk")" "$(cat "$T/pid-web")" "$(cat "$T/pid-bus")" 2>/dev/null || true
exit $r
FIN
mkdir -m 700 "$T/runtime"
XDG_RUNTIME_DIR="$T/runtime" dbus-run-session -- bash "$T/dentro.sh" "$T" "$AQUI"
