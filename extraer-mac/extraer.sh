#!/bin/bash
# Saca de una Mac encendida (pensado para Monterey, sirve para otras) lo mismo
# que GobCorp-Mac sacó del iMac con macOS 27 (Golden Gate) y lo que paquete.sh
# toma del disco de Catalina: recursos del sistema, medidas y capturas.
# Lo lanza «Extraer Mac.applescript»; también corre solo desde Terminal:
#
#   bash extraer.sh [permisos] [recursos] [medidas] [capturas] [videos] [entregar]   (sin nada: todo)
#   BLOQUES="08 09" bash extraer.sh capturas      (solo esos bloques de la tanda: 01 03 05 06 07 08 09 12 13 14 15 16)
#   BLOQUES="16" bash extraer.sh capturas         solo lo que faltaba de la lista de Catalina (en oscuro; pide la clave para el candado)
#
#   «permisos» va primero y pide DE UNA VEZ todo lo que el guion va a usar
#   (Accessibility, Screen Recording y la automatización de cada app), espera
#   a que lo concedas y, si Screen Recording se acaba de conceder, reabre
#   Terminal solo y sigue con los demás pasos. Así no hay que volver a la Mac
#   cada vez que salga un diálogo.
#
# Escribe en ~/extraer-salida/macos<versión>-<fecha> (disco local) y al final
# «entregar» comprime todo en un .tar.gz con SHA-256 y copia ese único archivo a
# la carpeta del guion (la memoria TRANSPORTE). Nada va a ningún repo: es de Apple.
#
# Reglas:
#   - /System se lee, no se toca. Nada pide la clave de administrador (la
#     captura del diálogo de clave se cancela sola).
#   - Lo que cambia para las capturas (modo oscuro, lupa y posición del Dock,
#     íconos del escritorio, barra de estado del Finder) se anota antes y se
#     devuelve al terminar, aunque algo falle.
#   - Crea ~/Muestra con tres archivos de ejemplo si no existe y la quita al
#     final solo si la creó él.
#   - Un paso que falla se anota en la bitácora y se sigue con el próximo.
#
# Escrito para el bash 3.2 de macOS: sin arreglos asociativos ni mapfile.
set -u

AQUI="$(cd "$(dirname "$0")" && pwd)"
H="osascript -l JavaScript $AQUI/herramientas.js"
U="osascript $AQUI/ui.applescript"
NOMBRE="$(scutil --get ComputerName 2>/dev/null | tr -cd 'A-Za-z0-9-' )"
VERSION="$(sw_vers -productVersion)"
# Siempre en disco local: la memoria USB (FAT32) escribe a menos de 1 MB/s con
# archivos chicos y volvía lentísimas las capturas. Al final, «entregar» comprime
# y copia UN solo archivo a la carpeta del guion (la memoria).
SAL="${SALIDA:-$HOME/extraer-salida/macos$VERSION-$(date +%Y%m%d)}"
CAP="$SAL/capturas"; VID="$SAL/videos"; MED="$SAL/medidas"; REC="$SAL/recursos"; HER="$SAL/herramientas"
mkdir -p "$SAL"
mkdir -p "$HER"; cp "$AQUI/extraer.sh" "$AQUI/herramientas.js" "$AQUI/ui.applescript" "$HER/" 2>/dev/null
LOG="$HER/capturas.log"

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
aviso() { log "$*"; osascript -e "display notification \"$*\" with title \"Extraer Mac\"" 2>/dev/null; }
osa() { osascript "$@" 2>>"$LOG"; }

# Ancho, alto, escala, barra y Dock en puntos. En Catalina el puente de JXA se
# cae al leer un NSRect (NSGetSizeAndAlignment, 15-10-2026) y todo salía vacío:
# las capturas por región y las ventanas de Finder quedaron mal. Respaldo: lo
# mismo medido con AppleScript.
pantalla() {
  local r; r="$($H pantalla 2>>"$LOG")"
  set -- $r
  if [ -n "${1:-}" ] && [ -n "${4:-}" ]; then echo "$r"; return; fi
  local b w h esc barra dock
  b="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>>"$LOG" | tr -d ' ')"
  w="$(echo "$b" | cut -d, -f3)"; h="$(echo "$b" | cut -d, -f4)"
  barra="$(osascript -e 'tell application "System Events" to get item 2 of (get size of menu bar 1 of process "Finder")' 2>>"$LOG")"
  if [ "$(defaults read com.apple.dock autohide 2>/dev/null)" = 1 ]; then dock=0
  else dock="$(osascript -e 'tell application "System Events" to get item 2 of (get size of list 1 of process "Dock")' 2>>"$LOG")"; fi
  system_profiler SPDisplaysDataType 2>/dev/null | grep -q Retina && esc=2 || esc=1
  log "pantalla medida con AppleScript (JXA no la dio): $w x $h, escala $esc, barra $barra, dock $dock"
  echo "$w $h $esc ${barra:-22} ${dock:-0}"
}

PASOS="$*"; [ -z "$PASOS" ] && PASOS="permisos recursos medidas capturas videos entregar"
quiere() { case " $PASOS " in *" $1 "*) return 0 ;; esac; return 1; }

log "=== extraer.sh ($PASOS) en $NOMBRE, macOS $VERSION, usuario $USER, TERM_PROGRAM=${TERM_PROGRAM:-?} ==="


# ---------------------------------------------------------------- permisos
# Todo de una vez, al principio. Los permisos son de la app que corre esto
# (Terminal, o la que el usuario use); los diálogos los muestra el sistema.
permisos_estado() { $H permisos consultar "$VERSION" 2>>"$LOG"; }
permisos_ok() { case "$1" in *'"accesibilidad":true'*) case "$1" in *'"grabacion":true'*|*'"grabacion":"no medible'*) return 0;; esac;; esac; return 1; }
pedir_permisos() {
  local antes r i
  antes="$(permisos_estado)"; log "permisos antes: $antes"
  echo; echo "== Permisos =="; echo "Voy a pedir ahora TODOS los permisos que usa el guion. Acepta cada diálogo"
  echo "y marca ${TERM_PROGRAM:-la terminal} en System Preferences ▸ Security & Privacy ▸ Privacy,"
  echo "en Accessibility y en Screen Recording. Espero hasta 10 minutos."; echo
  # 1. Automatización: un evento inofensivo a cada app que el guion controla
  #    (System Events, Finder, System Preferences, TextEdit y Terminal).
  for app in "System Events" "Finder" "System Preferences" "TextEdit" "Terminal"; do
    if osascript -e "with timeout of 300 seconds" -e "tell application \"$app\" to get name" -e "end timeout" >/dev/null 2>>"$LOG"; then
      log "automatización de $app: ok"
    else
      log "automatización de $app: DENEGADA o sin respuesta"; echo "  ✗ Automatización de $app: denegada. Se concede en Privacy ▸ Automation."
    fi
  done
  osascript -e 'tell application "System Preferences" to quit' >/dev/null 2>&1
  osascript -e 'tell application "TextEdit" to quit saving no' >/dev/null 2>&1
  # 2. Accessibility y Screen Recording: un solo disparo de los dos diálogos.
  permisos_estado >/dev/null; r="$($H permisos pedir "$VERSION" 2>>"$LOG")"; log "permisos pedidos: $r"
  i=0
  until permisos_ok "$r"; do
    i=$((i+1)); [ $i -ge 120 ] && break
    [ $((i % 12)) = 1 ] && { echo "  esperando… ($r)"; aviso "Faltan permisos: Accessibility y/o Screen Recording"; }
    sleep 5; r="$(permisos_estado)"
  done
  log "permisos después: $r"
  if ! permisos_ok "$r"; then
    echo; echo "No se concedieron todos los permisos ($r). Concede lo que falte y vuelve a correr el guion."; return 1
  fi
  echo "  ✓ Accessibility y Screen Recording concedidos."
  # 3. Screen Recording recién concedido solo aplica cuando la app se reabre:
  #    si antes no estaba, reabro Terminal con los pasos que faltan y me voy.
  case "$antes" in
    *'"grabacion":false'*)
      if [ "${TERM_PROGRAM:-}" = "Apple_Terminal" ]; then
        local resto; resto="$(echo " $PASOS " | sed 's/ permisos / /; s/^ *//; s/ *$//')"
        echo; echo "Screen Recording se acaba de conceder: cierro Terminal y lo vuelvo a abrir con: $resto"
        log "relanzando Terminal con: $resto"
        nohup /bin/bash -c "sleep 4; open -a Terminal; sleep 4; osascript -e 'tell application \"Terminal\" to do script \"cd $(printf %q "$AQUI") && /bin/bash ./extraer.sh $resto\"'" >/dev/null 2>&1 &
        sleep 1; osascript -e 'tell application "Terminal" to quit' >/dev/null 2>&1
        sleep 10; exit 0
      else
        echo; echo "Screen Recording se acaba de conceder: cierra ${TERM_PROGRAM:-la terminal}, ábrela otra vez y corre el guion de nuevo (sin «permisos»)."
        exit 0
      fi;;
  esac
  return 0
}
if quiere permisos; then
  pedir_permisos || exit 2
fi

# ---------------------------------------------------------------- recursos
if quiere recursos; then
  aviso "Recursos del sistema (tarda: son varios GB)"
  mkdir -p "$REC/sistema" "$REC/car" "$REC/iconos/coretypes" "$REC/cursores" "$REC/sonidos/sistema" \
           "$REC/sonidos/interfaz" "$REC/fondos" "$REC/cuenta"
  # 1. Un .tar por carpeta, como mac-sistema.tar de paquete.sh. La memoria es
  #    FAT32 (nada pasa de 4 GB): un .tar de más de 3.9 GB sale partido en
  #    .tar.aa, .tar.ab… y se junta con cat.
  #    Sin fuentes: las SF no se sacan (orden de José).: íconos, Assets.car, PDF, PNG,
  #    TIFF, plists y strings; sin binarios ni idiomas que no son inglés.
  STAGE="$(mktemp -d /tmp/extraer-mac.XXXXXX)"
  for d in "System/Applications" "System/Library/CoreServices" "System/Library/PreferencePanes" \
           "System/Library/Extensions" "System/Library/Frameworks" "System/Library/PrivateFrameworks" \
           "Applications"; do
    [ -d "/$d" ] || { log "  no existe /$d"; continue; }
    nombre="$(echo "$d" | tr '/ ' '--')"
    ( cd / && find "$d" \( -name MacOS -o -name _CodeSignature \) -prune -o -type f \
        \( -name '*.icns' -o -name '*.car' -o -name '*.pdf' -o -name '*.png' -o -name '*.tif' -o -name '*.tiff' \
           -o -name '*.plist' -o -name '*.strings' -o -name '*.json' \) \
        -print 2>/dev/null | grep -v -E '/[^/]+\.lproj/' ; \
      find "$d" \( -path '*/en.lproj/*' -o -path '*/English.lproj/*' -o -path '*/Base.lproj/*' \) -type f -print 2>/dev/null ) \
      | sort -u > "$STAGE/$nombre.lista"
    ( cd / && tar -cf - -T "$STAGE/$nombre.lista" 2>>"$LOG" ) | split -b 3900m - "$REC/sistema/$nombre.tar."
    partes=$(ls "$REC/sistema/$nombre.tar."* 2>/dev/null | wc -l | tr -d ' ')
    [ "$partes" = 1 ] && mv "$REC/sistema/$nombre.tar.aa" "$REC/sistema/$nombre.tar"
    log "  $d: $(wc -l < "$STAGE/$nombre.lista" | tr -d ' ') archivos, $partes parte/s"
  done
  rm -rf "${STAGE:?}"
  # 2. Lo que GobCorp-Mac sacó suelto de macOS 27, con los mismos nombres de carpeta.
  cp /System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/*.car "$REC/car/" 2>>"$LOG"
  cp /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/*.icns \
     /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/Assets.car "$REC/iconos/coretypes/" 2>>"$LOG"
  mkdir -p "$REC/iconos/apps" "$REC/iconos/prefpanes" "$REC/iconos/coreservices"
  for app in /System/Applications/*.app /System/Applications/Utilities/*.app; do
    n="$(basename "$app" .app)"; mkdir -p "$REC/iconos/apps/$n"
    cp "$app/Contents/Resources/"*.icns "$app/Contents/Resources/Assets.car" "$REC/iconos/apps/$n/" 2>/dev/null
  done
  for pp in /System/Library/PreferencePanes/*.prefPane; do
    n="$(basename "$pp" .prefPane)"; mkdir -p "$REC/iconos/prefpanes/$n"
    cp "$pp/Contents/Resources/"*.icns "$pp/Contents/Resources/"*.tiff "$pp/Contents/Resources/Assets.car" "$REC/iconos/prefpanes/$n/" 2>/dev/null
  done
  for app in Finder Dock ControlCenter Spotlight Siri loginwindow NotificationCenter; do
    a="/System/Library/CoreServices/$app.app/Contents/Resources"; [ -d "$a" ] || continue
    mkdir -p "$REC/iconos/coreservices/$app"
    cp "$a/"*.icns "$a/"*.car "$a/"*.png "$a/"*.pdf "$REC/iconos/coreservices/$app/" 2>/dev/null
  done
  CUR=/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors
  [ -d "$CUR" ] && ( cd "$CUR" && tar -cf - . ) | ( cd "$REC/cursores" && tar -xf - 2>/dev/null )
  cp /System/Library/Sounds/*.aiff "$REC/sonidos/sistema/" 2>>"$LOG"
  SS=/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds
  [ -d "$SS" ] && ( cd "$SS" && tar -cf - . ) | ( cd "$REC/sonidos/interfaz" && tar -xf - 2>/dev/null )
  # 3. Fondos: los de fábrica de esta versión y el que tiene puesto el usuario.
  for f in "/System/Library/Desktop Pictures/"*.heic "/Library/Desktop Pictures/"*.heic; do
    [ -f "$f" ] && cp "$f" "$REC/fondos/" 2>>"$LOG"
  done
  ACTUAL="$(osa -e 'tell application "System Events" to get picture of current desktop')"
  if [ -n "$ACTUAL" ] && [ -f "$ACTUAL" ]; then cp "$ACTUAL" "$REC/fondos/fondo-del-usuario-$(basename "$ACTUAL")"; fi
  echo "fondo puesto: ${ACTUAL:-?}" > "$REC/fondos/fondo-del-usuario.txt"
  # 4. Lo de la pantalla de inicio: la foto de la cuenta y los botones.
  FOTO="$(dscl . -read "/Users/$USER" Picture 2>/dev/null | sed '1s/^Picture: *//; s/^ *//' | grep -v '^$' | head -1)"
  [ -n "$FOTO" ] && [ -f "$FOTO" ] && cp "$FOTO" "$REC/cuenta/"
  dscl . -read "/Users/$USER" JPEGPhoto 2>/dev/null | tail -n +2 | xxd -r -p > "$REC/cuenta/avatar.jpegphoto" 2>/dev/null
  [ -s "$REC/cuenta/avatar.jpegphoto" ] || rm -f "$REC/cuenta/avatar.jpegphoto"
  for n in Restart ShutDown Sleep; do
    cp "/System/Library/CoreServices/loginwindow.app/Contents/Resources/$n.tiff" "$REC/cuenta/" 2>/dev/null
  done
  aviso "Recursos listos: $(du -sh "$REC" | awk '{print $1}')"
fi

# ---------------------------------------------------------------- medidas
if quiere medidas; then
  aviso "Medidas"
  mkdir -p "$MED"
  $H medidas "$VERSION" > "$MED/medidas.json" 2>>"$LOG"
  read -r W HH ESC BARRA DOCK <<< "$(pantalla)"
  {
    echo "Equipo: $(sysctl -n hw.model) · macOS $VERSION ($(sw_vers -buildVersion))"
    system_profiler SPDisplaysDataType 2>/dev/null | grep -E 'Resolution|UI Looks like|Retina|Display Type|Main Display' | sed 's/^ *//'
    echo "Se ve como (resolución lógica): $W x $HH pt · escala ${ESC}x"
    echo "Barra de menú: $BARRA pt (frame − visibleFrame) · el Dock reserva $DOCK pt"
    echo "Apariencia: $(defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light)"
  } > "$MED/pantalla.txt"
  {
    echo "Ajustes de interfaz leídos con defaults el $(date '+%Y-%m-%d') (macOS $VERSION)"
    for k in AppleInterfaceStyle AppleAccentColor AppleHighlightColor AppleShowScrollBars AppleActionOnDoubleClick \
             NSTableViewDefaultSizeMode AppleMenuBarVisibleInFullscreen _HIHideMenuBar AppleReduceDesktopTinting; do
      printf '%-30s = %s\n' "$k" "$(defaults read -g "$k" 2>/dev/null || echo '(sin clave)')"
    done
    for k in tilesize largesize magnification orientation autohide minimize-to-application show-recents mineffect; do
      printf 'com.apple.dock %-15s = %s\n' "$k" "$(defaults read com.apple.dock "$k" 2>/dev/null || echo '(sin clave)')"
    done
    for k in ShowPathbar ShowStatusBar FXPreferredViewStyle CreateDesktop NewWindowTarget; do
      printf 'com.apple.finder %-13s = %s\n' "$k" "$(defaults read com.apple.finder "$k" 2>/dev/null || echo '(sin clave)')"
    done
    printf 'reduceTransparency            = %s\n' "$(defaults read com.apple.universalaccess reduceTransparency 2>/dev/null || echo '(sin clave)')"
    echo "Dock (apps fijas):"; defaults read com.apple.dock persistent-apps 2>/dev/null | grep '"file-label"' | sed 's/^ */  /'
    echo "Ítems de la barra (ControlCenter/SystemUIServer):"
    osa -e 'tell application "System Events" to get description of every menu bar item of menu bar 1 of process "ControlCenter"'
    osa -e 'tell application "System Events" to get description of every menu bar item of menu bar 1 of process "SystemUIServer"'
  } > "$MED/ajustes-ui.txt"
  aviso "Medidas listas"
fi

# ---------------------------------------------------------------- capturas
# Estado del usuario, para devolverlo al terminar.
leer_def() { defaults read "$1" "$2" 2>/dev/null || echo "__sin__"; }
poner_def() { # dominio clave valor-anotado tipo
  if [ "$3" = "__sin__" ]; then defaults delete "$1" "$2" 2>/dev/null; else defaults write "$1" "$2" "-$4" "$3"; fi
}
MODO_ORIG="$(osa -e 'tell application "System Events" to tell appearance preferences to get dark mode')"
MAG_ORIG="$(leer_def com.apple.dock magnification)"; LARGE_ORIG="$(leer_def com.apple.dock largesize)"
ORI_ORIG="$(leer_def com.apple.dock orientation)"; DESK_ORIG="$(leer_def com.apple.finder CreateDesktop)"
STATUS_ORIG="$(leer_def com.apple.finder ShowStatusBar)"; AUTOHIDE_ORIG="$(leer_def com.apple.dock autohide)"
SS_ORIG="$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo __sin__)"
MUESTRA_CREADA=false
devolver() {
  poner_def com.apple.dock magnification "$MAG_ORIG" bool; poner_def com.apple.dock largesize "$LARGE_ORIG" int
  poner_def com.apple.dock orientation "$ORI_ORIG" string; poner_def com.apple.finder CreateDesktop "$DESK_ORIG" bool
  poner_def com.apple.finder ShowStatusBar "$STATUS_ORIG" bool
  poner_def com.apple.dock autohide "$AUTOHIDE_ORIG" bool
  if [ "$SS_ORIG" = "__sin__" ]; then defaults -currentHost delete com.apple.screensaver idleTime 2>/dev/null
  else defaults -currentHost write com.apple.screensaver idleTime -int "$SS_ORIG"; fi
  killall Dock Finder 2>/dev/null
  [ -n "$MODO_ORIG" ] && osa -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $MODO_ORIG"
  if $MUESTRA_CREADA && [ -d "$HOME/Muestra" ]; then rm -rf "${HOME:?}/Muestra"; fi
  log "estado del usuario devuelto"
}

comprobar_permisos() {
  local ok=true
  if ! osascript -e 'tell application "System Events" to tell process "Finder" to get name of menu bar item 1 of menu bar 1' >/dev/null 2>&1; then
    log "SIN Accessibility: la terminal que corre esto no puede controlar la interfaz"; ok=false; fi
  local t; t="$(mktemp /tmp/extraer-prueba.XXXXXX).png"; screencapture -x "$t" 2>/dev/null
  if ! $H ventanas | awk -F'\t' '$2==0' | grep -q . ; then log "aviso: no hay ventanas normales abiertas para probar Screen Recording"; fi
  rm -f "$t"
  $ok || { aviso "Faltan permisos (Accessibility). Mira capturas.log"; return 1; }
  return 0
}

if quiere capturas || quiere videos; then
  comprobar_permisos || { log "=== abortado por permisos ==="; exit 2; }
  trap devolver EXIT
  # Que no arranque el protector de pantalla ni se apague la pantalla a mitad
  # de las capturas (en Catalina salió Flurry en el menú del escritorio,
  # 15-10-2026). caffeinate muere con este guion; el idleTime se devuelve.
  caffeinate -d -i -u -w $$ >/dev/null 2>&1 &
  defaults -currentHost write com.apple.screensaver idleTime -int 0
  read -r W HH ESC BARRA DOCK <<< "$(pantalla)"
  W=${W%.*}; HH=${HH%.*}; BARRA=${BARRA%.*}; DOCK=${DOCK%.*}
  log "pantalla ${W}x${HH} pt, escala $ESC, barra $BARRA, dock $DOCK"
  # Ventanas de Finder en proporción a la pantalla (en macOS 27, 2240×1260:
  # {560, 220, 1760, 920}).
  X1=$((W/4)); Y1=$((HH*17/100)); X2=$((W*79/100)); Y2=$((HH*73/100))
  # Carpeta de muestra (la misma que en macOS 27, para comparar al lado).
  if [ ! -e "$HOME/Muestra" ]; then
    MUESTRA_CREADA=true
    mkdir -p "$HOME/Muestra/Documentos" "$HOME/Muestra/Imágenes" "$HOME/Muestra/Proyectos"
    printf 'Notas de la reunión\n\n- Revisar presupuesto\n' > "$HOME/Muestra/Documentos/Notas.txt"
    printf 'Lista\n' > "$HOME/Muestra/Documentos/Lista.txt"
    F1="$(ls "/System/Library/Desktop Pictures/"*.heic 2>/dev/null | head -1)"
    [ -n "$F1" ] && sips -s format jpeg -Z 1600 "$F1" --out "$HOME/Muestra/Imágenes/Lago.jpg" >/dev/null 2>&1
    printf 'Proyecto\n' > "$HOME/Muestra/Proyectos/Leeme.txt"
  fi
fi

esc() { osa -e 'tell application "System Events" to key code 53'; sleep 0.4; }
modo() { osa -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; sleep 2; }
ocultar() { osa -e 'tell application "System Events" to set visible of (every process whose visible is true and name is not "Finder") to false'; }
ocultar_excepto() { osa -e "tell application \"System Events\" to set visible of (every process whose visible is true and name is not \"Finder\" and name is not \"$1\") to false"; }
raton_fuera() { $H raton mover $((W-10)) $((HH/2)); sleep 0.3; }
cap_full() { sleep 0.7; screencapture -x "$CAP/$1.png" && log "cap $1"; }
cap_reg()  { sleep 0.7; screencapture -x -R "$2" "$CAP/$1.png" && log "cap $1 ($2)"; }
cap_win()  { [ -n "$2" ] || { log "sin ventana para $1: va la pantalla entera"; cap_full "$1"; return; }; sleep 0.7; screencapture -x -o -l "$2" "$CAP/$1.png" && log "cap $1 (ventana $2)"; }
ventana_pref() { # la ventana principal de System Preferences: la que tiene título (el panel actual); si no, la más grande
  local id; id=$($H ventanas "System Preferences" | awk -F'\t' '$2==0 && $4!="" {print $1; exit}')
  [ -n "$id" ] && echo "$id" || ventana_de "System Preferences"; }
cerrar_paneles_pref() { # hojas (sheets) que abren algunas pestañas, p. ej. Accessibility ▸ Dwell con «Done»: bloquean la ventana hasta cerrarlas.
  # Cancel primero: en Catalina es la Mac de todos los días y un OK podría aplicar algo; OK solo si no hay otro botón.
  osa -e 'with timeout of 15 seconds' -e 'tell application "System Events" to tell process "System Preferences"' \
      -e 'repeat with w in windows' -e 'repeat with s in sheets of w' \
      -e 'repeat with b in {"Cancel", "Done", "Close", "OK"}' -e 'try' -e 'click (first button of s whose name is b)' -e 'exit repeat' -e 'end try' -e 'end repeat' \
      -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'end timeout' 2>/dev/null; sleep 0.6; }
ventana_de() { # dueño [regex del título] → id de la ventana normal MÁS GRANDE (no la primera: puede haber paneles sueltos)
  $H ventanas "$1" | awk -F'\t' -v t="${2:-}" '$2==0 && (t=="" || $4 ~ t) { split($5, b, " "); a=b[3]*b[4]; if (a>max) {max=a; id=$1} } END { if (id) print id }'; }
centro() { local p s; p=(${1//,/ }); s=(${2//,/ }); echo "$(( ${p[0]} + ${s[0]}/2 )) $(( ${p[1]} + ${s[1]}/2 ))"; }
finder_activar() { osa -e 'tell application "Finder" to activate'; sleep 0.5; }
cerrar_finder() { osa -e 'tell application "Finder" to close every Finder window'; }
abrir_menu() { osa -e "tell application \"System Events\" to tell process \"$1\" to click menu bar item \"$2\" of menu bar 1"; sleep 0.8; }
abrir_menu_apple() { osa -e "tell application \"System Events\" to tell process \"$1\" to click menu bar item 1 of menu bar 1"; sleep 0.8; }
hover_item() { # proceso menú ítem
  local p s; p=$(osa -e "tell application \"System Events\" to tell process \"$1\" to get position of menu item \"$3\" of menu 1 of menu bar item \"$2\" of menu bar 1")
  s=$(osa -e "tell application \"System Events\" to tell process \"$1\" to get size of menu item \"$3\" of menu 1 of menu bar item \"$2\" of menu bar 1")
  [ -n "$p" ] && $H raton mover $(centro "$p" "$s"); sleep 0.8; }
item_barra() { # ítem de la barra: "Control Center" o "Clock" (Monterey+) / "Notification Center" (Catalina)
  if osa -e "tell application \"System Events\" to tell process \"ControlCenter\" to click (first menu bar item of menu bar 1 whose description is \"$1\")" 2>/dev/null; then return 0; fi
  # Catalina y anteriores: no hay ControlCenter; el reloj y Notification Center viven en SystemUIServer
  local nom="$1"; [ "$nom" = "Clock" ] && nom="Notification Center"
  if osa -e "tell application \"System Events\" to tell process \"SystemUIServer\" to click (first menu bar item of menu bar 1 whose description contains \"$nom\")" 2>/dev/null; then return 0; fi
  # respaldo por coordenadas: la ventana del ítem en la barra (Control Center = BentoBox)
  nom="$1"; [ "$nom" = "Control Center" ] && nom=BentoBox
  local b; b=$($H ventanas "Control Center" | awk -F'\t' -v n="$nom" '$4==n {print $5; exit}')
  [ -n "$b" ] && { set -- $b; $H raton clic $(( $1 + $3/2 )) $(( $2 + $4/2 )); log "item_barra $nom por coordenadas"; return 0; }
  log "item_barra $1: no existe en esta versión"; return 1; }
ventana_finder() { # carpeta-dentro-de-Muestra («.» = Muestra) vista x1 y1 x2 y2
  local f="folder \"$1\" of folder \"Muestra\" of home"; [ "$1" = . ] && f='folder "Muestra" of home'
  osa -e 'tell application "Finder"' -e "set w to make new Finder window to ($f)" \
      -e "set current view of w to $2 view" -e "set bounds of w to {$3, $4, $5, $6}" -e 'end tell'; sleep 1.5; }
id_finder() { osa -e "tell application \"Finder\" to get id of Finder window ${1:-1}"; }

bloque() { case " ${BLOQUES:-todos} " in *" todos "*|*" $1 "*) return 0;; esac; return 1; }
tanda() { # claro | oscuro
  local M=$1 DM=false; [ "$M" = oscuro ] && DM=true
  log "=== tanda $M ==="; aviso "Capturas en modo $M"
  modo $DM; ocultar; finder_activar; cerrar_finder; raton_fuera

  # 01-02 Escritorio y barra de menú
  if bloque 01; then
  cap_full 01-escritorio-vacio-$M
  cap_reg 02-barra-menu-sola-$M 0,0,$W,$BARRA
  cap_reg 02-barra-menu-estado-reloj-$M $((W*69/100)),0,$((W*31/100)),$BARRA
  abrir_menu_apple Finder; cap_full 02-barra-menu-apple-abierto-$M; esc
  ventana_finder Documentos list $X1 $Y1 $X2 $Y2
  osa -e 'tell application "Finder" to select file "Notas.txt" of folder "Documentos" of folder "Muestra" of home'; raton_fuera
  abrir_menu Finder File; hover_item Finder File "Open With"; cap_full 02-barra-menu-file-submenu-$M; esc; esc
  for m in Edit View Go Window Help; do abrir_menu Finder $m; cap_full 02-barra-menu-$(echo $m | tr A-Z a-z)-abierto-$M; esc; done
  cerrar_finder; raton_fuera

  fi
  # 03-04 Control Center y Notification Center
  if bloque 03; then
  if item_barra "Control Center"; then sleep 1.5; cap_full 03-control-center-$M; esc; sleep 0.4; esc; fi; raton_fuera
  item_barra "Clock"; sleep 1.8; cap_full 04-notification-center-$M; item_barra "Clock"; sleep 0.8; esc; raton_fuera

  fi
  # 05 Dock
  if bloque 05; then
  # Si el Dock se oculta solo (la Mac de José en Catalina), se muestra para el
  # bloque y se vuelve a ocultar al final (y en devolver).
  if [ "$AUTOHIDE_ORIG" = 1 ]; then
    defaults write com.apple.dock autohide -bool false; killall Dock; sleep 2.5
    read -r _ _ _ _ DOCK <<< "$(pantalla)"; DOCK=${DOCK%.*}; log "Dock visible para el bloque 05: $DOCK pt"
  fi
  cap_reg 05-dock-normal-$M 0,$((HH-DOCK-10)),$W,$((DOCK+10))
  osa -e 'tell application "System Events" to tell process "Dock" to perform action "AXShowMenu" of UI element "Finder" of list 1'; sleep 0.9
  cap_full 05-dock-menu-contextual-$M; esc
  osa -e 'tell application "System Events" to tell process "Dock" to perform action "AXShowMenu" of UI element "Safari" of list 1'; sleep 0.9
  P=$(osa -e 'tell application "System Events" to tell process "Dock" to get position of menu item "Options" of menu 1 of UI element "Safari" of list 1')
  S=$(osa -e 'tell application "System Events" to tell process "Dock" to get size of menu item "Options" of menu 1 of UI element "Safari" of list 1')
  [ -n "$P" ] && { $H raton mover $(centro "$P" "$S"); sleep 0.9; cap_full 05-dock-menu-options-$M; }
  esc; esc; raton_fuera
  # la pila Downloads en Fan, Grid y List; al final vuelve a como estaba
  PILA_ORIG=""
  for v in Fan Grid List Automatic; do
    marca=$(osa -e 'tell application "System Events" to tell process "Dock"' -e 'perform action "AXShowMenu" of UI element "Downloads" of list 1' -e 'delay 0.6' \
      -e "set r to value of attribute \"AXMenuItemMarkChar\" of menu item \"$v\" of menu 1 of UI element \"Downloads\" of list 1" -e 'key code 53' -e 'return r' -e 'end tell')
    [ -n "$marca" ] && [ "$marca" != "missing value" ] && PILA_ORIG=$v
  done
  log "pila Downloads estaba en: ${PILA_ORIG:-?}"
  for v in Fan Grid List; do
    osa -e 'tell application "System Events" to tell process "Dock"' -e 'perform action "AXShowMenu" of UI element "Downloads" of list 1' -e 'delay 0.6' \
        -e "click menu item \"$v\" of menu 1 of UI element \"Downloads\" of list 1" -e 'end tell' || continue
    sleep 0.8; osa -e 'tell application "System Events" to tell process "Dock" to click UI element "Downloads" of list 1' && { sleep 1.2; cap_full 05-dock-pila-$(echo $v | tr A-Z a-z)-$M; esc; }
  done
  osa -e 'tell application "System Events" to tell process "Dock" to perform action "AXShowMenu" of UI element "Downloads" of list 1'; sleep 0.6
  cap_full 05-dock-pila-menu-contextual-$M; esc
  [ -n "$PILA_ORIG" ] && osa -e 'tell application "System Events" to tell process "Dock"' -e 'perform action "AXShowMenu" of UI element "Downloads" of list 1' -e 'delay 0.6' \
        -e "click menu item \"$PILA_ORIG\" of menu 1 of UI element \"Downloads\" of list 1" -e 'end tell'
  raton_fuera
  defaults write com.apple.dock magnification -bool true; defaults write com.apple.dock largesize -int 128; killall Dock; sleep 2.5
  P=$(osa -e 'tell application "System Events" to tell process "Dock" to get position of UI element "Safari" of list 1')
  S=$(osa -e 'tell application "System Events" to tell process "Dock" to get size of UI element "Safari" of list 1')
  [ -n "$P" ] && { $H raton mover $(centro "$P" "$S"); sleep 1; cap_reg 05-dock-lupa-$M 0,$((HH-DOCK-90)),$W,$((DOCK+90)); }
  raton_fuera
  poner_def com.apple.dock magnification "$MAG_ORIG" bool; poner_def com.apple.dock largesize "$LARGE_ORIG" int
  defaults write com.apple.dock orientation left; killall Dock; sleep 2.5; cap_full 05-dock-izquierda-$M
  poner_def com.apple.dock orientation "$ORI_ORIG" string
  poner_def com.apple.dock autohide "$AUTOHIDE_ORIG" bool; killall Dock; sleep 2.5

  fi
  # 06 Finder
  if bloque 06; then
  defaults write com.apple.finder ShowStatusBar -bool true
  ocultar; finder_activar; cerrar_finder
  ventana_finder . icon $X1 $Y1 $X2 $Y2; raton_fuera
  cap_win 06-finder-iconos-activa-$M "$(id_finder)"
  osa -e 'tell application "Finder" to set current view of Finder window 1 to list view'; sleep 1.2; cap_win 06-finder-lista-activa-$M "$(id_finder)"
  osa -e 'tell application "Finder" to set current view of Finder window 1 to column view' -e 'tell application "Finder" to select folder "Documentos" of folder "Muestra" of home'; sleep 1.5
  cap_win 06-finder-columnas-activa-$M "$(id_finder)"
  osa -e 'tell application "Finder" to set target of Finder window 1 to (folder "Imágenes" of folder "Muestra" of home)' \
      -e 'tell application "Finder" to set current view of Finder window 1 to flow view' \
      -e 'tell application "Finder" to select file "Lago.jpg" of folder "Imágenes" of folder "Muestra" of home'; sleep 2
  cap_win 06-finder-galeria-activa-$M "$(id_finder)"
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke " "'; sleep 2; raton_fuera
  cap_full 06-finder-quick-look-$M; osa -e 'tell application "System Events" to tell process "Finder" to keystroke " "'; sleep 1
  # rectángulo de selección dentro de la ventana (vista de íconos)
  osa -e 'tell application "Finder" to set target of Finder window 1 to (folder "Muestra" of home)' -e 'tell application "Finder" to set current view of Finder window 1 to icon view'; sleep 1.2
  # El arrastre empieza en un hueco vacío del área de archivos (abajo a la
  # derecha) y sube hacia los íconos. Antes empezaba a 30 pt del borde: caía en
  # la barra lateral y, al soltar fuera, sacaba favoritos del lateral (Monterey
  # perdió Documents y Downloads, 15-10-2026). Con una ventana chica no se arrastra.
  B=$(osa -e 'tell application "Finder" to get bounds of Finder window 1' | tr -d ' ')
  bx1=$(echo "$B" | cut -d, -f1); by1=$(echo "$B" | cut -d, -f2); bx2=$(echo "$B" | cut -d, -f3); by2=$(echo "$B" | cut -d, -f4)
  # Y solo en la ~/Muestra que creó el guion (tres carpetas arriba a la
  # izquierda): en una carpeta del usuario no se arrastra nada.
  if ! $MUESTRA_CREADA; then
    log "06-finder-seleccion-rectangulo-$M: ~/Muestra ya existía (es del usuario); no se arrastra"
  elif [ -n "$by2" ] && [ $((bx2-bx1)) -ge 500 ] && [ $((by2-by1)) -ge 300 ]; then
    $H raton arrastrar $((bx2-30)) $((by2-80)) $((bx1+(bx2-bx1)*45/100)) $((by1+70)) "$CAP/06-finder-seleccion-rectangulo-$M.png"; log "cap 06-finder-seleccion-rectangulo-$M"
  else log "06-finder-seleccion-rectangulo-$M: ventana de Finder sin tamaño ($B); no se arrastra"; fi
  sleep 0.5; raton_fuera
  # semáforos en reposo y con el ratón encima
  osa -e 'tell application "Finder" to set current view of Finder window 1 to list view'; sleep 1.2; raton_fuera
  cap_reg 11-semaforos-reposo-$M $X1,$Y1,240,70
  for dx in 200 140 90 60 40 30 26; do $H raton mover $((X1+dx)) $((Y1+21)); sleep 0.15; done; sleep 1
  cap_reg 11-semaforos-hover-$M $X1,$Y1,240,70; raton_fuera
  # activa e inactiva
  ventana_finder Proyectos list $((X1+W/7)) $((Y1+HH/6)) $((X2+W/7)) $((Y2+HH/6)); raton_fuera
  cap_reg 11-semaforos-inactiva-$M $X1,$Y1,240,70
  cap_win 06-finder-lista-inactiva-$M "$(id_finder 2)"
  osa -e 'tell application "Finder" to close Finder window 1'; sleep 0.8
  # menú contextual sobre un archivo
  osa -e 'tell application "Finder" to set target of Finder window 1 to (folder "Documentos" of folder "Muestra" of home)'; sleep 1.2
  P=$(osa -e 'tell application "System Events" to tell process "Finder" to get position of row 2 of outline 1 of scroll area 1 of splitter group 1 of window 1')
  [ -z "$P" ] && P=$(osa -e 'tell application "System Events" to tell process "Finder" to get position of row 2 of outline 1 of scroll area 1 of splitter group 1 of splitter group 1 of window 1')
  if [ -n "$P" ]; then p=(${P//,/ }); $H raton derecho $(( ${p[0]} + 60 )) $(( ${p[1]} + 10 )); sleep 1
    cap_full 06-finder-menu-contextual-archivo-$M; esc; fi
  raton_fuera
  # menú contextual de una app en /Applications (el que en Catalina trae «Add to Dock»… si lo trae)
  osa -e 'tell application "Finder" to set target of Finder window 1 to (path to applications folder)'; sleep 1.5
  P=$(osa -e 'tell application "System Events" to tell process "Finder" to get position of row 3 of outline 1 of scroll area 1 of splitter group 1 of window 1')
  [ -z "$P" ] && P=$(osa -e 'tell application "System Events" to tell process "Finder" to get position of row 3 of outline 1 of scroll area 1 of splitter group 1 of splitter group 1 of window 1')
  if [ -n "$P" ]; then p=(${P//,/ }); $H raton derecho $(( ${p[0]} + 60 )) $(( ${p[1]} + 10 )); sleep 1
    cap_full 06-finder-menu-contextual-app-$M; esc; fi
  raton_fuera
  # Get Info
  osa -e 'tell application "Finder" to open information window of file "Notas.txt" of folder "Documentos" of folder "Muestra" of home'; sleep 2; raton_fuera
  cap_win 06-finder-get-info-$M "$(ventana_de Finder Info)"
  osa -e 'tell application "Finder" to close every information window'; sleep 0.5
  # Preferences, sus cuatro pestañas
  finder_activar; osa -e 'tell application "System Events" to tell process "Finder" to keystroke "," using command down'; sleep 1.5; raton_fuera
  for tab in General Tags Sidebar Advanced; do
    osa -e "tell application \"System Events\" to tell process \"Finder\" to click button \"$tab\" of toolbar 1 of window 1"; sleep 1
    cap_win 06-finder-preferences-$(echo $tab | tr A-Z a-z)-$M "$(ventana_de Finder 'Preferences|Settings')"
  done
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "w" using command down'; sleep 0.5
  # Window ▸ (sin Move & Resize en Monterey: se captura el menú entero)
  cerrar_finder; poner_def com.apple.finder ShowStatusBar "$STATUS_ORIG" bool
  # escritorio con íconos, su menú contextual y el rectángulo sobre los íconos
  defaults write com.apple.finder CreateDesktop -bool true; killall Finder; sleep 3; cerrar_finder
  cap_full 01-escritorio-iconos-$M
  $H raton derecho $((W/5)) $((HH*55/100)); sleep 1; cap_full 06-finder-menu-contextual-escritorio-$M; esc; raton_fuera
  # En el escritorio, de un hueco del centro hacia abajo: nunca desde la columna
  # de íconos (un arrastre que empieza sobre un ícono lo mueve).
  # Antes se comprueba con Finder que ningún ícono del escritorio caiga en el
  # rectángulo (con 100 pt de margen): el escritorio de José tiene archivos de
  # verdad, y un arrastre que empieza sobre uno lo mueve o lo mete en una carpeta.
  RX1=$((W*40/100)); RY1=$((HH*30/100)); RX2=$((W*60/100)); RY2=$((HH*55/100))
  # osascript da las posiciones aplanadas: «x1, y1, x2, y2, …». Si Finder no
  # contesta, no se arrastra (vacío solo vale cuando el escritorio no tiene nada).
  if POS=$(osascript -e 'tell application "Finder" to get desktop position of every item of desktop' 2>>"$LOG"); then
    ICONOS_EN_MEDIO=$(echo "$POS" | tr -d ' {}' | tr ',' '\n' | grep . | paste -d' ' - - \
      | awk -v a=$((RX1-100)) -v b=$((RY1-100)) -v c=$((RX2+100)) -v d=$((RY2+100)) '$1+0>=a && $1+0<=c && $2+0>=b && $2+0<=d' | wc -l | tr -d ' ')
  else ICONOS_EN_MEDIO="?"; fi
  if [ "${ICONOS_EN_MEDIO:-1}" != 0 ]; then
    log "06-escritorio-seleccion-rectangulo-$M: hay $ICONOS_EN_MEDIO ícono(s) del escritorio en la zona (o no se pudo leer); no se arrastra"
  elif [ "${W:-0}" -ge 800 ]; then
    $H raton arrastrar $((W*40/100)) $((HH*30/100)) $((W*60/100)) $((HH*55/100)) "$CAP/06-escritorio-seleccion-rectangulo-$M.png"; log "cap 06-escritorio-seleccion-rectangulo-$M"
  else log "06-escritorio-seleccion-rectangulo-$M: pantalla sin medida; no se arrastra"; fi
  raton_fuera
  poner_def com.apple.finder CreateDesktop "$DESK_ORIG" bool; killall Finder; sleep 2.5

  fi
  # 07 Spotlight y Launchpad
  if bloque 07; then
  osa -e 'tell application "System Events" to keystroke space using command down'; sleep 1.5; cap_full 07-spotlight-vacio-$M
  osa -e 'tell application "System Events" to keystroke "Lago"'; sleep 2.5; cap_full 07-spotlight-resultados-$M; esc; sleep 0.4; esc; sleep 0.5
  open -a Launchpad; sleep 2; cap_full 07-launchpad-$M; esc; sleep 1

  fi
  # 08 System Preferences: la cuadrícula, cada panel y cada pestaña (anchor)
  if bloque 08; then
  osa -e 'tell application "System Preferences" to quit'; sleep 2; pkill -x "System Preferences" 2>/dev/null; sleep 1
  osa -e 'tell application "System Preferences" to activate' -e 'tell application "System Preferences" to set show all of it to true' ; sleep 2.5; raton_fuera
  # En Monterey «show all» no bastó (la captura salió con un panel): ⌘L es View ▸ Show All Preferences.
  osa -e 'tell application "System Events" to tell process "System Preferences" to keystroke "l" using command down'; sleep 2
  osa -e 'tell application "System Preferences" to activate'; sleep 1
  ocultar_excepto "System Preferences"
  cap_win 08-preferencias-todas-$M "$(ventana_pref)"
  osa -e 'tell application "System Preferences" to get id of every pane' | tr ',' '\n' | sed 's/^ *//' > "$SAL/.paneles"
  while read -r PANE; do
    [ -n "$PANE" ] || continue
    osa -e "tell application \"System Preferences\" to set current pane to pane id \"$PANE\"" || continue
    sleep 2.5; raton_fuera
    cerrar_paneles_pref; cap_win 08-pref-$PANE-$M "$(ventana_pref)"
    osa -e "tell application \"System Preferences\" to get name of every anchor of pane id \"$PANE\"" | tr ',' '\n' | sed 's/^ *//' > "$SAL/.anclas"
    while read -r A; do
      [ -n "$A" ] || continue
      osa -e "tell application \"System Preferences\" to reveal anchor \"$A\" of pane id \"$PANE\"" || continue
      sleep 1.5; raton_fuera
      cap_win "08-pref-$PANE--$(echo "$A" | tr -c 'A-Za-z0-9_\n-' '_')-$M" "$(ventana_pref)"; cerrar_paneles_pref
    done < "$SAL/.anclas"
  done < "$SAL/.paneles"
  rm -f "$SAL/.paneles" "$SAL/.anclas"
  # Notifications con una app escogida (la segunda de la lista)
  osa -e 'tell application "System Preferences" to set current pane to pane id "com.apple.preference.notifications"'; sleep 2
  osa -e 'tell application "System Events" to tell process "System Preferences" to select row 2 of table 1 of scroll area 1 of window 1' && { sleep 1; cap_win 08-pref-notifications-app-$M "$(ventana_pref)"; }
  # Desktop & Screen Saver ▸ Screen Saver Options…
  osa -e 'tell application "System Preferences" to reveal anchor "ScreenSaverPref" of pane id "com.apple.preference.desktopscreeneffect"'; sleep 2.5
  if osa -e 'tell application "System Events" to tell process "System Preferences" to click (first button of tab group 1 of window 1 whose name starts with "Screen Saver Options")'; then
    sleep 1.5; cap_win 08-pref-screen-saver-options-$M "$(ventana_de 'System Preferences')"
    osa -e 'tell application "System Events" to tell process "System Preferences" to click button "Cancel" of sheet 1 of window 1' \
      || osa -e 'tell application "System Events" to tell process "System Preferences" to click button "OK" of sheet 1 of window 1'; sleep 1
  fi
  # Keyboard ▸ Shortcuts: las categorías de la izquierda una por una
  osa -e 'tell application "System Preferences" to reveal anchor "shortcutsTab" of pane id "com.apple.preference.keyboard"'; sleep 2
  TABLA=""
  for t in "table 1 of scroll area 1 of splitter group 1 of group 1 of tab group 1 of window 1" \
           "table 1 of scroll area 1 of splitter group 1 of tab group 1 of window 1" \
           "table 1 of scroll area 1 of tab group 1 of window 1"; do
    N=$(osa -e "tell application \"System Events\" to tell process \"System Preferences\" to count rows of $t") && { TABLA="$t"; break; }
  done
  i=1; while [ -n "$TABLA" ] && [ "$i" -le "${N:-0}" ]; do
    osa -e "tell application \"System Events\" to tell process \"System Preferences\" to select row $i of $TABLA"; sleep 1
    cap_win 08-pref-keyboard-shortcuts-$i-$M "$(ventana_pref)"; i=$((i+1))
  done
  [ -z "$TABLA" ] && log "no encontré la lista de categorías de Shortcuts"
  # Keyboard ▸ Modifier Keys…, con el menú de una tecla abierto
  osa -e 'tell application "System Preferences" to reveal anchor "keyboardTab" of pane id "com.apple.preference.keyboard"'; sleep 2
  if osa -e 'tell application "System Events" to tell process "System Preferences" to click (first button of tab group 1 of window 1 whose name starts with "Modifier Keys")'; then
    sleep 1.5; raton_fuera; cap_win 08-pref-keyboard-modifier-keys-$M "$(ventana_de 'System Preferences')"
    osa -e 'tell application "System Events" to tell process "System Preferences" to click pop up button 1 of sheet 1 of window 1'; sleep 1
    cap_full 08-pref-keyboard-modifier-keys-menu-$M; esc; sleep 0.5
    osa -e 'tell application "System Events" to tell process "System Preferences" to click button "Cancel" of sheet 1 of window 1'; sleep 1
  fi
  # Mission Control ▸ Hot Corners…, con el menú de una esquina abierto
  osa -e 'tell application "System Preferences" to set current pane to pane id "com.apple.preference.expose"'; sleep 2
  if osa -e 'tell application "System Events" to tell process "System Preferences" to click (first button of window 1 whose name starts with "Hot Corners")'; then
    sleep 1.5; raton_fuera; cap_win 08-pref-hot-corners-$M "$(ventana_de 'System Preferences')"
    osa -e 'tell application "System Events" to tell process "System Preferences" to click pop up button 1 of group 1 of sheet 1 of window 1' \
      || osa -e 'tell application "System Events" to tell process "System Preferences" to click pop up button 1 of sheet 1 of window 1'
    sleep 1; cap_full 08-pref-hot-corners-menu-$M; esc; sleep 0.5
    osa -e 'tell application "System Events" to tell process "System Preferences" to click button "Cancel" of sheet 1 of window 1'; sleep 1
  fi
  osa -e 'tell application "System Preferences" to quit'; sleep 1

  fi
  # 09 Diálogos
  if bloque 09; then
  osascript -e 'display alert "Do you want to replace the existing file?" message "A file with the same name already exists in this location. Replacing it will overwrite its current contents." buttons {"Cancel","Replace"} default button 2' >/dev/null 2>&1 & P1=$!
  sleep 2.5; raton_fuera; cap_win 09-alerta-2-botones-$M "$(ventana_de osascript)"; kill $P1 2>/dev/null; sleep 1
  osascript -e 'display alert "Do you want to save the changes made to the document “Notas”?" message "Your changes will be lost if you don’t save them." buttons {"Don’t Save","Cancel","Save"} default button 3' >/dev/null 2>&1 & P2=$!
  sleep 2.5; raton_fuera; cap_win 09-alerta-3-botones-$M "$(ventana_de osascript)"; kill $P2 2>/dev/null; sleep 1
  osa -e 'tell application "TextEdit"' -e 'activate' -e 'make new document with properties {text:"Notas de la reunión" & linefeed & linefeed & "- Revisar presupuesto"}' \
      -e "set bounds of window 1 to {$((X1-40)), $((Y1-40)), $((X2-40)), $((Y2+80))}" -e 'end tell'; sleep 2; raton_fuera; ocultar_excepto TextEdit
  osa -e 'tell application "System Events" to tell process "TextEdit" to keystroke "s" using command down'; sleep 2.5; raton_fuera
  cap_win 09-dialogo-save-$M "$(ventana_de TextEdit)"
  osa -e 'tell application "System Events" to tell process "TextEdit" to get {description, name} of every button of sheet 1 of window 1' >> "$LOG"
  if osa -e 'tell application "System Events" to tell process "TextEdit" to click (first button of sheet 1 of window 1 whose description contains "isclos" or description contains "xpand")'; then
    sleep 1.5; raton_fuera; cap_win 09-dialogo-save-expandido-$M "$(ventana_de TextEdit)"
  fi
  esc; sleep 1.2
  osa -e 'tell application "System Events" to tell process "TextEdit" to keystroke "w" using command down'; sleep 1.8; raton_fuera
  cap_win 09-hoja-guardar-cambios-$M "$(ventana_de TextEdit)"
  osa -e 'tell application "System Events" to tell process "TextEdit" to click button "Delete" of sheet 1 of window 1' || \
    osa -e 'tell application "System Events" to tell process "TextEdit" to click button 3 of sheet 1 of window 1'; sleep 1.2
  osa -e 'tell application "System Events" to tell process "TextEdit" to keystroke "o" using command down'; sleep 2.5; raton_fuera
  cap_win 09-dialogo-open-$M "$(ventana_de TextEdit)"; esc; sleep 1; osa -e 'tell application "TextEdit" to quit saving no'; sleep 1.5
  osascript -e 'do shell script "true" with administrator privileges' >/dev/null 2>&1 & P3=$!
  sleep 3; raton_fuera; cap_win 09-dialogo-contrasena-admin-$M "$(ventana_de SecurityAgent)"
  osa -e 'tell application "System Events" to tell process "SecurityAgent" to click button "Cancel" of window 1'; kill $P3 2>/dev/null; sleep 1.5

  fi
  # 12 About This Mac, sus pestañas (los nombres cambian entre versiones: se
  if bloque 12; then
  #    prueban todos los conocidos y se anota cuáles había)
  abrir_menu_apple Finder; osa -e 'tell application "System Events" to tell process "Finder" to click menu item 1 of menu 1 of menu bar item 1 of menu bar 1'; sleep 2.5; raton_fuera
  cap_win 12-about-this-mac-overview-$M "$(ventana_de 'System Information')"
  osa -e 'tell application "System Events" to tell process "System Information" to get name of every UI element of toolbar 1 of window 1' >> "$LOG"
  for tab in Displays Storage Memory Support Service Resources; do
    osa -e "tell application \"System Events\" to tell process \"System Information\" to click radio button \"$tab\" of radio group 1 of toolbar 1 of window 1" \
      || osa -e "tell application \"System Events\" to tell process \"System Information\" to click button \"$tab\" of toolbar 1 of window 1" || continue
    sleep 2; cap_win 12-about-this-mac-$(echo $tab | tr A-Z a-z)-$M "$(ventana_de 'System Information')"
  done
  pkill -x "System Information" 2>/dev/null; sleep 1

  fi
  # 15 Force Quit (⌥⌘Esc) y la barra de ⇧⌘5
  if bloque 15; then
  finder_activar; osa -e 'tell application "System Events" to key code 53 using {command down, option down}'; sleep 2; raton_fuera
  cap_win 15-force-quit-$M "$(ventana_de loginwindow)"; [ -f "$CAP/15-force-quit-$M.png" ] || cap_full 15-force-quit-$M
  osa -e 'tell application "System Events" to key code 53'; sleep 0.5
  osa -e 'tell application "System Events" to keystroke "w" using command down'; sleep 0.5
  osa -e 'tell application "System Events" to keystroke "5" using {shift down, command down}'; sleep 2; raton_fuera
  cap_full 15-captura-pantalla-barra-$M; esc; sleep 1

  fi
  # 13 ⌘Tab y Mission Control
  if bloque 13; then
  osa -e 'tell application "System Events"' -e 'key down command' -e 'keystroke tab' -e 'delay 1.2' \
      -e "do shell script \"screencapture -x '$CAP/13-cmd-tab-$M.png'\"" -e 'key code 53' -e 'key up command' -e 'end tell'; log "cap 13-cmd-tab-$M"; sleep 0.5
  open -a "Mission Control"; sleep 3.5   # con 2 s salió a mitad de la animación (Monterey)
  screencapture -x "$CAP/13-mission-control-$M.png"; log "cap 13-mission-control-$M"; esc; sleep 1

  fi
  # 14 Migration Assistant: solo la primera pantalla. Lo demás va a mano al
  if bloque 14; then
  #    final: Continue pide la clave y cierra todas las apps, Terminal incluido.
  open -a "Migration Assistant"; sleep 3; raton_fuera
  cap_win 14-migration-assistant-inicio-$M "$(ventana_de 'Migration Assistant')"
  pkill -x "Migration Assistant" 2>/dev/null; sleep 1
  fi
  # 16 Lo que faltaba de la lista de Catalina (lista-capturas-catalina-20261015):
  # menús de estado, Recent Items, Go to Folder, búsqueda, pestañas, menús del
  # fondo, Dock (separador y Trash), About This Mac completo, Input Sources +,
  # los desplegables de cada panel, Privacy entera, Network (Wi-Fi, Proxies,
  # Edit Locations), Displays Scaled, Desktop Colors/Folders, Screen Time,
  # Family Sharing, Launchpad en edición y lo que pide el candado. Solo en
  # oscuro (la lista es en oscuro). Nada se aplica: cada hoja se cierra con
  # Cancel o Done, y lo que se marca para la captura se devuelve.
  if bloque 16 && [ "$M" = oscuro ]; then
  aviso "Bloque 16: lo que faltaba de la lista"
  pref_panel() { osa -e 'tell application "System Preferences" to activate' -e "tell application \"System Preferences\" to set current pane to pane id \"$1\""; sleep 2.5; raton_fuera; }
  pref_ancla() { osa -e 'tell application "System Preferences" to activate' -e "tell application \"System Preferences\" to reveal anchor \"$2\" of pane id \"$1\""; sleep 2.5; raton_fuera; }
  ui_log() { local r; r="$($U "$@" 2>>"$LOG")"; [ "$r" = ok ] || log "16: ui $* → ${r:-sin respuesta}"; [ "$r" = ok ]; }
  cap_pref() { cap_win "16-$1-$M" "$(ventana_pref)"; }
  # Todos los desplegables de la ventana, uno por uno, abiertos.
  desplegables() { # prefijo
    local n i; n="$($U popups "System Preferences" 2>>"$LOG")"; log "16: $1 tiene ${n:-0} desplegables"
    i=1; while [ "$i" -le "${n:-0}" ]; do
      if ui_log popup "System Preferences" "$i"; then sleep 1; cap_full "16-$1-desplegable-$i-$M"; esc; sleep 0.4; fi
      i=$((i+1))
    done; }
  # El candado: lo abre el guion y la clave la teclea José (aviso y espera hasta 3 minutos).
  desbloquear() { # panel
    [ "$($U candado "System Preferences" 2>>"$LOG")" = abierto ] && return 0
    ui_log clic "System Preferences" "Click the lock" || return 1
    aviso "Escribe tu clave en System Preferences ($1): el guion espera hasta 3 minutos"
    local i=0; while [ $i -lt 90 ]; do
      [ "$($U candado "System Preferences" 2>>"$LOG")" = abierto ] && { log "16: $1 desbloqueado"; sleep 1; return 0; }
      sleep 2; i=$((i+1))
    done
    log "16: $1 sigue con candado: se salta lo que lo necesita"; esc; return 1; }
  bloquear() { [ "$($U candado "System Preferences" 2>>"$LOG")" = abierto ] && ui_log clic "System Preferences" "Click the lock"; sleep 1; }

  # --- Barra de menús: los menús de estado de SystemUIServer (sin Siri, que se abre sola)
  # (una descripción puede traer comas, «Wi-Fi, Wi-Fi is not enabled.»: se pide una por una)
  N=$(osa -e 'tell application "System Events" to count menu bar items of menu bar 1 of process "SystemUIServer"')
  i=1; while [ "$i" -le "${N:-0}" ]; do
    d=$(osa -e "tell application \"System Events\" to get description of menu bar item $i of menu bar 1 of process \"SystemUIServer\"")
    case "$d" in ""|Siri*) i=$((i+1)); continue ;; esac
    if osa -e "tell application \"System Events\" to tell process \"SystemUIServer\" to click menu bar item $i of menu bar 1"; then
      sleep 1.2; cap_full "16-barra-estado-$i-$(echo "$d" | cut -d, -f1 | tr -c 'A-Za-z0-9\n' '-' | tr A-Z a-z | sed 's/-*$//')-$M"; esc; sleep 0.5
    fi
    i=$((i+1))
  done; raton_fuera

  # --- Menú Apple ▸ Recent Items, con su submenú
  finder_activar; abrir_menu_apple Finder
  P=$(osa -e 'tell application "System Events" to tell process "Finder" to get position of menu item "Recent Items" of menu 1 of menu bar item 1 of menu bar 1')
  S=$(osa -e 'tell application "System Events" to tell process "Finder" to get size of menu item "Recent Items" of menu 1 of menu bar item 1 of menu bar 1')
  [ -n "$P" ] && { $H raton mover $(centro "$P" "$S"); sleep 1.2; cap_full "16-menu-apple-recent-items-$M"; }
  esc; esc; raton_fuera

  # --- Finder: Go to Folder, búsqueda, dos pestañas y el menú del fondo de la ventana
  ocultar; finder_activar; cerrar_finder
  ventana_finder . icon $X1 $Y1 $X2 $Y2; raton_fuera
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "g" using {shift down, command down}'; sleep 1.5
  cap_win "16-finder-go-to-folder-$M" "$(id_finder)"; esc; sleep 0.6
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "t" using command down'; sleep 1.5
  cap_win "16-finder-dos-pestanas-$M" "$(id_finder)"
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "w" using command down'; sleep 1
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "f" using command down'; sleep 1.2
  osa -e 'tell application "System Events" to tell process "Finder" to keystroke "Notas"'; sleep 2.5
  cap_win "16-finder-busqueda-$M" "$(id_finder)"; esc; sleep 0.6
  osa -e 'tell application "Finder" to set target of Finder window 1 to (folder "Muestra" of home)'; sleep 1
  B=$(osa -e 'tell application "Finder" to get bounds of Finder window 1' | tr -d ' ')
  bx2=$(echo "$B" | cut -d, -f3); by2=$(echo "$B" | cut -d, -f4)
  if $MUESTRA_CREADA && [ -n "$by2" ]; then
    $H raton derecho $((bx2-40)) $((by2-90)); sleep 1; cap_full "16-finder-menu-fondo-ventana-$M"; esc
  fi
  cerrar_finder; raton_fuera

  # --- Dock: el menú del separador y el de la Trash (con el Dock visible)
  if [ "$AUTOHIDE_ORIG" = 1 ]; then defaults write com.apple.dock autohide -bool false; killall Dock; sleep 2.5; fi
  P=$(osa -e 'tell application "System Events" to tell process "Dock" to get position of (first UI element of list 1 whose subrole is "AXSeparatorDockItem")')
  S=$(osa -e 'tell application "System Events" to tell process "Dock" to get size of (first UI element of list 1 whose subrole is "AXSeparatorDockItem")')
  [ -n "$P" ] && { $H raton derecho $(centro "$P" "$S"); sleep 1; cap_full "16-dock-menu-separador-$M"; esc; }
  osa -e 'tell application "System Events" to tell process "Dock" to perform action "AXShowMenu" of UI element "Trash" of list 1' && { sleep 1; cap_full "16-dock-menu-trash-$M"; esc; }
  poner_def com.apple.dock autohide "$AUTOHIDE_ORIG" bool; killall Dock; sleep 2.5; raton_fuera

  # --- About This Mac: la versión con Build y con número de serie, y cada pestaña
  abrir_menu_apple Finder; osa -e 'tell application "System Events" to tell process "Finder" to click menu item 1 of menu 1 of menu bar item 1 of menu bar 1'; sleep 2.5; raton_fuera
  for k in 1 2; do ui_log clic-valor "System Information" "Version" && { sleep 1; cap_win "16-about-overview-version-$k-$M" "$(ventana_de 'System Information')"; }; done
  ui_log clic-valor "System Information" "Version"
  for tab in Displays Storage Support Service; do
    ui_log clic "System Information" "$tab" && { sleep 2; cap_win "16-about-$(echo $tab | tr A-Z a-z)-$M" "$(ventana_de 'System Information')"; }
    if [ "$tab" = Storage ] && ui_log clic "System Information" "Manage"; then
      sleep 3; cap_full "16-about-storage-manage-$M"; pkill -x "Storage Management" 2>/dev/null; sleep 1
    fi
  done
  pkill -x "System Information" 2>/dev/null; sleep 1

  # --- System Preferences
  osa -e 'tell application "System Preferences" to quit'; sleep 2
  osa -e 'tell application "System Preferences" to activate'; sleep 2; ocultar_excepto "System Preferences"
  # Keyboard ▸ Input Sources con la hoja de +
  pref_ancla com.apple.preference.keyboard InputSources
  { ui_log clic "System Preferences" "add" || ui_log clic "System Preferences" "Add" || ui_log clic "System Preferences" "+"; } && {
    sleep 1.5; cap_pref teclado-input-sources-agregar; ui_log clic "System Preferences" "Cancel"; sleep 1; }
  # Los desplegables de General, Dock, Mission Control, Language & Region y Hot Corners
  pref_panel com.apple.preference.general; desplegables general
  pref_panel com.apple.preference.dock; desplegables dock
  pref_panel com.apple.preference.expose; desplegables mission-control
  pref_panel com.apple.Localization; desplegables idioma-region
  pref_panel com.apple.preference.expose
  if ui_log clic "System Preferences" "Hot Corners"; then sleep 1.5; desplegables esquinas; ui_log clic "System Preferences" "Cancel" || ui_log clic "System Preferences" "OK"; sleep 1; fi
  # Security & Privacy ▸ Privacy: cada categoría
  pref_ancla com.apple.preference.security Privacy
  for c in "Location Services" "Contacts" "Calendars" "Reminders" "Photos" "Camera" "Microphone" "Speech Recognition" \
           "Accessibility" "Input Monitoring" "Full Disk Access" "Files and Folders" "Screen Recording" "Automation" \
           "Advertising" "Analytics & Improvements" "Developer Tools"; do
    ui_log fila "System Preferences" "$c" && { sleep 1.2; cap_pref "privacy-$(echo "$c" | tr -c 'A-Za-z0-9\n' '-' | tr A-Z a-z | sed 's/-*$//')"; }
  done
  # Network: Wi-Fi escogido, Advanced ▸ Proxies (cada protocolo, sin marcar nada), Edit Locations
  pref_panel com.apple.preference.network
  ui_log fila "System Preferences" "Wi-Fi" && { sleep 1.5; cap_pref network-wi-fi; }
  if ui_log clic "System Preferences" "Advanced"; then
    sleep 2; ui_log clic "System Preferences" "Proxies" && sleep 1.2
    for pr in "Web Proxy (HTTP)" "Secure Web Proxy (HTTPS)" "SOCKS Proxy" "FTP Proxy" "Automatic Proxy Configuration"; do
      ui_log fila "System Preferences" "$pr" && { sleep 1; cap_pref "network-proxies-$(echo "$pr" | tr -c 'A-Za-z0-9\n' '-' | tr A-Z a-z | sed 's/-*$//')"; }
    done
    ui_log clic "System Preferences" "Cancel"; sleep 1.5
  fi
  # Displays ▸ Scaled (y de vuelta a Default for display)
  pref_ancla com.apple.preference.displays displaysDisplayTab
  if ui_log clic "System Preferences" "Scaled"; then sleep 1.5; cap_pref displays-scaled; ui_log clic "System Preferences" "Default for display"; sleep 1.5; fi
  # Desktop & Screen Saver ▸ Desktop: las categorías Colors y Folders
  pref_ancla com.apple.preference.desktopscreeneffect DesktopPref
  for c in Colors Folders; do ui_log fila "System Preferences" "$c" && { sleep 1.5; cap_pref "desktop-$(echo $c | tr A-Z a-z)"; }; done
  # Screen Time ▸ Content & Privacy y sus pestañas
  pref_panel com.apple.preference.screentime
  if ui_log fila "System Preferences" "Content & Privacy"; then
    sleep 1.5; cap_pref screen-time-content-privacy
    for t in Content Stores Apps Other; do ui_log clic "System Preferences" "$t" && { sleep 1; cap_pref "screen-time-content-privacy-$(echo $t | tr A-Z a-z)"; }; done
  fi
  # Family Sharing: cada categoría de la izquierda
  pref_panel com.apple.preferences.FamilySharingPrefPane
  $U filas "System Preferences" 2>>"$LOG" > "$SAL/.familia"
  while read -r c; do [ -n "$c" ] || continue
    ui_log fila "System Preferences" "$c" && { sleep 1.5; cap_pref "family-sharing-$(echo "$c" | tr -c 'A-Za-z0-9\n' '-' | tr A-Z a-z | sed 's/-*$//')"; }
  done < "$SAL/.familia"; rm -f "$SAL/.familia"
  # Con el candado (la clave la teclea José). Cada hoja se cierra con Cancel o Done.
  pref_ancla com.apple.preference.security General
  if desbloquear security; then
    ui_log clic "System Preferences" "Advanced" && { sleep 1.5; cap_pref security-advanced; ui_log clic "System Preferences" "Cancel" || ui_log clic "System Preferences" "OK"; sleep 1; }
    pref_ancla com.apple.preference.security Firewall
    ui_log clic "System Preferences" "Firewall Options" && { sleep 1.5; cap_pref security-firewall-options; ui_log clic "System Preferences" "Cancel"; sleep 1; }
    bloquear
  fi
  pref_panel com.apple.preferences.users
  if desbloquear users; then
    cap_pref users-desbloqueado
    ui_log fila "System Preferences" "Guest User" && { sleep 1.2; cap_pref users-guest-user; }
    ui_log fila "System Preferences" "Groups" && { sleep 1.2; cap_pref users-groups; }
    { ui_log clic "System Preferences" "add" || ui_log clic "System Preferences" "Add"; } && { sleep 1.5; cap_pref users-nuevo-usuario; ui_log clic "System Preferences" "Cancel"; sleep 1; }
    ui_log fila "System Preferences" "$(id -F 2>/dev/null)"; sleep 1
    ui_log clic "System Preferences" "Change Password" && { sleep 1.5; cap_pref users-change-password; ui_log clic "System Preferences" "Cancel"; sleep 1; }
    bloquear
  fi
  pref_panel com.apple.preference.datetime
  if desbloquear datetime; then cap_pref date-time-desbloqueado; bloquear; fi
  pref_panel com.apple.preference.network
  if desbloquear network; then
    ui_log popup-item "System Preferences" 1 "Edit Locations…" && { sleep 1.5; cap_pref network-edit-locations; ui_log clic "System Preferences" "Done" || ui_log clic "System Preferences" "Cancel"; sleep 1; }
    bloquear
  fi
  osa -e 'tell application "System Preferences" to quit'; sleep 1

  # --- Launchpad en modo de edición (con ⌥ apretado, sin tocar ningún ícono)
  open -a Launchpad; sleep 2
  osa -e 'tell application "System Events"' -e 'key down option' -e 'delay 1.5' \
      -e "do shell script \"screencapture -x '$CAP/16-launchpad-edicion-$M.png'\"" -e 'key up option' -e 'end tell' && log "cap 16-launchpad-edicion-$M"
  esc; sleep 1; raton_fuera
  fi
  log "=== fin tanda $M ==="
}

if quiere capturas; then
  mkdir -p "$CAP"
  tanda claro
  tanda oscuro
  aviso "Capturas listas: $(ls "$CAP" | wc -l | tr -d ' ')"
fi

# ---------------------------------------------------------------- videos
if quiere videos; then
  mkdir -p "$VID"; aviso "Videos (modo oscuro)"
  modo true; ocultar; finder_activar; cerrar_finder; raton_fuera
  grabar() { screencapture -V "$2" -x "$VID/$1.mov" & GP=$!; sleep 1.2; }
  defaults write com.apple.dock magnification -bool true; defaults write com.apple.dock largesize -int 128; killall Dock; sleep 3
  grabar 01-dock-lupa 8; x=$((W/5)); while [ $x -lt $((W*4/5)) ]; do $H raton mover $x $((HH-DOCK/2)); sleep 0.12; x=$((x+40)); done; raton_fuera; wait $GP; log "video 01"
  poner_def com.apple.dock magnification "$MAG_ORIG" bool; poner_def com.apple.dock largesize "$LARGE_ORIG" int; killall Dock; sleep 3
  grabar 02-control-center 7; item_barra "Control Center" || true; sleep 3.5; esc; raton_fuera; wait $GP; log "video 02"
  grabar 03-spotlight 8; osa -e 'tell application "System Events" to keystroke space using command down'; sleep 2; osa -e 'tell application "System Events" to keystroke "Lago"'; sleep 2.5; esc; sleep 0.3; esc; wait $GP; log "video 03"
  grabar 04-mission-control 7; open -a "Mission Control"; sleep 3; esc; sleep 1; wait $GP; log "video 04"
  ventana_finder . list $X1 $Y1 $X2 $Y2; raton_fuera
  grabar 05-minimizar-ventana 7; osa -e 'tell application "System Events" to tell process "Finder" to keystroke "m" using command down'; sleep 3; osa -e 'tell application "Finder" to set collapsed of Finder window 1 to false'; sleep 1.5; wait $GP; log "video 05"; cerrar_finder
  grabar 06-notification-center 7; item_barra "Clock"; sleep 3.5; item_barra "Clock"; raton_fuera; wait $GP; log "video 06"
  grabar 07-launchpad 6; open -a Launchpad; sleep 3; esc; wait $GP; log "video 07"
  aviso "Videos listos"
fi

# ---------------------------------------------------------------- entregar
# Un solo archivo: <salida>.tar.gz + .sha256, copiados a la carpeta del guion
# (la memoria) y verificados allá. Si pasa de 3.9 GB se parte (FAT32: 4 GB).
if quiere entregar; then
  aviso "Comprimiendo la salida"
  # El nombre sale de la carpeta de salida, con la Mac después de la versión:
  # macos10.15.8-20261015 → macos10.15.8-Macmini-20261015.tar.gz. Una corrida
  # parcial con SALIDA=…/macos10.15.8-parcial-20261015 no pisa el paquete de la
  # completa del mismo día (antes los dos se llamaban igual).
  PAQ="$(dirname "$SAL")/$(basename "$SAL" | sed "s/^macos$VERSION-/macos$VERSION-$NOMBRE-/").tar.gz"
  rm -f "$PAQ" "$PAQ.sha256" "$PAQ".parte-*
  if ( cd "$(dirname "$SAL")" && tar -cf - "$(basename "$SAL")" | gzip -1 > "$PAQ" ) && gzip -t "$PAQ" 2>>"$LOG"; then
    ( cd "$(dirname "$PAQ")" && shasum -a 256 "$(basename "$PAQ")" > "$PAQ.sha256" )
    log "paquete: $PAQ ($(du -h "$PAQ" | cut -f1)) · $(cat "$PAQ.sha256")"
    DEST="$AQUI"; TAM=$(stat -f %z "$PAQ")
    if [ "$TAM" -gt 4000000000 ]; then
      ( cd "$(dirname "$PAQ")" && split -b 3900m "$(basename "$PAQ")" "$(basename "$PAQ").parte-" ); LLEVAR="$PAQ".parte-*
      log "pasa de 4 GB: va partido; se junta con: cat $(basename "$PAQ").parte-* > $(basename "$PAQ")"
    else LLEVAR="$PAQ"; fi
    aviso "Copiando a $DEST (la memoria es lenta)"
    if cp $LLEVAR "$PAQ.sha256" "$DEST/" 2>>"$LOG"; then
      if [ "$TAM" -le 4000000000 ] && ( cd "$DEST" && shasum -a 256 -c "$(basename "$PAQ").sha256" >>"$LOG" 2>&1 ); then
        log "copia verificada en $DEST"; aviso "Entregado y verificado: $DEST/$(basename "$PAQ")"
        echo "LISTO: $DEST/$(basename "$PAQ")  (SHA-256 verificado). La carpeta local $SAL se queda por si hace falta algo suelto."
      elif [ "$TAM" -gt 4000000000 ]; then
        log "copia partida en $DEST (verifica tras juntar)"; echo "LISTO (partido): $DEST/$(basename "$PAQ").parte-*  → juntar con cat y comprobar con $(basename "$PAQ").sha256"
      else
        log "LA COPIA EN $DEST NO COINCIDE con el sha256"; echo "OJO: la copia en $DEST no pasó la verificación; el bueno es $PAQ"
      fi
    else
      log "no pude copiar a $DEST"; echo "No pude copiar a $DEST. El paquete bueno está en $PAQ"
    fi
  else
    log "falló la compresión"; echo "Falló la compresión; la salida sigue en $SAL"
  fi
fi

aviso "Terminado: $SAL"
log "=== fin ==="
