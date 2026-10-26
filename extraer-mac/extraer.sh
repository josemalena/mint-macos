#!/bin/bash
# Saca de una Mac encendida (pensado para Monterey, sirve para otras) lo mismo
# que GobCorp-Mac sacó del iMac con macOS 27 (Golden Gate) y lo que paquete.sh
# toma del disco de Catalina: recursos del sistema, medidas y capturas.
# Lo lanza «Extraer Mac.applescript»; también corre solo desde Terminal:
#
#   bash extraer.sh [permisos] [recursos] [medidas] [capturas] [videos] [entregar]   (sin nada: todo)
#   BLOQUES="08 09" bash extraer.sh capturas      (solo esos bloques de la tanda: 01 03 05 06 07 08 09 12 13 14 15 16 17)
#   BLOQUES="18" bash extraer.sh capturas         los nueve acentos: colores releídos y una ventanita por color (una vez, no por tanda)
#   BLOQUES="17" bash extraer.sh capturas         Stacks del escritorio (Mojave en adelante): pilas cerradas, una abierta y Group Stacks By
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
# Desde macOS 13 System Preferences es System Settings: otro proceso, otras ventanas y
# barra lateral en vez de rejilla. AJUSTES es el nombre de la app y de su proceso; con
# 12 o menos todo sigue por el camino de System Preferences.
MAYOR="${VERSION%%.*}"
if [ "$MAYOR" -ge 13 ] 2>/dev/null; then AJUSTES="System Settings"; else AJUSTES="System Preferences"; fi
# Siempre en disco local: la memoria USB (FAT32) escribe a menos de 1 MB/s con
# archivos chicos y volvía lentísimas las capturas. Al final, «entregar» comprime
# y copia UN solo archivo a la carpeta del guion (la memoria).
SAL="${SALIDA:-$HOME/extraer-salida/macos$VERSION-$(date +%Y%m%d)}"
CAP="$SAL/capturas"; VID="$SAL/videos"; MED="$SAL/medidas"; REC="$SAL/recursos"; HER="$SAL/herramientas"
mkdir -p "$SAL"
mkdir -p "$HER"; cp "$AQUI/extraer.sh" "$AQUI/herramientas.js" "$AQUI/ui.applescript" "$HER/" 2>/dev/null
LOG="$HER/capturas.log"

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }
# AJENA=1: la Mac de otra persona (por ssh, sin nadie que mire): sin avisos en su pantalla, sin su
# fondo ni su foto de cuenta, y nada que abra un diálogo de permisos.
aviso() { log "$*"; [ "${AJENA:-0}" = 1 ] && return 0; osascript -e "display notification \"$*\" with title \"Extraer Mac\"" 2>/dev/null; }
osa() { osascript "$@" 2>>"$LOG"; }

# Cierra una app por su nombre: quit por AppleScript (solo si está abierta, para
# no lanzarla) y, de respaldo, pkill -f por la ruta del .app. No pkill -x: macOS
# compara contra p_comm, que se corta a 16 caracteres, y con «System Information»
# (18) lo más probable es que nunca coincidiera (17-10-2026; SIN PROBAR en Mac hasta la próxima corrida).
cerrar_app() {
  osa -e "if application \"$1\" is running then tell application \"$1\" to quit"
  sleep 1
  pkill -f "/$1.app/" 2>/dev/null
  return 0
}

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
  if [ "$AJUSTES" = "System Settings" ]; then
    echo "y marca ${TERM_PROGRAM:-la terminal} en System Settings ▸ Privacy & Security, en Accessibility"
    echo "y en Screen Recording (desde Sequoia: «Screen & System Audio Recording»). Espero hasta 10 minutos."; echo
  else
    echo "y marca ${TERM_PROGRAM:-la terminal} en System Preferences ▸ Security & Privacy ▸ Privacy,"
    echo "en Accessibility y en Screen Recording. Espero hasta 10 minutos."; echo
  fi
  # 1. Automatización: un evento inofensivo a cada app que el guion controla
  #    (System Events, Finder, System Preferences o System Settings, TextEdit y Terminal).
  for app in "System Events" "Finder" "$AJUSTES" "TextEdit" "Terminal"; do
    if osascript -e "with timeout of 300 seconds" -e "tell application \"$app\" to get name" -e "end timeout" >/dev/null 2>>"$LOG"; then
      log "automatización de $app: ok"
    else
      log "automatización de $app: DENEGADA o sin respuesta"; echo "  ✗ Automatización de $app: denegada. Se concede en Privacy ▸ Automation."
    fi
  done
  osascript -e "tell application \"$AJUSTES\" to quit" >/dev/null 2>&1
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
  #    TIFF, plists, strings, loctable, xml, toolbar y nib; sin idiomas que no son inglés.
  #    Binarios solo los de los paneles de Settings y de System Settings (para SwiftUI).
  STAGE="$(mktemp -d /tmp/extraer-mac.XXXXXX)"
  for d in "System/Applications" "System/Library/CoreServices" "System/Library/PreferencePanes" \
           "System/Library/ExtensionKit" "System/Library/Extensions" "System/Library/Frameworks" \
           "System/Library/PrivateFrameworks" "Applications"; do
    [ -d "/$d" ] || { log "  no existe /$d"; continue; }
    nombre="$(echo "$d" | tr '/ ' '--')"
    ( cd / && find "$d" \( -name MacOS -o -name _CodeSignature \) -prune -o -type f \
        \( -name '*.icns' -o -name '*.car' -o -name '*.pdf' -o -name '*.png' -o -name '*.tif' -o -name '*.tiff' \
           -o -name '*.plist' -o -name '*.strings' -o -name '*.json' -o -name '*.xml' -o -name '*.loctable' \
           -o -name '*.toolbar' -o -name '*.nib' -o -path '*.nib/*' \) \
        -print 2>/dev/null | grep -v -E '/[^/]+\.lproj/' ; \
      find "$d" \( -path '*/en.lproj/*' -o -path '*/English.lproj/*' -o -path '*/Base.lproj/*' \) -type f -print 2>/dev/null ; \
      # Los ejecutables de los paneles de Settings y de System Settings: las vistas SwiftUI salen
      # de su metadata de tipos (herramientas/visor-nib/swiftui.py; excepción de José, solo interfaz).
      case "$d" in
        System/Library/ExtensionKit|System/Library/PreferencePanes) find "$d" -path '*/Contents/MacOS/*' -type f -print 2>/dev/null ;;
        System/Applications) find "$d/System Settings.app/Contents/MacOS" -type f -print 2>/dev/null ;;
      esac ) \
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
  # Inventario de Apple de cada .car copiado (assetutil -I), para validar lo que saca car.py en
  # la Mac mini: lo que car.py no abra se compara contra esto, no se adivina.
  if command -v assetutil >/dev/null 2>&1; then
    mkdir -p "$REC/car-inventario"; ninv=0
    while IFS= read -r car; do
      rel="${car#"$REC"/}"; dest="$REC/car-inventario/$(echo "$rel" | sed 's|/|__|g').json"
      if assetutil -I "$car" > "$dest" 2>>"$LOG"; then ninv=$((ninv+1)); else log "  assetutil -I falló con $rel"; fi
    done < <(find "$REC/car" "$REC/iconos" -name '*.car' -type f 2>/dev/null)
    log "  inventario de .car con assetutil: $ninv archivos"
  else
    log "  no hay assetutil: sin inventario de los .car"
  fi
  CUR=/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors
  [ -d "$CUR" ] && ( cd "$CUR" && tar -cf - . ) | ( cd "$REC/cursores" && tar -xf - 2>/dev/null )
  cp /System/Library/Sounds/*.aiff "$REC/sonidos/sistema/" 2>>"$LOG"
  SS=/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds
  [ -d "$SS" ] && ( cd "$SS" && tar -cf - . ) | ( cd "$REC/sonidos/interfaz" && tar -xf - 2>/dev/null )
  # 3. Fondos: los de fábrica de esta versión y el que tiene puesto el usuario.
  for f in "/System/Library/Desktop Pictures/"*.heic "/Library/Desktop Pictures/"*.heic; do
    [ -f "$f" ] && cp "$f" "$REC/fondos/" 2>>"$LOG"
  done
  if [ "${AJENA:-0}" != 1 ]; then  # el fondo y la foto de una Mac ajena son de su dueña
  ACTUAL="$(osa -e 'tell application "System Events" to get picture of current desktop')"
  if [ -n "$ACTUAL" ] && [ -f "$ACTUAL" ]; then cp "$ACTUAL" "$REC/fondos/fondo-del-usuario-$(basename "$ACTUAL")"; fi
  echo "fondo puesto: ${ACTUAL:-?}" > "$REC/fondos/fondo-del-usuario.txt"
  # 4. Lo de la pantalla de inicio: la foto de la cuenta y los botones.
  FOTO="$(dscl . -read "/Users/$USER" Picture 2>/dev/null | sed '1s/^Picture: *//; s/^ *//' | grep -v '^$' | head -1)"
  [ -n "$FOTO" ] && [ -f "$FOTO" ] && cp "$FOTO" "$REC/cuenta/"
  dscl . -read "/Users/$USER" JPEGPhoto 2>/dev/null | tail -n +2 | xxd -r -p > "$REC/cuenta/avatar.jpegphoto" 2>/dev/null
  [ -s "$REC/cuenta/avatar.jpegphoto" ] || rm -f "$REC/cuenta/avatar.jpegphoto"
  fi
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
  # defaults read da 0/1 para un booleano, pero «defaults write … -bool 0» no lo acepta e imprime su
  # ayuda (Mint-Macos en 27, 26-10-2026): se traduce a false/true.
  local v="$3"; [ "$4" = bool ] && case "$v" in 0) v=false ;; 1) v=true ;; esac
  if [ "$3" = "__sin__" ]; then defaults delete "$1" "$2" 2>/dev/null; else defaults write "$1" "$2" "-$4" "$v"; fi
}
MODO_ORIG="$(osa -e 'tell application "System Events" to tell appearance preferences to get dark mode')"
MAG_ORIG="$(leer_def com.apple.dock magnification)"; LARGE_ORIG="$(leer_def com.apple.dock largesize)"
ORI_ORIG="$(leer_def com.apple.dock orientation)"; DESK_ORIG="$(leer_def com.apple.finder CreateDesktop)"
STATUS_ORIG="$(leer_def com.apple.finder ShowStatusBar)"; AUTOHIDE_ORIG="$(leer_def com.apple.dock autohide)"
SS_ORIG="$(defaults -currentHost read com.apple.screensaver idleTime 2>/dev/null || echo __sin__)"
MUESTRA_CREADA=false
# Bloque 18 (acentos): las tres claves globales como estaban; se reponen solo si el bloque las tocó.
ACC_ORIG="$(leer_def -g AppleAccentColor)"; HIL_ORIG="$(leer_def -g AppleHighlightColor)"
AQUA_ORIG="$(leer_def -g AppleAquaColorVariant)"; ACENTO_TOCADO=false
acento_reponer() {
  poner_def -g AppleAccentColor "$ACC_ORIG" int; poner_def -g AppleHighlightColor "$HIL_ORIG" string
  poner_def -g AppleAquaColorVariant "$AQUA_ORIG" int
  $H avisar-colores >/dev/null 2>>"$LOG"; ACENTO_TOCADO=false; log "18: acento devuelto"
}
EXP_ORIG=""; EXP2_ORIG=""   # bloque 09: la hoja Save desplegada por preferencia (13 o más)
# Bloque 17 (Stacks): los archivos de prueba que puso en el Desktop y si cambió «Use Stacks».
PILA_LISTA="$SAL/pila-archivos.txt"; : > "$PILA_LISTA"; STACKS_TOCADO=false
usar_stacks_marca() { # «si» o «no»: si «Use Stacks» del menú View del escritorio está marcado
  local m; m="$(osa -e 'tell application "System Events" to tell process "Finder" to get value of attribute "AXMenuItemMarkChar" of menu item "Use Stacks" of menu 1 of menu bar item "View" of menu bar 1')"
  case "$m" in ""|missing\ value) echo no ;; *) echo si ;; esac; }
usar_stacks_clic() { osa -e 'tell application "System Events" to tell process "Finder" to click menu item "Use Stacks" of menu 1 of menu bar item "View" of menu bar 1'; }
borrar_pila() { local f; while IFS= read -r f; do case "$f" in "$HOME/Desktop/extraer-pila-"*|"$HOME/Downloads/extraer-pila-"*) rm -f "$f" ;; esac; done < "$PILA_LISTA"; : > "$PILA_LISTA"; }
devolver() {
  $ACENTO_TOCADO && acento_reponer
  if $STACKS_TOCADO; then osa -e 'tell application "Finder" to activate'; usar_stacks_clic; STACKS_TOCADO=false; log "17: Use Stacks devuelto en devolver"; fi
  borrar_pila
  [ -n "$EXP_ORIG" ] && poner_def -g NSNavPanelExpandedStateForSaveMode "$EXP_ORIG" bool
  [ -n "$EXP2_ORIG" ] && poner_def -g NSNavPanelExpandedStateForSaveMode2 "$EXP2_ORIG" bool
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
  foto_sistema despues
  if diff -r "$SAL/estado-sistema/antes" "$SAL/estado-sistema/despues" > "$SAL/estado-sistema/diferencias.txt" 2>&1; then
    log "Login Items y servicios de Sharing: iguales antes y después"
  else log "OJO: Login Items o servicios de Sharing cambiaron; mira estado-sistema/diferencias.txt"; fi
}
# Lo que el 08 abre y no vive en defaults: Login Items y los servicios de Sharing.
# Solo lectura. sfltool dumpbtm (13 o más) necesita root y no se corre: los
# ítems se leen por System Events y los servicios por los «disabled» de launchd.
foto_sistema() { # antes|despues
  local d="$SAL/estado-sistema/$1"; mkdir -p "$d"
  osa -e 'tell application "System Events" to get {name, path} of every login item' > "$d/login-items.txt" 2>&1
  launchctl print-disabled system > "$d/launchd-system.txt" 2>&1
  launchctl print-disabled "gui/$(id -u)" > "$d/launchd-gui.txt" 2>&1
  sharing -l > "$d/carpetas-compartidas.txt" 2>&1
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
  foto_sistema antes
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
# Toda tecla con ⌘ o texto va a la app que está AL FRENTE, no a la que nombra el
# «tell process». Si al frente quedara Terminal, ⌘W cerraría la ventana que corre
# este guion y el texto caería en el shell. tecla comprueba antes la app del
# frente y, si no es la esperada, no manda nada y lo anota.
al_frente() { osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null; }
tecla() { # app-esperada|no-terminal  orden-de-System-Events
  local f; f="$(al_frente)"
  case "$1" in no-terminal) [ -n "$f" ] && [ "$f" != Terminal ] ;; *) [ "$f" = "$1" ] ;; esac \
    || { log "tecla «$2» NO enviada: al frente estaba «${f:-?}» y se esperaba $1"; return 1; }
  osa -e "tell application \"System Events\" to $2"; }
modo() { osa -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $1"; sleep 2; }
ocultar() { osa -e 'tell application "System Events" to set visible of (every process whose visible is true and name is not "Finder") to false'; }
ocultar_excepto() { osa -e "tell application \"System Events\" to set visible of (every process whose visible is true and name is not \"Finder\" and name is not \"$1\") to false"; }
raton_fuera() { $H raton mover $((W-10)) $((HH/2)); sleep 0.3; }
cap_full() { sleep 0.7; screencapture -x "$CAP/$1.png" && log "cap $1"; }
cap_reg()  { sleep 0.7; screencapture -x -R "$2" "$CAP/$1.png" && log "cap $1 ($2)"; }
cap_win()  { [ -n "$2" ] || { log "sin ventana para $1: va la pantalla entera"; cap_full "$1"; return; }; sleep 0.7; screencapture -x -o -l "$2" "$CAP/$1.png" && log "cap $1 (ventana $2)"; }
ventana_pref() { # la ventana principal de System Preferences: la que tiene título (el panel actual); si no, la más grande.
  # System Settings: la más grande de capa 0, porque en 27 la de inicio no tiene título en CGWindowList (Mint-Macos, 26-10-2026).
  [ "$AJUSTES" = "System Settings" ] && { ventana_de "$AJUSTES"; return; }
  local id; id=$($H ventanas "$AJUSTES" | awk -F'\t' '$2==0 && $4!="" {print $1; exit}')
  [ -n "$id" ] && echo "$id" || ventana_de "$AJUSTES"; }
cerrar_paneles_pref() { # hojas (sheets) que abren algunas pestañas, p. ej. Accessibility ▸ Dwell con «Done»: bloquean la ventana hasta cerrarlas.
  # Cancel primero: en Catalina es la Mac de todos los días y un OK podría aplicar algo; OK solo si no hay otro botón.
  osa -e 'with timeout of 15 seconds' -e 'tell application "System Events" to tell process "System Preferences"' \
      -e 'repeat with w in windows' -e 'repeat with s in sheets of w' \
      -e 'repeat with b in {"Cancel", "Done", "Close", "OK"}' -e 'try' -e 'click (first button of s whose name is b)' -e 'exit repeat' -e 'end try' -e 'end repeat' \
      -e 'end repeat' -e 'end repeat' -e 'end tell' -e 'end timeout' 2>/dev/null; sleep 0.6; }
ventana_de() { # dueño [regex del título] → id de la ventana normal MÁS GRANDE (no la primera: puede haber paneles sueltos)
  $H ventanas "$1" | awk -F'\t' -v t="${2:-}" '$2==0 && (t=="" || $4 ~ t) { split($5, b, " "); a=b[3]*b[4]; if (a>max) {max=a; id=$1} } END { if (id) print id }'; }
ventana_alerta() { # dueños «a|b» → id de una alerta, diálogo o Force Quit. En CG no son capa 0
  # (Monterey 12.7.6, 26-10-2026: ventana_de no las veía y salieron a pantalla completa): primero
  # capa 0 como siempre; si no hay, cualquier capa de esos dueños, sin las que cubren la pantalla
  # (loginwindow tiene escudos de pantalla entera) ni las de menos de 40 pt. Si no encuentra
  # ninguna, deja en la bitácora lo que había, para afinar.
  local id d
  for d in $(echo "$1" | tr '|' ' '); do id="$(ventana_de "$d")"; [ -n "$id" ] && { echo "$id"; return; }; done
  id="$($H ventanas | awk -F'\t' -v d="^($1)$" -v W="$W" -v HH="$HH" '$3 ~ d { split($5, b, " ");
    if ((b[3] >= W && b[4] >= HH) || b[3] < 40 || b[4] < 40) next; a = b[3]*b[4]; if (a > max) { max = a; id = $1 } }
    END { if (id) print id }')"
  if [ -n "$id" ]; then echo "$id"; else log "sin ventana de $1; había: $($H ventanas | awk -F'\t' '{printf "%s/%s/%s; ", $3, $2, $5}')"; fi
}
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

# ---- Bloque 08 en System Settings (macOS 13 en adelante). SIN PROBAR en Mac (26-10-2026).
# En Sequoia 15.8.1 el bloque 08 de System Preferences salió casi entero mal: el proceso
# «System Preferences» ya no existe (cada captura fue la pantalla entera, sin System Settings
# o sin foco), el diccionario de AppleScript publica 6 paneles de unos 35, y sus «anchors» no
# abren subpáginas (salieron repetidas). Aquí se recorre la interfaz: cada fila de la barra
# lateral, el panel llevado hasta abajo, y sus subpáginas (un nivel). Nada se cambia: solo se
# pulsan botones que navegan o que abren una hoja, y cada hoja se cierra con Cancel o Done.
SUBMAX="${SUBMAX:-25}"   # subpáginas por panel, como mucho (Privacy & Security tiene unas 20)
# En seco (por omisión) no se pulsa ninguna subpágina: se anota «pulsaría …» en la bitácora para
# revisar la lista antes. Pulsar de verdad: AJ_SECO=0 (Planner, 26-10-2026).
AJ_SECO="${AJ_SECO:-1}"
# Botones con «…» que abren una hoja que se captura y se cierra; cualquier otro «…» no se pulsa.
AJ_HOJAS='^(Keyboard Shortcuts|Hot Corners|Advanced|Options|Details|Customize)'
AJ_HOJAS_EXACTO='^(Keyboard Shortcuts|Hot Corners|Advanced|Options|Details|Customize)(…|[.][.][.])?$'   # [.]: awk -v se come las «\\»
# Lo que empieza así hace algo en vez de navegar: nunca se pulsa. Las filas que navegan
# son sustantivos («About», «Storage», «Login Items & Extensions»).
AJ_NO='^(Turn|Enable|Disable|Add|Remove|Delete|Erase|Reset|Restart|Shut|Log Out|Sign|Update|Upgrade|Install|Allow|Deny|Quit|Apply|Done|OK|Cancel|Set Up|Change|Edit|Lock|Unlock|Forget|Join|Connect|Disconnect|Pair|Unpair|Clear|Empty|Restore|Use|Buy|Learn|Manage|Store|Optimize|Review|Open|Show|Hide|Calibrate|Identify|Detect|Arrange|Back|Forward|Search|Help|Share|Send|Copy|Import|Export|Choose|Select|Start|Stop|Pause|Resume|Test|Check|Verify|Repair|Get|Download|Renew|Request|Approve|Leave|Invite|Accept|Decline|Revert|Default|Report|Create|New|Rename|Replace|Run|Play|Record|Scan|Print|Close|Dismiss)( |$|…|\.)'
# Lo mismo para el último tramo de un AXIdentifier en camelCase (turnOn, resetAll): basta el prefijo.
# Sin «start» (startupDisk navega). featureDescription es texto, no navega.
AJ_NO_ID='^(turn|enable|disable|add|remove|delete|erase|reset|restart|shut|logout|signin|signout|update|upgrade|install|allow|deny|quit|apply|done|ok$|cancel|setup|change|edit|lock|unlock|forget|join|connect|disconnect|pair|unpair|clear|empty|restore|buy|learn|manage|optimize|open|show|hide|calibrate|identify|detect|arrange|back|forward|search|help|send|copy|import|export|choose|select|stop|pause|resume|test|check|verify|repair|download|renew|request|approve|leave|invite|accept|decline|revert|report|create|new|rename|replace|run|play|record|scan|print|close|dismiss|feature|zoom|minimi)'
# Filas de la barra lateral con datos de la cuenta o de pago: su panel se captura, sus subpáginas no;
# con AJENA=1 ni se abren. En Wi-Fi y Bluetooth tampoco se entra: ahí un botón con el nombre de
# una red o de un aparato CONECTA, y la iMac de 27 se maneja por Remote Control. Se comparan sin
# mayúsculas contra el texto de la fila Y su AXIdentifier (en 27 las filas no tienen texto:
# com.apple.systempreferences.AppleIDSettings*AppleIDSettings, com.apple.settings.notifications).
AJ_PRIVADO='apple ?account|apple ?id|wallet|password|passcode|internet.?accounts|game ?center|family|icloud|users ?(and|&) ?groups'
AJ_SIN_SUB="$AJ_PRIVADO|wi-?fi|bluetooth"
aj() { $U "$1" "$AJUSTES" "${@:2}" 2>>"$LOG"; }
aj_frente() { osa -e "tell application \"$AJUSTES\" to activate"; sleep 0.8; }
aj_slug() { echo "$1" | tr -c 'A-Za-z0-9\n' '-' | tr A-Z a-z | sed 's/--*/-/g; s/^-//; s/-*$//' | cut -c1-40; }
AJ_VENT_ANT=""
aj_cap() { # una sola ventana; si CG no da ninguna, se anota lo que había antes de ir a la pantalla entera
  local id; aj_frente; raton_fuera; id="$(ventana_pref | head -1)"
  [ -n "$id" ] || log "08: sin ventana de $AJUSTES para $1; CG tenía: $($H ventanas 2>>"$LOG" | grep -i -E 'setting|prefer' | tr '\t\n' ' ;')"
  # En 27 la ventana se recreó al llegar a Game Center y las filas siguientes no abrieron (26-10-2026).
  [ -n "$id" ] && [ -n "$AJ_VENT_ANT" ] && [ "$id" != "$AJ_VENT_ANT" ] && log "08: la ventana de $AJUSTES cambió de id: $AJ_VENT_ANT → $id ($1)"
  [ -n "$id" ] && AJ_VENT_ANT="$id"
  cap_win "$1" "$id"; }
# Cambia si cambió lo que se ve. El título y los botones fuera de la barra lateral («botones» ya la
# excluye): en 27 las primeras 80 líneas del árbol eran solo la barra, la firma salía siempre igual y
# aj_volver daba por vuelto lo que seguía en About; en General solo se pulsó la primera (26-10-2026).
aj_firma() { printf '%s|%s' "$(aj titulo)" "$(aj botones | cksum | cut -d' ' -f1)"; }
aj_cerrar_hojas() { # hojas y diálogos encima (en Sequoia, «Sign In to View AppleCare & Warranty»): Cancel primero
  local i=0
  while [ "$(aj hoja-hay)" = si ] && [ $i -lt 3 ]; do
    { [ "$($U clic "$AJUSTES::hoja" Cancel 2>>"$LOG")" = ok ] || [ "$($U clic "$AJUSTES::hoja" Done 2>>"$LOG")" = ok ] \
      || [ "$($U clic "$AJUSTES::hoja" Close 2>>"$LOG")" = ok ] || [ "$($U clic "$AJUSTES::hoja" OK 2>>"$LOG")" = ok ]; } || esc
    sleep 0.8; i=$((i+1))
  done; }
aj_fondo() { # base: si el panel tiene más abajo, una captura más llevada al fondo (-fin)
  [ "$(aj desplazar)" = ok ] || return 0
  sleep 1; aj_cap "$1-fin-$2"; aj desplazar-arriba >/dev/null; sleep 0.5; }
aj_volver_espera() { # firma: hasta 8 s (más lo que tarde la rueda) a que la firma vuelva a la de la raíz
  local i=0; while [ $i -lt 8 ]; do aj_esperar; [ "$(aj_firma)" = "$1" ] && return 0; sleep 1; i=$((i+1)); done; return 1; }
aj_volver() { # fila firma: de una subpágina a la raíz del panel, esperando a que de verdad vuelva
  aj clic Back >/dev/null
  aj_volver_espera "$2" && return 0
  log "08: Back no volvió a la raíz de la fila $1 (título ahora «$(aj titulo)»); vuelvo por la barra"
  aj barra-ir $(( $1 == 1 ? 2 : $1 - 1 )) >/dev/null; sleep 1.5; aj barra-ir "$1" >/dev/null
  aj_volver_espera "$2" || log "08: no pude volver a la raíz de la fila $1 (título «$(aj titulo)»)"; }
aj_esperar() { # hasta 10 s mientras la ventana tenga una rueda o una barra de progreso
  local i=0; while [ "$(aj ocupado)" = si ] && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  [ $i -gt 0 ] && log "08: esperé ${i} s a que cargara"; return 0; }
aj_ir() { # n: abre la fila n. Si falla (en 27, después de Game Center la ventana se recreó y las
  # filas de abajo no abrían): espera a que cargue, cierra lo que haya encima, relee la ventana y
  # reintenta UNA vez llevando la fila a la vista con la barra de scroll de la lista.
  [ "$(aj barra-ir "$1")" = ok ] && return 0
  aj_esperar; aj_cerrar_hojas; aj_frente
  log "08: barra-ir $1 falló; reintento una vez (ventana ahora: $(ventana_pref | head -1))"
  [ "$(aj barra-ir "$1" rodar)" = ok ]; }
aj_hoja_filas() { # base modo: una hoja con lista a la izquierda (Keyboard Shortcuts): cada fila
  local c j=0
  $U filas "$AJUSTES::hoja" 2>>"$LOG" > "$SAL/.hoja"
  while IFS= read -r c; do
    [ -n "$c" ] && [ $j -lt "$SUBMAX" ] || continue
    [ "$($U fila "$AJUSTES::hoja" "$c" 2>>"$LOG")" = ok ] || continue
    sleep 1; raton_fuera; cap_full "$1-$(aj_slug "$c")-$2"; j=$((j+1))
  done < "$SAL/.hoja"; rm -f "$SAL/.hoja"; }
ajustes_recorrer() { # claro|oscuro
  local M=$1 n txt ident clave base titulo raiz c k cand sub tam ancho yo ult rol subrol
  yo="$(id -F 2>/dev/null)"; AJ_VENT_ANT=""
  # Las del 08 de una corrida anterior del mismo día no se mezclan con estas.
  rm -f "$CAP"/08-*-"$M".png "$CAP"/08-*-"$M"-fin.png
  cerrar_app "$AJUSTES"; sleep 1
  # En Sequoia salieron Finder y Finder Settings de otras tomas detrás, y la ventana sin foco.
  cerrar_finder
  osa -e 'tell application "System Events" to tell process "Finder"' \
      -e 'repeat with w in (every window whose name ends with "Settings" or name ends with "Preferences")' \
      -e 'try' -e 'click (first button of w whose subrole is "AXCloseButton")' -e 'end try' -e 'end repeat' -e 'end tell'
  open -b com.apple.systempreferences; sleep 3
  ocultar_excepto "$AJUSTES"; osa -e 'tell application "System Events" to set visible of process "Finder" to false'
  aj_frente
  # La ventana tan alta como quepa (el ancho es fijo): menos paneles cortados abajo.
  tam="$(osa -e "tell application \"System Events\" to get size of window 1 of process \"$AJUSTES\"")"; ancho="${tam%%,*}"; ancho="${ancho// /}"
  [ -n "$ancho" ] && osa -e "tell application \"System Events\" to tell process \"$AJUSTES\"" \
      -e "set position of window 1 to {$(( (W-ancho)/2 )), $((BARRA+8))}" -e "set size of window 1 to {$ancho, $((HH-BARRA-DOCK-24))}" -e 'end tell'
  sleep 1; aj_cap 08-preferencias-todas-$M
  mkdir -p "$HER/arbol-ajustes"
  aj barra > "$SAL/.barra"; log "08: System Settings, barra lateral con $(grep -c . "$SAL/.barra") filas"
  # Antes del bucle, para que una corrida que falle deje con qué corregir.
  cp "$SAL/.barra" "$HER/arbol-ajustes/barra-$M.txt"; aj arbol > "$HER/arbol-ajustes/ventana-inicio-$M.txt"
  # Separados por «|»: con tabulador, bash junta dos seguidos y el texto vacío se come al identificador.
  while IFS='|' read -r n txt ident; do
    [ -n "$n" ] || continue   # la línea vacía del final
    # La etiqueta: el texto de la fila; si no tiene (27), lo último del AXIdentifier tras «.» o «*».
    [ -n "$txt" ] || txt="$(echo "$ident" | sed 's/.*[.*]//')"
    [ -n "$txt" ] || { log "08: fila $n sin etiqueta ni identificador (separador o búsqueda): se salta"; continue; }
    clave="$txt $ident"
    if [ "${AJENA:-0}" = 1 ] && { echo "$clave" | grep -qiE "$AJ_PRIVADO" || [ "$txt" = "$yo" ]; }; then
      log "08: AJENA, no se abre «${txt}»"; continue; fi
    aj_ir "$n" || { log "08: no pude abrir la fila $n «${txt}»"; continue; }
    sleep 2.5; echo "$clave" | grep -qiE 'storage|software.?update|general' && sleep 5   # Storage tarda en calcular
    aj_esperar
    aj_cerrar_hojas
    base="08-pref-$(printf %02d "$n")-$(aj_slug "$txt")"
    aj_cap "$base-$M"; aj_fondo "$base" "$M"
    aj botones > "$SAL/.todos"
    if [ "$M" = claro ]; then   # para afinar la próxima versión
      aj arbol > "$HER/arbol-ajustes/$base.txt"; cp "$SAL/.todos" "$HER/arbol-ajustes/$base.botones.txt"; fi
    if echo "$clave" | grep -qiE "$AJ_SIN_SUB" || [ "$txt" = "$yo" ]; then continue; fi
    titulo="$(aj titulo)"; raiz="$(aj_firma)"
    # Solo se pulsan botones con AXIdentifier del propio System Settings («com.apple.systempreferences.»
    # o «com.apple.settings.»), que no sean de la barra lateral y cuyo último tramo no empiece con un
    # verbo de acción. Los que no tienen identificador (flechas del scroll, «Search», close, zoom,
    # minimize) NUNCA: el 26-10-2026 en 27 se pulsó «increment arrow button» por ir por la descripción.
    # Y solo rol AXButton: un interruptor (AXCheckBox/AXSwitch), un popup o un deslizador también pueden
    # traer un id com.apple.settings.*, y pulsarlo cambia un ajuste (Planner, 26-10-2026). Va con «|»
    # porque el subrol puede venir vacío.
    # En 27, Privacy & Security navega con ids «<Nombre>_Navigator, N» (Mint-Macos, 26-10-2026: «Location
    # Services_Navigator, 0»): también valen, solo AXButton sin subrol (Planner). Y un botón SIN id cuyo
    # nombre sea exactamente uno de los que abren hoja (Hot Corners…, Keyboard Shortcuts…) va como
    # «nombre:<nombre>» y se pulsa por su nombre; cualquier otro sin id, nunca.
    awk -F'\t' -v hojas="$AJ_HOJAS_EXACTO" '
      ($4 ~ /^com\.apple\.(systempreferences|settings)\./ && $5 == "AXButton" && $6 !~ /^AX(Switch|Toggle)$/) ||
      ($4 ~ /^[A-Za-z0-9 &]+_Navigator, [0-9]+$/ && $5 == "AXButton" && $6 == "") { print $4 "|" $5 "|" $6; next }
      ($4 == "" && $2 ~ hojas && $5 == "AXButton" && $6 == "") { print "nombre:" $2 "|" $5 "|" $6 }' "$SAL/.todos" | awk '!v[$0]++' > "$SAL/.botones"
    [ -s "$SAL/.botones" ] || log "08: $txt: ningún botón con identificador de System Settings; subpáginas sin recorrer"
    k=0; cand=0
    while IFS='|' read -r c rol subrol; do
      [ $k -lt "$SUBMAX" ] || { log "08: $txt: llegué a $SUBMAX subpáginas, paro"; break; }
      cut -d'|' -f3 "$SAL/.barra" | grep -qxF "$c" && continue        # es de la barra lateral
      case "$c" in
        nombre:*) ult="${c#nombre:}" ;;
        *_Navigator*) ult="$(echo "$c" | sed 's/_Navigator.*//')" ;;
        *) ult="$(echo "$c" | sed 's/.*[.*]//')" ;;
      esac
      echo "$ult" | grep -qiE "$AJ_NO_ID" && { log "08: $txt: no se pulsa ${ult} (acción)"; continue; }
      echo "$c" | grep -qiE "$AJ_PRIVADO" && { log "08: $txt: no se pulsa ${ult} (privado)"; continue; }
      cand=$((cand+1))
      if [ "$AJ_SECO" != 0 ]; then log "08: $txt: pulsaría ${ult} (${c}; ${rol}/${subrol:-sin subrol})"; continue; fi
      case "$c" in
        nombre:*) [ "$(aj clic-igual "$ult")" = ok ] || { log "08: $txt: no encontré ${c} (título «$(aj titulo)»)"; continue; } ;;
        *) [ "$(aj clic-id "$c")" = ok ] || { log "08: $txt: no encontré ${c} (título «$(aj titulo)»)"; continue; } ;;
      esac
      log "08: $txt: pulsé ${ult} (${c}; ${rol}/${subrol:-sin subrol})"
      sleep 2
      sub="$base--$(aj_slug "$ult")"
      if [ "$(aj hoja-hay)" = si ]; then
        aj_frente; raton_fuera; cap_full "$sub-$M"; k=$((k+1))
        aj_hoja_filas "$sub" "$M"; aj_cerrar_hojas
      elif [ "$(aj titulo)" != "$titulo" ] || [ "$(aj_firma)" != "$raiz" ]; then
        aj_cap "$sub-$M"; aj_fondo "$sub" "$M"; k=$((k+1))
        aj_volver "$n" "$raiz"
      else
        log "08: «${c}» en ${txt} no abrió subpágina ni hoja: revisar si era un botón de acción"
      fi
    done < "$SAL/.botones"
    log "08: $txt: $k de $cand subpáginas u hojas"
  done < "$SAL/.barra"
  rm -f "$SAL/.barra" "$SAL/.botones" "$SAL/.todos"
  cerrar_app "$AJUSTES"; sleep 1
}

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
  # la pila Downloads en Fan, Grid y List; al final vuelve a como estaba.
  # En Sequoia salió vacía en las tres: si Downloads tiene menos de 3 archivos, van cuatro de
  # prueba (extraer-pila-*), que se borran al terminar el bloque (y en devolver).
  if [ "$(ls "$HOME/Downloads" 2>/dev/null | wc -l | tr -d ' ')" -lt 3 ]; then
    for n in 1 2; do printf 'Archivo de prueba %s (extraer-mac)\n' "$n" > "$HOME/Downloads/extraer-pila-nota-$n.txt" \
        && echo "$HOME/Downloads/extraer-pila-nota-$n.txt" >> "$PILA_LISTA"; done
    i=0; for f in $(ls "/System/Library/Desktop Pictures/"*.heic 2>/dev/null | head -2 | tr ' ' '?'); do
      i=$((i+1)); sips -s format jpeg -Z 1200 "$(echo "$f" | tr '?' ' ')" --out "$HOME/Downloads/extraer-pila-imagen-$i.jpg" >/dev/null 2>&1 \
        && echo "$HOME/Downloads/extraer-pila-imagen-$i.jpg" >> "$PILA_LISTA"; done
    log "05: Downloads casi vacía: $(grep -c Downloads/extraer-pila- "$PILA_LISTA") archivos de prueba"; sleep 1.5
  fi
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
  borrar_pila; raton_fuera
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
  tecla Finder 'keystroke " "'; sleep 2; raton_fuera
  cap_full 06-finder-quick-look-$M; tecla no-terminal 'keystroke " "'; sleep 1
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
  finder_activar; tecla Finder 'keystroke "," using command down'; sleep 1.5; raton_fuera
  for tab in General Tags Sidebar Advanced; do
    osa -e "tell application \"System Events\" to tell process \"Finder\" to click button \"$tab\" of toolbar 1 of window 1"; sleep 1
    cap_win 06-finder-preferences-$(echo $tab | tr A-Z a-z)-$M "$(ventana_de Finder 'Preferences|Settings')"
  done
  tecla Finder 'keystroke "w" using command down'; sleep 0.5
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
  tecla no-terminal 'keystroke space using command down'; sleep 1.5; cap_full 07-spotlight-vacio-$M
  tecla no-terminal 'keystroke "Lago"'; sleep 2.5; cap_full 07-spotlight-resultados-$M; esc; sleep 0.4; esc; sleep 0.5
  open -a Launchpad; sleep 2; cap_full 07-launchpad-$M; esc; sleep 1

  fi
  # 08 System Preferences: la cuadrícula, cada panel y cada pestaña (anchor).
  # Desde macOS 13, System Settings: la barra lateral, cada panel y sus subpáginas (ajustes_recorrer).
  if bloque 08 && [ "$AJUSTES" = "System Settings" ]; then
  ajustes_recorrer "$M"
  elif bloque 08; then
  cerrar_app "System Preferences"; sleep 1
  osa -e 'tell application "System Preferences" to activate' -e 'tell application "System Preferences" to set show all of it to true' ; sleep 2.5; raton_fuera
  # En Monterey «show all» no bastó (la captura salió con un panel): ⌘L es View ▸ Show All Preferences.
  tecla "System Preferences" 'keystroke "l" using command down'; sleep 2
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
  sleep 2.5; raton_fuera; cap_win 09-alerta-2-botones-$M "$(ventana_alerta 'osascript|CoreServicesUIAgent')"; kill $P1 2>/dev/null; sleep 1
  osascript -e 'display alert "Do you want to save the changes made to the document “Notas”?" message "Your changes will be lost if you don’t save them." buttons {"Don’t Save","Cancel","Save"} default button 3' >/dev/null 2>&1 & P2=$!
  sleep 2.5; raton_fuera; cap_win 09-alerta-3-botones-$M "$(ventana_alerta 'osascript|CoreServicesUIAgent')"; kill $P2 2>/dev/null; sleep 1
  osa -e 'tell application "TextEdit"' -e 'activate' -e 'make new document with properties {text:"Notas de la reunión" & linefeed & linefeed & "- Revisar presupuesto"}' \
      -e "set bounds of window 1 to {$((X1-40)), $((Y1-40)), $((X2-40)), $((Y2+80))}" -e 'end tell'; sleep 2; raton_fuera; ocultar_excepto TextEdit
  tecla TextEdit 'keystroke "s" using command down'; sleep 2.5; raton_fuera
  cap_win 09-dialogo-save-$M "$(ventana_de TextEdit)"
  osa -e 'tell application "System Events" to tell process "TextEdit" to get {description, name} of every button of sheet 1 of window 1' >> "$LOG"
  if osa -e 'tell application "System Events" to tell process "TextEdit" to click (first button of sheet 1 of window 1 whose description contains "isclos" or description contains "xpand")'; then
    sleep 1.5; raton_fuera; cap_win 09-dialogo-save-expandido-$M "$(ventana_de TextEdit)"
  elif [ "$AJUSTES" = "System Settings" ]; then
    # En Sequoia y en 27 el botón de desplegar no tiene nombre ni descripción («button, button»):
    # System Events no lo encuentra. Se pide la hoja ya desplegada con la preferencia global de
    # NSSavePanel, se abre otra vez y la preferencia vuelve como estaba (también en devolver).
    esc; sleep 1
    EXP_ORIG="$(leer_def -g NSNavPanelExpandedStateForSaveMode)"; EXP2_ORIG="$(leer_def -g NSNavPanelExpandedStateForSaveMode2)"
    defaults write -g NSNavPanelExpandedStateForSaveMode -bool true; defaults write -g NSNavPanelExpandedStateForSaveMode2 -bool true
    tecla TextEdit 'keystroke "s" using command down'; sleep 2.5; raton_fuera
    cap_win 09-dialogo-save-expandido-$M "$(ventana_de TextEdit)"
    poner_def -g NSNavPanelExpandedStateForSaveMode "$EXP_ORIG" bool; poner_def -g NSNavPanelExpandedStateForSaveMode2 "$EXP2_ORIG" bool
    EXP_ORIG=""; EXP2_ORIG=""
  fi
  esc; sleep 1.2
  tecla TextEdit 'keystroke "w" using command down'; sleep 1.8; raton_fuera
  cap_win 09-hoja-guardar-cambios-$M "$(ventana_de TextEdit)"
  osa -e 'tell application "System Events" to tell process "TextEdit" to click button "Delete" of sheet 1 of window 1' || \
    osa -e 'tell application "System Events" to tell process "TextEdit" to click button 3 of sheet 1 of window 1'; sleep 1.2
  tecla TextEdit 'keystroke "o" using command down'; sleep 2.5; raton_fuera
  cap_win 09-dialogo-open-$M "$(ventana_de TextEdit)"; esc; sleep 1; osa -e 'tell application "TextEdit" to quit saving no'; sleep 1.5
  osascript -e 'do shell script "true" with administrator privileges' >/dev/null 2>&1 & P3=$!
  sleep 3; raton_fuera; cap_win 09-dialogo-contrasena-admin-$M "$(ventana_alerta SecurityAgent)"
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
  cerrar_app "System Information"; sleep 1

  fi
  # 15 Force Quit (⌥⌘Esc) y la barra de ⇧⌘5
  if bloque 15; then
  finder_activar; tecla Finder 'key code 53 using {command down, option down}'; sleep 2; raton_fuera
  cap_win 15-force-quit-$M "$(ventana_alerta loginwindow)"; [ -f "$CAP/15-force-quit-$M.png" ] || cap_full 15-force-quit-$M
  osa -e 'tell application "System Events" to key code 53'; sleep 0.5   # Esc cierra Force Quit (antes iba además un ⌘W a ciegas)
  finder_activar; tecla Finder 'keystroke "5" using {shift down, command down}'; sleep 2; raton_fuera
  cap_full 15-captura-pantalla-barra-$M; esc; sleep 1

  fi
  # 13 ⌘Tab y Mission Control
  if bloque 13; then
  osa -e 'tell application "System Events"' -e 'key down command' -e 'try' -e 'keystroke tab' -e 'delay 1.2' \
      -e "do shell script \"screencapture -x '$CAP/13-cmd-tab-$M.png'\"" -e 'key code 53' -e 'end try' -e 'key up command' -e 'end tell'; log "cap 13-cmd-tab-$M"; sleep 0.5
  open -a "Mission Control"; sleep 3.5   # con 2 s salió a mitad de la animación (Monterey)
  screencapture -x "$CAP/13-mission-control-$M.png"; log "cap 13-mission-control-$M"; esc; sleep 1

  fi
  # 14 Migration Assistant: solo la primera pantalla. Lo demás va a mano al
  if bloque 14; then
  #    final: Continue pide la clave y cierra todas las apps, Terminal incluido.
  open -a "Migration Assistant"; sleep 3; raton_fuera
  cap_win 14-migration-assistant-inicio-$M "$(ventana_de 'Migration Assistant')"
  cerrar_app "Migration Assistant"; sleep 1
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
  finder_activar; tecla Finder 'keystroke "g" using {shift down, command down}'; sleep 1.5
  cap_win "16-finder-go-to-folder-$M" "$(id_finder)"; esc; sleep 0.6
  finder_activar; tecla Finder 'keystroke "t" using command down'; sleep 1.5
  cap_win "16-finder-dos-pestanas-$M" "$(id_finder)"
  tecla Finder 'keystroke "w" using command down'; sleep 1
  finder_activar; tecla Finder 'keystroke "f" using command down'; sleep 1.2
  tecla Finder 'keystroke "Notas"'; sleep 2.5
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
      sleep 3; cap_full "16-about-storage-manage-$M"; cerrar_app "Storage Management"; sleep 1
    fi
  done
  cerrar_app "System Information"; sleep 1

  # --- System Preferences (en 13 o más lo cubre el bloque 08 por System Settings)
  if [ "$AJUSTES" = "System Settings" ]; then
  log "16: macOS $VERSION: lo de System Preferences va en el bloque 08 (System Settings)"
  else
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
  # Si José ya está en Scaled, solo se captura (un clic en Default le cambiaría la
  # resolución). Si está en Default: Scaled, captura y de vuelta a Default.
  ESTADO_PANT="$($U marcado "System Preferences" "Default for display" 2>>"$LOG")"; log "16: Displays, Default for display marcado: ${ESTADO_PANT:-?}"
  if [ "$ESTADO_PANT" = no ]; then cap_pref displays-scaled
  elif [ "$ESTADO_PANT" = si ] && ui_log clic "System Preferences" "Scaled"; then
    sleep 1.5; cap_pref displays-scaled; ui_log clic "System Preferences" "Default for display"; sleep 1.5
  else log "16: Displays sin saber qué estaba marcado: no se toca"; fi
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
  fi

  # --- Launchpad en modo de edición (con ⌥ apretado, sin tocar ningún ícono)
  open -a Launchpad; sleep 2
  # La ⌥ se suelta pase lo que pase: el screencapture va dentro de un try.
  osa -e 'tell application "System Events"' -e 'key down option' -e 'try' -e 'delay 1.5' \
      -e "do shell script \"screencapture -x '$CAP/16-launchpad-edicion-$M.png'\"" -e 'end try' -e 'key up option' -e 'end tell' && log "cap 16-launchpad-edicion-$M"
  esc; sleep 1; raton_fuera
  fi
  # 17 Stacks del escritorio (Mojave en adelante; High Sierra no los tiene). Lo pide Dev para Fynder
  # (Planner, 19-10-2026): las pilas cerradas, una abierta y Group Stacks By. Los archivos de prueba van
  # al Desktop con el prefijo extraer-pila- y se borran al final (y en devolver); «Use Stacks» queda como
  # estaba. Las capturas llevan la versión: son de 27 o de Monterey hasta confirmarlas en Catalina.
  if bloque 17; then
  V17="macos$VERSION"
  # los archivos: imágenes, PDF y capturas de pantalla (estas con su marca de captura, por screencapture)
  mkdir -p "$HOME/Desktop"
  i=0; for f in $(ls "/System/Library/Desktop Pictures/"*.heic 2>/dev/null | head -3 | tr ' ' '?'); do
    i=$((i+1)); sips -s format jpeg -Z 1200 "$(echo "$f" | tr '?' ' ')" --out "$HOME/Desktop/extraer-pila-imagen-$i.jpg" >/dev/null 2>&1 \
      && echo "$HOME/Desktop/extraer-pila-imagen-$i.jpg" >> "$PILA_LISTA"; done
  for n in 1 2; do printf 'Documento de prueba %s (extraer-mac)\n' "$n" > "$SAL/pila-$n.txt"
    /usr/sbin/cupsfilter -m application/pdf "$SAL/pila-$n.txt" > "$HOME/Desktop/extraer-pila-documento-$n.pdf" 2>/dev/null \
      && echo "$HOME/Desktop/extraer-pila-documento-$n.pdf" >> "$PILA_LISTA"; done
  for n in 1 2; do screencapture -x -R 0,0,400,300 "$HOME/Desktop/extraer-pila-captura-$n.png" \
      && echo "$HOME/Desktop/extraer-pila-captura-$n.png" >> "$PILA_LISTA"; done
  log "17: $(wc -l < "$PILA_LISTA" | tr -d ' ') archivos de prueba en el Desktop"
  defaults write com.apple.finder CreateDesktop -bool true; killall Finder; sleep 3; cerrar_finder
  finder_activar; ocultar; raton_fuera
  STACKS_ORIG="$(usar_stacks_marca)"; log "17: Use Stacks antes: ${STACKS_ORIG:-?}"
  if [ "$STACKS_ORIG" != si ]; then usar_stacks_clic && STACKS_TOCADO=true; sleep 2.5; fi
  raton_fuera; cap_full 17-stacks-cerradas-$V17-$M
  # una pila abierta: la de imágenes si se encuentra; si no, el primer ícono del escritorio
  P="$(osa -e 'tell application "System Events" to tell process "Finder"' \
      -e 'set r to ""' -e 'repeat with e in (every UI element of group 1 of scroll area 1)' \
      -e 'if r is "" and (name of e contains "Image" or name of e contains "Imagen") then set r to ((item 1 of (position of e)) + (item 1 of (size of e)) div 2) & "," & ((item 2 of (position of e)) + (item 2 of (size of e)) div 3)' \
      -e 'end repeat' -e 'if r is "" then set e to UI element 1 of group 1 of scroll area 1' \
      -e 'if r is "" then set r to ((item 1 of (position of e)) + (item 1 of (size of e)) div 2) & "," & ((item 2 of (position of e)) + (item 2 of (size of e)) div 3)' \
      -e 'return r as text' -e 'end tell')"
  P="${P//, /,}"
  if [ -n "$P" ]; then p=(${P//,/ }); $H raton clic "${p[0]}" "${p[1]}"; sleep 2; $H raton mover $((W/5)) $((HH*85/100)); sleep 0.5
    cap_full 17-stack-abierta-$V17-$M
    $H raton clic "${p[0]}" "${p[1]}"; sleep 1.5
  else log "17: no encontré una pila en el escritorio"; fi
  raton_fuera
  # Group Stacks By, desde el menú contextual del escritorio
  $H raton derecho $((W/5)) $((HH*55/100)); sleep 1
  P="$(osa -e 'tell application "System Events" to tell process "Finder" to get position of menu item "Group Stacks By" of menu 1 of group 1 of scroll area 1' 2>/dev/null)"
  [ -z "$P" ] && P="$(osa -e 'tell application "System Events" to tell process "Finder" to get position of menu item "Group Stacks By" of menu 1' 2>/dev/null)"
  if [ -n "$P" ]; then P="${P//, /,}"; p=(${P//,/ }); $H raton mover $(( ${p[0]} + 60 )) $(( ${p[1]} + 8 )); sleep 1.2
  else tecla Finder 'keystroke "Group Stacks"'; sleep 0.5; tecla Finder 'key code 124'; sleep 1; fi
  cap_full 17-group-stacks-by-$V17-$M; esc; esc; raton_fuera
  # devolver: Use Stacks como estaba, los archivos fuera y los íconos del escritorio como en la tanda
  if $STACKS_TOCADO; then finder_activar; cerrar_finder; usar_stacks_clic && STACKS_TOCADO=false; sleep 1.5; fi
  borrar_pila
  poner_def com.apple.finder CreateDesktop "$DESK_ORIG" bool; killall Finder; sleep 2.5
  fi
  log "=== fin tanda $M ==="
}

# 18 Acentos: una vez por color, no por tanda. Los colores se releen en claro y oscuro desde un
# proceso nuevo (herramientas.js acento), que lee las preferencias al arrancar; la ventanita de
# controles sale de ese mismo proceso, como app Regular y con la ventana key (en 12.7.6 salió
# inactiva y sin acento). La toma del Finder abierto, que diría si el color entra en caliente,
# va solo con ACENTO_FINDER=1: en 12.7.6 no repintó con las notificaciones de avisar-colores, cuyos
# nombres faltan por confirmar con «herramientas.js escuchar-colores» cambiando el acento a mano.
# Las cadenas de AppleHighlightColor son las de uso común, no leídas de System Settings: se anotan
# como hipótesis y lo que cuenta es selectedTextBackgroundColor releído.
acentos() {
  local A="$MED/acentos" fila nombre acc hil aqua prev="" hex
  mkdir -p "$A"; : > "$A/resumen.txt"
  modo false; ocultar; finder_activar; cerrar_finder; raton_fuera
  if [ "${ACENTO_FINDER:-0}" = 1 ]; then
    ventana_finder . list $X1 $Y1 $X2 $Y2
    osa -e 'tell application "Finder" to select folder "Documentos" of folder "Muestra" of home'; raton_fuera
  fi
  ACENTO_TOCADO=true
  for fila in "multicolor|__sin__|__sin__|1" \
              "azul|4|0.698039 0.843137 1.000000 Blue|1" \
              "morado|5|0.968627 0.831373 1.000000 Purple|1" \
              "rosa|6|1.000000 0.749020 0.823529 Pink|1" \
              "rojo|0|1.000000 0.733333 0.721569 Red|1" \
              "naranja|1|1.000000 0.874510 0.701961 Orange|1" \
              "amarillo|2|1.000000 0.937255 0.690196 Yellow|1" \
              "verde|3|0.752941 0.964706 0.678431 Green|1" \
              "gris|-1|0.847059 0.847059 0.862745 Graphite|6"; do
    IFS='|' read -r nombre acc hil aqua <<< "$fila"
    poner_def -g AppleAccentColor "$acc" int; poner_def -g AppleHighlightColor "$hil" string
    poner_def -g AppleAquaColorVariant "$aqua" int
    $H avisar-colores >/dev/null 2>>"$LOG"; sleep 1.5
    $H acento "$CAP/18-acento-${nombre}-claro.png" "$CAP/18-acento-${nombre}-oscuro.png" > "$A/${nombre}.json" 2>>"$LOG"
    [ "${ACENTO_FINDER:-0}" = 1 ] && { finder_activar; cap_win "18-acento-${nombre}-finder-claro" "$(id_finder)"; }
    grep -q '"ventana_key": false' "$A/${nombre}.json" && log "18: ${nombre}: la ventanita no quedó key; la toma puede salir sin acento"
    hex="$(grep -A2 '"controlAccentColor"' "$A/${nombre}.json" | grep '"hex"' | head -1 | tr -dc '#0-9A-F')"
    printf '%-10s escrito AppleAccentColor=%s AppleHighlightColor=%s AppleAquaColorVariant=%s · releído controlAccentColor claro %s\n' \
      "$nombre" "$acc" "$hil" "$aqua" "${hex:-?}" >> "$A/resumen.txt"
    if [ -n "$prev" ] && [ "$hex" = "$prev" ] && [ "$nombre" != azul ]; then
      log "18: ${nombre}: controlAccentColor releído igual que el anterior (${hex}); no se aplicó o el color coincide"
    fi
    log "18: ${nombre} listo (${hex:-sin color})"; prev="$hex"
  done
  acento_reponer
  cerrar_finder; raton_fuera
}

if quiere capturas; then
  mkdir -p "$CAP" "$MED"
  tanda claro
  tanda oscuro
  bloque 18 && acentos
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
  grabar 03-spotlight 8; tecla no-terminal 'keystroke space using command down'; sleep 2; tecla no-terminal 'keystroke "Lago"'; sleep 2.5; esc; sleep 0.3; esc; wait $GP; log "video 03"
  grabar 04-mission-control 7; open -a "Mission Control"; sleep 3; esc; sleep 1; wait $GP; log "video 04"
  ventana_finder . list $X1 $Y1 $X2 $Y2; raton_fuera
  grabar 05-minimizar-ventana 7; tecla Finder 'keystroke "m" using command down'; sleep 3; osa -e 'tell application "Finder" to set collapsed of Finder window 1 to false'; sleep 1.5; wait $GP; log "video 05"; cerrar_finder
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
