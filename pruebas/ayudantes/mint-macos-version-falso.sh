#!/bin/sh
# mint-macos-version de mentira para las pruebas: versiones inventadas y un registro de lo que se le pide.
case "$1" in
  --lista) printf 'prueba-1.0   macOS Prueba 1.0\nprueba-2.0   macOS Prueba 2.0  (falta: medidas)\n' ;;
  --poner) echo "poner $2" >> "${MINT_VERSION_REGISTRO:-/dev/null}" ;;
  *) printf 'activa: prueba-1.0\nescogida: prueba-1.0\n' ;;
esac
