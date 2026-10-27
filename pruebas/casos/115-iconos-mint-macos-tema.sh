# caso: el tema de íconos Mint-Macos-<versión> (glifos de Apple, car-mac «simbolos») lo resuelve GTK3: los 40 de la tabla salen de él y se recolorean
# límite: 90
# Los glifos son de Apple y no van al repo: se toman de las referencias de la máquina (se salta si no están) y se instalan en el HOME de prueba.
prueba() {
  requiere python3 gtk-update-icon-cache
  local aqui; aqui="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  local ref; ref="$(ls -d "$PRUEBAS_HOME_REAL"/.local/share/mint-macos/referencias/simbolos-*/12.7.6/*/iconos-simbolicos/Mint-Macos-12.7.6 2>/dev/null | tail -1 || true)"
  [ -n "$ref" ] || saltar "no están los glifos de 12.7.6 en las referencias (paso «simbolos» de car-mac)"
  python3 -I "$aqui/../iconos/construir-tema-macos.py" 12.7.6 --origen "$ref" --hereda Adwaita | paso "$(cat)"
  local tsv="$aqui/../extraer-mac/simbolos-freedesktop.tsv" fallan=0 n=0 nombre ruta tinta
  [ -f "$tsv" ] || falla "falta $tsv"
  # (una muestra de la tabla: nombres de cada contexto)
  while read -r nombre ruta tinta; do
    n=$((n + 1))
    case "$ruta" in */Mint-Macos-12.7.6/*) ;; *) paso "no sale del tema: $nombre → $ruta"; fallan=$((fallan + 1)) ;; esac
    [ "$tinta" -gt 5 ] || { paso "no se recolorea: $nombre ($tinta px)"; fallan=$((fallan + 1)); }
  done < <(python3 -I "$aqui/ayudantes/icono-del-tema.py" Mint-Macos-12.7.6 edit-copy-symbolic edit-cut-symbolic drive-harddisk-symbolic preferences-system-symbolic)
  [ "$fallan" = 0 ] || falla "$fallan de $n íconos no salen del tema o no se pintan"
  paso "$n íconos salen del tema de Apple y se recolorean"
  # la salida de extraer-mac de la máquina del usuario (<SAL>/iconos-simbolicos/Mint-Macos-<versión>): con --salida y con MINT_MACOS_SALIDA
  local sal="$PRUEBAS_RES/sal"; rm -rf "$sal"; mkdir -p "$sal/iconos-simbolicos"; cp -r "$ref" "$sal/iconos-simbolicos/"
  rm -rf "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6"
  python3 -I "$aqui/../iconos/construir-tema-macos.py" 12.7.6 --salida "$sal" --hereda Adwaita > /dev/null || falla "--salida no encontró el tema"
  [ -f "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6/index.theme" ] || falla "--salida no instaló"
  rm -rf "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6"
  MINT_MACOS_SALIDA="$sal" python3 -I "$aqui/../iconos/construir-tema-macos.py" 12.7.6 --hereda Adwaita > /dev/null || falla "MINT_MACOS_SALIDA no encontró el tema"
  paso "la salida de extraer-mac se acepta con --salida y con MINT_MACOS_SALIDA"
  # los glifos no tapan los íconos regulares del tema de la versión: una carpeta pide [inode-directory, folder, folder-symbolic] y GTK3 busca tema por tema
  # con todos los nombres, así que un folder-symbolic en este tema ganaría a la carpeta regular del padre (pasó el 27-10-2026 con Constanza)
  local padre="$XDG_DATA_HOME/icons/PadreRegular"; rm -rf "$padre" "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6"
  mkdir -p "$padre/48x48/places"
  printf '[Icon Theme]\nName=PadreRegular\nDirectories=48x48/places\n[48x48/places]\nSize=48\nContext=Places\nType=Fixed\n' > "$padre/index.theme"
  python3 -c "import base64,sys;sys.stdout.buffer.write(base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='))" > "$padre/48x48/places/folder.png"
  python3 -I "$aqui/../iconos/construir-tema-macos.py" 12.7.6 --origen "$ref" --hereda PadreRegular > /dev/null || falla "no construyó sobre PadreRegular"
  [ -z "$(find "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6/scalable" -name 'folder-symbolic.svg' 2>/dev/null)" ] || falla "el glifo folder-symbolic se instaló y taparía la carpeta regular del tema padre"
  [ -n "$(find "$XDG_DATA_HOME/icons/Mint-Macos-12.7.6/scalable" -name 'edit-copy-symbolic.svg' 2>/dev/null)" ] || falla "se quitaron también glifos sin ícono regular (edit-copy-symbolic)"
  paso "los glifos con ícono regular en el tema de la versión no se instalan (la carpeta sigue siendo la del tema)"
  rm -rf "$padre"
  # lo que no está en el tema cae al que hereda
  python3 -I "$aqui/ayudantes/icono-del-tema.py" Mint-Macos-12.7.6 document-new-symbolic | grep -q Adwaita || paso "(document-new-symbolic no cayó en Adwaita; puede estar en el tema de Apple)"
  true
}
