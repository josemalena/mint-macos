"""Decodificador de deepmap2 (compresión 11 de los Assets.car de CoreUI).

Traducción a Python del decodificador portable de carfile-go
(github.com/devcxm/carfile-go, codec/deepmap2/deepmap2.go, commit fd01818,
27-08-2026). Nada de la estructura se adivinó aquí: se sigue ese código, que
es la única implementación documentada que encontré (16-10-2026).

Entra lo que va después de la envoltura MLEC de 16 bytes (igual que en
carfile-go: Payload.Data[16:]) y sale (ancho, alto, formato, píxeles): bytes
apretados, sin relleno de fila, en el mismo orden que el camino LZFSE (BGRA
premultiplicado para ARGB, gris y alfa para GA8). Formatos: 1 gris, 2 gris y
alfa, 3 RGB, 4 BGRA, 20 de 16 bits por canal (RGBW).

Licencia del original (MIT):

    Copyright (c) 2026 devcxm

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the
    "Software"), to deal in the Software without restriction, including
    without limitation the rights to use, copy, modify, merge, publish,
    distribute, sublicense, and/or sell copies of the Software, and to permit
    persons to whom the Software is furnished to do so, subject to the
    following conditions:

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
    OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
    NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
    DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
    USE OR OTHER DEALINGS IN THE SOFTWARE.
"""
import struct

CRUDO, DEFECTO, SIN_PERDIDA, PALETA = 1, 2, 3, 4

# formato → (componentes, bytes por componente, con alfa)
FORMATOS = {1: (1, 1, False), 2: (2, 1, True), 3: (3, 1, False), 4: (4, 1, True), 20: (4, 2, True)}


class Error(ValueError):
    pass


def _bpp(f):
    c, b, _ = FORMATOS[f]
    return c * b


def _segmento(datos, esperado, lzfse):
    """Un flujo comprimido: LZFSE/LZVN con cabecera bvx, o LZVN suelto."""
    if datos[:4] in (b"bvx2", b"bvx-", b"bvxn", b"bvx1"):
        return lzfse(datos, max(esperado, 0) + 65536)
    if esperado <= 0:
        raise Error("segmento LZVN suelto sin tamaño esperado")
    # LZVN sin cabecera: se le pone la de bloque «bvxn» (bytes crudos, bytes
    # comprimidos) y el fin «bvx$» para que lo abra liblzfse.
    envuelto = b"bvxn" + struct.pack("<II", esperado, len(datos)) + datos + b"bvx$"
    return lzfse(envuelto, esperado + 65536)[:esperado]


def _segmentos(carga, primero, esperado, lzfse):
    """Trozos [largo u32][datos] encadenados; el primer largo va aparte."""
    salida, resto, largo = [], carga, primero
    total = 0
    while True:
        if largo == 0 or largo > len(resto):
            raise Error(f"segmento de {largo} bytes con {len(resto)} disponibles")
        dec = _segmento(resto[:largo], esperado - total, lzfse)
        salida.append(dec)
        total += len(dec)
        resto = resto[largo:]
        if not resto:
            return salida
        if len(resto) < 4:
            raise Error("largo de segmento cortado")
        largo = struct.unpack("<I", resto[:4])[0]
        resto = resto[4:]


def _bytes_defecto(ancho, alto, f):
    c, _, alfa = FORMATOS[f]
    r = c - 1 if alfa else c
    n = (ancho * alto if alfa else 0) + alto + 2 * r * ancho * alto
    return (n + 15) & ~15


def _filas_defecto(n, ancho, f):
    c, _, alfa = FORMATOS[f]
    r = c - 1 if alfa else c
    por_fila = (ancho if alfa else 0) + 1 + 2 * r * ancho
    filas = n // por_fila
    if filas == 0 or n - filas * por_fila >= 16:
        raise Error(f"no sale el número de filas de {n} bytes")
    return filas


def _i16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def _despredecir(fila, ant, pred):
    if pred == 0:
        return
    n = len(fila)
    if pred == 1:
        for k in range(3):
            fila[k] = _i16(fila[k] + ant[k])
        for i in range(3, n, 3):
            izq, arr, arr_izq = fila[i - 3], ant[i], ant[i - 3]
            base = ant if abs(arr - arr_izq) > abs(izq - arr_izq) else None
            for k in range(3):
                p = base[i + k] if base is not None else fila[i - 3 + k]
                fila[i + k] = _i16(fila[i + k] + p)
    elif pred == 2:
        for i in range(3, n):
            fila[i] = _i16(fila[i] + fila[i - 3])
    elif pred == 3:
        for i in range(n):
            fila[i] = _i16(fila[i] + ant[i])
    elif pred == 4:
        for k in range(3):
            fila[k] = _i16(fila[k] + ant[k])
        for i in range(3, n):
            s = fila[i - 3] + ant[i] + 1
            if s < 0:
                s += 1
            fila[i] = _i16(fila[i] + (s >> 1))


def _escala_ancha(v):
    if v < 0:
        return 0
    if v >= 512:
        return 10000
    return (v * 10000 + 256) // 512


def _pixeles_defecto(src, ancho, alto, f):
    c, b, alfa_si = FORMATOS[f]
    n = ancho * alto
    r = c - 1 if alfa_si else c
    nalfa = n if alfa_si else 0
    necesario = nalfa + alto + 2 * r * n
    if len(src) < necesario or len(src) - necesario >= 16:
        raise Error(f"datos por defecto: {len(src)} bytes, se esperaban {necesario}")
    alfa = src[:nalfa]
    pred = src[nalfa:nalfa + alto]
    alto_pl = src[nalfa + alto:nalfa + alto + r * n]           # byte alto primero
    bajo_pl = src[nalfa + alto + r * n:necesario]              # byte bajo y signo
    bpp = c * b
    sal = bytearray(n * bpp)
    ant = [0] * (ancho * 3)
    for y in range(alto):
        fila = [0] * (ancho * 3)
        base = y * ancho * r
        for x in range(ancho):
            for k in range(r):
                i = base + x * r + k
                cod = bajo_pl[i] | (alto_pl[i] << 8)
                v = cod >> 1
                fila[x * 3 + k] = -v if cod & 1 else v
        _despredecir(fila, ant, pred[y])
        for x in range(ancho):
            d = (y * ancho + x) * bpp
            if r == 1:
                sal[d] = fila[x * 3] & 0xFF
                if alfa_si:
                    sal[d + 1] = alfa[y * ancho + x]
                continue
            Y = fila[x * 3]
            co = _i16(fila[x * 3 + 1] << 1)
            cg = _i16(fila[x * 3 + 2] << 1)
            t = _i16(Y - int(cg / 2))
            g = _i16(t + cg)
            bl = _i16(t - int(co / 2))
            rj = _i16(bl + co)
            if b == 1:
                sal[d], sal[d + 1], sal[d + 2] = rj & 0xFF, g & 0xFF, bl & 0xFF
                if alfa_si:
                    sal[d + 3] = alfa[y * ancho + x]
            else:
                struct.pack_into("<4H", sal, d, _escala_ancha(bl), _escala_ancha(g), _escala_ancha(rj),
                                 (alfa[y * ancho + x] * 10000 + 127) // 255)
        ant = fila
    return bytes(sal)


def decodificar(src, lzfse):
    """src: los datos de la imagen sin los 16 bytes de MLEC. lzfse(datos, tope)
    es el descompresor de car.py (liblzfse)."""
    if src[:4] == b"KCBC":
        return _kcbc(src, lzfse)
    if len(src) < 28:
        raise Error("deepmap2 cortado")
    version, _codif, largo = struct.unpack("<IIQ", src[:16])
    if version != 1:
        raise Error(f"contenedor deepmap2 versión {version}")
    if largo > len(src) - 16:
        raise Error("el contenedor declara más bytes de los que hay")
    fin = 16 + largo
    if src[16:20] != b"dmp2":
        raise Error(f"firma {src[16:20]!r} en vez de dmp2")
    metodo, version_blob, formato = src[20], src[21], src[23]
    if formato not in FORMATOS:
        raise Error(f"formato de píxel {formato}")
    ancho, alto = struct.unpack("<HH", src[24:28])
    if version_blob != 1 or not ancho or not alto:
        raise Error("blob dmp2 inválido")
    c, b, _ = FORMATOS[formato]
    bytes_pix = ancho * alto * c * b
    if metodo == CRUDO:
        carga = src[28:fin]
        if len(carga) != bytes_pix:
            raise Error("dmp2 crudo con tamaño distinto")
        return ancho, alto, formato, bytes(carga)
    if fin < 32:
        raise Error("descriptor cortado")
    desc = struct.unpack("<I", src[28:32])[0]
    carga = src[32:fin]
    if metodo == DEFECTO:
        partes, filas = [], 0
        resto, largo = carga, desc
        while True:
            if largo == 0 or largo > len(resto):
                raise Error("segmento por defecto cortado")
            dec = _segmento(resto[:largo], _bytes_defecto(ancho, alto, formato), lzfse)
            n = _filas_defecto(len(dec), ancho, formato)
            partes.append(_pixeles_defecto(dec, ancho, n, formato))
            filas += n
            resto = resto[largo:]
            if not resto:
                break
            largo = struct.unpack("<I", resto[:4])[0]
            resto = resto[4:]
        return ancho, filas, formato, b"".join(partes)
    if metodo == SIN_PERDIDA:
        pix = b"".join(_segmentos(carga, desc, bytes_pix, lzfse))
        fila = ancho * c * b
        if len(pix) % fila:
            raise Error("sin pérdida: fila incompleta")
        return ancho, len(pix) // fila, formato, pix
    if metodo == PALETA:
        ncolores, comp_paleta = desc & 0xFFFF, desc >> 16
        if not 0 < ncolores <= 256 or not 0 < comp_paleta <= c:
            raise Error("paleta inválida")
        paso = c * b
        bpal = ncolores * paso
        cod_n = struct.unpack("<I", carga[bpal:bpal + 4])[0]
        cod = carga[bpal + 4:bpal + 4 + cod_n]
        n = ancho * alto
        aparte = c - comp_paleta
        planos = n * aparte * b
        esperado = planos + n
        dec = _segmento(cod, esperado, lzfse)
        if len(dec) != esperado:
            raise Error(f"paleta: {len(dec)} bytes, se esperaban {esperado}")
        paleta, idx = carga[:bpal], dec[planos:]
        sal = bytearray(n * paso)
        for i, j in enumerate(idx):
            if j >= ncolores:
                raise Error("índice de paleta fuera de rango")
            sal[i * paso:(i + 1) * paso] = paleta[j * paso:(j + 1) * paso]
            for k in range(aparte):
                o = k * n * b + i * b
                d = i * paso + (comp_paleta + k) * b
                sal[d:d + b] = dec[o:o + b]
        return ancho, alto, formato, bytes(sal)
    raise Error(f"método dmp2 {metodo} sin soporte")


def _kcbc(src, lzfse):
    p, partes, ancho, formato, filas = 0, [], None, None, 0
    while p < len(src):
        if src[p:p + 4] != b"KCBC":
            raise Error("firma KCBC")
        n_filas, largo = struct.unpack("<II", src[p + 12:p + 20])
        a, h, f, pix = decodificar(src[p + 20:p + 20 + largo], lzfse)
        if h != n_filas or (ancho is not None and (a != ancho or f != formato)):
            raise Error("trozo KCBC incompatible")
        ancho, formato = a, f
        partes.append(pix)
        filas += h
        p += 20 + largo
    return ancho, filas, formato, b"".join(partes)
