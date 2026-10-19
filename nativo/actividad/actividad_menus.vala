/*
 * La barra de menús de Activity Monitor (nib de Catalina 10.14, referencias/activity-monitor-catalina-recursos): File, Edit, View,
 * Window y Help, con los atajos de la Mac (⌘ es Ctrl con keyd). La app la exporta como GMenuModel y el menú global la pinta en el
 * panel. Lo que esta versión hace tiene su acción en la ventana (win.*); el resto va en gris (acción sin definir) hasta que se
 * implemente. El menú «Activity Monitor» (About, Hide, Quit) lo pone appmenu@macos.
 */
namespace Actividad {
    class Menus {
        const string NADA = "win.sin-implementar";

        static MenuItem it (string etiqueta, string accion, string? accel = null, string? literal = null) {
            var i = new MenuItem (etiqueta, accion);
            if (accel != null) i.set_attribute_value ("accel", new Variant.string (accel));
            if (literal != null) i.set_attribute_value ("x-constanza-accel", new Variant.string (literal));
            return i;
        }

        static MenuItem radio (string etiqueta, string accion, string objetivo) {
            var i = new MenuItem (etiqueta, null);
            i.set_action_and_target_value (accion, new Variant.string (objetivo));
            return i;
        }

        public static MenuModel construir () {
            var barra = new Menu ();

            var archivo = new Menu ();
            archivo.append_item (it ("Close", "win.cerrar", "<Primary>w"));
            var impresion = new Menu ();
            impresion.append_item (it ("Page Setup…", NADA, "<Primary><Shift>p"));
            impresion.append_item (it ("Print…", NADA, "<Primary>p"));
            archivo.append_section (null, impresion);
            barra.append_submenu ("File", archivo);

            var edicion = new Menu ();
            var deshacer = new Menu ();
            deshacer.append_item (it ("Undo", NADA, "<Primary>z"));
            deshacer.append_item (it ("Redo", NADA, "<Primary><Shift>z"));
            edicion.append_section (null, deshacer);
            var portapapeles = new Menu ();
            portapapeles.append_item (it ("Cut", NADA, "<Primary>x"));
            portapapeles.append_item (it ("Copy", NADA, "<Primary>c"));
            portapapeles.append_item (it ("Paste", NADA, "<Primary>v"));
            portapapeles.append_item (it ("Delete", NADA));
            portapapeles.append_item (it ("Select All", NADA, "<Primary>a"));
            edicion.append_section (null, portapapeles);
            var buscar = new Menu ();
            buscar.append_item (it ("Find…", "win.buscar", "<Primary>f"));
            buscar.append_item (it ("Find Next", NADA, "<Primary>g"));
            buscar.append_item (it ("Find Previous", NADA, "<Primary><Shift>g"));
            buscar.append_item (it ("Use Selection for Find", NADA, "<Primary>e"));
            buscar.append_item (it ("Jump to Selection", NADA, "<Primary>j"));
            edicion.append_submenu ("Find", buscar);
            barra.append_submenu ("Edit", edicion);

            var ver = new Menu ();
            var columnas = new Menu ();
            foreach (var c in new string[] { "Process ID", "User", "% CPU", "CPU Time", "% GPU", "GPU Time", "# Threads", "# Ports",
                                              "Real Memory", "Real Private Memory", "Real Shared Memory", "Sudden Termination",
                                              "Sandbox", "Restricted", "Idle Wake Ups", "Energy Impact", "App Nap", "Sent Bytes",
                                              "Sent Packets", "Received Bytes", "Received Packets", "Purgeable Memory", "Memory",
                                              "Compressed Memory", "Graphics Card", "Bytes Written", "Bytes Read", "Preventing Sleep" })
                columnas.append_item (it (c, NADA));
            var grupo_columnas = new Menu ();
            grupo_columnas.append_submenu ("Columns", columnas);
            var dock = new Menu ();
            var dock1 = new Menu ();
            dock1.append_item (it ("Show CPU Usage", NADA));
            dock1.append_item (it ("Show CPU History", NADA));
            dock.append_section (null, dock1);
            var dock2 = new Menu ();
            dock2.append_item (it ("Show Network Usage", NADA));
            dock2.append_item (it ("Show Disk Activity", NADA));
            dock.append_section (null, dock2);
            var dock3 = new Menu ();
            dock3.append_item (it ("Show Application Icon", NADA));
            dock.append_section (null, dock3);
            grupo_columnas.append_submenu ("Dock Icon", dock);
            var frecuencia = new Menu ();
            frecuencia.append_item (radio ("Very often (1 sec)", "win.frecuencia", "1"));
            frecuencia.append_item (radio ("Often (2 sec)", "win.frecuencia", "2"));
            frecuencia.append_item (radio ("Normally (5 sec)", "win.frecuencia", "5"));
            grupo_columnas.append_submenu ("Update Frequency", frecuencia);
            ver.append_section (null, grupo_columnas);
            var filtros = new Menu ();
            filtros.append_item (radio ("All Processes", "win.filtro", "todos"));
            filtros.append_item (it ("All Processes, Hierarchically", NADA));
            filtros.append_item (radio ("My Processes", "win.filtro", "mios"));
            filtros.append_item (radio ("System Processes", "win.filtro", "sistema"));
            filtros.append_item (radio ("Other User Processes", "win.filtro", "otros"));
            filtros.append_item (it ("Active Processes", NADA));
            filtros.append_item (it ("Inactive Processes", NADA));
            filtros.append_item (it ("GPU Processes", NADA));
            filtros.append_item (it ("Windowed Processes", NADA));
            filtros.append_item (it ("Selected Processes", NADA));
            filtros.append_item (it ("Applications in last 12 hours", NADA));
            filtros.append_item (it ("Processes, by GPU", NADA));
            ver.append_section (null, filtros);
            var acciones = new Menu ();
            acciones.append_item (it ("Filter Processes", "win.buscar", "<Primary><Alt>f"));
            acciones.append_item (it ("Inspect Process", NADA, "<Primary>i"));
            acciones.append_item (it ("Sample Process", NADA, "<Primary><Alt>s"));
            acciones.append_item (it ("Run Spindump", NADA, null, "^⌥⌘S"));
            acciones.append_item (it ("Run System Diagnostics…", NADA));
            acciones.append_item (it ("Quit Process", "win.salir", "<Primary><Alt>q"));
            acciones.append_item (it ("Send Signal to Process…", "win.senal"));
            acciones.append_item (it ("Show Deltas for Process", NADA, "<Primary><Alt>j"));
            ver.append_section (null, acciones);
            var limpiar = new Menu ();
            limpiar.append_item (it ("Clear CPU History", NADA, "<Primary>k"));
            ver.append_section (null, limpiar);
            barra.append_submenu ("View", ver);

            var ventana = new Menu ();
            var v1 = new Menu ();
            v1.append_item (it ("Minimize", "win.minimizar", "<Primary>m"));
            v1.append_item (it ("Zoom", "win.zoom"));
            ventana.append_section (null, v1);
            var v2 = new Menu ();
            v2.append_item (it ("Activity Monitor", "win.principal", "<Primary>1"));
            v2.append_item (it ("CPU Usage", NADA, "<Primary>2"));
            v2.append_item (it ("CPU History", NADA, "<Primary>3"));
            v2.append_item (it ("GPU History", NADA, "<Primary>4"));
            var flotante = new Menu ();
            flotante.append_item (it ("Horizontal", NADA, "<Primary>4"));
            flotante.append_item (it ("Vertical", NADA, "<Primary>5"));
            flotante.append_item (it ("None", NADA));
            v2.append_submenu ("Floating CPU Window", flotante);
            ventana.append_section (null, v2);
            var v3 = new Menu ();
            v3.append_item (it ("Keep CPU Windows on Top", NADA));
            ventana.append_section (null, v3);
            var v4 = new Menu ();
            v4.append_item (it ("Arrange in Front", NADA));
            ventana.append_section (null, v4);
            barra.append_submenu ("Window", ventana);

            var ayuda = new Menu ();
            ayuda.append_item (it ("Activity Monitor Help", NADA, "<Primary><Shift>question"));
            barra.append_submenu ("Help", ayuda);
            return barra;
        }
    }
}
