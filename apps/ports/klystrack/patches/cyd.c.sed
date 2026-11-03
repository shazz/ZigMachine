# KESTREL: no oversampling (mused.c.sed): cyd_init runs after klystrack applies its config, so its own
# default (MAX_OVERSAMPLE = 4x) would win over mused.oversample until the menu changes it.
s/^\tcyd->oversample = MAX_OVERSAMPLE;$/\tcyd->oversample = 0; \/* KESTREL *\//
# KESTREL: a channel whose output nobody hears (gate off, and no gated channel ring-modulates from it) skips its
# oscillator and wavetable reads; its oscillators still advance (phase, sync bit, noise LFSR) exactly as before.
# frame_cost: the synth runs every channel every sample, played or not.
/^static Sint32 cyd_output_channel(CydEngine \*cyd, CydChannel \*chn)$/i\
static int kestrel_osc_needed = 1; /* KESTREL: set by cyd_output before each channel */\
static Uint32 kestrel_ringed; /* KESTREL: channels a gated channel ring-modulates from, this sample */\
static int kestrel_heard(const CydEngine *cyd, int i) /* KESTREL: called for i = 0, 1, ... each sample */\
{\
	if (i == 0)\
	{\
		kestrel_ringed = 0;\
		for (int c = 0 ; c < cyd->n_channels ; ++c)\
			if ((cyd->channel[c].flags & (CYD_CHN_ENABLE_GATE | CYD_CHN_ENABLE_RING_MODULATION)) == (CYD_CHN_ENABLE_GATE | CYD_CHN_ENABLE_RING_MODULATION)) kestrel_ringed |= 1u << (cyd->channel[c].ring_mod & 31);\
	}\
	return (cyd->channel[i].flags & CYD_CHN_ENABLE_GATE) || (kestrel_ringed >> i & 1);\
}\

s/^\t\t\tif (chn->subosc\[s\].frequency != 0)$/\t\t\tif (chn->subosc[s].frequency != 0 \&\& kestrel_osc_needed) \/* KESTREL *\//
s/^\t\ts\[i\] = (Sint32)cyd_output_channel(cyd, &cyd->channel\[i\]);$/\t\tkestrel_osc_needed = kestrel_heard(cyd, i); \/* KESTREL *\/\n&/
s/^\t\t\t\tif (cyd->channel\[i\].subosc\[sub\].wave.playing && cyd->channel\[i\].subosc\[sub\].wave.frequency != 0)$/\t\t\t\tif (kestrel_osc_needed \&\& cyd->channel[i].subosc[sub].wave.playing \&\& cyd->channel[i].subosc[sub].wave.frequency != 0) \/* KESTREL *\//
# KESTREL: an FX bus with no effect on passes its input through (what cydfx_output does), without the call.
s/^\t\tSint32 l, r;$/&\n\t\tif (!(cyd->fx[i].flags \& (CYDFX_ENABLE_CHORUS | CYDFX_ENABLE_REVERB | CYDFX_ENABLE_CRUSH))) { *left += fx_l[i]; *right += fx_r[i]; continue; } \/* KESTREL *\//
