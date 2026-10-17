# Pruebas de tareas reales

Lo que se hace todos los días con la Mac, repetido por un guion antes de cada
paquete: abrir apps y archivos, la Trash, las capturas, ⌘Tab, Force Quit, las
preferencias. `armar.sh` las corre con lo recién compilado; a mano:

```
pruebas/correr.sh                  # todos los casos, en un Xephyr aparte
pruebas/correr.sh 20 captura       # solo esos (el principio del número, o parte del nombre)
pruebas/correr.sh --lista          # qué casos hay
pruebas/correr.sh --pantalla-real  # en :0, con gui-lock y sin mandar teclas
```

Los resultados (el registro de cada caso, sus capturas y `resumen.txt`) quedan
en `~/.cache/mint-macos/pruebas/resultados`.

## Qué aísla

Cada corrida tiene su propio X (una copia de Xephyr con otro nombre, para que
un `pkill Xephyr` ajeno no la mate), su Muffin, su bus de D-Bus y un HOME con
sus `XDG_*`, exportados **antes** de arrancar el bus: si no, el dconf del bus
de prueba escribe en el de José (pasó el 10-10 y el 17-10-2026). Antes del
primer caso se comprueba que el dconf de prueba escribe donde debe, y al final
que el de José no cambió. Todo proceso que lleva la marca de la corrida en su
entorno se cierra al terminar, también lo que el bus activó (gvfs, portales).

El HOME de prueba empieza vacío: las apps salen con el tema de fábrica, no con
Constanza. Un caso que necesite un ajuste lo pone él mismo con `gsettings`.

En `--pantalla-real` las ventanas se abren en la pantalla de José, con el turno
de `gui-lock`, y los casos que necesitan teclado se saltan: a :0 no se mandan
teclas.

## Escribir un caso

Un archivo `casos/NN-nombre.sh` que define `prueba()`. El número da el orden.
Las dos primeras líneas dicen qué prueba y cuánto puede tardar; una tercera,
opcional, el gestor de ventanas:

```bash
# caso: mandar un archivo a la Trash y verlo en la ventana Trash de Fynder
# límite: 90
prueba() {
  requiere gio fynder
  local f="$HOME/Desktop/para la Trash.txt"
  mkdir -p "$(dirname "$f")"; echo hola > "$f"
  gio trash "$f"
  comprobar "está en la Trash" test -f "$XDG_DATA_HOME/Trash/files/para la Trash.txt"
  lanzar fynder trash:///
  local v; v="$(esperar_ventana '[Ff]ynder' 30)"
  esperar_texto "$v" "para la Trash.txt" 20
  captura trash
  cerrar_ventana "$v"
  esperar_sin_ventana "$v" 10
}
```

Sin `# gestor:` el caso corre con Muffin solo. Con `# gestor: cinnamon` corre
dentro de Cinnamon entero, con el panel y las extensiones `*@macos` del repo
(habilitada `cmdtab@macos`) y sin animaciones: es para lo que vive dentro del
shell, como ⌘Tab. Arrancarlo tarda unos segundos, y solo se cambia de gestor
cuando el caso siguiente pide otro, así que conviene numerar juntos los de
Cinnamon. En `--pantalla-real` la línea no cuenta: ahí está el Cinnamon de José.

Las ayudas están en `lib.sh`, con su uso al principio: `requiere`, `saltar`,
`falla`, `comprobar`, `lanzar`, `esperar_ventana`, `esperar_sin_ventana`,
`titulo`, `esperar_texto` (lee lo que muestra la ventana por accesibilidad,
AT-SPI, sin clics), `cerrar_ventana`, `teclas` (solo en Xephyr), `captura`.

Un caso pasa si `prueba` termina bien, falla en la primera comprobación que no
se cumple, y se salta (sale con 77) si no aplica. Lo que lanzó se cierra al
terminar aunque falle.

Un caso tiene que poder fallar: antes de darlo por bueno, se rompe a propósito
(otro nombre de archivo, otro título) y se mira que falle.
