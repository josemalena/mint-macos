# Etiquetas del Finder

Saca las etiquetas del Finder de una carpeta del disco de la Mac, **en solo lectura**,
a una base local y oculta. No copia ningún archivo: solo los nombres de las etiquetas
y a qué ruta pertenece cada una.

```
./desde-mac.sh                                           # Users/<usuario-mac>/Documents
./desde-mac.sh --carpeta Users/jmalena/Documents --destino ARCHIVO
```

Por defecto deja `~/.local/share/mint-macos/etiquetas/etiquetas.json`. Si `MAC_DATOS`
ya apunta a la raíz del volumen de datos montado, se usa; si no, monta uno aparte en
solo lectura (como los demás `desde-mac.sh`).

## Qué lee de la Mac

- En cada archivo o carpeta, el atributo extendido `com.apple.metadata:_kMDItemUserTags`:
  una lista de «Nombre\nN», con N el color (0 ninguno, 1 gris, 2 verde, 3 morado,
  4 azul, 5 amarillo, 6 rojo, 7 naranja).
- El catálogo de la barra lateral del Finder (colores y si se ve), en
  `Library/SyncedPreferences/com.apple.finder.plist`, clave `FinderTagDict`.

## Qué deja

La **base de etiquetas** (formato v2): el catálogo y las etiquetas por ruta
**relativa a `$HOME`** («Documents/SISMO/Koralis»), para que valga esté Documents en
iCloud, en Data o donde sea. Si ya existe, se **mezcla** sin pisar lo etiquetado en
Linux. Un archivo que iCloud dejó en la nube (`.Nombre.icloud`) se guarda con su
nombre real.

## Por qué un archivo aparte y no el atributo

Ni iCloud Drive (rclone) ni el HDD (exFAT) guardan atributos extendidos, y un ext4
solo acepta `user.*`: `com.apple.metadata:…` no se puede escribir al copiar a Linux. La
base es la fuente de verdad; `user.xdg.tags` (la convención de Linux) va solo donde se
pueda. Quien las muestra (Fynder, la barra lateral con Tags) lee esta base.
