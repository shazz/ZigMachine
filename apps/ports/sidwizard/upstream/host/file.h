
#include <stdio.h>
#include <stdlib.h>

#ifdef __unix__
 #include <sys/stat.h> //for mkdir(name,mode)
 #define DIR_SEPARATOR "/"
#else
 #include <io.h> //for mkdir()
 //#include <direct.h> //for mkdir()
 #define DIR_SEPARATOR "\\"
#endif


#define PATH_LENGTH_MAX 1024
#define FILENAME_LENGTH_MAX 256
#define C64DIRLIST_SIZE_MAX 65536
#define C64_FILENAME_LENGTH_MAX 32 //including possible additions
#define DIR_FILES_MAX 2000 //(C64DIRLIST_SIZE_MAX/C64_NAMELEN_MAX) //16384
#define DEFAULT_DRIVE 8
#define DRIVENUM_MIN 8
//#define EXTENSION_LENGTH 4 //including dot
#define FOLDER_CHARCODE 0x7F
#define TOOLONG_CHARCODE 0x7E

//Must be the same as in KERNAL.asm
#define diskZP 0xF6 //Be careful not to be used by SID-Wizard/SID-Maker!
#define diskZPnameLo (diskZP+0)
 //#define MIDIeventRead diskZPnameLo
#define diskZPnameHi (diskZP+1)
#define diskZPnameLen (diskZP+2)
 //#define MIDIeventWritten diskZPnameLen //#define MIDIbufNum diskZPnameLen
#define diskZPloadStatus (diskZP+3)
 enum DiskCommandsAndReplies { DISKSTATUS_OK=0, DISKCMD_OPEN=1, DISKCMD_CLOSE=2, DISKCMD_CHRIN=3, DISKCMD_CHROUT=4, DISKCMD_LOAD=5, DISKCMD_SAVE=6, DISKCMD_CHDIR=7,
                               //DISKCMD_INITMIDI=8, DISKCMD_CLOSEMIDI=9, DISKCMD_GETMIDIDATA=10, DISKCMD_GOTMIDIDATA=11,
                               DISKSTATUS_NODEVICE=0xF0, DISKSTATUS_NOTFOUND=0xF1, DISKSTATUS_EOF=0xF2, DISKSTATUS_FILEEXISTS=0xF3, DISKSTATUS_NOINPUT=0xF4};
#define diskZPstartLo (diskZP+4)
#define diskZPstartHi (diskZP+5)
#define diskZPendLo (diskZP+6)
#define diskZPendHi (diskZP+7)
#define diskZPdata  (diskZP+8)
#define diskZPdrive (diskZP+9) //device-number
//#define diskZPargLoad ()

//same as in SW-1.9
#define decozptr 0xd6
#define compzptr 0xd8

#define rd(addr) ( (cRSID_C64.RAMbank[addr]) )
#define wr(addr,data) { cRSID_C64.RAMbank[addr]=(data); }

#ifndef SIDMAKER
 #define CONFIG_DRIVERTYPE_POS 9
 #define CONFIG_TUNINGTYPE_POS 4
#endif

   //$01(C3:nodev!), 6 undefined bytes, diskname (current directory) closed by $00 (max. 35 (old:24) bytes)
   //filelist: 4 bytes filesize (last one is blocks free), " for filename or CR for end-of-list,
   //          filename (max 16 chars) closed by ", $00 row-end delimiter,
#define DRIVE_AMOUNT 8
#define RETURNcode 0x0D


//#if (TUI_ONLY)
// #define PRG_POSTFIX "-for-TUI"
//#else
// #define PRG_POSTFIX ""
//#endif

#ifndef SIDMAKER  //SID-Wizard:

 //#define EXENAMESTART "SIDwizard"
 //#include "../resources/SID-Wizard-1.8.h"
 #if (ENABLED_SDL)
  //#if (SIDAMOUNT==1)
   #include "../resources/SID-Wizard.h"
  //#elif (SIDAMOUNT==2)
   #include "../resources/SID-Wizard-2SID.h"
  //#elif (SIDAMOUNT==3)
   #include "../resources/SID-Wizard-3SID.h"
  //#elif (SIDAMOUNT==4)
   #include "../resources/SID-Wizard-4SID.h"
  //#endif
 #endif  //#endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI) //#if (TUI_ONLY)
  //#if (SIDAMOUNT==1)
   #include "../resources/SID-Wizard-for-TUI.h"
  //#elif (SIDAMOUNT==2)
   #include "../resources/SID-Wizard-2SID-for-TUI.h"
  //#elif (SIDAMOUNT==3)
   #include "../resources/SID-Wizard-3SID-for-TUI.h"
  //#elif (SIDAMOUNT==4)
   #include "../resources/SID-Wizard-4SID-for-TUI.h"
  //#endif
 #endif  //#else

#else  //SID-Maker:

 //#define EXENAMESTART "SIDmaker"
 #if (ENABLED_SDL)
  //#if (SIDAMOUNT==1)
   //#ifdef SFX_SUPPORT
    #include "../resources/SID-Maker-SFX.h"
    #include "../resources/SID-Maker-ROM-SFX.h"
   //#elif defined(SWP_SUPPORT)
    #include "../resources/SID-Maker-SWP.h"
    #include "../resources/SID-Maker-SWP-2SID.h"
    #include "../resources/SID-Maker-SWP-3SID.h"
    #include "../resources/SID-Maker-SWP-4SID.h"
    #include "../resources/SID-Maker-ROM-SWP.h"
    #include "../resources/SID-Maker-ROM-SWP-2SID.h"
    #include "../resources/SID-Maker-ROM-SWP-3SID.h"
    #include "../resources/SID-Maker-ROM-SWP-4SID.h"
    #include "../resources/SID-Maker-echo.h"
   //#else
    #include "../resources/SID-Maker.h"
    #include "../resources/SID-Maker-ROM.h"
   //#endif
  //#elif (SIDAMOUNT==2)
   #include "../resources/SID-Maker-2SID.h"
   #include "../resources/SID-Maker-ROM-2SID.h"
  //#elif (SIDAMOUNT==3)
   #include "../resources/SID-Maker-3SID.h"
   #include "../resources/SID-Maker-ROM-3SID.h"
  //#elif (SIDAMOUNT==4)
   #include "../resources/SID-Maker-4SID.h"
   #include "../resources/SID-Maker-ROM-4SID.h"
  //#endif
 #endif //#endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI) //#if (TUI_ONLY)
  //#if (SIDAMOUNT==1)
   //#ifdef SFX_SUPPORT
    #include "../resources/SID-Maker-SFX-for-TUI.h"
    #include "../resources/SID-Maker-ROM-SFX-for-TUI.h"
   //#elif defined(SWP_SUPPORT)
    #include "../resources/SID-Maker-SWP-for-TUI.h"
    #include "../resources/SID-Maker-SWP-2SID-for-TUI.h"
    #include "../resources/SID-Maker-SWP-3SID-for-TUI.h"
    #include "../resources/SID-Maker-SWP-4SID-for-TUI.h"
    #include "../resources/SID-Maker-ROM-SWP-for-TUI.h"
    #include "../resources/SID-Maker-ROM-SWP-2SID-for-TUI.h"
    #include "../resources/SID-Maker-ROM-SWP-3SID-for-TUI.h"
    #include "../resources/SID-Maker-ROM-SWP-4SID-for-TUI.h"
    #include "../resources/SID-Maker-echo-for-TUI.h"
   //#else
    #include "../resources/SID-Maker-for-TUI.h"
    #include "../resources/SID-Maker-ROM-for-TUI.h"
   //#endif
  //#elif (SIDAMOUNT==2)
   #include "../resources/SID-Maker-2SID-for-TUI.h"
   #include "../resources/SID-Maker-ROM-2SID-for-TUI.h"
  //#elif (SIDAMOUNT==3)
   #include "../resources/SID-Maker-3SID-for-TUI.h"
   #include "../resources/SID-Maker-ROM-3SID-for-TUI.h"
  //#elif (SIDAMOUNT==4)
   #include "../resources/SID-Maker-4SID-for-TUI.h"
   #include "../resources/SID-Maker-ROM-4SID-for-TUI.h"
  //#endif
 #endif  //#else //not TUI_ONLY:

#endif

