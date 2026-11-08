# SID-Wizard 1.97 (Hermit, WTF licence) for the ZigMachine / KESTREL, as a C cart: the PC version's design (its
# native C64 program on its own libcRSID C64), with a host of ours (kestrel_sw*.c) for the machine. README.md.
# Upstream's files are vendored in upstream/ (unchanged; README.md "Provenance"): every one is mirrored into
# build/gen/ and patched there by patches/<path with / as __>.sed when one exists (a patch must change its file).
#   make link | make names | make install | make clean | make cputest OUT=build/cputest (apps/sidwizard_cpu_check.mjs)
ZIG    ?= $(HOME)/.local/zig/0.16.0/zig
WABT   ?= ../../../fpga/.tools/wabt/bin
OUT    := build
GEN    := $(OUT)/gen
UP     := upstream
KSDL   := ../kestrel_sdl2/src
KINC   := ../kestrel_sdl2/include
# One unity build (kestrel_sw.c includes upstream's .c files, as upstream's SIDwizard.c does). _LINUX: upstream's
# X11 scancode table for the positional keys. UNCOMPRESSED_NATIVES: the native program is unpacked at build time.
DEFS   := -DSIDAMOUNT=1 -D_LINUX=1 -DENABLED_SDL=1 -DUNCOMPRESSED_NATIVES=1 -DOSCILLOSCOPE_SHOWS_ALL_CHANNELS=1 \
          -DVERSION=\"1.9\" -DSUBVERSION=\"7\" -DKESTREL_CDRIVE -D__KESTREL__
OPT    ?= -Os
CFLAGS := $(EXTRA) -target wasm32-wasi $(OPT) -g0 -mbulk-memory -std=gnu99 -Iinclude -I$(GEN) -I. -I$(KINC) $(DEFS) \
          -Wno-unused-parameter -Wno-pointer-sign -Wno-deprecated-non-prototype -Wno-unused-variable \
          -Wno-unused-function -Wno-comment -Wno-char-subscripts -Wno-unused-but-set-variable \
          -Wno-unused-value -Wno-parentheses -Wno-dangling-else -Wno-misleading-indentation -Wno-static-in-inline
MEM := 8388608
LDFLAGS := -Wl,--no-entry -Wl,--import-memory -Wl,--initial-memory=$(MEM) -Wl,--max-memory=$(MEM) \
           -Wl,--global-base=1048576 -Wl,-z,stack-size=131072 -Wl,--strip-debug

UP_FILES := $(patsubst $(UP)/%,%,$(shell find $(UP) -type f))
GENALL   := $(addprefix $(GEN)/,$(UP_FILES)) $(GEN)/resources/SID-Wizard.h $(GEN)/resources/KERNAL.h \
            $(GEN)/resources/chargen.h $(GEN)/libcRSID/C64/SID_FilterCurves.h
CDRIVE   := $(OUT)/ksdl/opt/kestrel_wasi_c.o $(OUT)/ksdl/opt/kestrel_wasi_cdir.o $(OUT)/ksdl/opt/kestrel_wasi_cfile.o $(OUT)/gemdos.o
KSDL_O   := $(addprefix $(OUT)/ksdl/,kestrel_wasi.o kestrel_heap.o kestrel_quit.o kestrel_audio.o)
OBJS     := $(OUT)/kestrel_sw.o $(OUT)/kestrel_sw_host.o $(KSDL_O) $(CDRIVE)

.PHONY: link names install clean data cputest
.SECONDARY:
link: $(OUT)/demo-sidwizard.wasm

$(GEN)/%: $(UP)/% $(wildcard patches/*.sed)
	@mkdir -p $(dir $@)
	@p=patches/$(subst /,__,$*).sed; if [ -f $$p ]; then sed -f $$p $< > $@; \
	  ! cmp -s $< $@ || { echo "patch $* changed nothing"; rm $@; exit 1; }; else cp $< $@; fi
# The light engine's filter table for 22.05 kHz (upstream's is for 44.1 kHz): the one libs/c/crsid made with
# cRSID's own curvegen for BARD's .sid player (libs/c/crsid/README.md); the two libraries' tables are the same file.
$(GEN)/libcRSID/C64/SID_FilterCurves.h: ../../../libs/c/crsid/patches/SID_FilterCurves.h $(UP)/libcRSID/C64/SID_FilterCurves.h
	@mkdir -p $(dir $@)
	cmp -s ../../../libs/c/crsid/upstream/C64/SID_FilterCurves.h $(UP)/libcRSID/C64/SID_FilterCurves.h || { echo "upstream filter table differs from libs/c/crsid's"; exit 1; }
	cp $< $@
# The resources/*.h upstream's Makefile makes (bin2array; not in the source archive)
$(OUT)/unpack: tools/unpack.c $(UP)/native/sources/tools/decompressor.c
	@mkdir -p $(OUT)
	$(ZIG) cc -O1 -w -o $@ $<
$(OUT)/SIDWIZ.PRG: $(UP)/resources/SID-Wizard.cmp $(OUT)/unpack
	$(OUT)/unpack $< $@
$(GEN)/resources/SID-Wizard.h: $(OUT)/SIDWIZ.PRG tools/bin2h.py
	@mkdir -p $(dir $@)
	python3 tools/bin2h.py $< $@ SID_Wizard --nul
$(GEN)/resources/KERNAL.h: $(UP)/host/KERNAL.bin tools/bin2h.py
	@mkdir -p $(dir $@)
	python3 tools/bin2h.py $< $@ KERNAL
$(GEN)/resources/chargen.h: $(UP)/resources/chargen tools/bin2h.py
	@mkdir -p $(dir $@)
	python3 tools/bin2h.py $< $@ chargen --nul

$(OUT)/kestrel_sw.o: kestrel_sw.c $(wildcard kestrel_sw*.c kestrel_sw*.h include/*.h) $(GENALL)
	@mkdir -p $(OUT)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/kestrel_sw_host.o: kestrel_sw_host.c
	@mkdir -p $(OUT)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/opt/%.o: $(KSDL)/opt/%.c $(KSDL)/opt/kestrel_wasi_c.h $(wildcard $(KINC)/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
$(OUT)/ksdl/%.o: $(KSDL)/%.c $(wildcard $(KINC)/*.h)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) -c $< -o $@
# KOS GEMDOS (C: as "/C"), built from the ROM tree's Zig, as GrafX2's
GEMDOS := ../../../rom/kos
$(OUT)/gemdos.o: $(wildcard $(GEMDOS)/gemdos*.zig $(GEMDOS)/fat*.zig)
	@mkdir -p $(dir $@)
	$(ZIG) build-obj -target wasm32-wasi -OReleaseSmall -fno-stack-check $(GEMDOS)/gemdos_c.zig -femit-bin=$@

$(OUT)/demo-sidwizard.wasm: $(OBJS)
	$(ZIG) cc $(CFLAGS) $(LDFLAGS) $^ -o $@
	@echo "imports (must all be env.*):"; $(WABT)/wasm-objdump -x -j Import $@ | grep -o '<- [^ ]*' | sort | uniq -c
# The same cart with its function names, for apps/frame_cost.mjs and tools/perf_audit.sh
names: $(OUT)/names/demo-sidwizard.wasm
$(OUT)/names/demo-sidwizard.wasm: $(OBJS)
	@mkdir -p $(dir $@)
	$(ZIG) cc $(CFLAGS) $(filter-out -Wl$(comma)--strip-debug,$(LDFLAGS)) $^ -o $@
comma := ,
# The cart whose boot first runs kestrel_sw_cpu_test.c (the fast 6502 against libcRSID's): apps/sidwizard_cpu_check.mjs.
# Give it its own OUT; CPUTEST_EXTRA=-DSW_CPU_BREAK plants the check's --break.
cputest:
	$(MAKE) link EXTRA="-DSW_CPU_TEST $(CPUTEST_EXTRA)"

# The floppy's files (data/, committed, packed by tools/mkdisks.sh): Hermit's example song, renamed to 8.3.
data:
	@mkdir -p data
	cp $(UP)/native/examples/flashitback.swm data/FLASHBAK.SWM

# The shipped cart: docs/demo-sidwizard.wasm, committed prebuilt (build.sh does not rebuild the C ports).
install: $(OUT)/demo-sidwizard.wasm
	cp $< ../../../docs/demo-sidwizard.wasm
	cd ../../.. && tools/mkdisks.sh

clean:
	rm -rf $(OUT)
