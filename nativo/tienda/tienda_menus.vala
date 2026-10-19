/*
 * La barra de menús del App Store (el MainMenu del nib de Catalina): Edit, Window y Help; el menú «App Store» (About, Preferences…,
 * Hide, Quit) lo pone appmenu@macos. Con acción: Cut, Copy, Paste, Delete y Select All sobre el campo de texto con el foco, Close,
 * Minimize, Zoom y Enter Full Screen; lo demás va en gris (acción sin definir) hasta que exista.
 */
namespace Tienda {
    class Menus {
        const string NADA = "win.sin-implementar";

        static MenuItem it (string etiqueta, string accion, string? accel = null, string? literal = null) {
            var i = new MenuItem (etiqueta, accion);
            if (accel != null) i.set_attribute_value ("accel", new Variant.string (accel));
            if (literal != null) i.set_attribute_value ("x-constanza-accel", new Variant.string (literal));
            return i;
        }

        public static MenuModel construir () {
            var barra = new Menu ();

            var edicion = new Menu ();
            var deshacer = new Menu ();
            deshacer.append_item (it ("Undo", NADA, "<Primary>z"));
            deshacer.append_item (it ("Redo", NADA, "<Primary><Shift>z"));
            edicion.append_section (null, deshacer);
            var portapapeles = new Menu ();
            portapapeles.append_item (it ("Cut", "win.cortar", "<Primary>x"));
            portapapeles.append_item (it ("Copy", "win.copiar", "<Primary>c"));
            portapapeles.append_item (it ("Paste", "win.pegar", "<Primary>v"));
            portapapeles.append_item (it ("Paste and Match Style", NADA, "<Primary><Alt><Shift>v"));
            portapapeles.append_item (it ("Delete", "win.borrar"));
            portapapeles.append_item (it ("Select All", "win.todo", "<Primary>a"));
            edicion.append_section (null, portapapeles);
            barra.append_submenu ("Edit", edicion);

            var ventana = new Menu ();
            var v1 = new Menu ();
            v1.append_item (it ("Close", "win.cerrar", "<Primary>w"));
            v1.append_item (it ("Minimize", "win.minimizar", "<Primary>m"));
            v1.append_item (it ("Zoom", "win.zoom"));
            v1.append_item (it ("Enter Full Screen", "win.pantalla-completa", null, "^⌘F"));
            ventana.append_section (null, v1);
            var v2 = new Menu ();
            v2.append_item (it ("Bring All to Front", NADA));
            ventana.append_section (null, v2);
            barra.append_submenu ("Window", ventana);

            var ayuda = new Menu ();
            ayuda.append_item (it ("App Store Help", NADA));
            ayuda.append_item (it ("About App Store & Privacy", NADA));
            barra.append_submenu ("Help", ayuda);
            return barra;
        }
    }
}
