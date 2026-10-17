# caso: Control-1 pone la primera etiqueta favorita (como _kMDItemUserTags de la
# Mac) y Control-0 las quita todas
# límite: 60
prueba() {
  requiere fynder getfattr
  necesita_teclado
  local d="$HOME/Documents/Etiquetas de prueba" f
  mkdir -p "$d"
  f="$d/Etiquetado.txt"
  echo x > "$f"
  lanzar fynder "$d"
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "Etiquetado.txt" 20
  teclas Down ctrl+1
  local ok=""
  for _ in $(seq 25); do
    getfattr -n user.com.apple.metadata:_kMDItemUserTags "$f" >/dev/null 2>&1 && { ok=1; break; }
    sleep 0.2
  done
  [ -n "$ok" ] || falla "Control-1 no puso la etiqueta"
  paso "Control-1 puso la etiqueta"
  teclas ctrl+0
  for _ in $(seq 25); do
    getfattr -n user.com.apple.metadata:_kMDItemUserTags "$f" >/dev/null 2>&1 || { ok=""; break; }
    sleep 0.2
  done
  [ -z "$ok" ] || falla "Control-0 no quitó las etiquetas"
  paso "Control-0 las quitó"
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
