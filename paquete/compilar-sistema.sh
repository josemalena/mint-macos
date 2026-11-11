#!/usr/bin/env bash
# Compila en ESTA computadora, sin root, lo que el paquete instala ya compilado en la otra
# (José, 10-11-2026: «que no haya que compilar para instalar, solo los binarios», y sin exigir
# el usuario jmalena). Cada pieza queda como un árbol de DESTDIR con prefijo /usr/local, que la
# otra computadora copia a / como root (requisitos.sh y login/instalar.sh):
#
#   SALIDA/fynder-muelle/usr/local/…   Fynder (fork de Nemo), con el módulo de GTK del selector de
#                                      Open/Save si lo trae, y Muelle (fork de plank-reloaded)
#   SALIDA/keyd/usr/local/…            keyd $KEYD_VERSION
#   SALIDA/fsapfs/usr/local/…          libfsapfs $LIBFSAPFS_VERSION (fsapfsinfo, fsapfsmount)
#   SALIDA/greeter/slick-greeter-mac   la pantalla de inicio, del GREETER_HASH (prefijo /usr/local)
#   SALIDA/VERSIONES                   de qué commit o versión salió cada una
#
#   paquete/compilar-sistema.sh SALIDA [fynder muelle greeter keyd fsapfs]   (sin piezas: todas)
#
# Las fuentes (cada paso dice de qué carpeta y commit sale):
#   Fynder y Muelle  el HEAD commiteado de los repos de al lado de mint-macos, los mismos de
#                    paquete.sh (FYNDER_LOCAL y PLANK_LOCAL: repos/fynder y repos/plank-reloaded),
#                    o FYNDER_FUENTE y MUELLE_FUENTE. Nunca ~/.cache/mint-macos/src, que se quedó
#                    atrás (10-11-2026: un paquete salió con un Fynder 173 commits más viejo que el de
#                    José). Las opciones de meson son las de fynder/instalar-fynder.sh (las de
#                    meson_options.txt y el perfil de macOS), pero en release
#   greeter          el GREETER_HASH de versiones.sh, del repo local que lo tenga (GREETER_FUENTE)
#   keyd             la etiqueta $KEYD_VERSION de github.com/rvaiya/keyd
#   libfsapfs        la versión publicada, con el sha256 del manifiesto (apfs/instalar-fsapfs.sh)
# Nunca se toca lo que esta computadora tiene instalado en ~/.local ni sus builds.
#
# Regla de José (18-10-2026, «cpu al 100%»): una compilación a la vez, con la menor prioridad y
# dos hilos; si ya hay otro ninja corriendo, se espera a que termine.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/versiones.sh"
SALIDA="${1:?uso: compilar-sistema.sh SALIDA [fynder muelle greeter keyd fsapfs]}"
shift
PIEZAS=("$@"); [ ${#PIEZAS[@]} -gt 0 ] || PIEZAS=(fynder muelle greeter keyd fsapfs)
mkdir -p "$SALIDA"; SALIDA="$(cd "$SALIDA" && pwd)"
TRABAJO="$SALIDA/.trabajo"; mkdir -p "$TRABAJO"
VERSIONES="$SALIDA/VERSIONES"; touch "$VERSIONES"

paso() { printf '\n▸ %s\n' "$*"; }
bajo() { nice -n 19 ionice -c3 "$@"; }
esperar_ninja() { while pgrep -x ninja >/dev/null || pgrep -x cargo >/dev/null; do sleep 10; done; }
anotar() { # pieza texto: una línea por pieza en VERSIONES
  grep -v "^$1=" "$VERSIONES" > "$VERSIONES.nuevo" || true
  echo "$1=$2" >> "$VERSIONES.nuevo"; mv "$VERSIONES.nuevo" "$VERSIONES"
}
# El árbol del HEAD commiteado (sin .git ni lo que esté a medias en la carpeta de trabajo).
fuente_head() { # repo destino
  rm -rf -- "${2:?}"; mkdir -p "$2"
  git -C "$1" archive HEAD | tar -x -C "$2"
}
meson_sistema() { # fuente build destdir opciones…  (el destdir se vacía antes)
  local src="$1" build="$2" dest="$3"; shift 3
  rm -rf -- "${build:?}" "${dest:?}"
  meson setup "$build" "$src" --prefix=/usr/local --buildtype=release "$@" >/dev/null
  esperar_ninja
  bajo ninja -j2 -C "$build" >/dev/null
  DESTDIR="$dest" meson install -C "$build" --no-rebuild --quiet
}
# Fynder y Muelle se instalan cada uno en su destdir (así no quedan restos de una fuente anterior)
# y SALIDA/fynder-muelle es la unión de los dos. Si falta uno (una SALIDA de antes, cuando los dos
# iban directo ahí), se copia encima y no se borra lo que había.
unir_fynder_muelle() {
  if [ -d "$TRABAJO/dest-fynder" ] && [ -d "$TRABAJO/dest-muelle" ]; then rm -rf -- "${SALIDA:?}/fynder-muelle"; fi
  mkdir -p "$SALIDA/fynder-muelle"
  local d
  for d in "$TRABAJO/dest-fynder" "$TRABAJO/dest-muelle"; do
    [ -d "$d" ] && cp -a "$d/." "$SALIDA/fynder-muelle/"
  done
  return 0
}
# De dónde sale una pieza: la carpeta, el commit y su fecha, y si hay cambios sin commitear.
contar_fuente() { # nombre repo
  paso "$1 $(git -C "$2" log -1 --format='%h del %cd' --date=format:'%d-%m-%Y %H:%M' HEAD)"
  echo "  de $2: $(git -C "$2" log -1 --format=%s HEAD | cut -c1-90)"
  [ -z "$(git -C "$2" status --porcelain --untracked-files=no)" ] \
    || echo "  ojo: $2 tiene cambios sin commitear; va solo el HEAD"
}

for pieza in "${PIEZAS[@]}"; do
  case "$pieza" in
    fynder)
      F="${FYNDER_FUENTE:-$(dirname "$REPO")/$FYNDER_LOCAL}"
      [ -d "$F/.git" ] || { echo "✗ no está el repo de Fynder en $F (FYNDER_FUENTE)"; exit 1; }
      H="$(git -C "$F" rev-parse HEAD)"
      contar_fuente Fynder "$F"
      fuente_head "$F" "$TRABAJO/fynder-src"
      # La versión del About es la de fynder/instalar-fynder.sh: 1.0.<commits desde el fork de Nemo>,
      # la misma que el Fynder de José del mismo commit. El número de build es esa misma cuenta
      # (FYNDER_BUILD_NUMBER), nunca el contador de ~/.local/state/fynder de José, que sube con cada
      # compilación suya (10-11-2026 se movió uno y se devolvió); un Fynder viejo, sin
      # FYNDER_BUILD_NUMBER, sube un contador propio en vez del de José.
      N="$(git -C "$F" rev-list --count --no-merges "$FYNDER_BASE..HEAD")"
      echo "$N" > "$TRABAJO/fynder-build-number"
      # El perfil de macOS (perfiles/ESQUEMA.md), del HEAD de mint-macos, si el Fynder tiene la opción.
      PERFIL=()
      if grep -q perfil_macos "$TRABAJO/fynder-src/meson_options.txt"; then
        git -C "$REPO" show HEAD:perfiles/vala/perfil-macos.vala > "$TRABAJO/perfil-macos.vala"
        PERFIL=(-Dperfil_macos="$TRABAJO/perfil-macos.vala")
      fi
      ( export FYNDER_BUILD_NUMBER="$N" FYNDER_BUILD_COUNTER="$TRABAJO/fynder-build-number" FYNDER_VERSION="1.0.$N"
        export SOURCE_DATE_EPOCH="$(git -C "$F" log -1 --format=%ct HEAD)"
        meson_sistema "$TRABAJO/fynder-src" "$TRABAJO/fynder-build" "$TRABAJO/dest-fynder" \
          -Ddeprecated_warnings=false -Dempty_view=false -Dexif=true -Dgtk_doc=false \
          -Dgtk_layer_shell=false -Dselinux=false -Dtracker=false -Dxmp=true "${PERFIL[@]}" )
      unir_fynder_muelle
      anotar fynder "$H"
      anotar fynder-version "1.0.$N"
      anotar fynder-fuente "$(basename "$F")"
      MOD="$(cd "$TRABAJO/dest-fynder" && ls usr/local/lib/*/gtk-3.0/modules/libfynder-chooser-module.so 2>/dev/null || true)"
      echo "  1.0.$N (build $N); módulo del selector de Open/Save: ${MOD:-no lo trae}"
      echo "  en $SALIDA/fynder-muelle/usr/local"
      ;;
    muelle)
      M="${MUELLE_FUENTE:-$(dirname "$REPO")/$PLANK_LOCAL}"
      [ -d "$M/.git" ] || { echo "✗ no está el repo de Muelle en $M (MUELLE_FUENTE)"; exit 1; }
      H="$(git -C "$M" rev-parse HEAD)"
      contar_fuente Muelle "$M"
      fuente_head "$M" "$TRABAJO/muelle-src"
      # Con el rpath, Muelle y sus docklets cargan la libplank del fork aunque la computadora
      # tenga el plank de Mint (su libplank.so.1 en /lib); lo mismo hace armar.sh.
      LDFLAGS="-Wl,-rpath,/usr/local/lib/$(gcc -print-multiarch)" \
      meson_sistema "$TRABAJO/muelle-src" "$TRABAJO/muelle-build" "$TRABAJO/dest-muelle" \
        -Denable-apport=false -Denable-docs=false -Denable-benchmark=false \
        -Denable-gmock=false -Denable-headless-tests=false -Dproduction-release=false
      unir_fynder_muelle
      anotar muelle "$H"
      anotar muelle-fuente "$(basename "$M")"
      echo "  en $SALIDA/fynder-muelle/usr/local"
      ;;
    greeter)
      G=""
      for g in "${GREETER_FUENTE:-}" "$(dirname "$REPO")/$GREETER_LOCAL"; do
        [ -n "$g" ] && git -C "$g" cat-file -e "$GREETER_HASH^{commit}" 2>/dev/null && { G="$g"; break; }
      done
      [ -n "$G" ] || { echo "✗ ningún repo local tiene el greeter $GREETER_HASH (GREETER_FUENTE)"; exit 1; }
      paso "slick-greeter-mac ${GREETER_HASH:0:7} (de $G)"
      rm -rf -- "$TRABAJO/greeter-src"; mkdir -p "$TRABAJO/greeter-src"
      git -C "$G" archive "$GREETER_HASH" | tar -x -C "$TRABAJO/greeter-src"
      rm -rf -- "$TRABAJO/greeter-build"
      # Como login/instalar.sh, que lo compilaba en la otra computadora: prefijo /usr/local.
      meson setup "$TRABAJO/greeter-build" "$TRABAJO/greeter-src" --prefix=/usr/local --buildtype=release >/dev/null
      esperar_ninja
      bajo ninja -j2 -C "$TRABAJO/greeter-build" >/dev/null
      install -D -m 755 "$TRABAJO/greeter-build/src/slick-greeter-mac" "$SALIDA/greeter/slick-greeter-mac"
      anotar greeter "$GREETER_HASH"
      echo "  $SALIDA/greeter/slick-greeter-mac"
      ;;
    keyd)
      paso "keyd $KEYD_VERSION"
      rm -rf -- "$TRABAJO/keyd" "$SALIDA/keyd"
      git clone -q --depth 1 --branch "$KEYD_VERSION" https://github.com/rvaiya/keyd.git "$TRABAJO/keyd"
      esperar_ninja
      bajo make -j2 -C "$TRABAJO/keyd" PREFIX=/usr/local >/dev/null
      # El install de keyd, a un DESTDIR. Su unidad de systemd la escribe solo si ve systemd (aquí sí).
      make -C "$TRABAJO/keyd" PREFIX=/usr/local DESTDIR="$SALIDA/keyd" install >/dev/null
      anotar keyd "$KEYD_VERSION"
      echo "  en $SALIDA/keyd/usr/local"
      ;;
    fsapfs)
      paso "libfsapfs $LIBFSAPFS_VERSION"
      rm -rf -- "$SALIDA/fsapfs"
      esperar_ninja
      FSAPFS_SOLO_COMPILAR="$SALIDA/fsapfs" FSAPFS_HILOS=2 bajo bash "$REPO/apfs/instalar-fsapfs.sh" >/dev/null
      anotar fsapfs "$LIBFSAPFS_VERSION"
      echo "  en $SALIDA/fsapfs/usr/local"
      ;;
    *) echo "✗ pieza desconocida: $pieza (fynder muelle greeter keyd fsapfs)"; exit 2 ;;
  esac
done

paso "Listo: $SALIDA"
cat "$VERSIONES"
