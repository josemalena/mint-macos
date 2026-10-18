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
            # Sustituciones: «A» + minúsculas (repetidas) + una mayúscula, o «A» + número + «_».
            if isinstance(self.ver(), str) and (self.ver().isdigit() or self.ver() == '_') and not self.ver(1) or (isinstance(self.ver(), str) and self.ver().isdigit() and self.ver(1) == '_') or self.ver() == '_':
                k = self.indice()
                self.pila.append(self.subs[k + 26])
                return
            while True:
                rep = self.numero()
                letra = self.p[self.i]
                self.i += 1
                if letra.islower():
                    for _ in range(int(rep) if rep else 1):
                        self.pila.append(self.subs[ord(letra) - 97])
                    continue
                for _ in range(int(rep) if rep else 1):
                    self.pila.append(self.subs[ord(letra) - 65])
                break
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
