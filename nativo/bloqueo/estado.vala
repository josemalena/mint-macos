/*
 * El estado del bloqueo, en $XDG_RUNTIME_DIR/mint-macos (solo el dueño lo lee):
 *   bloqueado     existe mientras la pantalla debe estar bloqueada; se escribe ANTES de dibujar nada y se borra solo cuando la
 *                 clave correcta salió del hijo de la pantalla
 *   bloqueo.lock  lo sostiene el supervisor (fcntl); si nadie lo sostiene y «bloqueado» existe, el vigilante relanza el bloqueo
 */
namespace Bloqueo.Estado {
    string carpeta () {
        var base_dir = Environment.get_variable ("XDG_RUNTIME_DIR") ?? "/tmp/mac-bloqueo-%u".printf ((uint) Posix.getuid ());
        var d = Path.build_filename (base_dir, "mint-macos");
        DirUtils.create_with_parents (d, 0700);
        return d;
    }

    string ruta_bandera () { return Path.build_filename (carpeta (), "bloqueado"); }
    string ruta_candado () { return Path.build_filename (carpeta (), "bloqueo.lock"); }

    public bool bloqueado () { return FileUtils.test (ruta_bandera (), FileTest.EXISTS); }

    public void marcar () {
        try {
            FileUtils.set_contents (ruta_bandera (), "%lld\n".printf (get_real_time () / 1000000));
        } catch (FileError e) {
            critical ("no pude escribir el estado de bloqueo: %s", e.message);
        }
    }

    public void borrar () { FileUtils.unlink (ruta_bandera ()); }

    /** Toma el candado del supervisor. Devuelve el descriptor, o -1 si otro supervisor ya lo tiene. */
    public int tomar_candado () {
        int fd = Posix.open (ruta_candado (), Posix.O_RDWR | Posix.O_CREAT | Posix.O_CLOEXEC, 0600);
        if (fd < 0) {
            return -1;
        }
        var f = Posix.Flock ();
        f.l_type = Posix.F_WRLCK;
        f.l_whence = Posix.SEEK_SET;
        if (Posix.fcntl (fd, Posix.F_SETLK, &f) != 0) {
            Posix.close (fd);
            return -1;
        }
        return fd;
    }

    /** ¿Hay un supervisor vivo? (alguien tiene el candado) */
    public bool supervisor_vivo () {
        int fd = Posix.open (ruta_candado (), Posix.O_RDWR | Posix.O_CREAT | Posix.O_CLOEXEC, 0600);
        if (fd < 0) {
            return false;
        }
        var f = Posix.Flock ();
        f.l_type = Posix.F_WRLCK;
        f.l_whence = Posix.SEEK_SET;
        bool vivo = Posix.fcntl (fd, Posix.F_GETLK, &f) == 0 && f.l_type != Posix.F_UNLCK;
        Posix.close (fd);
        return vivo;
    }
}
