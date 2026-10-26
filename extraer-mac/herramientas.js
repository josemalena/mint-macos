// herramientas.js — ayudantes de extraer.sh en JXA (osascript -l JavaScript),
// para no depender de swiftc ni de las Command Line Tools en la Mac.
//
//   osascript -l JavaScript herramientas.js pantalla
//       ancho alto escala barra dock   (puntos; dock = alto que reserva abajo)
//   osascript -l JavaScript herramientas.js ventanas [dueño]
//       id \t capa \t dueño \t título \t x y w h      (una ventana por línea)
//   osascript -l JavaScript herramientas.js raton mover|clic|derecho X Y
//   osascript -l JavaScript herramientas.js raton arrastrar X1 Y1 X2 Y2 [captura.png]
//       con captura.png toma la pantalla con el botón todavía apretado
//       (el rectángulo de selección) y después lo suelta
//   osascript -l JavaScript herramientas.js medidas
//   osascript -l JavaScript herramientas.js permisos [pedir]
//       {"accesibilidad":bool,"grabacion":bool} para la app que corre esto
//       (Terminal); con «pedir» dispara los diálogos del sistema de los dos
//       permisos de una vez, para concederlos al principio y no uno por uno.
//       JSON con lo que AppKit dice de la interfaz, en puntos (como
//       medidas.json de la entrega de macOS 27)
//   osascript -l JavaScript herramientas.js acento [claro.png oscuro.png]
//       JSON con AppleAccentColor/AppleHighlightColor tal como los lee este
//       proceso y los cuatro colores de acento en claro y oscuro; con las dos
//       rutas, además una ventanita con controles de acento (botón por
//       defecto, checkbox, radio, popup, segmentos, slider, texto seleccionado
//       con anillo de foco) capturada en cada apariencia
//   osascript -l JavaScript herramientas.js avisar-colores
//       publica las notificaciones con que las apps abiertas releen el acento
//       (si de verdad las releen en caliente está sin verificar)
//
// Las coordenadas van en puntos, con el origen arriba a la izquierda (las de
// screencapture -R y System Events).
ObjC.import('Cocoa');
ObjC.import('CoreGraphics');
ObjC.import('ApplicationServices');
// Estas tres no vienen en el puente: se declaran a mano (10.15+ las dos de CG).
try { ObjC.bindFunction('CGPreflightScreenCaptureAccess', ['bool', []]); } catch (e) {}
try { ObjC.bindFunction('CGRequestScreenCaptureAccess', ['bool', []]); } catch (e) {}
try { ObjC.bindFunction('AXIsProcessTrustedWithOptions', ['bool', ['id']]); } catch (e) {}

function run(argv) {
  const cmd = argv[0];
  if (cmd === 'pantalla') return pantalla();
  if (cmd === 'ventanas') return ventanas(argv[1] || '');
  if (cmd === 'raton') return raton(argv.slice(1));
  if (cmd === 'medidas') return medidas(argv[1] || '');
  if (cmd === 'permisos') return permisos(argv[1] === 'pedir', argv[2] || '');
  if (cmd === 'acento') return acento(argv[1] || '', argv[2] || '');
  if (cmd === 'avisar-colores') return avisarColores();
  return 'uso: pantalla | ventanas [dueño] | raton … | medidas | permisos [pedir] | acento [claro.png oscuro.png] | avisar-colores';
}

function pantalla() {
  const s = $.NSScreen.mainScreen;
  const f = s.frame, v = s.visibleFrame;
  const barra = (f.origin.y + f.size.height) - (v.origin.y + v.size.height);
  const dock = v.origin.y - f.origin.y;
  return [f.size.width, f.size.height, s.backingScaleFactor, barra, dock].join(' ');
}

function ventanas(filtro) {
  const ref = $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements, $.kCGNullWindowID);
  const lista = ObjC.deepUnwrap(ObjC.castRefToObject(ref)) || [];
  const out = [];
  lista.forEach(w => {
    const dueno = w.kCGWindowOwnerName || '';
    if (filtro && dueno.toLowerCase().indexOf(filtro.toLowerCase()) < 0) return;
    const b = w.kCGWindowBounds || {};
    out.push([w.kCGWindowNumber, w.kCGWindowLayer, dueno, w.kCGWindowName || '',
      [b.X, b.Y, b.Width, b.Height].map(n => Math.round(n || 0)).join(' ')].join('\t'));
  });
  return out.join('\n');
}

function evento(tipo, x, y, boton) {
  const e = $.CGEventCreateMouseEvent($(), tipo, $.CGPointMake(x, y), boton || $.kCGMouseButtonLeft);
  $.CGEventPost($.kCGHIDEventTap, e);
}
function pausa(seg) { delay(seg); }

function raton(a) {
  const n = a.slice(1).map(Number);
  switch (a[0]) {
    case 'mover': evento($.kCGEventMouseMoved, n[0], n[1]); break;
    case 'clic':
      evento($.kCGEventMouseMoved, n[0], n[1]); pausa(0.08);
      evento($.kCGEventLeftMouseDown, n[0], n[1]); pausa(0.06);
      evento($.kCGEventLeftMouseUp, n[0], n[1]); break;
    case 'derecho':
      evento($.kCGEventMouseMoved, n[0], n[1]); pausa(0.08);
      evento($.kCGEventRightMouseDown, n[0], n[1], $.kCGMouseButtonRight); pausa(0.06);
      evento($.kCGEventRightMouseUp, n[0], n[1], $.kCGMouseButtonRight); break;
    case 'arrastrar': {
      const [x1, y1, x2, y2] = n;
      evento($.kCGEventMouseMoved, x1, y1); pausa(0.1);
      evento($.kCGEventLeftMouseDown, x1, y1); pausa(0.15);
      const pasos = 25;
      for (let i = 1; i <= pasos; i++) {
        const f = i / pasos;
        evento($.kCGEventLeftMouseDragged, x1 + (x2 - x1) * f, y1 + (y2 - y1) * f);
        pausa(0.03);
      }
      pausa(0.6);
      if (a[5]) {
        const app = Application.currentApplication(); app.includeStandardAdditions = true;
        app.doShellScript('/usr/sbin/screencapture -x ' + "'" + a[5].replace(/'/g, "'\\''") + "'");
      }
      evento($.kCGEventLeftMouseUp, x2, y2);
      break;
    }
    default: return 'uso: raton mover|clic|derecho X Y | arrastrar X1 Y1 X2 Y2 [captura.png]';
  }
  return '';
}

// ---- permisos ---------------------------------------------------------------
// La versión llega de extraer.sh (sw_vers): en Catalina el puente de JXA no lee
// los structs (operatingSystemVersion, NSRect) y se cae o los da vacíos.
function versionDe(texto) {
  const p = String(texto || '').split('.').map(Number);
  return { mayor: p[0] || 0, menor: p[1] || 0 };
}
function esCatalinaOAnterior(texto) { const v = versionDe(texto); return v.mayor === 10; }

function permisos(pedir, version) {
  let acc = false, grab = false;
  try {
    if (pedir) {
      const op = $.NSMutableDictionary.alloc.init;
      op.setObjectForKey($.NSNumber.numberWithBool(true), $('AXTrustedCheckOptionPrompt'));
      acc = !!$.AXIsProcessTrustedWithOptions(op);
    } else acc = !!$.AXIsProcessTrusted();
  } catch (e) { acc = 'error: ' + e; }
  try {
    const v = versionDe(version);
    if (v.mayor > 10 || (v.mayor === 10 && v.menor >= 15)) {
      grab = !!$.CGPreflightScreenCaptureAccess();
      if (!grab && pedir) grab = !!$.CGRequestScreenCaptureAccess();
    } else grab = 'no medible en esta versión (anterior a 10.15: no hace falta)';
  } catch (e) { grab = 'error: ' + e; }
  return JSON.stringify({ accesibilidad: acc, grabacion: grab });
}

// ---- medidas ---------------------------------------------------------------
function r3(x) { return Math.round(x * 1000) / 1000; }
function srgb(c) {
  try {
    const s = c.colorUsingColorSpace($.NSColorSpace.sRGBColorSpace);
    if (!s || s.isNil()) return { error: 'no convertible a sRGB' };
    const comp = [s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent];
    const hex = '#' + comp.slice(0, 3).map(v => ('0' + Math.round(v * 255).toString(16).toUpperCase()).slice(-2)).join('');
    return { hex: hex, alfa: r3(comp[3]), rgba: comp.map(r3) };
  } catch (e) { return { error: String(e) }; }
}
function fuente(f) {
  try {
    const traits = ObjC.deepUnwrap(f.fontDescriptor.objectForKey($.NSFontTraitsAttribute)) || {};
    return { familia: f.familyName.js, nombre_postscript: f.fontName.js, tamano_pt: f.pointSize,
      peso_nsfont: r3(traits.NSCTFontWeightTrait || 0) };
  } catch (e) { return { error: String(e) }; }
}
const COLORES = ['controlAccentColor', 'selectedContentBackgroundColor', 'unemphasizedSelectedContentBackgroundColor',
  'windowBackgroundColor', 'controlBackgroundColor', 'underPageBackgroundColor', 'textBackgroundColor', 'controlColor',
  'labelColor', 'secondaryLabelColor', 'tertiaryLabelColor', 'quaternaryLabelColor', 'textColor', 'placeholderTextColor',
  'separatorColor', 'gridColor', 'selectedMenuItemTextColor', 'selectedTextBackgroundColor', 'keyboardFocusIndicatorColor',
  'linkColor', 'findHighlightColor', 'headerTextColor', 'shadowColor',
  'systemRedColor', 'systemOrangeColor', 'systemYellowColor', 'systemGreenColor', 'systemMintColor', 'systemTealColor',
  'systemCyanColor', 'systemBlueColor', 'systemIndigoColor', 'systemPurpleColor', 'systemPinkColor', 'systemBrownColor',
  'systemGrayColor'];
function coloresEn(nombre) {
  const out = {};
  $.NSAppearance.setCurrentAppearance($.NSAppearance.appearanceNamed(nombre));
  COLORES.forEach(k => {
    try { const c = $.NSColor[k]; out[k] = (c && !c.isNil()) ? srgb(c) : 'no existe en esta versión'; }
    catch (e) { out[k] = 'no existe en esta versión'; }
  });
  try {
    const alt = $.NSColor.alternatingContentBackgroundColors;
    out.alternatingContentBackgroundColors = [0, 1].map(i => srgb(alt.objectAtIndex(i)));
  } catch (e) {}
  return out;
}
function pref(dominio, clave) {
  const d = dominio === '-g'
    ? $.NSUserDefaults.standardUserDefaults.persistentDomainForName($.NSGlobalDomain)
    : $.NSUserDefaults.alloc.initWithSuiteName(dominio).dictionaryRepresentation;
  const v = d && !d.isNil() ? ObjC.deepUnwrap(d.objectForKey(clave)) : undefined;
  return v === undefined || v === null ? 'por defecto' : v;
}
function medidas(version) {
  $.NSApplication.sharedApplication;
  const viejo = esCatalinaOAnterior(version);
  const res = {
    generado: new Date().toISOString(),
    sistema: $.NSProcessInfo.processInfo.operatingSystemVersionString.js,
    unidad: 'puntos (pt); 1 pt = backingScaleFactor px',
  };
  if (viejo) {
    res.pantalla = 'no medida aquí: en esta versión JXA no lee NSRect; ver pantalla.txt';
  } else {
    const s = $.NSScreen.mainScreen, f = s.frame, v = s.visibleFrame;
    res.pantalla = {
      frame_pt: [f.size.width, f.size.height],
      visibleFrame_pt: [v.origin.x, v.origin.y, v.size.width, v.size.height],
      backingScaleFactor: s.backingScaleFactor,
      alto_barra_menu_pt: (f.origin.y + f.size.height) - (v.origin.y + v.size.height),
      alto_reservado_dock_pt: v.origin.y - f.origin.y,
      nota_dock: 'si el Dock se oculta solo, alto_reservado_dock_pt es 0',
    };
  }
  res.NSStatusBar_thickness_pt = $.NSStatusBar.systemStatusBar.thickness;
  const F = $.NSFont;
  res.fuentes = {
    systemFont: fuente(F.systemFontOfSize(0)), systemFont_bold: fuente(F.boldSystemFontOfSize(0)),
    menuFont: fuente(F.menuFontOfSize(0)), menuBarFont: fuente(F.menuBarFontOfSize(0)),
    titleBarFont: fuente(F.titleBarFontOfSize(0)), toolTipsFont: fuente(F.toolTipsFontOfSize(0)),
    labelFont: fuente(F.labelFontOfSize(0)), messageFont: fuente(F.messageFontOfSize(0)),
    paletteFont: fuente(F.paletteFontOfSize(0)), controlContentFont: fuente(F.controlContentFontOfSize(0)),
    monospacedSystemFont: fuente(F.monospacedSystemFontOfSizeWeight(0, 0)),
    tamanos_estandar_pt: { system: F.systemFontSize, small: F.smallSystemFontSize, label: F.labelFontSize },
    estilos_de_texto: {},
  };
  ['LargeTitle', 'Title1', 'Title2', 'Title3', 'Headline', 'Body', 'Callout', 'Subheadline', 'Footnote', 'Caption1', 'Caption2']
    .forEach(n => {
      try { res.fuentes.estilos_de_texto[n.charAt(0).toLowerCase() + n.slice(1)] = fuente(F.preferredFontForTextStyleOptions($['NSFontTextStyle' + n], $({}))); }
      catch (e) { res.fuentes.estilos_de_texto[n] = String(e); }
    });
  res.colores = { claro: coloresEn($.NSAppearanceNameAqua), oscuro: coloresEn($.NSAppearanceNameDarkAqua) };

  // Ventana de prueba (no se muestra): barra de título y semáforos.
  const ventana = {};
  if (viejo) ventana.nota = 'no medida en esta versión (JXA no lee NSRect): ver capturas';
  else try {
    const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, 600, 400), 15, 2, true);
    ventana.alto_barra_titulo_pt = w.frame.size.height - w.contentLayoutRect.size.height;
    ventana.semaforos = {};
    [['cerrar', 0], ['minimizar', 1], ['zoom', 2]].forEach(([n, t]) => {
      const b = w.standardWindowButton(t);
      if (b && !b.isNil()) ventana.semaforos[n] = { x_pt: b.frame.origin.x, y_desde_abajo_pt: b.frame.origin.y, ancho_pt: b.frame.size.width, alto_pt: b.frame.size.height };
    });
    // 4096 = unifiedTitleAndToolbar; toolbarStyle 3 = unified
    const wt = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, 600, 400), 15 | 4096, 2, true);
    wt.toolbar = $.NSToolbar.alloc.initWithIdentifier('medida');
    try { wt.toolbarStyle = 3; } catch (e) {}
    ventana.alto_titulo_mas_toolbar_unificada_pt = wt.frame.size.height - wt.contentLayoutRect.size.height;
  } catch (e) { ventana.error = String(e); }
  ventana.radio_esquina_pt = 'no medido aquí: ver capturas';
  ventana.sombra = 'no medido aquí: ver capturas';
  res.ventana = ventana;

  res.preferencias = {
    AppleInterfaceStyle: pref('-g', 'AppleInterfaceStyle'), AppleAccentColor: pref('-g', 'AppleAccentColor'),
    AppleHighlightColor: pref('-g', 'AppleHighlightColor'), AppleReduceTransparency: pref('com.apple.universalaccess', 'reduceTransparency'),
    dock_tilesize: pref('com.apple.dock', 'tilesize'), dock_largesize: pref('com.apple.dock', 'largesize'),
    dock_magnification: pref('com.apple.dock', 'magnification'), dock_orientation: pref('com.apple.dock', 'orientation'),
    dock_autohide: pref('com.apple.dock', 'autohide'),
  };
  return JSON.stringify(res, null, 2);
}

// ---- acento (bloque 18) ----------------------------------------------------
// Un proceso nuevo lee las preferencias al arrancar: lo que da aquí es lo que
// verá una app abierta DESPUÉS del cambio, no prueba que las abiertas cambien.
const ACENTO_COLORES = ['controlAccentColor', 'selectedContentBackgroundColor', 'selectedTextBackgroundColor',
  'keyboardFocusIndicatorColor'];
function acento(pngClaro, pngOscuro) {
  const app = $.NSApplication.sharedApplication;
  const out = { AppleAccentColor: pref('-g', 'AppleAccentColor'), AppleHighlightColor: pref('-g', 'AppleHighlightColor'),
    AppleAquaColorVariant: pref('-g', 'AppleAquaColorVariant'), colores: {} };
  [['claro', $.NSAppearanceNameAqua, pngClaro], ['oscuro', $.NSAppearanceNameDarkAqua, pngOscuro]].forEach(([n, ap, png]) => {
    $.NSAppearance.setCurrentAppearance($.NSAppearance.appearanceNamed(ap));
    const c = {};
    ACENTO_COLORES.forEach(k => {
      try { const x = $.NSColor[k]; c[k] = (x && !x.isNil()) ? srgb(x) : 'no existe en esta versión'; }
      catch (e) { c[k] = 'no existe en esta versión'; }
    });
    out.colores[n] = c;
    if (png) {
      try { out['captura_' + n] = ventanaAcento(app, ap, png); } catch (e) { out['captura_' + n] = 'error: ' + e; }
    }
  });
  return JSON.stringify(out, null, 2);
}
function girar(seg) { $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(seg)); }
function ventanaAcento(app, ap, png) {
  app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);
  app.finishLaunching;
  // 1 | 2 = titled | closable
  const w = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(240, 240, 380, 190), 1 | 2, 2, false);
  w.releasedWhenClosed = false;
  w.title = $('Acento');
  w.appearance = $.NSAppearance.appearanceNamed(ap);
  const v = w.contentView;
  const pon = (ctl, x, y, ancho, alto) => { ctl.setFrame($.NSMakeRect(x, y, ancho, alto)); v.addSubview(ctl); return ctl; };
  const ok = pon($.NSButton.buttonWithTitleTargetAction($('OK'), null, null), 270, 16, 92, 32);
  ok.keyEquivalent = $('\r');
  pon($.NSButton.buttonWithTitleTargetAction($('Cancel'), null, null), 170, 16, 92, 32);
  const chk = pon($.NSButton.checkboxWithTitleTargetAction($('Checkbox'), null, null), 20, 150, 120, 20); chk.state = 1;
  const rad = pon($.NSButton.radioButtonWithTitleTargetAction($('Radio'), null, null), 150, 150, 100, 20); rad.state = 1;
  const pop = pon($.NSPopUpButton.alloc.initWithFramePullsDown($.NSMakeRect(0, 0, 10, 10), false), 250, 146, 112, 26);
  pop.addItemsWithTitles($(['Popup', 'Dos']));
  const seg = pon($.NSSegmentedControl.segmentedControlWithLabelsTrackingModeTargetAction($(['Uno', 'Dos', 'Tres']), 0, null, null), 20, 112, 180, 24);
  seg.selectedSegment = 0;
  pon($.NSSlider.sliderWithValueMinValueMaxValueTargetAction(0.6, 0, 1, null, null), 210, 114, 152, 22);
  const tf = pon($.NSTextField.textFieldWithString($('Texto seleccionado')), 20, 70, 342, 24);
  w.makeKeyAndOrderFront(null);
  app.activateIgnoringOtherApps(true);
  girar(0.8);
  w.makeFirstResponder(tf); tf.selectText(null);
  w.display; girar(0.8);
  const t = $.NSTask.launchedTaskWithLaunchPathArguments('/usr/sbin/screencapture',
    $(['-x', '-o', '-l', String(w.windowNumber), png]));
  t.waitUntilExit;
  const st = t.terminationStatus;
  w.close; girar(0.2);
  return st === 0 ? png : 'screencapture salió con ' + st;
}
function avisarColores() {
  const c = $.NSDistributedNotificationCenter.defaultCenter;
  ['AppleColorPreferencesChangedNotification', 'AppleAquaColorVariantChanged'].forEach(n =>
    c.postNotificationNameObjectUserInfoDeliverImmediately($(n), null, null, true));
  return 'avisado';
}
