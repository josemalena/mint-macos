"""Lee un nib compilado de macOS y lo devuelve como un árbol de nodos simple.

Los nib de Catalina son bplist de NSKeyedArchiver (no NIBArchive, que es el de iOS):
`$objects` con todos los objetos, referencias como plistlib.UID, y `$top`
IB.objectdata (NSIBObjectData) con la raíz, los objetos de primer nivel y las
conexiones. Solo se leen recursos: nada de ejecutables (la licencia de macOS no lo
deja). Este archivo no trae datos de Apple: los lee del disco al correr.

    nodo = {"id": n, "clase": "NSTextField", "props": {...}, "hijos": [...]}

props, según la clase: titulo, texto, marco [x, y, ancho, alto] en puntos (con el
origen arriba a la izquierda, ya volteado), imagen, atajo («⌘N»), columnas, etc.
"""
import os
import plistlib
import re

NUM = r'-?[\d.]+(?:e-?\d+)?'


def rect(s):
    """«{{x, y}, {w, h}}» → [x, y, w, h]; «{w, h}» → [0, 0, w, h]."""
    if not isinstance(s, str):
        return None
    n = [float(x) for x in re.findall(NUM, s)]
    if len(n) == 4:
        return n
    if len(n) == 2:
        return [0.0, 0.0, n[0], n[1]]
    return None


# Modificadores de NSEventModifierFlags y cómo los escribe la Mac en un menú.
MODS = [(1 << 18, '⌃'), (1 << 19, '⌥'), (1 << 17, '⇧'), (1 << 20, '⌘')]
TECLAS = {'\x7f': '⌫', '\x1b': '⎋', '\r': '↩', '\t': '⇥', ' ': 'Space', '': '↑', '': '↓',
          '': '←', '': '→', '': '⌦', '': '↖', '': '↘', '': '⇞', '': '⇟'}


def atajo(tecla, mascara):
    """La tecla y la máscara de un NSMenuItem, como lo escribe la Mac: ⌃⌥⇧⌘ y la tecla.
    Una letra mayúscula lleva ⇧ implícito (así la guarda AppKit)."""
    if not tecla:
        return None
    mascara = mascara or 0
    if len(tecla) == 1 and tecla.isalpha() and tecla.isupper():
        mascara |= 1 << 17
    m = ''.join(s for b, s in MODS if mascara & b)
    if len(tecla) == 1 and 0xF704 <= ord(tecla) <= 0xF726:
        t = 'F%d' % (ord(tecla) - 0xF703)
    else:
        t = TECLAS.get(tecla, tecla.upper())
    return m + t


def nibarchive(b):
    """Un NIBArchive (los nib de Monterey en adelante) con la forma de un NSKeyedArchiver:
    {'$archiver', '$objects', '$top'}, objetos como dict con '$class' y referencias plistlib.UID.

    Cabecera «NIBArchive», dos u32 y ocho u32: objetos, claves, valores y clases (cantidad y
    posición de cada tabla). Los enteros de largo variable son de 7 bits, el menos
    significativo primero, y el byte con el bit alto encendido es el ÚLTIMO. Un arreglo o un
    diccionario lleva sus elementos con la clave UINibEncoderEmptyKey, en orden (en un
    diccionario, alternando clave y valor)."""
    import struct
    if not b.startswith(b'NIBArchive'):
        raise ValueError('no es un NIBArchive')
    nobj, pobj, nclav, pclav, nval, pval, ncla, pcla = struct.unpack_from('<8I', b, 18)

    def var(i):
        n = desp = 0
        while True:
            c = b[i]
            i += 1
            n |= (c & 0x7F) << desp
            desp += 7
            if c & 0x80:
                return n, i

    i, claves = pclav, []
    for _ in range(nclav):
        n, i = var(i)
        claves.append(b[i:i + n].decode('utf-8', 'replace'))
        i += n
    i, clases = pcla, []
    for _ in range(ncla):
        n, i = var(i)
        extra, i = var(i)
        i += 4 * extra
        clases.append(b[i:i + n].rstrip(b'\0').decode('utf-8', 'replace'))
        i += n
    i, valores = pval, []
    for _ in range(nval):
        k, i = var(i)
        t = b[i]
        i += 1
        if t in (0, 1, 2, 3):
            tam = (1, 2, 4, 8)[t]
            v = int.from_bytes(b[i:i + tam], 'little', signed=True)
            i += tam
        elif t in (4, 5):
            v = t == 4
        elif t == 6:
            v = struct.unpack_from('<f', b, i)[0]
            i += 4
        elif t == 7:
            v = struct.unpack_from('<d', b, i)[0]
            i += 8
        elif t == 8:
            n, i = var(i)
            v = bytes(b[i:i + n])
            i += n
        elif t == 9:
            v = None
        elif t == 10:
            v = plistlib.UID(struct.unpack_from('<I', b, i)[0])
            i += 4
        else:
            raise ValueError('NIBArchive: tipo de valor %d desconocido' % t)
        valores.append((claves[k], v))
    # Las clases van al final de $objects, una vez cada una, como en NSKeyedArchiver.
    objetos, crudos = [], []
    i = pobj
    for _ in range(nobj):
        c, i = var(i)
        vi, i = var(i)
        vn, i = var(i)
        crudos.append((c, valores[vi:vi + vn]))
    base_clases = nobj
    for c, vals in crudos:
        o = {'$class': plistlib.UID(base_clases + c)}
        nombre = clases[c]
        vacios = [v for k, v in vals if k == 'UINibEncoderEmptyKey']
        if nombre in ('NSArray', 'NSMutableArray', 'NSSet', 'NSMutableSet'):
            o['NS.objects'] = vacios
        elif nombre in ('NSDictionary', 'NSMutableDictionary'):
            o['NS.keys'], o['NS.objects'] = vacios[0::2], vacios[1::2]
        for k, v in vals:
            if k != 'UINibEncoderEmptyKey':
                o.setdefault(k, v)
        objetos.append(o)
    objetos += [{'$classname': n} for n in clases]
    raiz = next((plistlib.UID(j) for j, (c, _) in enumerate(crudos) if clases[c] == 'NSIBObjectData'), plistlib.UID(0))
    return {'$archiver': 'NSKeyedArchiver', '$objects': objetos, '$top': {'IB.objectdata': raiz}}


class Nib:
    def __init__(self, ruta, cadenas=None):
        crudo = open(ruta, 'rb').read()
        # Catalina compila los nib como bplist de NSKeyedArchiver; Monterey y los que siguen,
        # como NIBArchive. Los dos quedan con la forma del primero.
        d = nibarchive(crudo) if crudo.startswith(b'NIBArchive') else plistlib.loads(crudo)
        if d.get('$archiver') != 'NSKeyedArchiver':
            raise ValueError('no es un NSKeyedArchiver ni un NIBArchive: %s' % ruta)
        self.ruta = ruta
        self.o = d['$objects']
        self.top = self.res(d['$top'].get('IB.objectdata'))
        # Las cadenas de en.lproj/<nib>.strings, si el nib las referencia por clave.
        self.cadenas = cadenas or {}
        # La acción de cada control (NSNibControlConnector: fuente → selector, «terminate:»): es el
        # id que no cambia entre versiones de macOS aunque cambie el texto.
        self.acciones = {}
        self.enlaces = {}
        for con in self.lista(self.get(self.top, 'NSConnections')):
            if 'Binding' in (self.clase(con) or ''):
                fuente = self.res(self.get(con, 'NSSource'))
                ruta = self.texto(self.get(con, 'NSKeyPath'))
                if isinstance(fuente, dict) and ruta:
                    self.enlaces.setdefault(id(fuente), []).append((self.texto(self.get(con, 'NSBinding')) or '', ruta))
            if self.clase(con) in ('NSNibControlConnector', 'NSNibAXRelationshipConnector') or 'Control' in (self.clase(con) or ''):
                fuente = self.res(self.get(con, 'NSSource'))
                sel = self.texto(self.get(con, 'NSLabel'))
                if isinstance(fuente, dict) and sel:
                    self.acciones.setdefault(id(fuente), sel)

    # --- lo básico del archivador ---

    def res(self, v):
        return self.o[v.data] if isinstance(v, plistlib.UID) else v

    def clase(self, x):
        x = self.res(x)
        if isinstance(x, dict) and '$class' in x:
            return self.res(x['$class']).get('$classname')
        return None

    def get(self, x, k):
        x = self.res(x)
        return self.res(x.get(k)) if isinstance(x, dict) else None

    def clave(self, x):
        """La clave de localización de un texto («100365.title» → «100365»): el id que no cambia
        entre versiones mientras Apple no rehaga el control."""
        x = self.res(x)
        if self.clase(x) == 'NSLocalizableString':
            k = self.texto(self.get(x, 'NSKey'))
            if k:
                return k[:-6] if k.endswith('.title') else k
        return None

    def texto(self, x):
        x = self.res(x)
        if x is None or x == '$null':
            return None
        if isinstance(x, str):
            return x
        if isinstance(x, bytes):
            return x.decode('utf-8', 'replace')
        c = self.clase(x)
        if c in ('NSLocalizableString',):
            clave = self.texto(self.get(x, 'NSKey'))
            if clave and clave in self.cadenas:
                return self.cadenas[clave]
            # NIBArchive (Monterey) lo guarda en NS.bytes.
            return self.texto(self.get(x, 'NS.string') or self.get(x, 'NS.bytes'))
        if c in ('NSString', 'NSMutableString'):
            return self.texto(self.get(x, 'NS.string') or self.get(x, 'NS.bytes'))
        if c in ('NSAttributedString', 'NSMutableAttributedString'):
            return self.texto(self.get(x, 'NSString'))
        return None

    def lista(self, x):
        x = self.res(x)
        if not isinstance(x, dict):
            return []
        return [self.res(v) for v in x.get('NS.objects', [])]

    def lista_claves(self, x):
        x = self.res(x)
        if not isinstance(x, dict):
            return []
        return [self.res(v) for v in x.get('NS.keys', [])]

    def num(self, x, k):
        v = self.get(x, k)
        return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None

    # --- el árbol ---

    def imagen(self, x):
        """El nombre de una imagen (NSCustomResource → NSResourceName)."""
        r = self.res(x)
        if self.clase(r) == 'NSCustomResource':
            return self.texto(self.get(r, 'NSResourceName'))
        return None

    def nodo(self, x, alto_padre=None, visto=None):
        visto = set() if visto is None else visto
        x = self.res(x)
        clase = self.clase(x)
        if clase is None or id(x) in visto:
            return None
        visto.add(id(x))
        p = {}
        if clase == 'NSClassSwapper':
            # Una subclase propia de la app: las claves son las de la clase original.
            p['clase_propia'] = self.texto(self.get(x, 'NSClassName'))
            clase = self.texto(self.get(x, 'NSOriginalClassName')) or clase
        n = {'id': self.o.index(x) if len(self.o) < 20000 else None, 'clase': clase, 'props': p, 'hijos': []}
        cls_real = self.texto(self.get(x, 'NSClassName')) or self.texto(self.get(x, 'NSWindowClass'))
        if cls_real and cls_real != clase and 'clase_propia' not in p:
            p['clase_propia'] = cls_real
        for clave, nombre in (('NSTitle', 'titulo'), ('NSWindowTitle', 'titulo'), ('NSToolbarItemLabel', 'titulo'),
                              ('NSToolbarItemPaletteLabel', 'etiqueta_paleta'), ('NSToolbarItemToolTip', 'ayuda'),
                              ('NSToolTip', 'ayuda'), ('NSHeaderToolTip', 'ayuda'), ('NSSegmentItemLabel', 'titulo'),
                              ('NSIdentifier', 'identificador'), ('NSToolbarItemIdentifier', 'identificador'),
                              ('NSUserInterfaceItemIdentifier', 'identificador'), ('NSName', 'nombre')):
            t = self.texto(self.get(x, clave))
            if t:
                p[nombre] = t
                if nombre == 'titulo' and 'clave' not in p:
                    k = self.clave(self.get(x, clave))
                    if k:
                        p['clave'] = k
        # El marco, con el origen arriba a la izquierda (AppKit lo tiene abajo).
        m = rect(self.texto(self.get(x, 'NSFrame'))) or rect(self.texto(self.get(x, 'NSFrameSize')))
        if clase == 'NSWindowTemplate':
            m = rect(self.texto(self.get(x, 'NSWindowRect')))
            if m:
                p['marco_pantalla'] = m
                m = [0, 0, m[2], m[3]]
        if m:
            if alto_padre is not None:
                m = [m[0], alto_padre - m[1] - m[3], m[2], m[3]]
            p['marco'] = m
        # Los resortes (autoresizingMask): cómo se estira la vista cuando el padre cambia.
        flags = self.get(x, 'NSvFlags')
        if isinstance(flags, int) and flags & 0x3F:
            p['autoajuste'] = flags & 0x3F
        # El bit 31 es «hidden» (sale negativo: el bplist lo guarda con signo).
        if isinstance(flags, int) and (flags < 0 or flags & 0x80000000):
            p['oculta'] = True
        for k, nombre in (('NSImage', 'imagen'), ('NSToolbarItemImage', 'imagen'), ('NSOnImage', 'imagen_marcado')):
            im = self.imagen(self.get(x, k))
            if im:
                p[nombre] = im
        # La celda trae el texto, la imagen y el estilo del control.
        celda = self.get(x, 'NSCell')
        if isinstance(celda, dict):
            t = self.texto(self.get(celda, 'NSContents'))
            if t:
                p['texto'] = t
                k = self.clave(self.get(celda, 'NSContents'))
                if k:
                    p['clave'] = k
            # Casilla o radio: la imagen alterna de la celda (NSSwitch, NSRadioButton).
            alt = self.res(self.get(celda, 'NSAlternateImage'))
            if self.clase(alt) == 'NSButtonImageSource':
                nombre = self.texto(self.get(alt, 'NSImageName')) or ''
                p['tipo_boton'] = 'casilla' if 'Switch' in nombre else 'radio' if 'Radio' in nombre else nombre
            im = self.imagen(self.get(celda, 'NSNormalImage')) or self.imagen(self.get(celda, 'NSContents'))
            if im:
                p['imagen'] = im
            p['celda'] = self.clase(celda)
            # La alineación (bits 26-28 de NSCellFlags2: 0 izquierda, 1 derecha, 2 centro) y la letra.
            f2 = self.get(celda, 'NSCellFlags2')
            if isinstance(f2, int) and (f2 >> 26) & 7 in (1, 2):
                p['alineacion'] = {1: 'derecha', 2: 'centro'}[(f2 >> 26) & 7]
            letra = self.res(self.get(celda, 'NSSupport'))
            if self.clase(letra) == 'NSFont':
                p['letra'] = [self.texto(self.get(letra, 'NSName')), self.num(letra, 'NSSize')]
            segs =self.lista(self.get(celda, 'NSSegmentImages'))
            if segs:
                p['segmentos'] = [{'titulo': self.texto(self.get(s, 'NSSegmentItemLabel')),
                                   'imagen': self.imagen(self.get(s, 'NSSegmentItemImage')),
                                   'ancho': self.num(s, 'NSSegmentItemWidth'),
                                   'elegido': bool(self.get(s, 'NSSegmentItemSelected'))} for s in segs]
            menu = self.get(celda, 'NSMenu')
            if self.clase(menu) == 'NSMenu':
                hijo = self.nodo(menu, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
        if id(x) in self.acciones:
            p['accion'] = self.acciones[id(x)]
        if id(x) in self.enlaces:
            # Todos los enlaces («enabled ← self.sizeEnabled»…) y aparte el del valor: el ajuste que
            # cambia el control, el id de su comportamiento.
            p['enlaces'] = ['%s ← %s' % e for e in self.enlaces[id(x)]]
            valor = next((r for b, r in self.enlaces[id(x)] if b in ('value', 'selectedIndex', 'selectedTag',
                                                                      'selectedValue', 'selectedObject')), None)
            if valor:
                p['ajuste'] = valor
        if clase == 'NSMenuItem':
            a = atajo(self.texto(self.get(x, 'NSKeyEquiv')), self.num(x, 'NSKeyEquivModMask'))
            if a:
                p['atajo'] = a
            if self.get(x, 'NSIsSeparator'):
                p['separador'] = True
            if self.get(x, 'NSIsHidden'):
                p['oculto'] = True
            if self.get(x, 'NSState') == 1:
                p['marcado'] = True
            sub = self.get(x, 'NSSubmenu')
            if self.clase(sub) == 'NSMenu':
                hijo = self.nodo(sub, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
        if clase in ('NSMenu',):
            for it in self.lista(self.get(x, 'NSMenuItems')):
                hijo = self.nodo(it, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
        if clase == 'NSMatrix':
            celdas = self.lista(self.get(x, 'NSCells'))
            sel = self.get(x, 'NSSelectedRow')
            ops = []
            for i, cel in enumerate(celdas):
                o = {'texto': self.texto(self.get(cel, 'NSContents'))}
                k = self.clave(self.get(cel, 'NSContents'))
                if k:
                    o['clave'] = k
                if i == sel:
                    o['elegida'] = True
                alt = self.res(self.get(cel, 'NSAlternateImage'))
                if self.clase(alt) == 'NSButtonImageSource' and 'Radio' in (self.texto(self.get(alt, 'NSImageName')) or ''):
                    p['tipo_boton'] = 'radio'
                ops.append(o)
            p['opciones'] = ops
            p['filas'], p['columnas_matriz'] = self.get(x, 'NSNumRows'), self.get(x, 'NSNumCols')
        if clase in ('NSTableView', 'NSOutlineView'):
            cols = []
            for c in self.lista(self.get(x, 'NSTableColumns')):
                cols.append({'titulo': self.texto(self.get(self.get(c, 'NSHeaderCell'), 'NSContents')),
                             'identificador': self.texto(self.get(c, 'NSIdentifier')),
                             'ancho': self.num(c, 'NSWidth'), 'minimo': self.num(c, 'NSMinWidth'),
                             'maximo': self.num(c, 'NSMaxWidth'),
                             'oculta': bool(self.get(c, 'NSHidden')),
                             'ayuda': self.texto(self.get(c, 'NSHeaderToolTip'))})
            p['columnas'] = cols
            alto = self.num(x, 'NSRowHeight')
            if alto:
                p['alto_fila'] = alto
        if clase == 'NSTabView':
            for it in self.lista(self.get(x, 'NSTabViewItems')):
                hijo = self.nodo(it, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
        if clase == 'NSTabViewItem':
            t = self.texto(self.get(x, 'NSLabel'))
            if t:
                p['titulo'] = t
            v = self.get(x, 'NSView')
            hijo = self.nodo(v, None, visto) if isinstance(v, dict) else None
            if hijo:
                n['hijos'].append(hijo)
        if clase == 'NSWindowTemplate':
            tb = self.get(x, 'NSViewClass')
            if self.clase(tb) == 'NSToolbar':
                hijo = self.nodo(tb, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
            v = self.get(x, 'NSWindowView')
            hijo = self.nodo(v, None, visto)
            if hijo:
                n['hijos'].append(hijo)
        if clase == 'NSToolbar':
            # IBDefaultItems son identificadores; los ítems, en el diccionario IBIdentifiedItems.
            dic = self.get(x, 'NSToolbarIBIdentifiedItems')
            porid = dict(zip((self.texto(k) for k in self.lista_claves(dic)), self.lista(dic)))
            for e in self.lista(self.get(x, 'NSToolbarIBDefaultItems')):
                # Según la versión de IB, el ítem mismo o su identificador.
                i = self.texto(self.get(e, 'NSToolbarItemIdentifier')) if isinstance(e, dict) else self.texto(e)
                it = e if self.clase(e) == 'NSToolbarItem' else porid.get(i)
                if it is None:
                    # Los del sistema (espacio flexible, separador) no están en el diccionario.
                    n['hijos'].append({'id': None, 'clase': 'NSToolbarItem', 'props': {'identificador': i}, 'hijos': []})
                    continue
                hijo = self.nodo(it, None, visto)
                if hijo:
                    n['hijos'].append(hijo)
        if clase == 'NSToolbarItem':
            v = self.get(x, 'NSToolbarItemView')
            hijo = self.nodo(v, None, visto) if isinstance(v, dict) else None
            if hijo:
                n['hijos'].append(hijo)
        if clase in ('NSScrollView', 'NSClipView', 'NSBox'):
            doc = self.get(x, 'NSDocView') or self.get(x, 'NSContentView')
            if isinstance(doc, dict):
                hijo = self.nodo(doc, (m or [0, 0, 0, 0])[3], visto)
                if hijo:
                    n['hijos'].append(hijo)
        # Las subvistas, con el marco relativo a esta.
        alto = (m or [0, 0, 0, 0])[3]
        for sv in self.lista(self.get(x, 'NSSubviews')):
            hijo = self.nodo(sv, alto, visto)
            if hijo:
                n['hijos'].append(hijo)
        return n

    def raices(self):
        """Lo de primer nivel del nib: ventanas, vistas sueltas y menús, con su nombre en IB."""
        out = []
        valores = self.lista(self.get(self.top, 'NSObjectsValues'))
        claves = self.lista(self.get(self.top, 'NSObjectsKeys'))
        raiz = self.get(self.top, 'NSRoot')
        vistos = set()
        for obj, padre in zip(claves, valores):
            obj = self.res(obj)
            if self.res(padre) is not raiz and padre != raiz:
                continue
            c = self.clase(obj)
            # Ventanas, menús y vistas sueltas (las que la app mete en su ventana al correr,
            # como la lista de procesos de Activity Monitor).
            vista = c in ('NSWindowTemplate', 'NSMenu', 'NSBox', 'NSClassSwapper') or (c or '').endswith('View')
            if vista and id(obj) not in vistos:
                vistos.add(id(obj))
                n = self.nodo(obj)
                # Un NSClassSwapper que resultó no ser vista (un controlador) no se pinta.
                if n and (n['clase'] in ('NSWindowTemplate', 'NSMenu', 'NSBox') or n['clase'].endswith('View')):
                    out.append(n)
        return out


def cadenas_de(ruta_strings):
    """Un .strings (texto UTF-16 o UTF-8, o bplist) → dict."""
    if not os.path.exists(ruta_strings):
        return {}
    b = open(ruta_strings, 'rb').read()
    if b.startswith(b'bplist'):
        return plistlib.loads(b)
    for cod in ('utf-16', 'utf-8'):
        try:
            t = b.decode(cod)
            break
        except UnicodeDecodeError:
            continue
    else:
        return {}
    return dict(re.findall(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', t))


def openstep(t):
    """Un plist de texto de OpenStep («{ clave = (a, "b"); }») → dict, list y str."""
    i = 0

    def blanco():
        nonlocal i
        while i < len(t):
            if t[i].isspace():
                i += 1
            elif t.startswith('//', i):
                i = t.find('\n', i) + 1 or len(t)
            elif t.startswith('/*', i):
                i = t.find('*/', i) + 2 if t.find('*/', i) >= 0 else len(t)
            else:
                break

    def valor():
        nonlocal i
        blanco()
        c = t[i]
        if c == '{':
            i += 1
            d = {}
            while True:
                blanco()
                if t[i] == '}':
                    i += 1
                    return d
                k = valor()
                blanco()
                i += 1  # =
                d[k] = valor()
                blanco()
                if t[i] == ';':
                    i += 1
        if c == '(':
            i += 1
            out = []
            while True:
                blanco()
                if t[i] == ')':
                    i += 1
                    return out
                out.append(valor())
                blanco()
                if t[i] == ',':
                    i += 1
        if c == '"':
            j, s = i + 1, []
            while t[j] != '"':
                if t[j] == '\\':
                    j += 1
                    s.append({'n': '\n', 't': '\t'}.get(t[j], t[j]))
                else:
                    s.append(t[j])
                j += 1
            i = j + 1
            return ''.join(s)
        j = i
        while j < len(t) and (t[j].isalnum() or t[j] in '_.:$-/'):
            j += 1
        s, i = t[i:j], j
        return s

    return valor()


def barra_de_archivo(ruta, cadenas=None):
    """Un .toolbar de la app (Mail: MainWindow.toolbar, plist de OpenStep con «default set» y
    «toolbar array») → un nodo NSToolbar como los del nib: ítems con título, ayuda e imagen;
    los de segmentos, con un NSSegmentedControl dentro."""
    cadenas = cadenas or {}
    d = openstep(open(ruta, encoding='utf-8', errors='replace').read())
    porid = {}

    def juntar(v):
        if isinstance(v, list):
            for e in v:
                juntar(e)
        elif isinstance(v, dict) and v.get('identifier'):
            porid.setdefault(v['identifier'], v)
    juntar(d.get('toolbar array', []))

    def txt(k):
        return cadenas.get(k, k) if k else None

    def imagen(e):
        im = e.get('image')
        return None if im in (None, 'empty') else im

    barra = {'id': None, 'clase': 'NSToolbar', 'props': {'archivo': os.path.basename(ruta)}, 'hijos': []}
    for ident in d.get('default set', []):
        e = porid.get(ident, {})
        p = {'identificador': ident}
        for k, nombre in (('title', 'titulo'), ('help', 'ayuda')):
            if e.get(k):
                p[nombre] = txt(e[k])
        if imagen(e):
            p['imagen'] = imagen(e)
        item = {'id': None, 'clase': 'NSToolbarItem', 'props': p, 'hijos': []}
        if e.get('segments'):
            segs = [{'titulo': txt(s.get('title')), 'ayuda': txt(s.get('help')), 'imagen': imagen(s), 'elegido': False}
                    for s in e['segments']]
            item['hijos'].append({'id': None, 'clase': 'NSSegmentedControl', 'props': {'segmentos': segs},
                                  'hijos': []})
        elif ident == 'Search':
            item['hijos'].append({'id': None, 'clase': 'NSSearchField', 'props': {'marco': [0, 0, 200, 22]},
                                  'hijos': []})
        barra['hijos'].append(item)
    return barra


# Los modificadores de Carbon (keyEquivalentModifier): los mismos bits que NSEventModifierFlags.
def menus_carbon(ruta_xib):
    """Los menús de un nib de Carbon en XML (HIToolbox: StandardMenus.nib/objects.xib, de donde
    salen el menú Apple y los menús estándar), como nodos NSMenu/NSMenuItem del resto del lector.
    Cada ítem trae su «comando», el código de cuatro letras que no cambia entre versiones
    (abtm = About This Mac, apwn = Force Quit…, lock = Lock Screen)."""
    import xml.etree.ElementTree as ET
    t = open(ruta_xib, encoding='utf-8', errors='replace').read()
    # Los caracteres de control (la tecla Escape) vienen como &#27;: XML 1.0 no los deja.
    t = re.sub(r'&#(\d+);', lambda m: chr(int(m.group(1))) if int(m.group(1)) >= 32 or int(m.group(1)) in (9, 10, 13)
               else '&#xE0%02X;' % int(m.group(1)), t)
    raiz = ET.fromstring(t)
    por_id = {}
    for o in raiz.iter('object'):
        if o.get('id'):
            por_id[o.get('id')] = o

    def campos(o):
        return {c.get('name'): (c.text or '') for c in o if c.tag in ('string', 'int', 'boolean', 'ostype')}

    def tecla(v):
        # La Escape quedó como un carácter de uso privado: se vuelve a su código.
        return ''.join(chr(ord(c) - 0xE000) if 0xE000 <= ord(c) < 0xE100 else c for c in v)

    def item(o):
        d = campos(o)
        p = {}
        if d.get('separator') == 'TRUE':
            p['separador'] = True
        if d.get('title') and not p.get('separador'):
            p['titulo'] = d['title']
        if d.get('command'):
            p['comando'] = d['command']
        for k, nombre in (('hidden', 'oculto'), ('disabled', 'apagado'), ('dynamic', 'dinamico'),
                          ('sectionHeader', 'cabecera'), ('notPreviousAlternate', 'no_alterno')):
            if d.get(k) == 'TRUE':
                p[nombre] = True
        if d.get('keyEquivalent'):
            mascara = int(d.get('keyEquivalentModifier') or 1048576)  # sin máscara: ⌘
            a = atajo(tecla(d['keyEquivalent']), mascara)
            if a:
                p['atajo'] = a
        n = {'id': o.get('id'), 'clase': 'NSMenuItem', 'props': p, 'hijos': []}
        sub = next((c for c in o if c.get('name') == 'submenu'), None)
        if sub is not None:
            sub = por_id.get(sub.get('idRef')) if sub.tag == 'reference' else sub
            if sub is not None:
                n['hijos'].append(menu(sub))
        return n

    def menu(o):
        d = campos(o)
        n = {'id': o.get('id'), 'clase': 'NSMenu', 'props': {'titulo': d.get('title'), 'menu_id': d.get('menuID')}, 'hijos': []}
        items = next((c for c in o if c.tag == 'array' and c.get('name') == 'items'), None)
        for r in (items if items is not None else []):
            x = por_id.get(r.get('idRef')) if r.tag == 'reference' else r
            if x is not None:
                n['hijos'].append(item(x))
        return n

    # Los de primer nivel: los que no son submenú de un ítem.
    subs = {c.get('idRef') or c.get('id') for o in raiz.iter('object') for c in o if c.get('name') == 'submenu'}
    return [menu(o) for o in raiz.iter('object') if o.get('class') == 'IBCarbonMenu' and o.get('id') not in subs]


def abrir(ruta_nib):
    """El nib con sus cadenas en inglés (en.lproj/<nombre>.strings, si hay)."""
    base = os.path.splitext(os.path.basename(ruta_nib))[0]
    recursos = os.path.dirname(os.path.dirname(ruta_nib))
    return Nib(ruta_nib, cadenas_de(os.path.join(recursos, 'en.lproj', base + '.strings')))
