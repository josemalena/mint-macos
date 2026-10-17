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

## Notas

- Los estilos van por clases CSS (`.mac-caja`), no por id (`#mac-caja`): en Vala el nombre del widget no llegaba al selector.
- Nada de Apple en el repo: la fuente «.SF NS» y los íconos se generan en local.
