# caso: Muelle, la primera vez, trae la configuración de Plank (lanzadores, temas y dconf) sin tocar lo viejo, y deja un respaldo del dconf
# límite: 90
prueba() {
  despejar_pantalla
  requiere muelle dconf
  local esq; esq="$(dirname "$(command -v muelle)")/../esquemas"
  [ -d "$esq" ] && export GSETTINGS_SCHEMA_DIR="$esq"
  # Un Muelle de otro caso de la misma corrida (el 69) ya dejó su carpeta y la marca: se parte de cero.
  rm -rf "$XDG_CONFIG_HOME/muelle" "$XDG_DATA_HOME/muelle"
  dconf reset -f /org/mintmacos/muelle/
  # Lo de antes, con el nombre viejo: un lanzador, un tema y la clave del tema en dconf.
  mkdir -p "$XDG_CONFIG_HOME/plank/dock1/launchers" "$XDG_DATA_HOME/plank/themes/Prueba"
  mkdir -p "$XDG_DATA_HOME/applications"
  printf '[Desktop Entry]\nType=Application\nName=Prueba\nExec=true\nIcon=xed\n' > "$XDG_DATA_HOME/applications/prueba.desktop"
  printf '[PlankDockItemPreferences]\nLauncher=file://%s/applications/prueba.desktop\n' "$XDG_DATA_HOME" > "$XDG_CONFIG_HOME/plank/dock1/launchers/xed.dockitem"
  printf '[PlankTheme]\nTopRoundness=7\n' > "$XDG_DATA_HOME/plank/themes/Prueba/dock.theme"
  dconf write /net/launchpad/plank/docks/dock1/theme "'Prueba'"
  # (sin dock-items en dconf, Plank barre los lanzadores que no conoce: la clave viaja con la migración)
  dconf write /net/launchpad/plank/docks/dock1/dock-items "['xed.dockitem']"
  lanzar muelle
  esperar_ventana '^[Mm]uelle$' 30 >/dev/null
  sleep 2
  [ -f "$XDG_CONFIG_HOME/muelle/dock1/launchers/xed.dockitem" ] || falla "no trajo el lanzador a ~/.config/muelle"
  [ -f "$XDG_DATA_HOME/muelle/themes/Prueba/dock.theme" ] || falla "no trajo el tema a ~/.local/share/muelle"
  [ "$(dconf read /org/mintmacos/muelle/docks/dock1/theme)" = "'Prueba'" ] || falla "no trajo el dconf: $(dconf read /org/mintmacos/muelle/docks/dock1/theme)"
  ls "$XDG_DATA_HOME/mint-macos/respaldos/"plank-dconf-*.ini >/dev/null 2>&1 || falla "no dejó el respaldo del dconf"
  [ -f "$XDG_CONFIG_HOME/muelle/.migrado-de-plank" ] || falla "no dejó la marca de migración"
  paso "trajo lanzadores, temas y dconf, con respaldo y marca"
  # Lo viejo sigue igual: volver atrás es arrancar el plank de antes.
  [ -f "$XDG_CONFIG_HOME/plank/dock1/launchers/xed.dockitem" ] || falla "borró el lanzador viejo"
  [ "$(dconf read /net/launchpad/plank/docks/dock1/theme)" = "'Prueba'" ] || falla "tocó el dconf viejo"
  paso "lo de Plank quedó intacto"
}
