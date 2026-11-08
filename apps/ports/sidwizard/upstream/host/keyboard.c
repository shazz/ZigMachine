
#if (ENABLED_NCURSES)
 #define ENABLED_TUI 1
 #if (ENABLED_TUI_KEYS)
  #define TURN_OFF_CAPSLOCK 1           //so ncurses TUI and user won't get confused when shifted characters are typed in
  //#define TURN_OFF_KEYREPEAT_DELAY 1    //so keyrepeat and piano-keys in ncurses TUI works deterministically (not by a double delay)
  //(solved keyrepeat-delay issue with ncurses TUI in other way: setting repspd1 to 1 externally, so this ioctl hack got disabled
 #endif
#endif


#if (TURN_OFF_CAPSLOCK || TURN_OFF_KEYREPEAT_DELAY) //(ENABLED_TUI)
 //#include <stdio.h>
 //#include <stdlib.h>
 //#include <unistd.h>
 //#include <string.h>
 #include <signal.h>
 #include <errno.h>
 #include <linux/kd.h>   //constant-definitions
 #include <sys/ioctl.h>  //for keyboard-state/LED settings/requests   int ioctl (int fd, unsigned long op, void *argp);
 #include <fcntl.h>      //  operations: KDGETLED/KDSETLED: get/set keyboard-LEDs (CapsLock:bit2 value $4) , KDGKBLED/KDSKBLED: get/set keyboard-flags (CapsLock:bit2 value $4)
 //#include <sys/stat.h>    //           in kbd's kbdrate.c source-code KDKBDREP of linux/kd.h (since kernel-2.4.9) (or write() to /dev/port) is used to set repeat-delay
 //#include <sys/file.h>
 //#include <sys/types.h>
 //#include <getopt.h>
 //#include <sysexits.h>
#endif


#include "keyboard.h"



static byte ArgLoading=0, ShiftPressed=0, CtrlPressed=0; static word ShiftedKeyDelay=SHIFTED_KEY_DELAY; //100;
static byte* KeyStates; byte ExtraKeypress=0, ScanCode=0;

/*#if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
 enum { NCURSES_KEY_NONE = -1 };
 static int TUIkeyCode = NCURSES_KEY_NONE;
 static char DvorakKeybardLayout = 0;
#endif*/
static byte PositionalKeyScanCodeRow; byte PositionalKeyScanCodeColumn;



static void volumeUp() { if ( (int)cRSID.MainVolume+16 < 255 ) cRSID.MainVolume+=16; else cRSID.MainVolume=255; }

static void volumeDown() { if ( (int)cRSID.MainVolume-16 > 0) cRSID.MainVolume-=16; else cRSID.MainVolume=0; }


#if (TURN_OFF_CAPSLOCK) //(ENABLED_TUI)

static INLINE void ioctlCapsLockOff (char* tty_filename, char check_already_off) {  //IOCTL stuff needs root privileges btw.
 FASTVAR int TTYfile;  //get ID of current terminal without root-access/ioctl: cat /sys/class/tty/tty0/active  or 'fgconsole' command
 static unsigned long int /*char*/ FlagStates, LEDstates;  //printf( "%X, %X\n", LEDstates, FlagStates );
 if ( (TTYfile = open( tty_filename, O_NOCTTY /*O_RDWR*/ )) == -1 ) return;
 if ( ioctl( TTYfile, KDGKBLED, &FlagStates ) == -1 ) { close( TTYfile ); return; }
 if ( ioctl( TTYfile, KDGETLED, &LEDstates ) == -1 ) { close( TTYfile ); return; }
 if (check_already_off && (FlagStates & LED_CAP) == 0) { close( TTYfile ); return; } //if Caps-lock is not turned on or not detectable, don't do anything...
 FlagStates = (FlagStates /*& 0x07*/) & ~LED_CAP; LEDstates = (LEDstates /*& 0x07*/) & ~LED_CAP;  //command 'setleds -F -caps'does the same:
 if ( ioctl( TTYfile, KDSKBLED, FlagStates ) == -1 ) { close( TTYfile ); return; }
 //if ( ioctl( TTYfile, KDSETLED, LEDstates ) == -1 ) { close( TTYfile );return; } //clearing LED too would clear it permanently even if caps-lock is turned on again
 close( TTYfile );  //printf( " %X, %X\n", LEDstates, FlagStates );
}

static INLINE void turnOffCapsLock (char check_already_off) {  //( 'setxkbmap -option ctrl:nocaps' or X11 'XkbLockModifiers()' can turn entire Caps-lock key/functionality off permanently )
 ioctlCapsLockOff( "/dev/console", check_already_off ); ioctlCapsLockOff( "/dev/tty", check_already_off );
}

#endif


#if (TURN_OFF_KEYREPEAT_DELAY) //(ENABLED_TUI)

struct KeyRepeatInfo {
 int Delay; //milliseconds  (not changing if less than 0)
 int Period; //milliseconds (not changing if less than 0)
} KeyRepeatInfo;

struct KeyRepeatInfo SavedKeyrepeatInfo = { 250, 30 };

static INLINE void ioctlKeyRepeatDelayOff (char* tty_filename, char state) { //state: 0:turn off delay, 1: turn delay back on
 FASTVAR int TTYfile;  //get ID of current terminal without root-access/ioctl: cat /sys/class/tty/tty0/active  or 'fgconsole' command
 if ( (TTYfile = open( tty_filename, O_NOCTTY /*O_RDWR*/ )) == -1 ) return;
 if (state==0) { //save info and turn off delay
  KeyRepeatInfo.Delay = -1; KeyRepeatInfo.Period = -1; //value -1, so we're only requesting the data
  if ( ioctl( TTYfile /*0*/, KDKBDREP, &KeyRepeatInfo ) == -1 ) { close( TTYfile ); return; } //{ if (errno==EINVAL || errno==ENOTTY) return; else return; /*kbd_error(EXIT_FAILURE, errno, "ioctl KDKBDREP");*/ }
  //printf( "ioctl-returnvalue: %d,%d,%d,  keyboard delay: %d, repeat: %d\n", errno,EINVAL,ENOTTY, KeyRepeatInfo.Delay, KeyRepeatInfo.Period );
  SavedKeyrepeatInfo.Delay = KeyRepeatInfo.Delay; SavedKeyrepeatInfo.Period = KeyRepeatInfo.Period;
  KeyRepeatInfo.Delay = 40; KeyRepeatInfo.Period = 30;  //FUKK! unfortunately linux fbcon indeed doesn't accept delay smaller than 250! (unlike xset) (will need to handle scancodes directly for proper operation eventually?)
 }                                                      //so I'll go the other way round: decreasing C64 program's built-in delay (to not less than TUI_KEYHOLD_TIME)
 else { //turn delay back on
  KeyRepeatInfo.Delay = SavedKeyrepeatInfo.Delay; KeyRepeatInfo.Period = SavedKeyrepeatInfo.Period;
 }
 if ( ioctl( TTYfile /*0*/, KDKBDREP, &KeyRepeatInfo ) == -1 ) { close( TTYfile ); return; } //set delay and rate  (how is file-descriptor 0 working in kbdrate while I get error with it?)
 //KeyRepeatInfo.Delay = -1; KeyRepeatInfo.Period = -1; //verify
 //if ( ioctl( TTYfile /*0*/, KDKBDREP, &KeyRepeatInfo ) == -1 ) { close( TTYfile ); return; }
 //printf( " ioctl-returnvalue: %d,%d,%d,  keyboard delay: %d, repeat: %d\n", errno,EINVAL,ENOTTY, KeyRepeatInfo.Delay, KeyRepeatInfo.Period );
 close( TTYfile );
}

static void turnOffKeyrepeatDelay () {
 ioctlKeyRepeatDelayOff( "/dev/console", 0 ); ioctlKeyRepeatDelayOff( "/dev/tty", 0 );
}

void turnBackOnKeyrepeatDelay () { //turn it back on (set delay back to original)
 ioctlKeyRepeatDelayOff( "/dev/console", 1 ); ioctlKeyRepeatDelayOff( "/dev/tty", 1 );
}

#endif


void initKeyStates() {
 #if (ENABLED_SDL)
 /*cRSID_C64.*/KeyStates = (byte*) EmptyKeyArray;
 #endif
 /*cRSID_C64.*/ShiftedKeypressSim=0; /*cRSID_C64.*/ScanCode=0;
 /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF;
 /*cRSID_C64.*/PositionalKeyScanCodeRow=0xF; /*cRSID_C64.*/PositionalKeyScanCodeColumn=0xF;
 #if (TURN_OFF_CAPSLOCK) //(ENABLED_TUI)
 if (TUImode) turnOffCapsLock(0);
 #endif
 #if (TURN_OFF_KEYREPEAT_DELAY) //(ENABLED_TUI)
 if (TUImode) turnOffKeyrepeatDelay();
 #endif
}

static INLINE char isPianoKeyCondition () {
 return SpritEnaBars[INSCREEN_RASTER]!=0 //inside editor?
   && !( (cRSID_C64.IObankWR[0xD010]&1) && cRSID_C64.IObankWR[0xD001]>=34 && cRSID_C64.IObankWR[0xD001]<42 ) //not instrument-name-typing?
   && !ShiftPressed && !CtrlPressed; //!/*cRSID_C64.*/KeyStates[SDLK_LSHIFT] && !/*cRSID_C64.*/KeyStates[SDLK_RSHIFT] && !/*cRSID_C64.*/KeyStates[SDLK_LCTRL] && !/*cRSID_C64.*/KeyStates[SDLK_RCTRL]
}


static INLINE void getKeyStates() {
 #if (TURN_OFF_CAPSLOCK)
 enum { CAPSLOCK_CHECK_INTERVAL = 1000 /*milliseconds*/ / KEYSCAN_PERIOD };
 static int CapsLockTurnoffCheckTimer = 0;
 #endif
 static byte i,j, C64key, ShiftedKeypressSimTemp=0, CBMkeypressSimTemp=0, ExtraKeypressTemp=0;


 #if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)

 static int ShiftedKeys[] = { SDLK_INSERT, SDLK_LEFT, SDLK_F8, SDLK_F2, SDLK_F4, SDLK_F6, SDLK_UP, SDLK_PAGEUP }; //just for C64-key shift-predetermination //printf("%d\n",ArgLoading);
 static int CBMkeys[] = { SDLK_KP_MULTIPLY, SDLK_KP_DIVIDE }; //just for C64-key CBMkey-predetermination
 static int ExtraKeys[] = { SDLK_F2, SDLK_F4 }; //pressing shift with these should turn on C= key on C64 now
 static int ExtraKeysNoShift[] = { SDLK_F1, SDLK_F3, SDLK_F5, SDLK_F6, SDLK_DOWN }; //, SDLK_PAGEUP, SDLK_PAGEDOWN }; //(and turn C64-Shift off for F1 & F3 & F5)

 #if (!FORCED_SDL_EVENTS)
 if ( TIGHTLY (!TUImode) )
 #endif
 { //SDL-UI-mode:
  /*cRSID_C64.*/KeyStates = (ArgLoading==0) ? SDL_GetKeyState(NULL) : (byte*)EmptyKeyArray;
  ShiftPressed = KeyStates[SDLK_LSHIFT] || KeyStates[SDLK_RSHIFT];
  CtrlPressed = KeyStates[SDLK_LCTRL] || KeyStates[SDLK_RCTRL];
  ShiftedKeypressSimTemp = CBMkeypressSimTemp = ExtraKeypressTemp = 0; //calculating in temp-variables, so if EmulateKeyMatrix() is in other (audio) thread it won't sense a zeroing occasionally
  C64key = -1;
  #ifdef _LINUX
  if ( RARELY (/*cRSID_C64.*/KeyStates[SDLK_LALT] || /*cRSID_C64.*/KeyStates[SDLK_RALT] /*|| MouseClicked || MouseWheelUp || MouseWheelUpDown*/) ) /*cRSID_C64.*/KeyStates=(byte*)EmptyKeyArray; //Alt+TAB won't disturb track-tabbing
  #endif
  if ( RARELY (ShiftPressed) ) {
   for (i=0; i<(sizeof(ExtraKeysNoShift)/sizeof(int)); ++i) { //for(i=0;i<KEY_AMOUNT;++i) {  //give now Shift+F1/F2/F3/F4 the same function as Ctrl+F1/F2/F3/F4  (to adhere to TUI where Shift+Fx is always accessible, unlike Ctrl+Fx)
    if (KeyStates[ ExtraKeysNoShift[i]/*SDLKeyToC64key_CBM_SDLshiftedKeyExtras[i>>3][i&7]*/ ]) { /*C64key=i;*/ CBMkeypressSimTemp=ExtraKeypressTemp=1; /*ShiftPressed=0;*/ break; }
   }
   for (i=0; i<(sizeof(ExtraKeys)/sizeof(int)); ++i) {
    if (KeyStates[ ExtraKeys[i]/*SDLKeyToC64key_Shift_plus_CBM_SDLshiftedKeyExtras[i>>3][i&7]*/ ]) { /*C64key=i;*/ /*ShiftedKeypressSimTemp=*/CBMkeypressSimTemp/*=ExtraKeypressTemp*/=1; /*ShiftPressed=0;*/ break; }
   }
  }
  else { for (i=0; i<(sizeof(ShiftedKeys)/sizeof(int)); ++i) if ( RARELY(/*cRSID_C64.*/KeyStates[ShiftedKeys[i]]) ) { ShiftedKeypressSimTemp=1; break; } }
  for (i=0; i<(sizeof(CBMkeys)/sizeof(int)); ++i) { if ( RARELY (/*cRSID_C64.*/KeyStates[CBMkeys[i]]) ) { CBMkeypressSimTemp=1; break; } }
  for (i=0;i<8;++i) for(j=0;j<8;++j) { if ( RARELY (ShiftedMouseKey[i][j]) ) { MouseShiftedKeypressSim=1; break; } }
  /*cRSID_C64.*/ShiftedKeypressSimTemp=ShiftedKeypressSimTemp|MouseShiftedKeypressSim; /*cRSID_C64.*/CBMkeypressSimTemp=CBMkeypressSimTemp|MouseCBMkeypressSim; //could be common to keyboard & mouse //cRSID_C64.ShiftedKeypressSim=ShiftedKeypressSim; cRSID_C64.CBMkeypressSim=CBMkeypressSim; C64key=0xFF; //printf("%d\n",cRSID_C64.ScanCode); //printf("%d\n",cRSID_C64.IObankWR[0xD001]);
  for(i=0;i<KEY_AMOUNT;++i) { if ( RARELY (/*cRSID_C64.*/KeyStates[SDLKeyToC64key[i>>3][i&7]]) ) {C64key=i; break;} } //C64 key of a pressed SDL-key (for scancode comparison/conversion)
  ShiftedKeypressSim = ShiftedKeypressSimTemp; CBMkeypressSim = CBMkeypressSimTemp; ExtraKeypress = ExtraKeypressTemp;
  if ( MOSTLY (!ShiftedKeypressSim && !CBMkeypressSim) ) ShiftedKeyDelay=SHIFTED_KEY_DELAY;

  if ( RARELY ( /*cRSID_C64.*/ScanCode<64 && SDLscanCodeToC64key[/*cRSID_C64.*/ScanCode] && C64key!=SDLscanCodeToC64key[/*cRSID_C64.*/ScanCode] //only if valid scancode, and differs from SDLK
   && isPianoKeyCondition() && /*cRSID_C64.*/KeyStates!=EmptyKeyArray //inside editor?
   && ( (cRSID_C64.IObankWR[0xD01D]&1) || (!/*cRSID_C64.*/KeyStates[SDLK_a] && !/*cRSID_C64.*/KeyStates[SDLK_b]
        && !/*cRSID_C64.*/KeyStates[SDLK_c] && !/*cRSID_C64.*/KeyStates[SDLK_d] && !/*cRSID_C64.*/KeyStates[SDLK_e]&&!/*cRSID_C64.*/KeyStates[SDLK_f]) ) //note-column or ins/fx-column with non-hex keys
   ) ) { //printf("%2.2X-%2.2X\n",C64key,SDLscanCodeToC64key[cRSID_C64.ScanCode]);
   /*cRSID_C64.*/PianoKeyScanCodeRow = (SDLscanCodeToC64key[/*cRSID_C64.*/ScanCode]>>3);
   /*cRSID_C64.*/PianoKeyScanCodeColumn = (SDLscanCodeToC64key[/*cRSID_C64.*/ScanCode]&7);
  }
  else if ( RARELY (/*cRSID_C64.*/ScanCode==(20-OS_SCANCODESUB) && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { // Scancode (US '-' key) for forced position '-' Minus-key substitution
   /*cRSID_C64.*/PositionalKeyScanCodeRow=5; /*cRSID_C64.*/PositionalKeyScanCodeColumn=3; //-
  }
  else if ( RARELY (/*cRSID_C64.*/ScanCode==(21-OS_SCANCODESUB) && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { // Scancode (US '=+' key) for forced position '+' Plus-key substitution
   /*cRSID_C64.*/PositionalKeyScanCodeRow=5; /*cRSID_C64.*/PositionalKeyScanCodeColumn=0; //+
  }
  else if ( RARELY (/*cRSID_C64.*/ScanCode==(51-OS_SCANCODESUB) && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { // Scancode (US '\|'-key) for forced position '=' //Equal-key substitution
   if (ShiftPressed) ; //ExtraKeypressTemp=1; //if (cRSID_C64.KeyStates[SDLK_LSHIFT] || cRSID_C64.KeyStates[SDLK_RSHIFT]) { cRSID_C64.PositionalKeyScanCodeRow=5; cRSID_C64.PositionalKeyScanCodeColumn=0; } //plus - dead-end
   else {/*cRSID_C64.*/PositionalKeyScanCodeRow=6; /*cRSID_C64.*/PositionalKeyScanCodeColumn=5;} //=
  }
  else if ( RARELY (/*cRSID_C64.*/ScanCode==(34-OS_SCANCODESUB) && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { //Scancode (US '[{'-key) for forced position ':' Colon-key substitution (and minus if shifted)
   /*cRSID_C64.*/PositionalKeyScanCodeRow=5; /*cRSID_C64.*/PositionalKeyScanCodeColumn=5; //;
  }
  else if ( RARELY (/*cRSID_C64.*/ScanCode==(35-OS_SCANCODESUB) && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { //Scancode (US ']}'-key) for forced position ';' Semicolon-key substitution (and plus if shifted)
   /*cRSID_C64.*/PositionalKeyScanCodeRow=6; /*cRSID_C64.*/PositionalKeyScanCodeColumn=2; //;
  }
  else if ( RARELY (/*cRSID_C64.*/KeyStates[SDLK_CARET] /*cRSID_C64.KeyStates[SDLK_F10]*/ && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { // '^' as fastforward on German keyboard
   /*cRSID_C64.*/PositionalKeyScanCodeRow=7; /*cRSID_C64.*/PositionalKeyScanCodeColumn=1; //<- (back-arrow)
  }
  /*else if( (cRSID_C64.KeyStates[SDLK_LSHIFT] || cRSID_C64.KeyStates[SDLK_RSHIFT]) && cRSID_C64.KeyStates!=EmptyKeyArray ) { //dead-end: accidentally increases patt.num., no shift-version
   if(cRSID_C64.KeyStates[SDLK_EQUALS] || cRSID_C64.KeyStates[SDLK_MINUS]) { cRSID_C64.PianoKeyScanCodeRow=5; cRSID_C64.PianoKeyScanCodeColumn=0; } //Plus-key substitutions (laptop)
   //else if (cRSID_C64.KeyStates[SDLK_SEMICOLON]) { cRSID_C64.PianoKeyScanCodeRow=6; cRSID_C64.PianoKeyScanCodeColumn=2; } //semicolon substitution (because : is default)
   else { cRSID_C64.PianoKeyScanCodeRow = cRSID_C64.PianoKeyScanCodeColumn = 0xF; }
  }*/
  #ifndef SIDMAKER
  else if ( RARELY (MouseClicked && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { mouseButtonPress(); }
  else if ( RARELY (MouseWheelUp && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { mouseWheelUp(); }
  else if ( RARELY (MouseWheelDown && /*cRSID_C64.*/KeyStates!=EmptyKeyArray) ) { mouseWheelDown(); }
  #endif
  else {
   /*cRSID_C64.*/PianoKeyScanCodeRow = /*cRSID_C64.*/PianoKeyScanCodeColumn = 0xF;
   /*cRSID_C64.*/PositionalKeyScanCodeRow = /*cRSID_C64.*/PositionalKeyScanCodeColumn = 0xF;
  }
  mouseKeyReleaseCount();
  //ExtraKeypress = ExtraKeypressTemp;
 }

 #endif //ENABLED_SDL_EVENTS


 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)  //(regarding modkey-timing, would better be done in keymatrix-emulation? (albeit would slow things down checking all of it there at CPU-pace)):

 //static int ShiftedTUIkeys[] = { KEY_IC, KEY_LEFT, KEY_F(8), KEY_F(2), KEY_F(4), KEY_F(6), KEY_UP, KEY_PPAGE }; //KEY_PREVIOUS  //printf("%d\n",ArgLoading);
 if ( TIGHTLY (TUImode) ) { //else { //TUI-mode

  #if (TURN_OFF_CAPSLOCK)
  if ( RARELY (--CapsLockTurnoffCheckTimer <= 0) ) { CapsLockTurnoffCheckTimer = CAPSLOCK_CHECK_INTERVAL; turnOffCapsLock(1); }
  #endif

  ShiftedKeypressSimTemp=0; CBMkeypressSimTemp=0; //calculating in temp-variables, so if EmulateKeyMatrix() is in other (audio) thread it won't sense a zeroing occasionally
  for (i=0; i < C64_KEYTABLE_ROWS; ++i) {  //for (i=0; i<(sizeof(ShiftedTUIkeys)/sizeof(int)); ++i) { if (TUIkeyCode==ShiftedTUIkeys[i]) { ShiftedKeypressSim=1; break; } }
   for (j=0; j < C64_KEYTABLE_COLUMNS; ++j) { if ( RARELY (TUIkeyCode == NcursesKeyCodeToC64key_Shift[i][j]) ) { ShiftedKeypressSimTemp=1; break; } }
   if ( RARELY (ShiftedKeypressSimTemp) ) break;
  }
  for (i=0; i < C64_KEYTABLE_ROWS; ++i) {
   for (j=0; j < C64_KEYTABLE_COLUMNS; ++j) {
    if ( RARELY ( TUIkeyCode == NcursesKeyCodeToC64key_CBMkey[i][j] || TUIkeyCode == NcursesKeyCodeToC64key_CBMkey_Alternative[i][j]
         || (TUIkeyCode > NCURSES_XTERM_DEPENDENT_KEYS && TUIkeyCode-1 == NcursesKeyCodeToC64key_CBMkey_Alternative[i][j]) ) ) //for old xterms with Ctrl+Up/Down/Home/End/PageUp/PageDown to C=+./- (for alternative subtune-change)
    { CBMkeypressSimTemp=1; }
   }
   if ( RARELY (CBMkeypressSimTemp) ) break;
  }
  for (i=0; i < C64_KEYTABLE_ROWS; ++i) {
   for (j=0; j < C64_KEYTABLE_COLUMNS; ++j) {
    if ( RARELY (TUIkeyCode == NcursesKeyCodeToC64key_Shift_plus_CBMkey[i][j] || TUIkeyCode == NcursesKeyCodeToC64key_Shift_plus_CBMkey_Alternative[i][j]) ) {
     CBMkeypressSimTemp = ShiftedKeypressSimTemp = 1; break;
    }
   }
   if ( RARELY (CBMkeypressSimTemp) ) break;
  }
  ShiftedKeypressSim = ShiftedKeypressSimTemp; CBMkeypressSim = CBMkeypressSimTemp;
  if ( MOSTLY (!ShiftedKeypressSim && !CBMkeypressSim) ) ShiftedKeyDelay=SHIFTED_KEY_DELAY;

  if ( RARELY ( DvorakKeybardLayout && 0x20 <= TUIkeyCode && TUIkeyCode <= 0x7A /*TUIkeyCode!=NCURSES_KEY_NONE*/
   && DvorakKeyToC64key[TUIkeyCode-0x20] //only if valid keycode (might be set to 0 if the same as US key)
   && isPianoKeyCondition()
   && ( (cRSID_C64.IObankWR[0xD01D]&1) || (TUIkeyCode!='a' && TUIkeyCode!='b' && TUIkeyCode!='c' && TUIkeyCode!='d' && TUIkeyCode!='e' && TUIkeyCode!='f') ) //note-column or ins/fx-column with non-hex keys
  ) ) { //printf("%2.2X-%2.2X\n",C64key,SDLscanCodeToC64key[cRSID_C64.ScanCode]);
   /*cRSID_C64.*/PianoKeyScanCodeRow = DvorakKeyToC64key[ TUIkeyCode - 0x20 ] >> 3;
   /*cRSID_C64.*/PianoKeyScanCodeColumn = DvorakKeyToC64key[ TUIkeyCode - 0x20 ] & 7;
  }
  else if ( RARELY (DvorakKeybardLayout && TUIkeyCode == '[') ) { /*cRSID_C64.*/PositionalKeyScanCodeRow=5; /*cRSID_C64.*/PositionalKeyScanCodeColumn=3; } //forced -
  else if ( RARELY (DvorakKeybardLayout && TUIkeyCode == ']') ) { /*cRSID_C64.*/PositionalKeyScanCodeRow=5; /*cRSID_C64.*/PositionalKeyScanCodeColumn=0; } //forced +
  else {
   /*cRSID_C64.*/PianoKeyScanCodeRow = /*cRSID_C64.*/PianoKeyScanCodeColumn = 0xF;
   /*cRSID_C64.*/PositionalKeyScanCodeRow = /*cRSID_C64.*/PositionalKeyScanCodeColumn = 0xF;
  }

 }

 #endif //ENABLED_TUI_KEYS

}



INLINE void EmulateKeyMatrix () {

 FASTVAR /*static*/ byte Row, Col, Out, ShiftToCBMkey;  //static word ShiftedKeyDelay=100;
 static const byte Pow2 [8 ] = { 1, 2, 4, 8, 16, 32, 64, 128 };
 static const byte InvPow2 [8] = { 0xFE, 0xFD, 0xFB, 0xF7, 0xEF, 0xDF, 0xBF, 0x7F };

 //for(i=0;i<8;++i) { if (cRSID_C64.IObankWR[0xDC00] == InvPow2[i]) break; } //get tested keyboard-row
 //if(i<8) Row=i; else { cRSID_C64.IObankRD[0xDC01]=0xFF; return; }

 ShiftToCBMkey = ExtraKeypress; //= (ExtraKeypress); // && ShiftPressed); //|| CBMkeypressSim));// && ShiftPressed);
 Out=0xFF; //init row-keypress-bits


 #if (ENABLED_SDL_EVENTS) //(ENABLED_SDL)

 #if (!FORCED_SDL_EVENTS && ENABLED_TUI_KEYS) //(ENABLED_TUI)
 if ( TIGHTLY (!TUImode) )  //SDL-UI-mode:
 #endif
 { //SDL-UI-mode:
  for (Row=0; Row<C64_KEYTABLE_ROWS; ++Row) {
   if ( RARELY ( (cRSID_C64.IObankWR[0xDC00] & Pow2[Row]) == 0 ) ) { //get tested keyboard-row
    if ( RARELY (/*cRSID_C64.*/PianoKeyScanCodeRow!=0xF) ) {
     if ( RARELY (/*cRSID_C64.*/PianoKeyScanCodeRow==Row && !TUImode) ) Out &= InvPow2[/*cRSID_C64.*/PianoKeyScanCodeColumn];
    }
    else {

     if ( RARELY (/*cRSID_C64.*/ShiftedKeypressSim) ) { if( RARELY (Row==C64_LEFTSHIFT_ROW) ) Out&=0x7F; else if ( RARELY (Row==C64_RIGHTSHIFT_ROW) ) Out&=0xEF; } //emulate left/right-shift pressed together with key
     /*else*/ if ( RARELY (/*cRSID_C64.*/CBMkeypressSim) ) { if ( RARELY (Row==C64_CBMKEY_ROW) ) Out&=0xDF; } //emulate C= pressed together with key
     //else /*if (!ShiftedKeypressSim && !CBMkeypressSim)*/ ShiftedKeyDelay=SHIFTED_KEY_DELAY;

     for (Col=0; Col<C64_KEYTABLE_COLUMNS; ++Col) { //printf("%2.2X-%2.2X ",Row,i); //columns
      if ( RARELY ( !ShiftToCBMkey && ( // && (SDLKeyToC64key[Row][Col]==SDLK_LSHIFT || SDLKeyToC64key[Row][Col]==SDLK_RSHIFT) )
           ( /*cRSID_C64.*/PositionalKeyScanCodeRow==Row && /*cRSID_C64.*/PositionalKeyScanCodeColumn==Col ) //more positional keys (other than piano-keys)
           || /*cRSID_C64.*/KeyStates[SDLKeyToC64key[Row][Col]] || /*cRSID_C64.*/KeyStates[SDLKeyToC64key_Alternative[Row][Col]] //symbolic keys
           || ( ShiftPressed && KeyStates[ SDLKeyToC64key_Shift_SDLshiftedKeyExtras[Row][Col] ] ) // use Shift+'\' aka '|' as Shift+Enter
           || ( CtrlPressed && KeyStates[ SDLKeyToC64key_CBM_SDLCtrlkeyExtras[Row][Col] ] ) //Ctrl+Home/End to be the same as Ctrl+./- for subtune-change
       ) ) ) {
       Out &= InvPow2[Col]; //printf("%2.2X-%2.2X \n",Row,Col);
      } //modkey-emulations to be added on the C64  (mod-keys might have been pressed along with the SDL-key):
      else if ( RARELY ( (!ShiftPressed && /*cRSID_C64.*/KeyStates[SDLKeyToC64key_Shift[Row][Col]]) /*Up,F6,F8*/ || /*cRSID_C64.*/KeyStates[SDLKeyToC64key_CBMkey[Row][Col]] //Keypad / and * as Ctrl + / -
                || ShiftedMouseKey[Row][Col] || CBMmouseKey[Row][Col] //mouse-initiated key-combinations  //printf("%d %d\n",Row,Col);
                || ( ShiftToCBMkey && KeyStates[ SDLKeyToC64key_CBM_SDLshiftedKeyExtras[Row][Col] ] ) /*&& !ShiftPressed*/ //) //for Shift+F1/F3/PageUp/PageDown keys to make same(/other)-key plus CBM (C=) modifier-key keypresses
                || ( CBMkeypressSim && KeyStates[ SDLKeyToC64key_Shift_plus_CBM_SDLshiftedKeyExtras[Row][Col] ] ) /*SDLkeys pressed: F2/F4, Shift+F2/F4*/ // ) { //printf("%d %d\n",Row,Col);
      ) ) {
       if ( CALMLY (ShiftedKeyDelay>0) ) { --ShiftedKeyDelay; } else { Out &= InvPow2[Col]; } //emulate keypress (after shift and/or C=)
      }
     }

    }
   }
  }
 }

 #endif //ENABLED_SDL_EVENTS


 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)

 #if (!FORCED_SDL_EVENTS && ENABLED_SDL_EVENTS) //(ENABLED_SDL)
 else              //TUI-mode:
 #endif
 { //TUI-mode (unfortunately Ncurses and terminals in general have very limited key-combination support (they're character-based, not scancode/event-based)
  //ShiftedKeypressSim = CBMkeypressSim = 0;
  for (Row=0; Row < C64_KEYTABLE_ROWS; ++Row) {
   if ( RARELY ( (cRSID_C64.IObankWR[0xDC00] & Pow2[Row]) == 0 ) ) { //get tested keyboard-row
    if ( RARELY (/*cRSID_C64.*/PianoKeyScanCodeRow!=0xF) ) {
     if ( RARELY (/*cRSID_C64.*/PianoKeyScanCodeRow==Row && TUImode) ) Out &= InvPow2[/*cRSID_C64.*/PianoKeyScanCodeColumn];
    }
    else {

     if ( RARELY (ShiftedKeypressSim || CBMkeypressSim) ) {
      switch (Row) {
       case C64_LEFTSHIFT_ROW: if (/*cRSID_C64.*/ShiftedKeypressSim) Out&=0x7F; break; //emulate left-shift pressed together with key
       case C64_RIGHTSHIFT_ROW: if (/*cRSID_C64.*/ShiftedKeypressSim) Out&=0xEF; break; //emulate right-shift pressed together with key
       case C64_CBMKEY_ROW: if (/*cRSID_C64.*/CBMkeypressSim) Out&=0xDF; break; //emulate C= pressed together with key
      }
      for (Col=0; Col<C64_KEYTABLE_COLUMNS; ++Col) { //mvprintw(30,20,"%d (%d,%d)\n",TUIkeyCode,Row,Col); //printf("%2.2X-%2.2X ",Row,i); //columns
       if ( TUIkeyCode == NcursesKeyCodeToC64key_Shift[Row][Col]
            || TUIkeyCode == NcursesKeyCodeToC64key_CBMkey[Row][Col] || TUIkeyCode == NcursesKeyCodeToC64key_CBMkey_Alternative[Row][Col]
            || (TUIkeyCode > NCURSES_XTERM_DEPENDENT_KEYS && TUIkeyCode-1 == NcursesKeyCodeToC64key_CBMkey_Alternative[Row][Col]) //for old xterms with Ctrl+Up/Down/Home/End/PageUp/PageDown to C=+./- (for alternative subtune-change)
            || TUIkeyCode == NcursesKeyCodeToC64key_Shift_plus_CBMkey[Row][Col]
            || TUIkeyCode == NcursesKeyCodeToC64key_Shift_plus_CBMkey_Alternative[Row][Col] ) {
        //ShiftedKeypressSim = 1; CBMkeypressSim = 1;  mvprintw(32,20,"%d (%d,%d) %d\n",TUIkeyCode,Row,Col,ShiftedKeyDelay);
        if (ShiftedKeyDelay>0) { --ShiftedKeyDelay; cRSID_C64.IObankRD[0xDC01] = Out; return; }
        else { //emulate keypress (after modifier-key)
         cRSID_C64.IObankRD[0xDC01] = Out & InvPow2[Col]; return;
        }
       }
      }
     }

     else { //no C64 modifier key simulated:
      for (Col=0; Col < C64_KEYTABLE_COLUMNS; ++Col) { //columns
       if ( (PositionalKeyScanCodeRow==Row && PositionalKeyScanCodeColumn==Col)
            || TUIkeyCode == NcursesKeyCodeToC64key[Row][Col] || TUIkeyCode == NcursesKeyCodeToC64key_Alternative[Row][Col]
            || (Row==0 && Col==0 && TUIkeyCode==KEY_BACKSPACE_ALTERNATIVE) ) {
        cRSID_C64.IObankRD[0xDC01] = Out & InvPow2[Col]; return;
       }
      }
     }

    }
   }
  }

 }

 #endif //ENABLED_TUI_KEYS


 cRSID_C64.IObankRD[0xDC01]=Out;

}



//Keypress-simulations for argument-file loading
static void simulateKey_UP (char state) {
 #if (ENABLED_SDL)
  #if (!FORCED_SDL_EVENTS)
   if (!TUImode)
  #endif
    KeyStates[SDLK_UP] = state;
 #endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
 if (TUImode) TUIkeyCode = state? KEY_UP : NCURSES_KEY_NONE;
 #endif
}
static void simulateKey_DOWN (char state) {
 #if (ENABLED_SDL)
  #if (!FORCED_SDL_EVENTS)
   if (!TUImode)
  #endif
    KeyStates[SDLK_DOWN] = state;
 #endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  if (TUImode) TUIkeyCode = state? KEY_DOWN : NCURSES_KEY_NONE;
 #endif
}
static void simulateKey_RIGHT (char state) {
 #if (ENABLED_SDL)
  #if (!FORCED_SDL_EVENTS)
   if (!TUImode)
  #endif
    KeyStates[SDLK_RIGHT] = state;
 #endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  if (TUImode) TUIkeyCode = state? KEY_RIGHT : NCURSES_KEY_NONE;
 #endif
}
static void simulateKey_RETURN (char state) {
 #if (ENABLED_SDL)
  #if (!FORCED_SDL_EVENTS)
   if (!TUImode)
  #endif
    KeyStates[SDLK_RETURN] = state;
 #endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  if (TUImode) TUIkeyCode = state? '\r' : NCURSES_KEY_NONE;
 #endif
}
static void simulateKey_F8 (char state) {
 #if (ENABLED_SDL)
  #if (!FORCED_SDL_EVENTS)
   if (!TUImode)
  #endif
    KeyStates[SDLK_F8] = /*KeyStates[SDLK_F7] = KeyStates[SDLK_LSHIFT] = KeyStates[SDLK_RSHIFT] =*/ state;
    #ifndef SIDMAKER
    PianoRollMode = 0;  //if menu is brought in, piano-roll should disappear
    #endif
 #endif
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  if (TUImode) TUIkeyCode = state? KEY_F(8) /*(NCURSES_KEYCODE_SHIFT__Fx+7)*/ : NCURSES_KEY_NONE;
 #endif
}

