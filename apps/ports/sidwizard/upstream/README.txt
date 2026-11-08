                      SID-Wizard PC-version README

Simply type 'make' to build, given prerequisites are present ( 'make' tool,
'gcc' compiler, and maybe 'nasm' for internal SDL's assembly-code
accelerators like Hermes ).
(If changes are made to the native C64 code, 'make natives' might be a good idea
to build the native C64 apps before the main 'make', needs 64tass-v1.59.3120+.)
(Note: In case you have some permission issues with any mentioned operation on
your system, you can write 'sudo' before 'make' and other commands to
circumvent that.)

The general flow of rebuilding the whole SID-Wizard PC-suite is like this:
-'make clean' can retrigger rebuilding the executables they're here pre-built
-'make natives' creates C64 prg executables and the .cmp files from them in
 'resources' folder. If the .cmp files are there this step can be skipped.
-'make' creates .h files from the .cmp files and builds PC execatables from them

To create the package (.deb for Linux, .zip for Windows), type 'make package'.

To install the created package on the Linux system, type 'make install'.
(To uninstall it, type 'make uninstall'.)

To clean most stuff, type 'make clean', to clean natives better, type
'make cleannatives'. (This might be needed to rebuild SWMconvert & sng2swm too.)
(For uninstalling at the same time' type 'make purge'. You can get hints about
targets by 'make help' too.)

I only test and build for Linux systems, but still using cross-platform
libraries, so it's probably buildable for other OS-es with little tweaks.

For more information read the full SID-Wizard user-manual (in 'resources' for
PC-version and in 'natives/manuals' folder for C64 version).


2026 Hermit (Mihaly Horvath) with WTF licence
(Do what the frick you want with this code, but mentioning me if you use it
would still be nice.)

