//Minimal app to test the buildability of libcRSID with PC/embedded apps (providing their own sound-callback/etc.)

#include <stdio.h>

#include <SDL.h>

#include "../../libcRSID.h"

#include "../HerMiniSID.h"


enum { SAMPLERATE = 44100, BUFFERLENGTH = 2048 };


static void setSDLaudioCallback ();


int main () {
 cRSID_Interface *cRSID_API;

 setSDLaudioCallback();

 if ( cRSID_init( SAMPLERATE, BUFFERLENGTH ) == NULL ) { printf("**** Couldn't initialize cRSID! ****\n"); exit(-1); }

 cRSID.SIDheader = cRSID_processSIDfileData( (unsigned char*) HerMiniSID, sizeof(HerMiniSID) ); //processing included/loaded SID (file)data

 cRSID_initSIDtune( cRSID.SIDheader, 1 ); //initializing SID-tune (calling its 'init', etc.)

 SDL_PauseAudio(0); //start audio-callback

 printf("Playing tune... Press ENTER to finish.\n"); getchar();
 return 0;
}


static void audioCallback (void* userdata, unsigned char *buf, int len) {
 unsigned short i;                 //Playing SID-tune by continuously calling cRSID_generateSample() in this callback
 static cRSID_Output Output;
 for (i=0; i<len; i+=4) {
  Output = cRSID_generateSample(); //(The function returns a cRSID_Output struct with members called 'L' and 'R' for left and right channel sample-values.)
  buf[i+0] = Output.L & 0xFF; buf[i+1] = Output.L >> 8;
  buf[i+2] = Output.R & 0xFF; buf[i+3] = Output.R >> 8;
}}


static void setSDLaudioCallback () {
 static SDL_AudioSpec soundspec;
 if ( SDL_Init(SDL_INIT_AUDIO) < 0 ) { fprintf(stderr, "Couldn't initialize SDL-Audio: %s\n",SDL_GetError()); exit(-1); }
 soundspec.freq = SAMPLERATE; soundspec.samples = BUFFERLENGTH; soundspec.channels = 2; soundspec.format = AUDIO_S16;
 soundspec.callback = audioCallback; soundspec.userdata = NULL;
 if ( SDL_OpenAudio( &soundspec, NULL ) < 0 ) { fprintf(stderr, "Couldn't open audio: %s\n", SDL_GetError()); exit(-2); }
}


