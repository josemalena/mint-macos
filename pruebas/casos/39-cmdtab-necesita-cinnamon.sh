# caso: ⌘Tab (cmdtab@macos) pasa a la app anterior y ⌘` rota entre las ventanas de la misma app
# límite: 120
# gestor: cinnamon
# ⌘` y espera a que el frente sea DESTINO. xdotool dentro de Xephyr a veces pierde la captura de teclas de Muffin
# (en las corridas fallidas el registro de la extensión ni vio el atajo): se repite UNA vez. Sin la extensión no
# cambia nunca de ventana, así que el mutante sigue fallando.
rotar_hasta() {
  local destino="$1" intento
  for intento in 1 2; do
    teclas super+F10; sleep 1
    [ "$(xdotool getactivewindow)" = "$destino" ] && return 0
    paso "⌘\` no llegó (intento $intento)"
  done
  return 1
}

prueba() {
  requiere xed gnome-calculator xdotool
  necesita_teclado
  local f1="$HOME/Documents/uno.txt" f2="$HOME/Documents/dos.txt"
  mkdir -p "$HOME/Documents"; echo uno > "$f1"; echo dos > "$f2"

  # Los atajos de José (keyd manda ⌘ como Super): el Cinnamon de prueba trae los de fábrica.
  # ⌘` va aquí en Super+F10: en Xephyr, Super+grave (Above_Tab) lo resuelve Muffin a veces a otra acción (action 167 en lugar
  # de 20, medido con get_keybinding_action) y el atajo no llega a la extensión. La extensión solo mira el NOMBRE del atajo
  # (switch-group), así que la tecla concreta da igual para lo que se prueba; en la sesión de José es Above_Tab / masculine.
  # Uno por uno y con pausa: si Muffin recibe los dos cambios juntos a veces se queda con un atajo sin captura.
  gsettings set org.cinnamon.desktop.keybindings.wm switch-group "['<Super>F10']"
  sleep 2
  gsettings set org.cinnamon.desktop.keybindings.wm switch-windows "['<Super>Tab']"
  sleep 2
  lanzar xed "$f1"
  esperar_ventana '^[Xx]ed$' 20 >/dev/null
  local x1=""
  for _ in $(seq 75); do   # por el título: xed puede mapear antes otra ventana («Unsaved Document 1»)
    x1="$(xdotool search --onlyvisible --name 'uno\.txt' 2>/dev/null | tail -1 || true)"
    [ -n "$x1" ] && break; sleep 0.2
  done
  [ -n "$x1" ] || falla "no salió la ventana de xed con uno.txt"
  lanzar gnome-calculator
  local c; c="$(esperar_ventana '[Gg]nome-calculator' 20)"
  sleep 2   # la calculadora, la última que se abrió, queda al frente; ⌘ llega como Super
  [ "$(xdotool getactivewindow)" = "$c" ] || falla "la calculadora no quedó al frente antes de la prueba"

  paso "⌘Tab rápido: del frente (calculadora) a la app anterior (xed)"
  teclas super+Tab; sleep 1
  [ "$(xdotool getactivewindow)" = "$x1" ] || falla "⌘Tab no pasó a xed (frente: $(xdotool getactivewindow))"
  captura cmdtab-xed

  paso "⌘Tab otra vez: vuelve a la calculadora"
  teclas super+Tab; sleep 1
  [ "$(xdotool getactivewindow)" = "$c" ] || falla "⌘Tab no volvió a la calculadora"

  paso "⌘ sostenido + Tab: sale el panel de cmdtab (el selector de fábrica de Cinnamon no tiene esa clase)"
  xdotool keydown super; xdotool key Tab; sleep 1.5
  local panel
  panel="$(gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval \
    "let hay=false; let rec=a=>{ if (a.style_class && a.style_class.indexOf('cmdtab-panel')>=0) hay=true; a.get_children().forEach(rec); }; rec(imports.ui.main.uiGroup); hay ? 'PANEL' : 'nada'" 2>&1)"
  captura cmdtab-panel
  xdotool key Escape; xdotool keyup super; sleep 1
  case "$panel" in *PANEL*) paso "el panel de cmdtab está en pantalla" ;; *) falla "no salió el panel de cmdtab con ⌘Tab sostenido ($panel)" ;; esac

  paso "dos ventanas de xed: ⌘\` rota entre ellas"
  teclas super+Tab; sleep 1      # a xed, como lo haría José; nada de windowactivate (timestamp 0 que Muffin desconfía)
  [ "$(xdotool getactivewindow)" = "$x1" ] || falla "⌘Tab no pasó a xed antes de abrir la segunda ventana"
  lanzar xed --new-window "$f2"
  # La segunda ventana se espera por su título (el archivo), no «la que no sea la primera»: xed puede mapear otra antes.
  local x2=""
  for _ in $(seq 75); do
    x2="$(xdotool search --onlyvisible --name 'dos\.txt' 2>/dev/null | tail -1 || true)"
    [ -n "$x2" ] && break; sleep 0.2
  done
  [ -n "$x2" ] || falla "no salió la segunda ventana de xed (dos.txt)"
  paso "segunda ventana: $x2 «$(titulo "$x2")»"
  for _ in $(seq 25); do [ "$(xdotool getactivewindow 2>/dev/null)" = "$x2" ] && break; sleep 0.2; done
  [ "$(xdotool getactivewindow)" = "$x2" ] || falla "la segunda ventana de xed no quedó al frente"
  sleep 1   # que Muffin termine de asentar el orden de uso antes de rotar
  rotar_hasta "$x1" || falla "⌘\` no pasó a la otra ventana de xed (frente: $(xdotool getactivewindow))"
  rotar_hasta "$x2" || falla "⌘\` no volvió a la primera (frente: $(xdotool getactivewindow))"
  captura cmdtab-rotar
}
