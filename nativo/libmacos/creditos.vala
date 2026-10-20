/*
 * Los créditos que lleva el About de todos los programas de mint-macos (regla de José, 19-10-2026), todo en inglés:
 *   - la versión propia del programa (nunca la de Apple);
 *   - «Design based on macOS <nombre> <número>», del perfil de macOS activo (macos/<id>/version.json);
 *   - «Code © 2026 Jose Alberto de la Cruz Malena»;
 *   - si es un fork, «Based on <proyecto> © <autores> (<licencia>)»;
 *   - «Interface design © Apple Inc. macOS and <nombre> are trademarks of Apple Inc. Independent project, not affiliated with or endorsed by Apple.»
 * Una sola función para que todos los About salgan iguales.
 */
namespace MacOS {
    /** La versión de mint-macos que llevan todos sus programas. */
    public string version_programa () {
        return "0.1.0";
    }

    /** «macOS Catalina» y «10.15.8» del perfil activo; sin perfil, los de Catalina. */
    public void version_de_macos (out string nombre, out string numero) {
        nombre = "macOS Catalina";
        numero = "10.15.8";
        string? id = null;
        foreach (var ruta in new string[] { Path.build_filename (Environment.get_user_runtime_dir (), "mint-macos", "macos.json"),
                                            Path.build_filename (Environment.get_user_config_dir (), "mint-macos", "macos.json") }) {
            var o = leer_json_objeto (ruta);
            if (o != null && o.has_member ("version")) {
                id = o.get_string_member ("version");
                break;
            }
        }
        var v = leer_json_objeto (Path.build_filename (Environment.get_user_data_dir (), "mint-macos", "macos", id ?? "catalina-10.15", "version.json"));
        if (v == null) {
            return;
        }
        if (v.has_member ("nombre")) {
            nombre = v.get_string_member ("nombre");
        }
        if (v.has_member ("numero")) {
            numero = v.get_string_member ("numero");
        }
    }

    Json.Object? leer_json_objeto (string ruta) {
        try {
            var p = new Json.Parser ();
            p.load_from_file (ruta);
            var r = p.get_root ();
            return r != null && r.get_node_type () == Json.NodeType.OBJECT ? r.get_object () : null;
        } catch (Error e) {
            return null;
        }
    }

    public string texto_diseno () {
        string nombre, numero;
        version_de_macos (out nombre, out numero);
        return "Design based on %s %s".printf (nombre, numero);
    }

    public string texto_codigo () {
        return "Code © 2026 Jose Alberto de la Cruz Malena (GPL-3.0-or-later)";
    }

    public string texto_marcas () {
        string nombre, numero;
        version_de_macos (out nombre, out numero);
        var corto = nombre.has_prefix ("macOS ") ? nombre.substring (6) : nombre;
        return "Interface design © Apple Inc. macOS and %s are trademarks of Apple Inc. Independent project, not affiliated with or endorsed by Apple."
            .printf (corto);
    }

    /** Los créditos completos, uno por renglón (`basado_en` es «Based on …» si el programa es un fork). */
    public string texto_creditos (string? basado_en = null) {
        var s = new StringBuilder ();
        s.append (texto_diseno ());
        s.append_c ('\n');
        s.append (texto_codigo ());
        if (basado_en != null && basado_en != "") {
            s.append_c ('\n');
            s.append (basado_en);
        }
        s.append ("\n\n");
        s.append (texto_marcas ());
        return s.str;
    }

    /** El About de un programa de mint-macos. */
    public Gtk.AboutDialog dialogo_acerca (string programa, string? ruta_icono = null, string? basado_en = null, string icono_tema = "application-x-executable") {
        var d = new Gtk.AboutDialog ();
        d.program_name = programa;
        d.version = version_programa ();
        d.copyright = texto_codigo ();
        d.comments = texto_diseno () + (basado_en != null && basado_en != "" ? "\n" + basado_en : "") + "\n\n" + texto_marcas ();
        d.wrap_license = true;
        d.title = "About %s".printf (programa);
        d.skip_taskbar_hint = true;
        Gdk.Pixbuf? logo = null;
        if (ruta_icono != null) {
            try {
                logo = new Gdk.Pixbuf.from_file_at_size (ruta_icono, 64, 64);
            } catch (Error e) {
            }
        }
        if (logo != null) {
            d.logo = logo;
        } else {
            d.logo_icon_name = icono_tema;
        }
        d.response.connect (() => d.destroy ());
        return d;
    }

    /**
     * Los componentes de mint-macos con lo que se basan, para la ventana «Credits» de About This Mac (un solo lugar visible para todo el sistema).
     * Lo que sale de otro proyecto lo dice con su licencia; lo propio, solo con su autor.
     */
    public const string[] COMPONENTES = {
        "Fynder — Based on Nemo © Linux Mint and the Nautilus authors (GPL-2.0+; extension library LGPL)",
        "Muelle — Based on plank-reloaded © zquestz and Plank © Plank developers (GPL-3.0+)",
        "Spotlyte — Based on Ulauncher © Aleksandr Gornostal (GPL-3.0)",
        "Constanza (theme) — Based on Mojave-gtk-theme © Vince Liuice (GPL-3.0); cursors based on McMojave-circle © Vince Liuice (GPL-3.0)",
        "slick-greeter-mac — Based on slick-greeter © Linux Mint and Canonical (GPL-3.0)",
        "System Preferences, Activity Monitor, App Store, Force Quit, About This Mac, Lock Screen, Dock and menu services — Code © 2026 Jose Alberto de la Cruz Malena (GPL-3.0-or-later)"
    };

    /** El About de todo el sistema: el de la función común y, además, la lista de componentes con lo que se basan. */
    public Gtk.AboutDialog dialogo_creditos (string programa) {
        var d = dialogo_acerca (programa, null, null, "computer");
        d.add_credit_section ("Components", COMPONENTES);
        return d;
    }

    /**
     * Le pone a la aplicación la acción app.about (el ítem «About <programa>» del menú de la app, que appmenu@macos busca por D-Bus) y que
     * abra un solo About, el de la función común.
     */
    public void agregar_accion_acerca (Gtk.Application app, string programa, string? ruta_icono = null, string? basado_en = null,
                                       string icono_tema = "application-x-executable") {
        Gtk.AboutDialog? abierto = null;
        var accion = new SimpleAction ("about", null);
        accion.activate.connect (() => {
            if (abierto != null) {
                abierto.present ();
                return;
            }
            abierto = dialogo_acerca (programa, ruta_icono, basado_en, icono_tema);
            abierto.destroy.connect (() => { abierto = null; });
            abierto.present ();
        });
        app.add_action (accion);
    }
}
