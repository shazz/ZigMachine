//SID-Wizard emulation environment by Hermit (Year 2022)

#include <limits.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <libgen.h>
#include <math.h>
#ifdef SIDMAKER
 #include <time.h>
#endif

#ifdef _WINDOWS
 #include <windows.h>
 #include <tchar.h>
 #define realpath(N,R) _fullpath((R),(N),_MAX_PATH)
#endif

#include "SIDwizard.h"


//static char SIDamount = 1; //moved to cRSID_C64
#ifdef SIDMAKER
static char ROMsupport = 0, SWPsupport = 0, SFXsupport = 0, EchoSupport = 0;
#endif
static char DriverTypePos=TUNE_DRIVERTYPE_POS_1SID, TuningTypePos=TUNE_TUNINGTYPE_POS_1SID;
static char *WorkfileExtension = WORKFILE_EXTENSION_1SID, *MagicString = MAGICSTRING_1SID;

static int ArgFileDataSize = 0;
static int ArgMainVolume=0;
static byte MIDIturnedOn=0, PrevMIDIturnedOn=0xFF, ButtonChange=0;
static byte ArgMIDIname[MIDI_NAME_LENGTH_MAX+1]=""; // "Midi Through";

#if ( defined(LINUX) || defined(_LINUX) )
static char VideoDriverFBCON = 0, VideoDriverNonX11 = 0;
#endif

static char GUImode=0;  //TUI-mode and GUI-mode are mutually exclusive
static char TUImode=
#if (ENABLED_SDL)
 0
#else
 #if (ENABLED_TUI)
  1
 #else
  0
 #endif
#endif
 ;


#if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
 enum { NCURSES_KEY_NONE = -1, SETTING_AMOUNT = 4 };
 static int TUIkeyCode = NCURSES_KEY_NONE;
 static signed char DvorakKeybardLayout = 0;
 static signed char SettingMenu = 0, ChosenSetting = 0;
#endif

byte ShiftedKeypressSim=0, CBMkeypressSim=0;
static byte PianoKeyScanCodeRow, PianoKeyScanCodeColumn;
static byte BorderAlias;
signed char Zoom=ZOOM_DEFAULT;


static const char* ExitDialogText =  "                                        \n"
                                     " ************************************** \n"
                                     " * DO YOU REALLY WANT TO EXIT?  (Y/N) * \n"
                                     " ************************************** \n"
                                     "                                        ";


#include "libcRSID/libcRSID.h"
#include "libcRSID/C64/C64.h" //#include "libcRSID/libcRSID.c"
//#include "libcRSID/Optimize.h"

extern cRSID_C64instance cRSID_C64;
static cRSID_C64instance *C64 = &cRSID_C64;

#include "host/file.c"
#include "host/video.c"
#if (ENABLED_SDL)
 #include "host/mouse.c"
#endif
#include "host/keyboard.c"
#if (MIDI==1)
 #include "host/midi.c"
#endif



void SIDwizard_resetEngine (char processor_reset, char soundpipe_reset) {
 enum { SAMPLE_SEND_RETRY_DELAY = 1000 }; //microseconds  (so in case of error the machine doesn't run at 100% in loop)
 cRSID_stopSound(); cRSID.Paused = 1;
 if (soundpipe_reset) cRSID_closeSound(); //with following cRSID_initSound() ensures complete revival of a possibly thrown-away ALSA (e.g. error -32 'broken pipe' which stops sound and C64 emulation completely)
 usleep( SAMPLE_SEND_RETRY_DELAY );
 if (processor_reset) {
  usleep( SOUND_DELAY_MAX*2 * MICROSECONDS_IN_A_MILLISECOND ); //SDL_Delay(SOUND_DELAY_MAX); //wait for emulation in audio-thread to surely cease
  cRSID_initCPU( /*&C64->CPU,*/ SAFESTART_ADDRESS ); C64->Finished=0; C64->Returned=0;
  /*ArgFileIdx =*/ ArgFileDataSize = ArgLoading = 0; ArgFileNamePtr = NULL;
 }
 if (soundpipe_reset) cRSID_initSound(cRSID_C64.SampleRate, cRSID.SampleBufferLength); //ensures complete revival of a possibly thrown-away ALSA (e.g. error -32 'broken pipe' which stops sound and C64 emulation completely)
 cRSID_startSound(); cRSID.Paused = 0;
}


static void changeSIDmodel () {
 cRSID.SelectedSIDmodel = (cRSID.SelectedSIDmodel==8580)? 6581:8580;
 #ifndef SIDMAKER
  cRSID_C64.SID[1].ChipModel = cRSID_C64.SID[2].ChipModel = cRSID_C64.SID[3].ChipModel = cRSID_C64.SID[4].ChipModel = cRSID.SelectedSIDmodel;
 #endif
}

static void changeMIDIinputDevice (char direction) {
 #ifndef SIDMAKER
   if (MIDIturnedOn) {
    #if (MIDI)
    closeMIDI();
    initMIDI(direction);
    #endif
   }
 #endif
}



int main (int argc, char* argv[]) {
 int i,j,data, MinimumBufferSize = BUFFERSIZE_MIN;
 #ifndef SIDMAKER  //SID-Wizard
  int ArgPlayerType=-1;
  byte WishedPlayerType = 0;  //wished startup-menu playertype (to select automatically), will be playertype of opened file or forced playertype, given as argument
 #endif
 byte FilePlayerType=0,FileTuningType=0, ArgFileIdx=1, StartupMenu = 1, ExitDialog = 0;
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
 static byte KeyHoldTimer = 0;
 #endif
 FILE *fp; byte ArgFileData[65536]; static char fullpath[PATH_MAX+1]; static char* fullpathptr;
 #if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)
 static SDL_Event Event;
 #endif
 static char done=0;
 #ifdef SIDMAKER
  static time_t CurrentTime; static char* TimeString; static signed char TimeUpdateCnt=0;
 #endif

 #ifndef SIDMAKER
  static short KeySimEditorWaitCnt=KEYSIM_EDITORWAIT;
  byte /*ConfigPlayerType=0xFF,SelectedPlayerType=0,*/PlayerSelected=0, TuningSelected=0;
 #endif
 static short KeySimRepeatDelay = KEYSIM_REPEATDELAY, KeySimPressDuration = KEYSIM_PRESSDURATION;
 static short KeySimStartupDelayCnt=KEYSIM_STARTUPDELAY, KeySimRepeatDelayCnt=KEYSIM_REPEATDELAY;
 byte LoadKeyCnt=0;


 #if ( defined(_WINDOWS) || defined(WINDOWS) ) //preventing creation of txt files in the app's folder
  SDL_putenv("SDL_STDIO_REDIRECT=no");
  //freopen("CON", "w", stdout);
  //freopen("CON", "w", stderr);
  //etc:
  getcwd(fullpath, PATH_LENGTH_MAX);
 #endif


 #ifdef SIDMAKER
  ROMsupport=0; SWPsupport=0; SFXsupport=0; EchoSupport=0;
  if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM "-2SID" ) || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM "-3SID" )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM "-4SID" ) ) ROMsupport = 1;
  else if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM EXENAMETAIL_SWP )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM EXENAMETAIL_SWP "-2SID" ) || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM EXENAMETAIL_SWP "-3SID" )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_ROM EXENAMETAIL_SWP "-4SID" ) ) { ROMsupport = SWPsupport = 1; }
  else if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-2SID" ) || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-3SID" )
       || !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-4SID" ) ) SWPsupport = 1;
  else if ( !strcmp( basename(argv[0]),  EXENAME EXENAMETAIL_SFX ) ) SFXsupport = 1;
  else if ( !strcmp( basename(argv[0]),  EXENAME EXENAMETAIL_ECHO ) ) EchoSupport = 1;
 #endif

 cRSID_C64.SIDchipCount = 1;  //the default, whatever name and tail is given
 for (i=1; i < sizeof(ExeNames)/sizeof(char*); ++i) {  //printf( "--%s--%s--\n", basename(argv[0]), ExeNames[i] );
  if ( !strcmp( basename(argv[0]),  ExeNames[i] /*EXENAME EXENAMETAIL_1SID*/ ) )
  { cRSID_C64.SIDchipCount = i; break; }
 }
 #ifndef SIDMAKER
 for (i=1; i < sizeof(ExeNames)/sizeof(char*); ++i) {  //printf( "--%s--%s--\n", basename(argv[0]), ExeNames[i] );
  if ( !strcmp( basename(argv[0]),  ExeNames_GUI[i] /*EXENAME EXENAMETAIL_GUI EXENAMETAIL_1SID*/ ) )
  { cRSID_C64.SIDchipCount = i; GUImode=1; TUImode=0; break; }  //TUI-mode and GUI-mode are mutually exclusive
 }
 for (i=0; i < sizeof(ExeNames_PlayerType)/sizeof(char*); ++i) { //check playertype (too) in the name (currently only for 1SID variant)
  if ( !strcmp( basename(argv[0]),  ExeNames_PlayerType[i] /*EXENAME EXENAMETAIL_NORMAL*/ ) )
  { ArgPlayerType = i; break; }
  if ( !strcmp( basename(argv[0]),  ExeNames_GUI_PlayerType[i] /*EXENAME EXENAMETAIL_GUI EXENAMETAIL_NORMAL*/ ) )
  { ArgPlayerType = i; GUImode=1; TUImode=0; break; }  //TUI-mode and GUI-mode are mutually exclusive
 }
 #endif

 #ifdef SIDMAKER
  if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-2SID" ) ) cRSID_C64.SIDchipCount = 2;
  else if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-3SID" ) ) cRSID_C64.SIDchipCount = 3;
  else if ( !strcmp( basename(argv[0]), EXENAME EXENAMETAIL_SWP "-4SID" ) ) cRSID_C64.SIDchipCount = 4;
 #endif
 updateSIDamount( cRSID_C64.SIDchipCount );

 cRSID.SampleBufferLength = DEFAULT_BUFFERSIZE;

 i=1;
 while (i<argc) {  //(don't forget to add all of these arguments below into the exclusion list of the other arg-loop)  //printf( "--%s--\n", argv[i] );
  if (!strcmp(argv[i],"-h") || !strcmp(argv[i],"-?") || !strcmp(argv[i],"-help") || !strcmp(argv[i],"--h") || !strcmp(argv[i],"--help")) {
   printf("Usage: "EXENAME" [-h] [-2SID|-3SID|-4SID"
    #ifdef SIDMAKER
     "|-ROM|-SWP|-SFX|-echo"
    #endif
    "] [-tui|-gui] [-normal|-medium|-light|-extra|-bare|-demo] [-zoom1|-zoom2|-zoom3|-zoom4] [-lofiborder|-hqborder] [-sid6581|-sid8580] [-stereo|-mono|-narrow] [-volume <0..255>] [-dvorak] [[path]filename] [directory] [-drive9 directory] [-bufsize <samplecount>]\n");
  }
  else if (!strcmp(argv[i],"-1SID")) { updateSIDamount(1); }
  else if (!strcmp(argv[i],"-2SID"/*EXENAMETAIL_2SID*/)) { updateSIDamount(2); }
  else if (!strcmp(argv[i],"-3SID"/*EXENAMETAIL_3SID*/)) { updateSIDamount(3); }
  else if (!strcmp(argv[i],"-4SID"/*EXENAMETAIL_4SID*/)) { updateSIDamount(4); }
  #ifdef SIDMAKER
   else if (!strcmp(argv[i],"-ROM"/*EXENAMETAIL_ROM*/)) { ROMsupport = 1; }
   else if (!strcmp(argv[i],"-SWP"/*EXENAMETAIL_SWP*/)) { SWPsupport = 1; }
   else if (!strcmp(argv[i],"-SFX"/*EXENAMETAIL_SFX*/)) { SFXsupport = 1; }
   else if (!strcmp(argv[i],"-echo"/*EXENAMETAIL_ECHO*/)) { EchoSupport = 1; }
  #endif
  else if (!strcmp(argv[i],"-buflen") || !strcmp(argv[i],"-bufsize")) { //'bufsize' was a bit misleading because 'size' usually means the amount of bytes, but 'length' correctly the amount of objects (samples/frames)
   ++i;
   if(i<argc) {
    sscanf(argv[i],"%d",&cRSID.SampleBufferLength);
    //MinimumBufferSize = SAMPLERATE /*cRSID_C64.SampleRate*/ * SAMPLEBUFFER_UPDATE_PERIOD / MILLISECONDS_IN_A_SECOND
    if (cRSID.SampleBufferLength < MinimumBufferSize) cRSID.SampleBufferLength = (MinimumBufferSize / 256) + 256; //if(cRSID.BufferSize<256) cRSID.BufferSize=256;
    if (BUFFERSIZE_MAX<cRSID.SampleBufferLength) cRSID.SampleBufferLength=(BUFFERSIZE_MAX / 256) - 256;  //if (4096<cRSID.BufferSize) cRSID.BufferSize=4096;
   }
  }
  ++i;
 }


 initDiskIO(); //system("pwd");

 ArgMIDIname[0]='\0';

 cRSID.SelectedSIDmodel=8580; cRSID.Stereo=CRSID_CHANNELMODE_MONO; cRSID.HighQualitySID=1; /*cRSID_C64.*/BorderAlias=0; //default model and mode
 C64 = cRSID_init( DEFAULT_SAMPLERATE, cRSID.SampleBufferLength ); //DEFAULT_BUFFERSIZE );


 SIDwizardFolderName = getSIDwizardFolderPath();
 if ( !folderExists( SIDwizardFolderName ) ) {
  if ( mkdir( SIDwizardFolderName
  #ifndef WINDOWS
   , 0777
  #endif
  ) == -1 ) printf( "Couldn't create an optional SID-Wizard folder \"%s\" for config/etc.\n", SIDwizardFolderName );
  else printf( "SID-Wizard folder \"%s\" for config/etc got created.\n", SIDwizardFolderName );
 }
 loadConfigFile();  updateZoom();


 ArgFileDataSize=0;
 #ifndef SIDMAKER
  PlayerSelected=TuningSelected=0; //will tell if there's file to open
 #endif

 i=ArgFileIdx=1; getcwd(StartUpPath,PATH_LENGTH_MAX); if ( !strcmp(C64drivePaths[0],".") ) strcpy(C64drivePaths[0],StartUpPath);

 while (i<argc) {  //printf( " --%s--\n", argv[i] );
  if ( //excluding here the arguments already handled above:
       !strcmp(argv[i],"-h") || !strcmp(argv[i],"-?") || !strcmp(argv[i],"-help") || !strcmp(argv[i],"--h") || !strcmp(argv[i],"--help")
       || !strcmp(argv[i],"-buflen") || !strcmp(argv[i],"-bufsize")
       #ifdef SIDMAKER
        || !strcmp(argv[i],"-ROM") || !strcmp(argv[i],"-SWP") || !strcmp(argv[i],"-SFX") || !strcmp(argv[i],"-echo")
       #endif
       || !strcmp(argv[i],"-1SID") || !strcmp(argv[i],"-2SID") || !strcmp(argv[i],"-3SID") || !strcmp(argv[i],"-4SID") ) ; //handled above before cRSID_init(), it's here just to avoid treating these as filenames
  else if ( !strcmp(argv[i],"-tui") || !strcmp(argv[i],"-cli") || !strcmp(argv[i],"-TUI") || !strcmp(argv[i],"-CLI") ) {
   #if (ENABLED_TUI)
   TUImode=1; GUImode=0;  //TUI-mode and GUI-mode are mutually exclusive
   #else
    printf( "\nWarning: TUI (ncurses) support is not compiled into this runnable. Starting C64-UI.\n\n" );
   #endif
  }
  else if ( !strcmp(argv[i],"-GUI") || !strcmp(argv[i],"-gui") ) { GUImode=1; TUImode=0; }  //TUI-mode and GUI-mode are mutually exclusive
  #ifndef SIDMAKER  //SID-Wizard:
  else if (!strcmp(argv[i],"-normal"/*EXENAMETAIL_NORMAL*/)) { ArgPlayerType = 0; } //if set, startup menu automatically selects it
  else if (!strcmp(argv[i],"-medium"/*EXENAMETAIL_MEDIUM*/)) { ArgPlayerType = 1; }
  else if (!strcmp(argv[i],"-light"/*EXENAMETAIL_LIGHT*/)) { ArgPlayerType = 2; }
  else if (!strcmp(argv[i],"-extra"/*EXENAMETAIL_EXTRA*/)) { ArgPlayerType = 3; }
  else if (!strcmp(argv[i],"-bare"/*EXENAMETAIL_BARE*/)) { ArgPlayerType = 4; }
  else if (!strcmp(argv[i],"-demo"/*EXENAMETAIL_DEMO*/)) { ArgPlayerType = 5; }
  #endif
  else if (!strcmp(argv[i],"-zoom1")) { Zoom=1; updateZoom(); }
  else if (!strcmp(argv[i],"-zoom2")) { Zoom=2; updateZoom(); }
  else if (!strcmp(argv[i],"-zoom3")) { Zoom=3; updateZoom(); }
  else if (!strcmp(argv[i],"-zoom4")) { Zoom=4; updateZoom(); }
  else if (!strcmp(argv[i],"-lofiborder")) { /*cRSID_C64.*/BorderAlias=1; }
  else if (!strcmp(argv[i],"-hqborder")) { /*cRSID_C64.*/BorderAlias=0; }
  //else if (!strcmp(argv[i],"-positional")) { } //key-layout the same as positional in VICE
  else if (!strcmp(argv[i],"-sid6581")) { cRSID.SelectedSIDmodel=6581; }
  else if (!strcmp(argv[i],"-sid8580")) { cRSID.SelectedSIDmodel=8580; }
  else if (!strcmp(argv[i],"-mono"))   { cRSID.Stereo = CRSID_CHANNELMODE_MONO; } //mono/stereo
  else if (!strcmp(argv[i],"-stereo") || !strcmp(argv[i],"-narrow")) { cRSID.Stereo = CRSID_CHANNELMODE_NARROW; } //narrow stereo
  else if (!strcmp(argv[i],"-wide")) { cRSID.Stereo = CRSID_CHANNELMODE_STEREO; } //mono/stereo
  else if (!strcmp(argv[i],"-sidlight")) { cRSID.HighQualitySID=0; } //low-quality combined waveform, much less CPU-usage
  else if (!strcmp(argv[i],"-sidhq")) { cRSID.HighQualitySID=1; cRSID.HighQualityResampler=0; } //high-quality SID with 1MHz wavesample-rate (5.5x oversampling, good for combined waveforms)
  else if (!strcmp(argv[i],"-sinc")) { cRSID.HighQualitySID=1; cRSID.HighQualityResampler=1; }
  else if (!strcmp(argv[i],"-mididev")) { ++i; if(i<argc) strncpy((char*)ArgMIDIname,argv[i],MIDI_NAME_LENGTH_MAX); }  //MIDI input-port?
  else if (!strcmp(argv[i],"-drive8")) { ++i; if(i<argc) {strcpy(C64drivePaths[0],argv[i]); chdir(argv[i]);} }
  else if (!strcmp(argv[i],"-drive9")) { ++i; if(i<argc) strcpy(C64drivePaths[1],argv[i]); }
  else if (!strcmp(argv[i],"-drive10")) { ++i; if(i<argc) strcpy(C64drivePaths[2],argv[i]); }
  else if (!strcmp(argv[i],"-drive11")) { ++i; if(i<argc) strcpy(C64drivePaths[3],argv[i]); }
  else if (!strcmp(argv[i],"-drive12")) { ++i; if(i<argc) strcpy(C64drivePaths[4],argv[i]); }
  else if (!strcmp(argv[i],"-drive13")) { ++i; if(i<argc) strcpy(C64drivePaths[5],argv[i]); }
  else if (!strcmp(argv[i],"-drive14")) { ++i; if(i<argc) strcpy(C64drivePaths[6],argv[i]); }
  else if (!strcmp(argv[i],"-drive15")) { ++i; if(i<argc) strcpy(C64drivePaths[7],argv[i]); }
  else if (!strcmp(argv[i],"-dvorak")) { DvorakKeybardLayout = 1; }
  else if (!strcmp(argv[i],"-volume") || !strcmp(argv[i],"-mainvolume")) {
   ++i;
   if(i<argc) {
    sscanf(argv[i],"%d",&ArgMainVolume);
    if(ArgMainVolume<0) cRSID.MainVolume=0;
    else if(255<ArgMainVolume) cRSID.MainVolume=255;
    else cRSID.MainVolume = ArgMainVolume;
   }
  }
  else if ( !strcmp(filExt((byte*)argv[i]),WorkfileExtension) ) { //check file-extension and/or magic-string!
   ArgFileIdx=i;
   #ifdef _LINUX
    //fullpathptr=realpath(argv[i],fullpath); printf("--%s--%s--%s-----%s--%s--\n",argv[i],fullpath,fullpathptr,filExt(argv[i]),WorkfileExtension);
    //if ( /*fullpathptr!=NULL &&*/ (fp=fopen(argv[i],"rb")) != NULL ) {
   #elif defined (_WINDOWS)
    strcpy(C64drivePaths[0],fullpath); chdir(fullpath); //fullpathptr=realpath(argv[i],fullpath); //printf("--%s--%s--%s-----%s--%s--\n",argv[i],fullpath,fullpathptr,filExt(argv[i]),WorkfileExtension);
    //if ( fullpathptr!=NULL && (fp=fopen(fullpath,"rb")) != NULL ) {
   #endif
   if ( /*fullpathptr!=NULL &&*/ (fp=fopen(argv[i],"rb")) != NULL ) {
    fgetc(fp);fgetc(fp); //skip prg-header (loadaddress)
    while ( (data=fgetc(fp)) != EOF ) {
     ArgFileData[ArgFileDataSize]=data; ++ArgFileDataSize; //printf("%2.2X ",data);
    }
    fclose(fp);
    for(j=0;j<4;++j) if(ArgFileData[j]!=MagicString[j]) { printf("FileType of \"%s\" doesn't match.\n",argv[i]); ArgFileDataSize=0; break; } //printf("%d\n",ArgFileDataSize);
    if (ArgFileDataSize>0) { FilePlayerType=ArgFileData[DriverTypePos/*TUNE_DRIVERTYPE_POS*/]; FileTuningType=ArgFileData[TuningTypePos/*TUNE_TUNINGTYPE_POS*/]; }
   }
   else { printf( "Couldn't find file \"%s\" given as argument.\n", argv[i] ); }
  } //printf("\n%d (playertype:%d)\n",ArgFileDataSize,ArgFileData[DRIVERTYPE_POS]);
  else { strcpy(C64drivePaths[0],argv[i]); chdir(argv[i]); }
  ++i;
 }

 #ifdef SIDMAKER
 if (ArgFileDataSize>0) ArgFileNamePtr=argv[ArgFileIdx];
 #endif

 if (C64==NULL) exit(CRSID_ERROR_INIT);
 cRSID_setC64(C64); cRSID_initC64(C64); C64->RAMbank[1] = 0x34;

 cRSID_initCPU( /*&C64->CPU,*/ PROGRAMSTART_ADDRESS ); C64->Finished=0; C64->Returned=0; cRSID.RealSIDmode = 1;
 initKeyStates();  //cRSID_C64.ScanCodeRow = cRSID_C64.ScanCodeColumn = 0xF;  //init keys before soundstart, because sound includes keymatrix-check before GetKeyState

 loadNativeC64code();

 //printf("startsnd\n");
 cRSID_startSound(); cRSID.Paused = 0; //init keys before soundstart, because sound includes keymatrix-check before GetKeyState
 //if(SoundStarted==0) exit(CRSID_ERROR_INIT);

 //printf("initui\n");
 initUI(); //must be after startsound? (otherwise sometimes the callback doesn't start (clash with SetVideoMode?)
 #if ( ENABLED_SDL_EVENTS && (defined(LINUX) || defined(_LINUX)) )
  if (VideoDriverFBCON /*|| VideoDriverNonX11*/) {
   SDLscanCodeToC64key = SDLscanCodeToC64keyFBCON; //SDLscanCodeToC64keyNonX11;
   OS_SCANCODESUB = OS_SCANCODESUB_FBCON;
  }
 #endif

 #if (MIDI==1)
  //initMIDI();
 #endif

 if (TUImode || GUImode) {
  KeySimStartupDelayCnt = SPLASH_TO_KEYSIM_DELAY; //don't add splash-logo wait-time in SDL-app's TUI- or GUI-mode
  //KeySimEditorWaitCnt = KEYSIM_EDITORWAIT_TUI;
  //KeySimRepeatDelay = KEYSIM_REPEATDELAY_TUI; KeySimRepeatDelayCnt = KeySimRepeatDelay;
  //KeySimPressDuration = KEYSIM_PRESSDURATION_TUI;
 }



 //Main loop:  //printf("startlp\n");


 while (!done) { //printf("loopbeg\n");

  if ( MOSTLY (VICbankBars[INSCREEN_RASTER] != 3) ) { StartupMenu = 0; } //from now on Shift+F9 can be used to reset editor (or file-dialog)

  #if (!FORCED_SDL_EVENTS)
  if (!TUImode)
  #endif
  {
   #if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)

   while ( SDL_PollEvent( &Event ) ) {
    if ( RARELY (Event.type == SDL_QUIT) ) {
     //SDL_PumpEvents(); cRSID_C64.KeyStates=SDL_GetKeyState(NULL);
     //if ( !cRSID_C64.KeyStates[SDLK_LALT] && !cRSID_C64.KeyStates[SDLK_RALT] && !cRSID_C64.KeyStates[SDLK_F4] )
      done=1;
    }
    else if ( RARELY (ExitDialog) ) {
     if (ExitDialog==1 && Event.type == SDL_KEYDOWN) {
      if (Event.key.keysym.sym == SDLK_y) { done = 1; break; }
      else { ExitDialog = 2; }
     }
     else if (ExitDialog == 2 && Event.type == SDL_KEYUP) {
      ExitDialog = 0; cRSID.Paused = 0; cRSID_startSound(); displayScreen( DISPLAY_REFRESH_CODE ); continue;
     }
     SDL_Delay(KEYSCAN_PERIOD); continue;
    }
    else if ( MOSTLY (Event.type==SDL_KEYDOWN) ) {
     /*cRSID_C64.*/ScanCode=Event.key.keysym.scancode;  //printf( "keycode: $%2.2X scancode: %d($%2.2X)  (\'%c\') \n", Event.key.keysym.sym, ScanCode, ScanCode, Event.key.keysym.sym );
     switch (Event.key.keysym.sym) {
      //case SDLK_ESCAPE: done=1; break;
      case SDLK_F9: case SDLK_F7: { //reset editor (e.g. in case of freeze)
       if ( (SDL_GetKeyState(NULL)[SDLK_LSHIFT/*SDLK_LALT*/] || SDL_GetKeyState(NULL)[SDLK_RSHIFT]) && ArgLoading==0 && !StartupMenu/*&& disable in startup-menu too*/) {
        SIDwizard_resetEngine(1,0);
       }
       break;
      }
      case SDLK_F8: {  //exit-dialog
       if ( (SDL_GetKeyState(NULL)[SDLK_LSHIFT/*SDLK_LALT*/] || SDL_GetKeyState(NULL)[SDLK_RSHIFT]) && ArgLoading==0 ) {
        ExitDialog = 1; cRSID.Paused=1; cRSID_stopSound();  //printf( "%s\n", ExitDialogText );
        drawString( 0, SCREENHEIGHT/2, ExitDialogText, 0x80E0FF, 0x031020 ); //displayScreen( DISPLAY_EXITDIALOG_CODE ); //DISPLAY_REFRESH_CODE );
        continue; break;
       }
      }
      case SDLK_UP: { //increase Main Volume
       if (ShiftPressed /*|| CtrlPressed*/) { volumeUp(); }
       break;
      }
      case SDLK_F12: volumeUp(); break; //alternative key to increase Main Volume (supported in linux fbcon terminal)
      case SDLK_DOWN: { //decrease Main Volume
       if (ShiftPressed /*|| CtrlPressed*/) { volumeDown(); }
       break;
      }
      case SDLK_F11: volumeDown(); break; //alternative key to decrease Main Volume (supported in linux fbcon terminal)
     }
    }
    else if (Event.type==SDL_KEYUP && Event.key.keysym.scancode==/*cRSID_C64.*/ScanCode) /*cRSID_C64.*/ScanCode=0;
    else if (Event.type == SDL_MOUSEBUTTONDOWN && (Event.button.button==SDL_BUTTON_LEFT || Event.button.button==SDL_BUTTON_RIGHT) ) {
     MouseClickX=floor((Event.button.x-SIDEBORDER_WIDTH)/(float)CharWidth);
     MouseClickY=(Event.button.y-BorderHeight)/CharHeight; //if(MouseClickY<0)MouseClickY=0; //printf("%d,%d\n",MouseClickX,MouseClickY);
     #ifndef SIDMAKER
     if (GUImode && 0 <= MouseClickX && MouseClickX < PIANOROLL_TOGGLE_BUTTON_CHARWIDTH && MouseClickY < 0) {
      PianoRollMode ^= 1;
     }
     else
     #endif
     if (VICbankBars[INSCREEN_RASTER]!=3) {  //editor screen?
      MouseClicked=1; MouseKeyPressDurationCnt=MOUSEKEYPRESS_DURATOIN; FirstPress=1;
     }
     ButtonClickY=(Event.button.y-Zoom)/CHARHEIGHT;
     if(MouseClickX<0) { //setting button pressed
      for(i=0; i < (int)sizeof(ButtonBots); ++i) { if(ButtonTops[i]<=ButtonClickY && ButtonClickY<=ButtonBots[i]) break; } //printf("%d\n",i);
      switch (i) {
       case 0: //zoom
        if (!VideoDriverFBCON) { //don't allow live-resizing in linux framebuffer-console (leaves trails if decreased, gives sigfault if increased bigger than framebuffer)
         if (Event.button.button==SDL_BUTTON_LEFT) { if(Zoom<ZOOM_MAX) ++Zoom; else Zoom=ZOOM_MIN; }  //(still possible to set at startup with '-zoom' argument)
         else { if(Zoom>ZOOM_MIN) --Zoom; else Zoom=ZOOM_MAX; }
         updateZoom(); resizeUI();
        }
        break;
       case 1: //borderaliasing
         /*cRSID_C64.*/BorderAlias = /*cRSID_C64.*/BorderAlias ? 0:1;
         if (!GUImode) drawBigSprites(TOPSPRITE_ADDRESS,Zoom,0x00);
        break;
       case 2: //sidmodel
        changeSIDmodel();
        break;
       case 3: //sidquality
         cRSID.HighQualitySID = cRSID.HighQualitySID? 0:1;  cRSID.HighQualityResampler=0; //Sinc-mode turned off because it's noisy sometimes
        break;
       //#if (SIDAMOUNT>1)
       case 4: //mono/stereo
        /*if (cRSID_C64.SIDchipCount>1)*/ {  //cRSID.Stereo = cRSID.Stereo? 0:1; break;  //cRSID.Stereo ^= 1;
        cRSID.Stereo = cRSID.Stereo == CRSID_CHANNELMODE_MONO ? CRSID_CHANNELMODE_NARROW :
                   (cRSID.Stereo == CRSID_CHANNELMODE_STEREO ? CRSID_CHANNELMODE_MONO : CRSID_CHANNELMODE_STEREO);
       } break;
       case 5:
       /*#else
       case 4: //mono/stereo
       #endif*/
        if (Event.button.button==SDL_BUTTON_LEFT) changeMIDIinputDevice(1);
        else if (Event.button.button==SDL_BUTTON_RIGHT) changeMIDIinputDevice(2);
        break;
      }
     }
    }
    else if (Event.button.button==SDL_BUTTON_WHEELUP) {
     if (Event.button.x >= SIDEBORDER_WIDTH+WinWidth) { if (Event.button.y < BorderHeight) volumeUp(); }
     else if (VICbankBars[INSCREEN_RASTER]!=3 && Event.button.y >= BorderHeight) { MouseWheelUp=1; MouseKeyPressDurationCnt=MOUSEWHEELKEYPRESS_DURATOIN; }
    }
    else if (Event.button.button==SDL_BUTTON_WHEELDOWN) {
     if (Event.button.x >= SIDEBORDER_WIDTH+WinWidth) { if (Event.button.y < BorderHeight) volumeDown(); }
     else if (VICbankBars[INSCREEN_RASTER]!=3 && Event.button.y >= BorderHeight) { MouseWheelDown=1; MouseKeyPressDurationCnt=MOUSEWHEELKEYPRESS_DURATOIN; }
    }
   }
   if ( RARELY (ExitDialog) ) { SDL_Delay(KEYSCAN_PERIOD); continue; }
   if ( RARELY (done) ) break;

   SDL_PumpEvents(); //printf("getkey\n");
   #endif //ENABLED_SDL_EVENTS
  } // (!TUImode) end of SDL-UI-mode condition


  #if (ENABLED_TUI_KEYS)
  else if ( RARELY (!ArgLoading) ) { //TUImode
   #if  (ENABLED_TUI) //(ENABLED_NCURSES)
   data = getch();
   if (data != ERR) {  //mvprintw(30,0,"%d($%X)\n"/*,'%c')\n"*/,data,data); //,data);//data); //,getch()); //else printf("-\n");
    if (data == KEY_RESIZE) { displayScreen( DISPLAY_INIT_CODE ); displayScreen( DISPLAY_REFRESH_CODE ); } //refresh(); }
    else if ( /*data == KEY_EXIT ||*/ data == NCURSES_KEYCODE_SHIFT_F8 || /*data == NCURSES_KEYCODE_SHIFT_F10 ||*/ data == NCURSES_KEYCODE_CTRL_F8 ) { //|| data == NCURSES_KEYCODE_CTRL_F10 ) { // /*|| data == NCURSES_KEYCODE_CTRL_C || data == TUI_CTRL+'d' ||*/ /* (data==NCURSES_KEYCODE_ALT && getch() == KEY_F(10))*/ /*|| (data == NCURSES_KEYCODE_ESC && ERR)*/ /*|| data == 'q'*/ //if no other key after ESC it's really an ESC not an ALT with the same code
     //color_set( 1 + 1 *COLOR_AMOUNT + CURSOR_COLORS, NULL ); attron( A_BOLD );
     printColoredTUIstring( TUI_INSCREEN_X + 0, SCREENHEIGHT/2-3, ExitDialogText, 1 + 1 *COLOR_AMOUNT + CURSOR_COLORS, 1 ); //mvaddstr( SCREENHEIGHT/2-3, TUI_INSCREEN_X + 0, ExitDialogText );
     refresh();
     cRSID.Paused = 1;
     #if (ENABLED_ALSA)
      cRSID_closeSound(); //avoid buffer-dropout errors while we're waiting in Y/N loop
     #endif
     while ( (data=getch()) == ERR ) usleep( KEYSCAN_PERIOD_MICROSECONDS );
     if ( data == 'y' || data == 'Y' /* exit even with accidental Caps-lock */ ) { done = 1; break; }
     else {
      #if (ENABLED_ALSA)
       cRSID_initSound( cRSID_C64.SampleRate, cRSID.SampleBufferLength ); //buffer drained during Y/N dialog to avoid plain-ALSA problems or segfault, now turning it back on
      #endif
      cRSID.Paused = 0;
      displayScreen( DISPLAY_REFRESH_CODE );
     }
    }
    else if (data == NCURSES_KEYCODE_CTRL_F10) { done = 1; break; }
    else if ( (data == NCURSES_KEYCODE_SHIFT_F9 || data == NCURSES_KEYCODE_SHIFT_F7) /*|| data == NCURSES_KEYCODE_ALT_F9*/ && !ArgLoading && !StartupMenu) {
     SIDwizard_resetEngine(1,1); //0);
    }
    else if (data == KEY_SF || data == KEY_F(11) /*|| data == NCURSES_KEYCODE_CTRL_DOWN || data == NCURSES_KEYCODE_CTRL_DOWN+1*/ || data == KEY_SNEXT ) volumeDown();
    else if (data == KEY_SR || data == KEY_F(12) /*|| data == NCURSES_KEYCODE_CTRL_UP || data == NCURSES_KEYCODE_CTRL_UP+1*/ || data == KEY_SPREVIOUS ) volumeUp();
    #ifndef SIDMAKER
    else if ( data == KEY_F(9) ) SettingMenu ^= 1;
    else if (SettingMenu && data == NCURSES_KEYCODE_ESC) SettingMenu = 0;
    else if (SettingMenu && data == KEY_DOWN) { if (++ChosenSetting >= SETTING_AMOUNT) ChosenSetting=0; }
    else if (SettingMenu && data == KEY_UP) { if (--ChosenSetting < 0) ChosenSetting=SETTING_AMOUNT-1; }
    else if (SettingMenu && data == '\r') {
     switch (ChosenSetting) {
      case 0: changeSIDmodel(); break;
      case 1: cRSID.HighQualitySID = cRSID.HighQualitySID? 0:1; cRSID.HighQualityResampler=0; break; //Sinc-mode turned off because it's noisy sometimes
      case 2: { //cRSID.Stereo = cRSID.Stereo? 0:1;
        cRSID.Stereo = cRSID.Stereo == CRSID_CHANNELMODE_MONO ? CRSID_CHANNELMODE_NARROW :
                   (cRSID.Stereo == CRSID_CHANNELMODE_STEREO ? CRSID_CHANNELMODE_MONO : CRSID_CHANNELMODE_STEREO);
      } break;
      case 3: changeMIDIinputDevice(1); break;
     }
    }
    #endif
    else {
     SettingMenu = 0;
     /*cRSID_C64.*/TUIkeyCode = data; KeyHoldTimer=TUI_KEYHOLD_KEYFRAMES; //(data != ERR) ? data : 0; //cRSID_C64.ScanCode = (data != ERR) ? convertNcursesKeyToScanCode( data ) : 0;
     /*if (CursorY >= SCREENHEIGHT) { //correction for vertical orderlist  --- done in SID-Wizard instead to handle subpositions correctly
      if (TUIkeyCode==KEY_DOWN) TUIkeyCode=KEY_RIGHT;  else if (TUIkeyCode==KEY_RIGHT) TUIkeyCode=KEY_DOWN;
      if (TUIkeyCode==KEY_UP) TUIkeyCode=KEY_LEFT;  else if (TUIkeyCode==KEY_LEFT) TUIkeyCode=KEY_UP;
     }*/
    }
   }
   else { //no key pressed
    //#ifndef SIDMAKER  //in SID-Maker keyhold that's OK in SID-Wizard, would cause relocation-address to count 2..3 time at first non-repeated keypress
    if (KeyHoldTimer > 0) --KeyHoldTimer; else
    //#endif
     TUIkeyCode = NCURSES_KEY_NONE;
   }
   #endif
  }
  #endif


  getKeyStates(); //EmulateKeyMatrix(); //keymatrix-emulation happens in C64-emulation functions/thread


  //printf("keysimtest\n");


  #ifndef SIDMAKER  //SID-Wizard:


  WishedPlayerType = (ArgPlayerType < 0) ? FilePlayerType : ArgPlayerType;  //if argument forces playertype, select it as 'wished'

  if ( RARELY (ArgFileDataSize>0 || ArgPlayerType >= 0) ) {  //if a file given as argument is read, SID-Wizard arg-file loading
   if (KeySimStartupDelayCnt>0) { ArgLoading=1; KeySimStartupDelayCnt--; }
   else if (ConfigPlayerType!=0xFF) { //loading config-file and waiting for startup-menu is over (ConfigPlayerType becomes other than initial $FF):

    if (KeySimStartupDelayCnt==0) { //startup-menu:
     if (KeySimRepeatDelayCnt>0) {  //simulate a keypress+keyrelease with delays, state-machine belows decides which key
      KeySimRepeatDelayCnt--;
      if (KeySimRepeatDelayCnt < KeySimRepeatDelay - KeySimPressDuration) { //keyrelease  //KEYSIM_PRESSDURATION) {
       simulateKey_DOWN(0); simulateKey_UP(0); simulateKey_RIGHT(0); simulateKey_RETURN(0); //printf("--\n"); //simulate key-off
      }
      else { //keypress state-machine  //if player and tuning doesn't match the default, select them:  //printf("%d-%d\n",SelectedPlayerType,WishedPlayerType);
       if (SelectedPlayerType<WishedPlayerType) { simulateKey_DOWN(1); } //printf("down\n"); } //simulate 'Cursor-down'
       else if (SelectedPlayerType>WishedPlayerType) { simulateKey_UP(1); } //printf("up\n"); }
       else if (SelectedPlayerType==WishedPlayerType && !PlayerSelected) { PlayerSelected=1; } //printf("enter\n"); } //simulate 'Enter'
       else if (SelectedTuningType!=FileTuningType) { simulateKey_RIGHT(1); }
       else if (SelectedTuningType==FileTuningType) { simulateKey_RETURN(1); TuningSelected=1; }
      }
     }
     else {  //perform task requested by the state-machine above on keypresses and phases, reset repeat-counter for next keypress
      if (PlayerSelected && TuningSelected) {  //selection made
       KeySimStartupDelayCnt=-1;  // <- go to editor-waiter section below  //KeySimRepeatDelayCnt=KEYSIM_REPEATDELAY;
       simulateKey_DOWN(0); simulateKey_UP(0); simulateKey_RIGHT(0); simulateKey_RETURN(0);
      }
      KeySimRepeatDelayCnt = KeySimRepeatDelay; //reset repeat-delay for next keypress-round  //KEYSIM_REPEATDELAY; //printf("%d-%d\n",SelectedPlayerType,WishedPlayerType);
      if (!PlayerSelected) {  //follow where we are in player-type selector (assuming keypresses above went fine)
       if (SelectedPlayerType<WishedPlayerType) ++SelectedPlayerType;
       else if (SelectedPlayerType>WishedPlayerType) --SelectedPlayerType;
      }
      else {  //follow where we are in tuning-selector (assuming keypresses above went fine)
       if (SelectedTuningType!=FileTuningType) { ++SelectedTuningType; if(SelectedTuningType>3) SelectedTuningType=0; }
      }
     }
    }

    else if (KeySimEditorWaitCnt>=0) {  //startup-menu time expired, so now load the file given as commandline-argument
     if (KeySimEditorWaitCnt>0) KeySimEditorWaitCnt--; //wait for the editor to wake up after startup-menu
     else { //editor woke up...
      if (ArgFileDataSize > 0) {  //file-loading by argument was requested
       if (KeySimRepeatDelayCnt>0) {
        KeySimRepeatDelayCnt--;
        if (KeySimRepeatDelayCnt < KeySimRepeatDelay - KeySimPressDuration) { //KEYSIM_PRESSDURATION) { //release keys for a time-interval of KEYSIM_PRESSDURATION frames
         simulateKey_F8(0); simulateKey_DOWN(0); simulateKey_RETURN(0); //printf("--\n"); //simulate key-off
        }
        else { //press keys for a time-interval of (KEYSIM_REPEATDELAY-KEYSIM_PRESSDURATION) frames
         if (LoadKeyCnt==0) { simulateKey_F8(1); } //printf("F8\n"); }
         else if (LoadKeyCnt==1) { simulateKey_DOWN(1); } // printf("down\n"); }
         else if (LoadKeyCnt==2) { simulateKey_RETURN(1); ArgFileNamePtr=(byte*)argv[ArgFileIdx]; } //printf("enter\n"); }
         else if (LoadKeyCnt==3) { simulateKey_RETURN(1); } //printf("enter\n"); }
         else if (LoadKeyCnt==4) {
          ArgLoading=0; KeySimEditorWaitCnt=-1;  // <- leave the keysimulator code and arg-file loading  //printf("ArgFile-Loading ended\n");
          simulateKey_F8(0); simulateKey_DOWN(0); simulateKey_RETURN(0);
         }
        }
       }
       else {
        KeySimRepeatDelayCnt = KeySimRepeatDelay; //TUImode? KEYSIM_REPEATDELAY_TUI : KEYSIM_REPEATDELAY;
        ++LoadKeyCnt;
       }
      }
      else {  //file-loading by argument was not requested, just selecting player-type
       ArgLoading=0; KeySimEditorWaitCnt=-1;  // <- leave the keysimulator (and arg-loading) code
      }
     }
    }

   }
  }
  else if ( RARELY (KeySimStartupDelayCnt>0) ) { KeySimStartupDelayCnt--; } //if no arg-file loaded, still count down and show splash-screen...


  #else  //#ifdef SIDMAKER  //#else //SID-Maker arg-file loading:  //#endif //end of non-SIDMAKER (SID-Wizard editor) arg-loading


  if ( RARELY (ArgFileDataSize>0) ) {
   if (KeySimStartupDelayCnt>0) { ArgLoading=1; KeySimStartupDelayCnt--; }
   if (KeySimStartupDelayCnt==0) {
    if (KeySimRepeatDelayCnt>0) {
     KeySimRepeatDelayCnt--;
     if (KeySimRepeatDelayCnt < KeySimRepeatDelay - KeySimPressDuration) { //KEYSIM_PRESSDURATION) {
      simulateKey_RETURN(0); ///*cRSID_C64.*/KeyStates[SDLK_RETURN]=0; //printf("--\n"); //simulate key-off
     }
     else { //printf("%d-%d\n",SelectedPlayerType,FilePlayerType);
      if (LoadKeyCnt==0) { simulateKey_RETURN(1); } ///*cRSID_C64.*/KeyStates[SDLK_RETURN]=1; }
      else if (LoadKeyCnt==1) {
       KeySimStartupDelayCnt=-1; ArgLoading=0;
       simulateKey_RETURN(0);  // /*cRSID_C64.*/KeyStates[SDLK_RETURN]=0;
      }
     }
    }
    else {
     KeySimRepeatDelayCnt=KEYSIM_REPEATDELAY; ++LoadKeyCnt;
    }
   }
  }
  else if ( RARELY (KeySimStartupDelayCnt>0) ) { KeySimStartupDelayCnt--; } //if no arg-file loaded, still count down and show splash-screen...


 #endif //SIDMAKER selections


  //printf("diskio\n");
  handleDiskIO();
  #if (MIDI==1)
   handleMIDI();
  #endif


  //printf("dispscr\n");
  if ( MOSTLY (ScreenUpdateCnt>0) ) ScreenUpdateCnt--;
  else { ScreenUpdateCnt=SCREENUPDATE_PERIOD; }  //printf("delay\n");

  #if ( ENABLED_SDL && !defined(SIDMAKER) )
  if ( TIGHTLY ((TUImode || GUImode) || /*ArgFileDataSize==0 ||*/ KeySimStartupDelayCnt < SPLASH_TO_KEYSIM_DELAY) ) //SPLASH_SCREEN_DURATION)
  #endif
   { if ( TIGHTLY (!ExitDialog && ScreenUpdateCnt==SCREENUPDATE_PERIOD) ) displayScreen( DISPLAY_RUN_CODE ); } //,NULL );


  #ifdef SIDMAKER
  if ( MOSTLY (TimeUpdateCnt>0) ) TimeUpdateCnt--;
  else {
   TimeUpdateCnt=1000/KEYSCAN_PERIOD; CurrentTime=time(NULL);
   if ( CurrentTime != ((time_t)-1) ) {
    if ((TimeString=ctime(&CurrentTime))!=NULL) {
     if (strrchr(TimeString,'\n')!=NULL) *strrchr(TimeString,'\n') = '\0';
     if (strrchr(TimeString,'\r')!=NULL) *strrchr(TimeString,'\r') = '\0';
     for(i=0; i<31 && TimeString[i] ; ++i) cRSID_C64.ROMbanks[MIDIBUF1+i]=TimeString[i];
     for(;i<32;++i) cRSID_C64.ROMbanks[MIDIBUF1+i]='\0'; //strncpy(SIDheader+SIDHEADER_RELEASED_OFFSET,TimeString,SIDHEADER_TEXTFIELD_SIZE-1);
   }}
  }
  #endif


  #if (ENABLED_SDL)
   SDL_Delay( KEYSCAN_PERIOD ); //usleep( KEYSCAN_PERIOD * 1000 ); //printf("loopend\n");
  #else
   #if (ENABLED_ALSA)
    cRSID_syncGenSamples( SOUNDUPDATE_PERIOD_MICROSECONDS /*KEYSCAN_PERIOD_MICROSECONDS*/ ); //cRSID_generateSound( SampleBuffer, SampleBufferSize );
   #else
    //cRSID_C64.RealSIDmode = cRSID.RealSIDmode; //this one gets updated at SID-data rocessing too when the audio doesn't run, to let CPU routines use the up-to-date shadowed versions
    for (i = KEYSCAN_PERIOD_MICROSECONDS * cRSID_C64.SampleRate/*DEFAULT_SAMPLERATE*/ / MICROSECONDS_IN_A_SECOND; i >= 0; --i) cRSID_generateSample(); //cRSID_emulateC64();
    usleep( KEYSCAN_PERIOD_MICROSECONDS ); //if no sound support, though no point (except for SIDmaker), still take care about mainloop-delay
   #endif
  #endif
 }


 saveConfigFile();

 //printf("crsidclose\n"); // !! freezes if sound was not really started
 cRSID_close(); //printf("sdlquit\n");
 #if (MIDI==1)
  //closeMIDI();
 #endif
 closeUI(); //SDL_Quit(); //printf("ret0\n");
 #if (TURN_OFF_KEYREPEAT_DELAY) //(ENABLED_TUI)
  if (TUImode) turnBackOnKeyrepeatDelay();
 #endif


 return 0;

}