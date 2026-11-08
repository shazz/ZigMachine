# Only the 1-SID C64-UI program (resources/SID-Wizard.h, made by tools/bin2h.py from the unpacked program);
# the 2/3/4-SID ones are not built (kestrel_sw.c aliases their names). WASI is a unix for paths.
/#include "..\/resources\/SID-Wizard-[234]SID.h"/d
s|^#ifdef __unix__|#if defined(__unix__) \|\| defined(__wasi__) /* kestrel */|
