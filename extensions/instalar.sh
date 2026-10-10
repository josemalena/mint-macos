#!/bin/bash
# Las extensiones de Cinnamon de mint-macos.
#
#   ./instalar.sh              copia las extensiones a ~/.local/share/cinnamon/extensions
#   ./instalar.sh --encender   además las enciende (enabled-extensions), sin
#                              apagar las que ya estén encendidas
#
# Hoy: cmdtab@macos, el ⌘Tab de Catalina. Encendida reemplaza el selector de
# Cinnamon; apagada (o con volver.sh) vuelve el de Cinnamon.
#
# Respalda enabled-extensions y deja volver.sh en
# ~/.local/share/respaldos/extensiones-<fecha>/.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
DESTINO="$HOME/.local/share/cinnamon/extensions"
EXTENSIONES=(cmdtab@macos)
ENCENDER=false
[ "${1:-}" = "--encender" ] && ENCENDER=true

RESPALDO="$HOME/.local/share/respaldos/extensiones-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESPALDO" "$DESTINO"
antes="$(gsettings get org.cinnamon enabled-extensions)"
echo "$antes" > "$RESPALDO/enabled-extensions.txt"

for e in "${EXTENSIONES[@]}"; do
  [ -d "$DESTINO/$e" ] && cp -a "$DESTINO/$e" "$RESPALDO/$e.anterior"
  rm -rf "$DESTINO/$e"
  cp -a "$AQUI/$e" "$DESTINO/$e"
done

cat > "$RESPALDO/volver.sh" <<EOF
#!/bin/bash
# Deja las extensiones como estaban antes de $(date '+%d-%m-%Y %H:%M').
gsettings set org.cinnamon enabled-extensions "$antes"
$(for e in "${EXTENSIONES[@]}"; do
    echo "rm -rf \"$DESTINO/$e\""
    echo "[ -d \"$RESPALDO/$e.anterior\" ] && cp -a \"$RESPALDO/$e.anterior\" \"$DESTINO/$e\""
  done)
echo "Listo: el ⌘Tab vuelve a ser el de Cinnamon."
EOF
chmod +x "$RESPALDO/volver.sh"

if $ENCENDER; then
  nueva="$(python3 - "$antes" "${EXTENSIONES[@]}" <<'PY'
import ast, sys
txt = sys.argv[1].replace("@as ", "")
lista = ast.literal_eval(txt) if txt.strip() else []
for e in sys.argv[2:]:
    if e not in lista:
        lista.append(e)
print(str(lista))
PY
)"
  gsettings set org.cinnamon enabled-extensions "$nueva"
  echo "Extensiones encendidas: $nueva"
else
  echo "Extensiones copiadas (sin encender): ${EXTENSIONES[*]}"
fi
echo "Respaldo y vuelta atrás: $RESPALDO/volver.sh"
