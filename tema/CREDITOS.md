# Créditos de Constanza

Constanza es un tema para Linux Mint (Cinnamon) con la apariencia del Finder
oscuro de macOS. Se arma sobre trabajo de otros, que se descarga y se compila
en cada instalación en vez de copiarse a este repo:

| Pieza | Autor | Licencia | Cómo se usa |
|---|---|---|---|
| [Mojave-gtk-theme](https://github.com/vinceliuice/Mojave-gtk-theme) (commit `eff1025`) | Vince Liuice | GPL-3.0 | Base del tema GTK 2/3/4, del panel de Cinnamon, de los bordes de ventana (metacity-1) y del dock de Plank. Se clona y se compila con su instalador; su `COPYING` viaja dentro del tema instalado. |
| [McMojave-circle](https://github.com/vinceliuice/McMojave-circle) | Vince Liuice | GPL-3.0 | Solo el tema de cursores (`McMojave-cursors`), base de los cursores de Catalina. Los íconos ya no salen de aquí. |

Desde el 14-10-2026 el tema de íconos Constanza ya no hereda de Os-Catalina, McMojave ni WhiteSur:
lo que no sale del disco de la Mac ni del logo de cada app cae a Adwaita, gnome y hicolor.

Lo propio de Constanza (`gtk/_constanza.scss` y los guiones) va con la misma
licencia, GPL-3.0.

## Lo de Apple no está aquí

Los íconos del Finder (CoreTypes.bundle, las extensiones de almacenamiento) y
las fuentes San Francisco son de Apple. Este repo **no** los contiene: los
guiones los leen del disco de una Mac conectado a esta misma computadora y los
convierten en local, para uso personal. Sin ese disco, Constanza se queda con
los logos de las apps, Adwaita e Inter.
