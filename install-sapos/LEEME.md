# install-sapos

Todo lo de instalar sapOS en una Mac: la imagen, la memoria USB, el ícono y el nombre del disco
en el arranque, y el instalador de un solo paso.

| Archivo | Qué hace |
|---|---|
| `instalar-todo.sh` | **Un solo paso**, después de instalar Mint desde la memoria. Hace los drivers de la Mac (Wi-Fi Broadcom desde el ISO, sin internet; sensores; abanico con mbpfan), conecta el Wi-Fi si hace falta, y corre `instalar-aqui.sh`, los acentos con ⌥ (teclado en inglés), `silencio.sh` y el ícono y el nombre del disco. |
| `icono-disco.sh` | El ícono (`.VolumeIcon.icns`) y el nombre (`.disk_label`) del Startup Manager (⌥ al encender), en la EFI de esta máquina o en una memoria (`--disco sdX`, solo extraíbles). `--etiqueta "Texto"`, `--simular` y `--deshacer`. |
| `etiqueta-disco.py` | Arma `.disk_label` y `.disk_label_2x` sin bless: cada píxel es un índice de la paleta de la Mac (16 tonos), no el gris. |
| `ventoy/` | `ventoy.json` y `grub.cfg` de la memoria: Mint directo, sin menús ni texto. En la MacBook5,1 el ISO solo arranca en modo GRUB2, y por eso va con `.vtgrub2` en el nombre. |
| `macbook/acentos-option.sh` | ⌥e + vocal y ⌥n + n con teclado en inglés, por keyd, sin tocar los demás atajos de ⌥. |
| `imagen/` | La ISO propia de mint-macos (`construir.sh`, sin probar). |

Lo que lleva la manzana (`icono-disco.png`, `.VolumeIcon.icns`), las etiquetas que sacó bless y
lo viejo (`viejos/`) se quedan locales: `.gitignore` los bloquea.

**La memoria «Install sapOS»** (Ventoy 1.0.99): el ISO renombrado con `.vtgrub2`, `ventoy/` en
la raíz, el paquete en `mint-macos-paquete/`, y el ícono y el nombre puestos con
`./icono-disco.sh --disco sdX --etiqueta "Install sapOS"`.
