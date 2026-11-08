#ifndef DEFINED_HEADER__SIDWIZARD
 #define DEFINED_HEADER__SIDWIZARD


#ifndef CRSID_PLATFORM_PC
 #define CRSID_PLATFORM_PC 1
#endif


#if (ENABLED_NCURSES)
 #define ENABLED_TUI 1
#endif

#ifdef SIDMAKER
 #define MIDI 0
 #define MIDIBUF1 0xE009
#endif


#define ZOOM_DEFAULT 2  //values: 1..4 //use only 2x (for standard 640x480 resolution), otherwise some OSes might bug with fullscreen


#define USE_SDL_EVENTS_IF_PRESENT 0 //1  //even with ncurses TUI it's much better to use the more advanced key-handling based on SDL's raw/low-level keyboard-scanning without default repeats
                                         //NNNNOOOOOOOO, SDL events don't work without a window... solution may be opening a hidden window just to collect the events? but it would only work with X GUI

#define DEFAULT_SAMPLERATE 44100
#define SAMPLERATE (DEFAULT_SAMPLERATE)
#define C64_CPUCLK 985248
#define OVERSAMPLING_CYCLES 3 //23 //7 //static byte OVERSAMPLING_CYCLES = 23; //1; //7; //1; //C64->SampleClockRatio/OVERSAMPLING_RATIO; //#define OVERSAMPLING_CYCLES ((C64_PAL_CPUCLK*OVERSAMPLING_RATIO)/DEFAULT_SAMPLERATE)
//#define OVERSAMPLING_RATIO (C64_CPUCLK/DEFAULT_SAMPLERATE/OVERSAMPLING_CYCLES) //11   //8 //50 //23 //23 //8
#define SID_CHANNEL_AMOUNT 3

#define MILLISECONDS_IN_A_SECOND 1000
#define MICROSECONDS_IN_A_MILLISECOND 1000
#define MICROSECONDS_IN_A_SECOND (MICROSECONDS_IN_A_MILLISECOND * MILLISECONDS_IN_A_SECOND)
#define C64_PAL_FRAMETIME 20 //ms //screen-display and key-checking runs at this rate in SID-Wizard on emulated C64
#define FRAMETIME (C64_PAL_FRAMETIME) //20 //40 //30 //33 //100 //20 //ms
#define KEYSCAN_PERIOD 5 //10 //5 //11 //5 //ms (min./roundabout)  //5ms might give more hiccups in TUI ALSA sound on Raspberry Pi Zero? (but at least on framebuffer console there's no hiccup)
#define SOUNDUPDATE_PERIOD (KEYSCAN_PERIOD)
#define KEYSCAN_PERIOD_MICROSECONDS (KEYSCAN_PERIOD * MILLISECONDS_IN_A_SECOND) //1000)
#define SOUNDUPDATE_PERIOD_MICROSECONDS (SOUNDUPDATE_PERIOD * MILLISECONDS_IN_A_SECOND)
#define SCREENUPDATE_PERIOD (FRAMETIME/KEYSCAN_PERIOD) //KEYSCAN_PERIODs  //screen doesn't need as fast update-rate as key-scanning, only a fraction of it

#if (ENABLED_SDL)
 #define FORCED_SDL_EVENTS (USE_SDL_EVENTS_IF_PRESENT)
 #define ENABLED_SDL_EVENTS (ENABLED_SDL || FORCED_SDL_EVENTS)
#endif

#if (ENABLED_TUI)
 #if (!FORCED_SDL_EVENTS)
  #define ENABLED_TUI_KEYS 1
 #endif
 #ifndef SIDMAKER  //SID-Wizard TUI key-hold (so the short ncurses key-signals are sensed by C64 emulated keymatrix):
  #if (TUI_ONLY)
   #define TUI_KEYHOLD_TIME (C64_PAL_FRAMETIME * 40/10) //milliseconds
  #else
   #define TUI_KEYHOLD_TIME (C64_PAL_FRAMETIME * 27/10) //3) //2) //milliseconds  //should be at least 'repspd2' frames in native C64-code to have continuous pianokey-notes and stable Shift/Ctrl-keycombanations
  #endif
 #else  //SID-Maker TUI key-hold:          (typical key-repeat periods on PC are about 30..40ms, that should be bridged over for continuous press simulations)
  #define TUI_KEYHOLD_TIME (C64_PAL_FRAMETIME * 27/10) //milliseconds  //in TUI(-mode) SID-Maker relocation-address setting repeat would be a bit instable with the value that's OK for SID-Wizard
 #endif
 #define TUI_KEYHOLD_KEYFRAMES (TUI_KEYHOLD_TIME / KEYSCAN_PERIOD)
 //#define TUI_ONLY_C64_KEYREPEAT_DELAY_PALFRAMES (TUI_KEYHOLD_TIME/FRAMETIME/2)  //time should be bigger than TUI_KEYHOLD_TIME to avoid hiccups in C64 keyhandler
#endif

#if ( ENABLED_SDL && !defined(SIDMAKER) )
 #define SPLASH_SCREEN_DURATION (300 /*ms*/ / KEYSCAN_PERIOD)  //*5ms (max. 255)  //show the fancy splash-logo for a short time even on fast systems
#else
 #define SPLASH_SCREEN_DURATION 0
#endif
#define SPLASH_TO_KEYSIM_DELAY 70 //60 //40 //20 //*5ms, wait at startup after splash-screen, before simulating keypresses for player-type (& tuning) selection
#define KEYSIM_STARTUPDELAY (SPLASH_SCREEN_DURATION + SPLASH_TO_KEYSIM_DELAY) //*5ms, wait at startup before simulating keypresses for player-type (& tuning) selection
#define KEYSIM_EDITORWAIT 150 //150 //100 //50 //*5ms, wait for editor after startup-menu, before simulating keypresses for loading file given as bash-argument
 //#define KEYSIM_EDITORWAIT_TUI 150 //200 //it seems TUI-mode needs different value
#define KEYSIM_REPEATDELAY   (12 *C64_PAL_FRAMETIME /KEYSCAN_PERIOD) //44 //25 //20 //10 //*5ms, wait between simulated keypresses
 //#define KEYSIM_REPEATDELAY_TUI 44 //21 //*5ms //it seems TUI-mode needs different value
#define KEYSIM_PRESSDURATION (C64_PAL_FRAMETIME*35/10 /KEYSCAN_PERIOD) //*5ms //22 //16 //12 //5 //*5ms, duration of simulated keypresses
 //#define KEYSIM_PRESSDURATION_TUI 12 //22 //10 //12 //5 //*5ms, duration of simulated keypresses, it seems TUI-mode needs different value due to key-hold feature of PC-keyrepeats

#define SAMPLEBUFFER_UPDATE_PERIOD (KEYSCAN_PERIOD)  //called in the same main loop at the same pace as key-scanning
#define BUFFERSIZE_MIN (SAMPLERATE * SAMPLEBUFFER_UPDATE_PERIOD / MILLISECONDS_IN_A_SECOND)
#define SOUND_DELAY_MAX 100 //milliseconds (above this value the lag of using piano keys is unbearable to a musician)
#define BUFFERSIZE_MAX (SAMPLERATE * SOUND_DELAY_MAX / MILLISECONDS_IN_A_SECOND)
#define DEFAULT_BUFFERSIZE 2048 //(power of 2 nearest to but below BUFFERSIZE_MAX/2) //1024 //2048 //4096 //16384  //OK on slower machines too but still bearable delay
#define SOUND_DELAY_DEFAULT (DEFAULT_BUFFERSIZE / SAMPLERATE) //seconds  (46.4ms at 44.1kHz samplerate)

#ifndef OSCILLOSCOPE_SHOWS_ALL_CHANNELS
 #define OSCILLOSCOPE_SHOWS_ALL_CHANNELS 1
#endif

enum { BASIC_START_ADDRESS = 0x0801 };
#define PROGRAMSTART_ADDRESS 0x0810
#define SAFESTART_ADDRESS    0x080D

#define MIDI_NAME_LENGTH_MAX 255


#ifndef EXE_POSTFIX
 #define EXE_POSTFIX ""
#endif

#ifndef SIDMAKER
 #define EXENAME "SIDwizard" EXE_POSTFIX
 #define EXENAMETAIL_GUI "_GUI"
#else
 #define EXENAME "SIDmaker" EXE_POSTFIX
#endif

#define SIDWIZARD_USER_SUBFOLDER ".SIDwizard"
#define CONFIGFILE_NAME "DefaultSettings.cfg"


//#if (SIDAMOUNT==1)
 #define WORKFILE_EXTENSION_1SID ".swm"
 #define MAGICSTRING_1SID "SWM1"
 #define TUNE_DRIVERTYPE_POS_1SID 19 //$13 ;//position of player/driver-musicroutine type info (light/medium/full/extra/bare/demo), just an information, no restriction caused
 #define TUNE_TUNINGTYPE_POS_1SID 20 //$14 ;//position of tuning-type of frequency-table (0:normal 440Hz, 1:432Hz Verdi-tuning, 2-Just-intonation for key of C)
 #define EXENAMETAIL_1SID ""
//#elif (SIDAMOUNT==2)
 #define WORKFILE_EXTENSION_2SID ".sws"
 #define MAGICSTRING_2SID "SWMS"
 #define TUNE_DRIVERTYPE_POS_2SID 19 //$13 ;//position of player/driver-musicroutine type info (light/medium/full/extra/bare/demo), just an information, no restriction caused
 #define TUNE_TUNINGTYPE_POS_2SID 20 //$14 ;//position of tuning-type of frequency-table (0:normal 440Hz, 1:432Hz Verdi-tuning, 2-Just-intonation for key of C)
 #define EXENAMETAIL_2SID "-2SID"
//#elif (SIDAMOUNT==3)
 #define WORKFILE_EXTENSION_3SID ".swt"
 #define MAGICSTRING_3SID "SWMT"
 #define TUNE_DRIVERTYPE_POS_3SID 11 //position of player/driver-musicroutine type info (light/medium/full/extra/bare/demo), just an information, no restriction caused
 #define TUNE_TUNINGTYPE_POS_3SID 12 //position of tuning-type of frequency-table (0:normal 440Hz, 1:432Hz Verdi-tuning, 2-Just-intonation for key of C)
 #define EXENAMETAIL_3SID "-3SID"
//#elif (SIDAMOUNT==4)
 #define WORKFILE_EXTENSION_4SID ".swq"
 #define MAGICSTRING_4SID "SWMQ"
 #define TUNE_DRIVERTYPE_POS_4SID 11 //position of player/driver-musicroutine type info (light/medium/full/extra/bare/demo), just an information, no restriction caused
 #define TUNE_TUNINGTYPE_POS_4SID 12 //position of tuning-type of frequency-table (0:normal 440Hz, 1:432Hz Verdi-tuning, 2-Just-intonation for key of C)
 #define EXENAMETAIL_4SID "-4SID"
//#endif

 #ifdef SIDMAKER
  #define EXENAMETAIL_ROM "-ROM"
  #define EXENAMETAIL_SWP "-SWP"
  #define EXENAMETAIL_SFX "-SFX"
  #define EXENAMETAIL_ECHO "-echo"
 #else
  #define EXENAMETAIL_NORMAL "-normal"
  #define EXENAMETAIL_MEDIUM "-medium"
  #define EXENAMETAIL_LIGHT "-light"
  #define EXENAMETAIL_EXTRA "-extra"
  #define EXENAMETAIL_BARE "-bare"
  #define EXENAMETAIL_DEMO "-demo"
 #endif

//#define EXENAME EXENAMESTART EXENAMETAIL
 enum PlayerTypeIDs { PLAYERID_NORMAL=0, PLAYERID_MEDIUM=1, PLAYERID_LIGHT=2, PLAYERID_EXTRA=3, PLAYERID_BARE=4, PLAYERID_DEMO=5 };
 enum TuningTypeIDs { TUNINGID_EQUALTEMPERED=0, TUNINGID_VERDITUNING=1, TUNINGID_JUSTINTONATION=2, TUNINGID_DREAN=3 };


typedef unsigned char byte; //typedef uint8_t byte;
typedef unsigned short word; //typedef uint16_t word;


void SIDwizard_resetEngine (char processor_reset, char soundpipe_reset);


#endif //DEFINED_HEADER__SIDWIZARD