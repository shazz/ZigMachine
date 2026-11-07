# The output attenuator divides each sample by a constant for the run (13 for one SID): ZDIV
# (config/zm_crsid.h) switches to a constant divide, which GCC -mno-div / wasm turn into a multiply.
# Bit-exact. HQsampleCount (HQ engine only, not used) likewise.
s/Output\.\([LR]\) \/= cRSID_C64\.Attenuation;/Output.\1 = ZDIV(Output.\1, cRSID_C64.Attenuation);/g
s/\(cRSID_C64\.SID\[[0-9]\]\.[A-Za-z]*\) \/= HQsampleCount;/\1 = ZDIV(\1, HQsampleCount);/g
