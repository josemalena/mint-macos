// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * mac-bloqueo: la pantalla de bloqueo de mint-macos (Lock Screen, ⌃⌘Q), dentro de la sesión, sin pasar por el greeter de LightDM.
 *   mac-bloqueo              bloquea (supervisor + pantalla); sale cuando se desbloquea. Si ya hay un bloqueo, no hace nada.
 *   mac-bloqueo --pantalla   solo la pantalla (lo lanza el supervisor)
 *   mac-bloqueo --vigilar    el vigilante: relanza el bloqueo si algo lo mató (para un servicio de usuario con Restart=always)
 *   mac-bloqueo --liberar    salida de emergencia: quita el bloqueo (para quien ya entró a la cuenta por una consola o por ssh)
 *   mac-bloqueo --estado     imprime «bloqueado» o «libre»; sale 0 si está bloqueado
 */
int main (string[] args) {
    string modo = args.length > 1 ? args[1] : "";
    switch (modo) {
    case "--pantalla":
        return Bloqueo.pantalla (args);
    case "--vigilar":
        return Bloqueo.Supervisor.vigilar ();
    case "--liberar":
        return Bloqueo.Supervisor.liberar ();
    case "--estado":
        stdout.printf ("%s\n", Bloqueo.Estado.bloqueado () ? "bloqueado" : "libre");
        return Bloqueo.Estado.bloqueado () ? 0 : 1;
    case "":
        return Bloqueo.Supervisor.bloquear ();
    default:
        stderr.printf ("uso: mac-bloqueo [--pantalla | --vigilar | --estado]\n");
        return 2;
    }
}
