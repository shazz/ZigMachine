# The machine's audio side (host/haudio.h, docs/FPGA_AUDIO.md "The SoC"): the
# open players (demo-audio.wasm, the SNDH player on Musashi) through wasm2c, for
# the native host (the oracle, with the machine's own chips) and for the board
# firmware (the audio core's write queue, cycles/baudio.c). Included by
# fpga/Makefile before board.mk, whose firmware links the AUD_* objects.
#
#   make host-audio CART=tutorial   build/host/<cart>/host_audio: the native host + audio
#   ZM_AUDIO_LOG=/dev/shm/a build/host/tutorial/host_audio tutorial 120 60   -> a.w, a.pcm
#
# Both audio modules import their memory and the chip calls from `env`, as the
# cart does; tools/wasm_env_rename.py moves them to `aud` first, so the two
# memories stay apart (the players' 3 MiB is not the cart's 7 MiB).
AUD_WASM_audio := $(ROOT)/docs/demo-audio.wasm
AUD_WASM_maud  := $(ROOT)/docs/machine-audio.wasm
AUD_SRC        := host/audio.c host/audio_bridge.c host/audio_imports.c host/audio_pcm.c
AUD_HDRS       := host/haudio.h host/audio_regs.h host/audio_queue.h host/host.h host/hstream.h

$(HOST)/common/%.aud.wasm: tools/wasm_env_rename.py tools/wasm_info.py
	@mkdir -p $(@D)
	cd tools && uv run python wasm_env_rename.py $(AUD_WASM_$*) aud $(CURDIR)/$@
# The players' wasm is a prerequisite: an edited player must reach every native model built from it.
$(HOST)/common/audio.aud.wasm: $(AUD_WASM_audio)
$(HOST)/common/maud.aud.wasm: $(AUD_WASM_maud)
$(HOST)/common/aplayer.c: $(HOST)/common/audio.aud.wasm
	wasm2c $< -n audio -o $@
$(HOST)/common/maud.c: $(HOST)/common/maud.aud.wasm
	wasm2c $< -n maud -o $@
$(HOST)/common/aplayer.h: $(HOST)/common/aplayer.c
$(HOST)/common/maud.h: $(HOST)/common/maud.c

# --- native: host_audio, the oracle ---
# -include host/hstream.h: the cart's stream imports reach the ring (tools/host_gen.py STREAM hooks).
HOST_AUD_CFLAGS = $(HOST_CFLAGS) -DZM_AUDIO_SOFT -DHOST_AUDIO -DHOST_MUSIC_DIR='"$(ROOT)/docs/music"' -include host/hstream.h
$(HOST)/%/host_audio: $(HOST)/%/env.c $(HOST)/%/cart.o $(HOST_COMMON) $(HOST)/common/aplayer.o \
		$(HOST)/common/maud.o $(AUD_SRC) $(AUD_HDRS) host/audio_soft.c host/haudio_soft.h host/main.c host/boot.c \
		$(HOST_IO) $(INPUT_DEPS)
	@mkdir -p $(@D)/aud
	for s in $(HOST)/$*/env.c host/boot.c host/main.c host/host_io.c $(AUD_SRC) host/audio_soft.c $(INPUT_SRC); do \
		$(HOST_CC) $(HOST_AUD_CFLAGS) $(INPUT_CFLAGS) -I$(HOST)/$* -c $$s -o $(@D)/aud/$$(basename $$s .c).o || exit 1; done
	$(HOST_CC) $(@D)/aud/*.o $(HOST)/$*/cart.o $(HOST_COMMON) $(HOST)/common/aplayer.o $(HOST)/common/maud.o \
		-lm -lpthread -o $@

.PHONY: host-audio
host-audio: memmap $(HOST)/$(CART)/host_audio

# --- the native SNDH replays' oracle (tests/test_sndh_native.py): one song, no cart, a digest of
# the writes a frame; run once with ZM_SNDH_MUSASHI=1 (the reference) and once without.
#   make sndh-oracle && ZM_AUDIO_DIGEST=/dev/shm/n.d build/host/oracle/sndh_oracle union/beat_dis.sndh 0 600
# (host.h wants a cart's header for its types: tutorial's.)
ORACLE_SRC := host/sndh_oracle.c $(AUD_SRC) host/audio_soft.c
ORACLE_RT  := $(addprefix $(HOST)/common/,rt.o rt-mem.o rt-exc.o)
$(HOST)/oracle/sndh_oracle: $(ORACLE_SRC) $(AUD_HDRS) host/audio_queue.h host/haudio_soft.h $(ORACLE_RT) \
		$(HOST)/common/aplayer.o $(HOST)/common/maud.o $(HOST)/tutorial/cart.h
	@mkdir -p $(@D)/o
	for s in $(ORACLE_SRC); do \
		$(HOST_CC) $(HOST_AUD_CFLAGS) -I$(HOST)/tutorial -c $$s -o $(@D)/o/$$(basename $$s .c).o || exit 1; done
	$(HOST_CC) $(@D)/o/*.o $(ORACLE_RT) $(HOST)/common/aplayer.o $(HOST)/common/maud.o -lm -lpthread -o $@
.PHONY: sndh-oracle
sndh-oracle: memmap $(HOST)/oracle/sndh_oracle

# The oracle that also counts the 68000 instructions Musashi runs and the calls it makes into the
# tune (zm_survey_insns / zm_survey_calls, printed with ZM_SNDH_TIMERS): tools/bard_load_survey.py's
# measure of a tune's work, which unlike x86 time does not move with the box's load. Each call of
# the instruction hook is one instruction; a call (play, an interrupt) ends at the return stub.
$(HOST)/oracle/aplayer_count.o: $(HOST)/common/aplayer.c
	@mkdir -p $(@D)
	sed 's/^\( *\)w2c_audio_zmSndhInstructionHook_0(instance, var_i0)/\1zm_survey_insns++, zm_survey_calls += var_i0 == zm_survey_ret, w2c_audio_zmSndhInstructionHook_0(instance, var_i0)/' \
		$< >$(@D)/aplayer_count.c
	sed -i '1i unsigned long long zm_survey_insns, zm_survey_calls; unsigned zm_survey_ret;' $(@D)/aplayer_count.c
	grep -q 'zm_survey_insns++' $(@D)/aplayer_count.c || (echo "$@: the hook's call site moved"; exit 1)
	$(HOST_CC) $(HOST_CFLAGS) -c $(@D)/aplayer_count.c -o $@
$(HOST)/oracle/sndh_survey: $(HOST)/oracle/sndh_oracle $(HOST)/oracle/aplayer_count.o
	$(HOST_CC) $(filter-out %/sndh_oracle.o,$(wildcard $(HOST)/oracle/o/*.o)) $(HOST)/oracle/o/sndh_oracle.o \
		$(ORACLE_RT) $(HOST)/oracle/aplayer_count.o $(HOST)/common/maud.o -lm -lpthread -o $@
.PHONY: sndh-survey
sndh-survey: memmap $(HOST)/oracle/sndh_survey

# --- the board firmware (cycles/board.mk links these): the players for rv32 (`aligned`, as the
# cart), the shared audio side, the queue backend and the cart's songs (tools/song_pack.py: the
# songs host_audio started in SONG_FRAMES frames, plus the cart's literal song names).
SONG_FRAMES ?= 600
HCYC        := build/hcycles
AUD_FW_SRC  := $(AUD_SRC) cycles/baudio.c cycles/bsongs.c cycles/bmirror.c
AUD_FW_DEPS := $(AUD_FW_SRC) $(AUD_HDRS) cycles/baudio.h cycles/bsndinfo.h cycles/aud_state.h cycles/bmirror.h gen/glass_cart.h $(CYC)/$(HV)/common/aplayer.o $(HOST)/common/aplayer.h
# The players for rv32, in a cycles.mk variant: `aligned` (soft-float), `alignedf` (board.mk ZM_FPU=1).
$(CYC)/%/common/aplayer.o: $(CYC)/src/aplayer.c
	@mkdir -p $(@D)
	$(RV_CC) $(RV_CFLAGS) $(V_$*) -c $< -o $@
$(HCYC)/songs/%.c: $(ROOT)/docs/demo-%.wasm $(HOST)/%/host_audio tools/song_pack.py
	@mkdir -p $(@D)
	ZM_AUDIO_LOG=$(HCYC)/songs/$* $(HOST)/$*/host_audio $* $(SONG_FRAMES) $(SONG_FRAMES) >/dev/null
	uv run python tools/song_pack.py $< $@ --log $(HCYC)/songs/$*.w

# --- the players' cost alone (cycles/baudio_bench.c), on the board SoC sim: no cart.
#   make audio-bench SONG=union/wow_scroller.sndh [TUNE=0] [ZM_FRAMES=60]
#   ZM_SOC=$PWD/build/soc_hp ZM_INIT=sim_zm_ddr.init tools/cycles_sim.sh build/hcycles/abench/zm_ddr.init /dev/shm/ab
# (host.h wants a cart's header for its types: tutorial's.)
SONG ?= sos.sndh
TUNE ?= 0
ABENCH := $(HCYC)/abench
.PHONY: audio-bench
audio-bench: memmap $(HCYC)/gen/csr_addr.h $(CYC)/aligned/common/aplayer.o $(HCYC)/sim/common/fw.a $(HOST)/tutorial/cart.h
	@mkdir -p $(ABENCH)
	printf 'L 0 0 %s\n' '$(SONG)' >$(ABENCH)/song.w
	uv run python tools/song_pack.py $(ROOT)/docs/demo-tutorial.wasm $(ABENCH)/songs.c --log $(ABENCH)/song.w
	for s in $(AUD_FW_SRC) $(ABENCH)/songs.c cycles/baudio_bench.c; do \
		$(RV_CC) $(HRV_CFLAGS) -I$(HOST)/tutorial '-DZM_SONG="$(SONG)"' -DZM_TUNE=$(TUNE) -DZM_FRAMES=$(ZM_FRAMES) \
			-c $$s -o $(ABENCH)/$$(basename $$s .c).o || exit 1; done
	$(RV_CC) $(HRV_LDFLAGS) -o $(ABENCH)/fw.elf $(ABENCH)/*.o $(CYC)/aligned/common/aplayer.o $(HCYC)/sim/common/fw.a -lm
	$(RV_OBJCOPY) -O binary $(ABENCH)/fw.elf $(ABENCH)/fw.bin && truncate -s %8 $(ABENCH)/fw.bin
	od -An -v -tx8 -w8 $(ABENCH)/fw.bin | tr -d ' ' >$(ABENCH)/zm_ddr.init
