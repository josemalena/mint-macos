# nativo/: las ventanas de mint-macos en Vala + GTK3

Fase 1 del paso de Python a binario (decisión de José, 16-10-2026): las ventanas en Vala + GTK3 y, más adelante, los
ayudantes de root y los servicios en Rust, en un solo proyecto con meson.

- `libmacos/`: lo común. `estilo.vala` (el CSS de las alertas de Catalina y su carga), `iconos.vala` (los íconos dibujados con
  cairo) y `alerta.vala` (la base: ventana sin marco con sombra, caja, franja y un `Gtk.Fixed` donde cada pieza va en su píxel).
- `sesion/`: `mac-sesion`, los diálogos de sesión (Log Out, Restart, Shut Down y el aviso del invitado). Mismos argumentos y
  misma salida JSON que `applets/applemenu@macos/applemenu.py --mode …`:

      mac-sesion --mode restart [--seconds 60] [--print-json] [--prueba]

  `--prueba` enseña el diálogo y no ejecuta nada. Force Quit sigue en Python.

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

## Notas

- Los estilos van por clases CSS (`.mac-caja`), no por id (`#mac-caja`): en Vala el nombre del widget no llegaba al selector.
- Nada de Apple en el repo: la fuente «.SF NS» y los íconos se generan en local.
