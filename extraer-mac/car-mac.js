// car-mac.js — saca el contenido de los .car con el CoreUI de la propia Mac.
// JXA, como herramientas.js: sin swiftc ni Command Line Tools.
//
//   osascript -l JavaScript car-mac.js <recursos> <salida> [subcarpeta…]
//
// Recorre los .car de <recursos>/<subcarpeta> (por omisión «car» e «iconos») y
// deja en <salida>/<ruta relativa a recursos, con «__» por «/»>/ cada rendición
// convertida, con los mismos nombres que tema/iconos/car.py para poder
// compararlos archivo por archivo:
//   <nombre>-<ancho>x<alto>[-<atributo><valor>…][-oscuro][@<escala>x].png
// Además, por cada .car, cuenta.tsv: lo sacado y lo que no, por tipo y motivo.
//
// Qué sale de cada tipo:
//   mapas de bits (ARGB, GA8, GA16, RGBW, rle, JPEG, HEIF)  PNG sin premultiplicar
//   PDF y SVG (y glifos vectoriales)   el original, más PNG @1x y @2x («-vector»: el mapa de bits
//                                      que CoreUI guarda del mismo PDF sale con el nombre sin él)
//   efectos (CTFX)                     JSON con cada efecto y sus parámetros
//   degradados (GRAD)                  JSON con las paradas de color y de opacidad
//   multisize (MSIS)                   JSON con cada tamaño y su índice
//   datos (DATA: .caar, .caml…)        el crudo; el .caar además en .caml si se puede
//   colores                            colores-<apariencia>.json, para cotejar con el COLR
//   pilas de capas (LayerStack/Group)  JSON con cada capa: a qué rendición apunta, marco y fusión
//
// La API de CoreUI es privada: los selectores salen de mirar las clases en la
// Mac (class_copyMethodList, 26-10-2026, macOS 27.0.1). Lo que no exista en
// otra versión se anota en cuenta.tsv con su motivo; no se adivina.
// Nada de lo que sale de aquí va a un repo: es de Apple.
ObjC.import('Foundation');
ObjC.import('AppKit');
ObjC.import('QuartzCore');
ObjC.import('CoreGraphics');

// Los métodos que reciben la clave como puntero (renditionWithKey:) no aceptan
// el Ref que devuelve el puente: van por objc_msgSend con punteros crudos.
ObjC.bindFunction('sel_registerName', ['void *', ['char *']]);
ObjC.bindFunction('objc_msgSend', ['void *', ['id', 'void *', 'void *']]);
const SEL = {};
function sel(n) { return SEL[n] || (SEL[n] = $.sel_registerName(n)); }
function msg(o, n, a) { return $.objc_msgSend(o, sel(n), a === undefined ? null : a); }
function nada(o) { return !o || (o.isNil && o.isNil()); }

// Atributos de la clave con los nombres de car.py (kRenditionAttributeType_*).
// Las tres últimas car.py no las nombra: salen con su número, como allá.
// Look (0) no tiene accesor en CUIRenditionKey: no entra al nombre.
const ATRIBUTOS = [
  ['themeElement', 'elemento'], ['themePart', 'parte'], ['themeSize', 'tamaño'],
  ['themeDirection', 'dirección'], ['themeValue', 'valor'], ['themeAppearance', 'apariencia'],
  ['themeDimension1', 'dimensión1'], ['themeDimension2', 'dimensión2'], ['themeState', 'estado'],
  ['themeLayer', 'capa'], ['themeScale', 'escala'], ['themePresentationState', 'presentación'],
  ['themeIdiom', 'idiom'], ['themeSubtype', 'subtipo'], ['themeIdentifier', 'identificador'],
  ['themePreviousValue', 'valor_previo'], ['themePreviousState', 'estado_previo'],
  ['themeSizeClassHorizontal', 'clase_h'], ['themeSizeClassVertical', 'clase_v'],
  ['themeMemoryClass', 'memoria'], ['themeGraphicsClass', 'gráficos'], ['themeDisplayGamut', 'gamut'],
  ['themeDeploymentTarget', 'despliegue'], ['themeLocalization', '26'],
  ['themeGlyphWeight', '27'], ['themeGlyphSize', '28'],
];
let accesores = null;   // los que existen en esta versión de CoreUI

function atributos(k) {
  if (!accesores) accesores = ATRIBUTOS.filter(([s]) => k.respondsToSelector(s));
  const atr = {};
  for (const [s, n] of accesores) { const v = Number(k[s]); if (v) atr[n] = v; }
  return atr;
}

function fourcc(n) {
  n = n >>> 0;
  return String.fromCharCode((n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255).replace(/[\0 ]/g, '');
}

function archivo(nombre) { return nombre.replace(/\//g, '__'); }   // como archivo() de car.py

// La apariencia va por su nombre en el .car (st.appearances), no por si hay
// una: el 8 es NSAppearanceNameAqua (claro explícito) y el 10 ISAppearanceTintable,
// y los dos salían como «-oscuro» y pisaban al oscuro de verdad (1).
const APARIENCIAS = {
  NSAppearanceNameDarkAqua: '-oscuro', UIAppearanceDark: '-oscuro',
  NSAppearanceNameAqua: '-claro', UIAppearanceLight: '-claro',
  NSAppearanceNameAccessibilityDarkAqua: '-oscuro-ax', NSAppearanceNameAccessibilityAqua: '-claro-ax',
  NSAppearanceNameAccessibilitySystem: '-ax', ISAppearanceTintable: '-tintable',
};
let APAR = {};   // id → nombre, del .car que se está sacando
function sufijoApariencia(id) {
  if (!id) return '';
  const n = APAR[id];
  return (n && APARIENCIAS[n]) || `-apariencia${n ? n.replace(/^(NS|UI|IS)AppearanceName|^(NS|UI|IS)Appearance/, '') : id}`;
}

// El nombre de car.py: <nombre>-<w>x<h>[-<atr><v>…][-<apariencia>][@<e>x]
function sufijo(atr, w, h, esc) {
  const extra = Object.keys(atr).filter(k => !['identificador', 'escala', 'apariencia'].includes(k))
    .sort().map(k => `-${k}${atr[k]}`).join('');
  esc = Number(esc) || 1;   // la de la rendición (el CSI), como car.py; no la de la clave
  return `-${w}x${h}${extra}` + sufijoApariencia(atr.apariencia) + (esc !== 1 ? `@${esc}x` : '');
}

// NSNumber → número: Number() sobre el objeto del puente da NaN.
function num(x) { return nada(x) ? null : Number(ObjC.unwrap(x)); }

// ---- escritura
const FM = $.NSFileManager.defaultManager;
function carpeta(r) { FM.createDirectoryAtPathWithIntermediateDirectoriesAttributesError($(r), true, $(), null); }
// Dos rendiciones distintas pueden dar el mismo nombre (p. ej. un PDF y el mapa
// de bits que CoreUI guarda de él): la segunda lleva «-r2», «-r3»… antes de la
// extensión, en vez de pisar a la primera. USADOS se vacía en cada .car.
let USADOS = {}, REPETIDOS = 0;
function libre(ruta) {
  if (!USADOS[ruta]) { USADOS[ruta] = 1; return ruta; }
  // el «-rN» va justo antes de la extensión final (o de «@Nx.ext»)
  const m = ruta.match(/^(.*)(@\dx\.[^./]+)$/) || ruta.match(/^(.*)(\.[^./]+)$/) || [ruta, ruta, ''];
  let i = 2; while (USADOS[`${m[1]}-r${i}${m[2]}`]) i++;
  REPETIDOS++; USADOS[`${m[1]}-r${i}${m[2]}`] = 1;
  return `${m[1]}-r${i}${m[2]}`;
}
function escribirDatos(d, ruta) { return d.writeToFileAtomically($(libre(ruta)), true); }
function escribirTexto(t, ruta) { return $(t).writeToFileAtomicallyEncodingError($(libre(ruta)), true, $.NSUTF8StringEncoding, null); }
function escribirJSON(o, ruta) { return escribirTexto(JSON.stringify(o, null, 1), ruta); }

// CGImage → PNG (NSBitmapImageRep escribe el PNG sin premultiplicar):
// {datos, ancho, alto}, para que el nombre lleve el tamaño de verdad.
function png(cg) {
  if (nada(cg)) return null;
  const rep = $.NSBitmapImageRep.alloc.initWithCGImage(cg);
  if (nada(rep)) return null;
  const d = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}));
  return nada(d) ? null : { datos: d, ancho: Number(rep.pixelsWide), alto: Number(rep.pixelsHigh) };
}

// Un dibujo vectorial (PDF o SVG) a PNG del tamaño w×h en puntos, a escala e.
// NSImage lee PDF siempre y SVG desde macOS 14; si no lo lee, null.
function pngVector(datos, w, h, e, ruta) {
  const im = $.NSImage.alloc.initWithData(datos);
  if (nada(im) || !im.isValid) return null;
  if (!(w > 0 && h > 0)) { const s = im.size; w = s.width; h = s.height; }
  const pw = Math.max(1, Math.round(w * e)), ph = Math.max(1, Math.round(h * e));
  const rep = $.NSBitmapImageRep.alloc.initWithBitmapDataPlanesPixelsWidePixelsHighBitsPerSampleSamplesPerPixelHasAlphaIsPlanarColorSpaceNameBytesPerRowBitsPerPixel(
    null, pw, ph, 8, 4, true, false, $.NSDeviceRGBColorSpace, 0, 0);
  const ctx = $.NSGraphicsContext.graphicsContextWithBitmapImageRep(rep);
  $.NSGraphicsContext.saveGraphicsState;
  $.NSGraphicsContext.setCurrentContext(ctx);
  im.drawInRectFromRectOperationFraction($.NSMakeRect(0, 0, pw, ph), $.NSZeroRect, $.NSCompositingOperationCopy, 1);
  ctx.flushGraphics;
  $.NSGraphicsContext.restoreGraphicsState;
  const d = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $({}));
  return escribirDatos(d, ruta) ? [pw, ph] : null;
}

// Un trozo de NSData desde la primera aparición de una firma («%PDF»).
// Ojo: en JXA d.length y r.location llegan como texto («224» > «1360» es
// verdad entre textos): van siempre por Number().
function buscar(d, firma) {
  if (nada(d)) return -1;
  const f = $(firma).dataUsingEncoding($.NSISOLatin1StringEncoding);
  const largo = Number(d.length), r = d.rangeOfDataOptionsRange(f, 0, $.NSMakeRange(0, largo));
  const en = Number(r.location);
  return en < largo ? en : -1;
}
function desde(d, firma) {
  const en = buscar(d, firma);
  return en < 0 ? null : d.subdataWithRange($.NSMakeRange(en, Number(d.length) - en));
}

// uint32 little-endian en d[en..en+3] (por base64: el puente no da los bytes).
function u32(d, en) {
  const t = d.subdataWithRange($.NSMakeRange(en, 4)).base64EncodedStringWithOptions(0).js;
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const v = t.slice(0, 6).split('').reduce((n, c) => n * 64 + A.indexOf(c), 0);   // 36 bits: los 4 bytes y 4 de relleno
  const b = [(v / 2 ** 28) & 255, (v / 2 ** 20) & 255, (v / 2 ** 12) & 255, (v / 2 ** 4) & 255];
  return b[0] + b[1] * 256 + b[2] * 65536 + b[3] * 16777216;
}

// El PDF original del CSI: el bloque RAWD («DWAR» en disco) lleva etiqueta,
// versión y largo (4 bytes cada uno) y después el PDF tal cual, como lo lee car.py.
function pdfDelCSI(d) {
  const en = buscar(d, 'DWAR');
  if (en < 0 || en + 12 > Number(d.length)) return null;
  const largo = u32(d, en + 8);
  if (!(largo > 0) || en + 12 + largo > Number(d.length)) return null;
  const pdf = d.subdataWithRange($.NSMakeRange(en + 12, largo));
  return buscar(pdf, '%PDF') === 0 ? pdf : null;
}

// CGRect como CFData (4 doubles), para kCGPDFContextMediaBox: el puente no
// pasa un CGRect donde se espera su puntero. JXA no trae btoa.
function rectDatos(x, y, w, h) {
  const b = new Uint8Array(new Float64Array([x, y, w, h]).buffer);
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let t = '';
  for (let i = 0; i < b.length; i += 3) {
    const n = (b[i] << 16) | ((b[i + 1] || 0) << 8) | (b[i + 2] || 0);
    t += A[n >> 18 & 63] + A[n >> 12 & 63] + (i + 1 < b.length ? A[n >> 6 & 63] : '=') + (i + 2 < b.length ? A[n & 63] : '=');
  }
  return $.NSData.alloc.initWithBase64EncodedStringOptions($(t), 0);
}

// CGPDFDocument → NSData de un PDF nuevo con cada página y su MediaBox.
function pdfDeDocumento(doc) {
  if (nada(doc)) return null;
  const n = Number($.CGPDFDocumentGetNumberOfPages(doc));
  if (!n) return null;
  const md = $.NSMutableData.data;
  const ctx = $.CGPDFContextCreate($.CGDataConsumerCreateWithCFData(md), null, null);
  if (nada(ctx)) return null;
  for (let p = 1; p <= n; p++) {
    const pg = $.CGPDFDocumentGetPage(doc, p);
    const c = $.CGPDFPageGetBoxRect(pg, $.kCGPDFMediaBox);
    $.CGPDFContextBeginPage(ctx, $.NSDictionary.dictionaryWithObjectForKey(rectDatos(c.origin.x, c.origin.y, c.size.width, c.size.height), 'MediaBox'));
    $.CGContextDrawPDFPage(ctx, pg);
    $.CGPDFContextEndPage(ctx);
  }
  $.CGPDFContextClose(ctx);
  return Number(md.length) ? md : null;
}

function srgb(cg) {
  if (nada(cg)) return null;
  const c = $.NSColor.colorWithCGColor(cg);
  const s = nada(c) ? null : c.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
  if (nada(s)) return null;
  const r3 = x => Math.round(Number(x) * 1e6) / 1e6;
  return [r3(s.redComponent), r3(s.greenComponent), r3(s.blueComponent), r3(s.alphaComponent)];
}

// «Color Fill: r=0, g=0, b=0, opacity=0.6, blendMode=…» → {efecto, parámetros}.
// CUIShapeEffectPreset no da los valores por un selector que el puente lea
// (valueForParameter:inEffectAtIndex: devuelve una unión): sale de su debugDescription.
function efectos(texto) {
  const m = texto.match(/Effects:\s*\{([\s\S]*)\}/);
  if (!m) return [];
  return m[1].split('\n').map(l => l.trim()).filter(Boolean).map(l => {
    const dos = l.indexOf(': ');
    let tipo = l, resto = '';
    if (dos > 0) { tipo = l.slice(0, dos); resto = l.slice(dos + 2); }
    else { const ig = l.indexOf('='); if (ig > 0) { tipo = l.slice(0, ig); resto = 'valor=' + l.slice(ig + 1); } }
    const p = {};
    for (const par of resto.split(/,\s*/)) {
      const ig = par.indexOf('='); if (ig < 0) continue;
      const k = par.slice(0, ig).trim(), v = par.slice(ig + 1).trim();
      p[k] = v !== '' && !isNaN(Number(v)) ? Number(v) : v;
    }
    return { efecto: tipo.trim(), parametros: p };
  });
}

function colorDeCUI(c) {
  if (nada(c)) return null;
  if (c.respondsToSelector('CGColor')) { const v = srgb(c.CGColor); if (v) return v; }
  const m = String(c.description.js).match(/\(\s*([-\d.e]+(?:\s+[-\d.e]+)*)\s*\)\s*>?\s*$/);
  return m ? m[1].split(/\s+/).map(Number) : String(c.description.js);
}
function lista(a, f) { const o = []; if (nada(a)) return o; for (let i = 0; i < a.count; i++) o.push(f(a.objectAtIndex(i))); return o; }

// ---- un .car
function sacar(ruta, dest) {
  const cuenta = {};   // tipo → {sacado, faltan: {motivo: n}}
  const anota = (tipo, ok, motivo) => {
    const c = cuenta[tipo] || (cuenta[tipo] = { sacado: 0, faltan: {} });
    if (ok) c.sacado++; else c.faltan[motivo] = (c.faltan[motivo] || 0) + 1;
  };
  const cat = $.NSClassFromString('CUICatalog').alloc.initWithURLError($.NSURL.fileURLWithPath(ruta), null);
  if (nada(cat)) { anota('catálogo', false, 'CUICatalog no lo abre'); return cuenta; }
  const ts = cat._themeStore, st = ts.store;
  carpeta(dest);
  // apariencias: id → nombre
  const apar = {};
  try { const d = st.appearances; if (!nada(d)) { const ks = d.allKeys; for (let i = 0; i < ks.count; i++) { const k = ks.objectAtIndex(i); apar[num(d.objectForKey(k))] = k.js; } } } catch (e) {}
  APAR = apar; USADOS = {}; REPETIDOS = 0;
  // identificador → nombre de faceta, como FACETKEYS en car.py. Con
  // renditionNameForKeyList: el proceso se cae en algunas claves (SVG de
  // CoreTypes, 27.0.1): sale de la clave base de cada nombre.
  const facetas = {};
  try {
    const ns = st.allRenditionNames;
    for (let i = 0; !nada(ns) && i < ns.count; i++) {
      const n = ns.objectAtIndex(i), bk = cat._baseKeyForName(n);
      if (!nada(bk) && Number(bk.themeIdentifier)) facetas[Number(bk.themeIdentifier)] = n.js;
    }
  } catch (e) {}
  const colores = {};   // apariencia → [...]
  const keys = st.allAssetKeys;
  for (let i = 0; i < keys.count; i++) {
    const k = keys.objectAtIndex(i);
    let r;
    try { r = ObjC.castRefToObject(msg(ts, 'renditionWithKey:', msg(k, 'keyList'))); }
    catch (e) { anota('?', false, 'renditionWithKey: ' + e); continue; }
    if (nada(r)) { anota('?', false, 'renditionWithKey: nil'); continue; }
    const clase = $.NSStringFromClass(r.class).js;
    const pf = fourcc(r.pixelFormat);
    const atr = atributos(k);
    const fac = facetas[atr.identificador] || null;
    const nombre = archivo(fac || r.name.js || 'sin-nombre');
    const base = dest + '/' + nombre;
    const tipo = clase.replace(/^_?CUI(Theme)?/, '').replace(/Rendition$/, '') + (pf ? ' ' + pf : '');
    try {
      if (clase === '_CUIThemePixelRendition' && /^ZZZZPackedAsset/.test(r.name.js)) {
        anota(tipo, false, 'hoja empaquetada: sale por sus enlaces');
      } else if (/InternalLink|ThemePixel|RawPixel/.test(clase)) {
        // ARGB, GA8, GA16, RGBW, rle, JPEG, HEIF: lo que CoreUI ya descomprime.
        const tam = [Number(r.unslicedSize.width), Number(r.unslicedSize.height)];
        // CoreStructuredImage (InternalLink DATA, 128×128): no trae mapa de bits
        // (CUIImage.image es NULL en 27.0.1); es la descripción de un material de
        // NSVisualEffectView: sus propiedades van a un JSON.
        if (pf === 'DATA') {
          const pr = r.properties;
          const ok = !nada(pr) && escribirJSON({ tipo: 'imagen_estructurada', nombre: fac || r.name.js, atributos: atr,
            tamano: tam, propiedades: String(pr.description.js) }, base + sufijo(atr, tam[0], tam[1], r.scale) + '.json');
          anota(tipo, !!ok, 'sin propiedades');
          continue;
        }
        const t = png(r.unslicedImage);   // el nombre lleva el tamaño de verdad del PNG
        const ok = !!t && escribirDatos(t.datos, base + sufijo(atr, t.ancho, t.alto, r.scale) + '.png');
        if (clase === '_CUIRawPixelRendition' && t) {
          // el JPEG original, tal cual, si se encuentra en el CSI
          const j = pf === 'JPEG' ? desde(r.srcData, '\xff\xd8\xff') : null;
          if (j) escribirDatos(j, base + sufijo(atr, t.ancho, t.alto, r.scale) + '.jpg');
        }
        anota(tipo, ok, 'unslicedImage vacía');
      } else if (clase === '_CUIThemePDFRendition') {
        // El original sale del RAWD del CSI; si no está, el CGPDFDocument que arma
        // CoreUI, vuelto a escribir (mismo dibujo, no el byte original).
        let pdf = pdfDelCSI(r.srcData), via = 'original';
        if (!pdf) { pdf = pdfDeDocumento(r.pdfDocument); via = 'reescrito'; }
        if (!pdf) { anota(tipo, false, 'sin RAWD con %PDF ni pdfDocument'); continue; }
        anota(tipo + ' ' + via, true);
        const ip = $.NSImage.alloc.initWithData(pdf);
        const pw = nada(ip) ? 0 : Math.round(Number(ip.size.width)), ph = nada(ip) ? 0 : Math.round(Number(ip.size.height));
        const s = sufijo(atr, pw, ph, 1);
        escribirDatos(pdf, base + s + '.pdf');
        const ok1 = pngVector(pdf, 0, 0, 1, base + s + '-vector.png'), ok2 = pngVector(pdf, 0, 0, 2, base + s + '-vector@2x.png');
        anota(tipo, !!(ok1 && ok2), 'NSImage no dibuja el PDF');
      } else if (clase === '_CUIThemeSVGRendition' || clase === '_CUIThemeVectorGlyphRendition') {
        const svg = r.rawData;
        if (nada(svg)) { anota(tipo, false, 'rawData vacío'); continue; }
        const w = Number(r.canvasSize.width), h = Number(r.canvasSize.height);
        const s = sufijo(atr, Math.round(w), Math.round(h), 1);
        escribirDatos(svg, base + s + '.svg');
        const ok1 = pngVector(svg, w, h, 1, base + s + '-vector.png'), ok2 = pngVector(svg, w, h, 2, base + s + '-vector@2x.png');
        anota(tipo, !!(ok1 && ok2), 'NSImage no lee SVG en esta versión (llegó en macOS 14): solo el .svg');
      } else if (clase === '_CUIThemeEffectRendition') {
        const e = r.effectPreset;
        if (nada(e)) { anota(tipo, false, 'effectPreset nil'); continue; }
        const texto = e.debugDescription.js;
        escribirJSON({ tipo: 'efecto', nombre: fac || r.name.js, atributos: atr, escala_efecto: Number(e.effectScale),
          cantidad: Number(e.effectCount), efectos: efectos(texto), texto: texto }, base + sufijo(atr, 0, 0, 1) + '.json');
        anota(tipo, true);
      } else if (clase === '_CUIThemeGradientRendition') {
        const g = r.gradient;
        if (nada(g)) { anota(tipo, false, 'gradient nil'); continue; }
        const pos = lista(g.colorLocations, num), col = lista(g.colorStops, colorDeCUI);
        const opos = lista(g.opacityLocations, num), op = lista(g.opacityStops, num);
        escribirJSON({ tipo: 'degradado', nombre: fac || r.name.js, atributos: atr,
          estilo: fourcc(r.gradientStyle), angulo: Number(r.gradientDrawingAngle),
          suavizado: Number(g.smoothingCoefficient), tramado: !!g.isDithered,
          paradas_color: col.map((c, j) => ({ posicion: pos[j], srgb: c })),
          paradas_opacidad: op.map((o, j) => ({ posicion: opos[j], opacidad: o })) }, base + sufijo(atr, 0, 0, 1) + '.json');
        anota(tipo, true);
      } else if (clase === '_CUIThemeNamedColorGradientRendition') {
        escribirJSON({ tipo: 'degradado_de_colores_con_nombre', nombre: fac || r.name.js, atributos: atr,
          colores: lista(r.colorNames, x => x.js), paradas: lista(r.colorStops, num), tipo_degradado: Number(r.gradientType),
          inicio: [Number(r.gradientStartPoint.x), Number(r.gradientStartPoint.y)],
          fin: [Number(r.gradientEndPoint.x), Number(r.gradientEndPoint.y)] }, base + sufijo(atr, 0, 0, 1) + '.json');
        anota(tipo, true);
      } else if (clase === '_CUIThemeMultisizeImageSetRendition') {
        const tams = lista(r.sizeIndexes, x => {
          const m = String(x.description.js).match(/size: \(([\d.]+), ([\d.]+)\) index: (\d+) idiom: (\d+) subtype: (\d+)/);
          return m ? { ancho: +m[1], alto: +m[2], indice: +m[3], idiom: +m[4], subtipo: +m[5] } : String(x.description.js);
        });
        escribirJSON({ tipo: 'multisize', nombre: fac || r.name.js, atributos: atr, tamanos: tams,
          nota: 'cada índice es el valor del atributo «dimensión1» de la rendición de ese tamaño, con el mismo nombre' },
          base + sufijo(atr, 0, 0, 1) + '.json');
        anota(tipo, true);
      } else if (clase === '_CUIThemeColorRendition') {
        const a = apar[atr.apariencia || 0] || (atr.apariencia ? String(atr.apariencia) : 'NSAppearanceNameSystem');
        (colores[a] || (colores[a] = [])).push({ nombre: fac || r.name.js, atributos: atr, srgb: srgb(r.cgColor),
          color_del_sistema: r.substituteWithSystemColor ? r.systemColorName.js : null });
        anota(tipo, true);
      } else if (clase === '_CUIRawDataRendition') {
        const d = r.data;
        if (nada(d)) { anota(tipo, false, 'data vacío'); continue; }
        // la extensión del nombre va también al final, después del sufijo
        const n = r.name.js, m = n.match(/\.([A-Za-z0-9]+)$/), ext = m ? m[1] : 'dat';
        const s = base + sufijo(atr, 0, 0, 1);
        escribirDatos(d, s + '.' + ext);
        if (ext === 'caar') {
          // .caar → .caml: CAPackage lo lee y CAMLWriter (QuartzCore, privado) lo escribe.
          let ok = false;
          try {
            const pk = $.NSClassFromString('CAPackage').packageWithDataTypeOptionsError(d, $('com.apple.coreanimation-archive'), $({}), null);
            const W = $.NSClassFromString('CAMLWriter');
            if (!nada(pk) && !nada(W)) {
              const md = $.NSMutableData.data;
              W.writerWithData(md).encodeObject(pk.rootLayer);
              if (md.length > 0) ok = escribirDatos(md, s + '.caml');
            }
          } catch (e) {}
          if (!ok) escribirTexto('El .caar va crudo: CAPackage o CAMLWriter no lo pasaron a .caml en esta Mac.\n', s + '.caar.nota.txt');
          anota(tipo + ' caar→caml', ok, 'CAPackage/CAMLWriter no lo convierte: va el crudo con nota');
        }
        anota(tipo, true);
      } else if (/Layer(Stack|Group)/.test(clase)) {
        // Cada capa apunta a otra rendición por su clave (que sale como imagen
        // aparte): aquí va a qué apunta, su marco y cómo se funde.
        const capas = lista(r.layerReferences, l => {
          const rk = l.referenceKey, ra = nada(rk) ? {} : atributos(rk), f = l.frame;
          return { capa: nada(l.layerName) ? null : l.layerName.js, referencia: facetas[ra.identificador] || null,
            atributos_referencia: ra, marco: [Number(f.origin.x), Number(f.origin.y), Number(f.size.width), Number(f.size.height)],
            marco_fijo: !!l.fixedFrame, opacidad: Number(l.opacity), modo_fusion: Number(l.blendMode), opacidad_sombra: Number(l.shadowOpacity) };
        });
        const tam = [Number(r.unslicedSize.width), Number(r.unslicedSize.height)];
        const ok = escribirJSON({ tipo: 'pila_de_capas', clase: clase, nombre: fac || r.name.js, atributos: atr, tamano: tam, capas: capas,
          nota: 'las capas van en el orden de layerReferences; si la primera es la de abajo es hipótesis' },
          base + sufijo(atr, tam[0], tam[1], r.scale) + '.json');
        anota(tipo, !!ok && capas.length > 0, capas.length ? 'no se pudo escribir' : 'sin layerReferences');
      } else {
        anota(tipo, false, 'clase sin conversor: ' + clase);
      }
    } catch (e) { anota(tipo, false, 'error: ' + String(e).slice(0, 120)); }
  }
  if (REPETIDOS) cuenta['(nombres repetidos, con -rN)'] = { sacado: REPETIDOS, faltan: {} };
  for (const a of Object.keys(colores)) escribirJSON({ apariencia: a, colores: colores[a] }, dest + '/colores-' + archivo(a) + '.json');
  return cuenta;
}

function tsv(cuenta) {
  const filas = ['tipo\tsacado\tno_sacado\tmotivo'];
  for (const t of Object.keys(cuenta).sort()) {
    const c = cuenta[t], m = Object.keys(c.faltan);
    if (!m.length) filas.push(`${t}\t${c.sacado}\t0\t`);
    m.forEach((mo, j) => filas.push(`${t}\t${j ? '' : c.sacado}\t${c.faltan[mo]}\t${mo}`));
  }
  return filas.join('\n') + '\n';
}

function run(argv) {
  if (argv.length < 2) return 'uso: car-mac.js <recursos> <salida> [subcarpeta…]';
  $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/CoreUI.framework').load;
  const rec = argv[0].replace(/\/$/, ''), sal = argv[1].replace(/\/$/, '');
  const subs = argv.length > 2 ? argv.slice(2) : ['car', 'iconos'];
  carpeta(sal);
  const total = {}, resumen = [];
  for (const sub of subs) {
    const en = FM.enumeratorAtPath($(rec + '/' + sub));
    if (nada(en)) { resumen.push(`${sub}: no existe`); continue; }
    let p;
    while (!nada(p = en.nextObject)) {
      const rel = sub + '/' + p.js;
      if (!/\.car$/.test(rel)) continue;
      const dest = sal + '/' + rel.replace(/\//g, '__');
      const c = sacar(rec + '/' + rel, dest);
      escribirTexto(tsv(c), dest + '/cuenta.tsv');
      for (const t of Object.keys(c)) {
        const T = total[t] || (total[t] = { sacado: 0, faltan: {} });
        T.sacado += c[t].sacado;
        for (const m of Object.keys(c[t].faltan)) T.faltan[m] = (T.faltan[m] || 0) + c[t].faltan[m];
      }
      resumen.push(rel);
    }
  }
  escribirTexto(tsv(total), sal + '/cuenta-total.tsv');
  return `${resumen.length} .car → ${sal}\n` + tsv(total);
}
