/*
 * Siri, Profiles y CDs & DVDs: los paneles de Catalina que Linux no tiene (port de settings/ausentes.py).
 *
 * Se dibujan como en las capturas (Screen Shot 2026-10-14 at 12.13.06 AM Siri; 08-pref-…configurationprofiles y …digihub.discs)
 * pero en gris, como en una Mac que no tuviera esa función: nada se inventa ni se deja funcionando de adorno.
 * Profiles y CDs & DVDs: sin perfiles de aprovisionamiento ni unidad óptica; se dibujan igual, vacíos y en gris.
 */
namespace Preferencias {

    public class PanelSiri : Panel {
        public PanelSiri () {
            id = "com.apple.preference.speech";
            nombre = "Siri";
            palabras = "siri, voice, ask siri, hey siri, dictation";
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            caja.get_style_context ().add_class ("mp-propio");
            caja.margin_top = 18;
            caja.margin_bottom = 18;
            var izq = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            izq.set_size_request (240, -1);
            var icono = imagen_icono_panel (id, 112);
            icono.margin_top = 10;
            icono.margin_bottom = 10;
            izq.pack_start (icono, false, false, 0);
            var t = new Gtk.Label ("Siri");
            t.get_style_context ().add_class ("mp-titulo-negrita");
            izq.pack_start (t, false, false, 0);
            var c = new Gtk.CheckButton.with_label ("Enable Ask Siri");
            c.active = true;
            c.halign = Gtk.Align.CENTER;
            izq.pack_start (gris (c), false, false, 0);
            caja.pack_start (izq, false, false, 0);
            caja.pack_start (new Gtk.Separator (Gtk.Orientation.VERTICAL), false, false, 0);

            var der = new Gtk.Grid ();
            der.column_spacing = 10;
            der.row_spacing = 10;
            der.margin = 20;
            var d = new Gtk.Label ("Siri helps you get things done, just by asking. Find files on your Mac, dictate a note, check the weather, and more.");
            d.xalign = 0;
            d.set_line_wrap (true);
            d.set_max_width_chars (52);
            der.attach (d, 0, 0, 2, 1);
            var hey = new Gtk.CheckButton.with_label ("Listen for “Hey Siri” on headphones");
            der.attach (gris (hey), 1, 1, 1, 1);
            string[] t_ = { "Keyboard Shortcut:", "Language:", "Siri Voice:" };
            string[] v_ = { "Hold Command Space", "English (United States)", "American (Female)" };
            for (int i = 0; i < 3; i++) {
                der.attach (etiqueta_fila (t_[i]), 0, 2 + i, 1, 1);
                var cb = new Gtk.ComboBoxText ();
                cb.append ("v", v_[i]);
                cb.set_active (0);
                der.attach (gris (cb), 1, 2 + i, 1, 1);
            }
            der.attach (etiqueta_fila ("Voice Feedback:"), 0, 5, 1, 1);
            var vf = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12);
            var on = new Gtk.RadioButton.with_label_from_widget (null, "On");
            var off = new Gtk.RadioButton.with_label_from_widget (on, "Off");
            vf.pack_start (on, false, false, 0);
            vf.pack_start (off, false, false, 0);
            der.attach (gris (vf), 1, 5, 1, 1);
            der.attach (etiqueta_fila ("Siri History:"), 0, 6, 1, 1);
            der.attach (gris (new Gtk.Button.with_label ("Delete Siri & Dictation History")), 1, 6, 1, 1);
            var menu = new Gtk.CheckButton.with_label ("Show Siri in menu bar");
            menu.active = true;
            der.attach (gris (menu), 0, 7, 2, 1);
            der.attach (gris (new Gtk.Button.with_label ("Siri Suggestions & Privacy…")), 1, 7, 1, 1);
            caja.pack_start (der, true, true, 0);
            caja.show_all ();
            return caja;
        }
    }

    public class PanelProfiles : Panel {
        public PanelProfiles () {
            id = "com.apple.preferences.configurationprofiles";
            nombre = "Profiles";
            palabras = "profiles, configuration profiles, provisioning profiles, mdm";
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 14, 14, 14, 14);
            var cuerpo = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            var izq = marco_lista ();
            izq.set_size_request (190, 300);
            var lista = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
            var cab = new Gtk.Label ("Provisioning Profiles");
            cab.xalign = 0;
            cab.margin = 8;
            cab.get_style_context ().add_class ("mp-sd-detalle");
            lista.pack_start (cab, false, false, 0);
            izq.add (lista);
            var der = marco_lista ();
            cuerpo.pack_start (izq, false, false, 0);
            cuerpo.pack_start (der, true, true, 0);
            caja.pack_start (cuerpo, true, true, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            var botones = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            botones.get_style_context ().add_class ("linked");
            foreach (var t in new string[] { "+", "−" }) {
                botones.pack_start (gris (new Gtk.Button.with_label (t)), false, false, 0);
            }
            pie.pack_start (botones, false, false, 0);
            pie.pack_end (boton_ayuda (), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            return caja;
        }
    }

    public class PanelDiscs : Panel {
        public PanelDiscs () {
            id = "com.apple.preference.digihub.discs";
            nombre = "CDs & DVDs";
            palabras = "cd, dvd, disc, insert, blank, music cd, picture cd, video dvd, eject";
        }

        public override Gtk.Widget? construir () {
            var caja = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            caja.get_style_context ().add_class ("mp-propio");
            margenes (caja, 20, 20, 20, 20);
            var rejilla = new Gtk.Grid ();
            rejilla.column_spacing = 10;
            rejilla.row_spacing = 10;
            rejilla.halign = Gtk.Align.CENTER;
            // null es la fila de aire entre los discos en blanco y los demás.
            string?[,] filas = { { "When you insert a blank CD:", "Ask what to do" }, { "When you insert a blank DVD:", "Ask what to do" },
                                 { null, null },
                                 { "When you insert a music CD:", "Ignore" }, { "When you insert a picture CD:", "Ignore" },
                                 { "When you insert a video DVD:", "Ignore" } };
            for (int i = 0; i < 6; i++) {
                if (filas[i, 0] == null) {
                    var aire = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
                    aire.set_size_request (-1, 16);
                    rejilla.attach (aire, 0, i, 2, 1);
                    continue;
                }
                rejilla.attach (etiqueta_fila (filas[i, 0]), 0, i, 1, 1);
                var c = new Gtk.ComboBoxText ();
                c.append ("v", filas[i, 1]);
                c.set_active (0);
                c.set_size_request (236, -1);
                rejilla.attach (gris (c), 1, i, 1, 1);
            }
            var eject = new Gtk.CheckButton.with_label ("Show eject in menu bar");
            rejilla.attach (gris (eject), 1, 6, 1, 1);
            caja.pack_start (rejilla, false, false, 0);
            var pie = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
            pie.pack_end (boton_ayuda (), false, false, 0);
            caja.pack_start (pie, false, false, 0);
            caja.show_all ();
            return caja;
        }
    }
}
