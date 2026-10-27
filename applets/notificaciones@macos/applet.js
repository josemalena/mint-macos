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
const { Gio, GLib, St, Clutter } = imports.gi;
const Util = imports.misc.util;

const ANCHO_ICONO = 18;

// Lo medido en la Mac, del perfil de la versión de macOS activa (apps/animaciones.json); sin perfil o sin ese número, lo de siempre.
function delPerfil(animacion, campo) {
  try {
    let id = null;
    for (let dir of [GLib.get_user_runtime_dir(), GLib.get_user_config_dir()]) {
      try {   // file_get_contents lanza si el archivo no está
        let [ok, bytes] = GLib.file_get_contents(GLib.build_filenamev([dir, "mint-macos", "macos.json"]));
        if (ok) { id = JSON.parse(imports.byteArray.toString(bytes)).version; break; }
      } catch (e) {}
    }
    if (!id) return null;
    let [ok2, datos] = GLib.file_get_contents(GLib.build_filenamev([GLib.get_user_data_dir(), "mint-macos", "macos", id, "apps", "animaciones.json"]));
    let v = ok2 ? JSON.parse(imports.byteArray.toString(datos)).comportamiento[animacion][campo] : 0;
    return v > 0 ? v : null;
  } catch (e) {
    return null;
  }
}

// Ancho del contenido: el del perfil (360 pt en Monterey, 367 en Sequoia) es el del panel entero, con el borde de 1 px a cada lado.
const ANCHO_PANEL = (delPerfil("notification-center-entrar", "ancho_panel_pt") || 347) - 2;
// El panel entra deslizándose desde el borde derecho (Monterey: ~200 ms visibles, 230 de ajuste; sale en 150-167 ms), con easeInEaseOut y sin
// fundido. Sin esos números no se anima y queda lo de Cinnamon.
const MS_ENTRAR = delPerfil("notification-center-entrar", "ms");
const MS_SALIR = delPerfil("notification-center-salir", "ms");
const FONDO_PANEL = 0.96;   // sin vidrio (José, 18-10-2026: «no usemos vidrio»): la caja va casi opaca
const FUENTE = 'font-family: ".SF NS", sans-serif;';

function dibujarIcono(area, alto) {
  let cr = area.get_context();
  let y0 = Math.round((alto - 22) / 2) + 6; // y 6 en la barra de 22
  // Con No molestar encendido el ícono se ve apagado.
  let activas = true;
  try { activas = new Gio.Settings({ schema_id: "org.cinnamon.desktop.notifications" }).get_boolean("display-notifications"); } catch (e) {}
  // El color de texto de la barra (blanco en oscuro, casi negro en claro)
  let c = area.get_theme_node().get_foreground_color();
  cr.setSourceRGBA(c.red / 255, c.green / 255, c.blue / 255, activas ? 1 : 0.4);
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

    // El armado de Catalina para todas las notificaciones (catalina.js).
    // Ojo: Cinnamon guarda los módulos del applet; un cambio en catalina.js
    // pide reiniciar Cinnamon, ReloadXlet no lo vuelve a leer.
    this._catalina = imports.ui.appletManager.applets[metadata.uuid].catalina;
    this._catalina.aplicar();
    // Sin el vidrio de Catalina (vidrio.js, ya quitado): los menús van opacos. Si un Cinnamon que todavía lo tenía puesto recarga
    // este applet, su instancia vieja lo desaplica al irse.

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
    // Para la esquina activa «Notification Center» (System Preferences ▸ Mission Control).
    global.mintMacosNotificationCenter = () => this.on_applet_clicked();
    // Fluido desde el primer clic: el primer open cuesta ~48 ms (se miden los actores y se arma el menú) contra ~4 ms los demás, y
    // Today tardaba en llenarse. Se calienta una vez, ya cargada la sesión: abrir y cerrar en el mismo ciclo no llega a pintar un
    // cuadro, y los datos de Today se piden y se renuevan cada 10 min, así que al abrir ya están.
    this._calentar = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 8, () => {
      this._calentar = 0;
      try { this._ajustarAlto(); this.menu.open(false); this.menu.close(false); } catch (e) {}
      this._refrescarHoy();
      this._renovarHoy = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 600, () => { this._refrescarHoy(); return GLib.SOURCE_CONTINUE; });
      return GLib.SOURCE_REMOVE;
    });
  }

  on_applet_removed_from_panel() {
    delete global.mintMacosNotificationCenter;
    if (this._calentar) GLib.source_remove(this._calentar);
    if (this._renovarHoy) GLib.source_remove(this._renovarHoy);
    if (this._reintento) GLib.source_remove(this._reintento);
    if (this._catalina) this._catalina.quitar();
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

  on_applet_clicked(event) {
    // ⌥ + clic: No molestar, sin abrir el panel.
    try {
      let estado = Clutter.get_current_event().get_state();
      if (estado & Clutter.ModifierType.MOD1_MASK) { this._alternarNoMolestar(); return; }
    } catch (e) {}
    if (!this.menu.isOpen) this._ajustarAlto();
    this._actualizarHoras();
    this.menu.toggle();
  }

  // El panel se desliza desde el borde derecho de la pantalla, no se funde como los menús de Cinnamon. open/close del menú se envuelven: el original
  // coloca y muestra (o esconde) sin animar y aquí se mueve el actor. open(false) —el calentamiento— queda sin animar.
  _deslizar() {
    let menu = this.menu, original = { open: menu.open, close: menu.close };
    let desplazamiento = () => ANCHO_PANEL + 40;   // sobra: sale entero del borde, se recorta con la pantalla
    menu.open = function (animate) {
      this.actor.remove_all_transitions();
      original.open.call(this, false);
      if (!animate || !Main.wm.desktop_effects_menus) return;
      let x = this.actor.x;
      this.actor.x = x + desplazamiento();
      this.actor.ease({ x: x, duration: MS_ENTRAR, mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD });
    };
    menu.close = function (animate) {
      if (!this.isOpen) return;
      if (!animate || !Main.wm.desktop_effects_menus) { original.close.call(this, false); return; }
      let actor = this.actor, x = actor.x, hide = actor.hide;
      actor.remove_all_transitions();
      actor.hide = () => {};   // el close original esconde de golpe: se esconde al terminar de deslizar
      try { original.close.call(this, false); } finally { delete actor.hide; }
      actor.ease({ x: x + desplazamiento(), duration: MS_SALIR, mode: Clutter.AnimationMode.EASE_IN_OUT_QUAD,
                   onComplete: () => { if (!this.isOpen) { actor.hide(); actor.x = x; } } });
    };
  }

  _armarMenu() {
    if (this.menu) this.menu.destroy();
    this.menu = new Applet.AppletPopupMenu(this, this._orientation);
    this.menuManager.addMenu(this.menu);
    // Sin el marco opaco del tema (border-image de .popup-menu): el tinte
    // casi opaco va solo en la caja.
    this.menu.actor.set_style(FUENTE + " border-image: none; background: none; background-color: transparent; box-shadow: none; padding: 0;");
    // Los colores (fondo, borde, textos) salen del tema: clase nc-panel en _constanza-cinnamon.css (oscuro) y en el -claro
    this.menu.box.add_style_class_name("nc-panel");
    this.menu.box.set_style(`width: ${ANCHO_PANEL}px; padding: 8px 0; border-radius: 0;`);
    if (MS_ENTRAR !== null && MS_SALIR !== null) this._deslizar();

    // Today | Notifications arriba (captura 1.33.53 PM): el segmento activo en gris claro.
    this._pestanas = new St.BoxLayout({ style: "padding: 6px 24px 8px 24px;" });
    this._segmentos = {};
    for (let [clave, texto] of [["today", "Today"], ["notifications", "Notifications"]]) {
      let b = new St.Button({ label: texto, reactive: true, track_hover: true, x_expand: true, can_focus: true });
      b.connect("clicked", () => this._mostrarPestana(clave));
      this._segmentos[clave] = b;
      this._pestanas.add(b, { expand: true });
    }
    this.menu.addActor(this._pestanas);

    // «Clear All» arriba, alineado con las tarjetas, solo cuando hay algo que
    // borrar. A la izquierda: el menú de un applet pegado a la esquina queda
    // unos píxeles fuera de la pantalla y lo de la derecha se cortaba.
    this._cabecera = new St.BoxLayout({ style: "padding: 0 0 6px 10px;" });
    this._botonBorrar = new St.Button({ label: "Clear All", reactive: true, track_hover: true,
                                        style: FUENTE + " font-size: 9pt;", style_class: "nc-texto-tenue" });
    this._botonBorrar.connect("clicked", () => this._borrarTodo());
    this._cabecera.add_child(this._botonBorrar);
    this.menu.addActor(this._cabecera);

    this._vacio = new St.Label({ text: "No Notifications", x_align: Clutter.ActorAlign.CENTER,
                                 y_align: Clutter.ActorAlign.CENTER, x_expand: true, y_expand: true,
                                 style: FUENTE + " font-size: 15pt;", style_class: "nc-texto-muy-tenue" });

    this._lista = new St.BoxLayout({ vertical: true, style: "spacing: 8px; padding: 0 8px;" });
    this._scroll = new St.ScrollView({ x_fill: true, y_fill: true, y_align: St.Align.START, style_class: "vfade" });
    this._scroll.set_policy(St.PolicyType.NEVER, St.PolicyType.AUTOMATIC);
    this._scroll.add_actor(this._lista);
    this._contenido = new St.BoxLayout({ vertical: true, y_expand: true });
    this._notifs = new St.BoxLayout({ vertical: true, y_expand: true });
    this._notifs.add(this._scroll, { expand: true });
    this._notifs.add(this._vacio, { expand: true });
    this._contenido.add(this._notifs, { expand: true });
    this._hoy = this._armarHoy();
    this._contenido.add(this._hoy, { expand: true });
    this.menu.addActor(this._contenido);
    this._armarPie();
    this._mostrarPestana(this._pestana || "notifications");

    // Re-hospedar las que ya había (al cambiar de orientación).
    for (let n of this.notificaciones) {
      n.actor.unparent();
      n.actor.set_width(ANCHO_PANEL - 16);
      this._lista.add_child(n.actor);
    }
    this._actualizar();
  }

  // ── Today y el pie ───────────────────────────────────────────────────────────────────────────────────────────────────
  _mostrarPestana(clave) {
    this._pestana = clave;
    for (let k in this._segmentos) {
      let activo = k === clave;
      this._segmentos[k].set_style(FUENTE + " font-size: 9.5pt; padding: 2px 0; text-align: center;" +
        (k === "today" ? " border-radius: 4px 0 0 4px;" : " border-radius: 0 4px 4px 0;"));
      this._segmentos[k].add_style_class_name("nc-segmento");
      if (activo) this._segmentos[k].add_style_pseudo_class("active"); else this._segmentos[k].remove_style_pseudo_class("active");
    }
    this._hoy.visible = clave === "today";
    this._notifs.visible = clave === "notifications";
    this._botonBorrar.visible = clave === "notifications" && this.notificaciones.length > 0;
    this._cabecera.visible = clave === "notifications";
    if (clave === "today") this._pedirHoy();
    if (this._boton_edit) this._boton_edit.visible = clave === "today";
  }

  // La fecha y el clima. El clima lo da el servicio org.mintmacos.Hoy1 (mac-ventanas); sin servicio no se pinta nada.
  _armarHoy() {
    let caja = new St.BoxLayout({ vertical: true, y_expand: true, style: "padding: 18px 24px 8px 24px; spacing: 14px;" });
    this._fecha = new St.Label({ style: FUENTE + " font-size: 24pt; font-weight: 200;", style_class: "nc-fecha-grande" });
    this._fecha.clutter_text.line_wrap = true;
    caja.add_child(this._fecha);
    this._widgets = new St.BoxLayout({ vertical: true, style: "spacing: 10px;" });
    caja.add_child(this._widgets);
    return caja;
  }

  // Al abrir Today: se pinta enseguida lo último que se leyó y se pide lo nuevo aparte.
  _pedirHoy() {
    this._fecha.set_text(new Date().toLocaleFormat("%A,\n%B %-d"));
    if (this._clima || this._eventos) this._pintarWidgets(this._clima || null);
    this._refrescarHoy();
    // El clima tarda un momento la primera vez: se vuelve a pedir si estaba vacío.
    if (!this._climaListo && !this._reintento) {
      this._reintento = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2500, () => {
        this._reintento = 0;
        if (this.menu.isOpen && this._pestana === "today") this._pedirHoy();
        return GLib.SOURCE_REMOVE;
      });
    }
  }

  // Pide el clima y el calendario sin bloquear; cuando llegan, repinta (si Today está a la vista).
  _refrescarHoy() {
    Gio.DBus.session.call("org.mintmacos.Hoy1", "/org/mintmacos/Hoy1", "org.mintmacos.Hoy1", "Clima", null,
      new GLib.VariantType("(a{sv})"), Gio.DBusCallFlags.NONE, 4000, null, (con, res) => {
        let clima = null;
        try { clima = con.call_finish(res).recursiveUnpack()[0]; } catch (e) {}
        // Un clima vacío (el servicio aún no lo leyó, o sin red) no borra el último bueno.
        if (clima && clima.ciudad) this._clima = clima;
        this._pintarWidgets(this._clima || null);
      });
    this._pedirCalendario();
  }

  // Los eventos de hoy, del calendario de Thunderbird, por org.mintmacos.Calendario1 (de Infra). Sin servicio no se pinta.
  _pedirCalendario() {
    let hoy = new Date();
    let desde = new Date(hoy.getFullYear(), hoy.getMonth(), hoy.getDate()).getTime();
    Gio.DBus.session.call("org.mintmacos.Calendario1", "/org/mintmacos/Calendario1", "org.mintmacos.Calendario1", "Eventos",
      new GLib.Variant("(xx)", [desde, desde + 86400000]), new GLib.VariantType("(aa{sv})"), Gio.DBusCallFlags.NONE, 6000, null,
      (con, res) => {
        let eventos = null;
        try { eventos = con.call_finish(res).recursiveUnpack()[0]; } catch (e) {}
        this._eventos = eventos || [];
        this._pintarWidgets(this._clima || null);
      });
  }

  // El widget Calendar (captura 1.33.53 PM): horas a la izquierda y cada evento como un bloque con la barra de su color.
  _tarjetaCalendario(eventos, desde) {
    let tarjeta = new St.BoxLayout({ vertical: true, style_class: "nc-tarjeta", style: "border-radius: 8px; padding: 0;" });
    tarjeta.add_child(new St.Label({ text: "CALENDAR", style_class: "nc-tarjeta-titulo", style: FUENTE + " font-size: 8.5pt; font-weight: bold; padding: 6px 10px;" }));
    let dia = eventos.filter(e => e.todo_el_dia);
    let con_hora = eventos.filter(e => !e.todo_el_dia);
    for (let e of dia) {
      let fila = new St.BoxLayout({ style: "padding: 5px 10px 5px 10px; spacing: 8px;" });
      fila.add_child(new St.Widget({ style: "background-color: " + (e.color || "#ff2d55") + ";", width: 3, height: 16 }));
      fila.add_child(new St.Label({ text: e.titulo, y_align: Clutter.ActorAlign.CENTER, style: FUENTE + " font-size: 10pt;" }));
      tarjeta.add_child(fila);
    }
    if (con_hora.length) {
      let h0 = new Date(Math.min(...con_hora.map(e => e.inicio))).getHours();
      let h1 = new Date(Math.max(...con_hora.map(e => e.fin))).getHours() + 1;
      h0 = Math.max(0, Math.min(h0, 22));
      h1 = Math.max(h0 + 4, Math.min(h1, 24));
      const ALTO_HORA = 44, ANCHO = ANCHO_PANEL - 48 - 28, X0 = 44;
      let area = new St.Widget({ layout_manager: new Clutter.FixedLayout(), style: "padding: 4px 0;" });
      area.set_size(ANCHO + X0, (h1 - h0) * ALTO_HORA + 8);
      for (let h = h0; h < h1; h++) {
        let y = 4 + (h - h0) * ALTO_HORA;
        let etiqueta = (h % 12 === 0 ? 12 : h % 12) + (h < 12 ? " AM" : " PM");
        let l = new St.Label({ text: etiqueta, style: FUENTE + " font-size: 8.5pt;", style_class: "nc-texto-medio" });
        l.set_position(8, y - 2);
        area.add_actor(l);
        let linea = new St.Widget({ style_class: "nc-linea-hora" });
        linea.set_position(X0, y + 6);
        linea.set_size(ANCHO, 1);
        area.add_actor(linea);
      }
      for (let e of con_hora) {
        let i = new Date(e.inicio), f = new Date(e.fin);
        let y = 4 + ((i.getHours() + i.getMinutes() / 60) - h0) * ALTO_HORA + 6;
        let alto = Math.max(22, ((f - i) / 3600000) * ALTO_HORA);
        let color = e.color || "#ff2d55";
        let bloque = new St.BoxLayout({ vertical: true, style_class: "nc-bloque", style: "padding: 2px 6px 2px 10px;" });
        bloque.add_child(new St.Label({ text: e.titulo, style: FUENTE + " font-size: 9.5pt;" }));
        if (e.lugar) bloque.add_child(new St.Label({ text: e.lugar, style_class: "nc-texto-tenue", style: FUENTE + " font-size: 8.5pt;" }));
        bloque.set_position(X0 + 2, y);
        bloque.set_size(ANCHO - 4, alto);
        area.add_actor(bloque);
        // La barra del color del calendario, a la izquierda del bloque.
        let barra = new St.Widget({ style: "background-color: " + color + ";" });
        barra.set_position(X0 + 2, y);
        barra.set_size(3, alto);
        area.add_actor(barra);
      }
      tarjeta.add_child(area);
    }
    return tarjeta;
  }

  _pintarWidgets(clima) {
    this._clima = clima;
    for (let c of this._widgets.get_children()) this._widgets.remove_child(c);
    if (this._eventos && this._eventos.length) this._widgets.add_child(this._tarjetaCalendario(this._eventos));
    this._climaListo = !!(clima && clima.ciudad);
    if (!this._climaListo) return;
    let tarjeta = new St.BoxLayout({ vertical: true, style_class: "nc-tarjeta", style: "border-radius: 8px; padding: 0;" });
    let titulo = new St.Label({ text: "WEATHER", style_class: "nc-tarjeta-titulo", style: FUENTE + " font-size: 8.5pt; font-weight: bold; padding: 6px 10px;" });
    tarjeta.add_child(titulo);
    let cuerpo = new St.BoxLayout({ style: "padding: 14px 14px; spacing: 14px;" });
    cuerpo.add_child(new St.Icon({ icon_name: clima.icono, icon_size: 44, style: "" }));
    let datos = new St.BoxLayout({ vertical: true, style: "spacing: 2px;" });
    datos.add_child(new St.Label({ text: clima.ciudad, style: FUENTE + " font-size: 13pt; font-weight: bold;" }));
    datos.add_child(new St.Label({ text: clima.descripcion, style_class: "nc-texto-claro", style: FUENTE + " font-size: 10pt;" }));
    datos.add_child(new St.Label({ text: `H:${Math.round(clima.maxima)}°  L:${Math.round(clima.minima)}°`, style_class: "nc-texto-claro", style: FUENTE + " font-size: 10pt;" }));
    cuerpo.add(datos, { expand: true });
    cuerpo.add_child(new St.Label({ text: `${Math.round(clima.temperatura)}°`, y_align: Clutter.ActorAlign.CENTER,
                                    style: FUENTE + " font-size: 30pt; font-weight: 200;" }));
    tarjeta.add_child(cuerpo);
    this._widgets.add_child(tarjeta);
  }

  // Abajo: Edit (solo en Today) y el engranaje, que abre System Preferences ▸ Notifications (captura 1.33.53 PM).
  _armarPie() {
    this._pie = new St.BoxLayout({ style_class: "nc-pie", style: "padding: 8px 24px 6px 24px;" });
    this._boton_edit = new St.Button({ label: "Edit", reactive: true, track_hover: true, can_focus: true, x_expand: true,
      style_class: "nc-boton-pie", style: FUENTE + " font-size: 9.5pt; border-radius: 3px; padding: 1px 28px;" });
    // Sin captura del modo Edit: el botón queda a la vista y sin acción hasta tenerla.
    this._boton_edit.reactive = false;
    this._boton_edit.opacity = 140;
    this._pie.add(this._boton_edit, { expand: true, x_align: St.Align.MIDDLE });
    this._engranaje = new St.Button({ reactive: true, track_hover: true, can_focus: true, style: "padding: 0 0 0 10px;" });
    this._engranaje.set_child(new St.Icon({ icon_name: "emblem-system-symbolic", icon_size: 16, style: "color: rgba(128,128,132,0.9);" }));
    this._engranaje.connect("clicked", () => {
      this.menu.close();
      try { Util.spawnCommandLine("mac-preferencias notifications"); } catch (e) {}
    });
    this._pie.add_child(this._engranaje);
    this.menu.addActor(this._pie);
  }

  // No molestar: la pantalla de notificaciones de Cinnamon. ⌥ + clic en el ícono lo cambia, como en la Mac.
  _alternarNoMolestar() {
    let c = new Gio.Settings({ schema_id: "org.cinnamon.desktop.notifications" });
    c.set_boolean("display-notifications", !c.get_boolean("display-notifications"));
    Gio.Settings.sync();
    this._icono.queue_repaint();
  }

  // El panel ocupa todo el alto bajo la barra, como en la Mac.
  _ajustarAlto() {
    let m = Main.layoutManager.findMonitorForActor(this.actor) || Main.layoutManager.primaryMonitor;
    // Las pestañas, la cabecera «Clear All» y el pie también ocupan alto: si no se descuentan, el panel queda más alto que la
    // pantalla y Cinnamon lo sube por encima de la barra (las pestañas quedaban tapadas).
    let extra = 0;
    for (let a of [this._pestanas, this._cabecera, this._pie]) {
      if (a && a.visible) extra += a.get_preferred_height(-1)[1];
    }
    this._contenido.set_height(m.height - this._alto - 16 - 30 - extra);
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
    this._botonBorrar.visible = hay && this._pestana !== "today";
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
