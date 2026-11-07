#Basic cRSID build-configuration used by makefiles for sources of tools/tests/apps


CCFLAGS = -std=gnu99

CCFLAGS += -Wall -Wextra -Wno-unused -Wno-unused-parameter  -Wno-implicit-fallthrough  # -g  # -s

CCFLAGS += -finline-functions -finline-small-functions -finline-functions-called-once -fearly-inlining -findirect-inlining

#CCFLAGS += -O3
#CCFLAGS += -lm

