# KESTREL: ayumi.cpp is replaced by ../kestrel_ayumi.cpp, upstream's API over the integer AY core every renderer
# shares (libs/c/ayumi, a box filter in place of the cubic interpolator + 192-tap FIR); its state rides at the end
# of struct ayumi.
/^struct ayumi {$/i\
#include "zm_ay.h" /* KESTREL: libs/c/ayumi */
/^  void\* timer_func_userdata;$/a\
  struct zm_ay k;   /* KESTREL: the chip (kestrel_ayumi.cpp) */\
  float step_seen;  /* KESTREL: the ay->step k's clock was set from (SoundChipAY::updateClock writes step) */
