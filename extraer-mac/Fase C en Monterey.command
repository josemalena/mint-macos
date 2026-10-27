#!/bin/bash
# La ronda «fase C» (27-10-2026) en Monterey, con doble clic desde la sesión de la
# Mac. Por ssh no sirve: System Events da -600 y el guion para solo.
# Pide los permisos una vez y después corre las cinco secciones (FASE="A B C D E").
# Al final, fase-c/tubo.txt dice qué paquetes miden menos de 100 MB (van por scp)
# y fase-c/transporte.txt, los que van a la memoria TRANSPORTE (se copian solos a
# esta carpeta si es la memoria).
AQUI="$(cd "$(dirname "$0")" && pwd)"
SALIDA="${SALIDA:-$HOME/extraer-salida/macos$(sw_vers -productVersion)-fase-c-$(date +%Y%m%d)}"

echo "== Extraer Mac: fase C =="
echo
echo "Durará un buen rato y la pantalla va a cambiar de fondo, de modo claro/oscuro"
echo "y de «Reduce transparency». Todo vuelve como estaba al terminar, aunque algo falle."
echo "No toques la Mac mientras corre."
echo
read -r -p "Pulsa Enter para empezar (o cierra esta ventana para cancelar)… " _

cd "$AQUI" || { echo "No encuentro la carpeta extraer-mac."; exit 1; }
SALIDA="$SALIDA" FASE="${FASE:-A B C D E}" bash extraer.sh permisos fase-c
r=$?
echo
echo "extraer.sh terminó con código $r. La bitácora está en $SALIDA/herramientas/capturas.log"
[ -f "$SALIDA/fase-c/no-hecho.txt" ] && { echo; echo "Lo que no se hizo, y por qué:"; cat "$SALIDA/fase-c/no-hecho.txt"; }
for l in tubo transporte; do
  [ -s "$SALIDA/fase-c/$l.txt" ] && { echo; echo "Va por $l:"; sed "s|^|  $SALIDA/fase-c/|" "$SALIDA/fase-c/$l.txt"; }
done
echo
read -r -p "Pulsa Enter para cerrar… " _
