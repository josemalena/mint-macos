# caso: el panel de ⌘Tab nombra una app de Mac en Darling (WM_CLASS «darling-<id>», sin .desktop) con su _DARLING_APP_NAME, no «Darling com.apple.textedit»
# límite: 120
# gestor: cinnamon
prueba() {
  requiere xed xdotool python3 gdbus
  necesita_teclado
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  gsettings set org.cinnamon.desktop.keybindings.wm switch-windows "['<Super>Tab']"
  sleep 2
  lanzar xed
  esperar_ventana '^[Xx]ed$' 20 >/dev/null
  lanzar python3 -I "$aqui/ayudantes/ventana-darling.py" TextEdit com.apple.TextEdit
  esperar_ventana '^darling-com.apple.textedit$' 30 >/dev/null
  sleep 2
  xdotool keydown super; xdotool key Tab; sleep 1.5
  local nombres
  nombres="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "let t=[]; let rec=a=>{ if (a.style_class && a.style_class.indexOf('cmdtab-nombre')>=0) t.push(a.get_text()); a.get_children().forEach(rec); }; rec(imports.ui.main.uiGroup); t.join('|')" 2>&1)"
  captura cmdtab-darling
  xdotool key Escape; xdotool keyup super; sleep 1
  paso "nombres en el panel: $nombres"
  case "$nombres" in *TextEdit*) ;; *) falla "el panel no nombra la app de Darling «TextEdit»: $nombres" ;; esac
  case "$nombres" in *[Dd]arling*) falla "el panel muestra el nombre inventado con la clase: $nombres" ;; esac
}
