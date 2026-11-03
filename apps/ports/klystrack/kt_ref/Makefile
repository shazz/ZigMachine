# kt_ref: upstream klystron's cyd + music.c, native, as klystrack's WAV export renders a song
# (kt_ref.c). Needs apps/ports/fetch.sh (the pinned upstream) and SDL2's headers (SDL_RWops).
#
#   make -C apps/ports/klystrack/kt_ref          build/kt_ref
#   build/kt_ref ../data/STARPRT2.KT 20 --features
KL      := ../../upstream/klystrack/klystron/src
CFLAGS  := -O2 -I.. -g -DSTEREOOUTPUT -DNOSDL_MIXER -DLOWRESWAVETABLE -DUSESDL_RWOPS -I$(KL) -I$(KL)/snd \
	$(shell sdl2-config --cflags)
LIBS    := $(shell sdl2-config --libs) -lm

build/kt_ref: kt_ref.c ../kestrel_chorus.c $(wildcard $(KL)/snd/*.c)
	@mkdir -p build
	$(CC) $(CFLAGS) $^ -o $@ $(LIBS)

clean:
	rm -rf build
.PHONY: clean
