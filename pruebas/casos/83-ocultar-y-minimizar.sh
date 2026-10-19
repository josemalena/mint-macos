# caso: ⌘H oculta la app del frente entera (todas sus ventanas) y ⌘M minimiza solo la ventana del frente, en kitty, Edge, Fynder y xed
# límite: 240
# gestor: cinnamon-applets
# keyd deja h y m sin regla en [meta] (keyd/default.conf) y sin excepción en app.conf, así que en la sesión de José
# ⌘H y ⌘M llegan como Super+H y Super+M a todas las apps; aquí xdotool los manda igual. Super+H lo atrapa
# appmenu@macos (_ocultarApp) y Super+M es el «minimize» de Muffin.
oculta() { xprop -id "$1" _NET_WM_STATE 2>/dev/null | grep -q _NET_WM_STATE_HIDDEN; }

al_frente() {
  local w="$1"
  for _ in 1 2 3; do
    xdotool windowactivate --sync "$w" 2>/dev/null || true
    sleep 0.5
    [ "$(xdotool getactivewindow 2>/dev/null)" = "$w" ] && return 0
  done
  falla "no pude traer al frente la ventana $w"
}

# dos ventanas de la misma app: ⌘M baja solo una; ⌘H, las dos; la de otra app sigue a la vista.
probar_app() {
  local nombre="$1" w1="$2" w2="$3" otra="$4"
  paso "── $nombre"
  al_frente "$w1"
  teclas super+m; sleep 1
  oculta "$w1" || falla "$nombre: ⌘M no minimizó la ventana del frente"
  oculta "$w2" && falla "$nombre: ⌘M minimizó también la otra ventana de la app"
  xdotool windowactivate "$w1" 2>/dev/null || true; sleep 1
  al_frente "$w2"
  teclas super+h; sleep 1
  oculta "$w1" && oculta "$w2" || falla "$nombre: ⌘H no ocultó las dos ventanas de la app"
  oculta "$otra" && falla "$nombre: ⌘H ocultó también la ventana de otra app"
  for w in "$w1" "$w2"; do xdotool windowactivate "$w" 2>/dev/null || true; done; sleep 1
  paso "$nombre: ⌘M y ⌘H bien"
}

dos_ventanas() { # CLASE (regex de WM_CLASS) → dos ids visibles
  local ids=""
  for _ in $(seq 100); do
    ids="$(xdotool search --onlyvisible --class "$1" 2>/dev/null | sort -u | tail -2 | tr '\n' ' ')"
    [ "$(echo $ids | wc -w)" -ge 2 ] && break; sleep 0.2
  done
  [ "$(echo $ids | wc -w)" -ge 2 ] || falla "no salieron dos ventanas de $1"
  echo "$ids"
}

prueba() {
  requiere xdotool xprop xed
  necesita_teclado
  # Super+M = minimizar lo pone install.sh (cinnamon/keybindings.dconf): el Cinnamon de prueba trae
  # los de fábrica, donde «minimize» está vacío.
  gsettings set org.cinnamon.desktop.keybindings.wm minimize "['<Super>m']"; sleep 2
  mkdir -p "$HOME/Documents"; echo uno > "$HOME/Documents/uno.txt"; echo dos > "$HOME/Documents/dos.txt"
  lanzar xed "$HOME/Documents/uno.txt"; sleep 2
  lanzar xed --new-window "$HOME/Documents/dos.txt"
  read -r x1 x2 <<< "$(dos_ventanas '^[Xx]ed$')"

  if command -v kitty >/dev/null; then
    lanzar kitty --class kitty; lanzar kitty --class kitty
    read -r k1 k2 <<< "$(dos_ventanas '^kitty$')"
    probar_app kitty "$k1" "$k2" "$x1"
  else paso "sin kitty: se salta"; fi

  if command -v fynder >/dev/null; then
    lanzar fynder --no-desktop "$HOME"; sleep 2; lanzar fynder --no-desktop "$HOME/Documents"
    read -r f1 f2 <<< "$(dos_ventanas '^[Ff]ynder$')"
    probar_app Fynder "$f1" "$f2" "$x1"
  else paso "sin fynder: se salta"; fi

  local edge; edge="$(command -v microsoft-edge || command -v google-chrome || true)"
  if [ -n "$edge" ]; then
    local perfil="$HOME/edge-prueba"
    lanzar "$edge" --user-data-dir="$perfil" --no-first-run --no-default-browser-check --disable-gpu --password-store=basic --new-window about:blank
    sleep 4
    lanzar "$edge" --user-data-dir="$perfil" --no-first-run --disable-gpu --password-store=basic --new-window about:blank
    read -r e1 e2 <<< "$(dos_ventanas '^(microsoft-edge|Microsoft-edge|google-chrome|Google-chrome)$')"
    probar_app "$(basename "$edge")" "$e1" "$e2" "$x1"
  else paso "sin Edge ni Chrome: se salta"; fi

  probar_app xed "$x1" "$x2" "${k1:-${f1:-$x1}}"
}
