/*
 * motu_com_stub.c — Minimal COM stub for MOTU Digital Performer
 *
 * CLSID {E6BADE5B-E703-4672-B167-4AC9C9206747} is called by DP's osfoundation
 * initialization path. On Windows with a MOTU driver installed, this class is
 * registered; on Wine without the driver, CoCreateInstance fails and the
 * returned null pointer causes a crash at dp+0x1958065.
 *
 * The global singleton pointer is loaded from a .data global, checked for null,
 * and passed through osfoundation→perffoundation→dp callbacks. As long as the
 * pointer is non-null, DP handles subsequent null fields gracefully (logged and
 * skipped). This stub returns a minimally valid COM object (IUnknown + fat vtable)
 * to prevent the crash.
 *
 * Selah Technologies LLC — SelahBridgePro project
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <objbase.h>
#include <unknwn.h>

/* ------------------------------------------------------------------ */
/* Fat vtable — 64 slots; entries 0-2 are IUnknown, rest return S_OK  */
/* ------------------------------------------------------------------ */

#define VTBL_SIZE 64

typedef HRESULT (STDMETHODCALLTYPE *VEntry)(void *);
static VEntry g_vtbl[VTBL_SIZE];

static HRESULT STDMETHODCALLTYPE Obj_QI(void *pThis, const IID *riid, void **ppv)
{
    /* Return self for every QI — universal COM black-hole */
    *ppv = pThis;
    return S_OK;
}

static ULONG STDMETHODCALLTYPE Obj_AddRef(void *pThis) { return 2; }
static ULONG STDMETHODCALLTYPE Obj_Release(void *pThis) { return 1; }

/* All other virtual slots: accept any call signature, return S_OK / 0 */
static HRESULT STDMETHODCALLTYPE Stub_Noop(void *pThis) { return S_OK; }

static void init_vtbl(void)
{
    g_vtbl[0] = (VEntry)Obj_QI;
    g_vtbl[1] = (VEntry)Obj_AddRef;
    g_vtbl[2] = (VEntry)Obj_Release;
    for (int i = 3; i < VTBL_SIZE; i++)
        g_vtbl[i] = (VEntry)Stub_Noop;
}

/* ------------------------------------------------------------------ */
/* Stub object — 512 bytes; every 8-byte field after the vtable ptr    */
/* is initialized to point back to the object itself, so that chains   */
/* of dereferences (obj->field->method) land on valid stub objects.    */
/* ------------------------------------------------------------------ */

#define STUB_BYTES 512

typedef struct {
    VEntry *lpVtbl;     /* offset 0 */
    LONG    refcount;   /* offset 8 */
    LONG    _pad;       /* offset 12 */
    /* offset 16 … STUB_BYTES-1: self-pointer grid (see CreateInstance) */
    char    body[STUB_BYTES - 16];
} StubObj;

static StubObj *make_stub(void)
{
    StubObj *obj = (StubObj *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, STUB_BYTES);
    if (!obj) return NULL;
    obj->lpVtbl   = g_vtbl;
    obj->refcount = 1;
    /* Fill every 8-byte-aligned slot from offset 16 onward with self-pointer.
     * DP's disassembly shows it reads [rbx+0x50]; offset 0x50 = 80 bytes in.
     * By pointing all such fields back at obj, any further COM dereference
     * from those fields will also find a valid vtable at offset 0. */
    int slots = (STUB_BYTES - 16) / 8;
    void **grid = (void **)((char *)obj + 16);
    for (int i = 0; i < slots; i++)
        grid[i] = (void *)obj;
    return obj;
}

/* ------------------------------------------------------------------ */
/* Class factory                                                        */
/* ------------------------------------------------------------------ */

typedef struct {
    void **lpVtbl;
} CF;

static HRESULT STDMETHODCALLTYPE CF_QI(CF *self, const IID *riid, void **ppv)
    { *ppv = self; return S_OK; }
static ULONG   STDMETHODCALLTYPE CF_AddRef(CF *self)    { return 2; }
static ULONG   STDMETHODCALLTYPE CF_Release(CF *self)   { return 1; }

static HRESULT STDMETHODCALLTYPE CF_CreateInstance(CF *self, IUnknown *outer,
                                                   const IID *riid, void **ppv)
{
    StubObj *obj = make_stub();
    if (!obj) return E_OUTOFMEMORY;
    *ppv = obj;
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE CF_LockServer(CF *self, BOOL lock)
    { return S_OK; }

static void *cf_vtbl[] = {
    CF_QI, CF_AddRef, CF_Release, CF_CreateInstance, CF_LockServer
};
static CF g_factory = { cf_vtbl };

/* ------------------------------------------------------------------ */
/* DLL entry points                                                     */
/* ------------------------------------------------------------------ */

HRESULT WINAPI DllGetClassObject(const CLSID *rclsid, const IID *riid, void **ppv)
{
    /* Accept any CLSID — this DLL is only registered for one */
    (void)rclsid; (void)riid;
    *ppv = &g_factory;
    return S_OK;
}

HRESULT WINAPI DllRegisterServer(void)   { return S_OK; }
HRESULT WINAPI DllUnregisterServer(void) { return S_OK; }
HRESULT WINAPI DllCanUnloadNow(void)     { return S_FALSE; }

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID reserved)
{
    (void)hInst; (void)reserved;
    if (reason == DLL_PROCESS_ATTACH)
        init_vtbl();
    return TRUE;
}
