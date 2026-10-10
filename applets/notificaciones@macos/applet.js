/*
 * Notification Center (notificaciones@macos).
 *
 * En la Mac el ícono está siempre en la esquina derecha de la barra, haya o no
 * notificaciones, y sin contador: tres renglones con un punto y una raya
 * (medido en la captura de José, Screen Shot 12.32.05 a 1x: 18×10 px, de y 6
 * a 15, puntos de 2 px, rayas de 2 px desde x 4, la del medio 3 px más
 * corta). Va dibujado, no es un archivo de Apple.
 *
 * El clic abre el panel de la derecha, como la Notification Center de
 * Catalina: lo más nuevo arriba y «No Notifications» cuando no hay. Las
 * notificaciones las guarda la bandeja de Cinnamon; esto sale del applet
 * notifications@cinnamon.org (GPL), al que reemplaza en la barra. «Today»
 * (los widgets) no existe aquí, y por eso no se pinta la pestaña.
 */

const Applet = imports.ui.applet;
const Main = imports.ui.main;
const PopupMenu = imports.ui.popupMenu;
const MessageTray = imports.ui.messageTray;
const { Gio, St, Clutter } = imports.gi;

const ANCHO_ICONO = 18;
const ANCHO_PANEL = 345;
const FUENTE = 'font-family: ".SF NS", sans-serif;';

function dibujarIcono(area, alto) {
  let cr = area.get_context();
  let y0 = Math.round((alto - 22) / 2) + 6; // y 6 en la barra de 22
  cr.setSourceRGBA(1, 1, 1, 1);
  for (let [i, largo] of [[0, 14], [1, 11], [2, 14]]) {
    let y = y0 + i * 4;
    cr.rectangle(0, y, 2, 2);
    cr.rectangle(4, y, largo, 2);
  }
  cr.fill();
  cr.$dispose();
}

// «just now», «5 min ago» o la hora, como la Mac en cada notificación.
function cuando(fecha) {
  let s = Math.floor((Date.now() - fecha.getTime()) / 1000);
  if (s < 60) return "now";
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return fecha.toLocaleFormat("%b %-d");
}

class NotificationCenter extends Applet.Applet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this._alto = panelHeight;
    this._icono = new St.DrawingArea({ width: ANCHO_ICONO, height: panelHeight });
    this._icono.connect("repaint", a => dibujarIcono(a, this._alto));
    this.actor.add_actor(this._icono);
    // 18 px de tinta desde la lupa, lo que deja la Mac entre íconos de la
    // derecha (sin Siri, que aquí no existe).
    this.actor.set_style("padding-left: 12px;");

    this._orientation = orientation;
    this.menuManager = new PopupMenu.PopupMenuManager(this);
    this.notificaciones = []; // de la más vieja a la más nueva
    this._senal = Main.messageTray.connect("notify-applet-update", (_t, n) => this._agregar(n));
  }

  // El contador de Cinnamon se sube ANTES de armar el menú: si el armado
  // falla y se baja al quitar el applet, queda en 0 y Cinnamon deja de
  // pasarle las notificaciones a nadie (pasó el 10-10-2026).
  on_applet_added_to_panel() {
    if (!this._contado) { MessageTray.extensionsHandlingNotifications++; this._contado = true; }
    this._armarMenu();
  }

  on_applet_removed_from_panel() {
    if (this._senal) Main.messageTray.disconnect(this._senal);
    if (this._contado) {
      MessageTray.extensionsHandlingNotifications = Math.max(0, MessageTray.extensionsHandlingNotifications - 1);
      this._contado = false;
    }
    if (MessageTray.extensionsHandlingNotifications === 0) this._borrarTodo();
  }

  on_panel_height_changed() {
    this._alto = this._panelHeight;
    this._icono.set_height(this._alto);
    this._icono.queue_repaint();
  }

  on_orientation_changed(orientation) {
    this._orientation = orientation;
    this._armarMenu();
  }

  on_applet_clicked() {
    if (!this.menu.isOpen) this._ajustarAlto();
    this._actualizarHoras();
    this.menu.toggle();
  }

  _armarMenu() {
    if (this.menu) this.menu.destroy();
    this.menu = new Applet.AppletPopupMenu(this, this._orientation);
    this.menuManager.addMenu(this.menu);
    this.menu.actor.set_style(FUENTE);
    this.menu.box.set_style(`width: ${ANCHO_PANEL}px; padding: 8px 0; background-color: rgba(30, 30, 32, 0.96);` +
                            " border: 1px solid #45474a; border-radius: 0;");

    // «Clear All» arriba, alineado con las tarjetas, solo cuando hay algo que
    // borrar. A la izquierda: el menú de un applet pegado a la esquina queda
    // unos píxeles fuera de la pantalla y lo de la derecha se cortaba.
    this._cabecera = new St.BoxLayout({ style: "padding: 0 0 6px 10px;" });
    this._botonBorrar = new St.Button({ label: "Clear All", reactive: true, track_hover: true,
                                        style: FUENTE + " font-size: 9pt; color: rgba(255,255,255,0.6);" });
    this._botonBorrar.connect("clicked", () => this._borrarTodo());
    this._cabecera.add_child(this._botonBorrar);
    this.menu.addActor(this._cabecera);

    this._vacio = new St.Label({ text: "No Notifications", x_align: Clutter.ActorAlign.CENTER,
                                 y_align: Clutter.ActorAlign.CENTER, x_expand: true, y_expand: true,
                                 style: FUENTE + " font-size: 15pt; color: rgba(255,255,255,0.35);" });

    this._lista = new St.BoxLayout({ vertical: true, style: "spacing: 8px; padding: 0 8px;" });
    this._scroll = new St.ScrollView({ x_fill: true, y_fill: true, y_align: St.Align.START, style_class: "vfade" });
    this._scroll.set_policy(St.PolicyType.NEVER, St.PolicyType.AUTOMATIC);
    this._scroll.add_actor(this._lista);
    this._contenido = new St.BoxLayout({ vertical: true, y_expand: true });
    this._contenido.add(this._scroll, { expand: true });
    this._contenido.add(this._vacio, { expand: true });
    this.menu.addActor(this._contenido);

    // Re-hospedar las que ya había (al cambiar de orientación).
    for (let n of this.notificaciones) {
      n.actor.unparent();
      n.actor.set_width(ANCHO_PANEL - 16);
      this._lista.add_child(n.actor);
    }
    this._actualizar();
  }

  // El panel ocupa todo el alto bajo la barra, como en la Mac.
  _ajustarAlto() {
    let m = Main.layoutManager.findMonitorForActor(this.actor) || Main.layoutManager.primaryMonitor;
    this._contenido.set_height(m.height - this._alto - 16 - 30);
  }

  _agregar(notificacion) {
    if (notificacion.isTransient) { notificacion.destroy(); return; }
    notificacion.actor.unparent();
    let i = this.notificaciones.indexOf(notificacion);
    if (i !== -1) {
      if (notificacion._destroyed) this.notificaciones.splice(i, 1);
      else { notificacion._inNotificationBin = true; this._lista.add_child(notificacion.actor); }
      this._actualizar();
      return;
    }
    if (notificacion._destroyed) return;
    notificacion._inNotificationBin = true;
    this.notificaciones.push(notificacion);
    this._lista.add_child(notificacion.actor);
    notificacion.actor.add_style_class_name("notification-applet-padding");
    // La tarjeta de Cinnamon pide más ancho que el panel y se salía por la
    // derecha (con el «Clear All»): se ajusta al panel menos sus márgenes.
    notificacion.actor.set_width(ANCHO_PANEL - 16);
    notificacion.connect("scrolling-changed", (_n, s) => { this.menu.passEvents = s; });
    notificacion.connect("destroy", () => {
      let j = this.notificaciones.indexOf(notificacion);
      if (j !== -1) this.notificaciones.splice(j, 1);
      this._actualizar();
    });
    notificacion._timeLabel.show();
    this._actualizar();
  }

  _actualizar() {
    if (!this._lista) return;
    // Lo más nuevo arriba, como la Mac.
    for (let c of this._lista.get_children()) this._lista.remove_child(c);
    for (let n of this.notificaciones.slice().reverse()) this._lista.add_child(n.actor);
    let hay = this.notificaciones.length > 0;
    this._scroll.visible = hay;
    this._vacio.visible = !hay;
    this._botonBorrar.visible = hay;
  }

  _actualizarHoras() {
    for (let n of this.notificaciones)
      try { n._timeLabel.clutter_text.set_text(cuando(n._timestamp)); } catch (e) {}
  }

  _borrarTodo() {
    for (let n of this.notificaciones.slice().reverse()) {
      try { this._lista.remove_actor(n.actor); } catch (e) {}
      n.destroy(MessageTray.NotificationDestroyedReason.DISMISSED);
    }
    this.notificaciones = [];
    this._actualizar();
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new NotificationCenter(metadata, orientation, panelHeight, instanceId);
}
