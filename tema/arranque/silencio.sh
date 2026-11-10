#!/usr/bin/env bash
# El arranque y el apagado sin texto, como la Mac (José, 10-11-2026):
#   - GRUB escondido y en 0 segundos: Shift o Esc al encender enseñan el menú;
#   - el kernel y systemd callados (quiet splash loglevel=3 …): en pantalla solo sale
#     un error de verdad;
#   - el driver de video dentro del initramfs, para que la manzana salga desde el
#     primer segundo y no después de unas líneas de texto;
#   - al apagar o reiniciar, el fondo de pantalla del usuario (catalina.script y
#     mac-fondo-apagado).
# Durante la manzana, Esc enseña los mensajes y Esc otra vez los esconde (lo hace
# Plymouth). Todo queda guardado: journalctl -b (este arranque) y journalctl -b -1
# (el anterior, con su apagado). ⌘V como en la Mac queda para el fork de Plymouth.
#
#   sudo ./silencio.sh             lo pone (necesita el tema catalina: instalar.sh)
#   sudo ./silencio.sh --deshacer  lo quita todo y deja GRUB y el initramfs como estaban
#
# No edita /etc/default/grub: va en un archivo aparte que GRUB lee después
# (/etc/default/grub.d/90-mint-macos-silencio.cfg); quitarlo es borrar ese archivo.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
[ "$(id -u)" = 0 ] || { echo "✗ con sudo: sudo $0 ${1:-}"; exit 1; }
USUARIO="${SUDO_USER:-}"
[ -n "$USUARIO" ] && [ "$USUARIO" != root ] || { echo "✗ córrelo con sudo desde tu usuario (el fondo de apagado es el suyo)"; exit 1; }
HOME_USUARIO="$(getent passwd "$USUARIO" | cut -d: -f6)"

GRUB_D=/etc/default/grub.d/90-mint-macos-silencio.cfg
MODULOS=/etc/initramfs-tools/modules
INICIO="# mint-macos silencio.sh: el driver de video, para la manzana desde el principio"
FIN="# mint-macos silencio.sh (fin)"
APAGADO=/var/lib/mint-macos/apagado
TEMA=/usr/share/plymouth/themes/catalina
BIN="$HOME_USUARIO/.local/bin/mac-fondo-apagado"
AUTO="$HOME_USUARIO/.config/autostart/mint-macos-fondo-apagado.desktop"

paso() { printf '\n▸ %s\n' "$*"; }
como_usuario() { sudo -u "$USUARIO" HOME="$HOME_USUARIO" "$@"; }
parar_vigilante() {   # solo el de este guion: por la ruta exacta del binario, nunca por nombre suelto
  local p
  for p in $(pgrep -u "$USUARIO" -x -f "bash $BIN --vigilar" || true); do
    kill "$p" 2>/dev/null || true
  done
}

if [ "${1:-}" = --deshacer ]; then
  paso "GRUB como estaba"
  rm -f "$GRUB_D"; update-grub
  paso "initramfs como estaba"
  [ -f "$MODULOS" ] && sed -i "/^$INICIO\$/,/^$FIN\$/d" "$MODULOS"
  update-initramfs -u
  paso "Sin el fondo al apagar"
  parar_vigilante
  rm -f "$TEMA/fondo-apagado.png" "$BIN" "$AUTO"
  rm -rf "$APAGADO"
  echo; echo "Listo: arranca y apaga como antes de silencio.sh (el tema catalina sigue)."
  exit 0
fi
[ -z "${1:-}" ] || { echo "uso: sudo $0 [--deshacer]" >&2; exit 2; }

paso "El tema de arranque catalina"
if [ ! -f "$TEMA/catalina.plymouth" ]; then
  echo "  no está: primero lo instala instalar.sh"
  "$AQUI/instalar.sh"
fi
# El script del tema trae lo del apagado: se copia siempre, por si es de antes.
install -m 644 "$AQUI/catalina.script" "$TEMA/catalina.script"

paso "GRUB escondido y el arranque callado"
mkdir -p "$(dirname "$GRUB_D")"
cat > "$GRUB_D" <<'EOF'
# mint-macos (tema/arranque/silencio.sh): el arranque sin texto, como la Mac.
# Shift o Esc al encender enseñan el menú. Para quitarlo: sudo silencio.sh --deshacer
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
for _p in quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0; do
  case " $GRUB_CMDLINE_LINUX_DEFAULT " in
    *" $_p "*) ;;
    *) GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT $_p" ;;
  esac
done
unset _p
EOF
echo "  $GRUB_D"
update-grub

paso "El driver de video en el initramfs"
DRIVERS="$(for d in /sys/class/drm/card[0-9]*/device/driver; do
             [ -e "$d" ] && basename "$(readlink -f "$d")"
           done 2>/dev/null | sort -u | grep -E '^(nouveau|i915|amdgpu|radeon)$' || true)"
[ -f "$MODULOS" ] && sed -i "/^$INICIO\$/,/^$FIN\$/d" "$MODULOS"
if [ -n "$DRIVERS" ]; then
  { echo "$INICIO"; echo "$DRIVERS"; echo "$FIN"; } >> "$MODULOS"
  echo "  $(echo $DRIVERS) (en $MODULOS)"
else
  echo "  no se reconoció el driver de video: se queda como estaba"
fi

paso "Al apagar, el fondo de pantalla de $USUARIO"
install -d -o "$USUARIO" -g "$USUARIO" -m 755 "$APAGADO"
install -D -o "$USUARIO" -g "$USUARIO" -m 755 "$AQUI/fondo-apagado.sh" "$BIN"
install -d -o "$USUARIO" -g "$USUARIO" "$(dirname "$AUTO")"
cat > "$AUTO" <<EOF
[Desktop Entry]
Type=Application
Name=Fondo para el apagado (mint-macos)
Comment=Deja el fondo de pantalla listo para la pantalla de apagado
Exec=$BIN --vigilar
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
chown "$USUARIO": "$AUTO"
como_usuario "$BIN" || echo "  ⚠ no se pudo preparar ahora: se prepara al entrar a la sesión"
ln -sfn "$APAGADO/fondo.png" "$TEMA/fondo-apagado.png"

paso "initramfs (el arranque lo lee de ahí)"
update-initramfs -u

echo
echo "Listo: se ve desde el próximo arranque y en el próximo apagado."
echo "  Esc durante la manzana: los mensajes.   Shift o Esc al encender: el menú de GRUB."
echo "  journalctl -b: este arranque.   journalctl -b -1: el anterior, con su apagado."
echo "  Para quitarlo: sudo $0 --deshacer"
