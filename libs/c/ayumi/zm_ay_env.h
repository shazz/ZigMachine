/* zm_ay's envelope, shared by its two files (internal: not part of zm_ay.h). */
#ifndef ZM_AY_ENV_H
#define ZM_AY_ENV_H
#include "zm_ay.h"

/* k envelope counter wraps (upstream: Envelopes[shape][segment](ay) once a wrap), a slide at a time */
void zm_ay_env_advance(struct zm_ay* ay, int k);
/* The envelope's current segment holds its level (no step changes it). */
int zm_ay_env_holds(const struct zm_ay* ay);
/* The level a segment starts at (upstream's reset_segment). */
void zm_ay_env_reset(struct zm_ay* ay);
#endif
