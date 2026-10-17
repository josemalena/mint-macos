# caso: ⌘Tab (cmdtab@macos) pasa a la app anterior y ⌘` rota entre las ventanas de la misma app
# límite: 120
# gestor: cinnamon
prueba() {
  requiere xed gnome-calculator xdotool
  necesita_teclado
  local f1="$HOME/Documents/uno.txt" f2="$HOME/Documents/dos.txt"
  mkdir -p "$HOME/Documents"; echo uno > "$f1"; echo dos > "$f2"

  # Los atajos de José (keyd manda ⌘ como Super): el Cinnamon de prueba trae los de fábrica.
  gsettings set org.cinnamon.desktop.keybindings.wm switch-windows "['<Super>Tab']"
  gsettings set org.cinnamon.desktop.keybindings.wm switch-group "['<Super>Above_Tab']"
  sleep 1
  lanzar xed "$f1"
  local x1; x1="$(esperar_ventana '^[Xx]ed$' 20)"
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

  paso "dos ventanas de xed: ⌘\` rota entre ellas"
  xdotool windowactivate "$x1"; sleep 0.5
  lanzar xed --new-window "$f2"
  local x2="" v
  for _ in $(seq 50); do
    for v in $(xdotool search --onlyvisible --class '^[Xx]ed$'); do
      [ "$v" != "$x1" ] && x2="$v"
    done
    [ -n "$x2" ] && break; sleep 0.2
  done
  [ -n "$x2" ] || falla "no salió la segunda ventana de xed"
  xdotool windowactivate "$x2"; sleep 0.5
  [ "$(xdotool getactivewindow)" = "$x2" ] || falla "la segunda ventana de xed no quedó al frente"
  teclas super+grave; sleep 1
  [ "$(xdotool getactivewindow)" = "$x1" ] || falla "⌘\` no pasó a la otra ventana de xed (frente: $(xdotool getactivewindow))"
  teclas super+grave; sleep 1
  [ "$(xdotool getactivewindow)" = "$x2" ] || falla "⌘\` no volvió a la primera"
  captura cmdtab-rotar
}
