# caso: el Notification Center tiene la pestaña Today con la fecha y el clima (servicio org.mintmacos.Hoy1), el pie con Edit y el
# engranaje, y ⌥ + clic alterna No molestar
# límite: 120
# gestor: cinnamon-notificaciones
prueba() {
  requiere mac-ventanas gdbus
  lanzar mac-ventanas --residente   # el servicio org.mintmacos.Hoy1 vive en el residente de ventanas (ya no hay mac-hoy)
  lanzar python3 "$MINT_MACOS_REPO/pruebas/ayudantes/calendario-falso.py"
  sleep 1
  ev() { gdbus call --session --dest org.Cinnamon --object-path /org/Cinnamon --method org.Cinnamon.Eval "$1" 2>&1; }
  local a="imports.ui.appletManager.getRunningInstancesForUuid('notificaciones@macos')[0]"
  local r; r="$(ev "$a ? 'ok' : 'sin-applet'")"
  case "$r" in *"'\"ok\"'"*|*ok*) ;; *) falla "no hay applet notificaciones@macos: $r" ;; esac
  ev "$a._mostrarPestana('today'); 'ok'" >/dev/null
  local clima=""
  for _ in $(seq 20); do
    sleep 1
    ev "$a._pedirHoy(); 'ok'" >/dev/null
    sleep 1
    r="$(ev "String($a._climaListo)")"
    case "$r" in *true*) clima=1; break ;; esac
  done
  paso "fecha: $(ev "$a._fecha.get_text()")"
  [ -n "$clima" ] || falla "no llegó el clima por org.mintmacos.Hoy1 (¿sin red?): $r"
  r="$(ev "$a._widgets.get_n_children()")"
  case "$r" in *"2"*) paso "widgets de Calendar y clima en Today" ;; *) falla "Today no trae Calendar y el clima (2 widgets): $r" ;; esac
  # El panel abierto, para mirarlo.
  ev "$a._ajustarAlto(); $a.menu.open(false); 'ok'" >/dev/null
  sleep 1
  captura notification-center-today
  ev "$a._mostrarPestana('notifications'); 'ok'" >/dev/null
  sleep 1
  captura notification-center-notifications
  ev "$a.menu.close(false); 'ok'" >/dev/null
  # No molestar: el ajuste de Cinnamon se invierte.
  local antes; antes="$(gsettings get org.cinnamon.desktop.notifications display-notifications)"
  ev "$a._alternarNoMolestar(); 'ok'" >/dev/null
  sleep 1
  local despues; despues="$(gsettings get org.cinnamon.desktop.notifications display-notifications)"
  [ "$antes" != "$despues" ] || falla "No molestar no cambió el ajuste ($antes)"
  ev "$a._alternarNoMolestar(); 'ok'" >/dev/null
}
