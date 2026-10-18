#!/usr/bin/env bash
# Arma el paquete de mint-macos desde cero, con un solo comando: nada sale de
# lo que esté instalado o compilado a medias en esta computadora.
#
#   ./armar.sh [carpeta]       por defecto ~/.cache/mint-macos/armado/<fecha-hora>
#   ./armar.sh --sin-paquete   compila y prueba, sin armar el paquete
#
# Pasos, todos con set -e (el primero que falla para todo):
#   1. clona mint-macos en su HEAD (lo commiteado; lo que esté a medias no va)
#   2. trae cada fork en el hash de versiones.sh: de su repo publicado y, si el
#      hash no está ahí, del repo local, con aviso
#   3. compila Fynder, el Dock y la pantalla de inicio (meson) y rust/ (cargo)
#   4. corre las pruebas: verificar-versiones.sh, cargo test, las de meson de
#      Fynder y del Dock (en un Xvfb aparte, con su propio bus y XDG) y las de
#      tareas reales (pruebas/correr.sh) con lo recién compilado
#   5. arma el paquete con paquete.sh, sobre lo compilado en 3 (nativo/ se compila
#      aquí también, para las pruebas; el del paquete y los binarios de rust los
#      compila paquete.sh del mismo HEAD)
#   6. deja en la carpeta SUMAS.sha256: el sha256 de cada archivo del paquete y
#      de cada archivo dentro de sus .tar.gz, para comparar dos corridas
#
# Necesita los paquetes de requisitos.sh, cargo, Xephyr y el disco de la Mac
# (paquete.sh lo lee). Los binarios llevan compilado el ~/.local de este
# usuario, igual que con paquete.sh.
#
# Trabaja en ~/.cache/mint-macos/armar (ARMAR_TRABAJO=<carpeta> la cambia; se
# borra al empezar) y la borra al terminar, salvo con ARMAR_GUARDAR=1.
# ARMAR_COMMIT=<commit> arma ese commit en vez del HEAD: dos armados para
# comparar no cambian aunque se commitee en el medio (17-10-2026).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
SIN_PAQUETE=false
DEST=""
for a in "$@"; do
  case "$a" in
    --sin-paquete) SIN_PAQUETE=true ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    -*) echo "opción desconocida: $a" >&2; exit 2 ;;
    *) DEST="$a" ;;
  esac
done
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/mint-macos"
DEST="${DEST:-$CACHE/armado/$(date +%Y%m%d-%H%M%S)}"
PREFIJO="$HOME/.local"
ARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo x86_64-linux-gnu)"

paso() { printf '\n▸ %s\n' "$*"; }
aviso() { echo "  ⚠ $*"; }
# corre un paso con su salida a un log; si falla, enseña el final del log.
callado() {
  local log="$T/ultimo.log"
  "$@" > "$log" 2>&1 || { echo "  ✗ falló: $*"; tail -30 "$log" | sed 's/^/    /'; exit 1; }
}

for c in git meson ninja valac cargo Xephyr dbus-run-session; do
  command -v "$c" >/dev/null || { echo "  ✗ falta $c (requisitos.sh)"; exit 1; }
done
# Siempre la misma carpeta de trabajo: los builds de meson dejan su ruta dentro
# de los binarios, y con una carpeta al azar dos corridas no darían lo mismo.
# Por eso una sola corrida a la vez.
mkdir -p "$CACHE"
exec 9> "$CACHE/armar.lock"
flock -n 9 || { echo "  ✗ ya hay un armar.sh corriendo"; exit 1; }
T="${ARMAR_TRABAJO:-$CACHE/armar}"
rm -rf "${T:?}"
mkdir -p "$T"
[ "${ARMAR_GUARDAR:-0}" = 1 ] || trap 'rm -rf "${T:?}"' EXIT

paso "mint-macos en su HEAD"
HEAD="$(git -C "$REPO" rev-parse --verify "${ARMAR_COMMIT:-HEAD}^{commit}")"
git clone -q --no-hardlinks "$REPO" "$T/mint-macos"
git -C "$T/mint-macos" checkout -q --detach "$HEAD"
M="$T/mint-macos"
echo "  ${HEAD:0:9} $(git -C "$M" log -1 --format=%s)"
SUCIOS="$(git -C "$REPO" status --porcelain --untracked-files=no | wc -l)"
[ "$SUCIOS" = 0 ] || aviso "$SUCIOS archivos con cambios sin commitear en $REPO: no van"
source "$M/versiones.sh"

# traer <F>: deja $T/src/<_LOCAL> en el hash del manifiesto; imprime la carpeta.
traer() {
  local F="$1" n
  n="${F}_NOMBRE"; local nombre="${!n}"
  n="${F}_REPO"; local repo="${!n}"
  n="${F}_HASH"; local hash="${!n}"
  n="${F}_LOCAL"; local loc="${!n}"
  local dir="$T/src/$loc" local_d=""
  for d in "$(dirname "$REPO")/$loc" "$CACHE/src/$loc"; do
    [ -d "$d/.git" ] && { local_d="$d"; break; }
  done
  if [ -z "$hash" ]; then
    [ -n "$local_d" ] || { echo "  ✗ $nombre: sin hash en versiones.sh y sin repo local" >&2; exit 1; }
    aviso "$nombre: sin hash en versiones.sh, va el HEAD de $local_d ($(git -C "$local_d" rev-parse --short HEAD))" >&2
    git clone -q --no-hardlinks "$local_d" "$dir"
  else
    if [ -n "$repo" ] && git clone -q --filter=blob:none --no-checkout "$repo" "$dir" 2>/dev/null \
        && { git -C "$dir" cat-file -e "$hash^{commit}" 2>/dev/null || git -C "$dir" fetch -q origin "$hash" 2>/dev/null; } \
        && git -C "$dir" cat-file -e "$hash^{commit}" 2>/dev/null; then
      :
    else
      rm -rf "${dir:?}"
      [ -n "$local_d" ] && git -C "$local_d" cat-file -e "$hash^{commit}" 2>/dev/null \
        || { echo "  ✗ $nombre: ${hash:0:9} no está ni en ${repo:-(sin repo)} ni en un repo local" >&2; exit 1; }
      aviso "$nombre: ${hash:0:9} no está en ${repo:-su repo (no tiene)}; lo saco del repo local $local_d" >&2
      git clone -q --no-hardlinks --no-checkout "$local_d" "$dir"
    fi
    git -C "$dir" checkout -q --detach "$hash"
  fi
  echo "  $nombre en $(git -C "$dir" log -1 --format='%h %s')" >&2
  echo "$dir"
}

paso "Los forks, en los hashes de versiones.sh"
mkdir -p "$T/src"
S_FYNDER="$(traer FYNDER)"
S_PLANK="$(traer PLANK)"
S_GREETER="$(traer GREETER)"
S_SPOTLYTE="$(traer SPOTLYTE)"

RAIZ="$T/raiz"     # el «/» de montaje: los binarios quedan en $RAIZ$HOME/.local
paso "Compilar Fynder"
# Fynder lleva en el binario un número de build que sube con cada compilación,
# de un contador en ~/.local/state/fynder (src/gen-build-number.sh). Aquí va un
# contador propio que arranca en el número de parches del fork sobre Nemo (los
# de VERSIONES.md) y sube cada vez que meson corre el generador (dos: build e
# install): así el armado no mueve el de José y dos corridas dan el mismo
# número. SOURCE_DATE_EPOCH (la fecha del commit) es para la fecha de build,
# cuando el generador lo respete.
N_FYNDER="$(git -C "$S_FYNDER" rev-list --count --no-merges "$FYNDER_BASE..HEAD")"
echo "$N_FYNDER" > "$T/fynder-build-number"
export FYNDER_BUILD_COUNTER="$T/fynder-build-number"
export SOURCE_DATE_EPOCH="$(git -C "$S_FYNDER" log -1 --format=%ct HEAD)"
callado meson setup "$T/build/fynder" "$S_FYNDER" --prefix="$PREFIJO"
callado ninja -C "$T/build/fynder"
callado meson install -C "$T/build/fynder" --destdir "$RAIZ"
echo "  $(du -h "$T/build/fynder/src/fynder" | cut -f1) src/fynder, build $(cat "$T/fynder-build-number")"
unset SOURCE_DATE_EPOCH

paso "Compilar mint-macos-dock"
# Sin el rpath el binario carga la libplank del sistema y no la del fork.
LDFLAGS="-Wl,-rpath,$PREFIJO/lib/$ARCH" \
  callado meson setup "$T/build/plank" "$S_PLANK" --prefix="$PREFIJO" -Denable-apport=false
callado ninja -C "$T/build/plank"
callado meson install -C "$T/build/plank" --destdir "$RAIZ"
echo "  listo"

paso "Compilar slick-greeter-mac (prueba: el paquete lleva la fuente)"
callado meson setup "$T/build/greeter" "$S_GREETER" --prefix=/usr/local
callado ninja -C "$T/build/greeter"
echo "  listo"

paso "Pruebas: versiones.sh"
# El verificador lee los repos locales con su upstream; corre sobre el
# manifiesto commiteado, que tiene que ser el mismo del árbol.
git -C "$REPO" diff --quiet "$HEAD" -- versiones.sh VERSIONES.md verificar-versiones.sh \
  || { echo "  ✗ versiones.sh, VERSIONES.md o verificar-versiones.sh no son los de ${HEAD:0:9}"; exit 1; }
callado "$REPO/verificar-versiones.sh"
echo "  cuadra"

paso "Pruebas: rust (cargo test)"
( cd "$M/rust" && CARGO_TARGET_DIR="$T/build/rust" callado cargo test --locked --quiet )
echo "  $(grep -Eo '[0-9]+ passed' "$T/ultimo.log" | awk '{s += $1} END {print s + 0}') pruebas pasan"
# Los binarios también, para las pruebas de tareas reales (las AppImages). Después
# de contar: callado deja su salida en el mismo ultimo.log.
( cd "$M/rust" && CARGO_TARGET_DIR="$T/build/rust" callado cargo build --locked --quiet )

# nativo/ (Vala) del mismo commit, en la raíz: sin esto los casos usaban lo que
# hubiera en ~/.local/bin (18-10-2026: 42 y 45 fallaban con el About viejo).
paso "Compilando nativo/ (Vala)"
callado meson setup "$T/build/nativo" "$M/nativo" --buildtype=release --prefix=/usr
callado ninja -C "$T/build/nativo"
install -d "$RAIZ$PREFIJO/bin"
find "$T/build/nativo" -mindepth 2 -maxdepth 2 -type f -executable -name 'mac-*' -exec install -m 755 {} "$RAIZ$PREFIJO/bin/" \;
install -m 755 "$M"/nativo/mac-*-lanzar "$RAIZ$PREFIJO/bin/"
echo "  $(ls "$RAIZ$PREFIJO/bin" | grep -c '^mac-') programas de nativo/"

# meson test de Fynder y del Dock en un X, bus y XDG propios: nada de lo de
# José (pantalla :0, dconf, ~/.config) entra en las pruebas. GIO_USE_VFS=local:
# sin gvfs, que montaba su FUSE en el XDG_RUNTIME_DIR de la prueba y lo dejaba
# colgado (17-10-2026).
paso "Pruebas: Fynder y el Dock (meson test, en un X que no se ve)"
PX="$T/px"; mkdir -p "$PX"/{config,data,cache,runtime}; chmod 700 "$PX/runtime"
PANT=":$(( 90 + RANDOM % 9 ))"
while [ -e "/tmp/.X11-unix/X${PANT#:}" ]; do PANT=":$(( ${PANT#:} + 1 ))"; done
# Xvfb, que no se ve (regla de José, 18-10-2026: nada en el LEN); sin Xvfb, Xephyr
# en +0+0, dentro del Dell.
if [ -x /usr/bin/Xvfb ]; then
  Xvfb "$PANT" -screen 0 1280x800x24 -nolisten tcp > "$PX/xephyr.log" 2>&1 &
else
  Xephyr "$PANT" -screen 1280x800+0+0 -nolisten tcp > "$PX/xephyr.log" 2>&1 &
fi
XPID=$!
trap 'kill $XPID 2>/dev/null || true; fusermount -uz "$PX/runtime/gvfs" 2>/dev/null || true
      [ "${ARMAR_GUARDAR:-0}" = 1 ] || rm -rf "${T:?}"' EXIT
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${PANT#:}" ] && break; sleep 0.1; done
[ -e "/tmp/.X11-unix/X${PANT#:}" ] || { echo "  ✗ Xephyr no arrancó"; tail "$PX/xephyr.log"; exit 1; }
# Los esquemas de GSettings de lo compilado (sin instalar no hay ninguno) y los
# del sistema, compilados aparte.
mkdir -p "$PX/esquemas"
# (los del fork pisan a los del sistema: el Dock también trae net.launchpad.plank)
cp /usr/share/glib-2.0/schemas/*.xml "$PX/esquemas/"
cp -f "$RAIZ$PREFIJO"/share/glib-2.0/schemas/*.xml "$PX/esquemas/"
glib-compile-schemas "$PX/esquemas"
aparte() {
  env -u DBUS_SESSION_BUS_ADDRESS DISPLAY="$PANT" HOME="$PX" XDG_CONFIG_HOME="$PX/config" \
    XDG_DATA_HOME="$PX/data" XDG_CACHE_HOME="$PX/cache" XDG_RUNTIME_DIR="$PX/runtime" \
    GSETTINGS_BACKEND=memory GSETTINGS_SCHEMA_DIR="$PX/esquemas" GIO_USE_VFS=local \
    dbus-run-session -- "$@"
}
# Tres pruebas de Nemo (upstream, sin tocar en el fork) no terminan solas, por
# cómo están escritas: «Copy test» pide archivos por argumento y sin ellos sale
# con 1; «Search Engine test» tiene el gtk_main_quit comentado, y «Directory
# Async test» nunca conecta su quit_cb (recarga cada 5 s para siempre). Se
# corren todas las demás, también las que el fork agregue.
SIN_FIN_FYNDER=("Copy test" "Search Engine test" "Directory Async test")
for b in fynder plank; do
  PRUEBAS=()
  while IFS= read -r p; do
    p="${p#*:}"; p="${p# }"     # «proyecto / nombre» o «nombre», según meson
    p="${p##* / }"
    if [ "$b" = fynder ] && printf '%s\n' "${SIN_FIN_FYNDER[@]}" | grep -qxF "$p"; then continue; fi
    PRUEBAS+=("$p")
  done < <(meson test -C "$T/build/$b" --list 2>/dev/null)
  callado aparte meson test -C "$T/build/$b" --print-errorlogs "${PRUEBAS[@]}"
  echo "  $b: $(grep -E '^Ok:' "$T/ultimo.log" | awk '{print $2}') pasan de ${#PRUEBAS[@]} ($(printf '%s, ' "${PRUEBAS[@]}" | sed 's/, $//'))"
done
echo "  sin correr (no terminan solas, ver arriba): $(printf '%s, ' "${SIN_FIN_FYNDER[@]}" | sed 's/, $//')"
kill $XPID 2>/dev/null || true

# Las tareas reales (pruebas/), con lo recién compilado: los programas de
# $RAIZ$PREFIJO/bin antes que los instalados.
paso "Pruebas: tareas reales (pruebas/correr.sh, en Xvfb)"
PRUEBAS_RUST="$T/build/rust/debug" "$M/pruebas/correr.sh" --prefijo "$RAIZ$PREFIJO" --resultados "$T/pruebas" \
  || { echo "  ✗ fallan pruebas de tareas reales (registros en $T/pruebas; ARMAR_GUARDAR=1 los deja)"; exit 1; }

$SIN_PAQUETE && { paso "Listo (sin paquete)"; exit 0; }

paso "El paquete (paquete.sh, sobre lo compilado aquí)"
BUILD_FYNDER="$T/build/fynder" BUILD_DOCK="$T/build/plank" BINARIOS_DESDE="$RAIZ$HOME" \
  GREETER_FUENTE="$S_GREETER" SPOTLYTE_FUENTE="$S_SPOTLYTE" \
  "$M/paquete.sh" "$DEST"

cat >> "$DEST/origen.txt" <<EOF
armado=armar.sh
$(for F in "${FORKS[@]}"; do n="${F}_NOMBRE"; h="${F}_HASH"; echo "fork.${!n}=${!h:-HEAD}"; done)
EOF

paso "SUMAS.sha256"
(
  cd "$DEST"
  for f in $(find . -maxdepth 1 -type f ! -name SUMAS.sha256 -printf '%P\n' | LC_ALL=C sort); do
    sha256sum "$f"
    case "$f" in
      *.tar.gz)
        # cada archivo de adentro: el .tar.gz puede cambiar (fecha del gzip,
        # orden) sin que cambie lo que lleva
        python3 - "$f" <<'PY'
import hashlib, sys, tarfile
with tarfile.open(sys.argv[1]) as t:
    for m in sorted(t.getmembers(), key=lambda m: m.name):
        if m.isfile():
            print(hashlib.sha256(t.extractfile(m).read()).hexdigest() + "  " + sys.argv[1] + ":" + m.name)
        elif m.issym():
            print("enlace -> " + m.linkname + "  " + sys.argv[1] + ":" + m.name)
PY
        ;;
    esac
  done
) > "$T/SUMAS.sha256"
mv "$T/SUMAS.sha256" "$DEST/SUMAS.sha256"
echo "  $(wc -l < "$DEST/SUMAS.sha256") sumas"

paso "Listo: $DEST ($(du -sh "$DEST" | cut -f1))"
