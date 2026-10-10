/*
 * La lupa de Spotlight en la barra (buscar@macos).
 *
 * Medida en la captura de José (Screen Shot 12.32.05, 1x): 14×14 px, de y 5 a
 * 18, un aro fino de 10 px y el mango en diagonal hasta la esquina. Va
 * dibujada, no es un archivo de Apple.
 *
 * El clic abre el buscador que José ya usa con ⌘Espacio: Ulauncher
 * (ulauncher-toggle). Sin Ulauncher el clic no hace nada y lo dice en el log.
 */

const Applet = imports.ui.applet;
const Util = imports.misc.util;
const { GLib, St } = imports.gi;
const Cairo = imports.cairo;

const ANCHO = 14;

function dibujarLupa(area, alto) {
  let cr = area.get_context();
  let y0 = Math.round((alto - 22) / 2) + 5; // y 5 en la barra de 22
  cr.setSourceRGBA(1, 1, 1, 0.95);
  cr.setLineCap(Cairo.LineCap.ROUND);
  cr.setLineWidth(1.3);
  cr.arc(5.3, y0 + 5.3, 4.5, 0, 2 * Math.PI);
  cr.stroke();
  cr.setLineWidth(1.6);
  cr.moveTo(8.8, y0 + 8.8);
  cr.lineTo(13, y0 + 13);
  cr.stroke();
  cr.$dispose();
}

class Buscar extends Applet.Applet {
  constructor(metadata, orientation, panelHeight, instanceId) {
    super(orientation, panelHeight, instanceId);
    this._alto = panelHeight;
    this._lupa = new St.DrawingArea({ width: ANCHO, height: panelHeight });
    this._lupa.connect("repaint", a => dibujarLupa(a, this._alto));
    this.actor.add_actor(this._lupa);
    // En la Mac hay 25 px de tinta a tinta entre el usuario y la lupa; el
    // tema deja 5 px por lado en cada applet de la derecha.
    this.actor.set_style("padding-left: 17px;");
  }

  on_panel_height_changed() {
    this._alto = this._panelHeight;
    this._lupa.set_height(this._alto);
    this._lupa.queue_repaint();
  }

  on_applet_clicked() {
    if (GLib.find_program_in_path("ulauncher-toggle")) Util.spawn(["ulauncher-toggle"]);
    else global.logWarning("buscar@macos: falta ulauncher-toggle (instala Ulauncher)");
  }
}

function main(metadata, orientation, panelHeight, instanceId) {
  return new Buscar(metadata, orientation, panelHeight, instanceId);
}
