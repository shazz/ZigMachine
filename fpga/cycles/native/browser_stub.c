/* The wasm cart a native (KESTREL-only) disk carries for the browser (tools/native_cart.py):
 * the disk format wants a boot cart, and a browser that mounts the disk should say why
 * nothing runs instead of showing black. The board never runs it: ZWINDOW loads the disk's
 * CART.RV32 (the native cart). Built with zig cc as apps/c/build.sh builds a C cart. */
#define ROM(name) __attribute__((import_module("env"), import_name(name)))
ROM("guiOpenPlane") extern unsigned guiOpenPlane(unsigned plane, int w, int h);
ROM("romInstallPalettePlane") extern void romInstallPalettePlane(unsigned plane);
ROM("guiRect") extern void guiRect(unsigned h, int x, int y, int w, int hh, unsigned color);
ROM("guiText") extern void guiText(unsigned h, const char* p, unsigned len, int x, int y, unsigned ink,
                                   unsigned paper);

static unsigned gui;
static const char L1[] = "THIS DISK RUNS ON KESTREL ONLY";
static const char L2[] = "a native ZIGGY cart: no wasm inside";

__attribute__((export_name("boot"))) void boot(void) {
    gui = guiOpenPlane(0, 320, 200);
    if (gui) romInstallPalettePlane(0);
}

__attribute__((export_name("frame"))) void frame(float dt) {
    (void)dt;
    if (!gui) return;
    guiRect(gui, 0, 0, 320, 200, 0);
    guiText(gui, L1, sizeof L1 - 1, 40, 88, 1, 0);
    guiText(gui, L2, sizeof L2 - 1, 20, 104, 1, 0);
}

__attribute__((export_name("isPlaneEnabled"))) int isPlaneEnabled(int id) { return id == 0 && gui != 0; }
__attribute__((export_name("hblDispatch"))) void hblDispatch(unsigned a, unsigned b, unsigned c, unsigned d) {
    (void)a, (void)b, (void)c, (void)d;
}
__attribute__((export_name("skipBoot"))) void skipBoot(void) {}
