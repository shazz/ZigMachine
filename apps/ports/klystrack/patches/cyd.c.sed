# KESTREL: no oversampling (mused.c.sed): cyd_init runs after klystrack applies its config, so its own
# default (MAX_OVERSAMPLE = 4x) would win over mused.oversample until the menu changes it.
s/^\tcyd->oversample = MAX_OVERSAMPLE;$/\tcyd->oversample = 0; \/* KESTREL *\//
