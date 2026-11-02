# KESTREL: ayumi.cpp is replaced by ../kestrel_ayumi.cpp (the same chip model in integers, a box filter in place
# of the cubic interpolator + 192-tap FIR); its state rides at the end of struct ayumi.
/^struct ayumi {$/i\
struct kestrel_ay { /* KESTREL: kestrel_ayumi.cpp */\
  float step_seen;            /* ay->step the next fields were computed from */\
  unsigned ticks_q16;         /* chip ticks (clock / 8) a sample, 16.16 */\
  unsigned frac;              /* the fraction of a tick carried to the next sample */\
  int pan_l[3], pan_r[3];     /* Q15 */\
  int out_l, out_r;           /* the sample before DC removal, Q15 */\
  int dc_l, dc_r;             /* DC estimate, Q23 */\
};
/^  void\* timer_func_userdata;$/a\
  struct kestrel_ay k; /* KESTREL */
