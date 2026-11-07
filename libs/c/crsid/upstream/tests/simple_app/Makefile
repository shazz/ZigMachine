
CC=gcc
#CC=tcc  #for debugging, using faster compiler for testing (comment out for gcc set in libcRSID/Common.mk)


LIBFOLDER = ../..
LIBHEADER = $(LIBFOLDER)/libcRSID.h
LIBSOURCE = $(LIBFOLDER)/libcRSID.c
LIBSOURCES = $(LIBHEADER) $(LIBSOURCE)


CCFLAGS = -std=gnu99  `sdl-config --cflags --libs`  -lSDL  # -s

DEFINES = -DCRSID_PLATFORM_PC  -DLINUX


all: static
#all: shared


shared: $(LIBSOURCES)
	$(CC)  testapp.c  -o testapp_shared  $(DEFINES)  $(CCFLAGS)  -L$(LIBFOLDER)  -lcRSID  -Wl,-rpath=$(LIBFOLDER)  # -s
	./testapp_shared


static: $(LIBSOURCES)  #simple test if library is buildable within PC (providing SDL and other PC stuff)
	$(CC)  testapp.c $(LIBSOURCE)  -o testapp  $(DEFINES)  $(CCFLAGS)  # -s
	./testapp


alsa: CCFLAGS = -std=gnu99  -lasound  # -s
alsa: $(LIBSOURCES)  #simple test if library is buildable within PC (providing SDL and other PC stuff)
	$(CC)  testapp.c $(LIBSOURCE)  -o testapp_alsa  $(DEFINES)  -DUSING_AUDIO_LIBRARY__ALSA=1  $(CCFLAGS)
	./testapp_alsa


clean:
	rm  -f ./testapp ./testapp_shared ./testapp_alsa

