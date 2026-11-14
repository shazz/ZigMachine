/* env.hostBardJob where no coprocessor serves (host/bjob.h): the native host and ZIGGY with the players
 * on it (ZM_AUDIO=1). Every op answers 0, so zg.bard.job serves the cart's jobs in the cart, at once,
 * through the same kernels BARD runs: the same bytes, inside the cart's frame. */
#include <stdint.h>

struct w2c_env;
uint32_t audio_bard_job(struct w2c_env* e, uint32_t op, uint32_t arg);

uint32_t audio_bard_job(struct w2c_env* e, uint32_t op, uint32_t arg) {
    (void)e, (void)op, (void)arg;
    return 0;
}
