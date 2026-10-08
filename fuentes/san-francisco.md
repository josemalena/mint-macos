# San Francisco en Cinnamon (desde el disco del Mac Mini)

**Los archivos de la fuente nunca entran a este repo.** Es público y San
Francisco es de Apple: su licencia limita el uso a sus sistemas operativos.
José decidió usarla en este host de forma local (07-10-2026). Aquí queda solo
cómo se instala; si no está instalada, el repo sigue con Inter.

## De dónde sale

- **La buena para la interfaz: la fuente de sistema de macOS**, `SFNS.ttf`
  (variable, con los grados de tamaño óptico de Text y Display), más
  `SFNSItalic.ttf`, `SFNSMono.ttf` y `SFNSMonoItalic.ttf`. Está en
  `/System/Library/Fonts/` del **volumen del sistema** del Mac (el 5,
  «MacMini»), no en el de datos que se monta de costumbre (el 1).
- Las `SF-Pro-Display-*.otf` de `~/Library/Fonts` del Mac son solo la variante
  Display (para tamaños grandes): a 10 pt se ve apretada. No son la buena.

## Pasos

```bash
# 1. Montar el volumen del sistema del Mac, en solo lectura, en una carpeta temporal
mkdir -p /tmp/macsys
fsapfsmount -f 5 /dev/sdb2 /tmp/macsys &   # ver ../apfs para fsapfsmount
sleep 5

# 2. Copiar las cuatro fuentes a las del usuario y desmontar
mkdir -p ~/.local/share/fonts/san-francisco
cp /tmp/macsys/System/Library/Fonts/{SFNS.ttf,SFNSItalic.ttf,SFNSMono.ttf,SFNSMonoItalic.ttf} \
   ~/.local/share/fonts/san-francisco/
fusermount -u /tmp/macsys
fc-cache -f ~/.local/share/fonts

# 3. Ponerla en la interfaz, las barras de título y Nemo
#    (el nombre de la familia lleva un punto delante: «.SF NS»)
gsettings set org.cinnamon.desktop.interface font-name ".SF NS 10"
gsettings set org.gnome.desktop.interface font-name ".SF NS 10"
gsettings set org.gnome.desktop.interface document-font-name ".SF NS 10"
gsettings set org.cinnamon.desktop.wm.preferences titlebar-font ".SF NS Semibold 10"
gsettings set org.gnome.desktop.wm.preferences titlebar-font ".SF NS Semibold 10"
gsettings set org.nemo.desktop font ".SF NS 10"

# 4. Que Nemo no ponga la columna de fechas en letra monoespaciada
gsettings set org.nemo.preferences date-font-choice "no-mono"
```

Para volver a Inter: los mismos `gsettings` con `"Inter 10"` (títulos:
`"Inter Semi-Bold 10"`) y `date-font-choice "auto-mono"`.

## Notas

- `fc-match ".SF NS"` responde `SFNS.ttf: "System Font"`: el primer nombre de la
  familia es «System Font», pero en gsettings se usa «.SF NS», que no se
  confunde con nada.
- La fuente monoespaciada del sistema no se cambia (se queda en la de Mint).
