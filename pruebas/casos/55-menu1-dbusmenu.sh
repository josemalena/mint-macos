# caso: org.mintmacos.Menu1 lee el menú de una app que publica com.canonical.dbusmenu (Firefox y compañía): barra, AboutToShow
# antes de abrir, atajos, y el clic llega a la app. La app y el registrador son de mentira (pruebas/ayudantes/dbusmenu-falso.py).
# límite: 120
prueba() {
  requiere mac-menu xdotool python3 gdbus
  local reg="$HOME/dbusmenu-falso.registro"; : > "$reg"
  # Una ventana X cualquiera sin propiedades de GTK: xterm o, si no hay, una de Gtk sin módulo de menú.
  GTK_MODULES="" lanzar python3 -c '
import gi; gi.require_version("Gtk","3.0")
from gi.repository import Gtk
w=Gtk.Window(title="sin-menu"); w.set_wmclass("sinmenu","SinMenu"); w.show_all(); Gtk.main()'
  local w; w="$(esperar_ventana '[Ss]in[Mm]enu' 30)"
  # un mac-menu de un caso anterior recuerda el xid (las ventanas de prueba repiten ids) y diría «ninguna»: se arranca uno nuevo
  for p in $(pgrep -x mac-menu); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  # y el registrador (el de mint-macos o el de vala-panel) que un caso anterior hizo activar por D-Bus: tiene el nombre del Registrar y esta app es de mentira
  for p in $(pgrep -f 'menu-global/mint-macos-registrador|menu-global/registrador.py|vala-panel/appmenu-registrar'); do grep -qz "^HOME=$HOME\$" "/proc/$p/environ" 2>/dev/null && kill "$p"; done
  sleep 1.5
  lanzar mac-menu
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/dbusmenu-falso.py" "$w" "$reg"
  sleep 2
  llamar() { gdbus call --session --dest org.mintmacos.Menu1 --object-path /org/mintmacos/Menu1 --method "org.mintmacos.Menu1.$1" "${@:2}" 2>&1 || true; }
  local f b
  f="$(llamar Fuente "$w")"; paso "Fuente: $f"
  b="$(llamar Barra "$w")"; paso "Barra: $b"
  case "$b" in *"'File'"*"'Edit'"*) ;; *) falla "la barra no trae File y Edit (sin el _): $b" ;; esac
  # el menú propio de la app (x-constanza-app-menu): no es un menú de arriba y MenuApp lo devuelve
  case "$b" in *FalsoApp*) falla "la barra repite el menú de la app marcado x-constanza-app-menu: $b" ;; esac
  local ma; ma="$(llamar MenuApp "$w")"; paso "MenuApp: $ma"
  case "$ma" in *"About FalsoApp"*"Quit FalsoApp"*) ;; *) falla "MenuApp no trae About y Quit del menú marcado: $ma" ;; esac
  local fid; fid="$(printf '%s' "$b" | grep -o "'id': <'d[0-9]*'>" | head -1 | grep -o "'d[0-9]*'" | tr -d "'")"
  local o; o="$(llamar Abrir "$w" "$fid")"; paso "File: $o"
  case "$o" in *"'New'"*) ;; *) falla "File no trae New: $o" ;; esac
  case "$o" in *"⌘N"*) paso "atajo de la Mac: ⌘N" ;; *) falla "New sin ⌘N: $o" ;; esac
  grep -q "AboutToShow" "$reg" || falla "no se llamó AboutToShow antes de abrir"
  local v; v="$(printf '%s' "$o" | grep -o "^(uint32 [0-9]*" | grep -o "[0-9]*$")"
  llamar Activar "$w" "$v" "d2" >/dev/null
  sleep 1
  grep -q "Event 2 clicked" "$reg" || falla "el clic no llegó a la app: $(cat "$reg")"
  llamar Cerrar "$w" "$fid" >/dev/null
  sleep 1
  grep -q "Event 1 closed" "$reg" || falla "no llegó el closed: $(cat "$reg")"
}
