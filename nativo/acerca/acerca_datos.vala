/*
 * Lo que enseña About This Mac / About This PC. Todo lo que se lee al arrancar (modelo, procesador, memoria, gráficos,
 * serie, sistema y logo) sale de /run/mint-macos/equipo.json, que escribe un solo programa (mint-macos-equipo): aquí no
 * se lee /proc, ni lspci ni DMI. Si el archivo no está, solo salen los datos de os-release y ninguna fila de hardware;
 * un campo que no viene (serie, velocidad de la memoria) no muestra fila. Lo que cambia con el sistema corriendo
 * (las pantallas por su EDID y los discos) se lee en vivo.
 */
namespace Acerca {
    public const string RUTA_EQUIPO = "/run/mint-macos/equipo.json";

    /** Las pruebas apuntan a otro equipo.json con MINT_MACOS_EQUIPO. */
    string ruta_equipo () {
        return Environment.get_variable ("MINT_MACOS_EQUIPO") ?? RUTA_EQUIPO;
    }

    public class Equipo : Object {
        public string tipo = "pc";                 // «mac» o «pc»
        public string nombre = "";                 // «Mac mini (Late 2012)», o fabricante y modelo en un PC
        public string sistema = "Linux";
        public string version = "";                // «22.3 (Zena)»
        public string logo = "";
        public string logo_icono = "";
        public string serie = "";
        public string procesador = "";             // «2.5 GHz Dual-Core Intel Core i5»
        public string memoria = "";                // «16 GB 1333 MHz DDR3»
        public string graficos = "";               // «Intel HD Graphics 4000 1536 MB»

        /** «About This Mac» o «About This PC», según el equipo. */
        public string etiqueta_menu () {
            return tipo == "mac" ? "About This Mac" : "About This PC";
        }

        public static Equipo cargar () {
            var e = new Equipo ();
            try {
                var p = new Json.Parser ();
                p.load_from_file (ruta_equipo ());
                var o = p.get_root ().get_object ();
                e.tipo = o.get_string_member_with_default ("tipo", "pc");
                e.nombre = o.get_string_member_with_default ("nombre", "");
                if (e.nombre == "") {
                    e.nombre = "%s %s".printf (o.get_string_member_with_default ("fabricante", ""),
                                               o.get_string_member_with_default ("identificador", "")).strip ();
                }
                if (o.has_member ("serie") && !o.get_null_member ("serie")) e.serie = o.get_string_member ("serie");
                e.procesador = texto_de (o, "procesador");
                e.memoria = texto_de (o, "memoria");
                if (o.has_member ("graficos") && o.get_member ("graficos").get_node_type () == Json.NodeType.ARRAY) {
                    var g = o.get_array_member ("graficos");
                    if (g.get_length () > 0) e.graficos = g.get_object_element (0).get_string_member_with_default ("texto", "");
                }
                e.logo = o.get_string_member_with_default ("logo", "");
                e.logo_icono = o.get_string_member_with_default ("logo_icono", "");
                if (o.has_member ("sistema")) {
                    var s = o.get_object_member ("sistema");
                    e.sistema = s.get_string_member_with_default ("nombre", "Linux");
                    e.version = s.get_string_member_with_default ("version", "");
                }
                return e;
            } catch (Error err) {
                // sin el servicio: solo os-release
            }
            var os = os_release ();
            e.sistema = os.contains ("NAME") ? os["NAME"] : "Linux";
            e.version = os.contains ("VERSION") ? os["VERSION"] : "";
            e.logo_icono = os.contains ("LOGO") ? os["LOGO"] : "";
            return e;
        }

        static string texto_de (Json.Object o, string clave) {
            if (!o.has_member (clave) || o.get_member (clave).get_node_type () != Json.NodeType.OBJECT) return "";
            return o.get_object_member (clave).get_string_member_with_default ("texto", "");
        }

        /** «Linux Mint» y «Zena» de «22.3 (Zena)»: el nombre del sistema y su nombre de versión, si lo trae. */
        public string version_numero () {
            int i = version.index_of (" (");
            return i > 0 ? version.substring (0, i) : version;
        }

        public string version_nombre () {
            int i = version.index_of (" (");
            if (i < 0 || !version.has_suffix (")")) return "";
            return version.substring (i + 2, version.length - i - 3);
        }
    }

    public string leer (string ruta) {
        try {
            string t;
            FileUtils.get_contents (ruta, out t);
            return t.strip ();
        } catch (Error e) {
            return "";
        }
    }

    HashTable<string, string> os_release () {
        var h = new HashTable<string, string> (str_hash, str_equal);
        foreach (var linea in leer ("/etc/os-release").split ("\n")) {
            int i = linea.index_of_char ('=');
            if (i > 0) h[linea.substring (0, i)] = linea.substring (i + 1).replace ("\"", "");
        }
        return h;
    }

    string ejecutar (string[] cmd) {
        try {
            var p = new Subprocess.newv (cmd, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            string salida;
            p.communicate_utf8 (null, null, out salida, null);
            return salida ?? "";
        } catch (Error e) {
            return "";
        }
    }

    // ── Overview ────────────────────────────────────────────────────────

    /** Dónde está el sistema: la etiqueta del volumen raíz, o el nombre del sistema. */
    public string disco_de_arranque (string respaldo) {
        var montajes = montajes_de_discos ();
        var dev = montajes.lookup ("/");
        var etiqueta = dev != null ? etiqueta_de (dev) : "";
        return etiqueta != "" ? etiqueta : respaldo;
    }

    // ── Displays ────────────────────────────────────────────────────────

    public class Pantalla : Object {
        public string nombre = "";     // «LEN T2454pA Display»
        public double pulgadas = 0;        // con un decimal, del EDID
        public int ancho = 0;
        public int alto = 0;
    }

    /** Las pantallas conectadas, con el nombre y el tamaño que dice su EDID (la Mac lo lee igual). */
    public Pantalla[] pantallas () {
        Pantalla[] salida = {};
        var display = Gdk.Display.get_default ();
        if (display == null) return salida;
        for (int i = 0; i < display.get_n_monitors (); i++) {
            var m = display.get_monitor (i);
            var g = m.get_geometry ();
            var p = new Pantalla ();
            p.ancho = g.width * m.get_scale_factor ();
            p.alto = g.height * m.get_scale_factor ();
            var salida_x = m.get_model () ?? "";
            var edid = edid_de (salida_x);
            double diag = 0;
            if (edid.length >= 128) {
                p.nombre = nombre_edid (edid);
                diag = Math.sqrt ((double) (edid[21] * edid[21] + edid[22] * edid[22])) / 2.54;
            }
            if (diag <= 0 && m.get_width_mm () > 0) {
                diag = Math.sqrt ((double) (m.get_width_mm () * m.get_width_mm () + m.get_height_mm () * m.get_height_mm ())) / 25.4;
            }
            p.pulgadas = Math.round (diag * 10) / 10.0;
            if (p.nombre == "") p.nombre = salida_x != "" ? salida_x : "Display";
            salida += p;
        }
        return salida;
    }

    /** El EDID de la salida «HDMI-3» (en sysfs es «card1-HDMI-A-3»). */
    uint8[] edid_de (string salida_x) {
        if (salida_x == "") return {};
        try {
            var dir = Dir.open ("/sys/class/drm");
            string? n;
            while ((n = dir.read_name ()) != null) {
                int i = n.index_of_char ('-');
                if (i < 0) continue;
                var conector = n.substring (i + 1).replace ("-A-", "-");
                if (conector != salida_x) continue;
                uint8[] datos;
                FileUtils.get_data ("/sys/class/drm/%s/edid".printf (n), out datos);
                if (datos.length < 128) continue;
                return datos;
            }
        } catch (Error e) {
        }
        return {};
    }

    /** «LEN T2454pA Display»: las 3 letras del fabricante (bytes 8-9) y el nombre del descriptor 0xFC. */
    string nombre_edid (uint8[] b) {
        int fab = (b[8] << 8) | b[9];
        var id = "%c%c%c".printf ((char) (((fab >> 10) & 31) + 64), (char) (((fab >> 5) & 31) + 64), (char) ((fab & 31) + 64));
        string modelo = "";
        for (int o = 54; o <= 108; o += 18) {
            if (b[o] == 0 && b[o + 1] == 0 && b[o + 3] == 0xFC) {
                var sb = new StringBuilder ();
                for (int k = 5; k < 18 && b[o + k] != 0x0A; k++) sb.append_c ((char) b[o + k]);
                modelo = sb.str.strip ();
            }
        }
        // muchos monitores ya traen el fabricante en el nombre («LEN T2454pA»)
        if (modelo == "") return "%s Display".printf (id);
        return modelo.has_prefix (id) ? "%s Display".printf (modelo) : "%s %s Display".printf (id, modelo);
    }

    /** «24-inch» o «17.1-inch»: un decimal solo si hace falta, como la Mac. */
    public string pulgadas_texto (double p) {
        var t = "%.1f".printf (p).replace (",", ".");
        if (t.has_suffix (".0")) t = t.substring (0, t.length - 2);
        return "%s-inch".printf (t);
    }

    // ── Storage ─────────────────────────────────────────────────────────

    public class Volumen : Object {
        public string nombre = "";
        public string dispositivo = "";
        public int64 tamano = 0;
        public int64 libre = 0;
        public string descripcion = "";     // «500 GB\nSolid State\nSATA Drive»
        public bool externo = false;
    }

    /** punto de montaje → dispositivo, de los discos reales (nada de loop, tmpfs ni /boot/efi). */
    HashTable<string, string> montajes_de_discos () {
        var h = new HashTable<string, string> (str_hash, str_equal);
        foreach (var l in leer ("/proc/self/mounts").split ("\n")) {
            var c = l.split (" ");
            // solo discos de verdad: nada de loop, de FUSE (las imágenes montadas) ni de tmpfs
            if (c.length < 3 || !Regex.match_simple ("^/dev/(sd[a-z]+|nvme[0-9]+n[0-9]+p|mmcblk[0-9]+p|vd[a-z]+|dm-)[0-9]*$", c[0])) continue;
            var mp = c[1].replace ("\\040", " ");
            if (mp.has_prefix ("/boot") || mp.has_prefix ("/var/snap") || mp.has_prefix ("/snap")) continue;
            h[mp] = c[0];
        }
        return h;
    }

    string etiqueta_de (string dispositivo) {
        try {
            var dir = Dir.open ("/dev/disk/by-label");
            string? n;
            while ((n = dir.read_name ()) != null) {
                var destino = FileUtils.read_link ("/dev/disk/by-label/" + n);
                if (Path.get_basename (destino) == Path.get_basename (dispositivo)) {
                    return Uri.unescape_string (n.replace ("\\x20", " ")) ?? n;
                }
            }
        } catch (Error e) {
        }
        return "";
    }

    string describir_disco (string dispositivo, out bool externo) {
        externo = false;
        var padre = ejecutar ({ "lsblk", "-no", "PKNAME", dispositivo }).strip ();
        var base_ = padre != "" ? "/dev/" + padre : dispositivo;
        var campos = ejecutar ({ "lsblk", "-dnb", "-o", "SIZE,ROTA,TRAN,RM", base_ }).strip ().split (" ");
        string[] c = {};
        foreach (var x in campos) if (x != "") c += x;
        if (c.length < 2) return "";
        var bytes = int64.parse (c[0]);
        var tam = bytes >= 900000000000 ? "%.0f TB".printf (bytes / 1e12 < 1.5 ? 1.0 : bytes / 1e12) : "%d GB".printf ((int) Math.round (bytes / 1e9));
        if (bytes >= 900000000000 && bytes < 1500000000000) tam = "1 TB";
        var tran = c.length > 2 ? c[2].up () : "";
        externo = tran == "USB" || (c.length > 3 && c[c.length - 1] == "1");
        if (externo) return "External %s\n%s Disk".printf (tam, tran != "" ? tran : "USB");
        return "%s\n%s\n%s".printf (tam, c[1] == "0" ? "Solid State" : "Hard Disk", tran != "" ? tran + " Drive" : "Drive");
    }

    public Volumen[] volumenes (string nombre_sistema) {
        Volumen[] salida = {};
        var vistos = new HashTable<string, string> (str_hash, str_equal);
        var montajes = montajes_de_discos ();
        string[] llaves = {};
        montajes.foreach ((k, d) => { llaves += k.dup (); });
        // la raíz primero, el resto por nombre
        for (int i = 1; i < llaves.length; i++) {
            var x = llaves[i];
            int j = i - 1;
            while (j >= 0 && (llaves[j] != "/" && (x == "/" || strcmp (llaves[j], x) > 0))) {
                llaves[j + 1] = llaves[j];
                j--;
            }
            llaves[j + 1] = x;
        }
        foreach (var mp in llaves) {
            var dev = montajes[mp];
            if (vistos.contains (dev)) continue;
            vistos[dev] = "1";
            var v = new Volumen ();
            v.dispositivo = dev;
            var et = etiqueta_de (dev);
            if (et != "") v.nombre = et;
            else if (mp == "/") v.nombre = nombre_sistema;
            else v.nombre = Path.get_basename (mp);
            try {
                var info = File.new_for_path (mp).query_filesystem_info ("filesystem::size,filesystem::free", null);
                v.tamano = (int64) info.get_attribute_uint64 ("filesystem::size");
                v.libre = (int64) info.get_attribute_uint64 ("filesystem::free");
            } catch (Error e) {
                continue;
            }
            bool ext;
            v.descripcion = describir_disco (dev, out ext);
            v.externo = ext;
            salida += v;
        }
        return salida;
    }

    /** «92.58 GB» / «1 TB» / «190 MB», como las cifras de la Mac (base 10). */
    public string tamano_legible (int64 b) {
        if (b >= 1000000000000) return "%s TB".printf (cifra (b / 1e12));
        if (b >= 1000000000) return "%s GB".printf (cifra (b / 1e9));
        return "%d MB".printf ((int) Math.round (b / 1e6));
    }

    string cifra (double d) {
        var s = "%.2f".printf (d);
        if (s.contains (".")) s = s.chomp ().replace (",", ".");
        while (s.has_suffix ("0")) s = s.substring (0, s.length - 1);
        if (s.has_suffix (".")) s = s.substring (0, s.length - 1);
        return s;
    }
}

namespace Acerca {
    /** Lo leído del equipo, en texto: lo usan las pruebas (mac-acerca --texto). */
    public string resumen () {
        var e = Equipo.cargar ();
        var sb = new StringBuilder ();
        sb.append ("menu: %s\n".printf (e.etiqueta_menu ()));
        sb.append ("sistema: %s | versión %s | nombre %s\n".printf (e.sistema, e.version_numero (), e.version_nombre ()));
        sb.append ("equipo: %s\n".printf (e.nombre));
        sb.append ("procesador: %s\nmemoria: %s\ndisco de arranque: %s\ngráficos: %s\nserie: %s\n".printf (
            e.procesador, e.memoria, disco_de_arranque (e.sistema), e.graficos, e.serie));
        foreach (var p in pantallas ()) sb.append ("pantalla: %s | %s | %d x %d\n".printf (p.nombre, pulgadas_texto (p.pulgadas), p.ancho, p.alto));
        foreach (var v in volumenes (e.sistema)) {
            sb.append ("volumen: %s | %s de %s | %s\n".printf (v.nombre, tamano_legible (v.libre), tamano_legible (v.tamano), v.descripcion.replace ("\n", " / ")));
        }
        return sb.str;
    }
}
