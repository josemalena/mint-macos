# nativo/: las ventanas de mint-macos en Vala + GTK3

Fase 1 del paso de Python a binario (decisión de José, 16-10-2026): las ventanas en Vala + GTK3 y, más adelante, los
ayudantes de root y los servicios en Rust, en un solo proyecto con meson.

- `libmacos/`: lo común. `estilo.vala` (el CSS de las alertas de Catalina y su carga), `iconos.vala` (los íconos dibujados con
  cairo) y `alerta.vala` (la base: ventana sin marco con sombra, caja, franja y un `Gtk.Fixed` donde cada pieza va en su píxel).
- `sesion/`: `mac-sesion`, los diálogos de sesión (Log Out, Restart, Shut Down y el aviso del invitado). Mismos argumentos y
  misma salida JSON que `applets/applemenu@macos/applemenu.py --mode …`:

      mac-sesion --mode restart [--seconds 60] [--print-json] [--prueba]

  `--prueba` enseña el diálogo y no ejecuta nada. Force Quit sigue en Python.

- `polkit/`: `mac-polkit`, el agente de polkit estilo Catalina (hereda `PolkitAgent.Listener`; el de Python no podía). Mismo
  aspecto que `polkit/agente.py` (0 píxeles distintos en el diálogo genérico y en la variante de Restart). Necesita
  `libpolkit-agent-1-dev` para compilar; sin ella se compila todo lo demás. El supervisor `mint-macos-polkit` usa el binario
  si está en `~/.local/bin`; `instalar.sh --python` lo quita y vuelve al de Python. En la Mac el botón genérico es «OK».

- `forcequit/`: `mac-forcequit`, la ventana «Force Quit Applications» con las medidas de la captura de Catalina
  (`15-force-quit-oscuro`): lista de 298 × 168 con filas de 22 px, botón «Force Quit» o «Relaunch» (con Fynder, el Finder de
  aquí), flechas y Enter, y la lista se actualiza sola al abrirse o cerrarse ventanas (libwnck). `--prueba` no mata nada.
  `applets/applemenu@macos/forcekill.py` lo usa si está instalado (⌥⌘⎋ y Apple ▸ Force Quit…); `instalar.sh --python` lo quita.

- `launchpad/`: `mac-launchpad-vala`, el Launchpad de Catalina residente (mismo id de aplicación que el de Python: solo uno
  de los dos es el residente). Port fiel de `launchpad/launchpad.py`, con las medidas de las capturas de Catalina del 14-10-2026.
  `--png ARCHIVO [--pagina N] [--consulta T] [--carpeta]` pinta un cuadro sin tocar el bus de sesión; `--lista` imprime lo que
  mostraría. `launchpad/instalar.sh` deja el comando `mac-launchpad`, que solo usa el binario si José lo activó:
  `activar-launchpad.sh` deja el marcador `~/.config/mint-macos/launchpad-vala.activo` y cambia el residente; `--quitar` (o
  `instalar.sh --python`) lo devuelve a Python.

### Launchpad: lo que NO tiene fuente (se portó igual que en Python, anotado en vez de dado por bueno)
- «No Results» (texto, tamaño 26, 50 % de opacidad, a 300 px): ninguna captura de Catalina de una búsqueda sin resultados.
- El fundido de entrada de 0.18 s y la animación de las páginas (aproximación 0.22 por cuadro): las capturas son estáticas.
- El cursor de texto del buscador: no se dibuja; la captura de la búsqueda «s» (1.06.12) deja ver uno, y no se sabe si parpadea.
- El Dock (Plank) queda tapado por el Launchpad a pantalla completa; en las capturas de Catalina el Dock se ve encima.
- Tab no hace nada, arrastrar y la rueda de dos dedos cambian de página, el clic en el vacío esconde: sin captura que lo confirme.
- Modo de edición (íconos que tiemblan, borrar, crear carpetas arrastrando, nombre de carpeta editable): hay captura
  (`16-launchpad-edicion-oscuro`) pero ninguna del movimiento; no se implementó.

## Construir

    meson setup build && ninja -C build      # el binario queda en build/sesion/mac-sesion

Hace falta `valac`, `meson`, `ninja` y los paquetes de desarrollo de GTK 3 (`libgtk-3-dev`).

## Medido (Xephyr, 5 corridas, mediana; Python = applemenu.py --mode logoff --prueba)

|                                  | Python  | Vala    |
|----------------------------------|---------|---------|
| tiempo hasta que se ve la ventana| 269 ms  | 128 ms  |
| RSS con la ventana puesta        | 52.8 MB | 33.0 MB |

Los píxeles de los cuatro diálogos (Log Out, Restart, Shut Down e invitado) salen idénticos a los de la versión en Python
(0 píxeles distintos al comparar las capturas).

## Medido: agente de polkit (Xephyr, sesión de logind aparte; 5 corridas, mediana)

|                          | Python  | Vala    |
|--------------------------|---------|---------|
| RSS en reposo (residente)| 48.7 MB | 31.6 MB |
| pkexec hasta la ventana  | 109 ms  | 134 ms  |

El tiempo lo domina `pkexec` y polkitd, no el agente: sin ganancia. Lo que se gana es memoria, en un proceso que vive siempre.

## Medido: Force Quit (:0, mediana de 5, arranque en frío; Python = forcekill.py sin el residente)

|                                  | Python  | Vala    |
|----------------------------------|---------|---------|
| tiempo hasta que se ve la ventana| 1080 ms | 616 ms  |
| RSS con la ventana puesta        | 62.7 MB | 40.7 MB |

## Medido: Launchpad (Xephyr 1920×1200, bus propio, residente armado y oculto; Python = launchpad.py --residente)

Mediana de las corridas estables (3 de Python, 4 de Vala; 1 de Vala salió atípica a 103 MB de RSS tras reconstruirse el fondo).

|                                    | Python  | Vala    |
|------------------------------------|---------|---------|
| RSS en reposo (oculto)             | 76.8 MB | 54.5 MB |
| PSS en reposo (lo que cuesta de verdad) | 36.1 MB | 23.0 MB |
| PSS con el Launchpad mostrado      | 50.3 MB | 37.2 MB |
| Atajo (Activate) hasta que se ve   | ~25 ms  | ~25 ms  |

Los píxeles contra Python: 0 distintos (tolerancia 2 %) en las seis vistas probadas (página 1 y 2, búsqueda «s» y «safari», sin
resultados y carpeta Other); diferencia media 0.3 %, que viene del fondo (se desenfoca con otra librería). Contra Catalina se
comparó el diseño lado a lado (rejilla, buscador, resaltado, panel de la carpeta); el contenido de las apps es el de aquí.
Un arranque en frío cuesta más de 0.5 s (GTK 130-200 ms, datos y fondo 70-110 ms, íconos y texto 250-375 ms): por eso es residente.

## Notas

- Los estilos van por clases CSS (`.mac-caja`), no por id (`#mac-caja`): en Vala el nombre del widget no llegaba al selector.
- Nada de Apple en el repo: la fuente «.SF NS» y los íconos se generan en local.
