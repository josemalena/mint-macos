/*
 * Las notificaciones de Cinnamon armadas como las de Catalina
 * (notificaciones@macos). Vale para el aviso de arriba a la derecha y para
 * las tarjetas del panel, que son la misma pieza (MessageTray.Notification).
 *
 * Referencia de José: macos-catalina-push-notification.webp (a 2x). A 1x:
 * tarjeta de 344×63 con esquinas de 12; el ícono de la app de 30 px a 12 del
 * borde y centrado en vertical; el texto desde x 51 en tres renglones de
 * 17 px (título en semibold, la app en negrita, el cuerpo en una línea con
 * «…»); la imagen adjunta de 42 px a 10 del borde derecho; sin botones en
 * reposo: la X sale al pasar el puntero.
 *
 * Cinnamon pone la hora sobre el título, la imagen de 125 px a la izquierda
 * del cuerpo y no enseña el nombre de la app. Aquí se reacomoda después de
 * cada update()/setImage(); el estilo (colores, letra, relleno) va en el tema,
 * con las clases que se ponen aquí. quitar() deja Cinnamon como estaba.
 */

const MessageTray = imports.ui.messageTray;
const { St, Pango, Clutter } = imports.gi;

const ICONO = 30;
const IMAGEN = 42;

let _original = null;

function _cerrarDe(n) {
  // La X de Cinnamon no se guarda en el objeto: es el botón de la columna 3.
  if (n._botonCerrar !== undefined) return n._botonCerrar;
  n._botonCerrar = null;
  for (let c of n._table.get_children()) {
    if (c instanceof St.Button && c.child instanceof St.Icon && c.child.icon_name === "xsi-window-close") {
      n._botonCerrar = c;
      break;
    }
  }
  return n._botonCerrar;
}

function _acomodar(n) {
  try {
    n._table.add_style_class_name("notificacion-catalina");

    // Ícono a 30 px, a la izquierda y centrado en los tres renglones.
    if (n._icon) {
      if (n._icon instanceof St.Icon) n._icon.icon_size = ICONO;
      n._table.child_set(n._icon, { row: 0, col: 0, row_span: 2, y_align: St.Align.MIDDLE, y_fill: false });
    }

    // Título en semibold (Cinnamon lo envuelve en <b>, que es 700) y los
    // tres renglones juntos, a 17 px.
    n._titleLabel.clutter_text.set_markup(n.title || "");
    n._titleLabel.add_style_class_name("notificacion-titulo");
    n._bannerBox.set_style("spacing: 1px;");
    n._timeLabel.add_style_class_name("notificacion-hora");

    // Segundo renglón: de dónde viene (el nombre de la app), si no repite
    // el título.
    let origen = n.source && n.source.title ? n.source.title : "";
    if (!n._origenLabel) {
      n._origenLabel = new St.Label({ style_class: "notificacion-origen" });
      n._bannerBox.add_actor(n._origenLabel);
    }
    n._origenLabel.text = origen;
    n._origenLabel.visible = origen !== "" && origen !== n.title;

    // El cuerpo en una línea, con «…».
    if (n._bodyUrlHighlighter) {
      let t = n._bodyUrlHighlighter.actor.clutter_text;
      t.line_wrap = false;
      t.single_line_mode = true;
      t.ellipsize = Pango.EllipsizeMode.END;
      n._bodyUrlHighlighter.actor.add_style_class_name("notificacion-cuerpo");
    }

    // La imagen adjunta a la derecha, a la altura de la tarjeta.
    if (n._imageBin) {
      n._table.child_set(n._imageBin, { row: 0, col: 4, row_span: 2, x_expand: false, y_align: St.Align.MIDDLE });
      n._imageBin.opacity = 255;
      if (n._scrollArea) n._table.child_set(n._scrollArea, { col: 1, col_span: 3 });
    }

    // La X, solo con el puntero encima.
    let x = _cerrarDe(n);
    if (x && !n._xConectada) {
      n._xConectada = true;
      x.opacity = 0;
      n.actor.track_hover = true;
      n.actor.connect("notify::hover", () => { x.opacity = n.actor.hover ? 200 : 0; });
    }
  } catch (e) {
    global.logError("notificaciones@macos: " + e);
  }
}

function aplicar() {
  if (_original) return;
  let N = MessageTray.Notification.prototype;
  let S = MessageTray.Source.prototype;
  _original = {
    update: N.update,
    setImage: N.setImage,
    imagen: Object.getOwnPropertyDescriptor(N, "IMAGE_SIZE"),
    icono: Object.getOwnPropertyDescriptor(S, "ICON_SIZE"),
  };
  N.update = function () {
    let r = _original.update.apply(this, arguments);
    _acomodar(this);
    return r;
  };
  N.setImage = function () {
    let r = _original.setImage.apply(this, arguments);
    _acomodar(this);
    return r;
  };
  // Las imágenes y los íconos se cargan ya del tamaño de la Mac.
  Object.defineProperty(N, "IMAGE_SIZE", { get() { return IMAGEN; }, configurable: true });
  Object.defineProperty(S, "ICON_SIZE", { value: ICONO, writable: true, configurable: true });
}

function quitar() {
  if (!_original) return;
  let N = MessageTray.Notification.prototype;
  let S = MessageTray.Source.prototype;
  N.update = _original.update;
  N.setImage = _original.setImage;
  if (_original.imagen) Object.defineProperty(N, "IMAGE_SIZE", _original.imagen);
  if (_original.icono) Object.defineProperty(S, "ICON_SIZE", _original.icono);
  else delete S.ICON_SIZE;
  _original = null;
}
