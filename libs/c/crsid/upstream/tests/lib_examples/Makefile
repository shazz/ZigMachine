
CC=gcc
#CC=tcc  #for debugging, using faster compiler for testing (comment out for gcc set in libcRSID/Common.mk)


LIBFOLDER = ../..
LIBHEADER = $(LIBFOLDER)/libcRSID.h
LIBSOURCE = $(LIBFOLDER)/libcRSID.c
LIBSOURCES = $(LIBHEADER) $(LIBSOURCE)


CCFLAGS = -std=gnu99  -s


all: testlib testapp


testlib: $(LIBSOURCES) builtinmusic  #simple test if library is buildable within embedded apps (like RockBox not providing SDL and other PC stuff)
	$(CC)  testlib.c $(LIBSOURCE)  -o testlib  $(DEFINES)  $(CCFLAGS)
	./testlib


testapp: CCFLAGS += `sdl-config --cflags --libs`  -lSDL
testapp: $(LIBSOURCES) builtinmusic  #simple test if library is buildable within PC (providing SDL and other PC stuff)
	$(CC)  testapp.c $(LIBSOURCE)  -o testapp  $(DEFINES)  $(CCFLAGS)
	./testapp


builtinmusic: $(LIBFOLDER)
	$(CC)  $(LIBFOLDER)/tools/bin2array.c  -o $(LIBFOLDER)/tools/bin2array
	$(LIBFOLDER)/tools/bin2array  ../HerMiniSID.sid


clean:
	rm -f  ./testlib ./testapp

