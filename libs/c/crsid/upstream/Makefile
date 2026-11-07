#libcRSID makefile

#CRSID_PLATFORM = 1
include Config.mk
include Common.mk


CRSID_FILTERTABLE_RESOLUTION=12
CRSID_OVERSAMPLING_FILTERTABLE_RESOLUTION=14

LIBHEADER = libcRSID.h
LIBHEADERS = $(LIBHEADER) *.h
LIBSOURCE = libcRSID.c
SUBSOURCES = C64/*.c host/*.c
LIBSOURCES = $(LIBSOURCE) $(SUBSOURCES)
LIBSHARED = libcRSID.so
LIBSTATIC = libcRSID.a


all: libs


FORCE:


libs: CCFLAGS+=-O3
libs: curvegen $(LIBSHARED) $(LIBSTATIC)


shared: $(LIBSHARED)

static: $(LIBSTATIC)


$(LIBSHARED): $(LIBHEADERS) $(LIBSOURCES)  # FORCE
ifeq ($(OS),Darwin)
	$(CC)  -c $(LIBSOURCE)  -fpic  -o $(LIBSHARED).o  $(LIB_DEFINES)  -DCRSID_LIBRARY  $(LIB_CCFLAGS)
	$(CC)  $(LIBSHARED).o  -shared  -o $(LIBSHARED) -L/opt/homebrew/opt/sdl12-compat/lib -lSDL
else
	$(CC)  -c $(LIBSOURCE)  -fpic  -o $(LIBSHARED).o  $(LIB_DEFINES)  -DCRSID_LIBRARY  $(LIB_CCFLAGS)  # -s
	$(CC)  $(LIBSHARED).o  -shared  -o $(LIBSHARED)
endif
	$(RM) $(LIBSHARED).o


$(LIBSTATIC): $(LIBHEADERS) $(LIBSOURCES)  # FORCE
	$(CC)  -c $(LIBSOURCE)  -o $(LIBSTATIC).o  $(LIB_DEFINES)  -DCRSID_LIBRARY  $(LIB_CCFLAGS)  # -s
	$(AR) $(LIBSTATIC) $(LIBSTATIC).o
	$(RM) $(LIBSTATIC).o


#test: CCFLAGS+=-g
#test: CCFLAGS+=-O0
#test: CC=tcc  #for debugging, using faster compiler for testing (comment out for gcc set in libcRSID/Common.mk)
test: simple_app lib_examples

lib_examples: curvegen $(LIBHEADERS) $(LIBSOURCES) #simple test if library is buildable within PC or embedded apps (like RockBox not providing SDL and other PC stuff)
	make  -C tests/lib_examples

simple_app: libs
ifeq ($(LIBCRSID_AUDIO_BACKEND__ALSA),1)
	make  -C tests/simple_app  alsa
else
	make  -C tests/simple_app  shared
endif

curvegen: $(LIBHEADERS)  tools/curvegen.c  tools/resampling/resampling.c
	$(CC)  tools/curvegen.c  -o tools/curvegen  -lm  -s
	tools/curvegen  C64/SID_FilterCurves.h  # $(CRSID_OVERSAMPLING_RATIO)  # $(CRSID_FILTERTABLE_RESOLUTION) $(CRSID_OVERSAMPLING_FILTERTABLE_RESOLUTION)
	$(CC)  tools/resampling/resampling.c  -o tools/resampling/resampling  -lm  -s
	tools/resampling/resampling  C64/SincWindow.h  # $(CRSID_RESAMPLER_SINCWINDOW_PERIODS) $(CRSID_RESAMPLER_SINCPERIOD_SAMPLES) $(CRSID_RESAMPLER_SINCWINDOW_MAGNITUDE)  # 12  128  2048


clean:
	$(RM) *.o *.a *.so
	$(RM) tools/curvegen  tools/bin2array  tools/resampling/resampling
	$(RM) tests/lib_examples/testlib  tests/lib_examples/testapp  tests/simple_app/testapp

purge: clean


help:
	@echo ""
	@echo "libcRSID Makefile help, targets ('all' is the default which creates all libs):"
	@echo "all, libs, shared, static, test, clean"
	@echo ""

