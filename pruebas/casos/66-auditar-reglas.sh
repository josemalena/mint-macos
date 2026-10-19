# caso: las reglas de mac-visor-nib auditar (texto, menús, geometría) con datos inventados, y el extractor de menús por org.mintmacos.Menu1
# contra xed
# límite: 90
prueba() {
  requiere python3 xed mac-menu gdbus xdotool
  local a="$MINT_MACOS_REPO/herramientas/visor-nib"
  python3 -I "$a/auditar/prueba.py" > "$PRUEBAS_RES/$PRUEBAS_CASO-reglas.txt" 2>&1 || falla "las reglas fallan: $(tail -3 "$PRUEBAS_RES/$PRUEBAS_CASO-reglas.txt")"
  paso "reglas: $(grep -c '^✓' "$PRUEBAS_RES/$PRUEBAS_CASO-reglas.txt") comprobaciones"
  export GTK_MODULES="${GTK_MODULES:-appmenu-gtk-module}"
  lanzar mac-menu
  sleep 1
  lanzar xed
  local w; w="$(esperar_ventana '[Xx]ed' 30)"
  sleep 2
  local r; r="$(cd "$a" && python3 -I -c "
import sys; sys.path.insert(0, '.')
from auditar import nuestro, menus
n = nuestro.de_menu1($w)
print([m['texto'] for m in n['menus']])
mac = {'menus': [{'texto': 'Edit', 'items': [{'texto': 'Undo', 'atajo': '⌘Z'}, {'texto': 'Cut', 'atajo': '⌘X'}, {'texto': 'Inexistente', 'atajo': ''}]}]}
f = menus.revisar(mac, n)
print([(x['que'], x['gravedad']) for x in f])
" 2>&1)"
  paso "menús de xed: $r"
  case "$r" in *"'File'"*"'Edit'"*) ;; *) falla "de_menu1 no trajo File y Edit: $r" ;; esac
  case "$r" in *"Inexistente"*"falta"*) paso "la regla ve lo que falta" ;; *) falla "la regla no marcó «Inexistente» como falta: $r" ;; esac
}
