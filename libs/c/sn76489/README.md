# Our SN76489: the Sega PSG, MIT

The Mega Drive / Master System / Game Gear PSG in integer C, written from TI's SN76489AN data sheet and
SMS Power's notes on the Sega variant (Maxim): three square tones and a noise channel, each a counter at
clock / 16; the 16-bit noise LFSR (white: taps bits 0 and 3; periodic: bit 0), reset to 0x8000 by a noise
write; noise at 0x10 / 0x20 / 0x40 or tone 2's period; 2 dB attenuation steps; periods 0 and 1 hold a
tone high (the PCM trick); the Game Gear's stereo byte.

Each output sample is the exact mean of the counters' levels over its span (a box filter), not a point
sample: no aliasing pile-up at the top. One divide, at reset (`sn76489_reset`); none per sample.

Used by the VGM engine (`libs/c/vgm`), which mixes it into the YM2612's stereo. Against the reference
(libvgm's SN76496 core): the same pitches and attenuation steps, the level matched by the engine's PSG gain
(`ZM_VGM_PSG_GAIN`); noise correlates by loudness only (the LFSR's phase is the emulator's).
