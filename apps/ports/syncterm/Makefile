# SyncTERM 1.9 (GPLv2, Stephen Hurd / Synchronet) for the ZigMachine / KESTREL, as a C cart: the BBS terminal
# in the desk mode (640x480, 80x25 cells of 8x16), its network MOCKED by an in-cart fake BBS (kestrel_fakebbs.c)
# behind a BSD sockets shim (kestrel_sock.c). Same layout as apps/ports/grafx2: upstream untouched in
# ../upstream/sbbs (apps/ports/fetch.sh), its files mirrored into build/gen/<dir>/ and patched there by
# patches/<file>.sed (a patch must change its file), the shared SDL2 layer in ../kestrel_sdl2.
#   make objs | make link | make install | make clean
WABT   ?= ../../../fpga/.tools/wabt/bin
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
UPSTREAM ?= ../upstream
UP     := $(UPSTREAM)/sbbs/src
OUT    := build
GEN    := $(OUT)/gen
KSDL   := ../kestrel_sdl2/src
KINC   := ../kestrel_sdl2/include
HSH    := hash
DIRS   := syncterm sbbs3 uifc conio xpdev encode comio $(HSH)
# Upstream's unix MT build (build/Common.gmake, PREFER_POLL as on Linux), without cryptlib (no SSH / TLS), OOII, JPEG XL, X11, SDL and
# curses; ciolib's output is ours (kestrel_cio.c, in place of its retro backend: patches/ciolib.c.sed).
DEFS   := -D__unix__ -D__KESTREL__ -D_THREAD_SAFE -D_REENTRANT -DUSE_XP_SEMAPHORES -DLINK_LIST_THREADSAFE \
          -DWITHOUT_CRYPTLIB -DWITHOUT_OOII -DTELNET_NO_DLL -DHAS_INTTYPES_H -D_DEFAULT_SOURCE -D_BSD_SOURCE \
          -D_GNU_SOURCE -DPREFIX=\"/\" -DSYSTEM_LIST_DIR=\"/\" -DNO_X -DDISABLE_X11=1 -DHAVE_VASPRINTF \
          -DWITH_RETRO -DPREFER_POLL -DNDEBUG -D__wasilibc_use_wasip2 -DUNAME_ARCHITECTURE_DESC=\"wasm32\"
INCS   := -I. -Iinclude -I$(KINC) $(addprefix -I$(GEN)/,$(DIRS))
CFLAGS := $(EXTRA) -target wasm32-wasi -O2 -g0 -mbulk-memory -std=gnu11 $(INCS) -include kestrel_port.h $(DEFS) -w
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=131072 -Wl,--strip-debug

# syncterm/objects.mk without filepick (uifc's), webget (cryptlib), modem / comio / pty (no serial, no shell);
# uifc/objects.mk's MT_OBJS; conio/objects.mk without syncicon64 (the window icon); xpdev's MTOBJS without
# xpmap (mmap); encode's and hash's objects.mk.
UP_SRC := syncterm/bbslist syncterm/uifcinit syncterm/fonts syncterm/rip_icons syncterm/ripper syncterm/rlogin \
  syncterm/telnet_io syncterm/conn_telnet syncterm/conn syncterm/term syncterm/window syncterm/menu \
  syncterm/syncterm sbbs3/telnet sbbs3/zmodem sbbs3/xmodem uifc/uifc32 uifc/uifcx uifc/uifc_ini uifc/filepick \
  conio/ciolib conio/cterm conio/vidmodes conio/allfonts conio/mouse conio/utf8_codepages conio/ansi_cio \
  xpdev/conwrap xpdev/dat_file xpdev/datewrap xpdev/dirwrap xpdev/filewrap xpdev/genwrap xpdev/ini_file \
  xpdev/link_list xpdev/msg_queue xpdev/multisock xpdev/named_str_list xpdev/os_info xpdev/rwlockwrap \
  xpdev/semwrap xpdev/netwrap xpdev/sockwrap xpdev/semfile xpdev/str_list xpdev/stbuf xpdev/strwrap \
  xpdev/threadwrap xpdev/unicode xpdev/xp_dl xpdev/xpbeep xpdev/xpdatetime xpdev/xpprintf xpdev/xpsem \
  xpdev/xpevent encode/utf8 encode/uucode encode/yenc encode/lzh encode/hex encode/base64 \
  $(HSH)/crc16 $(HSH)/crc32 $(HSH)/md5 $(HSH)/sha1
UP_HDR := $(patsubst $(UP)/%,%,$(foreach d,$(DIRS),$(wildcard $(UP)/$(d)/*.h)))
GENALL := $(addprefix $(GEN)/,$(UP_HDR) $(addsuffix .c,$(UP_SRC)))
# The shared layer: the core (heap, WASI over the floppy, quit) and the opt-in fibers. Not its input.c:
# kestrel_keys.c maps the keys to ciolib codes directly (SyncTERM has no SDL path here).
KSDL_OBJ := kestrel_heap kestrel_wasi kestrel_quit opt/kestrel_fiber opt/kestrel_pthread
OBJS   := $(addprefix $(OUT)/up/,$(addsuffix .o,$(UP_SRC))) $(patsubst %.c,$(OUT)/%.o,$(wildcard kestrel_*.c)) \
          $(addprefix $(OUT)/ksdl/,$(addsuffix .o,$(KSDL_OBJ)))

.PHONY: objs link dbg clean install
.SECONDARY:
objs: $(OBJS)

$(GEN)/%: $(UP)/% $(wildcard patches/*.sed)
	@mkdir -p $(dir $@)
	@if [ -f patches/$(notdir $*).sed ]; then sed -f patches/$(notdir $*).sed $< > $@; \
	  ! cmp -s $< $@ || { echo "patch $* changed nothing"; rm $@; exit 1; }; else cp $< $@; fi
$(OUT)/up/%.o: $(GEN)/%.c $(GENALL) kestrel_port.h $(wildcard include/*.h $(KINC)/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(wildcard $(KINC)/*.h $(KINC)/SDL2/*) kestrel_port.h kestrel_net.h
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -DKESTREL_NET_NO_RENAME -c $< -o $@
$(OUT)/kestrel_%.o: kestrel_%.c $(GENALL) $(wildcard *.h include/*.h $(KINC)/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@

# Asyncify: SyncTERM is threaded; its threads are fibers (../kestrel_sdl2/src/opt/kestrel_fiber.c).
WASM_OPT := node $(UPSTREAM)/binaryen/bin/wasm-opt
link: $(OUT)/demo-syncterm.wasm
$(OUT)/demo-syncterm.raw.wasm: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(LDFLAGS) $^ -o $@
$(OUT)/demo-syncterm.wasm: $(OUT)/demo-syncterm.raw.wasm
	$(WASM_OPT) $< --enable-bulk-memory --enable-sign-ext --enable-mutable-globals --enable-nontrapping-float-to-int \
	  --asyncify -O2 -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c

# The same cart with its function names, for a readable trap (node run.mjs with CART=build/dbg.wasm).
dbg: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(filter-out -Wl$(comma)--strip-debug,$(LDFLAGS)) $^ -o $(OUT)/dbg.raw.wasm
	$(WASM_OPT) $(OUT)/dbg.raw.wasm --enable-bulk-memory --enable-sign-ext --enable-mutable-globals \
	  --enable-nontrapping-float-to-int --asyncify -O2 -g -o $(OUT)/dbg.wasm
comma := ,

clean:
	rm -rf $(OUT)

# The shipped cart: docs/demo-syncterm.wasm, committed prebuilt (build.sh does not rebuild the C ports).
# tools/mkdisks.sh packs docs/demo-syncterm.zmd from it plus data/ (the fake BBS's screen, SyncTERM's ini).
install: $(OUT)/demo-syncterm.wasm
	cp $< ../../../docs/demo-syncterm.wasm
	cd ../../.. && tools/mkdisks.sh
