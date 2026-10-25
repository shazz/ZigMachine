// --------------------------------------------------------------------------
// KOS, the KESTREL Operating System: the browser's power-on (docs/ZIGTOS_BOOT.md, where
// "ZigTOS" is KOS). docs/sealed-loader.js's boot() uses it when the page powers on with a
// disk in drive A (?disk=X.zmd, or a TV channel's disk) or none (?disk=none):
//
//   1. kosSetBoot(cold, what will boot, drive A full?, hwRamFree), hwInit;
//   2. the POST: rom.wasm draws it on plane 0 (rom/kos/kos.zig) for ?post=N frames
//      (default 180; ?post=0: none), and any key skips the rest;
//   3. request KOS_BOOT_DRIVE: the loader's swapCart boots drive A: the disk's boot sector
//      or cart, or the desktop (demo-gem.wasm) over a data disk or an empty drive.
//
// The same steps run in node (apps/scene_hash_kos.mjs), the native host (fpga/host/kos_host.c)
// and the board firmware (fpga/cycles/bkos.c), which agree frame for frame.
// --------------------------------------------------------------------------
globalThis.ZMKos = (function () {
    const BOOT_COLD = 0, DEV_DESKTOP = 0, DEV_DRIVE_A = 1;
    const POST_FRAMES = 180; // rom/kos/kos.zig POST_FRAMES
    const BOOT_DRIVE = 5;    // the POST's request: boot drive A (sealed-loader.js swapCart)

    // What drive A will boot: its cart (a bootable disk, or one whose executable boot sector
    // chainloads a cart) or the desktop (a data disk, a sector that hands over to the OS, none).
    function bootsCart(drive, mounted) {
        if (!drive || !drive.bootable) return false;
        return !(drive.v2 && mounted && mounted.chainCart && mounted.chainCart.len === 0);
    }

    // The POST as the running "cart" until it ends: plane 0 only, no HBL handler, no exports
    // beyond what the loader's frame and input handlers call.
    function postCart(rom, frames) {
        let done = false;
        rom.kosPostStart(frames);
        const skip = () => { done = true; };
        return {
            frame() { if (!done) done = rom.kosPostFrame() !== 0; },
            isPlaneEnabled: (p) => p === 0,
            pollCartRequest: () => (done ? BOOT_DRIVE : 0),
            hblDispatch() {},
            ownsKeyboard: () => 0,
            key: skip, // a key held at power-on skips the POST, as on the ST
            input: skip,
        };
    }

    // Stage 1: the reset's system variables, then the hardware's.
    function power(rom, machine, drive, mounted) {
        rom.kosSetBoot(BOOT_COLD, bootsCart(drive, mounted) ? DEV_DRIVE_A : DEV_DESKTOP, drive ? 1 : 0, machine.hwRamFree());
        machine.hwInit();
    }

    // ?post=N: the POST's frames (0 = none); anything else is the default.
    function postFrames(params) {
        const n = Number(params.get("post"));
        return params.has("post") && Number.isInteger(n) && n >= 0 ? n : POST_FRAMES;
    }

    return { BOOT_DRIVE, bootsCart, postCart, power, postFrames };
})();
