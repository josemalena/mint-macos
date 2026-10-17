# caso: ⇧⌘G abre «Go to the folder:» y Go lleva a la carpeta escrita
# límite: 60
prueba() {
  requiere fynder
  necesita_teclado
  mkdir -p "$HOME/Documents/Destino de Go"
  lanzar fynder "$HOME"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  sleep 1
  teclas ctrl+shift+g
  esperar_texto "$v" "Go to the folder:" 10
  teclas ctrl+a
  xdotool type --delay 40 "~/Documents/Destino de Go"
  teclas Return
  local t=""
  for _ in $(seq 50); do
    t="$(titulo "$v")"
    case "$t" in "Destino de Go"*) break ;; esac
    sleep 0.2
  done
  case "$t" in "Destino de Go"*) paso "fue a la carpeta" ;; *) falla "el título quedó «$t»" ;; esac
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
