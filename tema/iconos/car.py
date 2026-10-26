#!/usr/bin/env python3
"""Lector de catálogos de recursos de Apple (Assets.car) sin macOS.

    car.py listar <Assets.car>              cada imagen: nombre, tamaño, escala,
                                            apariencia, formato y compresor
    car.py sacar <Assets.car> <carpeta> [nombre…]
                                            escribe en PNG lo que se pueda
                                            descomprimir (sin comprimir, rle, LZFSE y
                                            deepmap2; 8 bits y de 16 bits RGBW/GA16)
    car.py glifos <Assets.car> <carpeta> [--oscuro] [nombre…]
                                            los glifos que traen vector (PDF),
                                            dibujados con pdftocairo a su tamaño
                                            natural: <nombre>@1x.png y @2x.png

Un .car es un archivo BOM («BOMStore», big-endian) con árboles B: FACETKEYS
(nombre → atributos) y RENDITIONS (atributos → imagen). Cada imagen es un
bloque CSI («CTSI», little-endian) con un encabezado fijo, una lista TLV y los
datos. El formato no es público; esto sigue lo que se ha documentado
desmontándolo (Timac, «Reverse engineering the .car file format»).

deepmap2 (compresión 11, la de Catalina) se abre con deepmap2.py, traducido
del decodificador de carfile-go (MIT; 16-10-2026). Muchos glifos traen además
su vector en PDF (bloque RAWD): «glifos» los saca de ahí.
Nada de lo que sale de aquí va al repo.
"""
import ctypes
import ctypes.util
import os
import struct
import sys

# Atributos de una clave de imagen (kRenditionAttributeType_*).
ATRIBUTOS = {
    0: "look", 1: "elemento", 2: "parte", 3: "tamaño", 4: "dirección",
    6: "valor", 7: "apariencia", 8: "dimensión1", 9: "dimensión2",
    10: "estado", 11: "capa", 12: "escala", 14: "presentación", 15: "idiom",
    16: "subtipo", 17: "identificador", 18: "valor_previo", 19: "estado_previo",
    20: "clase_h", 21: "clase_v", 22: "memoria", 23: "gráficos", 24: "gamut",
    25: "despliegue",
}
# Nombre de apariencia → sufijo del archivo; la misma tabla que car-mac.js.
APARIENCIAS = {
    "NSAppearanceNameDarkAqua": "-oscuro", "UIAppearanceDark": "-oscuro",
    "NSAppearanceNameAqua": "-claro", "UIAppearanceLight": "-claro",
    "NSAppearanceNameAccessibilityDarkAqua": "-oscuro-ax",
    "NSAppearanceNameAccessibilityAqua": "-claro-ax",
    "NSAppearanceNameAccessibilitySystem": "-ax", "ISAppearanceTintable": "-tintable",
}
COMPRESORES = {
    0: "ninguno", 1: "rle", 2: "zip", 3: "lzvn", 4: "lzfse", 5: "jpeg-lzfse",
    6: "blurred", 7: "astc", 8: "paleta", 9: "hevc", 10: "deepmap-lzfse",
    11: "deepmap2",
}


class BOM:
    """El contenedor: bloques numerados, variables con nombre y árboles B."""

    def __init__(self, datos):
        if datos[:8] != b"BOMStore":
            raise ValueError("no es un archivo BOM")
        self.d = datos
        _, _, ind_ofs, _, var_ofs, _ = struct.unpack(">6I", datos[8:32])
        n = struct.unpack(">I", datos[ind_ofs:ind_ofs + 4])[0]
        self.bloques = [struct.unpack(">II", datos[ind_ofs + 4 + 8 * i:ind_ofs + 12 + 8 * i])
                        for i in range(n)]
        self.vars = {}
        n = struct.unpack(">I", datos[var_ofs:var_ofs + 4])[0]
        p = var_ofs + 4
        for _ in range(n):
            indice, largo = struct.unpack(">IB", datos[p:p + 5])
            self.vars[datos[p + 5:p + 5 + largo].decode("ascii")] = indice
            p += 5 + largo

    def bloque(self, i):
        ofs, largo = self.bloques[i]
        return self.d[ofs:ofs + largo]

    def arbol(self, nombre):
        """Pares (clave, valor) de un árbol B, en orden."""
        cab = self.bloque(self.vars[nombre])
        if cab[:4] != b"tree":
            raise ValueError(f"{nombre} no es un árbol")
        hoja = struct.unpack(">I", cab[8:12])[0]
        while True:  # bajar hasta la primera hoja
            p = self.bloque(hoja)
            es_hoja, _, _, _ = struct.unpack(">HHII", p[:12])
            if es_hoja:
                break
            hoja = struct.unpack(">I", p[12:16])[0]
        while hoja:
            p = self.bloque(hoja)
            _, cuenta, siguiente, _ = struct.unpack(">HHII", p[:12])
            for i in range(cuenta):
                valor, clave = struct.unpack(">II", p[12 + 8 * i:20 + 8 * i])
                yield self.bloque(clave), self.bloque(valor)
            hoja = siguiente


def tag(b):
    """Las etiquetas de cuatro letras van al revés en disco («CTSI» = ISTC)."""
    return b[::-1].decode("latin-1").strip()


class Catalogo:
    def __init__(self, ruta):
        with open(ruta, "rb") as f:
            self.bom = BOM(f.read())
        kf = self.bom.bloque(self.bom.vars["KEYFORMAT"])
        _, _, cuenta = struct.unpack("<4sII", kf[:12])
        self.formato = list(struct.unpack(f"<{cuenta}I", kf[12:12 + 4 * cuenta]))
        # identificador → nombre, desde FACETKEYS
        self.nombres = {}
        for clave, valor in self.bom.arbol("FACETKEYS"):
            n = struct.unpack("<H", valor[4:6])[0]
            for i in range(n):
                a, v = struct.unpack("<HH", valor[6 + 4 * i:10 + 4 * i])
                if a == 17:
                    self.nombres[v] = clave.decode("utf-8", "replace")
        # id de apariencia → nombre («NSAppearanceNameDarkAqua»…), desde 11.
        self.apariencias = {}
        if "APPEARANCEKEYS" in self.bom.vars:
            for clave, valor in self.bom.arbol("APPEARANCEKEYS"):
                self.apariencias[struct.unpack("<H", valor[:2])[0]] = clave.decode("utf-8", "replace")

    def sufijo_apariencia(self, atr):
        """La apariencia por su nombre en el .car, con la tabla de car-mac.js
        (extraer-mac) para comparar archivo por archivo. Antes toda apariencia
        distinta de 0 salía «-oscuro»: en 27 Aqua (8) y Tintable (10) pisaban al
        oscuro de verdad. Un .car sin APPEARANCEKEYS (Catalina) solo tiene la 1."""
        a = atr.get("apariencia")
        if not a:
            return ""
        n = self.apariencias.get(a)
        if n is None:
            return "-oscuro" if a == 1 and not self.apariencias else f"-apariencia{a}"
        if n in APARIENCIAS:
            return APARIENCIAS[n]
        for pre in ("NSAppearanceName", "UIAppearanceName", "ISAppearanceName",
                    "NSAppearance", "UIAppearance", "ISAppearance"):
            if n.startswith(pre):
                return "-apariencia" + n[len(pre):]
        return "-apariencia" + n

    def imagenes(self):
        for clave, valor in self.bom.arbol("RENDITIONS"):
            vals = struct.unpack(f"<{len(clave) // 2}H", clave)
            atr = {ATRIBUTOS.get(a, str(a)): v for a, v in zip(self.formato, vals)}
            im = Imagen(valor, self.nombres.get(atr.get("identificador")))
            im.catalogo = self
            im.clave = frozenset((a, v) for a, v in zip(self.formato, vals) if v)
            yield atr, im

    def formato_hoja(self, clave):
        """El formato de píxel de la hoja a la que apunta un enlace: el del
        enlace mismo no es fiable (car.py contaba ARGB lo que es GA8)."""
        self.hoja(None) if not hasattr(self, "_hojas") else None
        im = self._hojas.get(clave)
        return im.pixeles if im else None

    def hoja(self, clave):
        """La hoja empaquetada con esa clave, ya abierta (con caché). Las hay
        en color (ARGB) y en gris (GA8): un recorte en color puede salir de
        una hoja gris (los semáforos inactivos)."""
        if not hasattr(self, "_hojas"):
            self._hojas, self._abiertas = {}, {}
            for _, im in self.imagenes():
                if im.nombre.startswith("ZZZZPackedAsset"):
                    self._hojas[im.clave] = im
        if clave is None:
            return None
        if clave not in self._abiertas:
            im = self._hojas.get(clave)
            self._abiertas[clave] = pixeles_de(im) if im else None
        return self._abiertas[clave]


class Imagen:
    """Un bloque CSI: encabezado de 184 bytes, TLV y los datos."""

    def __init__(self, b, nombre_faceta):
        if b[:4] != b"ISTC":
            raise ValueError("bloque CSI sin firma")
        (_, _, self.ancho, self.alto, escala) = struct.unpack("<5I", b[4:24])
        self.escala = escala / 100
        self.pixeles = tag(b[24:28])
        self.nombre = b[40:168].split(b"\0")[0].decode("utf-8", "replace")
        self.faceta = nombre_faceta
        tlv, _, _, largo = struct.unpack("<4I", b[168:184])
        self.datos = b[184 + tlv:184 + tlv + largo]
        self.tlv, p = {}, 184
        while p < 184 + tlv:
            tipo, n = struct.unpack("<II", b[p:p + 8])
            self.tlv[tipo] = b[p + 8:p + 8 + n]
            p += 8 + n
        # Enlace a un recorte de una hoja empaquetada (TLV 1010, «INLK»):
        # x, y, ancho, alto y la clave de la hoja como pares atributo-valor.
        self.enlace = None
        e = self.tlv.get(1010)
        if e and e[:4] == b"KLNI":
            x, y, w, h = struct.unpack("<4I", e[8:24])
            largo_clave = struct.unpack("<H", e[26:28])[0]
            clave = e[28:28 + largo_clave]
            pares = [struct.unpack("<HH", clave[i:i + 4]) for i in range(2, len(clave) - 3, 4)]
            self.enlace = ((x, y, w, h), frozenset((a, v) for a, v in pares if a))
        self.compresor = None
        self.envoltura = tag(self.datos[:4]) if len(self.datos) >= 4 else ""
        if self.envoltura in ("CELM", "KCBC"):
            # MLEC: versión, compresor, largo; adentro el flujo directo o
            # trozos KCBC de N filas, cada uno con su flujo.
            self.compresor = struct.unpack("<I", self.datos[8:12])[0]

    @property
    def compresion(self):
        if self.compresor is None:
            return {"RAWD": "crudo", "": "-"}.get(self.envoltura, self.envoltura)
        return COMPRESORES.get(self.compresor, str(self.compresor))


# --- LZFSE por liblzfse (paquete liblzfse1) ---------------------------------
_lz = None


def lzfse(datos, esperado):
    global _lz
    if _lz is None:
        ruta = ctypes.util.find_library("lzfse")
        if not ruta:
            raise RuntimeError("falta liblzfse (apt install liblzfse1)")
        _lz = ctypes.CDLL(ruta)
        _lz.lzfse_decode_buffer.restype = ctypes.c_size_t
    salida = ctypes.create_string_buffer(esperado + 4096)
    n = _lz.lzfse_decode_buffer(salida, len(salida), datos, len(datos), None)
    return salida.raw[:n]


def rle(cuerpo, bpp):
    """Compresión 1 (Aqua, hojas chicas): un campo (4 en ARGB, 3 en GA8; los
    bytes por píxel salen del formato, no de él), ancho y alto, una
    tabla de desplazamientos por fila y en cada fila tramos con cabecera de 32
    bits: el bit alto es «repetir el píxel que sigue», sin él «van N píxeles».
    Dos filas iguales comparten desplazamiento (las dos últimas en Aqua): cada
    fila se lee hasta llenar el ancho, no hasta la siguiente entrada.
    Sale sin relleno de fila, en el orden de siempre (BGRA o GA)."""
    _, ancho, alto = struct.unpack("<3I", cuerpo[:12])
    ofs = struct.unpack(f"<{alto}I", cuerpo[12:12 + 4 * alto])
    sal, fin = bytearray(), len(cuerpo)
    for y in range(alto):
        p, fila = ofs[y], bytearray()
        while p < fin and len(fila) < ancho * bpp:
            cab = struct.unpack("<I", cuerpo[p:p + 4])[0]
            n = cab & 0x7FFFFFFF
            if n * bpp > ancho * bpp - len(fila):
                return None  # tramo más largo que la fila: no es este formato
            if cab & 0x80000000:
                fila += cuerpo[p + 4:p + 4 + bpp] * n
                p += 4 + bpp
            else:
                fila += cuerpo[p + 4:p + 4 + n * bpp]
                p += 4 + n * bpp
        if len(fila) != ancho * bpp:
            return None
        sal += fila
    return bytes(sal)


# Píxeles anchos (desde Big Sur, sobre todo AppIcon): media precisión por
# canal, premultiplicados. RGBW = R, G, B, A (8 bytes); GA16 = gris, alfa
# (4 bytes). El orden R-G-B sale de los íconos (Notes amarillo); el espacio de
# color (sRGB extendido o P3) es hipótesis: se recorta a 0..1 sin convertir.
ANCHOS = {"RGBW": 4, "GA16": 2}


def _de_media(crudo, ancho, alto, canales, fila=None, enteros=False):
    import numpy as np
    from PIL import Image as PImage
    fila = fila or len(crudo) // alto
    a = np.frombuffer(crudo[:fila * alto], np.uint8).reshape(alto, fila)[:, :ancho * canales * 2]
    if enteros:  # deepmap2 «por defecto» (carfile-go): B, G, R, A en 0..10000
        v = a.copy().view("<u2").reshape(alto, ancho, canales).astype(np.float32) / 10000
        v = v[..., [2, 1, 0, 3]] if canales == 4 else v
    else:
        v = a.copy().view("<f2").reshape(alto, ancho, canales).astype(np.float32)
    v = np.nan_to_num(np.clip(v, 0, 1))
    alfa = v[..., -1:]
    color = np.where(alfa > 0, np.clip(v[..., :-1] / np.maximum(alfa, 1e-6), 0, 1), 0)
    if canales == 2:
        color = np.repeat(color, 3, axis=-1)
    return PImage.fromarray((np.dstack([color, alfa]) * 255 + 0.5).astype(np.uint8), "RGBA")


def pixeles_de(im):
    """BGRA premultiplicado → bytes RGBA, o None si no se puede."""
    from PIL import Image as PImage
    if im.pixeles not in ("ARGB", "GA8") and im.pixeles not in ANCHOS:
        return None
    if not im.datos and im.enlace and getattr(im, "catalogo", None):
        (x, y, w, h), clave = im.enlace
        hoja = im.catalogo.hoja(clave)
        if not hoja:
            return None
        # Coordenadas de CoreGraphics: el origen va abajo a la izquierda.
        y = hoja.height - y - h
        return hoja.crop((x, y, x + w, y + h))
    ancho = im.pixeles in ANCHOS
    canales = 4 if im.pixeles in ("ARGB", "RGBW") else 2
    esperado = im.ancho * im.alto * canales * (2 if ancho else 1)
    d = im.datos
    if im.envoltura != "CELM":
        return None
    cuerpo = d[16:]
    if im.compresor == 11:
        # deepmap2: tema/iconos/deepmap2.py (traducido de carfile-go). Sale en el
        # mismo orden que el camino LZFSE, sin relleno de fila.
        import deepmap2
        try:
            a, h, formato, crudo = deepmap2.decodificar(cuerpo, lzfse)
        except deepmap2.Error:
            return None
        if ancho:
            # formato 20 (RGBW); el GA16 (18) deepmap2.py no lo trae. «Por
            # defecto» (método 2) sale en enteros 0..10000; sin pérdida, en media.
            if (a, h) != (im.ancho, im.alto) or formato != 20:
                return None
            return _de_media(crudo, a, h, 4, a * 8, enteros=cuerpo[20] == 2)
        if (a, h) != (im.ancho, im.alto) or formato != (4 if canales == 4 else 2):
            return None
    elif cuerpo[:4] == b"KCBC":
        # En trozos: cada KCBC trae (0, 0, filas, largo) y su propio flujo.
        partes, p = [], 0
        while cuerpo[p:p + 4] == b"KCBC":
            filas, largo = struct.unpack("<II", cuerpo[p + 12:p + 20])
            trozo = cuerpo[p + 20:p + 20 + largo]
            # Cada fila va rellenada hasta un múltiplo de 64 bytes.
            n = filas * (-(-esperado // im.alto // 64) * 64)
            if im.compresor == 0:
                partes.append(trozo)
            elif im.compresor == 4:
                partes.append(lzfse(trozo, n))
            else:
                return None
            p += 20 + largo
        crudo = b"".join(partes)
    else:
        cuerpo = cuerpo[:struct.unpack("<I", d[12:16])[0]]
        if im.compresor == 0:
            crudo = cuerpo
        elif im.compresor == 1:
            crudo = rle(cuerpo, canales)
            if crudo is None:
                return None
        elif im.compresor == 4:
            crudo = lzfse(cuerpo, im.alto * (-(-esperado // im.alto // 64) * 64))
        else:
            return None
    if len(crudo) < esperado:
        return None
    if ancho:
        return _de_media(crudo, im.ancho, im.alto, canales)
    # El largo real de fila: con relleno (múltiplo de 64) o sin él.
    fila = len(crudo) // im.alto if len(crudo) % im.alto == 0 else im.ancho * canales
    if canales == 4:
        img = PImage.frombuffer("RGBa", (im.ancho, im.alto), crudo, "raw", "BGRa", fila, 1)
        return img.convert("RGBA")
    # GA8: gris y alfa, premultiplicado; PIL no convierte «La», se hace a mano.
    import numpy as np
    ga = np.frombuffer(crudo[:fila * im.alto], np.uint8).reshape(im.alto, fila)[:, :im.ancho * 2]
    ga = ga.reshape(im.alto, im.ancho, 2).astype(np.float32)
    gris, alfa = ga[..., 0], ga[..., 1]
    gris = np.where(alfa > 0, np.clip(gris * 255 / np.maximum(alfa, 1), 0, 255), 0)
    rgba = np.dstack([gris, gris, gris, alfa]).astype(np.uint8)
    return PImage.fromarray(rgba, "RGBA")


def archivo(nombre):
    """Nombre de imagen → nombre de archivo. Desde Monterey hay nombres con «/»
    (CoreTypes «DropFolderBadge/image_100x100», FindMy): se cambian por «__»
    para no partir la ruta."""
    return nombre.replace("/", "__")


def mayor(ruta, nombre):
    """La imagen más grande que se pueda abrir con ese nombre, o None."""
    mejor = None
    for atr, im in Catalogo(ruta).imagenes():
        if (im.faceta or im.nombre) != nombre or atr.get("apariencia"):
            continue
        if mejor and im.ancho * im.alto <= mejor[0]:
            continue
        img = pixeles_de(im)
        if img is not None:
            mejor = (im.ancho * im.alto, img)
    return mejor[1] if mejor else None


def glifos(ruta, carpeta, solo, oscuro=False):
    """Cada glifo con PDF, dibujado a 1x y 2x del tamaño de su mapa de bits de
    1x; si no hay mapa de bits, al tamaño de la página. Con oscuro, el dibujo
    de modo oscuro cuando lo hay: en Catalina varios cambian de forma, no
    solo de color (la vista de íconos y Arrange son rellenos en oscuro)."""
    import subprocess
    import tempfile
    pdfs, tam = {}, {}
    cat = Catalogo(ruta)
    for atr, im in cat.imagenes():
        nombre = im.faceta or im.nombre
        ap = cat.sufijo_apariencia(atr)
        if ap not in ("", "-claro", "-oscuro"):
            continue  # accesibilidad, Tintable…: aparte
        es_oscuro = ap == "-oscuro"
        if solo and nombre not in solo:
            continue
        if im.pixeles == "PDF" and im.envoltura == "RAWD":
            if es_oscuro and not oscuro:
                continue
            if not es_oscuro and oscuro and nombre in pdfs:
                continue  # ya está el oscuro
            largo = struct.unpack("<I", im.datos[8:12])[0]
            pdfs[nombre] = im.datos[12:12 + largo]
        elif im.escala == 1 and im.ancho and not es_oscuro:
            tam[nombre] = (im.ancho, im.alto)
    os.makedirs(carpeta, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for nombre, pdf in pdfs.items():
            ent = os.path.join(tmp, "g.pdf")
            with open(ent, "wb") as f:
                f.write(pdf)
            for esc in (1, 2):
                base = os.path.join(carpeta, f"{archivo(nombre)}@{esc}x")
                orden = ["pdftocairo", "-png", "-singlefile", "-transp"]
                if nombre in tam:
                    w, h = tam[nombre]
                    orden += ["-scale-to-x", str(w * esc), "-scale-to-y", str(h * esc)]
                else:
                    orden += ["-r", str(72 * esc)]
                subprocess.run(orden + [ent, base], check=True)
                if nombre in tam:  # pdftocairo a veces redondea un píxel de más
                    from PIL import Image as PImage
                    img = PImage.open(base + ".png")
                    if img.size != (w * esc, h * esc):
                        img.resize((w * esc, h * esc), PImage.LANCZOS).save(base + ".png")
    print(f"  {len(pdfs)} glifos con vector")


def listar(ruta):
    cat = Catalogo(ruta)
    filas = []
    for atr, im in cat.imagenes():
        pix = im.pixeles
        if im.enlace and not im.datos:  # el formato de la hoja, no el del enlace
            pix = cat.formato_hoja(im.enlace[1]) or pix
        ap = cat.sufijo_apariencia(atr).lstrip("-") or "claro"
        filas.append((im.faceta or im.nombre, f"{im.ancho}x{im.alto}", f"@{im.escala:g}",
                      ap, pix, im.compresion))
    for f in sorted(filas):
        print("\t".join(f))
    cuenta = {}
    for f in filas:
        cuenta[f[5]] = cuenta.get(f[5], 0) + 1
    print("\n" + "  ".join(f"{k}: {v}" for k, v in sorted(cuenta.items())), file=sys.stderr)


def sacar(ruta, carpeta, solo):
    cat = Catalogo(ruta)
    os.makedirs(carpeta, exist_ok=True)
    hechos = saltados = 0
    for atr, im in cat.imagenes():
        nombre = im.faceta or im.nombre
        if solo and nombre not in solo:
            continue
        img = pixeles_de(im)
        if img is None:
            saltados += 1
            continue
        # Los controles repiten nombre y tamaño en cada estado (normal,
        # apretado, inactivo…): los atributos van en el nombre del archivo.
        extra = "".join(f"-{k}{v}" for k, v in sorted(atr.items())
                        if v and k not in ("identificador", "escala", "apariencia"))
        sufijo = f"-{im.ancho}x{im.alto}{extra}" + cat.sufijo_apariencia(atr) + \
            (f"@{im.escala:g}x" if im.escala != 1 else "")
        img.save(os.path.join(carpeta, f"{archivo(nombre)}{sufijo}.png"))
        hechos += 1
    print(f"  {hechos} imágenes; {saltados} sin poder abrir (vectores u otro formato)")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "listar":
        listar(sys.argv[2])
    elif len(sys.argv) >= 4 and sys.argv[1] == "glifos":
        resto = [a for a in sys.argv[4:] if a != "--oscuro"]
        glifos(sys.argv[2], sys.argv[3], set(resto), oscuro="--oscuro" in sys.argv[4:])
    elif len(sys.argv) >= 4 and sys.argv[1] == "sacar":
        sacar(sys.argv[2], sys.argv[3], set(sys.argv[4:]))
    else:
        sys.exit(__doc__)
