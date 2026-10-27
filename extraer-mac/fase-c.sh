# fase-c.sh — la ronda «fase C» de Dev-Dock (27-10-2026), pensada para Monterey 12.7.6.
# No se corre suelto: lo carga extraer.sh con `bash extraer.sh fase-c` (usa sus
# ayudantes, $H, $CAP, $VID, $W, $HH, $DOCK, osa, cap_*, modo, devolver…).
# La lista viene de referencias/trabajo-samana-20261026/LISTA-CAPTURAS-FASE-C.md.
#
#   FASE="A B C D E" bash extraer.sh fase-c     (por omisión, todas las secciones)
#
#   A  estados de controles (apretado, puntero encima, foco, inactivo), claro y oscuro
#   B  ventanas, barras, menús y Dock sobre fondo liso blanco, negro y gris,
#      con «Reduce transparency» apagado y encendido
#   C  videos que faltaban (Mission Control con ventanas, salidas, Launchpad,
#      genio con ⇧, Dock oculto, pila, NC, banner, ventana, menú)
#   D  hojas y páginas de System Preferences que no había
#   E  datos: ajustes de accesibilidad y `defaults read` de Dock, reloj, Control Center y global
#
# Fuera de esta ronda, y anotado en la bitácora (no se inventa): C8 el login (hay que
# cerrar la sesión), C9 de macOS 27 (es otra Mac), D1 con dos pantallas, D5 portátil o
# UPS, D10 Dictation y una segunda fuente de entrada (cambian ajustes de idioma),
# D15 encender servicios de Sharing (solo se selecciona la fila), D16 «Connect» de
# Bluetooth y A12 el switch (Monterey casi no usa NSSwitch).
#
# Todo lo que se cambia se anota antes y vuelve en devolver(): fondo, Reduce
# transparency, Full Keyboard Access, volumen, acento, Dock y modo.

FC="$SAL/fase-c"; FCC="$FC/capturas"; FCV="$FC/videos"; FCD="$FC/datos"
mkdir -p "$FCC" "$FCV" "$FCD"
seccion() { case " ${FASE:-A B C D E} " in *" $1 "*) return 0;; esac; return 1; }
fuera() { log "fase-c: NO SE HACE $1 — $2"; echo "$1: $2" >> "$FC/no-hecho.txt"; }
: > "$FC/no-hecho.txt"
SP="System Preferences"

# ---- lo que se cambia, como estaba ---------------------------------------------
FONDO_ORIG="$(osa -e 'tell application "System Events" to get picture of every desktop' | tr ',' '\n' | sed 's/^ *//' | head -1)"
RT_ORIG="$(leer_def com.apple.universalaccess reduceTransparency)"
FKA_ORIG="$(leer_def -g AppleKeyboardUIMode)"
VOL_ORIG="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
RT_TOCADO=false; FONDO_TOCADO=false; FKA_TOCADO=false
fase_c_devolver() {
  if $FONDO_TOCADO && [ -n "$FONDO_ORIG" ]; then
    osa -e "tell application \"System Events\" to set picture of every desktop to \"$FONDO_ORIG\""; FONDO_TOCADO=false; log "fase-c: fondo devuelto"; fi
  if $RT_TOCADO; then rt_poner "$( [ "$RT_ORIG" = 1 ] && echo true || echo false )"; RT_TOCADO=false; log "fase-c: Reduce transparency devuelto ($RT_ORIG)"; fi
  if $FKA_TOCADO; then poner_def -g AppleKeyboardUIMode "$FKA_ORIG" int; FKA_TOCADO=false; log "fase-c: Full Keyboard Access devuelto"; fi
  [ -n "$VOL_ORIG" ] && osascript -e "set volume output volume $VOL_ORIG" 2>/dev/null
  osa -e "tell application \"$SP\" to quit" 2>/dev/null
  osa -e 'tell application "TextEdit" to quit saving no' 2>/dev/null
  return 0
}

# ---- ayudantes ---------------------------------------------------------------------
# System Events se cierra solo tras un rato sin uso y JXA puede seguir dando -600 aunque vuelva;
# AppleScript sí lo levanta (Mint-Macos, 12.7.6, 27-10-2026): se le habla así antes de cada búsqueda.
se_despierto() { osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1; }
marco() { se_despierto; $H ui "$1" buscar "$2" "$3" "${4:-1}" 2>>"$LOG"; }            # proc rol regex [n] → x y w h
pulsar() { se_despierto; $H ui "$1" pulsar "$2" "$3" "${4:-1}" >/dev/null 2>>"$LOG"; }
abrir_popup() { se_despierto; $H ui "$1" menu "$2" "$3" "${4:-1}" >/dev/null 2>>"$LOG"; }
fuera_xy() { echo "$((W-60)) $((HH/2))"; }   # para soltar sin disparar nada (lejos de las esquinas activas)
pref() { # pane [anchor]
  osa -e "tell application \"$SP\" to activate"
  if [ -n "${2:-}" ]; then osa -e "tell application \"$SP\" to reveal anchor \"$2\" of pane id \"$1\""
  else osa -e "tell application \"$SP\" to set current pane to pane id \"$1\""; fi
  sleep 2.5; raton_fuera; }
capsp() { cap_win "$1" "$(ventana_pref)"; }
cancelar_hoja() { # la hoja de adelante: Cancel, Done u OK (en ese orden)
  local b; for b in Cancel Done OK; do pulsar "$SP" AXButton "^$b$" && { sleep 1; return 0; }; done; esc; }
# Los estados de un control: puntero encima, apretado (y soltar fuera) y, si se pide, con la ventana inactiva.
estados() { # nombre proc rol regex [n] [ventana-id-fn] [sitio|no-apretar]
  # «sitio»: un slider se suelta donde se apretó (soltarlo lejos cambiaría el valor);
  # «no-apretar»: solo reposo y encima (el brillo no se puede devolver).
  local nom="$1" p="$2" rol="$3" re="$4" n="${5:-1}" vfn="${6:-ventana_pref}" modo_s="${7:-}" m
  m="$(marco "$p" "$rol" "$re" "$n")"; [ -n "$m" ] || { fuera "A $nom" "no encontré $rol /$re/ en $p"; return 1; }
  set -- $m; local cx=$(( $1 + $3/2 )) cy=$(( $2 + $4/2 ))
  # El id de la ventana se pide UNA vez, antes de apretar: con el botón abajo la app está
  # en su bucle de seguimiento y no contesta (el Finder dio -1712 y salió la pantalla entera).
  local wid; wid="$($vfn)"
  cap_win "A-$nom-reposo-$M" "$wid"
  $H raton mover $cx $cy; sleep 0.6; cap_win "A-$nom-encima-$M" "$wid"
  if [ "$modo_s" != no-apretar ]; then
    $H raton apretar $cx $cy; sleep 0.6; cap_win "A-$nom-apretado-$M" "$wid"
    if [ "$modo_s" = sitio ]; then $H raton soltar $cx $cy; else $H raton soltar $(fuera_xy); fi
    sleep 0.6
  fi
  raton_fuera
  log "fase-c A $nom: $m (centro $cx,$cy)"
}
inactiva() { # nombre fn-de-ventana [prefijo]: la misma ventana con el Finder al frente
  finder_activar; sleep 0.8; cap_win "${3:-A}-$1-inactiva-$M" "$($2)"; }
id_textedit() { ventana_de TextEdit; }
rt_poner() { # true|false — Reduce transparency por la interfaz (escribir el dominio está protegido)
  pref com.apple.preference.universalaccess Seeing_Display
  local m; m="$(marco "$SP" AXCheckBox '^Reduce transparency')"
  [ -n "$m" ] || { log "fase-c: no encontré «Reduce transparency»"; return 1; }
  local v; v="$(leer_def com.apple.universalaccess reduceTransparency)"
  { [ "$1" = true ] && [ "$v" != 1 ]; } || { [ "$1" = false ] && [ "$v" = 1 ]; } && pulsar "$SP" AXCheckBox '^Reduce transparency'
  sleep 1.5; log "fase-c: Reduce transparency → $1 (leído: $(leer_def com.apple.universalaccess reduceTransparency))"; }
fondo_liso() { # blanco|negro|gris
  local rgb; case "$1" in blanco) rgb="255 255 255";; negro) rgb="0 0 0";; gris) rgb="128 128 128";; esac
  local f="$FC/.fondo-$1.png"; $H liso $rgb "$f" >/dev/null 2>>"$LOG"
  FONDO_TOCADO=true
  osa -e "tell application \"System Events\" to set picture of every desktop to \"$f\""; sleep 2; }

# ======================================================================== E (datos)
if seccion E; then
  for d in com.apple.dock com.apple.menuextra.clock com.apple.controlcenter NSGlobalDomain; do
    defaults read "$d" > "$FCD/defaults-$d.txt" 2>&1; done
  { for k in reduceTransparency increaseContrast reduceMotion differentiateWithoutColor; do
      echo "$k=$(leer_def com.apple.universalaccess $k)"; done
    echo "AppleAccentColor=$(leer_def -g AppleAccentColor)"; echo "AppleHighlightColor=$(leer_def -g AppleHighlightColor)"
    echo "AppleKeyboardUIMode=$(leer_def -g AppleKeyboardUIMode)"; echo "fondo=$FONDO_ORIG"; } > "$FCD/ajustes-ui.txt"
  log "fase-c E: datos en $FCD"
fi

# =================================================================== A (controles)
fase_a() {
  # A4 botón normal (Displays ▸ «Night Shift…»), A11 slider (Displays ▸ Brightness)
  pref com.apple.preference.displays
  estados boton-night-shift "$SP" AXButton '^Night Shift'
  estados slider-brillo "$SP" AXSlider 'bright|brillo' 1 ventana_pref no-apretar || true
  # A6 el «?»
  estados boton-ayuda "$SP" AXButton '^help$|^Help$' || true
  # A7 popups de General: cerrado, apretado (abre el menú), una fila resaltada, y se suelta fuera
  pref com.apple.preference.general
  local i; for i in 1 2 3; do
    local m; m="$(marco "$SP" AXPopUpButton '' $i)"; [ -n "$m" ] || break
    set -- $m; local cx=$(( $1 + $3/2 )) cy=$(( $2 + $4/2 ))
    cap_win "A-popup$i-cerrado-$M" "$(ventana_pref)"
    $H raton apretar $cx $cy; sleep 1; cap_full "A-popup$i-abierto-$M"
    $H raton arrastrar-a $cx $((cy+24)); sleep 0.6; cap_full "A-popup$i-fila-resaltada-$M"
    $H raton soltar $(fuera_xy); sleep 0.6; esc; raton_fuera
  done
  # A3 radios (Appearance), A14 el anillo de foco con Full Keyboard Access
  # En Monterey los tres de Appearance son AXCheckBox (subrol AXToggle): «Light», «Dark» y uno
  # sin nombre cuya ayuda dice «Automatically adjusts…». El 2.º es Dark.
  estados radio-apariencia "$SP" AXCheckBox '^(Light|Dark)$|^Automatically adjusts' 2 || true
  FKA_TOCADO=true; defaults write -g AppleKeyboardUIMode -int 2
  osa -e "tell application \"$SP\" to quit"; sleep 1.5; pref com.apple.preference.general
  for i in 1 2 3 4 5 6; do tecla "$SP" 'key code 48'; sleep 0.6; cap_win "A-foco-tab$i-$M" "$(ventana_pref)"; done
  poner_def -g AppleKeyboardUIMode "$FKA_ORIG" int; FKA_TOCADO=false
  # A1 checkbox (Dock & Menu Bar ▸ Magnification), A9 pestañas de Keyboard
  pref com.apple.preference.dock
  estados checkbox-dock "$SP" AXCheckBox '^Magnification' || true
  pref com.apple.preference.keyboard keyboardTab
  estados pestana-text "$SP" AXRadioButton '^Text$' || true
  inactiva pestanas-keyboard ventana_pref
  # A9 deshabilitado: Security & Privacy con el candado cerrado (solo se mira; no se abre)
  pref com.apple.preference.security General; capsp "A-security-candado-cerrado-$M"
  # A11 slider de Sound ▸ Output volume (el volumen vuelve en devolver)
  pref com.apple.preference.sound output; estados slider-volumen "$SP" AXSlider '' 1 ventana_pref sitio || true
  # A10 segmentado clásico: las vistas de la barra del Finder; A13 su búsqueda; A15 selección de la barra lateral
  osa -e "tell application \"$SP\" to quit"; sleep 1
  cerrar_finder; ventana_finder . icon $X1 $Y1 $X2 $Y2; finder_activar
  estados segmentado-vistas Finder AXRadioButton 'list' 1 id_finder || estados segmentado-vistas Finder AXButton 'list' 1 id_finder || true
  inactiva segmentado-vistas id_finder; finder_activar
  # En Monterey la búsqueda está plegada en un AXButton «Search»; al pulsarlo sale el
  # AXTextField (subrol AXSearchField, descripción «search text field»).
  local s; s="$(marco Finder AXTextField 'search')"
  if [ -z "$s" ] && [ -n "$(marco Finder AXButton '^Search$')" ]; then
    cap_win "A-busqueda-plegada-$M" "$(id_finder)"
    pulsar Finder AXButton '^Search$'; sleep 1; s="$(marco Finder AXTextField 'search')"; fi
  if [ -n "$s" ]; then set -- $s; cap_win "A-busqueda-reposo-$M" "$(id_finder)"
    $H raton clic $(( $1 + $3/2 )) $(( $2 + $4/2 )); sleep 0.8; cap_win "A-busqueda-foco-$M" "$(id_finder)"
    tecla Finder 'keystroke "Lago"'; sleep 1.2; cap_win "A-busqueda-texto-$M" "$(id_finder)"; esc; esc
  else fuera "A13 búsqueda" "no encontré el campo de búsqueda del Finder"; fi
  cap_win "A-barra-lateral-seleccion-activa-$M" "$(id_finder)"; inactiva barra-lateral-seleccion id_finder
  cerrar_finder
  # A5/A8 diálogo Save de TextEdit: botón por defecto y el disclosure; nada se guarda (Cancel)
  osa -e 'tell application "TextEdit" to activate' -e 'tell application "TextEdit" to make new document'; sleep 1.5
  tecla TextEdit 'keystroke "s" using command down'; sleep 1.5
  estados boton-save TextEdit AXButton '^Save$' 1 id_textedit || true
  estados disclosure-save TextEdit AXDisclosureTriangle '' 1 id_textedit || estados disclosure-save TextEdit AXButton 'expand|disclosure|show details' 1 id_textedit || true
  inactiva hoja-save id_textedit
  osa -e 'tell application "TextEdit" to activate'; tecla TextEdit 'key code 53'; sleep 0.8
  osa -e 'tell application "TextEdit" to quit saving no'; sleep 1
  fuera A12 "Monterey casi no usa NSSwitch; «Allow Notifications» es casilla"
  fuera A2 "el checkbox mixto: Keyboard ▸ Shortcuts ▸ Services ya sale en el bloque 08 (keyboard-shortcuts-N)"
}
if seccion A; then
  ocultar; raton_fuera
  for M in claro oscuro; do modo $([ $M = oscuro ] && echo true || echo false); CAP="$FCC"; fase_a; done
  # A15 con acento Graphite (el acento vuelve en devolver)
  ACENTO_TOCADO=true; poner_def -g AppleAccentColor -1 int; poner_def -g AppleAquaColorVariant 6 int
  $H avisar-colores >/dev/null 2>>"$LOG"; killall Finder; sleep 3
  M=claro; modo false; CAP="$FCC"; ventana_finder . icon $X1 $Y1 $X2 $Y2; finder_activar
  cap_win "A-barra-lateral-seleccion-graphite-$M" "$(id_finder)"; cerrar_finder
  acento_reponer
fi

# ============================================== B (fondos, sombras, barras y Dock)
fase_b() { # fondo rt
  local f="$1" rt="$2" suf="$1-rt$2-$M"
  cerrar_finder; cap_full "B-escritorio-$suf"
  ventana_finder . icon $X1 $Y1 $X2 $Y2; finder_activar; raton_fuera; cap_full "B-finder-activo-$suf"
  abrir_menu Finder File; cap_full "B-menu-file-$suf"; esc
  inactiva "finder-$suf" id_finder B
  cerrar_finder
}
if seccion B; then
  ocultar; raton_fuera; CAP="$FCC"
  for M in claro oscuro; do modo $([ $M = oscuro ] && echo true || echo false)
    for rt in 0 1; do
      RT_TOCADO=true; rt_poner $([ $rt = 1 ] && echo true || echo false); osa -e "tell application \"$SP\" to quit"; sleep 1
      for f in blanco negro gris; do fondo_liso $f; fase_b $f $rt; done
    done
    # B2 sin barra de título (Spotlight) sobre blanco y negro; B6 Dock lateral y con lupa sobre gris
    for f in blanco negro; do fondo_liso $f; tecla no-terminal 'keystroke space using command down'; sleep 1.5; cap_full "B-spotlight-$f-$M"; esc; done
    fondo_liso gris
    for o in left right; do defaults write com.apple.dock orientation -string $o; killall Dock; sleep 3; cap_full "B-dock-$o-gris-$M"; done
    poner_def com.apple.dock orientation "$ORI_ORIG" string
    defaults write com.apple.dock magnification -bool true; defaults write com.apple.dock largesize -int 128; killall Dock; sleep 3
    $H raton mover $((W/2)) $((HH-DOCK/2)); sleep 1; cap_full "B-dock-lupa-gris-$M"
    # B7 la etiqueta de un ícono del Dock
    poner_def com.apple.dock magnification "$MAG_ORIG" bool; killall Dock; sleep 3
    d="$(marco Dock AXDockItem '^Finder$')"; [ -n "$d" ] && { set -- $d; $H raton mover $(( $1 + $3/2 )) $(( $2 + $4/2 )); sleep 1.5; cap_full "B-dock-etiqueta-$M"; }
    raton_fuera
  done
  RT_TOCADO=true; rt_poner "$( [ "$RT_ORIG" = 1 ] && echo true || echo false )"; RT_TOCADO=false
fi

# ======================================================================= C (videos)
if seccion C; then
  exigir_pantalla fase-c-videos
  modo true; ocultar; cerrar_finder; raton_fuera
  grabar() { screencapture -V "$2" -x "$FCV/$1.mov" & GP=$!; sleep 1.2; }
  marca() { log "fase-c C $1: $2 (t≈$(( $(date +%s) - T0 )) s)"; }
  cuatro() { local w2=$((W/2)) h2=$(( (HH-DOCK-BARRA)/2 + BARRA )); cerrar_finder
    ventana_finder . icon 20 $((BARRA+10)) $((w2-10)) $((h2-10)); ventana_finder Documentos list $((w2+10)) $((BARRA+10)) $((W-20)) $((h2-10))
    ventana_finder Imágenes icon 20 $((h2+10)) $((w2-10)) $((HH-DOCK-20)); ventana_finder Proyectos column $((w2+10)) $((h2+10)) $((W-20)) $((HH-DOCK-20)); }
  # C1 Mission Control con cuatro ventanas
  cuatro; finder_activar; raton_fuera
  grabar C1-mission-control 14; T0=$(date +%s)
  open -a "Mission Control"; marca C1 entrar; sleep 3; open -a "Mission Control"; marca C1 "salir (otra vez)"; sleep 3
  open -a "Mission Control"; sleep 3; esc; marca C1 "salir (Esc)"; sleep 2; wait $GP
  fuera "C1 ventana a miniatura" "en Mission Control no hay un disparador fiable por guion"
  cerrar_finder
  # C2 salidas de Spotlight y Control Center (Esc y clic afuera)
  grabar C2-spotlight-salida 8; T0=$(date +%s); tecla no-terminal 'keystroke space using command down'; sleep 2; esc; marca C2 "Spotlight Esc"
  sleep 1.5; tecla no-terminal 'keystroke space using command down'; sleep 2; $H raton clic $((W/2)) $((HH-DOCK-60)); marca C2 "Spotlight clic afuera"; sleep 1.5; wait $GP
  grabar C2-control-center-salida 8; T0=$(date +%s); item_barra "Control Center"; sleep 2; esc; marca C2 "CC Esc"
  sleep 1.5; item_barra "Control Center"; sleep 2; $H raton clic $((W/2)) $((HH/2)); marca C2 "CC clic afuera"; sleep 1.5; wait $GP
  # C3 salida de la lupa del Dock
  defaults write com.apple.dock magnification -bool true; defaults write com.apple.dock largesize -int 128; killall Dock; sleep 3
  grabar C3-lupa-salida 6; T0=$(date +%s); $H raton mover $((W/2)) $((HH-DOCK/2)); sleep 1.5; raton_fuera; marca C3 "puntero fuera"; sleep 2; wait $GP
  poner_def com.apple.dock magnification "$MAG_ORIG" bool; poner_def com.apple.dock largesize "$LARGE_ORIG" int; killall Dock; sleep 3
  # C4 Launchpad: página 1 → 2 → 1 con la rueda
  grabar C4-launchpad-paginas 9; T0=$(date +%s); open -a Launchpad; sleep 2
  $H raton mover $((W/2)) $((HH/2)); $H raton rueda -3 0 6; marca C4 "a la página 2"; sleep 2; $H raton rueda 3 0 6; marca C4 "de vuelta"; sleep 2; esc; wait $GP
  # C5 genio con ⇧, ventana chica y grande
  for t in chica grande; do
    cerrar_finder
    if [ $t = chica ]; then ventana_finder . icon $((W/2-200)) $((HH/2-130)) $((W/2+200)) $((HH/2+130)); else ventana_finder . icon 40 $((BARRA+20)) $((W-40)) $((HH-DOCK-30)); fi
    finder_activar; raton_fuera
    b="$(marco Finder AXButton 'minimize')"
    grabar C5-genio-shift-$t 10; T0=$(date +%s)
    if [ -n "$b" ]; then set -- $b; $H raton clic-shift $(( $1 + $3/2 )) $(( $2 + $4/2 )); marca C5 "minimizar con ⇧ ($t)"
    else tecla Finder 'keystroke "m" using command down'; marca C5 "minimizar ⌘M, sin ⇧: no encontré el botón amarillo ($t)"; fi
    sleep 4; log "  C5 $t: minimizada=$(osascript -e 'tell application "Finder" to get collapsed of Finder window 1' 2>&1)"
    osa -e 'tell application "Finder" to set collapsed of Finder window 1 to false'; marca C5 "restaurar"; sleep 3; wait $GP
  done
  cerrar_finder
  # C6 Dock oculto: entrar y salir (autohide vuelve en devolver)
  defaults write com.apple.dock autohide -bool true; killall Dock; sleep 3; raton_fuera
  grabar C6-dock-oculto 8; T0=$(date +%s); $H raton mover $((W/2)) $((HH-2)); marca C6 entrar; sleep 2.5; $H raton mover $((W/2)) $((HH/2)); marca C6 salir; sleep 2.5; wait $GP
  poner_def com.apple.dock autohide "$AUTOHIDE_ORIG" bool; killall Dock; sleep 3
  # C7 la pila de Downloads del Dock (en la vista que tenga: no se le cambia)
  s="$(marco Dock AXDockItem '^Downloads$')"
  if [ -n "$s" ]; then set -- $s; grabar C7-pila-dock 8; T0=$(date +%s); $H raton clic $(( $1 + $3/2 )) $(( $2 + $4/2 )); marca C7 abrir; sleep 2.5; esc; marca C7 cerrar; sleep 2; wait $GP
    fuera "C7 abanico y cuadrícula" "se grabó la vista que tiene la pila; cambiarla toca la preferencia del Dock"
  else fuera C7 "no hay pila Downloads en el Dock"; fi
  # C10 banner y C9 Notification Center con dos avisos
  grabar C10-banner 10; T0=$(date +%s); osascript -e 'display notification "Aviso de prueba de extraer-mac" with title "Extraer Mac"'; marca C10 "entra el banner"; sleep 8; wait $GP
  osascript -e 'display notification "Segundo aviso de prueba" with title "Extraer Mac"'; sleep 6
  grabar C9-notification-center 8; T0=$(date +%s); item_barra Clock; marca C9 abrir; sleep 3; item_barra Clock; marca C9 cerrar; sleep 2; wait $GP
  # C11 abrir y cerrar una ventana, y pantalla completa
  finder_activar; grabar C11-ventana-abrir-cerrar 8; T0=$(date +%s)
  tecla Finder 'keystroke "n" using command down'; marca C11 abrir; sleep 2.5; tecla Finder 'keystroke "w" using command down'; marca C11 cerrar; sleep 2; wait $GP
  ventana_finder . icon $X1 $Y1 $X2 $Y2; finder_activar
  grabar C11-pantalla-completa 10; T0=$(date +%s)
  tecla Finder 'keystroke "f" using {command down, control down}'; marca C11 "entrar a pantalla completa"; sleep 4
  tecla Finder 'keystroke "f" using {command down, control down}'; marca C11 "salir"; sleep 3; wait $GP
  # C12 abrir un menú y escoger un ítem (View ▸ as List: solo cambia la vista de la ventana de Muestra)
  finder_activar; grabar C12-menu-escoger 6; T0=$(date +%s); abrir_menu Finder View; marca C12 abrir; sleep 1
  osa -e 'tell application "System Events" to tell process "Finder" to click menu item "as List" of menu 1 of menu bar item "View" of menu bar 1'; marca C12 escoger; sleep 2; wait $GP
  cerrar_finder
  fuera C8 "el login: hay que cerrar la sesión; va a mano"
  fuera C9-27 "el NC y el genio de macOS 27: es otra Mac"
  fuera "Spaces" "cambiar de escritorio necesita un segundo Space; crearlo cambia la configuración de Mission Control"
fi

# ======================================================== D (System Preferences)
filas() { # prefijo: selecciona cada fila de la primera tabla o lista y la captura
  local i=1 n; se_despierto; n="$($H ui "$SP" fila 1 2>>"$LOG")"; [ -n "$n" ] || { fuera "D $1" "sin tabla"; return; }
  while [ $i -le "$n" ] && [ $i -le 30 ]; do $H ui "$SP" fila $i >/dev/null 2>>"$LOG"; sleep 1.2; capsp "D-$1-fila$i-$M"; i=$((i+1)); done; }
pestanas() { # prefijo: cada pestaña (AXRadioButton del tab group) de la ventana o la hoja de adelante
  local i=1 n; se_despierto; n="$($H ui "$SP" contar AXRadioButton 2>>"$LOG")"
  while [ $i -le "${n:-0}" ] && [ $i -le 12 ]; do pulsar "$SP" AXRadioButton '' $i; sleep 1.2; capsp "D-$1-pestana$i-$M"; i=$((i+1)); done; }
hoja() { # prefijo regex-del-botón: abre la hoja, la captura y la cierra
  pulsar "$SP" AXButton "$2" || { fuera "D $1" "no encontré el botón /$2/"; return 1; }
  sleep 1.8; raton_fuera; capsp "D-$1-$M"; }
popup_abierto() { # prefijo n
  abrir_popup "$SP" AXPopUpButton '' "$2" || { fuera "D $1" "sin popup $2"; return; }
  sleep 1; cap_full "D-$1-$M"; esc; sleep 0.5; }
fase_d() {
  # D1 Displays: Night Shift (y su Schedule abierto), Color Profile abierto, Universal Control
  pref com.apple.preference.displays; capsp "D-displays-$M"
  hoja displays-night-shift '^Night Shift' && { popup_abierto displays-night-shift-schedule 1; cancelar_hoja; }
  popup_abierto displays-color-profile 1
  hoja displays-universal-control '^Universal Control' && cancelar_hoja
  fuera "D1 Scaled" "escoger Scaled cambia la resolución"; fuera "D1 dos pantallas" "hay una sola"
  # D2 Time Machine
  pref com.apple.prefs.backup; capsp "D-time-machine-$M"
  hoja time-machine-options '^Options' && cancelar_hoja
  hoja time-machine-select-disk '^Select (Backup )?Disk' && cancelar_hoja
  # D3 Network: cada servicio de la lista, Advanced con sus pestañas, Location abierto, el «+»
  pref com.apple.preference.network; capsp "D-network-$M"; filas network-servicio
  $H ui "$SP" fila 1 >/dev/null 2>>"$LOG"; sleep 1
  hoja network-advanced '^Advanced' && { pestanas network-advanced; cancelar_hoja; }
  popup_abierto network-location 1
  hoja network-mas '^Add$|^\+$|add service' && cancelar_hoja
  # D4 Accessibility: cada página de la barra lateral y, en Display, sus pestañas
  pref com.apple.preference.universalaccess; filas accessibility
  pref com.apple.preference.universalaccess Seeing_Display; pestanas accessibility-display
  # D6 Date & Time ▸ Time Zone (el mapa solo, recortado)
  pref com.apple.preference.datetime TimeZonePref; capsp "D-time-zone-$M"
  m="$(marco "$SP" AXImage '' 1)"; [ -n "$m" ] && { set -- $m; cap_reg "D-time-zone-mapa-$M" "$1,$2,$3,$4"; }
  # D7 Dock & Menu Bar: cada fila (20 módulos)
  pref com.apple.preference.dock; filas dock-menu-bar
  # D8 Notifications & Focus ▸ Focus: Options y «+» (la plantilla); no se activa ningún Focus
  pref com.apple.preference.notifications Focus; capsp "D-focus-$M"
  hoja focus-options '^Options' && cancelar_hoja
  fuera "D8 Do Not Disturb activado" "activar un Focus cambia los avisos de José"
  # D9 Sound: las tres pestañas y el popup de Sound Effects abierto
  pref com.apple.preference.sound effects; pestanas sound; popup_abierto sound-efectos-salida 1
  # D10 Keyboard ▸ Modifier Keys: cada popup abierto, uno por uno
  pref com.apple.preference.keyboard keyboardTab
  if pulsar "$SP" AXButton '^Modifier Keys'; then sleep 1.5
    for i in 1 2 3 4 5 6; do popup_abierto keyboard-modifier-$i $i; done; cancelar_hoja; fi
  fuera "D10 Change Keyboard Type" "abre Keyboard Setup Assistant, que pide pulsar teclas"
  fuera "D10 dos fuentes y Dictation" "cambian ajustes de idioma"
  pref com.apple.preference.keyboard InputSources; capsp "D-input-sources-$M"
  # D11 Mission Control: los popups de abajo y Hot Corners con cada esquina abierta
  pref com.apple.preference.expose; for i in 1 2 3 4 5 6; do popup_abierto mission-control-popup$i $i; done
  if pulsar "$SP" AXButton '^Hot Corners'; then sleep 1.5; for i in 1 2 3 4; do popup_abierto hot-corner-$i $i; done; cancelar_hoja; fi
  # D12 Users & Groups, D13 Security & Privacy (pestañas y filas de Privacy), D14, D16, D17
  pref com.apple.preferences.users; capsp "D-users-$M"
  hoja users-login-options '^Login Options' || true
  pref com.apple.preference.security; pestanas security
  pref com.apple.preference.security Privacy; filas security-privacy
  pref com.apple.preferences.internetaccounts; capsp "D-internet-accounts-$M"
  pref com.apple.preferences.extensions; capsp "D-extensions-$M"; filas extensions
  # D15 Sharing: se selecciona cada servicio (sin marcar su casilla: nada se enciende)
  pref com.apple.preferences.sharing; filas sharing-servicio
  fuera "D15 encender servicios" "solo se selecciona la fila"
  pref com.apple.preferences.Bluetooth; capsp "D-bluetooth-$M"; hoja bluetooth-advanced '^Advanced' && cancelar_hoja
  fuera "D16 Connect" "conectar un aparato"
  pref com.apple.preference.printfax; capsp "D-printers-$M"
  osa -e "tell application \"$SP\" to quit"; sleep 1
}
if seccion D; then
  [ "$AJUSTES" = "System Preferences" ] || fuera D "esta versión usa System Settings: va por el bloque 08"
  if [ "$AJUSTES" = "System Preferences" ]; then
    ocultar; CAP="$FCC"
    for M in claro oscuro; do modo $([ $M = oscuro ] && echo true || echo false); osa -e "tell application \"$SP\" to quit"; sleep 1; ocultar_excepto "$SP"; fase_d; done
  fi
fi

# ======================================= el tamaño, para el tubo (<100 MB) o TRANSPORTE
# Regla de José: por scp solo pasa lo que mide menos de 100 MB. Un tar por sección;
# tubo.txt y transporte.txt dicen qué va por dónde.
( cd "$FC" && for d in capturas videos datos; do
    [ -d "$d" ] || continue
    tar -cf - "$d" | gzip -1 > "fase-c-$d.tar.gz"; shasum -a 256 "fase-c-$d.tar.gz" > "fase-c-$d.tar.gz.sha256"
  done
  : > tubo.txt; : > transporte.txt
  for t in fase-c-*.tar.gz; do
    if [ "$(stat -f %z "$t")" -lt 100000000 ]; then echo "$t" >> tubo.txt; else echo "$t" >> transporte.txt; fi
  done )
log "fase-c: lista; tubo: $(tr '\n' ' ' < "$FC/tubo.txt") · TRANSPORTE: $(tr '\n' ' ' < "$FC/transporte.txt")"
if [ -s "$FC/transporte.txt" ] && [ -d "$AQUI" ]; then
  while read -r t; do cp "$FC/$t" "$FC/$t.sha256" "$AQUI/" && ( cd "$AQUI" && shasum -a 256 -c "$t.sha256" >>"$LOG" 2>&1 ) && log "fase-c: $t en $AQUI (verificado)"; done < "$FC/transporte.txt"
fi
aviso "Fase C lista: $FC"
