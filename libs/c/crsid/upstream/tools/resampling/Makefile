
all:
	gcc  resampling.c  -o resampling  -DCRSID_RESAMPLING_TEST_SOUND  -lc  -lm  -lSDL  `sdl-config --cflags --libs`  -s  # -O2  # -g
#	./resampling  SincWindow512.h  16  256  8192
#	./resampling  SincWindow2048.h  12  128  2048
#	./resampling  SincWindow512.h  8  128  2048
#	./resampling  SincWindow512.h  6  128  2048
	./resampling  SincWindow512.h  4  256  4096
#	./resampling  SincWindow512.h  6  32  512
#	./resampling  SincWindow512.h  4  16  256
#	./resampling  SincWindow512.h  4  8  256
#	diagram test.raw