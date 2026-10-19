"""El vocabulario común de los perfiles (ESQUEMA.md, «Formato de una interfaz»): un nodo de un nib
(Catalina, Monterey) o de una vista SwiftUI (Sequoia, 27) pasa a

    {"clase": "casilla", "props": {"id": …, "texto": …, "ajuste": …}, "hijos": [...]}

con clases que las piezas entienden sin saber de AppKit ni de SwiftUI. El id es el estable: la
clave del texto, la acción, el identificador o el ajuste enlazado.
"""

# Clases del vocabulario.
VENTANA, GRUPO_V, GRUPO_H, SECCION, FILA = 'ventana', 'grupo-v', 'grupo-h', 'seccion', 'fila'
BOTON, CASILLA, RADIO, INTERRUPTOR, SELECTOR = 'boton', 'casilla', 'radio', 'interruptor', 'selector'
DESLIZADOR, CAMPO, TEXTO, IMAGEN, LISTA, TABLA = 'deslizador', 'campo', 'texto', 'imagen', 'lista', 'tabla'
PESTANAS, PESTANA, SEPARADOR, ESPACIO, AYUDA, OTRO = 'pestanas', 'pestana', 'separador', 'espacio', 'ayuda', 'otro'


def _id(p):
    """El id estable de un control, en orden de preferencia."""
    for k in ('clave', 'accion', 'identificador', 'ajuste'):
        if p.get(k):
            return '%s:%s' % (k, p[k])
    return None


def _nodo(clase, p, hijos=None, **extra):
    props = {k: v for k, v in extra.items() if v not in (None, [], {})}
    i = _id(p)
    if i:
        props['id'] = i
    for k in ('texto', 'ajuste', 'enlaces', 'marco', 'ayuda', 'imagen', 'clave', 'accion'):
        if p.get(k) not in (None, '') and k not in props:
            props[k] = p[k]
    return {'clase': clase, 'props': props, 'hijos': hijos or []}


def _orden(hijos):
    """De arriba abajo y de izquierda a derecha (el orden en que se leen)."""
    def k(n):
        m = n['props'].get('marco') or [0, 0, 0, 0]
        return (round(m[1] / 4), m[0])
    return sorted(hijos, key=k)


def desde_nib(n):
    """Un nodo de herramientas/visor-nib/nib.py → vocabulario. None si no se ve (oculto)."""
    c, p = n['clase'], n['props']
    if p.get('oculta'):
        return None
    hijos = [h for h in (desde_nib(x) for x in n['hijos']) if h]
    if c == 'NSWindowTemplate':
        cont = [h for h in hijos if h['clase'] != 'menu']
        return _nodo(VENTANA, p, cont[0]['hijos'] if len(cont) == 1 and cont[0]['clase'] == GRUPO_V else cont,
                     titulo=p.get('titulo'))
    if c == 'NSButton':
        tipo = p.get('tipo_boton')
        if tipo == 'casilla':
            return _nodo(CASILLA, p)
        if tipo == 'radio':
            return _nodo(RADIO, p)
        if p.get('accion', '').endswith('HelpLookup:') or p.get('accion') == 'doHelp:':
            return _nodo(AYUDA, p)
        return _nodo(BOTON, p)
    if c == 'NSMatrix':
        return _nodo(RADIO if p.get('tipo_boton') == 'radio' else SELECTOR, p, opciones=p.get('opciones'))
    if c in ('NSPopUpButton', 'NSComboBox'):
        ops = []
        for m in n['hijos']:
            for it in m['hijos']:
                q = it['props']
                if q.get('separador') or not q.get('titulo'):
                    continue
                o = {'texto': q['titulo']}
                if q.get('clave'):
                    o['id'] = 'clave:' + q['clave']
                if q.get('marcado'):
                    o['elegida'] = True
                ops.append(o)
        return _nodo(SELECTOR, p, opciones=ops)
    if c in ('NSSlider', 'NSLevelIndicator'):
        return _nodo(DESLIZADOR, p)
    if c in ('NSTextField', 'NSSearchField', 'NSSecureTextField', 'NSTokenField'):
        # Un rótulo trae texto fijo; un campo, no (o es de búsqueda).
        return _nodo(TEXTO if p.get('texto') and c == 'NSTextField' else CAMPO, p)
    if c in ('NSImageView',):
        return _nodo(IMAGEN, p)
    if c in ('NSTableView', 'NSOutlineView'):
        return _nodo(TABLA, p, columnas=[{'texto': k.get('titulo'), 'id': k.get('identificador')}
                                         for k in p.get('columnas', []) if not k.get('oculta')])
    if c == 'NSTabView':
        return _nodo(PESTANAS, p, [h for h in hijos if h['clase'] == PESTANA])
    if c == 'NSTabViewItem':
        return _nodo(PESTANA, p, hijos[0]['hijos'] if len(hijos) == 1 else hijos, titulo=p.get('titulo'))
    if c == 'NSBox':
        cont = hijos[0]['hijos'] if len(hijos) == 1 and hijos[0]['clase'] == GRUPO_V else hijos
        if not cont:
            return _nodo(SEPARADOR, p)
        return _nodo(SECCION, p, _orden(cont), titulo=p.get('titulo') if p.get('titulo') not in ('Box', 'Title') else None)
    if c == 'NSMenu':
        return None  # los menús de un control ya van en sus opciones
    if c in ('NSView', 'NSCustomView', 'NSClipView', 'NSScrollView', 'NSStackView', 'NSVisualEffectView', 'NSGridView'):
        if not hijos:
            return None if c != 'NSCustomView' else _nodo(OTRO, p, clase_mac=p.get('clase_propia') or c)
        if len(hijos) == 1 and c != 'NSScrollView':
            return hijos[0]
        return _nodo(GRUPO_V, p, _orden(hijos))
    return _nodo(OTRO, p, _orden(hijos), clase_mac=p.get('clase_propia') or c)


# --- SwiftUI ------------------------------------------------------------------------

SWIFTUI = {'Form': GRUPO_V, 'List': LISTA, 'ScrollView': GRUPO_V, 'VStack': GRUPO_V, 'LazyVStack': GRUPO_V,
           'HStack': GRUPO_H, 'LazyHStack': GRUPO_H, 'ZStack': GRUPO_V, 'Section': SECCION, 'Toggle': INTERRUPTOR,
           'Picker': SELECTOR, 'Slider': DESLIZADOR, 'Stepper': CAMPO, 'TextField': CAMPO, 'SecureField': CAMPO,
           'Text': TEXTO, 'Label': TEXTO, 'Image': IMAGEN, 'Button': BOTON, 'HelpLink': AYUDA, 'Divider': SEPARADOR,
           'Spacer': ESPACIO, 'TabView': PESTANAS, 'LabeledContent': FILA, 'GroupBox': SECCION, 'Grid': GRUPO_V,
           'GridRow': GRUPO_H, 'ForEach': GRUPO_V, 'DisclosureGroup': SECCION, 'Menu': SELECTOR, 'Link': BOTON}


def desde_swiftui(n):
    """Un nodo de swiftui.a_ui → vocabulario."""
    c, p = n['clase'], n['props']
    hijos = []
    for h in n['hijos']:
        v = desde_swiftui(h)
        if v is None:
            continue
        # Las tuplas (TupleView) no son un nivel: sus hijos van directo.
        hijos.extend(v['hijos'] if v['clase'] == '_tupla' else [v])
    if c in ('Tupla', 'FormFooterContent'):
        return {'clase': '_tupla', 'props': {}, 'hijos': hijos}
    if c == 'EmptyView':
        return None
    mods = p.get('modificadores', [])
    extra = {'modificadores': mods, 'vista': p.get('vista'), 'condicional': p.get('condicional'),
             'texto': p.get('texto'), 'clave': p.get('clave')}
    if c == 'Toggle' and any('checkbox' in m.lower() for m in mods):
        return _nodo(CASILLA, p, hijos, **extra)
    if c == 'Picker' and any('Inline' in m or 'RadioGroup' in m for m in mods):
        return _nodo(RADIO, p, hijos, **extra)
    if c == 'Section' and len(n['hijos']) == 3:
        cab, cont, pie = (desde_swiftui(x) for x in n['hijos'])
        cuerpo = cont['hijos'] if cont and cont['clase'] == '_tupla' else ([cont] if cont else [])
        return _nodo(SECCION, p, cuerpo, cabecera=cab, pie=pie, **extra)
    return _nodo(SWIFTUI.get(c, OTRO), p, hijos, clase_swiftui=None if c in SWIFTUI else c, **extra)
