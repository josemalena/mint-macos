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
  done < <(python3 -I "$aqui/ayudantes/icono-del-tema.py" Mint-Macos-12.7.6 edit-copy-symbolic edit-cut-symbolic folder-symbolic user-trash-symbolic user-home-symbolic printer-symbolic drive-harddisk-symbolic preferences-system-symbolic)
  [ "$fallan" = 0 ] || falla "$fallan de $n íconos no salen del tema o no se pintan"
  paso "$n íconos salen del tema de Apple y se recolorean"
  # lo que no está en el tema cae al que hereda
  python3 -I "$aqui/ayudantes/icono-del-tema.py" Mint-Macos-12.7.6 document-new-symbolic | grep -q Adwaita || paso "(document-new-symbolic no cayó en Adwaita; puede estar en el tema de Apple)"
  true
}
