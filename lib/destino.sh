# lib/destino.sh — dónde instala cada pieza de mint-macos. Lo cargan los instalar.sh:
#
#   source "$AQUI/../lib/destino.sh"
#
# MINT_MACOS_DESTINO=usuario (por omisión, lo de siempre: ~/.local, ~/.config, gsettings, systemctl --user)
# MINT_MACOS_DESTINO=sistema (la imagen: /usr/local, /etc/xdg, /etc/skel, los esquemas por defecto)
# MINT_MACOS_RAIZ=/ruta      solo con «sistema»: la raíz donde se escribe (el chroot visto desde
#                            fuera). Dentro del chroot va vacía.
#
# Cada ruta viene en dos: D_* es DÓNDE se copia (con la raíz delante) y R_* es la ruta de verdad,
# la que se escribe dentro de un .desktop, un .service o un guion (sin la raíz). En «usuario» son
# iguales. Nunca escribir una D_* dentro de un archivo: en la imagen apuntaría al chroot.
#
#   ajuste ESQUEMA CLAVE VALOR      usuario: gsettings set · sistema: una línea del .gschema.override
#   unidad_usuario enable|start|restart|stop UNIDAD…
#                                   usuario: systemctl --user · sistema: solo enable, global (--global)
#   es_sistema                      verdadero en «sistema»
#   COMO_ROOT                       «sudo» en usuario, vacío en sistema (la imagen ya corre como root)

MINT_MACOS_DESTINO="${MINT_MACOS_DESTINO:-usuario}"
case "$MINT_MACOS_DESTINO" in
  usuario)
    _datos="${XDG_DATA_HOME:-$HOME/.local/share}"; _conf="${XDG_CONFIG_HOME:-$HOME/.config}"
    R_BIN="$HOME/.local/bin"; R_LIB="$HOME/.local/lib/mint-macos"; R_DATOS="$_datos"; R_CONF="$_conf"
    R_AUTOARRANQUE="$_conf/autostart"; R_SYSTEMD_USUARIO="$_conf/systemd/user"; R_DBUS="$_datos/dbus-1/services"
    R_APPS="$_datos/applications"; R_ICONOS="$_datos/icons"; R_TEMAS="$_datos/themes"
    RAIZ=""; COMO_ROOT="sudo"
    ;;
  sistema)
    R_BIN="/usr/local/bin"; R_LIB="/usr/local/lib/mint-macos"; R_DATOS="/usr/local/share"
    # La configuración de cada usuario nuevo nace de /etc/skel (la de los que ya existen no se toca).
    R_CONF="/etc/skel/.config"
    R_AUTOARRANQUE="/etc/xdg/autostart"; R_SYSTEMD_USUARIO="/usr/local/lib/systemd/user"
    R_DBUS="/usr/local/share/dbus-1/services"; R_APPS="/usr/local/share/applications"
    R_ICONOS="/usr/share/icons"; R_TEMAS="/usr/share/themes"
    RAIZ="${MINT_MACOS_RAIZ:-}"; COMO_ROOT=""
    [ "$(id -u)" = 0 ] || [ -n "$RAIZ" ] || { echo "✗ MINT_MACOS_DESTINO=sistema sin raíz: corre como root (dentro del chroot)" >&2; exit 1; }
    ;;
  *) echo "✗ MINT_MACOS_DESTINO=$MINT_MACOS_DESTINO: usuario o sistema" >&2; exit 1 ;;
esac
for _v in BIN LIB DATOS CONF AUTOARRANQUE SYSTEMD_USUARIO DBUS APPS ICONOS TEMAS; do
  eval "D_$_v=\"\$RAIZ\$R_$_v\""
done
unset _v _datos _conf
# Los valores por defecto de los esquemas en la imagen (se compilan al final con glib-compile-schemas).
D_OVERRIDE="$RAIZ/usr/share/glib-2.0/schemas/90_mint-macos.gschema.override"

es_sistema() { [ "$MINT_MACOS_DESTINO" = sistema ]; }

ajuste() { # esquema clave valor (el valor en GVariant, como lo toma gsettings set)
  if ! es_sistema; then gsettings set "$1" "$2" "$3"; return; fi
  mkdir -p "$(dirname "$D_OVERRIDE")"; touch "$D_OVERRIDE"
  # Un esquema es una sección [esquema]; una clave repetida se reemplaza (la última gana).
  python3 -I - "$D_OVERRIDE" "$1" "$2" "$3" <<'PY'
import sys
ruta, esq, clave, valor = sys.argv[1:5]
secciones, orden, actual = {}, [], None
for linea in open(ruta, encoding='utf-8').read().splitlines():
    if linea.startswith('[') and linea.endswith(']'):
        actual = linea[1:-1]
        if actual not in secciones: secciones[actual] = {}; orden.append(actual)
    elif '=' in linea and actual:
        k, v = linea.split('=', 1); secciones[actual][k.strip()] = v.strip()
if esq not in secciones: secciones[esq] = {}; orden.append(esq)
secciones[esq][clave] = valor
with open(ruta, 'w', encoding='utf-8') as f:
    for s in orden:
        f.write('[%s]\n' % s)
        for k, v in secciones[s].items(): f.write('%s=%s\n' % (k, v))
        f.write('\n')
PY
}

unidad_usuario() { # enable|start|restart|stop|disable unidad…
  local accion="$1"; shift
  if ! es_sistema; then systemctl --user "$accion" "$@"; return; fi
  # En la imagen no hay sesión: solo cuenta habilitarla para todos (default.target.wants global).
  case "$accion" in
    enable|disable) systemctl ${RAIZ:+--root="$RAIZ"} --global "$accion" "$@" ;;
    *) : ;;
  esac
}
