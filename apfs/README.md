# Leer un disco APFS de una Mac

El kernel de Linux no trae APFS. Esto lo resuelve con **fsapfsmount**
(libfsapfs, de libyal): un montaje por FUSE en **solo lectura**, que es lo
seguro para un disco con datos de una Mac.

## Requisitos

- Paquetes: `build-essential autoconf automake autopoint libtool pkg-config
  libfuse3-dev fuse3 curl` (los instala el script).
- libfsapfs **20260921**, compilado desde la versión publicada; no está en
  los repositorios de Mint. Otra versión: `LIBFSAPFS_VERSION=… ./instalar-fsapfs.sh`.
- Para el montaje automático, el disco en el `fstab` con `fstype=fsapfs`.

## Instalar

```bash
./instalar-fsapfs.sh
```

Compila e instala `fsapfsinfo` y `fsapfsmount` en `/usr/local/bin`, y copia
`mount.fsapfs` a `/sbin`, que es el que llama `mount` cuando el fstab dice
`fsapfs`.

## Montar

Un contenedor APFS trae varios volúmenes, y los datos no están en el
primero. Hay que decir cuál con `-f`; si no, falla con
`mount_handle_open: invalid volume index value out of bounds`.

```bash
fsapfsinfo /dev/sdb2                       # lista los volúmenes
fsapfsmount -f 1 /dev/sdb2 ~/macmini-ro    # a mano, sin sudo si estás en el grupo disk
```

Automático al primer acceso: la línea de `fstab.ejemplo` en `/etc/fstab`
(con el UUID de `lsblk -o NAME,FSTYPE,UUID`) y luego
`sudo systemctl daemon-reload`. El volumen se elige en `mount.fsapfs`
(`-f 1` = «MacMini - Data»).

## Cuando se cuelga

Si el proceso FUSE muere, systemd sigue diciendo que está montado y la
carpeta responde *Transport endpoint is not connected*. No se arregla
solo:

```bash
./recuperar.sh                  # /media/$USER/MacMini por defecto
./recuperar.sh /otro/punto
```

## Escritura (no recomendada)

Existe un módulo del kernel con escritura experimental,
[linux-apfs-rw](https://github.com/linux-apfs/linux-apfs-rw) (v0.3.21). Hay
que recompilarlo con cada kernel nuevo (`linux-headers-$(uname -r)`, `make`,
o por DKMS) y su propio README advierte riesgo real de corromper datos. Para
un disco con información de la Mac, quedarse con fsapfsmount en solo
lectura.
