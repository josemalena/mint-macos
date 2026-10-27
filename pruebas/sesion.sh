#!/usr/bin/env bash
# Corre dentro del bus de prueba (lo lanza correr.sh con dbus-run-session): deja
# un gestor de ventanas si hace falta y corre cada caso con su tiempo límite.
#   sesion.sh CASO.sh…
set -uo pipefail
# Antes de nada: nada de lo que sigue borra ni escribe en lo real. Si las XDG son las de la persona (sesion.sh lanzado a mano, sin correr.sh), no se sigue:
# este script borra el macos.json de la versión de macOS y escribe en el dconf (Infra, 27-10-2026).
case "${XDG_CONFIG_HOME:-}" in ""|"$HOME/.config"|"$HOME/.config/") echo "  ✗ XDG_CONFIG_HOME es el real: no sigo"; exit 1 ;; esac
[ "${XDG_RUNTIME_DIR:-}" != "/run/user/$(id -u)" ] || { echo "  ✗ XDG_RUNTIME_DIR es el real: no sigo"; exit 1; }
[ -n "${XDG_RUNTIME_DIR:-}" ] || { echo "  ✗ XDG_RUNTIME_DIR vacío: no sigo"; exit 1; }
# Qué cambió en el dconf de José y si es fuga (revisar_dconf).
source "$(dirname "$0")/dconf-jose.sh"

RES="$PRUEBAS_RES"

# Antes de nada: el dconf de este bus tiene que escribir en el HOME de prueba.
dconf write /org/mint-macos/prueba/marca "'$MINT_MACOS_PRUEBA'"
if [ ! -s "$XDG_CONFIG_HOME/dconf/user" ]; then
  echo "  ✗ el dconf de la prueba no escribe en $XDG_CONFIG_HOME: no sigo"
  exit 1
fi

# En Xephyr no hay gestor de ventanas. Cada caso dice cuál necesita en su
# cabecera («# gestor: cinnamon»); si no dice nada, Muffin, el de Cinnamon a
# secas (foco, decoración, _NET_ACTIVE_WINDOW para wmctrl). Cinnamon entero es
# para lo que corre dentro del shell (extensiones como cmdtab@macos), y se
# cambia de uno a otro solo cuando el caso siguiente pide otro. En :0 ya está
# el de José.
GESTOR=""
GPID=""
# Listo es cuando el shell dice que arrancó y cargó cmdtab@macos (lo dice en
# su log; el nombre org.Cinnamon sale en el bus mucho antes).
cinnamon_listo() {
  wmctrl -m >/dev/null 2>&1 \
    && grep -q 'Cinnamon started at' "$RES/cinnamon.log" \
    && grep -q 'Loaded extension cmdtab@macos' "$RES/cinnamon.log"
}
poner_gestor() {
  [ "$PRUEBAS_REAL" != true ] || return 0
  [ "$1" != "$GESTOR" ] || return 0
  # A Muffin, con SIGKILL: con SIGTERM se cae (SIGSEGV en libgdk) y systemd-coredump procesaba un
  # volcado cada ~40 s durante una corrida (19-10-2026, calor y CPU).
  if [ -n "$GPID" ]; then kill $([ "$GESTOR" = muffin ] && echo -KILL) "$GPID" 2>/dev/null; wait "$GPID" 2>/dev/null; fi
  # Que el X suelte la composición del gestor que se fue antes de arrancar el otro: si el selector _NET_WM_CM_S0
  # sigue con dueño, el nuevo arranca sin componer y la pantalla queda lisa (caso 95 en el armado, 19-10-2026).
  for _ in $(seq 50); do
    python3 -I -c 'import sys; from Xlib import display; d = display.Display(); sys.exit(d.get_selection_owner(d.intern_atom("_NET_WM_CM_S0")) != 0)' \
      2>/dev/null && break
    sleep 0.1
  done
  GESTOR=""
  case "$1" in
    muffin)
      # Muffin se cae (SIGSEGV en libgdk) al cerrarlo con kill para pasar a Cinnamon. Sin volcado de
      # memoria: systemd-coredump guardaba uno cada ~40 s durante una corrida (19-10-2026, calor y CPU).
      (ulimit -c 0; exec muffin --replace --sm-disable) > "$RES/muffin.log" 2>&1 &
      GPID=$!
      for _ in $(seq 50); do wmctrl -m >/dev/null 2>&1 && break; sleep 0.1; done
      wmctrl -m >/dev/null 2>&1 || { echo "Muffin no arrancó (muffin.log)"; return 1; } ;;
    cinnamon|cinnamon-applets|cinnamon-notificaciones|cinnamon-colgadas|cinnamon-animaciones)
      # Las extensiones del repo (las que se están probando), no las de José.
      mkdir -p "$XDG_DATA_HOME/cinnamon/extensions" "$XDG_CONFIG_HOME/autostart"
      cp -r "$MINT_MACOS_REPO"/extensions/*@macos "$XDG_DATA_HOME/cinnamon/extensions/"
      gsettings set org.cinnamon enabled-extensions "['cmdtab@macos']"
      # «cinnamon-applets» además pone en el panel la barra de menús (appmenu@macos y globalmenu@macos) del repo.
      if [ "$1" = cinnamon-applets ] || [ "$1" = cinnamon-notificaciones ] || [ "$1" = cinnamon-colgadas ] || [ "$1" = cinnamon-animaciones ]; then
        mkdir -p "$XDG_DATA_HOME/cinnamon/applets"
        cp -r "$MINT_MACOS_REPO"/applets/appmenu@macos "$MINT_MACOS_REPO"/applets/globalmenu@macos "$XDG_DATA_HOME/cinnamon/applets/"
        gsettings set org.cinnamon panels-enabled "['1:0:top']"
        gsettings set org.cinnamon enabled-applets "['panel1:left:0:appmenu@macos:1', 'panel1:left:1:globalmenu@macos:2']"
      fi
      # «cinnamon-colgadas»: lo mismo y el menú Apple (applemenu@macos), que cambia el diálogo de «no responde» por Force Quit.
      if [ "$1" = cinnamon-colgadas ]; then
        cp -r "$MINT_MACOS_REPO"/applets/applemenu@macos "$XDG_DATA_HOME/cinnamon/applets/"
        gsettings set org.cinnamon enabled-applets "['panel1:left:0:applemenu@macos:3', 'panel1:left:1:appmenu@macos:1', 'panel1:left:2:globalmenu@macos:2']"
      fi
      # «cinnamon-notificaciones»: lo mismo y el Notification Center (notificaciones@macos) a la derecha.
      if [ "$1" = cinnamon-notificaciones ]; then
        cp -r "$MINT_MACOS_REPO"/applets/notificaciones@macos "$XDG_DATA_HOME/cinnamon/applets/"
        gsettings set org.cinnamon enabled-applets "['panel1:left:0:appmenu@macos:1', 'panel1:left:1:globalmenu@macos:2', 'panel1:right:0:notificaciones@macos:3']"
      fi
      # «cinnamon-animaciones»: lo del Notification Center y, ENCENDIDOS los efectos, el genio (Magic Lamp, la instalada de José copiada
      # aquí y con el parche de duración del repo, no la suya) y Mission Control: para medir las animaciones contra el perfil.
      if [ "$1" = cinnamon-animaciones ]; then
        cp -r "$MINT_MACOS_REPO"/applets/notificaciones@macos "$XDG_DATA_HOME/cinnamon/applets/"
        gsettings set org.cinnamon enabled-applets "['panel1:left:0:appmenu@macos:1', 'panel1:left:1:globalmenu@macos:2', 'panel1:right:0:notificaciones@macos:3']"
        # El perfil de Monterey del repo (las medidas, no las de la máquina): lo leen las extensiones y los applets al arrancar.
        mkdir -p "$XDG_CONFIG_HOME/mint-macos" "$XDG_DATA_HOME/mint-macos/macos/monterey-12.7.6/apps"
        echo '{"version": "monterey-12.7.6"}' > "$XDG_CONFIG_HOME/mint-macos/macos.json"
        cp "$MINT_MACOS_REPO/perfiles/monterey-12.7.6/animaciones.json" "$MINT_MACOS_REPO/perfiles/monterey-12.7.6/efectos.json" "$XDG_DATA_HOME/mint-macos/macos/monterey-12.7.6/apps/"
        ML="$PRUEBAS_HOME_REAL/.local/share/cinnamon/extensions/CinnamonMagicLamp@klangman"
        if [ -d "$ML" ]; then
          cp -r "$ML" "$XDG_DATA_HOME/cinnamon/extensions/"
          patch -s -N -p1 -d "$XDG_DATA_HOME/cinnamon/extensions/CinnamonMagicLamp@klangman" \
            < "$MINT_MACOS_REPO/extensions/parches/magiclamp-duracion-del-perfil.patch" > /dev/null || true
          gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos', 'sombras@macos', 'CinnamonMagicLamp@klangman']"
        else
          gsettings set org.cinnamon enabled-extensions "['cmdtab@macos', 'misioncontrol@macos', 'sombras@macos']"
        fi
        gsettings set org.cinnamon desktop-effects true
        gsettings set org.cinnamon startup-animation false
      else
        # Sin animaciones: una ventana recién abierta se ve (y se captura) al mapearse.
        gsettings set org.cinnamon desktop-effects false
        gsettings set org.cinnamon startup-animation false
      fi
      (ulimit -c 0; exec cinnamon --replace) > "$RES/cinnamon.log" 2>&1 &
      GPID=$!
      for _ in $(seq 600); do cinnamon_listo && break; sleep 0.1; done
      cinnamon_listo || { echo "Cinnamon no arrancó en 60s (cinnamon.log)"; return 1; } ;;
    *) echo "gestor desconocido: $1"; return 1 ;;
  esac
  GESTOR="$1"
}

# cerrar_caso NOMBRE: lo que lanzó el caso y siga vivo.
cerrar_caso() {
  local p
  for p in $(grep -lzx "PRUEBAS_CASO=$1" /proc/[0-9]*/environ 2>/dev/null | cut -d/ -f3); do
    kill "$p" 2>/dev/null || true
  done
}

for c in "$@"; do
  n="$(basename "$c" .sh)"
  limite="$(sed -n 's/^# límite: *//p' "$c" | head -1)"
  gestor="$(sed -n 's/^# gestor: *//p' "$c" | head -1)"
  # La versión de macOS de un caso no pasa al siguiente: los casos que ponen macos.json (en el runtime o en la configuración) lo dejaban para los demás
  # y el del runtime manda sobre el de la configuración.
  rm -f "$XDG_RUNTIME_DIR/mint-macos/macos.json" "$XDG_CONFIG_HOME/mint-macos/macos.json"
  # Sin $(…): el gestor tiene que quedar en este shell (GESTOR, GPID).
  if ! poner_gestor "${gestor:-muffin}" > "$RES/gestor.err" 2>&1; then
    printf '  ✗ %-28s %s\n' "$n" "$(tail -1 "$RES/gestor.err")"
    continue
  fi
  inicio=$(date +%s)
  PRUEBAS_CASO="$n" timeout "${limite:-120}" bash -c 'source "$PRUEBAS_LIB"; source "$1"; prueba' _ "$c" \
    > "$RES/$n.log" 2>&1
  r=$?
  cerrar_caso "$n"
  seg=$(( $(date +%s) - inicio ))
  # El dconf de José, después de cada caso: si cambió algo que tocan las pruebas, no
  # sigue nada más; si fue otra cosa (José trabajando), se anota y se sigue.
  dr=0; revisar_dconf "$PRUEBAS_DCONF_JOSE" || dr=$?
  if [ "$dr" = 2 ]; then
    printf '  ✗ %-28s el dconf de José cambió en %s: paro la corrida\n' "$n" "$(head -3 "$PRUEBAS_DCOPIA/dconf-fugas.txt" | tr '\n' ' ')"
    exit 2
  fi
  case $r in
    0) printf '  ✓ %-28s %3ss\n' "$n" "$seg" ;;
    77) printf '  – %-28s saltado: %s\n' "$n" "$(tail -1 "$RES/$n.log")" ;;
    124) printf '  ✗ %-28s se pasó de %ss\n' "$n" "${limite:-120}"; tail -5 "$RES/$n.log" | sed 's/^/      /' ;;
    *) printf '  ✗ %-28s\n' "$n"; tail -5 "$RES/$n.log" | sed 's/^/      /' ;;
  esac
done | tee "$RES/resumen.txt"

# El conteo sale del resumen (el for corre en el subshell del tee).
FALLAN=$(grep -c '^  ✗' "$RES/resumen.txt" || true)
printf '  %s bien, %s fallan, %s saltados\n' "$(grep -c '^  ✓' "$RES/resumen.txt")" "$FALLAN" \
  "$(grep -c '^  –' "$RES/resumen.txt")" | tee -a "$RES/resumen.txt"
[ "$FALLAN" = 0 ]
