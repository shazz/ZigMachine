# Converting a browser cart to a board cart

The browser runs a cart as `docs/demo-<tag>.wasm` inside its disk, `docs/demo-<tag>.zmd`.
The board (KESTREL) doesn't run wasm. Converting a cart works like this:

1. wasm2c translates the cart to C.
2. The C is compiled for the cart CPU (ZIGGY, rv32).
3. It is linked with the machine, the ROM and the board firmware into `fw.bin`.
4. `fw.bin` is packed into a copy of the cart's disk as one more FAT file. That copy is called a
   "fat disk". The browser ignores the extra file; ZWINDOW on the board boots it.

No cart needs changing to be converted. The checks at the end are what tell you whether it then
*plays* right on the board.

## Quick start

```bash
cd fpga
tools/board_carts.sh rick_dangerous joust                     # build only
tools/board_carts.sh --stage /dev/shm/sd \
    --bit build/board_v6fpu/gateware/platform_z7.bit \
    rick_dangerous joust                                       # build + stage the SD tree
```

The script prints one line per cart, `<tag> ok <bytes>` or `<tag> FAIL rc=<n> (<log>)`. Each cart's
log goes to `build/board_carts/<tag>.log`. With `--stage`, it also writes:

- `/dev/shm/sd/`: the SD card tree, with the carts in `zigmachine/`. Read `MANIFEST.txt` in it.
- `/dev/shm/sd.md5`: the md5 of every file under `zigmachine/`, for whoever uploads the card.

It stages **only the carts you named that built OK**. Copy `zigmachine/demo-<tag>.zmd`, and
`zigmachine/progs/` when there is one, onto the card. Copy `shelf.txt` only if you want the OSD
to forget the other carts' titles: the staged one lists only these carts.

Builds take `prototypes/_gate_logs/build.lock` one cart at a time, so the script waits behind any
gate that's running. The first cart in a tree takes about 10 minutes (the hp_sim SoC and the common
objects); after that it's a few minutes per cart.

## Which variant

The board image has to match the bitstream you boot:

| Variable | Default | Meaning |
|---|---|---|
| `FPU=1` | 1 | hardware float, for an FPU bitstream (v6); `FPU=0` builds soft float |
| `AUDIO=snd` | snd | music on BARD, the sound CPU, for a `--sound-cpu` bitstream; `AUDIO=1` puts it on the cart CPU, `AUDIO=0` means no music |

The images go to `build/hcycles/board[_snd][_fpu]/<tag>/fw.bin`. The blitter is always the
hardware one, so the bitstream must be built with `--blit`.

## One-time setup (a fresh worktree)

1. **Submodules.** A fresh worktree has `fpga/third_party/*` empty, and the main checkout's clones
   are shallow, so they can't be a `--reference`. Copy each one from the main checkout, offline:
   ```bash
   for p in $(git config -f .gitmodules --get-regexp path | awk '{print $2}'); do
     sha=$(git ls-tree HEAD $p | awk '{print $3}')
     git -C <main checkout>/$p archive $sha | tar -x -C $p
   done
   ```
2. **Tools.** `ln -s <main checkout>/fpga/.tools fpga/.tools` (wasm2c and wabt).
3. **Netlists.** Copy `fpga/build/vexgen/` from a checkout that has them.
4. **The CSR map of the bitstream you boot**, as `fpga/build/soc_z7/csr.json`. Copy the `csr.json`
   that sits next to that bitstream's build, e.g. `build/board_v6fpu/csr.json`. An image linked
   for another map is refused (`tools/cycles_csr.py --hp-check`). Don't borrow another branch's
   elaboration: it can differ by one region.

The script stops early with a message if steps 2 or 4 are missing.

## The checks, per cart

Do them in this order. The early ones are free.

### 1. It built

- `ok` means it linked and is under **12 MiB**: the make rule refuses anything bigger, because with
  BARD the cart's RAM ends at 12 MiB.
- A link error naming a `w2c_env_*` or `w2c_machine_*` symbol means the cart imports something the
  board firmware doesn't have. That's a firmware job, not a cart one.

### 2. The browser harness still passes

If the cart changed: `flock prototypes/_gate_logs/build.lock ./build.sh --only <tag>`. Carts with a
headless harness (`apps/<tag>_headless.mjs`) are checked frame by frame against their reference.

### 3. It runs in the board-SoC sim

The board SoC in Verilator, running the same image built for the sim. Its frame hashes are compared
with the browser (`apps/scene_hash.mjs`) and the native host:

```bash
flock prototypes/_gate_logs/build.lock make -C fpga soc-hp-fpu          # once, a Verilator build
flock prototypes/_gate_logs/sim-a.lock \
  uv run --project fpga python fpga/tools/hp_sim_run.py <tag> --fpu --frames 60 --run-id <me>
```

Look for `hp <tag> rc=0 ok`: it ran to the end with no video underrun, and the hashes equal both
references. In the uart log, `fpga/build/hcycles/uart/<tag>_fpu.txt`, each `ZM AF <frame> <cart>
<audio>` line gives the cart's cycles for that frame (`cycles/bmain.c`), so 100,000,000 / cart
cycles = the fps the cart reaches. Run at most two big sims at a time, and never a sim beside Vivado.

### 4. What the board does differently from the browser

Check these before promising a cart:

- **The joystick.** The board's stick (glass `REG_JOY`) reaches the cart as `input(dir)` /
  `inputRelease(dir)`: 0 up, 1 down, 2 left, 3 right, **5 fire**. The browser never sends
  direction 5 to a cart that owns the keyboard, so a game can work in the browser and still drop
  the fire button on the board. Rick Dangerous and Joust did, until their `5 => FIRE`. For a game,
  grep its `fn input` for direction 5, and make sure fire combines with the held directions (it's
  one more bit of the same stick byte).
- **The keyboard and mouse** arrive the same way as in the browser (`cycles/binput.c`).
- **Music** runs on BARD: SNDH (68000), SAP (6502 + POKEY) and the native players. BARD is slow.
  Check its load with `make snd-bench`: the budget is 1.67 Mc a frame, and wow_scroller already
  takes 130 %.
- **Speed.** Per-frame float crawls on a soft-float image (`FPU=0`): see "Float math" in
  CLAUDE.md. Measure the fps in step 3 before blaming the board.
- **Disk streaming** (`zg.disk`) reads from the shelf disk ZWINDOW puts in DDR.
- **Data disks.** A disk that isn't bootable, such as ST Replay's, boots GEM. Each program on it
  gets its own fat disk in `zigmachine/progs/demo-<tag>/<NAME>.zmd`, which `glass_sd.py` builds.
  Copy that folder too: a stale one left on the card boots the old firmware, and the cart comes
  back **CartSilent**.

### 5. On the board

Upload, boot, and then check:
- the picture;
- the music;
- the stick, including fire combined with each direction;
- the keyboard;
- Escape back to the menu;
- the OSD title.

## Keeping a cart on the shelf

`glass_sd.py` stages any `fw.bin` it's given, so a cart can be tried out without being listed. To
keep it on the card, add the tag to `SHELF` in `tools/glass_shelf.py`; `make board-shelf` and
`glass_sd.py --shelf` follow that list. The OSD text comes from `tools/shelf_meta.py`, which reads
`apps/zig/scenes/catalog.zig`, the comment in `build.zig`'s cart matrix, and the scene's header.
Fix a missing year or group there, then check with `uv run python tools/shelf_meta.py --check`.

## Smaller carts (#127)

Once `feat/cart-system-split` lands, the card carries one system image (`system.rv32`: firmware,
machine, ROM and BARD) and each cart only its own code, about 15 KB instead of 260 KB packed. Its
build is:
- `make board-split` for the system image;
- `make split-cart CART=<tag>` for each cart;
- `glass_sd.py --system build/hcycles/split/board_snd_fpu/sys.bin --fw-dir build/hcycles/split/carts_fpu`
  to stage.

It needs its own `glass` ARM binary (`make glass`). The checks above are the same.
