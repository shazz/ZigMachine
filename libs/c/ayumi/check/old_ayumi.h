/* The struct and API perf/ports-synth's kestrel_ayumi.cpp was written against (upstream's ayumi.h + the
 * ayumi.h.sed state), enough to build that file as the reference in check.sh: no upstream checkout needed. */
#ifndef AYUMI_H
#define AYUMI_H
enum { TONE_CHANNELS = 3, DECIMATE_FACTOR = 8 };
typedef float (*ayumi_filter_func)(float* x);
extern "C" float ayumi_filter_medium(float* x);
struct tone_channel { int tone_period, tone_counter, tone, t_off, n_off, e_on, volume; float pan_left, pan_right; };
struct kestrel_ay {
  float step_seen; unsigned ticks_q16, frac; int pan_l[3], pan_r[3]; int out_l, out_r; int dc_l, dc_r;
};
struct ayumi {
  struct tone_channel channels[TONE_CHANNELS];
  int noise_period, noise_counter, noise;
  int envelope_counter, envelope_period, envelope_shape, envelope_segment, envelope;
  const float* dac_table;
  float step, left, right;
  ayumi_filter_func filter_func;
  int (*timer_func)(struct ayumi* ay, void* userdata);
  void* timer_func_userdata;
  struct kestrel_ay k;
};
extern "C" {
int ayumi_configure(struct ayumi* ay, int is_ym, float clock_rate, int sr);
void ayumi_set_chip_type(struct ayumi* ay, int is_ym);
void ayumi_set_pan(struct ayumi* ay, int index, float pan, int is_eqp);
void ayumi_set_tone(struct ayumi* ay, int index, int period);
void ayumi_set_noise(struct ayumi* ay, int period);
void ayumi_set_mixer(struct ayumi* ay, int index, int t_off, int n_off, int e_on);
void ayumi_set_volume(struct ayumi* ay, int index, int volume);
void ayumi_set_envelope(struct ayumi* ay, int period);
void ayumi_set_envelope_shape(struct ayumi* ay, int shape);
void ayumi_set_filter_quality(struct ayumi* ay, ayumi_filter_func filter_func);
void ayumi_set_timer_func(struct ayumi* ay, int (*timer_func)(struct ayumi* ay, void* userdata), void* timer_func_userdata);
void ayumi_process(struct ayumi* ay);
void ayumi_remove_dc(struct ayumi* ay);
}
#endif
