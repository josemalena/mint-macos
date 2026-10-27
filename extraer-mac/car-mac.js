// car-mac.js — saca el contenido de los .car con el CoreUI de la propia Mac.
// JXA, como herramientas.js: sin swiftc ni Command Line Tools.
//
//   osascript -l JavaScript car-mac.js <recursos> <salida> [subcarpeta…]
//   osascript -l JavaScript car-mac.js simbolos <salida> <versión> <tabla.tsv> <.car o carpeta>…
//     (los glifos vectoriales como íconos -symbolic de freedesktop: ver simbolos())
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

// identificador → nombre de faceta, como FACETKEYS en car.py. Con
// renditionNameForKeyList: el proceso se cae en algunas claves (SVG de
// CoreTypes, 27.0.1): sale de la clave base de cada nombre.
function facetasDe(cat, st) {
  const facetas = {};
  try {
    const ns = st.allRenditionNames;
    for (let i = 0; !nada(ns) && i < ns.count; i++) {
      const n = ns.objectAtIndex(i), bk = cat._baseKeyForName(n);
      if (!nada(bk) && Number(bk.themeIdentifier)) facetas[Number(bk.themeIdentifier)] = n.js;
    }
  } catch (e) {}
  return facetas;
}

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
  const facetas = facetasDe(cat, st);
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

// ---- símbolos: los glifos vectoriales como íconos -symbolic de freedesktop
//
//   osascript -l JavaScript car-mac.js simbolos <salida> <versión> <tabla.tsv> <.car o carpeta>…
//
// De cada nombre sale UN glifo: el vectorial (VectorGlyph o SVG, sin imagen,
// degradado ni blanco) más cercano a regular mediano (peso 4, tamaño 2), sin apariencia.
// Va a <salida>/iconos-simbolicos/Mint-Macos-<versión>/scalable/<contexto>/
// <nombre>-symbolic.svg, con index.theme, simbolos.tsv (de dónde salió cada
// uno) y descartados.tsv (los que no, con su motivo). <nombre> es el de freedesktop si el glifo está en la tabla; si no,
// el del .car, en «sf». Si dos .car traen el mismo nombre gana el primero:
// CoreGlyphs va primero.
// GTK pinta los -symbolic con el color del texto: por eso van sin fill. Que
// así sirvan en claro, en oscuro y con el acento es hipótesis hasta probarlo.
const CONTEXTOS = { Actions: 'actions', Places: 'places', Status: 'status', Devices: 'devices',
  Categories: 'categories', Applications: 'apps', Emblems: 'emblems', MimeTypes: 'mimetypes' };

function leerTabla(ruta) {
  const t = $.NSString.stringWithContentsOfFileEncodingError($(ruta), $.NSUTF8StringEncoding, null);
  if (nada(t)) throw new Error('no se pudo leer la tabla ' + ruta);
  const tabla = {};
  for (const l of t.js.split('\n')) {
    if (!l.trim() || l[0] === '#') continue;
    const [sf, fd, ctx] = l.split('\t');
    if (!CONTEXTOS[ctx]) throw new Error(`contexto desconocido en la tabla: «${l}»`);
    tabla[sf] = { fd, ctx };
  }
  return tabla;
}

// name_aliases.strings de CoreGlyphs, junto al .car: nombre viejo → nuevo
function alias(car) {
  const d = $.NSDictionary.dictionaryWithContentsOfFile($(car.replace(/[^/]*$/, '') + 'name_aliases.strings'));
  return nada(d) ? {} : ObjC.deepUnwrap(d);
}

// Los colores que no son negro ni «none», por propiedad: {fill: [...], otros: [...]}.
function colores(t) {
  const re = /(fill|stroke|stop-color|color)\s*(?:=\s*["']([^"']*)["']|:\s*([^;"'}]+))/gi, c = { fill: {}, otros: {} };
  let m;
  while ((m = re.exec(t))) {
    const v = (m[2] || m[3] || '').trim().toLowerCase().replace(/\s+/g, '');
    if (!/^(none|currentcolor|black|#000|#000000|#000000ff|rgb\(0,0,0\)|inherit|)$/.test(v)) c[m[1].toLowerCase() === 'fill' ? 'fill' : 'otros'][v] = 1;
  }
  return { fill: Object.keys(c.fill), otros: Object.keys(c.otros) };
}

// El texto SVG de una rendición. Los glifos de las apps traen el SVG en
// rawData; los de CoreGlyphs (27.0.1) lo traen compilado («GVS» en el CSI) y
// el texto sale de su svgDocument con CGSVGDocumentWriteToData (CoreSVG, privado).
let escribirSVG;
function textoSVG(r) {
  const d = r.rawData;
  if (!nada(d) && Number(d.length) > 0) {
    const t = $.NSString.alloc.initWithDataEncoding(d, $.NSUTF8StringEncoding);
    if (!nada(t) && /^\s*</.test(t.js)) return t.js;
  }
  if (escribirSVG === undefined) {
    escribirSVG = null;
    try {
      $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/CoreSVG.framework').load;
      ObjC.bindFunction('CGSVGDocumentWriteToData', ['void', ['void *', 'id', 'void *']]);
      escribirSVG = $.CGSVGDocumentWriteToData;
    } catch (e) {}
  }
  if (!escribirSVG || !r.respondsToSelector('svgDocument')) return null;
  const doc = msg(r, 'svgDocument');
  if (!doc) return null;
  const md = $.NSMutableData.data;
  escribirSVG(doc, md, null);
  const t = $.NSString.alloc.initWithDataEncoding(md, $.NSUTF8StringEncoding);
  return nada(t) || !Number(md.length) ? null : t.js;
}

// Los recortes del glifo como huecos de verdad. En el monocromo de SF una capa
// puede abrir hueco en lo dibujado antes:
//   27 (CoreSVG 362): la capa monochrome-N con -sfsymbols-clear-behind en su CSS;
//     si además tiene opacity:0 solo recorta. Un path puede estar en varias capas
//     (class="monochrome-1 monochrome-2": la misma forma en las dos).
//   12 (CoreSVG 175.5): el path blanco del multicolor; recorta y no se dibuja.
// Sin eso quedan manchas: el «?» de questionmark.square.fill invisible sobre el
// cuadrado lleno. Las capas se componen en orden y cada recorte envuelve lo de
// antes en una máscara alfa: un path evenodd con la forma de la capa y un
// rectángulo grande. La forma va primero: en 27 los d empiezan con «m»
// relativa, que después del «Z» del rectángulo saldría desde su esquina. Alfa porque GTK 3 mete
// «path { fill: <color> !important }» y eso pinta también la máscara; el
// fill="#fff" es para quien ignore mask-type y use luminancia.
// Probado en librsvg 2.58 con ese CSS (26-10-2026): salen los huecos en claro y con acento.
// null si no hay recortes; {cuerpo, criterio} o {motivo}.
const GRANDE = 'M-100000 -100000H100000V100000H-100000Z';
function esBlanco(v) { return /^(white|#fff|#ffffff|#ffffffff|rgb\(255,255,255\))$/i.test((v || '').replace(/\s+/g, '')); }
function atributo(p, a) { return (p.match(new RegExp(`\\s${a}\\s*=\\s*["']([^"']*)["']`)) || [])[1]; }
function conRecortes(cuerpo, reglas) {
  const paths = [...cuerpo.matchAll(/<path\b[^>]*?\/>/g)];
  if (!paths.length) return null;
  const capas = [];   // {ps: [path…], recorta, visible}, en orden de dibujo
  let criterio;
  if (Object.values(reglas).some(r => /clear-behind\s*:\s*true/.test(r))) {
    // capa → paths. Un path sin clase (el primero de calendar.badge.plus) va como
    // capa visible en su lugar del documento: antes de la capa del path que lo
    // sigue (hipótesis, cotejada con el dibujo de macOS).
    const por = {}, sinClase = [];
    paths.forEach(([p], i) => {
      const cs = (atributo(p, 'class') || '').match(/\bmonochrome-\d+\b/g);
      if (!cs) { sinClase.push(i); return; }
      for (const c of cs) (por[+c.split('-')[1]] || (por[+c.split('-')[1]] = [])).push(p);
    });
    if (!Object.keys(por).length)
      return { motivo: 'recorte de SF con las capas en LayerTree (shapeGroupLayer), no en los path' };
    const orden = [];
    for (const k of Object.keys(por)) {
      const r = reglas['monochrome-' + k] || '';
      orden.push({ clave: +k, ps: por[k], recorta: /clear-behind\s*:\s*true/.test(r), visible: !/(^|;)\s*opacity\s*:\s*0(\.0*)?\s*(;|$)/.test(r) });
    }
    for (const i of sinClase) {
      const sig = paths.slice(i + 1).map(([p]) => (atributo(p, 'class') || '').match(/\bmonochrome-(\d+)\b/)).find(x => x);
      orden.push({ clave: (sig ? +sig[1] : 1e9) - 0.5 + i * 1e-6, ps: [paths[i][0]], recorta: false, visible: true });
    }
    capas.push(...orden.sort((a, b) => a.clave - b.clave));
    criterio = 'clear-behind';
  } else if (paths.some(([p]) => esBlanco(atributo(p, 'fill')))) {
    for (const [p] of paths) { const b = esBlanco(atributo(p, 'fill')); capas.push({ ps: [p], recorta: b, visible: !b }); }
    criterio = 'blanco';
  } else return null;
  // solo una lista de <path/> dentro de <g>, como lo escribe CoreSVG
  const ult = paths[paths.length - 1], ini = paths[0].index, fin = ult.index + ult[0].length;
  let entre = cuerpo.slice(ini, fin);
  for (const [p] of paths) entre = entre.replace(p, '');
  const antes = cuerpo.slice(0, ini);
  // fuera los metadatos de SF que no dibujan: grupos vacíos (<g id="da" data-d…/>,
  // LayerTree) y el ancla de rotación (<circle id="ra" r="0"/>)
  let despues = cuerpo.slice(fin), antes0;
  do {
    antes0 = despues;
    despues = despues.replace(/<g\b[^>]*\/>|<g\b[^>]*>\s*<\/g>|<circle\b[^>]*\sr\s*=\s*["']0["'][^>]*\/>/g, '');
  } while (despues !== antes0);
  if (entre.trim() || !/^(\s*<g\b[^>]*>)*\s*$/.test(antes) || !/^(\s*<\/g>)*\s*$/.test(despues))
    return { motivo: `recorte (${criterio}) en un SVG que no es una lista de path dentro de <g>` };
  // el path dibujado, sin fill, clase, opacidad ni datos de animación de SF
  const limpio = p => p.replace(/\s+(fill|class|opacity|data-[\w-]+)\s*=\s*["'][^"']*["']/g, '');
  // La forma de una capa de varios path es su par-impar: document.on.document
  // trae en monochrome-2 la hoja llena y otra más chica, y en macOS esa capa es el
  // contorno (cotejado con NSImage imageWithSystemSymbolName, 27.0.1). Van en un
  // solo path evenodd; la «m» inicial de cada d pasa a «M» (empiezan en 0,0) para
  // poder juntarlos. Con un solo path, el path tal cual.
  const forma = ps => ps.map(p => atributo(p, 'd').trim().replace(/^m/, 'M')).join(' ');
  let acc = '', defs = '', n = 0;
  for (const c of capas) {
    if (c.recorta) {
      n++;
      defs += `<mask id="recorte${n}" mask-type="alpha" style="mask-type:alpha" maskUnits="userSpaceOnUse" x="-100000" y="-100000" width="200000" height="200000">` +
        `<path fill="#fff" fill-rule="evenodd" d="${forma(c.ps)} ${GRANDE}"/></mask>`;
      acc = `<g mask="url(#recorte${n})">${acc}</g>`;
    }
    if (c.visible) acc += c.ps.length === 1 ? limpio(c.ps[0]) : `<path fill-rule="evenodd" d="${forma(c.ps)}"/>`;
  }
  return { cuerpo: `<defs>${defs}</defs>` + antes.trim() + acc + despues.trim(), criterio };
}

// El SVG de CoreUI → -symbolic: con xmlns (CoreSVG no lo pone y librsvg lo
// pide), viewBox llevado al canvasSize, centrado en una caja cuadrada, sin fill
// y con los recortes como máscara (conRecortes).
function simbolico(t, cw, ch) {
  // las reglas de capa del CSS de SF, antes de quitarlo
  const reglas = {};
  for (const m of t.matchAll(/\.(monochrome-\d+)\s*\{([^}]*)\}/g)) reglas[m[1]] = m[2];
  // fuera la cabecera y el CSS de SF Symbols (-sfsymbols-…: capas y animación, que GTK no usa)
  t = t.replace(/<\?xml[\s\S]*?\?>/g, '').replace(/<!--[\s\S]*?-->/g, '').replace(/<!DOCTYPE[^>]*>/gi, '')
    .replace(/<style\b[\s\S]*?<\/style>/g, '').replace(/<defs>\s*<\/defs>/g, '');
  const m = t.match(/<svg\b([^>]*)>([\s\S]*)<\/svg>\s*$/);
  if (!m) return { motivo: 'no es un <svg>' };
  let cuerpo = m[2];
  if (/<(image|linearGradient|radialGradient|pattern|mask|filter)\b/.test(cuerpo)) return { motivo: 'trae imagen, degradado, patrón, máscara o filtro' };
  // El color de relleno de un glifo es el tinte de su modo multicolor (Monterey lo
  // escribe como fill="#5856D6" en folder; 27 solo como clase): se quita y queda la
  // forma de un solo color. El blanco es recorte (conRecortes); si no se puede
  // enmascarar, se descarta: pintado con el color del texto taparía el glifo.
  const c = colores(cuerpo);
  if (c.otros.length) return { motivo: 'trazo o degradado con color', detalle: c.otros.join(' ') };
  const rec = conRecortes(cuerpo, reglas);
  if (rec && rec.motivo) return { motivo: rec.motivo, detalle: c.fill.join(' ') };
  if (!rec && c.fill.some(esBlanco)) return { motivo: 'tiene partes en blanco', detalle: c.fill.join(' ') };
  const vb = (m[1].match(/viewBox\s*=\s*["']([^"']*)["']/) || [])[1];
  let [vx, vy, vw, vh] = vb ? vb.trim().split(/[\s,]+/).map(Number) : [0, 0, cw, ch];
  if (!(vw > 0 && vh > 0)) return { motivo: 'sin viewBox ni canvasSize' };
  if (!(cw > 0 && ch > 0)) { cw = vw; ch = vh; }
  // sin fill (salvo «none», que dice que esa forma es solo trazo) y sin las clases
  // de capa de SF (hierarchical-0:secondary…), que sin su CSS no dicen nada.
  // Con recortes, conRecortes ya dejó los path limpios (y la máscara lleva su fill).
  if (rec) cuerpo = rec.cuerpo;
  else cuerpo = cuerpo.replace(/\s+fill\s*=\s*["'](?!none)[^"']*["']/gi, '').replace(/fill\s*:\s*(?!none)[^;"']+;?/gi, '')
    .replace(/\s+class\s*=\s*["'][^"']*\b(monochrome|hierarchical|multicolor|palette)-\d[^"']*["']/g, '');
  const f = x => String(+(+x).toFixed(4));
  const sx = cw / vw, sy = ch / vh, tx = -vx * sx, ty = -vy * sy;
  // el viewBox y el canvasSize difieren en redondeo (11.3813 y 11.381342): eso no lleva matriz
  const e = 1e-3 * Math.max(cw, ch);
  if (Math.abs(sx * vw - vw) > e || Math.abs(sy * vh - vh) > e || Math.abs(tx) > e || Math.abs(ty) > e)
    cuerpo = `<g transform="matrix(${f(sx)} 0 0 ${f(sy)} ${f(tx)} ${f(ty)})">${cuerpo}</g>`;
  const L = Math.max(cw, ch);
  return { svg: '<?xml version="1.0" encoding="UTF-8"?>\n' +
    `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" version="1.1" width="16" height="16" viewBox="${f(-(L - cw) / 2)} ${f(-(L - ch) / 2)} ${f(L)} ${f(L)}">` +
    cuerpo.trim() + '</svg>\n', quitados: c.fill.join(' '), recorte: rec ? rec.criterio : '' };
}

function simbolos(argv) {
  if (argv.length < 4) return 'uso: car-mac.js simbolos <salida> <versión> <tabla.tsv> <.car o carpeta>…';
  const sal = argv[0].replace(/\/$/, ''), version = argv[1], tabla = leerTabla(argv[2]);
  const tema = `${sal}/iconos-simbolicos/Mint-Macos-${version}`;
  const cars = [];
  for (const a of argv.slice(3)) {
    const dir = Ref();
    if (!FM.fileExistsAtPathIsDirectory($(a), dir)) continue;
    if (!dir[0]) { cars.push(a); continue; }
    const en = FM.enumeratorAtPath($(a)); let p;
    while (!nada(p = en.nextObject)) if (/\.car$/.test(p.js)) cars.push(a.replace(/\/$/, '') + '/' + p.js);
  }
  const cuenta = {}, filas = ['icono\tcontexto\tnombre_sf\talias\tclase\tatributos\tcolores_quitados\trecorte\tcar'], hechos = {}, dirs = {};
  const fuera = ['nombre_sf\tclase\tmotivo\tdetalle\tcar'];
  const anota = (tipo, ok, motivo) => {
    const c = cuenta[tipo] || (cuenta[tipo] = { sacado: 0, faltan: {} });
    if (ok) c.sacado++; else c.faltan[motivo] = (c.faltan[motivo] || 0) + 1;
  };
  for (const car of cars) {
    const cat = $.NSClassFromString('CUICatalog').alloc.initWithURLError($.NSURL.fileURLWithPath(car), null);
    if (nada(cat)) { anota('catálogo', false, 'CUICatalog no lo abre'); continue; }
    const ts = cat._themeStore, st = ts.store, facetas = facetasDe(cat, st), keys = st.allAssetKeys;
    // nombre del .car → entrada de la tabla, directo o por su alias nuevo
    const al = alias(car), deTabla = {};
    for (const sf of Object.keys(tabla)) {
      deTabla[sf] = { ...tabla[sf], alias: '' };
      if (al[sf]) deTabla[al[sf]] = { ...tabla[sf], alias: sf };
    }
    // las claves de cada nombre, de la más cercana a regular mediano a la más
    // lejana. Dirección 4 es la de derecha a izquierda (speaker.slash.fill con
    // la bocina a la derecha, dibujado en 27.0.1): va después de la 5 y la 0.
    const porNombre = {};
    for (let i = 0; i < keys.count; i++) {
      const k = keys.objectAtIndex(i), atr = atributos(k), n = facetas[atr.identificador];
      if (!n) continue;
      const w = atr['27'] || 0, s = atr['28'] || 0;
      const nota = (atr.apariencia ? 1000 : 0) + (atr['dirección'] === 4 ? 100 : 0) + (w ? Math.abs(w - 4) * 10 : 0) + (s ? { 2: 0, 1: 1, 3: 2 }[s] || 3 : 0)
        + ((atr.escala || 1) > 1 ? 0.5 : 0) - (atr.despliegue || 0) * 0.01;
      (porNombre[n] || (porNombre[n] = [])).push({ k, atr, nota });
    }
    for (const n of Object.keys(porNombre)) {
      let r = null, clase = '', atr = null, motivo = 'sin glifo vectorial';
      for (const c of porNombre[n].sort((a, b) => a.nota - b.nota)) {
        try { r = ObjC.castRefToObject(msg(ts, 'renditionWithKey:', msg(c.k, 'keyList'))); } catch (e) { r = null; }
        if (nada(r)) continue;
        clase = $.NSStringFromClass(r.class).js;
        if (clase === '_CUIThemeVectorGlyphRendition' || clase === '_CUIThemeSVGRendition') { atr = c.atr; break; }
        r = null;
      }
      if (!atr) continue;   // no es un glifo: lo saca el paso «car»
      const tipo = clase.replace(/^_?CUI(Theme)?/, '').replace(/Rendition$/, '');
      const texto = textoSVG(r);
      if (!texto) { anota(tipo, false, 'ni rawData con texto SVG ni svgDocument que CoreSVG escriba'); continue; }
      const s = simbolico(texto, Number(r.canvasSize.width), Number(r.canvasSize.height));
      if (!s.svg) { anota(tipo, false, s.motivo); fuera.push([n, tipo, s.motivo, s.detalle || '', car].join('\t')); continue; }
      const e = deTabla[n], icono = e ? e.fd : archivo(n), ctx = e ? CONTEXTOS[e.ctx] : 'sf';
      if (hechos[icono]) { anota(tipo, false, 'el nombre ya salió de un .car anterior'); continue; }
      const dir = `${tema}/scalable/${ctx}`;
      if (!dirs[ctx]) { carpeta(dir); dirs[ctx] = e ? e.ctx : 'SF Symbols'; }
      if (!escribirTexto(s.svg, `${dir}/${icono}-symbolic.svg`)) { anota(tipo, false, 'no se pudo escribir'); continue; }
      hechos[icono] = 1;
      anota(tipo + (e ? ' (tabla)' : ' (nombre original)'), true);
      if (s.recorte) anota(`${tipo}: recortes como máscara (${s.recorte})`, true);
      const a = Object.keys(atr).filter(x => x !== 'identificador').map(x => `${x}=${atr[x]}`).join(' ');
      filas.push([icono, ctx, n, e ? e.alias : '', tipo, a, s.quitados, s.recorte, car].join('\t'));
    }
  }
  const ds = Object.keys(dirs).sort();
  if (!ds.length) return 'ningún glifo vectorial en ' + cars.length + ' .car\n' + tsv(cuenta);
  escribirTexto(['[Icon Theme]', `Name=Mint-Macos-${version}`,
    `Comment=Glifos de macOS ${version}, sacados de sus .car en esa Mac. Son de Apple: no se distribuyen.`,
    'Inherits=Mint-Y,Adwaita,hicolor', 'Directories=' + ds.map(c => 'scalable/' + c).join(','), '']
    .concat(...ds.map(c => [`[scalable/${c}]`, `Context=${dirs[c]}`, 'Size=16', 'MinSize=8', 'MaxSize=512', 'Type=Scalable', '']))
    .join('\n'), tema + '/index.theme');
  escribirTexto(filas.join('\n') + '\n', tema + '/simbolos.tsv');
  escribirTexto(fuera.join('\n') + '\n', tema + '/descartados.tsv');
  escribirTexto(tsv(cuenta), tema + '/cuenta.tsv');
  return `${cars.length} .car → ${tema}\n` + tsv(cuenta);
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
  $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/CoreUI.framework').load;
  if (argv[0] === 'simbolos') return simbolos(argv.slice(1));
  if (argv.length < 2) return 'uso: car-mac.js <recursos> <salida> [subcarpeta…]\n       car-mac.js simbolos <salida> <versión> <tabla.tsv> <.car o carpeta>…';
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
