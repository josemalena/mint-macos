// SPDX-License-Identifier: GPL-3.0-or-later
[CCode (cheader_filename = "pam_ayuda.h")]
namespace PamAyuda {
    [CCode (cname = "mac_bloqueo_autenticar")]
    public int autenticar (string servicio, string usuario, [CCode (array_length = false)] uint8[] clave, size_t largo);
}
