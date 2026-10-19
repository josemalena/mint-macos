# caso: el menú Apple y el menú de la app leen sus textos del perfil de la versión de macOS activa (perfiles/ESQUEMA.md), por id; sin
# perfil siguen con los de siempre. El perfil de la prueba es inventado (nada de Apple) y las dos copias de perfil.js son iguales.
# límite: 120
# gestor: cinnamon-applets
prueba() {
  requiere xed gdbus xdotool
  cmp -s "$MINT_MACOS_REPO/applets/applemenu@macos/perfil.js" "$MINT_MACOS_REPO/applets/appmenu@macos/perfil.js" \
    || falla "perfil.js de applemenu y de appmenu no son iguales"
  paso "las dos copias de perfil.js son iguales"
  local base="$HOME/.local/share/mint-macos/macos/prueba-1.0/apps"
  mkdir -p "$base" "$XDG_RUNTIME_DIR/mint-macos"
  cat > "$base/menu-apple.json" <<'J'
{"id":"menu-apple","items":[
 {"id":"abtm","texto":"About This Test Machine"},
 {"id":"spro","texto":"Test System Information…","alterno_de":"abtm","mods_alterno":"⌥"},
 {"separador":true},
 {"id":"sysp","texto":"Test Settings…"},
 {"id":"soft","texto":"Test Store…"},
 {"separador":true},
 {"id":"apwn","texto":"Force Test Quit…","atajo":"⌥⌘⎋"},
 {"separador":true},
 {"id":"slep","texto":"Doze"},
 {"id":"rrst","texto":"Test Restart…"},
 {"id":"rest","texto":"Test Restart Now","alterno_de":"rrst","mods_alterno":"⌥"},
 {"id":"rsdn","texto":"Test Shut Down…"},
 {"id":"shut","texto":"Test Shut Down Now","alterno_de":"rsdn","mods_alterno":"⌥"},
 {"separador":true},
 {"id":"lock","texto":"Test Lock","atajo":"⌃⌘Q"},
 {"id":"logo","texto":"Test Log Out %@…","atajo":"⇧⌘Q"}]}
J
  cat > "$base/menus-estandar.json" <<'J'
{"id":"menus-estandar","menus":[{"id":"app","texto":"%@","items":[
 {"id":"orderFrontStandardAboutPanel:","texto":"About Test %@"},
 {"id":"showWindow:","texto":"Test Preferences…","atajo":"⌘,"},
 {"id":"hide:","texto":"Conceal %@","atajo":"⌘H"},
 {"id":"terminate:","texto":"Finish %@","atajo":"⌘Q"}]}]}
J
  echo '{"version":"prueba-1.0"}' > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
  # Los dos applets en el panel de la prueba.
  mkdir -p "$XDG_DATA_HOME/cinnamon/applets"
  cp -r "$MINT_MACOS_REPO/applets/applemenu@macos" "$XDG_DATA_HOME/cinnamon/applets/"
  gsettings set org.cinnamon enabled-applets "['panel1:left:0:appmenu@macos:1', 'panel1:left:1:globalmenu@macos:2', 'panel1:right:0:applemenu@macos:9']"
  sleep 5
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  xdotool windowfocus "$w" 2>/dev/null || true
  sleep 3
  ev() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1" 2>&1; }
  local r
  r="$(ev "let a=imports.ui.appletManager.getRunningInstancesForUuid('applemenu@macos')[0]; a._buildMenu(); a.menu._getMenuItems().filter(i=>i.label).map(i=>i.label.text).join('|')")"
  paso "menú Apple: $r"
  for t in "About This Test Machine" "Test Settings…" "Test Store…" "Force Test Quit…" "Doze" "Test Restart…" "Test Shut Down…" "Test Lock"; do
    case "$r" in *"$t"*) ;; *) falla "el menú Apple no trae «$t» del perfil: $r" ;; esac
  done
  case "$r" in *"Test Log Out"*"…"*) paso "Log Out con el nombre de la persona" ;; *) falla "falta «Test Log Out …»: $r" ;; esac
  # Con ⌥ los ítems pasan a sus alternos del perfil; al soltarlo, vuelven.
  r="$(ev "let a=imports.ui.appletManager.getRunningInstancesForUuid('applemenu@macos')[0]; a._conAlt=true; a._syncAlternos(); let con=a.menu._getMenuItems().filter(i=>i.label).map(i=>i.label.text).join('|'); a._conAlt=false; a._syncAlternos(); let sin=a.menu._getMenuItems().filter(i=>i.label).map(i=>i.label.text).join('|'); con+'##'+sin")"
  paso "alternos: $r"
  case "$r" in *"Test System Information…"*"Test Restart Now"*"Test Shut Down Now"*"##"*"About This Test Machine"*"Test Restart…"*) paso "con ⌥ cambian y al soltarlo vuelven" ;; *) falla "los alternos con ⌥ no funcionan: $r" ;; esac
  r="$(ev "let a=imports.ui.appletManager.getRunningInstancesForUuid('appmenu@macos')[0]; a._buildMenu(); a._updateMenuLabels(false); [a.hideItem.label.text, a.quitItem.label.text].join('|')")"
  paso "menú de la app: $r"
  case "$r" in *"Conceal "*"|Finish "*) ;; *) falla "el menú de la app no usa el perfil: $r" ;; esac
  # Sin perfil, el de siempre.
  echo '{"version":"no-existe-9.9"}' > "$XDG_RUNTIME_DIR/mint-macos/macos.json"
}
