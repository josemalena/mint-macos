# caso: `mint-macos-version --aplicar` pone el alto de la barra de la versión activa (si lo trae medido) y al volver a una sin medida deja el de antes
# límite: 90
# Va con el dconf de la prueba (la barra de mint-macos: panel arriba y menú Apple en los applets) y dos perfiles falsos: «prueba-con» (25 px) y «prueba-sin».
alto() { gsettings get org.cinnamon panels-height | tr -d "[]' @as"; }
elegir() {   # elegir ID: la versión escogida y aplicada
  mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_RUNTIME_DIR/mint-macos"
  echo "{\"version\": \"$1\"}" > "$XDG_CONFIG_HOME/mint-macos/macos.json"
  python3 -I "$AQUI/../perfiles/macos_version.py" --aplicar
}
prueba() {
  requiere gsettings python3
  AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local d="$HOME/.local/share/mint-macos/macos"
  mkdir -p "$d/prueba-con" "$d/prueba-sin"
  echo '{"pantalla": {"alto_barra_menu_pt": 25}}' > "$d/prueba-con/medidas.json"
  echo '{}' > "$d/prueba-sin/medidas.json"
  rm -f "$XDG_CONFIG_HOME/mint-macos/barra-altura.json"
  gsettings set org.cinnamon panels-enabled "['1:0:top']"
  gsettings set org.cinnamon panels-height "['1:22']"
  gsettings set org.cinnamon enabled-applets "['panel1:left:1:applemenu@macos:24']"
  elegir prueba-sin;  [ "$(alto)" = "1:22" ] || falla "una versión sin alto medido cambió la barra: $(alto)"
  elegir prueba-con;  [ "$(alto)" = "1:25" ] || falla "la versión con 25 no puso 25: $(alto)"
  paso "con alto medido: $(alto)"
  elegir prueba-con;  [ "$(alto)" = "1:25" ] || falla "aplicar dos veces la misma cambió algo: $(alto)"
  elegir prueba-sin;  [ "$(alto)" = "1:22" ] || falla "volver a una versión sin medida no devolvió el 22: $(alto)"
  [ ! -f "$XDG_CONFIG_HOME/mint-macos/barra-altura.json" ] || falla "quedó el estado después de volver"
  paso "ir y volver deja 22"
  # la persona cambió el alto a mano estando en la versión con medida: al volver no se le pisa
  elegir prueba-con; gsettings set org.cinnamon panels-height "['1:30']"
  elegir prueba-sin;  [ "$(alto)" = "1:30" ] || falla "pisó el alto que la persona puso a mano: $(alto)"
  # una versión que no existe, o con medidas ilegibles: no falla ni cambia nada
  echo 'no es json' > "$d/prueba-sin/medidas.json"
  gsettings set org.cinnamon panels-height "['1:22']"
  elegir prueba-sin;  [ "$(alto)" = "1:22" ] || falla "medidas ilegibles cambiaron la barra: $(alto)"
  elegir no-existe;   [ "$(alto)" = "1:22" ] || falla "una versión sin perfil cambió la barra: $(alto)"
  # que no sea la barra de mint-macos (sin el menú Apple): no se toca
  gsettings set org.cinnamon enabled-applets "['panel1:left:1:menu@cinnamon.org:1']"
  elegir prueba-con;  [ "$(alto)" = "1:22" ] || falla "tocó una barra que no es la de mint-macos: $(alto)"
  paso "no pisa lo que no es suyo ni falla con perfiles rotos"
  true
}
