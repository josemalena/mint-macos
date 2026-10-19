# caso: Keyboard ▸ Shortcuts ▸ App Shortcuts enseña los atajos guardados (atajos-apps.json) y «+» abre la hoja con Application,
# Menu Title y Keyboard Shortcut
# límite: 120
prueba() {
  requiere mac-preferencias xdotool python3
  export MP_PYTHON_DIR="$MINT_MACOS_REPO/settings"
  export MINT_ATAJOS_APPS="$HOME/atajos-apps.json"
  printf '{"version":1,"atajos":[{"app":"*","nombre":"All Applications","titulo":"Print Test","atajo":"⇧⌘P"},{"app":"xed.desktop","nombre":"Text Editor","titulo":"Word wrap","atajo":"⌥⌘9"}]}' > "$MINT_ATAJOS_APPS"
  lanzar mac-preferencias
  local v; v="$(esperar_ventana '[Mm]ac-settings' 40)"
  mac-preferencias keyboard
  for _ in $(seq 50); do [ "$(titulo "$v")" = "Keyboard" ] && break; sleep 0.2; done
  [ "$(titulo "$v")" = "Keyboard" ] || falla "no abrió Keyboard: «$(titulo "$v")»"
  atspi() { python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$(xdotool getwindowpid "$v")" "$@"; }
  atspi --texto "Shortcuts" --rol "radio button" --pulsar --segundos 20 >&2 || falla "no se pudo pulsar la pestaña Shortcuts"
  sleep 1
  # Las categorías son etiquetas sin acción: se pulsan en su lugar (extensión de AT-SPI) con el ratón.
  local xy; xy="$(python3 - "$(xdotool getwindowpid "$v")" "App Shortcuts" <<'PY'
import sys, gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
pid, texto = int(sys.argv[1]), sys.argv[2]
esc = Atspi.get_desktop(0)
for i in range(esc.get_child_count()):
    app = esc.get_child_at_index(i)
    if app and app.get_process_id() == pid:
        pila = [app]
        while pila:
            n = pila.pop(0)
            try:
                if n.get_name() == texto and n.get_role_name() == "label":
                    e = n.get_component_iface().get_extents(Atspi.CoordType.SCREEN)
                    print(e.x + e.width // 2, e.y + e.height // 2)
                    raise SystemExit(0)
                for k in range(n.get_child_count()):
                    pila.append(n.get_child_at_index(k))
            except SystemExit:
                raise
            except Exception:
                pass
PY
)"
  [ -n "$xy" ] || falla "no encontré la categoría App Shortcuts"
  xdotool mousemove $xy click 1
  sleep 1
  esperar_texto "$v" "Print Test" 20
  esperar_texto "$v" "Word wrap" 10
  esperar_texto "$v" "▾ Text Editor" 10
  captura app-shortcuts
  pulsar "$v" "+" 10
  sleep 1
  local pid arbol; pid="$(xdotool getwindowpid "$v")"
  arbol="$(python3 "$(dirname "$PRUEBAS_LIB")/atspi.py" --pid "$pid" --volcar 2>/dev/null || true)"
  captura app-shortcuts-hoja
  for t in "Menu Title:" "Keyboard Shortcut:" "Add"; do
    case "$arbol" in *"$t"*) paso "la hoja trae «$t»" ;; *) falla "la hoja no trae «$t»" ;; esac
  done
  pulsar "$v" "Cancel" 10
}
