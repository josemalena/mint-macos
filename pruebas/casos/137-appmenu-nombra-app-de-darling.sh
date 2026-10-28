# caso: la barra de menús y el «Force Quit %@» del menú de la manzana nombran a una app de Mac en Darling (WM_CLASS «darling-<id>», sin .desktop) con su _DARLING_APP_NAME
# límite: 120
# gestor: cinnamon-colgadas
prueba() {
  requiere xdotool python3 gdbus
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  lanzar python3 -I "$aqui/ayudantes/ventana-darling.py" TextEdit com.apple.TextEdit
  local w; w="$(esperar_ventana '^darling-com.apple.textedit$' 30)"
  xdotool windowfocus "$w" 2>/dev/null || true
  sleep 3
  local r
  r="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "let a=imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos'); let m=imports.ui.appletManager.getRunningInstancesForUuid('applemenu@macos'); [a.length ? a[0]._applet_label.get_text() : 'sin-appmenu', m.length ? m[0]._nombreDeApp(global.display.focus_window) : 'sin-applemenu'].join('|')" 2>&1)"
  paso "barra y manzana: $r"
  captura appmenu-darling
  case "$r" in *"'TextEdit|TextEdit'"*|*"TextEdit|TextEdit"*) ;; *) falla "la barra o el menú de la manzana no nombran «TextEdit»: $r" ;; esac
  case "$r" in *[Dd]arling*) falla "salió el nombre inventado con la clase: $r" ;; esac
}
