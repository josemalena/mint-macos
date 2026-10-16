/*
 * El estilo de las alertas de Catalina, medido en las capturas de la Mac mini a 1x (las mismas medidas que
 * applets/applemenu@macos/applemenu.py):
 *   ventana de 416 × 196: franja superior de 21 px (degradado #3B3B3C → #313233, línea negra debajo), cuerpo #2A2B2C,
 *   borde de 1 px #545556, esquinas de 5; ícono: círculo #8B8D8E de 64 px a 20 px del borde y 21 px bajo la franja;
 *   texto desde x 91, #DEDFDF: título en negrita (13 px) y la cuenta regresiva en chico (11 px); casilla de 14 × 14 #4B4E51;
 *   botones de 70 × 19 a 20 px del borde derecho y del de abajo, 14 px entre ellos: Cancel #5F6061 y la acción en azul.
 * La fuente es SF (obligatoria): «.SF NS». Los íconos se dibujan: ningún archivo de Apple.
 */
namespace MacOS {
    public const int SOMBRA = 24;

    const string CSS_ALERTA = """
.mac-dialogo { background: transparent; }
.mac-caja {
  background-color: #2a2b2c;
  border: 1px solid #545556;
  border-radius: 5px;
  box-shadow: 0 10px 24px rgba(0, 0, 0, 0.55);
}
.mac-franja {
  background-image: linear-gradient(to bottom, #3b3b3c, #313233);
  border-bottom: 1px solid #000000;
  border-radius: 5px 5px 0 0;
}
.mac-titulo { font-family: ".SF NS"; font-weight: bold; font-size: 13px; color: #dedfdf; }
.mac-cuenta { font-family: ".SF NS"; font-size: 11px; color: #dedfdf; }
.mac-casilla, .mac-casilla label { font-family: ".SF NS"; font-size: 13px; color: #dedfdf; }
.mac-casilla check {
  min-width: 14px; min-height: 14px; margin: 0 6px 0 0;
  border-radius: 3px; border: 1px solid #5a5d60;
  background-image: none; background-color: #4b4e51;
}
.mac-casilla check:checked { background-color: #165ee1; border-color: #165ee1; color: #ffffff; }
button.mac-boton {
  font-family: ".SF NS"; font-size: 13px; color: #e7e7e7;
  min-height: 19px; min-width: 50px; padding: 0 10px; margin: 0; outline: none;
  border-radius: 5px; border: none; box-shadow: none; text-shadow: none;
  background-image: none; background-color: #5f6061;
}
button.mac-boton label { padding: 0; margin: 0; min-width: 0; }
button.mac-boton:hover { background-color: #6a6b6c; }
button.mac-boton.mac-boton-accion { background-image: linear-gradient(to bottom, #165ee1, #1555cb); color: #ffffff; }
button.mac-boton.mac-boton-accion:hover { background-image: linear-gradient(to bottom, #2a6cec, #1a5ed6); }
""";

    // El aviso del invitado (captura 1.32.11 PM, a 1x): botones de 21 px y el de ⏎ con el aro azul.
    const string CSS_INVITADO = """
.mac-inv-titulo { font-family: ".SF NS"; font-weight: bold; font-size: 13px; color: #dedfdf; }
.mac-inv-texto { font-family: ".SF NS"; font-size: 11px; color: #dedfdf; }
button.mac-boton-inv {
  font-family: ".SF NS"; font-size: 13px; color: #e7e7e7;
  min-height: 21px; min-width: 50px; padding: 0 10px; margin: 0; outline: none;
  border-radius: 5px; border: 1px solid transparent; box-shadow: none; text-shadow: none;
  background-image: none; background-color: #5f6061;
}
button.mac-boton-inv label { padding: 0; margin: 0; min-width: 0; }
button.mac-boton-inv:hover { background-color: #6a6b6c; }
button.mac-boton-inv.mac-boton-pordefecto { border: 2px solid rgba(34, 110, 232, 0.85); }
""";

    /** Carga una hoja de estilo para toda la pantalla, por encima del tema. */
    public void aplicar_css (string css) {
        var proveedor = new Gtk.CssProvider ();
        try {
            proveedor.load_from_data (css);
        } catch (Error e) {
            warning ("CSS: %s", e.message);
            return;
        }
        Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), proveedor,
                                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    }

    /** El estilo común de las alertas (la caja, la franja, el texto y los botones). */
    public void aplicar_estilo_alerta () {
        aplicar_css (CSS_ALERTA);
    }

    public void aplicar_estilo_invitado () {
        aplicar_css (CSS_ALERTA);
        aplicar_css (CSS_INVITADO);
    }
}
