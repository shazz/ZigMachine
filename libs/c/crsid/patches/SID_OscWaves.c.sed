# The light pulse's edge steepness divides by the voice's frequency step on every sample: ZRECIP
# (config/zm_crsid.h) memoises it per voice. Bit-exact.
s|PHASEACCU_MAX/PhaseAccuStep|ZRECIP(SID, Channel, PHASEACCU_MAX, PhaseAccuStep)|
