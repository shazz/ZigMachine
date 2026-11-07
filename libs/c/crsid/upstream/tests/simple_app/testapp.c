//Minimal app to test the buildability of libcRSID app on PC with SDL support

#include <stdio.h>

#ifndef CRSID_PLATFORM_PC
 #define CRSID_PLATFORM_PC
#endif
#include "../../libcRSID.h"


enum { SAMPLERATE = 44100, BUFFERLENGTH = 2048, BUFFERUPDATE_PERIOD = 5000 /*microseconds*/ };


int main () {

 if ( cRSID_init( SAMPLERATE, BUFFERLENGTH ) == NULL ) { printf("**** Couldn't initialize cRSID! ****\n"); exit(-1); }

 //Simplest way to play a SID-file with libcRSID (with its built-in SDL-based audio-callback):
 if (cRSID_playSIDfile( "../HerMiniSID.sid", 1 ) == NULL) { printf("Load error! (File not found.)\n"); return -2; }

 //Alternative way, to play a SID-file in a bit more steps:
 //if ( (cRSID.SIDheader = cRSID_loadSIDtune("../HerMiniSID.sid")) == NULL ) { printf("Load error!\n"); return -2; }
 //cRSID_initSIDtune( cRSID.SIDheader, 1 );
 //cRSID_playSIDtune();

 #if (USING_AUDIO_LIBRARY__ALSA)
  printf("Playing the tune... Press Ctrl+C to finish.\n"); //printf("Playing the tune for some seconds...\n");

  while (1) { cRSID_syncGenSamples( BUFFERUPDATE_PERIOD ); } //here the samples are to be sent periodically

 #else
  printf("Playing the tune... Press ENTER to finish.\n");

  getchar(); //here the audio is played on another thread so we can blockingly wait here for a key

 #endif

 cRSID_close();
 return 0;
}


