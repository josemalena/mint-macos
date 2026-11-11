#!/usr/bin/env bash
# Instala mint-macos desde un paquete de paquete.sh, en una computadora con
# Linux Mint que no tiene el disco de la Mac. Se corre desde la carpeta del
# paquete, como el usuario que va a usarlo (no con sudo). La clave se pide UNA
# vez, al principio, y se mantiene viva hasta el final: lo que necesita sudo
# (requisitos, el arranque y la pantalla de inicio) entra en la misma corrida.
#
#   ./instalar-aqui.sh
#   MINT_MACOS_TECLADO="us,es" ./instalar-aqui.sh   escoge las distribuciones de
#                                    teclado (sin esto se queda la de la instalación de Mint)
#   MINT_MACOS_ETIQUETAS=propias ./instalar-aqui.sh  las etiquetas de Fynder de quien armó
#                                    el paquete aunque instale otro usuario (ver p_binarios)
#
# Sirve cualquier usuario y nada se compila aquí (José, 10-11-2026): Fynder, Muelle, keyd,
# libfsapfs y la pantalla de inicio vienen ya compilados (compilado.tar.gz y greeter.tar.gz,
# de paquete/compilar-sistema.sh) y van a /usr/local. Internet hace falta solo para los
# paquetes de apt de ejecución (requisitos.sh).
#
# Pasos:
#   1. revisa la versión de Mint (avisa si no es la del paquete)
#   2. pide la clave y sudo requisitos.sh (también copia lo ya compilado a /usr/local)
#   3. los ajustes de Fynder y el Dock (como el usuario: dconf y gsettings nunca como root)
#   4. lo de Apple a ~/.cache/mint-macos/mac-sistema, que hace de disco de la Mac
#   5. instalar.sh --sin-compilar, Settings.app, Launchpad, el ayudante
#      (Force Quit y ⇧⌘5) y las apps web de Apple
#   6. con la misma clave: los ayudantes de root de System Preferences
#      (settings/instalar-root.sh: Modifier Keys, Sharing, Startup Disk; los de
#      Rust que trae rust-binarios.tar.gz), el arranque (Plymouth) y la pantalla de inicio de
#      Catalina, y bloquear con ella; y si hay discos APFS en fstab, el
#      vigilante que rehace su montaje cuando el FUSE muere (apfs/vigilar.sh)
#   7. dice lo que queda: iCloud Drive y cerrar sesión
#
# El asistente gráfico corre los mismos pasos uno por uno, sin sudo, y los de
# root se los pide a asistente-root.sh (una sola clave, por pkexec):
#   ./instalar-aqui.sh --lista          los pasos, en orden, con «root» los de root
#   ./instalar-aqui.sh --paso <nombre>  uno solo de los pasos de usuario
#
# En la terminal deja todo lo que dice en ~/.cache/mint-macos/instalar-aqui-<fecha>.log.
# Si algo falla, dice en qué paso, en qué línea y con qué comando, en vez de
# cerrarse callado (09-11-2026: en la MacBook5,1 se cerró sin decir nada a mitad
# del paso 3, y no había forma de saber dónde).
set -eEuo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$HOME/mint-macos"
MAC="$HOME/.cache/mint-macos/mac-sistema"
PASO_ACTUAL="el arranque"
T0=$SECONDS
EN_TERMINAL=0; [ -t 1 ] && EN_TERMINAL=1
LOG=""

transcurrido() { printf '%d:%02d' $(((SECONDS - T0) / 60)) $(((SECONDS - T0) % 60)); }
paso() { PASO_ACTUAL="$*"; printf '\n■ %s  (%s)\n' "$*" "$(transcurrido)"; printf '@@paso %s\n' "$*"; }
leer() { sed -n "s/^$1=//p" "$AQUI/origen.txt"; }

# El comando que falló, dónde y cómo seguir. Con -E la trampa vale también dentro
# de las funciones y de los $(…); solo se avisa una vez.
fallo() {
  local rc=$? linea=$1 cmd=$2
  [ -z "${YA_AVISO:-}" ] || return 0
  YA_AVISO=1
  printf '\n✗ Se paró en «%s» (línea %s, salió con %s):\n    %s\n' "$PASO_ACTUAL" "$linea" "$rc" "$cmd" >&2
  [ -z "$LOG" ] || printf '  Todo lo que dijo está en %s\n' "$LOG" >&2
  printf '  Arregla lo que diga arriba y vuelve a correr ./instalar-aqui.sh: lo que ya está hecho se salta.\n' >&2
}
trap 'fallo "$LINENO" "$BASH_COMMAND"' ERR

p_verificar() {
paso "1. ¿Es la misma clase de computadora?"
[ "$(id -u)" != 0 ] || { echo "  ✗ córrelo como tu usuario, sin sudo"; exit 1; }
# Cualquier usuario sirve: lo compilado va a /usr/local, sin rutas del home de nadie (10-11-2026).
# Un paquete de antes (con binarios.tar.gz en el ~/.local de quien lo armó) sí exige el mismo home.
if [ ! -f "$AQUI/compilado.tar.gz" ] && [ -f "$AQUI/binarios.tar.gz" ] && [ "$HOME" != "$(leer home)" ]; then
  echo "  ✗ este paquete es de antes del 10-11-2026: se armó para $(leer home) y aquí es $HOME."
  echo "    Fynder y el Dock llevan esa ruta compilada: entra con el usuario $(leer usuario), o arma uno nuevo."
  exit 1
fi
MINT_AQUI="$(. /etc/os-release && echo "$VERSION_ID")"
if [ "$MINT_AQUI" != "$(leer mint)" ]; then
  echo "  ojo: el paquete es de Mint $(leer mint) y esto es Mint $MINT_AQUI."
  echo "  Si Fynder o el Dock no arrancan, hay que compilarlos aquí (./instalar.sh sin --sin-compilar)."
fi
echo "  usuario $USER, Mint $MINT_AQUI, mint-macos $(leer repo | cut -c1-7)"
}

p_repo() {
paso "El repo en $REPO"
if [ -e "$REPO" ]; then
  mv "$REPO" "$REPO.antes-$(date +%Y%m%d-%H%M%S)"
  echo "  el que había quedó al lado, con fecha"
fi
tar -xzf "$AQUI/mint-macos.tar.gz" -C "$HOME"
# Fynder, Muelle, keyd y libfsapfs ya compilados (paquete/compilar-sistema.sh), en $REPO/compilado:
# requisitos.sh, que corre como root, los copia de ahí a /usr/local.
if [ -f "$AQUI/compilado.tar.gz" ]; then tar -xzf "$AQUI/compilado.tar.gz" -C "$REPO"; fi
# Los ayudantes de root en Rust, ya compilados (los instala settings/instalar-root.sh, en el paso 6).
# Con if y no con &&: como última línea, un && sin el archivo hace que la función devuelva 1.
if [ -f "$AQUI/rust-binarios.tar.gz" ]; then tar -xzf "$AQUI/rust-binarios.tar.gz" -C "$REPO"; fi
}

# Las etiquetas de Fynder de fábrica de macOS, con los colores que usa Fynder para cada una
# (formato de finder-tags: nombre, color, visible).
ETIQUETAS_FABRICA="[('Red', 6, true), ('Orange', 7, true), ('Yellow', 5, true), ('Green', 2, true), ('Blue', 4, true), ('Purple', 3, true), ('Gray', 1, true), ('Work', 0, true), ('Home', 0, true), ('Important', 0, true)]"

p_binarios() {
paso "3. Fynder y el Dock"
# Todo lo de este paso corre como el usuario: dconf y gsettings como root irían al dconf de root.
if [ -f "$AQUI/compilado.tar.gz" ]; then
  # Ya están en /usr/local (los copió requisitos.sh en el paso 2).
  for b in fynder muelle; do command -v "$b" >/dev/null || { echo "  ✗ no está $b: corre antes el paso de root «requisitos»"; exit 1; }; done
  echo "  en /usr/local: $(command -v fynder), $(command -v muelle)"
else
  # Un paquete de antes: Fynder y el Dock compilados con el ~/.local de quien lo armó.
  tar -xzf "$AQUI/binarios.tar.gz" -C "$HOME"
  glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas"
  echo "  $(tar -tzf "$AQUI/binarios.tar.gz" | wc -l) archivos en ~/.local"
fi
# Los ajustes de Fynder de quien armó el paquete (la barra de ruta, el menú global, la barra
# de herramientas…), para todos.
[ -f "$AQUI/fynder-ajustes.dconf" ] && dconf load /io/github/josemalena/fynder/ < "$AQUI/fynder-ajustes.dconf"
# Las etiquetas (José, 10-11-2026): las suyas si instala jmalena o con MINT_MACOS_ETIQUETAS=propias;
# a cualquier otro usuario, las de fábrica de macOS, y solo si no tiene unas propias ya.
if [ -f "$AQUI/fynder-etiquetas-propias.dconf" ] && { [ "$USER" = jmalena ] || [ "${MINT_MACOS_ETIQUETAS:-}" = propias ]; }; then
  dconf load /io/github/josemalena/fynder/ < "$AQUI/fynder-etiquetas-propias.dconf"
  echo "  etiquetas: las del paquete"
elif [ -z "$(dconf read /io/github/josemalena/fynder/preferences/finder-tags)" ]; then
  dconf write /io/github/josemalena/fynder/preferences/finder-tags "$ETIQUETAS_FABRICA"
  echo "  etiquetas: las de fábrica de macOS"
else
  echo "  etiquetas: las que ya tenías"
fi
# Los diálogos de sesión en Vala (el lanzador cae a applemenu.py si faltan).
[ -f "$AQUI/nativo-binarios.tar.gz" ] && tar -xzf "$AQUI/nativo-binarios.tar.gz" -C "$HOME"
# Open/Save de todo el sistema con el selector de Fynder (portal y módulo de GTK; toma efecto al
# volver a entrar). Vuelta atrás: sh fynder-selector.sh --quitar. Y las hojas pegadas a su ventana,
# como en la Mac (vuelta atrás: gsettings set org.cinnamon.muffin attach-modal-dialogs false).
# El módulo: el de /usr/local (compilado.tar.gz) o el del ~/.local de un paquete de antes. Sin
# módulo (no siempre viene), el ls falla: con pipefail, eso cerraba el guion.
MOD="$(ls /usr/local/lib/*/gtk-3.0/modules/libfynder-chooser-module.so /usr/local/lib/fynder/libfynder-chooser-module.so \
          "$HOME"/.local/lib/*/gtk-3.0/modules/libfynder-chooser-module.so 2>/dev/null | head -1 || true)"
if [ -f "$AQUI/fynder-selector.sh" ] && [ -n "$MOD" ]; then
  MODULO_COMPILADO="$MOD" sh "$AQUI/fynder-selector.sh" && echo "  selector de Open/Save: Fynder"
else
  echo "  selector de Open/Save: el de GTK (el paquete no trae el módulo de Fynder)"
fi
gsettings set org.cinnamon.muffin attach-modal-dialogs true 2>/dev/null || true
}

p_apple() {
paso "4. Lo de Apple"
# Si una corrida anterior ya lo descomprimió entero (la marca .completo se pone
# al final), no se repiten los 4 GB: volver a correr el instalador después de un
# tropiezo no cuesta otra vez esos minutos. REHACER_APPLE=1 lo fuerza.
if [ -f "$MAC/.completo" ] && [ -z "${REHACER_APPLE:-}" ]; then
  echo "  ya está, de una corrida anterior (REHACER_APPLE=1 ./instalar-aqui.sh lo repite)"
else
rm -rf "${MAC:?}"; mkdir -p "$MAC"
# Entero, o partido en trozos (.parte-00, -01…) cuando pasa de 4 GB (FAT32).
# Son unos 4 GB y tardan: en la terminal se ve cuánto lleva. El avance va directo
# a la terminal (/dev/tty), así que no ensucia el registro.
TOTAL="$(du -cb "$AQUI"/mac-sistema.tar* | tail -1 | cut -f1)"
echo "  $(numfmt --to=iec "$TOTAL") para descomprimir; tarda unos minutos"
AV=""
if [ "$EN_TERMINAL" = 1 ]; then
  # Cada 2 s, lo escrito contra el total. Sin la trampa ni -e: un sleep cortado al
  # final no es un fallo de la instalación.
  ( trap - ERR; set +e
    while sleep 2; do
      n="$(du -sb "$MAC" 2>/dev/null | cut -f1)"; p=$((n * 100 / TOTAL)); [ "$p" -le 99 ] || p=99
      printf '\r  %3d %%  (%s de %s)' "$p" "$(numfmt --to=iec "$n")" "$(numfmt --to=iec "$TOTAL")" > /dev/tty
    done ) &
  AV=$!
fi
if [ -f "$AQUI/mac-sistema.tar" ]; then tar -xf "$AQUI/mac-sistema.tar" -C "$MAC"
else cat "$AQUI"/mac-sistema.tar.parte-* | tar -xf - -C "$MAC"; fi
if [ -n "$AV" ]; then kill "$AV" 2>/dev/null || true; wait "$AV" 2>/dev/null || true; printf '\r  100 %%%*s\n' 30 '' > /dev/tty; fi
touch "$MAC/.completo"
fi
[ -f "$AQUI/apple-extra.tar.gz" ] && tar -xzf "$AQUI/apple-extra.tar.gz" -C "$HOME"
# La base de los cursores, antes del tema (la flecha, la I y la espera).
if [ -f "$AQUI/cursores-base.tar.gz" ]; then
  mkdir -p "$HOME/.local/share/icons"
  tar -xzf "$AQUI/cursores-base.tar.gz" -C "$HOME/.local/share/icons"
fi
echo "  en $MAC (hace de disco de la Mac para los guiones)"
}

# Spotlyte, el Spotlight: va antes de mint-macos para que install.sh encuentre
# su configuración (⌘Espacio deja de abrir el Run de Cinnamon).
p_spotlyte() {
paso "Spotlyte (el Spotlight)"
[ -f "$AQUI/spotlyte.tar.gz" ] || { echo "  el paquete no trae Spotlyte"; return 0; }
SPOT="$HOME/.local/share/spotlyte"
[ -e "$SPOT/app" ] && mv "$SPOT/app" "$SPOT/app.antes-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SPOT" "$HOME/.local/bin" "$HOME/.config/autostart"
tar -xzf "$AQUI/spotlyte.tar.gz" -C "$SPOT"
cat > "$HOME/.local/bin/spotlyte" <<'EOF'
#!/bin/sh
# Spotlyte: fork de ULauncher con el diseño del Spotlight de Catalina (instalado en ~/.local/share/spotlyte).
exec env GDK_BACKEND=x11 python3 "$HOME/.local/share/spotlyte/app/bin/ulauncher" "$@"
EOF
chmod 755 "$HOME/.local/bin/spotlyte"
cat > "$HOME/.config/autostart/spotlyte.desktop" <<EOF
[Desktop Entry]
Name=Spotlyte
Comment=Spotlight para Linux (fork de ULauncher)
GenericName=Launcher
Exec=$HOME/.local/bin/spotlyte --hide-window
Icon=ulauncher
Terminal=false
Type=Application
X-GNOME-Autostart-enabled=true
EOF
# La configuración solo si no hay una (la del usuario no se toca). El tema trae la ruta del
# caché de quien armó el paquete: se pasa al $HOME de aquí.
if [ -f "$AQUI/spotlyte-config.tar.gz" ] && [ ! -e "$HOME/.config/ulauncher/settings.json" ]; then
  tar -xzf "$AQUI/spotlyte-config.tar.gz" -C "$HOME"
  ORIGEN_HOME="$(leer home)"
  if [ -n "$ORIGEN_HOME" ] && [ "$ORIGEN_HOME" != "$HOME" ] && [ -d "$HOME/.config/ulauncher/user-themes" ]; then
    # Con || true: sin coincidencias, grep devuelve 1 y con pipefail eso cerraría el guion.
    { grep -rlF "$ORIGEN_HOME/" "$HOME/.config/ulauncher/user-themes" 2>/dev/null || true; } | while IFS= read -r f; do
      sed -i "s#$ORIGEN_HOME/#$HOME/#g" "$f"
    done
  fi
fi
echo "  en $SPOT/app; arranca al entrar (⌘Espacio)"
}

p_mint_macos() {
paso "5. mint-macos"
export MAC_SISTEMA="$MAC"
"$REPO/instalar.sh" --sin-compilar
# Los lanzadores de los programas en Vala que vienen en nativo-binarios.tar.gz: el App
# Store y el Activity Monitor. Sin ellos, el ícono del App Store del Dock abría el
# Software Manager de Mint (MacBook5,1, 09-11-2026). El Dock se reordena al final.
if [ -x "$HOME/.local/bin/mac-tienda" ]; then "$REPO/nativo/instalar.sh" --sin-compilar; fi
"$REPO/settings/desde-mac.sh"
"$REPO/settings/instalar.sh"
"$REPO/launchpad/instalar.sh"
"$REPO/ayudante/instalar.sh"
# El agente de polkit estilo Catalina (mac-polkit si vino en nativo-binarios, o el de Python), ACTIVO: --activar
# apaga el de Cinnamon y oculta polkit-gnome en el autoarranque de este usuario (si no, compiten por la sesión).
# Surte efecto al volver a entrar. Vuelta atrás: polkit/instalar.sh --quitar.
"$REPO/polkit/instalar.sh"
"$REPO/polkit/instalar.sh" --activar
"$REPO/icloud/apps-web.sh"
# Los perfiles de versión de macOS (perfiles/ESQUEMA.md): lo que haya aquí del disco de la Mac y
# de las referencias, mint-macos-version y el autoarranque que aplica la versión escogida al entrar.
# Los que vienen en el paquete primero: aquí no están las referencias de Monterey ni de Sequoia,
# y generar.py no pisa un perfil que no puede rehacer.
if [ -f "$AQUI/perfiles.tar.gz" ]; then
  mkdir -p "$HOME/.local/share/mint-macos/macos"
  tar -xzf "$AQUI/perfiles.tar.gz" -C "$HOME/.local/share/mint-macos/macos"
fi
"$REPO/perfiles/instalar.sh"
# Los servicios de D-Bus en Rust (vienen en rust-binarios.tar.gz): la activación los arranca la
# primera vez que una ventana los llama. Sin su binario, se avisa y se sigue.
for s in tienda monitor apariencia calendario appleid avisos; do
  if [ -x "$REPO/rust/target/release/mint-macos-$s" ]; then "$REPO/$s/instalar.sh"
  else echo "  ⚠ el paquete no trae mint-macos-$s: $s queda sin instalar"; fi
done
# rclone en ~/.local/bin (versión fija, con checksum): lo usan el panel Apple ID
# de System Preferences y iCloud Drive. El alta de la cuenta la hace José.
"$REPO/icloud/icloud.sh" instalar
# El dock otra vez, ahora que existen Launchpad y System Preferences: en el
# paso del tema todavía no estaban y el dock se quedaba sin ellos.
PLANK_ORDEN_MAC=1 "$REPO/tema/plank/configurar.sh"
}

# La pantalla de inicio se compila del fork que trae el paquete, no de GitHub.
GREETER_DIR="$HOME/.cache/mint-macos/src/mint-macos-greeter-paquete"
p_greeter() {
[ -f "$AQUI/greeter.tar.gz" ] || return 0
mkdir -p "$(dirname "$GREETER_DIR")"
tar -xzf "$AQUI/greeter.tar.gz" -C "$(dirname "$GREETER_DIR")" --transform "s#^mint-macos-greeter#$(basename "$GREETER_DIR")#"
}

p_bloqueo() {
paso "Bloquear con la pantalla de inicio"
"$REPO/login/bloqueo.sh"
}

p_lo_que_queda() {
paso "Lo que queda"
echo "  - Si la pantalla de inicio no saliera: Ctrl+Alt+F2, entra y  sudo login-mac-revertir"
echo "  - iCloud Drive como carpeta:  $REPO/icloud/icloud.sh instalar, y luego «alta» y «montar»"
echo "    (pide el Apple ID y el código; lo escribes tú)."
echo "  - El agente de polkit (el diálogo de clave estilo Catalina) queda activo al volver a entrar."
echo "    Si diera problemas:  $REPO/polkit/instalar.sh --quitar   (devuelve el de Cinnamon y polkit-gnome)."
echo "  - Cierra sesión y vuelve a entrar."
echo "  - $MAC se puede borrar al terminar; solo hace falta para volver a generar el tema."
}

# Los pasos en orden. Los de root los corre asistente-root.sh en el asistente,
# y sudo aquí.
PASOS="verificar repo root:requisitos binarios apple spotlyte mint-macos root:ayudantes root:arranque greeter root:login bloqueo root:vigilante lo-que-queda"

case "${1:-}" in
  --lista) for p in $PASOS; do echo "$p" | sed 's/^root:/root /'; done; exit 0 ;;
  --paso)
    case "${2:-}" in
      verificar|repo|binarios|apple|spotlyte|mint-macos|greeter|bloqueo|lo-que-queda) "p_$(echo "$2" | tr - _)"; exit 0 ;;
      *) echo "  ✗ paso desconocido o de root: ${2:-}" >&2; exit 2 ;;
    esac ;;
  "") ;;
  *) echo "uso: $0 [--lista | --paso <nombre>]" >&2; exit 2 ;;
esac

# En la terminal: todo seguido, con una sola clave de sudo, y todo lo que dice
# también va al registro. sudo pide la clave por /dev/tty, así que no pasa por él.
LOG="$HOME/.cache/mint-macos/instalar-aqui-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1
echo "Registro de esta corrida: $LOG"
p_verificar
p_repo
paso "2. Requisitos (sudo; baja paquetes de internet)"
echo "  La clave se pide ahora y no se vuelve a pedir."
sudo -v
# Mantiene viva la clave mientras dure la instalación (sudo la olvida a los
# 15 minutos) y se acaba con este proceso.
( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
MANTENER=$!
trap 'kill $MANTENER 2>/dev/null || true' EXIT
sudo "$REPO/requisitos.sh"
p_binarios
p_apple
p_spotlyte
p_mint_macos
paso "6. Los ayudantes de root, el arranque y la pantalla de inicio (sudo, con la misma clave)"
# Sin ellos los paneles de System Preferences que cambian el sistema (Modifier
# Keys, Sharing, Startup Disk) solo miran: no hay candado ni clave.
sudo "$REPO/settings/instalar-root.sh"
sudo "$REPO/tema/arranque/instalar.sh"
p_greeter
if [ -d "$GREETER_DIR" ]; then sudo "$REPO/login/instalar.sh" --activar --fuente "$GREETER_DIR"
else sudo "$REPO/login/instalar.sh" --activar; fi
p_bloqueo
# El vigilante de los montajes APFS, solo si esta máquina los tiene en fstab
# (el paquete no monta ninguno: lo de la Mac viene en mac-sistema.tar).
if awk '$3 == "fsapfs" && $1 !~ /^#/ {f=1} END {exit !f}' "${FSTAB:-/etc/fstab}"; then
  sudo "$REPO/apfs/vigilar.sh" --instalar
else
  echo "  sin discos APFS en fstab: el vigilante de montajes no hace falta"
fi
p_lo_que_queda
printf '\n✓ Terminó sin errores en %s. El registro está en %s\n' "$(transcurrido)" "$LOG"
