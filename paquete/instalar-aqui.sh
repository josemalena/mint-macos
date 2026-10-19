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
#
# Necesita internet para los paquetes de apt, para compilar keyd y fsapfs
# (requisitos.sh). Todo lo demás viene en el paquete, también el fork de la
# pantalla de inicio (greeter.tar.gz).
#
# Pasos:
#   1. revisa que el usuario y la versión de Mint sean los del paquete
#   2. pide la clave y sudo requisitos.sh
#   3. Fynder y el Dock a ~/.local (ya compilados)
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
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$HOME/mint-macos"
MAC="$HOME/.cache/mint-macos/mac-sistema"

paso() { printf '\n■ %s\n' "$*"; printf '@@paso %s\n' "$*"; }
leer() { sed -n "s/^$1=//p" "$AQUI/origen.txt"; }

p_verificar() {
paso "1. ¿Es la misma clase de computadora?"
[ "$(id -u)" != 0 ] || { echo "  ✗ córrelo como tu usuario, sin sudo"; exit 1; }
if [ "$HOME" != "$(leer home)" ]; then
  echo "  ✗ el paquete se armó para $(leer home) y aquí es $HOME."
  echo "    Fynder y el Dock llevan esa ruta compilada: entra con el usuario $(leer usuario)."
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
# Los ayudantes de root en Rust, ya compilados (los instala settings/instalar-root.sh, en el paso 6).
[ -f "$AQUI/rust-binarios.tar.gz" ] && tar -xzf "$AQUI/rust-binarios.tar.gz" -C "$REPO"
}

p_binarios() {
paso "3. Fynder y el Dock"
tar -xzf "$AQUI/binarios.tar.gz" -C "$HOME"
glib-compile-schemas "$HOME/.local/share/glib-2.0/schemas"
# Los ajustes de Fynder de la otra computadora (etiquetas, menú global…).
[ -f "$AQUI/fynder-ajustes.dconf" ] && dconf load /io/github/josemalena/fynder/ < "$AQUI/fynder-ajustes.dconf"
echo "  $(tar -tzf "$AQUI/binarios.tar.gz" | wc -l) archivos en ~/.local"
# Los diálogos de sesión en Vala (el lanzador cae a applemenu.py si faltan).
[ -f "$AQUI/nativo-binarios.tar.gz" ] && tar -xzf "$AQUI/nativo-binarios.tar.gz" -C "$HOME"
# Open/Save de todo el sistema con el selector de Fynder (portal y módulo de GTK; toma efecto al
# volver a entrar). Vuelta atrás: sh fynder-selector.sh --quitar. Y las hojas pegadas a su ventana,
# como en la Mac (vuelta atrás: gsettings set org.cinnamon.muffin attach-modal-dialogs false).
MOD="$(ls "$HOME"/.local/lib/*/gtk-3.0/modules/libfynder-chooser-module.so 2>/dev/null | head -1)"
if [ -f "$AQUI/fynder-selector.sh" ] && [ -n "$MOD" ]; then
  MODULO_COMPILADO="$MOD" sh "$AQUI/fynder-selector.sh" && echo "  selector de Open/Save: Fynder"
fi
gsettings set org.cinnamon.muffin attach-modal-dialogs true 2>/dev/null || true
}

p_apple() {
paso "4. Lo de Apple"
rm -rf "${MAC:?}"; mkdir -p "$MAC"
# Entero, o partido en trozos (.parte-00, -01…) cuando pasa de 4 GB (FAT32).
if [ -f "$AQUI/mac-sistema.tar" ]; then tar -xf "$AQUI/mac-sistema.tar" -C "$MAC"
else cat "$AQUI"/mac-sistema.tar.parte-* | tar -xf - -C "$MAC"; fi
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
# La configuración solo si no hay una (la del usuario no se toca).
if [ -f "$AQUI/spotlyte-config.tar.gz" ] && [ ! -e "$HOME/.config/ulauncher/settings.json" ]; then
  tar -xzf "$AQUI/spotlyte-config.tar.gz" -C "$HOME"
fi
echo "  en $SPOT/app; arranca al entrar (⌘Espacio)"
}

p_mint_macos() {
paso "5. mint-macos"
export MAC_SISTEMA="$MAC"
"$REPO/instalar.sh" --sin-compilar
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

# En la terminal: todo seguido, con una sola clave de sudo.
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
