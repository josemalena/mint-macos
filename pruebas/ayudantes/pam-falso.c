/* Un PAM de mentira para probar mac-bloqueo sin tocar la clave de nadie: LD_PRELOAD de esto, y la clave correcta es «buena».
   Solo vive en las pruebas; el binario de verdad no trae ninguna clave ni ningún atajo. */
#include <stdlib.h>
#include <string.h>
struct pam_message { int msg_style; const char *msg; };
struct pam_response { char *resp; int resp_retcode; };
struct pam_conv { int (*conv)(int, const struct pam_message **, struct pam_response **, void *); void *appdata_ptr; };
static const struct pam_conv *guardada;
int pam_start(const char *s, const char *u, const struct pam_conv *c, void **h) { guardada = c; *h = (void *) 1; return 0; }
int pam_authenticate(void *h, int f) {
    struct pam_message m = { 1, "Password:" };
    const struct pam_message *pm = &m;
    struct pam_response *r = NULL;
    if (guardada->conv(1, &pm, &r, guardada->appdata_ptr) != 0 || !r) return 7;
    int ok = r[0].resp && strcmp(r[0].resp, "buena") == 0;
    if (r[0].resp) { memset(r[0].resp, 0, strlen(r[0].resp)); free(r[0].resp); }
    free(r);
    return ok ? 0 : 7;
}
int pam_acct_mgmt(void *h, int f) { return 0; }
int pam_end(void *h, int r) { return 0; }
