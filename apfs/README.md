# Leer un disco APFS de una Mac

El kernel de Linux no trae APFS. Esto lo resuelve con **fsapfsmount**
(libfsapfs, de libyal): un montaje por FUSE en **solo lectura**, que es lo
seguro para un disco con datos de una Mac.

## Requisitos

- Paquetes: `build-essential autoconf automake autopoint libtool pkg-config
  libssl-dev libfuse3-dev fuse3 curl` (los instala el script). Sin
  `libssl-dev`, la lectura falla con *unable to set padding in context*.
  No usar el `libfsapfs` de apt: está viejo y roto con OpenSSL 3.
- `user_allow_other` activo en `/etc/fuse.conf`, para montar desde Nemo.
- Opcional: el usuario en el grupo `disk`, para montar a mano sin `sudo`.
- libfsapfs **20260921**, compilado desde la versión publicada; no está en
  los repositorios de Mint. Otra versión: `LIBFSAPFS_VERSION=… ./instalar-fsapfs.sh`.
- Para el montaje automático, el disco en el `fstab` con `fstype=fsapfs`.

## Instalar

```bash
./instalar-fsapfs.sh
```

Compila e instala `fsapfsinfo` y `fsapfsmount` en `/usr/local/bin`, copia
`mount.fsapfs` a `/sbin` (el que llama `mount` cuando el fstab dice
`fsapfs`), activa `user_allow_other` y te agrega al grupo `disk`.

## Montar

Un contenedor APFS trae varios volúmenes, y los datos no están en el
primero. Hay que decir cuál con `-f`; si no, falla con
`mount_handle_open: invalid volume index value out of bounds`.

```bash
fsapfsinfo /dev/sdb2                       # lista los volúmenes
fsapfsmount -f 1 /dev/sdb2 ~/macmini-ro    # a mano, sin sudo si estás en el grupo disk
```

Automático y en Nemo: la línea de `fstab.ejemplo` en `/etc/fstab` (con el
UUID de `lsblk -o NAME,FSTYPE,UUID`) y luego `sudo systemctl daemon-reload`.
Se monta solo al primer acceso, y en Nemo aparece como «MacMini - Data»
con clic para montar. El volumen se elige en `mount.fsapfs` (`-f 1`).

| Error | Causa | Arreglo |
|---|---|---|
| *option allow_other only allowed if 'user_allow_other' is set* | Montaste desde Nemo (como usuario) y falta la línea en `/etc/fuse.conf` | `sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf` |
| *invalid volume index value out of bounds* | No se dijo qué volumen del contenedor | `-f 1` (o el que diga `fsapfsinfo`) |
| *unable to set padding in context* | libfsapfs sin OpenSSL o el de apt | Reinstalar con `./instalar-fsapfs.sh` |
| *Transport endpoint is not connected* | El proceso FUSE murió | `./recuperar.sh` |

## Cuando se cuelga

Si el proceso FUSE muere, systemd sigue diciendo que está montado y la
carpeta responde *Transport endpoint is not connected*. No se arregla
solo:

```bash
./recuperar.sh                  # /media/$USER/MacMini por defecto
./recuperar.sh /otro/punto
```

## Por qué fsapfsmount y no el módulo del kernel

Hay un módulo con escritura experimental, linux-apfs-rw, pero hay que
recompilarlo con cada kernel nuevo (en esta computadora quedó compilado
para el 6.17 y no carga en el 7.0) y su propio README advierte riesgo de
corromper datos. fsapfsmount no depende del kernel y en solo lectura no
puede dañar el disco de la Mac: es el único camino que se usa aquí.
