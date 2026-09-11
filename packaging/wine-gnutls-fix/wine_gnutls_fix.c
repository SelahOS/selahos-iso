/*
 * wine_gnutls_fix.so — LD_PRELOAD interposer for Wine's schannel_gnutls backend.
 *
 * Wine's secur32/schannel_gnutls.c calls gnutls_priority_set_direct() to
 * configure the TLS priority string for a session. On this system, letting
 * gnutls negotiate TLS 1.3 corrupts buffer-size calculations inside
 * Foundation.dll (used by Spark/SparkCore and other Electron-ish Windows
 * apps built with Swift interop), producing an ACCESS_VIOLATION deep in
 * wine's ntdll page-fault handler.
 *
 * This interposer appends ":-VERS-TLS1.3" to whatever priority string the
 * caller passes, forcing negotiation down to TLS 1.2, then calls through to
 * the real gnutls_priority_set_direct(). No other behavior changes.
 *
 * Reconstructed 2026-09-06 after the original /tmp copy was lost on reboot
 * (tmpfs). Installed under ~/.local/lib so it survives reboots.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

typedef int (*orig_priority_set_direct_t)(void *priority_cache,
                                           const char *priorities,
                                           const char **err_pos);

int gnutls_priority_set_direct(void *priority_cache,
                                const char *priorities,
                                const char **err_pos)
{
    static orig_priority_set_direct_t real_fn = NULL;
    if (!real_fn) {
        real_fn = (orig_priority_set_direct_t)dlsym(RTLD_NEXT, "gnutls_priority_set_direct");
        if (!real_fn) {
            fprintf(stderr, "[wine_gnutls_fix] dlsym failed: %s\n", dlerror());
            return -1;
        }
    }

    char patched[4096];
    if (priorities) {
        snprintf(patched, sizeof(patched), "%s:-VERS-TLS1.3", priorities);
    } else {
        snprintf(patched, sizeof(patched), "NORMAL:-VERS-TLS1.3");
    }

    return real_fn(priority_cache, patched, err_pos);
}
