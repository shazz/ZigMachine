# KESTREL: the mix is kestrel_paula.c's integer mixer (it replaces pt2_paula.c, see its header): outputAudio
# hands it the whole block, and no 2x oversampling (the mixer steps every Paula sample at any rate).
/^#include "pt2_paula.h"$/a\
void kestrel_paulaOutput(int16_t *target, int32_t numSamples); /* KESTREL: kestrel_paula.c */
/^void outputAudio(int16_t \*target, int32_t numSamples)$/{
n
s/^{$/{\
\tkestrel_paulaOutput(target, numSamples); return; \/* KESTREL *\//
}
s/^\taudio.oversamplingFlag = (audio.outputRate < 96000);.*/\taudio.oversamplingFlag = false; \/* KESTREL: kestrel_paula.c *\//
