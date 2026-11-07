#common Makefile content (usable by app too)

CRSID_VERSION=1.58


#if libraries should be built against ALSA only (eliminating SDL-dependence):
LIBCRSID_AUDIO_BACKEND__ALSA=0


OS := $(shell uname)
ifeq ($(OS),Darwin)
 CC=gcc-14
else
 CC=gcc
 #CC=tcc  #seems not to be able to create libraries
endif

AR=ar rcs
CP=cp
RM=rm -f
DEBUGGER=gdb -ex run --args


DEPENDS=libsdl1.2debian

#CRSID_PLATFORM__EMBEDDED = 0
#CRSID_PLATFORM__PC = 1
#CRSID_PLATFORM = $(CRSID_PLATFORM__PC)  #set from outside
#BACKEND_IDS = -DCRSID_BACKEND_ID__EMBEDDED=$(CRSID_PLATFORM__EMBEDDED) -DCRSID_BACKEND_ID__PC=$(CRSID_PLATFORM__PC)

LIBDIR = /usr/lib
INCDIR = /usr/include

DEFINES = -DCRSID_VERSION=\"$(CRSID_VERSION)\"

LIBCRSID_PC_DEFINES = -DCRSID_PLATFORM_PC

SDL_DEFINES = $(LIBCRSID_PC_DEFINES) -DUSING_AUDIO_LIBRARY__SDL=1
SDL_EXTERNAL_SOURCES = `sdl-config --cflags --libs`  -lSDL  # -lm  # -lpulse0

#alsa is used with CLI-only versions to have sound (in place of SDL-audio)
ALSA_DEFINES = $(LIBCRSID_PC_DEFINES) -DUSING_AUDIO_LIBRARY__ALSA=1
ALSA_SOURCES = -lasound


ifeq ($(OS),Darwin)
PC_DEFINES = $(LIBCRSID_PC_DEFINES)  -DDIR_SEPARATOR=\"/\"  -DDARWIN
PC_CCFLAGS = -I/opt/homebrew/opt/sdl12-compat/include/SDL  -L/opt/homebrew/opt/sdl12-compat/lib  -lSDLmain -lSDL -framework Cocoa -w  # -lm
else
 PC_DEFINES = $(LIBCRSID_PC_DEFINES)
 ifeq ($(LIBCRSID_AUDIO_BACKEND__ALSA),1)
  PC_DEFINES = $(ALSA_DEFINES)
  PC_CCFLAGS = $(ALSA_SOURCES)
 else                           #btw SDL-1.2 is designed originally as the default backend for audio (and video)
  PC_DEFINES = $(SDL_DEFINES)
  PC_CCFLAGS = $(SDL_EXTERNAL_SOURCES)
 endif
endif


# ifeq ($(CRSID_PLATFORM),$(CRSID_PLATFORM_PC))
LIB_DEFINES = $(DEFINES) $(PC_DEFINES)
LIB_CCFLAGS = $(CCFLAGS) $(PC_CCFLAGS)
# endif


