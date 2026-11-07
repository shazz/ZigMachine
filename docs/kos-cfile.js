// --------------------------------------------------------------------------
// KOS GEMDOS's writes to C: on the page and in node's harnesses (docs/KOS_GEMDOS.md §7): the host
// half of env.kosFileOp where C: is an image in memory. A cart never writes sectors: it hands the
// host a request (rom/kos/kfs_abi.zig: 12 words, then the path, a second path and the data, all in
// its own memory) and KFS (docs/kos-cfs.wasm, rom/kos/kfs*.zig) edits the image at the file level,
// as glass does on the board over Linux's FAT (fpga/glass/src/kos_file.zig). The native host runs
// the same wasm through wasm2c (fpga/host/kos_cfile.c), with the same bounds as here.
//
//   const op = ZMKosFile.make(() => memory.buffer, image, new WebAssembly.Module(kfsBytes));
//   env.kosFileOp = op;   // op.writes: the sectors written so far
// --------------------------------------------------------------------------
globalThis.ZMKosFile = (function () {
    const REQ_WORDS = 12, DATA_MAX = 32768, PATH_MAX = 127;
    const ERANGE = -64, EDRIVE = -46;

    // The request's bytes, bounded, copied into KFS's buffer: false if any lies outside the cart's memory.
    function copyIn(cart, k, at, w) {
        const [, , , , , len, data, path, plen, path2, p2len] = w;
        if (plen > PATH_MAX || p2len > PATH_MAX || len > DATA_MAX) return false;
        for (const [a, n] of [[path, plen], [path2, p2len], [data, len]]) if (a + n > cart.byteLength) return false;
        const dst = new Uint8Array(k.buffer);
        dst.set(new Uint8Array(cart, path, plen), at);
        dst.set(new Uint8Array(cart, path2, p2len), at + 128);
        dst.set(new Uint8Array(cart, data, len), at + 256);
        return true;
    }

    function make(cartBuffer, img, module) {
        let kmem = null;
        const env = {
            kfsRead(sector, dst) {
                const at = (sector >>> 0) * 512;
                if (!img || at + 512 > img.length) return 0;
                new Uint8Array(kmem.buffer, dst >>> 0, 512).set(img.subarray(at, at + 512));
                return 1;
            },
            kfsWrite(sector, src) {
                const at = (sector >>> 0) * 512;
                if (!img || at + 512 > img.length) return 0;
                img.set(new Uint8Array(kmem.buffer, src >>> 0, 512), at);
                op.writes++;
                return 1;
            },
        };
        const kfs = new WebAssembly.Instance(module, { env }).exports;
        kmem = kfs.memory;
        function op(req) {
            const cart = cartBuffer();
            req >>>= 0;
            if (req % 4 || req + REQ_WORDS * 4 > cart.byteLength) return ERANGE;
            const w = new Uint32Array(cart, req, REQ_WORDS);
            if (!img) return EDRIVE;
            if (w[0] === 0) { w[11] = kfs.kfsGen(); return kfs.kfsGen() & 0x7fffffff; } // the generation
            if (!copyIn(cart, kfs.memory, kfs.kfsBuf(), w)) return ERANGE;
            const r = kfs.kfsServe(w[0], w[1], w[2], w[3], w[4], w[8], w[10], w[5]);
            w[11] = kfs.kfsGen();
            return r;
        }
        op.writes = 0;
        op.stamp = (time, date) => kfs.kfsStamp(time, date);
        return op;
    }

    return { make };
})();
