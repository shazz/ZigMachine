;===============================================================================
;--- SID-WIZARD --- A native C64 music editor (tracker) tool
;-------------------------------------------------------------------------------
;by Hermit Software (Mihaly Horvath) - with much help from Soci of Singular Crew
;-------------------------------------------------------------------------------

The complete User Manual can be found in 'manuals' folder. The most recent version is
'SID-Wizard-1.9-UserManual.txt'. You can find older versions in PDF format in the
older SID-Wizard releases like 1.7 , if you need a more verbose documentation.

The latest Japanese translation is found here:
http://csdb.dk/release/?id=126819

Also, don't forget to check out WitchMaster's perfect book about SID-Wizard at CSDb.

You can find all executables in 'application' directory, including a d64 with instruments.
There's a KERNALload version of SID-Maker and SID-Wizard now which can be used with SD2IEC and
fastloader cartridges that couldn't work with SID-Wizard, like the Final Cartridge III.
It completely turns off the cartridge fastloader and forces KERNAL loader and saver.
If there's no binary or you want to re-compile all the .prg and .d64 files,
here :


Assemble/compile/install (in Linux):
------------------------------------
 Prerequisites:
  -64tass (v1.59.3120 v1.60.3243 were used) in system-directory* to assemble asm/inc files
  -c1541 in system-directory* to create .d64 diskimages via program and examples
   (it is part of VICE, while x64 is the emulator executable but not necessary)
  *system directory /usr/local/bin might be a good option for Linux
  -gcc, g++, make (should be in the system-path, part of 'build-essential' .deb package)
  (You can use mingw-gcc toolchain as well if you have M$ OS. On 64bit systems you need
   gcc-multilib and g++-multilib packages to compile SWMconvert and sng2swm. In case
   you want 64bit version, delete the -m32 gcc/g++ modifiers in the Makefile.)

 There is a 'Makefile' present in the 'sources' directory...
 Go to the 'sources' directory in shell, and simply type 'make' to create the 
 binaries into 'application' directory (one level upper in file-tree).
 
 -'make clean' : will purge all the binary/tune files created by 'make'.)
 
 -'make install' : the SWMconvert & sng2swm executables will be copied to /usr/local/bin
  system-resource directory to be executable from anywhere later.
  Also a copy of SID-Wizard, SID-Maker and example tunes & instruments will be
  copied to an '/opt/SID-Wizard' directory, and a desktop/menu entry file
  '/usr/applications/SID-Wizard.desktop' and icon will be created to point to SID-Wizard.
  (Of course 'x64' of VICE-emulator is a prerequisite for this to work.)
 
 -'make uninstall' : typing this in commandline will delete the executable & desktop 
  files that were copied to system-folders by 'make install'. (Instruments & tunes remain)
 
 *To re-compile only 2SID version of SID-Wizard, type 'make 2SID' in command prompt.



;Graphic-tools: sw-header was painted with SPRedit (.ols format) 
;               sw-splash was finalized in HermIRES (.hbm format)
;
;-------------------------------------------------------------------------------
;The PIC assembler source for the MIDI interface should be compiled separately.
;I used 'gpasm' for Linux, the syntax might be compatible with 'mpasm' as well.
;To design the little HerMIDI PCB I used gEDA's PCB Designer...

;-------------------------------------------------------------------------------
;License: You know I'm not into licensing and legal stuff but for the sake of completeness
;let's declare SID-Wizard as a WTF-licensed tool, so you can do WTF you want with it.

; 2026 Hermit Software Hungary  - contact:   by Personal Message at CSDb
;===============================================================================
