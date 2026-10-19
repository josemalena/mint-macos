#!/usr/bin/env python3
"""Las vistas SwiftUI de un ejecutable de la Mac, desde la metadata de tipos de Swift.

SwiftUI no deja nib: la ventana la arma el código. Pero el compilador guarda, para cada
`struct X: View`, el tipo concreto de su `body` (en __swift5_assocty, el tipo asociado
«Body»): `VStack<TupleView<(Text, Toggle<…>)>>`. Ese tipo es el árbol de la vista. Solo se lee
metadata de tipos (nombres y estructura), nunca código ni lógica: la excepción de José
(«solo información para replicar la interfaz y la experiencia»). Nada de lo que sale de aquí
va al repo.

    swiftui.py EJECUTABLE              cada vista con el tipo de su body, ya legible
    swiftui.py EJECUTABLE --json SAL   lo mismo en JSON, con el árbol (para el visor)

Necesita swift-demangle (~/.local/share/mint-macos/swift-demangle, de la toolchain de
swift.org). Lee el trozo x86_64 de un binario universal.

Cómo se resuelve un nombre: los tipos traen referencias simbólicas (un byte 0x01-0x17 y un
desplazamiento de 32 bits) a descriptores de este binario o, por la GOT, a símbolos de otras
bibliotecas (SwiftUI). Cada referencia se cambia por un tipo de mentira de un solo nodo
(«So<n>RefNV», del módulo __C, que no agrega sustituciones) para no correr la numeración de
las sustituciones del resto del nombre; después de pasar por swift-demangle, cada RefN se
cambia por su nombre de verdad.
"""
import json
import os
import re
import struct
import subprocess
import sys

DEMANGLE = os.path.expanduser('~/.local/share/mint-macos/swift-demangle')


class MachO:
    def __init__(self, ruta):
        b = open(ruta, 'rb').read()
        if b[:4] == b'\xca\xfe\xba\xbe':
            n = struct.unpack_from('>I', b, 4)[0]
            for i in range(n):
                cpu, _sub, off, size, _al = struct.unpack_from('>5I', b, 8 + 20 * i)
                if cpu == 0x01000007:
                    b = b[off:off + size]
                    break
            else:
                raise ValueError('sin trozo x86_64')
        if struct.unpack_from('<I', b, 0)[0] != 0xfeedfacf:
            raise ValueError('no es Mach-O de 64 bits')
        self.b = b
        self.segs, self.secs, fix = [], {}, None
        p = 32
        for _ in range(struct.unpack_from('<I', b, 16)[0]):
            cmd, tam = struct.unpack_from('<II', b, p)
            if cmd == 0x19:
                seg = b[p + 8:p + 24].rstrip(b'\0').decode()
                va, vtam, fo, _ft = struct.unpack_from('<4Q', b, p + 24)
                self.segs.append((va, vtam, fo))
                for j in range(struct.unpack_from('<I', b, p + 64)[0]):
                    q = p + 72 + 80 * j
                    sec = b[q:q + 16].rstrip(b'\0').decode()
                    a, s, _o = struct.unpack_from('<QQI', b, q + 32)
                    self.secs[sec] = (a, s)
            elif cmd == 0x80000034:
                fix = struct.unpack_from('<II', b, p + 8)
            p += tam
        self.imports = self._imports(fix) if fix else []
        self.inicios = self._inicios()

    def _inicios(self):
        """LC_FUNCTION_STARTS: dónde empieza cada función (para saber dónde termina una)."""
        b, p, out = self.b, 32, []
        for _ in range(struct.unpack_from('<I', b, 16)[0]):
            cmd, tam = struct.unpack_from('<II', b, p)
            if cmd == 0x26:
                off, sz = struct.unpack_from('<II', b, p + 8)
                i, va = off, 0x100000000
                while i < off + sz:
                    v = sh = 0
                    while True:
                        c = b[i]
                        i += 1
                        v |= (c & 0x7f) << sh
                        sh += 7
                        if not c & 0x80:
                            break
                    if v == 0:
                        break
                    va += v
                    out.append(va)
            p += tam
        return out

    def _imports(self, fix):
        fo = fix[0]
        _v, _st, imp, sym, n, fmt, _sf = struct.unpack_from('<7I', self.b, fo)
        out = []
        for i in range(n):
            if fmt == 1:
                no = struct.unpack_from('<I', self.b, fo + imp + 4 * i)[0] >> 9
            elif fmt == 2:
                no = struct.unpack_from('<I', self.b, fo + imp + 8 * i)[0] >> 9
            else:
                no = struct.unpack_from('<Q', self.b, fo + imp + 16 * i)[0] >> 32
            e = self.b.index(b'\0', fo + sym + no)
            out.append(self.b[fo + sym + no:e].decode())
        return out

    def off(self, va):
        for a, t, fo in self.segs:
            if a <= va < a + t:
                return va - a + fo
        raise ValueError('dirección fuera: %x' % va)

    def u32(self, va):
        return struct.unpack_from('<I', self.b, self.off(va))[0]

    def rel(self, va):
        return va + struct.unpack_from('<i', self.b, self.off(va))[0]

    def rel_ind(self, va):
        """Un puntero relativo que puede ser indirecto (el bit bajo encendido: va por la GOT)."""
        r = struct.unpack_from('<i', self.b, self.off(va))[0]
        if r == 0:
            return None
        if r & 1:
            return self.ranura(va + (r & ~1))
        return ('local', va + r)

    def cstr(self, va):
        o = self.off(va)
        return self.b[o:self.b.index(b'\0', o)].decode('utf-8', 'replace')

    def ranura(self, va):
        """Una entrada de la GOT con chained fixups: ('simbolo', nombre) o ('local', dirección)."""
        raw = struct.unpack_from('<Q', self.b, self.off(va))[0]
        if raw >> 63:
            return ('simbolo', self.imports[raw & 0xFFFFFF])
        t = raw & 0xFFFFFFFFF
        return ('local', t + 0x100000000 if t < 0x100000000 else t)

    def mangled(self, va):
        """Un nombre mangled con sus referencias simbólicas: lista de str y (tipo, destino)."""
        o = i = self.off(va)
        out = []
        while self.b[i] != 0:
            c = self.b[i]
            if 1 <= c <= 0x17:
                r = struct.unpack_from('<i', self.b, i + 1)[0]
                out.append((c, va + (i - o) + 1 + r))
                i += 5
            elif 0x18 <= c <= 0x1f:
                out.append((c, struct.unpack_from('<Q', self.b, i + 1)[0]))
                i += 9
            else:
                out.append(chr(c))
                i += 1
        return out


SUFIJO = {16: 'C', 17: 'V', 18: 'O', 3: 'P'}


class Lector:
    def __init__(self, ruta):
        self.m = MachO(ruta)
        self.refs = {}       # RefN → texto ya legible
        self.por_destino = {}
        self._cache = {}
        self.precargar()

    # --- los nombres de los descriptores ---

    def nombre_ctx(self, va, profundidad=0):
        """El nombre legible de un descriptor de contexto de este binario («Appearance.AppearanceView»)."""
        flags = self.m.u32(va)
        tipo = flags & 0x1F
        padre = self.m.rel_ind(va + 4) if profundidad < 20 and tipo != 0 else None
        pre = ''
        if padre and padre[0] == 'local' and padre[1]:
            pre = self.nombre_ctx(padre[1], profundidad + 1)
        elif padre and padre[0] == 'simbolo':
            pre = self.legible_simbolo(padre[1])
        if tipo == 0:
            return self.m.cstr(self.m.rel(va + 8))
        if tipo == 1:  # extensión: el contexto extendido es un nombre mangled
            return self.legible(self.m.mangled(self.m.rel(va + 8)))
        if tipo == 2:  # anónimo (fileprivate): transparente
            return pre
        if tipo == 4:  # tipo opaco: se expande a su tipo de verdad
            return self.opaco(va)
        nombre = self.m.cstr(self.m.rel(va + 8))
        return (pre + '.' if pre else '') + nombre

    def opaco(self, va):
        """«some View» de una función de este binario: su tipo de verdad, que va detrás del
        descriptor (sin contexto genérico: el de las vistas no lo tiene)."""
        flags = self.m.u32(va)
        n = flags >> 16
        if flags & 0x80 or n == 0:
            return 'some View'
        return self.legible(self.m.mangled(self.m.rel(va + 8)))

    def modificador(self, simbolo):
        """El nombre corto de un modificador de SwiftUI de su descriptor opaco: «.padding»."""
        t = self.legible_simbolo(simbolo)
        m = re.search(r'View\.([A-Za-z_]+)', t)
        return '.' + m.group(1) if m else t

    def arbol_opaco(self, va):
        """El árbol del tipo de verdad de un «some View» de este binario."""
        flags = self.m.u32(va)
        if flags & 0x80 or (flags >> 16) == 0:
            return Nodo('some View')
        return Pila(self, self.m.mangled(self.m.rel(va + 8))).leer()

    def legible_simbolo(self, s):
        if s in self._cache:
            return self._cache[s]
        self._cache[s] = t = self._legible_simbolo(s)
        return t

    def precargar(self):
        """Todos los símbolos de Swift de las importaciones en una sola llamada a swift-demangle."""
        sims = [i for i in self.m.imports if i.startswith('_$s') and i not in self._cache]
        for s, t in zip(sims, demangle([x[1:] for x in sims])):
            self._cache[s] = self._limpiar(t)

    @staticmethod
    def _limpiar(t):
        t = re.sub(r'^(nominal type descriptor|protocol descriptor|opaque type descriptor) for ', '', t)
        return re.sub(r'^opaque type of (.*)$', r'«\1»', t)

    def _legible_simbolo(self, s):
        s = s[1:] if s.startswith('_') else s
        if s.startswith('$s'):
            t = demangle([s])[0]
            t = re.sub(r'^(nominal type descriptor|protocol descriptor|opaque type descriptor) for ', '', t)
            t = re.sub(r'^opaque type of (.*)$', r'«\1»', t)
            return t
        return s

    # --- un nombre mangled completo ---

    def legible(self, partes):
        texto = []
        i = 0
        while i < len(partes):
            p = partes[i]
            if isinstance(p, str):
                texto.append(p)
                i += 1
                continue
            clase, destino = p
            if clase == 2:
                d = self.m.ranura(destino)
            elif clase == 1:
                d = ('local', destino)
            else:
                d = ('otro', destino)
            nombre = self.nombre_de(d)
            clave = 'Ref%d' % len(self.refs)
            self.refs[clave] = nombre
            texto.append('So%d%sV' % (len(clave), clave))
            i += 1
            # Un opaco va seguido de «Qo» y su índice: ya está expandido, se quita.
            j = i
            while j < len(partes) and partes[j] in ('S', 'g'):
                j += 1
            if j + 1 < len(partes) and partes[j] == 'Q' and partes[j + 1] == 'o' and self.es_opaco(d):
                k = j + 2
                while k < len(partes) and isinstance(partes[k], str) and (partes[k].isdigit() or partes[k] == '_'):
                    k += 1
                    if partes[k - 1] == '_':
                        break
                texto.extend(x for x in partes[i:j])
                i = k
        mang = ''.join(texto)
        mang = mang[2:] if mang.startswith('$s') else mang
        # Un tipo suelto se demanglea como «tipo» con la D del final.
        return '$s' + mang + 'D'

    def es_opaco(self, d):
        if d[0] == 'simbolo':
            return d[1].endswith('QOMQ') or d[1].endswith('MQ')
        if d[0] == 'local':
            try:
                return self.m.u32(d[1]) & 0x1F == 4
            except ValueError:
                return False
        return False

    def nombre_de(self, d):
        if d[0] == 'simbolo':
            return self.legible_simbolo(d[1])
        if d[0] == 'local':
            try:
                return self.nombre_ctx(d[1])
            except (ValueError, struct.error):
                return '?'
        return '?'

    # --- los textos de cada vista (excepción de José, 18-10-2026: solo para saber qué texto
    # lleva cada control; nada de esto va al repo) ---

    def bodies(self):
        """{vista: dirección del getter de su body}, de los testigos de la conformidad a View
        (__swift5_proto: la conformidad lleva sus testigos resilientes y uno es «body.getter»)."""
        out = {}
        a, t = self.m.secs.get('__swift5_proto', (0, 0))
        for va in range(a, a + t, 4):
            cd = self.m.rel(va)
            proto = self.m.rel_ind(cd)
            if not proto or proto[0] != 'simbolo' or proto[1] != '_$s7SwiftUI4ViewMp':
                continue
            flags = self.m.u32(cd + 12)
            tref = self.m.rel(cd + 4)
            d = self.m.ranura(tref) if (flags >> 3) & 7 == 1 else ('local', tref)
            try:
                tipo = self.nombre_de(d)
            except (ValueError, struct.error):
                continue
            p = cd + 16 + (4 if flags & (1 << 6) else 0) + 12 * ((flags >> 8) & 0xFF)
            if not flags & (1 << 16):
                continue
            for i in range(self.m.u32(p)):
                q = p + 4 + 8 * i
                req = self.m.rel_ind(q)
                if req and req[0] == 'simbolo' and '4body' in req[1]:
                    out[tipo] = self.m.rel(q + 4)
        return out

    def _ensamblado(self):
        """El __text desensamblado una vez (llvm-objdump), por función."""
        if hasattr(self, '_asm'):
            return self._asm
        import bisect
        import hashlib
        import tempfile
        cache = os.path.expanduser('~/.cache/mint-macos/swiftui')
        os.makedirs(cache, exist_ok=True)
        clave = hashlib.sha1(self.m.b[:4096] + str(len(self.m.b)).encode()).hexdigest()
        asm = os.path.join(cache, clave + '.asm')
        if not os.path.exists(asm):
            with tempfile.NamedTemporaryFile(dir=cache, suffix='.bin') as f:
                f.write(self.m.b)
                f.flush()
                r = subprocess.run(['llvm-objdump-18', '-d', '--no-show-raw-insn', '-M', 'intel', f.name],
                                   capture_output=True, text=True)
            open(asm, 'w').write(r.stdout)
        ini = self.m.inicios
        por = {}
        for ln in open(asm):
            mm = re.match(r'\s*([0-9a-f]+):\s+(.*)', ln)
            if mm:
                a = int(mm.group(1), 16)
                k = bisect.bisect_right(ini, a) - 1
                if k >= 0:
                    por.setdefault(ini[k], []).append(mm.group(2))
        self._asm = por
        return por

    def stubs(self):
        """{dirección del stub: la función importada, ya legible}: a quién llama el código."""
        if hasattr(self, '_stubs'):
            return self._stubs
        out = {}
        a, t = self.m.secs.get('__stubs', (0, 0))
        crudos = {}
        for va in range(a, a + t, 6):
            o = self.m.off(va)
            if self.m.b[o:o + 2] == b'\xff\x25':
                d = self.m.ranura(va + 6 + struct.unpack_from('<i', self.m.b, o + 2)[0])
                if d[0] == 'simbolo':
                    crudos[va] = d[1]
        swift = [(k, v) for k, v in crudos.items() if v.startswith('_$s')]
        for (k, _v), t_ in zip(swift, demangle([v[1:] for _k, v in swift])):
            out[k] = t_
        self._stubs = out
        return out

    # A quién se le pasa un texto: el tipo de control que lo pone, o «oculto» si no se ve.
    # Solo los que reciben el texto: accessibilityIdentifier o AddTraits no cuentan, y si se
    # tomaran se llevarían el título de un Picker cuya etiqueta se arma en un closure aparte.
    CONSUMIDORES = [('accessibilityLabel', 'oculto'), ('accessibility(label', 'oculto'), ('accessibilityHint', 'oculto'),
                    ('accessibilityValue', 'oculto'), ('.help(', 'oculto'), ('Text.init', 'Text'),
                    ('Toggle.init', 'Toggle'), ('Picker.init', 'Picker'), ('Button.init', 'Button'),
                    ('Label.init', 'Label'), ('LabeledContent.init', 'LabeledContent'),
                    ('Section.init', 'Section'), ('Slider.init', 'Slider'), ('Stepper.init', 'Stepper'),
                    ('Link.init', 'Link'), ('Menu.init', 'Menu'), ('TextField.init', 'TextField'),
                    ('DisclosureGroup.init', 'DisclosureGroup'), ('navigationTitle', 'titulo')]

    def consumidor(self, nombre):
        for k, v in self.CONSUMIDORES:
            if k in nombre:
                return v
        return None

    def cadenas(self, f, prof=0, vistos=None):
        """Las cadenas que usa una función y las que llama o pasa como closure, en orden: las
        largas por su dirección en __cstring, las cortas (hasta 15 bytes) por los dos inmediatos
        de 64 bits con que Swift las arma."""
        vistos = set() if vistos is None else vistos
        if f in vistos or prof > 6:
            return []
        vistos.add(f)
        asm = self._ensamblado()
        cs_a, cs_t = self.m.secs.get('__cstring', (0, 0))
        tx_a, tx_t = self.m.secs.get('__text', (0, 0))
        inicios = set(self.m.inicios)
        res, inm = [], []
        stubs = self.stubs()
        pendientes = []  # índices en res de las cadenas que todavía no se le pasaron a nadie

        def agregar(c):
            pendientes.append(len(res))
            res.append([c, None])

        def vaciar():
            for k, v in enumerate(inm):
                if v >> 60 == 0xE:
                    otro = inm[k - 1] if k > 0 and inm[k - 1] >> 60 != 0xE else (
                        inm[k + 1] if k + 1 < len(inm) and inm[k + 1] >> 60 != 0xE else 0)
                    try:
                        agregar((otro.to_bytes(8, 'little') + v.to_bytes(8, 'little')[:7])[:(v >> 56) & 0x0F].decode())
                    except UnicodeDecodeError:
                        pass
            inm.clear()
        for ln in asm.get(f, []):
            mm = re.match(r'(?:movabs|mov)\s+\w+, (-?0x[0-9a-f]+)$', ln.strip())
            if mm:
                inm.append(int(mm.group(1), 16) & 0xFFFFFFFFFFFFFFFF)
                continue
            mm = re.search(r'#+ (0x[0-9a-f]+)', ln)
            if ln.startswith(('call', 'jmp')) or mm:
                vaciar()
            if mm and ln.startswith('lea'):
                t = int(mm.group(1), 16)
                for c in (t + 32, t):
                    if cs_a <= c < cs_a + cs_t:
                        agregar(self.m.cstr(c))
                        break
                else:
                    if tx_a <= t < tx_a + tx_t and t in inicios:
                        res += self.cadenas(t, prof + 1, vistos)
                continue
            mm = re.match(r'(?:call|jmp)\s+(0x[0-9a-f]+)', ln)
            if mm:
                t = int(mm.group(1), 16)
                if t in stubs:
                    tipo = self.consumidor(stubs[t])
                    if tipo:
                        for i in pendientes:
                            res[i][1] = tipo
                        pendientes.clear()
                elif tx_a <= t < tx_a + tx_t and t in inicios:
                    res += self.cadenas(t, prof + 1, vistos)
        vaciar()
        return res

    def claves_por_vista(self, tabla):
        """{vista: [claves de texto en el orden en que su body las usa]}, solo las que están en la
        tabla de textos del bundle y se ven (sin las de deshacer, ayuda ni accesibilidad)."""
        if not tabla:
            return {}
        # Las de deshacer (en Sequoia la clave es el texto: «Change Dock position»), ayudas y accesibilidad.
        oculta = re.compile(r'(_UNDO|_TOOLTIP|_HELP|_AX|_ACCESSIBILITY|\.accessibility|^Change )')
        out = {}
        for vista, f in self.bodies().items():
            ks = []
            for c, tipo in self.cadenas(f):
                if c in tabla and not oculta.search(c) and tipo != 'oculto':
                    ks.append((c, tipo))
            out[vista] = ks
        return out

    # --- las vistas ---

    def vistas(self):
        """[(nombre de la vista, mangled del body)] de cada conformidad a SwiftUI.View."""
        a, tam = self.m.secs['__swift5_assocty']
        out = []
        va = a
        while va < a + tam:
            conf = self.m.mangled(self.m.rel(va))
            proto = ''.join(x for x in self.m.mangled(self.m.rel(va + 4)) if isinstance(x, str))
            n, rs = struct.unpack_from('<II', self.m.b, self.m.off(va + 8))
            for k in range(n):
                r = va + 16 + k * rs
                if self.m.cstr(self.m.rel(r)) == 'Body' and proto.endswith('7SwiftUI4ViewP'):
                    out.append((conf, self.m.mangled(self.m.rel(r + 4))))
            va += 16 + n * rs
        return out


class Nodo:
    """Un tipo: nombre, argumentos genéricos (o los elementos de una tupla) y la clase de nodo."""

    def __init__(self, nombre, args=None, clase='tipo'):
        self.nombre, self.args, self.clase = nombre, args or [], clase

    def __repr__(self):
        if self.clase == 'tupla':
            return '(%s)' % ', '.join(map(repr, self.args))
        if self.clase == 'opcional':
            return '%r?' % self.args[0]
        if self.args:
            return '%s<%s>' % (self.nombre, ', '.join(map(repr, self.args)))
        return self.nombre

    def json(self):
        return {'tipo': self.nombre, 'clase': self.clase, 'args': [a.json() for a in self.args]}


ESTANDAR = {'S': 'String', 'i': 'Int', 'b': 'Bool', 'd': 'Double', 'f': 'Float', 'u': 'UInt', 'y': 'Void',
            'a': 'Array', 'D': 'Dictionary', 'h': 'Set', 'q': 'Optional', 'P': 'UnsafePointer', 'c': 'Character'}


class Pila:
    """Lee la gramática de tipos de Swift que sale en los body de SwiftUI con una pila, como el
    Demangler de Swift: «y» abre una lista, «_» marca el primer elemento o separa niveles, «G»
    cierra un genérico, «t» una tupla, «Sg» es el opcional y «Qo» el tipo opaco de un
    modificador (el «some View» de .padding(), .help()…), que queda como Modificador<contenido>.
    Las referencias simbólicas ya vienen resueltas a nombres (lector.nombre_de)."""

    # Qué entra a la tabla de sustituciones (comprobado contra los body de System Settings).
    SUBS = {'ref': True, 'ref_opaco': False, 'generico': True, 'opcional': True, 'opaco': True, 'tupla': False}

    def __init__(self, lector, partes, subs=None):
        self.l, self.p, self.i = lector, partes, 0
        self.pila, self.subs = [], []
        self.reglas = dict(self.SUBS, **(subs or {}))

    def sub(self, regla, n):
        if self.reglas[regla]:
            self.subs.append(n)

    def ver(self, k=0):
        j = self.i + k
        return self.p[j] if j < len(self.p) else None

    def leer(self):
        try:
            while self.i < len(self.p):
                self.paso()
        except (ValueError, IndexError, AttributeError) as e:
            # Lo que no se entiende no tumba la vista: lo leído hasta ahí, marcado.
            tipos = [x for x in self.pila if isinstance(x, Nodo)]
            if not tipos:
                raise ValueError('no se pudo leer: %s' % e) from e
            return Nodo('⚠ %s' % e, tipos, 'incompleto')
        tipos = [x for x in self.pila if isinstance(x, Nodo)]
        if len(tipos) != 1:
            raise ValueError('quedaron %d nodos' % len(tipos))
        return tipos[0]

    def numero(self):
        n = ''
        while isinstance(self.ver(), str) and self.ver().isdigit():
            n += self.p[self.i]
            self.i += 1
        return n

    def indice(self):
        """INDEX: «_» = 0, «N_» = N+1."""
        n = self.numero()
        if self.ver() == '_':
            self.i += 1
        return int(n) + 1 if n else 0

    def tipos_hasta_marca(self):
        """Los tipos de arriba de la pila hasta una marca (sin sacarla)."""
        out = []
        while self.pila and isinstance(self.pila[-1], Nodo):
            out.append(self.pila.pop())
        return out[::-1]

    def paso(self):
        c = self.p[self.i]
        self.i += 1
        if not isinstance(c, str):
            clase, destino = c
            d = self.l.m.ranura(destino) if clase == 2 else ('local', destino) if clase == 1 else ('otro', destino)
            if self.l.es_opaco(d) and d[0] == 'simbolo':
                n = Nodo(self.l.modificador(d[1]), clase='opaco')
            elif self.l.es_opaco(d):
                n = Nodo('some View', clase='opaco-local')
                n.local = d[1]
            else:
                n = Nodo(self.l.nombre_de(d))
            self.pila.append(n)
            self.sub('ref_opaco' if n.clase.startswith('opaco') else 'ref', n)
            return
        if c == 'y':
            self.pila.append('y')
        elif c == '_':
            self.pila.append('_')
        elif c == 'G':
            niveles = []
            while True:
                niveles.append(self.tipos_hasta_marca())
                m = self.pila.pop() if self.pila else None
                if m == 'y':
                    break
                if m != '_':
                    raise ValueError('G sin y')
            base = self.pila.pop()
            args = [a for nivel in niveles[::-1] for a in nivel]
            n = Nodo(base.nombre, args, 'opcional' if base.nombre == 'Optional' and len(args) == 1 else 'tipo')
            self.pila.append(n)
            self.sub('generico', n)
        elif c == 't':
            if self.pila and self.pila[-1] == 'y':
                self.pila.pop()
                elems = []
            else:
                elems = []
                while True:
                    marca = self.pila and self.pila[-1] == '_'
                    if marca:
                        self.pila.pop()
                    elems.append(self.pila.pop())
                    if marca:
                        break
                elems = elems[::-1]
            n = Nodo('', elems, 'tupla')
            self.pila.append(n)
            self.sub('tupla', n)
        elif c == 'S':
            k = self.p[self.i]
            self.i += 1
            if k == 'g':
                n = Nodo('Optional', [self.pila.pop()], 'opcional')
                self.pila.append(n)
                self.sub('opcional', n)
            elif k == 'o':
                pass  # el módulo __C: lo que sigue es un nombre
            elif k in ESTANDAR:
                self.pila.append(Nodo(ESTANDAR[k]))
            else:
                self.pila.append(Nodo('S' + k))
        elif c == 'Q' and self.ver() == 'o':
            self.i += 1
            self.indice()
            # Los argumentos del opaco, hasta su declaración (Modificador<contenido, …>).
            args = []
            while self.pila and not (isinstance(self.pila[-1], Nodo) and self.pila[-1].clase in ('opaco', 'opaco-local')):
                x = self.pila.pop()
                if isinstance(x, Nodo):
                    args.append(x)
                elif x == 'y':
                    pass
            decl = self.pila.pop()
            if decl.clase == 'opaco-local':
                n = self.l.arbol_opaco(decl.local)
            else:
                n = Nodo(decl.nombre, args[::-1], 'modificador')
            self.pila.append(n)
            self.sub('opaco', n)
        elif c == 'A':
            # Sustituciones, como demangleMultiSubstitutions de Swift: minúsculas (índice < 26, siguen
            # más), una mayúscula (la última), o un número y «_» (índice número + 27); un número
            # delante de una letra es cuántas veces se repite.
            rep = -1
            while True:
                x = self.p[self.i]
                self.i += 1
                if x.islower():
                    for _ in range(max(rep, 1)):
                        self.pila.append(self.subs[ord(x) - 97])
                    rep = -1
                    continue
                if x.isupper():
                    for _ in range(max(rep, 1)):
                        self.pila.append(self.subs[ord(x) - 65])
                    break
                if x == '_':
                    self.pila.append(self.subs[rep + 27])
                    break
                self.i -= 1
                rep = int(self.numero())
        elif c == 'x':
            self.pila.append(Nodo('T'))  # el parámetro genérico de una vista genérica
        elif c == 'p':
            # Un existencial («any P»): la lista de protocolos, como una tupla.
            protos = []
            while self.pila and isinstance(self.pila[-1], Nodo):
                protos.append(self.pila.pop())
                if self.pila and self.pila[-1] == '_':
                    self.pila.pop()
                    break
            if self.pila and self.pila[-1] == 'y':
                self.pila.pop()
            n = Nodo('any ' + ' & '.join(p.nombre for p in protos[::-1]))
            self.pila.append(n)
            self.sub('ref', n)
        elif c == 'X':
            # Xc (existencial con clase), Xp (metatipo de existencial)…: el tipo queda igual.
            self.i += 1
        elif c == '0' and isinstance(self.ver(), str) and self.ver().isalpha():
            # Identificador con palabras repetidas («0aB0»): no se reconstruye; un nombre genérico.
            while isinstance(self.ver(), str) and (self.ver().isalpha() or self.ver() == '0'):
                self.i += 1
            self.pila.append(Nodo('…'))
        elif c.isdigit():
            # Un identificador suelto: «7SwiftUI» (módulo) seguido de otro y del tipo.
            n = c + self.numero()
            nombre = ''.join(self.p[self.i:self.i + int(n)])
            self.i += int(n)
            self.pila.append(Nodo(nombre))
        elif c in 'VCO':
            # Cierra un nombre nominal: contexto + identificador.
            ident = self.pila.pop()
            if self.pila and isinstance(self.pila[-1], Nodo) and self.pila[-1].clase == 'contexto':
                ctx = self.pila.pop()
                ident = Nodo(ctx.nombre + '.' + ident.nombre)
            self.pila.append(ident)
            self.sub('ref', ident)
        else:
            raise ValueError('no sé leer %r' % c)


# --- del tipo a un árbol de interfaz -----------------------------------------------

# Lo que no se pinta: envoltorios cuyo contenido es el primer argumento.
ENVOLTORIOS = {'ModifiedContent', 'Group', 'AnyView', '_ConditionalContent', 'Optional', '_VariadicView.Tree',
               'TupleView', 'IDView', 'StaticIf', '_ViewModifier_Content', 'EquatableView', 'Optional'}
# Contenedores: sus hijos son todos los argumentos que son vistas.
CONTENEDORES = {'VStack', 'HStack', 'ZStack', 'LazyVStack', 'LazyHStack', 'LazyVGrid', 'LazyHGrid', 'Grid',
                'GridRow', 'Form', 'List', 'Section', 'ScrollView', 'NavigationStack', 'NavigationView',
                'NavigationSplitView', 'GroupBox', 'DisclosureGroup', 'ViewThatFits', 'FormFooterContent',
                'LabeledContent', 'TabView', 'Menu', 'ControlGroup', 'GeometryReader', 'ScrollViewReader'}
# Controles: una hoja con nombre propio (sus argumentos son su etiqueta).
CONTROLES = {'Text', 'Toggle', 'Picker', 'Button', 'Image', 'Spacer', 'Divider', 'Slider', 'Stepper', 'TextField',
             'SecureField', 'Link', 'HelpLink', 'ProgressView', 'Label', 'Color', 'Circle', 'Rectangle',
             'RoundedRectangle', 'Capsule', 'DatePicker', 'ColorPicker', 'EmptyView', 'Toggle', 'Gauge', 'TextEditor'}
# Tipos que no son vistas (datos, estilos, colecciones) y no se pintan como hijos.
NO_VISTAS = {'Int', 'String', 'Bool', 'Double', 'Float', 'Array', 'Dictionary', 'Set', 'Void', 'T', '…',
             'Binding', 'State', 'Range', 'UInt'}


def corto(nombre):
    """«SwiftUI.VStack» → «VStack»; las de la app quedan con su nombre sin módulo."""
    return nombre.split('.', 1)[1] if '.' in nombre and not nombre.startswith('_VariadicView') else nombre


def es_estilo(n):
    return n.nombre.endswith('Style') or n.nombre.endswith('Modifier') or n.nombre.startswith('_') and n.nombre not in ENVOLTORIOS


def a_ui(n, vistas, modulo, prof=0, mods=None, textos=None, cursor=None):
    """Un Nodo de tipo → {'clase', 'props', 'hijos'} para el visor, con las vistas del módulo
    expandidas a su body y los modificadores juntados en la vista que modifican."""
    mods = list(mods or [])
    if prof > 60:
        return {'clase': '…', 'props': {}, 'hijos': []}
    nom = n.nombre
    if n.clase == 'incompleto':
        hijos = [a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor) for a in n.args]
        return {'clase': 'Incompleto', 'props': {'aviso': nom}, 'hijos': hijos}
    if n.clase == 'tupla':
        return {'clase': 'Tupla', 'props': {}, 'hijos': [a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor) for a in n.args if es_vista(a)]}
    if n.clase == 'opcional':
        # Un «if» sin else: la vista sale solo a veces (el aviso de un perfil que administra el ajuste).
        r = a_ui(n.args[0], vistas, modulo, prof + 1, mods, textos, cursor)
        r['props'] = dict(r['props'], condicional=True)
        return r
    if n.clase == 'modificador':
        if not n.args:
            return {'clase': 'Vista', 'props': {'modificadores': mods + [nom]}, 'hijos': []}
        resto = [a.nombre for a in n.args[1:] if a.nombre]
        return a_ui(n.args[0], vistas, modulo, prof + 1, mods + [nom + ('(%s)' % ', '.join(map(corto, resto)) if resto else '')],
                    textos, cursor)
    base = corto(nom)
    # Una vista de la app: se expande a su body.
    if nom in vistas and prof < 40:
        # Los Text de esta vista toman sus claves en orden (textos: {vista: [(clave, texto)]}); las
        # copias de una misma vista siguen la lista donde quedó la anterior (los tres botones de
        # tema de Appearance: Light, Dark, Auto).
        cursores = (textos or {}).setdefault('_cursores', {})
        if nom not in cursores:
            cursores[nom] = {'lista': list((textos or {}).get(nom, [])), 'i': 0}
        elif cursores[nom]['i'] >= len(cursores[nom]['lista']):
            cursores[nom]['i'] = 0
        sub = a_ui(vistas[nom], vistas, modulo, prof + 1, mods, textos, cursores[nom])
        sub['props'] = dict(sub['props'], vista=nom)
        return sub
    if base == 'ModifiedContent' and n.args:
        return a_ui(n.args[0], vistas, modulo, prof + 1, mods + [corto(n.args[1].nombre) if len(n.args) > 1 else ''],
                    textos, cursor)
    if base in ENVOLTORIOS or base.startswith('_ConditionalContent'):
        hijos = [a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor) for a in n.args if es_vista(a)]
        if base == '_ConditionalContent' and hijos:
            # Las dos ramas del if: se pinta la primera; la otra queda anotada.
            h = hijos[0]
            h['props'] = dict(h['props'], otra_rama=len(hijos) > 1)
            if mods:
                h['props']['modificadores'] = mods + h['props'].get('modificadores', [])
            return h
        if len(hijos) == 1:
            h = hijos[0]
            if mods:
                h['props'] = dict(h['props'], modificadores=mods + h['props'].get('modificadores', []))
            return h
        return {'clase': 'Tupla', 'props': {'modificadores': mods} if mods else {}, 'hijos': hijos}
    props = {'tipo': repr(n)[:400]}
    if mods:
        props['modificadores'] = mods
    if base == 'ForEach' and len(n.args) >= 3:
        # ForEach<Datos, Id, Contenido>: el contenido, que se repite.
        # Lo que repite un ForEach sale de datos (los casos de un enum), no de las claves del body
        # de esta vista: no toma de su lista.
        h = a_ui(n.args[2], vistas, modulo, prof + 1, textos=textos, cursor=None)
        return {'clase': 'ForEach', 'props': props, 'hijos': [h]}
    if base in CONTENEDORES or base not in CONTROLES:
        hijos = [a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor) for a in n.args if es_vista(a)]
        return {'clase': base, 'props': props, 'hijos': hijos}
    if cursor is not None:
        tomar(cursor, base, props)
    # Un control: sus argumentos de vista son su etiqueta. En un Picker el primero es la etiqueta y
    # el resto las opciones; en el código las opciones van antes que el título (ver tomar).
    if base == 'Picker' and cursor is not None:
        hijos = []
        for k, a in enumerate(x for x in n.args if es_vista(x)):
            anterior = cursor.get('modo')
            cursor['modo'] = 'etiqueta' if k == 0 else 'opcion'
            hijos.append(a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor))
            cursor['modo'] = anterior
        if cursor.get('opciones'):
            props['opciones'] = cursor.pop('opciones')
        return {'clase': base, 'props': props, 'hijos': hijos}
    hijos = [a_ui(a, vistas, modulo, prof + 1, textos=textos, cursor=cursor) for a in n.args if es_vista(a)]
    return {'clase': base, 'props': props, 'hijos': hijos}


def tomar(cursor, base, props):
    """Le pone a un control el texto que el código le pasa: el siguiente de la lista de su vista
    que se le pasó a ese tipo de control (Toggle.init → Toggle). Un Text toma los que se le pasaron
    a Text.init; si un control ya tomó su título, su Text de adentro (la etiqueta) no toma otro."""
    lista = cursor['lista']
    if base == 'Text' and cursor.get('saltar_texto'):
        cursor['saltar_texto'] = False
        return
    i = cursor['i']
    while i < len(lista) and lista[i][2] in ('Slider', 'Stepper', 'titulo'):
        i += 1  # títulos que no se pintan como texto (el de un deslizador va oculto)
    if i >= len(lista):
        return
    clave, texto, tipo = lista[i]
    if base in ('Slider', 'Stepper', 'Gauge'):
        # Su etiqueta va escondida (.labelsHidden) y no sale en el tipo, pero el código la arma:
        # se la come para no correr las de abajo («Dock Size» en Desktop & Dock).
        if tipo in ('Text', None, base):
            props['etiqueta_oculta'] = texto
            cursor['i'] = i + 1
        return
    modo = cursor.get('modo')
    if base == 'Text' and modo in ('etiqueta', 'opcion'):
        # La etiqueta de un Picker: el siguiente que se le pasó a Text.init (o al Picker); una opción:
        # el siguiente sin tipo. Se sacan de la lista sin correr el cursor sobre los otros.
        quiere = ('Text', 'Picker', 'Label') if modo == 'etiqueta' else (None,)
        for j in range(i, len(lista)):
            if lista[j][2] in quiere:
                props['clave'], props['texto'] = lista[j][0], lista[j][1]
                if modo == 'etiqueta':
                    # Lo que el código armó antes del título y sin tipo son las opciones del Picker.
                    ops = [k for k in range(i, j) if lista[k][2] is None]
                    cursor['opciones'] = [{'clave': lista[k][0], 'texto': lista[k][1]} for k in ops]
                    for k in reversed(ops + [j]):
                        lista.pop(k)
                else:
                    lista.pop(j)
                return
        return
    if base == 'Text' and tipo in ('Text', None, 'Label'):
        props['clave'], props['texto'] = clave, texto
        cursor['i'] = i + 1
    elif base == tipo and base in ('Toggle', 'Picker', 'Button', 'Label', 'LabeledContent', 'Section', 'Link', 'Menu',
                                   'TextField', 'DisclosureGroup'):
        props['clave'], props['texto'] = clave, texto
        cursor['i'] = i + 1
        cursor['saltar_texto'] = True


def es_vista(n):
    if n.clase in ('tupla', 'modificador', 'opcional', 'incompleto', 'opaco-local'):
        return True
    b = corto(n.nombre)
    return b not in NO_VISTAS and not es_estilo(n) and not b[:1].islower()


def app_swiftui(ejecutable):
    """Las vistas de un ejecutable: {nombre: Nodo del body} y las raíces (las que ninguna otra
    usa), de la más grande a la más chica."""
    lec = Lector(ejecutable)
    vistas = {}
    for conf, body in lec.vistas():
        try:
            nombre = lec.nombre_de(('local', conf[0][1])) if len(conf) == 1 and not isinstance(conf[0], str) else None
        except (ValueError, struct.error):
            nombre = None
        if not nombre:
            continue
        try:
            vistas[nombre] = Pila(lec, body).leer()
        except ValueError:
            continue

    usadas = set()

    def marcar(n):
        if n.nombre in vistas:
            usadas.add(n.nombre)
        for a in n.args:
            marcar(a)
    for v in vistas.values():
        marcar(v)

    memo = {}

    def tam(nombre, camino=()):
        """Cuántos nodos tiene la vista ya expandida (con memoria: sin ella, crece exponencial)."""
        if nombre in memo:
            return memo[nombre]
        if nombre in camino:
            return 1

        def nodos(n):
            if n.nombre in vistas:
                return tam(n.nombre, camino + (nombre,))
            return 1 + sum(nodos(a) for a in n.args)
        memo[nombre] = r = nodos(vistas[nombre])
        return r
    raices = sorted((v for v in vistas if v not in usadas), key=lambda v: -tam(v))
    return vistas, raices


def textos_swiftui(ejecutable, tabla):
    """{vista: [(clave, texto)]} para a_ui: los textos que usa el body de cada vista, en orden,
    con su texto en inglés de la tabla del bundle (Localizable.loctable o .strings)."""
    if not tabla:
        return {}
    try:
        lec = Lector(ejecutable)
        return {v: [(k, tabla[k], tipo) for k, tipo in ks] for v, ks in lec.claves_por_vista(tabla).items()}
    except (ValueError, KeyError, OSError, struct.error, subprocess.SubprocessError):
        return {}


def demangle(nombres):
    if not nombres:
        return []
    r = subprocess.run([os.path.join(DEMANGLE, 'bin', 'swift-demangle'), '-simplified'], input='\n'.join(nombres) + '\n',
                       capture_output=True, text=True, env=dict(os.environ, LD_LIBRARY_PATH=os.path.join(DEMANGLE, 'lib')))
    return r.stdout.rstrip('\n').split('\n')


def resolver(texto, refs):
    """Cambia cada __C.RefN (y RefN) por su nombre, de las más largas a las más cortas."""
    for k in sorted(refs, key=len, reverse=True):
        texto = texto.replace('__C.' + k, refs[k]).replace(k, refs[k])
    return texto


def leer(ruta):
    lec = Lector(ruta)
    crudas = lec.vistas()
    nombres = [(lec.legible(c), lec.legible(b)) for c, b in crudas]
    planos = demangle([x for par in nombres for x in par])
    out = []
    for i in range(len(nombres)):
        vista = resolver(planos[2 * i], lec.refs)
        body = resolver(planos[2 * i + 1], lec.refs)
        out.append({'vista': vista, 'body': body, 'mangled': nombres[i][1]})
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    vistas = leer(sys.argv[1])
    if '--json' in sys.argv:
        json.dump(vistas, open(sys.argv[sys.argv.index('--json') + 1], 'w'), ensure_ascii=False, indent=1)
        return
    for v in vistas:
        print('%s\n    %s\n' % (v['vista'], v['body']))


if __name__ == '__main__':
    main()
