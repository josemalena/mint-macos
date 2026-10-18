# caso: un programa GTK con su propio GtkFileChooserDialog (como xed) guarda por la hoja de Fynder
# (fynder/gtk-module + portal; el diálogo de GTK no aparece y el programa recibe la ruta escogida)
# límite: 150
prueba() {
  requiere fynder python3 xdotool /usr/libexec/xdg-desktop-portal
  necesita_teclado
  local base mod
  base="$(dirname "$(command -v fynder)")/.."
  # instalado a mano (instalar-selector.sh) o en el paquete (meson install)
  for mod in "${FYNDER_MODULO:-}" "$base/lib/fynder/libfynder-chooser-module.so" \
             "$base"/lib/*/gtk-3.0/modules/libfynder-chooser-module.so; do
    [ -n "$mod" ] && [ -f "$mod" ] && break
  done
  [ -f "$mod" ] || saltar "no encuentro libfynder-chooser-module.so"
  paso "módulo: $mod"

  # el portal de la prueba escoge a Fynder para FileChooser (el portal 1.20 lee
  # los .portal y la preferencia de XDG_DESKTOP_PORTAL_DIR)
  local portales="$XDG_RUNTIME_DIR/portales" p
  mkdir -p "$portales" "$XDG_DATA_HOME/dbus-1/services" "$HOME/Documentos"
  for p in /usr/share/xdg-desktop-portal/portals/*.portal; do ln -sf "$p" "$portales/"; done
  printf '[portal]\nDBusName=org.freedesktop.impl.portal.desktop.fynder\nInterfaces=org.freedesktop.impl.portal.FileChooser;\n' \
    > "$portales/fynder.portal"
  printf '[preferred]\ndefault=xapp;gtk;\norg.freedesktop.impl.portal.FileChooser=fynder;\n' \
    | tee "$portales/portals.conf" > "$portales/x-cinnamon-portals.conf"
  printf '[D-BUS Service]\nName=org.freedesktop.impl.portal.desktop.fynder\nExec=%s --no-default-window\n' \
    "$(command -v fynder)" > "$XDG_DATA_HOME/dbus-1/services/org.freedesktop.impl.portal.desktop.fynder.service"
  gdbus call --session -d org.freedesktop.DBus -o /org/freedesktop/DBus -m org.freedesktop.DBus.ReloadConfig >/dev/null
  XDG_DESKTOP_PORTAL_DIR="$portales" lanzar /usr/libexec/xdg-desktop-portal --replace

  # el programa: su propio diálogo de guardar, como xed
  local cliente="$XDG_RUNTIME_DIR/guardar.py" salida="$PRUEBAS_RES/$PRUEBAS_CASO-programa.txt"
  cat > "$cliente" <<'PY'
import sys, os, gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, GLib
ventana = Gtk.Window(title="Programa con dialogo propio"); ventana.set_default_size(600, 400); ventana.show_all()
def abrir():
    d = Gtk.FileChooserDialog(title="Save As", transient_for=ventana, action=Gtk.FileChooserAction.SAVE)
    d.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Save", Gtk.ResponseType.OK)
    d.set_current_folder(os.path.expanduser("~/Documentos")); d.set_current_name("nota.txt")
    def respuesta(dd, r):
        print("RESPUESTA", r, dd.get_filename(), flush=True); Gtk.main_quit()
    d.connect("response", respuesta); d.show()
    return False
GLib.timeout_add(1000, abrir); GLib.timeout_add_seconds(110, Gtk.main_quit); Gtk.main()
PY
  GTK_MODULES="$mod" setsid python3 "$cliente" > "$salida" 2>&1 < /dev/null &

  # la hoja de Fynder (no el diálogo de GTK): la ventana de Fynder en Documentos
  local hoja=""
  for _ in $(seq 100); do
    hoja="$(xdotool search --onlyvisible --class Fynder 2>/dev/null | tail -1 || true)"
    [ -n "$hoja" ] && break
    sleep 1
  done
  [ -n "$hoja" ] || falla "no salió la hoja de Fynder (¿salió el diálogo de GTK?): $(tail -2 "$salida")"
  paso "hoja de Fynder: $hoja «$(titulo "$hoja")»"
  sleep 3
  xdotool windowactivate --sync "$hoja" 2>/dev/null || true
  xdotool key Return
  for _ in $(seq 20); do grep -q RESPUESTA "$salida" && break; sleep 0.5; done
  grep -q "RESPUESTA -5 $HOME/Documentos/nota.txt" "$salida" \
    || falla "el programa no recibió la ruta: $(grep RESPUESTA "$salida" || tail -2 "$salida")"
  paso "el programa recibió $HOME/Documentos/nota.txt con Save (-5)"
}
