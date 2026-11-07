//Minimal app to test the buildability of libcRSID with PC/embedded apps (providing their own sound-callback/etc.)

#include <stdio.h>

#include "../../libcRSID.h"

#include "../HerMiniSID.h"


#define SAMPLERATE 44100
#define BUFFERLENGTH 2048


int main () {

 if ( cRSID_init( SAMPLERATE, BUFFERLENGTH ) == NULL ) { printf("**** Couldn't initialize cRSID! ****\n"); exit(-1); }

 cRSID.SIDheader = cRSID_processSIDfileData( (unsigned char*) HerMiniSID, sizeof(HerMiniSID) ); //processing included/loaded SID (file)data

 cRSID_initSIDtune( cRSID.SIDheader, 1 ); //initializing SID-tune (calling its 'init', etc.)

 //Playing SID-tune by continuously calling cRSID_generateSample():
 //(The function returns a cRSID_Output struct with members called 'L' and 'R' for left and right channel sample-values.)
 int i;
 for (i=0; i < 10000; ++i) { printf( "%d ", cRSID_generateSample().L ); }

 printf("\n");
 return 0;
}

