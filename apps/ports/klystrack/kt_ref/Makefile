# kt_ref: upstream klystron's cyd + music.c, native, as the klystrack cart plays a song (kt_ref.c).
# Needs apps/ports/fetch.sh (the pinned upstream) and SDL2's headers (SDL_RWops).
#
#   make -C apps/ports/klystrack/kt_ref          build/kt_ref
#   build/kt_ref ../data/STARPORT2.KT 20 --features
#   make -C apps/ports/klystrack/kt_ref tables    regenerate libs/zig/players/kt_tables_gen.zig
#
# One upstream source is patched (build/freqs.c, freqs.sed): get_freq interpolates a note in the top
# semitone (95.01..95.99) toward frequency_table[96], one past the table. What is there is whatever
# the linker put next: 384 in this build, 0 in the klystrack cart (docs/demo-klystrack.wasm's data).
# The patch reads 0, the cart's, so kt_ref (and the BARD player, kt_tables.zig getFreq) is defined there.
KL      := ../../upstream/klystrack/klystron/src
CFLAGS  := -O2 -I.. -g -DSTEREOOUTPUT -DNOSDL_MIXER -DLOWRESWAVETABLE -DUSESDL_RWOPS -I$(KL) -I$(KL)/snd \
	$(shell sdl2-config --cflags)
LIBS    := $(shell sdl2-config --libs) -lm
SND     := $(filter-out $(KL)/snd/freqs.c,$(wildcard $(KL)/snd/*.c))

build/freqs.c: $(KL)/snd/freqs.c freqs.sed
	@mkdir -p build
	sed -f freqs.sed $< >$@
	! cmp -s $< $@ || (echo "freqs.sed changed nothing"; rm $@; exit 1)

build/kt_ref: kt_ref.c ../kestrel_chorus.c build/freqs.c $(SND)
	$(CC) $(CFLAGS) $^ -o $@ $(LIBS)

# The constants upstream computes with libm, as Zig: libs/zig/players/kt_tables_gen.zig (kt_tables.c).
build/kt_tables: kt_tables.c build/freqs.c
	$(CC) $(CFLAGS) $^ -o $@ $(LIBS)
tables: build/kt_tables
	build/kt_tables >../../../../libs/zig/players/kt_tables_gen.zig

clean:
	rm -rf build
.PHONY: clean tables
