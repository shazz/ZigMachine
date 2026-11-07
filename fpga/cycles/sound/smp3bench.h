/* snd-bench's MP3 mode (cycles/sound/smp3bench.c): start the stream, feed it before a frame, report. */
#ifndef ZM_SMP3BENCH_H
#define ZM_SMP3BENCH_H

void mp3_bench_start(const char* song);
void mp3_bench_feed(void);
void mp3_bench_report(int frame);

#endif
