/*
 * El vidrio de Catalina («vibrancy») para los menús de Cinnamon
 * (notificaciones@macos). José, 10-10-2026: el Notification Center de Catalina
 * deja ver el escritorio desenfocado detrás, y los menús de la barra también.
 *
 * Mientras un menú está abierto, debajo de su caja va un clon en vivo del
 * fondo y de cada ventana del escritorio, recortado a la caja y con varias
 * pasadas de Clutter.BlurEffect (Cinnamon no trae desenfoque de lo de detrás;
 * Clutter.BlurEffect desenfoca el actor al que se le pone, y aquí ese actor
 * es el clon). La caja tiene que ser translúcida en el tema para que se vea.
 *
 * Va dentro del contenedor del menú (_boxWrapper), debajo de la caja, con su
 * misma asignación: se mueve con el menú. Lo que se ve a través se calcula al
 * abrir y otra vez al terminar la animación.
 *
 * Cada pasada es un FBO del tamaño del menú: 14 en el panel de 345×1150 dejan
 * a Cinnamon en 0.5–3.7 % de CPU (medido el 10-10-2026, Ivy Bridge); los
 * menús chicos llevan 32.
 */

const PopupMenu = imports.ui.popupMenu;
const { Clutter, GLib } = imports.gi;

// Cada pasada es un FBO del tamaño del menú: los chicos aguantan más (y
// las necesitan: con 14 el texto de detrás todavía se leía en el menú Apple).
var PASADAS_GRANDE = 14;
var PASADAS_CHICO = 32;
var AREA_CHICO = 400 * 700;
let _original = null;

// El escritorio entero (fondo y ventanas) en coordenadas de pantalla.
function _lienzo() {
  let lienzo = new Clutter.Actor({ width: global.stage.width, height: global.stage.height });
  // El fondo, y las ventanas una por una: los grupos de ventanas miden 0×0 y
  // un clon de ellos no pinta nada (así lo hace también Expo).
  if (global.background_actor) lienzo.add_child(new Clutter.Clone({ source: global.background_actor }));
  let ws = global.workspace_manager.get_active_workspace();
  for (let wa of global.get_window_actors()) {
    let mw = wa.meta_window;
    if (!wa.visible || !mw || mw.minimized) continue;
    if (!mw.is_on_all_workspaces() && mw.get_workspace() !== ws) continue;
    lienzo.add_child(new Clutter.Clone({ source: wa, x: wa.x, y: wa.y }));
  }
  return lienzo;
}

function _ubicar(menu) {
  let v = menu._vidrio;
  if (!v) return;
  let [x, y] = menu._boxWrapper.get_transformed_position();
  v._lienzo.set_position(-Math.round(x), -Math.round(y));
}

function poner(menu) {
  quitar(menu);
  if (!menu._boxWrapper || !menu.box) return;
  // vidrio (del tamaño de la caja, recortado) > desenfoque (mismo tamaño,
  // recortado: así cada pasada es un FBO del tamaño del menú y no de la
  // pantalla) > lienzo (el escritorio, corrido a la posición del menú).
  let v = new Clutter.Actor({ clip_to_allocation: true, reactive: false });
  let desenfoque = new Clutter.Actor({ clip_to_allocation: true });
  desenfoque.add_constraint(new Clutter.BindConstraint({ source: v, coordinate: Clutter.BindCoordinate.SIZE }));
  let [w, h] = menu.box.get_size();
  let pasadas = w * h > AREA_CHICO ? PASADAS_GRANDE : PASADAS_CHICO;
  for (let i = 0; i < pasadas; i++) desenfoque.add_effect(new Clutter.BlurEffect());
  v._lienzo = _lienzo();
  desenfoque.add_child(v._lienzo);
  v.add_child(desenfoque);
  menu._boxWrapper.insert_child_below(v, menu.box);
  // El contenedor del menú solo asigna la caja: el vidrio toma lo mismo.
  menu._vidrioSenal = menu._boxWrapper.connect_after("allocate", (_a, caja, flags) => {
    if (menu._vidrio) menu._vidrio.allocate(caja, flags);
  });
  menu._vidrio = v;
  menu._boxWrapper.queue_relayout();
  _ubicar(menu);
  // Otra vez al terminar la animación de abrir.
  menu._vidrioTiempo = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 260, () => {
    menu._vidrioTiempo = 0;
    _ubicar(menu);
    return GLib.SOURCE_REMOVE;
  });
}

function quitar(menu) {
  if (menu._vidrioTiempo) { GLib.source_remove(menu._vidrioTiempo); menu._vidrioTiempo = 0; }
  if (menu._vidrioSenal) { try { menu._boxWrapper.disconnect(menu._vidrioSenal); } catch (e) {} menu._vidrioSenal = 0; }
  if (menu._vidrio) { menu._vidrio.destroy(); menu._vidrio = null; }
}

/* Todos los menús emergentes de Cinnamon (los de la barra, los del escritorio). */
function aplicar() {
  if (_original) return;
  let P = PopupMenu.PopupMenu.prototype;
  _original = { open: P.open, close: P.close };
  P.open = function () {
    let r = _original.open.apply(this, arguments);
    try { poner(this); } catch (e) { global.logError("vidrio: " + e); }
    return r;
  };
  P.close = function () {
    try { quitar(this); } catch (e) {}
    return _original.close.apply(this, arguments);
  };
}

function desaplicar() {
  if (!_original) return;
  let P = PopupMenu.PopupMenu.prototype;
  P.open = _original.open;
  P.close = _original.close;
  _original = null;
}
