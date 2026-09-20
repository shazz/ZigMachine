// --------------------------------------------------------------------------
// Run your own cart: a visitor picks (or drops) a .wasm cart or a .zmd disk and
// the machine boots it, entirely in the browser. The file is read with
// File.arrayBuffer() and never leaves the device.
//
// A classic script loaded AFTER sealed-loader.js: it shares that script's
// top-level state (demo, machine, swapping, mountedDisk, currentTag...) and
// boots through the same instantiateCart/mountDiskBytes as a channel does, so a
// packed cart is unpacked by the ROM and an uploaded disk streams its files
// through the same drive (diskReadBlock) as a disk fetched from a URL.
// --------------------------------------------------------------------------
const UPLOAD_EXPORTS = ["boot", "frame", "isPlaneEnabled"]; // what the render loop calls

// Checks that touch nothing: if any fails, the running machine keeps going.
// Returns { kind, buf } ready to start, or { error } to show the visitor.
async function prepareUpload(file) {
    const Z = globalThis.ZMDisk;
    if (!Z) throw new Error("the disk module (zmdisk.js) did not load");
    if (file.size > Z.DISK_MAX_BYTES)
        return { error: `Too big: ${(file.size / 1048576).toFixed(1)} MB. A disk can be at most ` +
                        `${Z.DISK_MAX_BYTES / 1048576} MB, a cart ${Z.CART_MAX_BYTES / 1048576} MB.` };
    const buf = new Uint8Array(await file.arrayBuffer());
    const c = Z.classifyUpload(buf);
    if (c.error) return c;
    if (c.kind === "wasm") {
        if (!WebAssembly.validate(buf)) return { error: "This .wasm is not a valid WebAssembly module." };
        const names = WebAssembly.Module.exports(await WebAssembly.compile(buf)).map((e) => e.name);
        const missing = UPLOAD_EXPORTS.filter((n) => !names.includes(n));
        if (missing.length) return { error: `Not a ZigMachine cart: it does not export ${missing.join("(), ")}().` };
        const ram = globalThis.ZMRam && globalThis.ZMRam.cartRam(buf);
        if (ram && ram.over) return { error: "This cart's data and stack overrun the 2 MB cart window." };
    }
    if (c.kind === "disk") Z.parseDisk(buf, file.name); // a corrupt disk throws here, before anything is mounted
    return { kind: c.kind, buf };
}

// Start a prepared file. A disk mirrors swapCart req 1: bootable -> its cart,
// data disk -> GEM with the disk mounted so the FLOPPY window opens its app.
async function startUpload(p, name) {
    let bytes = p.buf.buffer, bootable = true;
    if (p.kind === "disk") {
        ({ bootable, cart: bytes } = mountDiskBytes(p.buf, name));
        if (!bootable) bytes = await fetch("demo-gem.wasm" + BUST).then((r) => r.arrayBuffer());
    } else {
        mountedDisk = null; // a bare cart: no disk in the drive
    }
    const next = (await instantiateCart(bytes, name)).instance.exports;
    const missing = UPLOAD_EXPORTS.filter((n) => typeof next[n] !== "function");
    if (missing.length) {
        alert(`ZigMachine: ${name} is not a ZigMachine cart (no ${missing.join("(), ")}()).`);
        throw new Error(`${name} does not export ${missing.join(", ")}`);
    }
    demo = next;
    machine.hwInit();
    demo.boot();
    if (demo.skipBoot) demo.skipBoot();
    if (bootable && window.armCartOsd) window.armCartOsd(name); // name card: the file's own name
    currentTag = null;    // not a channel: + / - start again from the first one
    diskApp = !bootable;  // data disk -> GEM's FLOPPY opens its app
    diskDirSet = false;   // hand GEM the new disk's FAT listing
}

async function bootUserFile(file) {
    if (!file) return;
    if (!demo || !machine) { alert("ZigMachine is still starting, try again in a moment."); return; }
    if (swapping) { alert("ZigMachine is busy loading, try again in a moment."); return; }
    swapping = true;
    const prevDisk = mountedDisk, prevTag = currentTag;
    let started = false; // past this point the cart window may hold part of the new cart
    try {
        const p = await prepareUpload(file);
        if (p.error) { alert(`ZigMachine: cannot run ${file.name}.\n\n${p.error}`); return; }
        started = true;
        await startUpload(p, file.name);
        console.log(`Running your ${p.kind === "disk" ? "disk" : "cart"}: ${file.name}`);
        started = false; // success
    } catch (e) {
        console.error("upload failed:", e);
        // instantiateCart already alerted for a failure past this point.
        if (!started) alert(`ZigMachine: cannot run ${file.name}.\n\n${e.message}`);
    } finally {
        swapping = false;
    }
    // A failed start may have unpacked over the running cart's RAM (the ROM
    // depacks straight into the cart window): do not trust that cart, tune back
    // in to where the visitor was, with the disk they had.
    if (started) {
        mountedDisk = prevDisk;
        await swapCart(prevTag ? 1 : -1, prevTag || undefined);
    }
}

function pickUserFile() {
    const input = document.getElementById("upload_input");
    if (input) input.click();
}

// The file picker and drag & drop onto the monitor.
(function () {
    const input = document.getElementById("upload_input");
    if (!input) return;
    // Phone pickers filter by file types they know, and .zmd is not one: an
    // accept list there greys out the very files we want. The content is
    // sniffed anyway, so only a desktop (fine pointer) keeps the filter.
    if (!(window.matchMedia && window.matchMedia("(pointer: fine)").matches)) input.removeAttribute("accept");
    input.addEventListener("change", function () {
        const f = input.files && input.files[0];
        bootUserFile(f).finally(function () { input.value = ""; }); // the same file can be picked again
    });
    const stage = document.querySelector(".stage");
    const hasFiles = (e) => !!(e.dataTransfer && Array.from(e.dataTransfer.types || []).includes("Files"));
    // A file dropped anywhere else must not navigate the page away to it.
    window.addEventListener("dragover", function (e) { if (hasFiles(e)) e.preventDefault(); });
    window.addEventListener("drop", function (e) { if (hasFiles(e)) e.preventDefault(); });
    if (!stage) return;
    let depth = 0; // dragenter/leave fire for every child crossed
    const disarm = () => { depth = 0; stage.classList.remove("drop-armed"); };
    stage.addEventListener("dragenter", function (e) {
        if (!hasFiles(e)) return;
        e.preventDefault();
        depth++;
        stage.classList.add("drop-armed");
    });
    stage.addEventListener("dragover", function (e) {
        if (!hasFiles(e)) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
    });
    stage.addEventListener("dragleave", function () { if (--depth <= 0) disarm(); });
    stage.addEventListener("drop", function (e) {
        if (!hasFiles(e)) return;
        e.preventDefault();
        e.stopPropagation();
        disarm();
        bootUserFile(e.dataTransfer.files[0]);
    });
})();
