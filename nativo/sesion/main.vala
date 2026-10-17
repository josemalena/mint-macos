/*
 * mac-sesion: el binario suelto de los diálogos de sesión (ver cli.vala). Sigue compilándose para la vuelta atrás y las pruebas.
 */
int main (string[] args) {
    return Sesion.atender (args, (t) => { stdout.printf ("%s", t); }, (t) => { stderr.printf ("%s", t); });
}
