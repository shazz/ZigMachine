// tests/tb/hdmi_audio_tb.cpp at 44.1 kHz (tests/tb/hdmi_audio44_top.v): N 6272,
// the CTS alternating 44444 / 44445, over 12 frames (about 9,000 samples and
// 180 CTS periods: twenty full cycles of the nine-period CTS pattern).
#define HDMI_RATE44 1
#include "hdmi_audio_tb.cpp"
