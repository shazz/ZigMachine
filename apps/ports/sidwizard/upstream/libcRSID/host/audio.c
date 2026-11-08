

#ifdef CRSID_PLATFORM_PC


#define USING_SDL  (ENABLED_SDL)
#define USING_ALSA (ENABLED_ALSA)


#if (USING_SDL)
 #include <SDL.h>
#elif (USING_ALSA)
 #include <stdint.h>
 //#define _POSIX_C_SOURCE 199309L  //supposedly needed to bring clock_gettime() from time.h
 //#include <time.h>
 #include <sys/time.h>
 #include <alsa/asoundlib.h>
 #include <alsa/pcm.h>
 #if (ENABLED_NCURSES) //just for testing/debugging:
  #include <curses.h>  //#include "../../host/ncurses/include/curses.h"
 #endif
#endif


#include "host.h"

#include "../libcRSID.h"

#include "../../SIDwizard.h"


enum { SAMPLE_BYTES = 2 /*for the used S16 LE 16-bit format*/, SAMPLE_CHANNELS =
  /*#if (SIDAMOUNT==1)
   1 //channel (mono)
  #else*/
   2 //channels (stereo)
  //#endif
   , SAMPLE_FRAMESIZE = (SAMPLE_BYTES * SAMPLE_CHANNELS) /*bytes*/, SILENT_SAMPLE_VALUE = 0 /*with signed S16*/
};


#if (USING_ALSA)
static snd_pcm_t* SoundDevice = NULL;
static byte* /* unsigned char* */ SampleBuffer = NULL;
static int /*SampleRate,*/ /*SampleBufferLength = 0,*/ SampleBufferSize = 0;
#endif


void cRSID_soundCallback (void* userdata, unsigned char *buf, int len) {
 cRSID_C64.SoundStarted=1; //set to inform the rest of the code that sound could be started already (buffer callback works)
 cRSID_generateSound( buf, len );
 //cRSID_autoAdvance();
}



void* cRSID_initSound (unsigned short samplerate, unsigned short buflen) {

 cRSID_C64.SoundStarted=0;

 #if (USING_SDL)  //init SDL sound:

  static SDL_AudioSpec soundspec;

  if ( SDL_Init(SDL_INIT_AUDIO /*| SDL_INIT_VIDEO*/ ) < 0 ) {
   fprintf(stderr, "Couldn't initialize SDL-Audio: %s\n",SDL_GetError()); return NULL;
  }
  soundspec.freq=samplerate;
  soundspec.channels=SAMPLE_CHANNELS;
  soundspec.format=AUDIO_S16;
  soundspec.samples=buflen; soundspec.userdata=&cRSID_C64; soundspec.callback=cRSID_soundCallback;
  if ( SDL_OpenAudio( &soundspec, NULL ) < 0 ) {
   fprintf(stderr, "Couldn't open audio: %s\n", SDL_GetError()); return NULL;
  }

  //cRSID.Paused = 0;

  return (void*)&soundspec;


 #elif (USING_ALSA)  //init ALSA sound:


  enum { DISABLE_RESAMPLER = 0, ENABLE_RESAMPLER = 1 }; //advised to turn on because many soundcards are at 48kHz, not 44100Hz
  //static int SampleBufferSize;
  //static snd_pcm_t* SoundDevice;
  //static snd_pcm_hw_params_t *HwParams;

  if (SoundDevice != NULL) return (void*)SoundDevice;

  if ( snd_pcm_open( &SoundDevice, "default" /* "plughw:0,0" */ , SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK ) < 0 ) {
   fprintf( stderr, "Couldn't initialize ALSA-Audio!\n" ); SoundDevice=NULL; return NULL;
  }

  cRSID.SampleBufferLength = buflen; cRSID_C64.SampleRate = samplerate;

  if ( snd_pcm_set_params( SoundDevice, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
       SAMPLE_CHANNELS, samplerate, ENABLE_RESAMPLER, 1000000 * cRSID.SampleBufferLength / samplerate ) < 0 ) { //last parameter is latency in microseconds, but if not precise we'll set exact buffersize instead
   fprintf( stderr, "Couldn't set ALSA 44kHz S16-LE playback-format.\n" ); return NULL;
  }
  //snd_pcm_hw_params_malloc( &HwParams ); snd_pcm_hw_params_any( SoundDevice, HwParams ); //get sound-device parameters to HwParams
  //if ( snd_pcm_hw_params_set_buffer_size( SoundDevice, HwParams, buflen * 2 ) < 0 ) { printf( "Couldn't set audio buffer-length %d\n", buflen ); return NULL; }
  //snd_pcm_hw_params_free( HwParams );  printf("ALSA: %d samples available for writing\n", (int) snd_pcm_avail_update( SoundDevice ) );

  SampleBufferSize = cRSID.SampleBufferLength * SAMPLE_FRAMESIZE; //in bytes
  SampleBuffer = malloc( SampleBufferSize ); memset( SampleBuffer, SILENT_SAMPLE_VALUE, SampleBufferSize ); if (SampleBuffer == NULL) { printf("Couldn't allocate sample-buffer!\n"); }

  snd_pcm_nonblock( SoundDevice, 0 ); //switch to blocking-mode for playback

  if ( snd_pcm_prepare( SoundDevice ) < 0 ) { printf("Couldn't prepare ALSA sound-device\n"); return NULL; }

  //snd_pcm_start( SoundDevice ); //needed? (for 'mmap' diect buffer mode only?)
  //snd_pcm_drain( SoundDevice );
  //printf("ALSA: %d samples available for writing\n", (int) snd_pcm_avail_update( SoundDevice ) );  //exit(0);

  //cRSID.Paused = 0;

  return (void*)SoundDevice; //cRSID_initSound; //NULL;


 #else  //SIDmaker has no sound:

  return cRSID_initSound; //a non-NULL is still returned to caller to show everything's fine


 #endif //end of sound-init selections
}



#if (USING_ALSA)
static INLINE int64_t getEpochTimeMicroseconds () {
 static struct timeval /*struct timespec*/ CurrentTime;
 gettimeofday( &CurrentTime, NULL /*timezone*/ );  //clock_gettime( CLOCK_MONOTONIC_RAW, &Time );
 return CurrentTime.tv_sec * 1000000 + CurrentTime.tv_usec;
}

void cRSID_syncGenSamples (int frametime) {  //this synchronizer functioun should last till the next frame by generating audio, or waiting if done with it
 enum { /*MICROSECONDS_IN_A_SECOND = 1000000,*/ SYNC_TIME_GRANULARITY = 1000 /* microseconds */ }; //, SYNC_PERIODS_MAX=SOUNDUPDATE_PERIOD_MICROSECONDS/SYNC_TIME_GRANULARITY }; //maximum allowed jitter (when there's no CPU-overload)
 //enum { SAMPLECHUNK_SIZE_SLACK = BUFFERSIZE_MIN /*100*/ /*samples*/ }; //generating some more samples than needed in current round by lowering send-threshold
 enum { SAMPLE_SEND_RETRY_DELAY = 1000 }; //microseconds  (so in case of error the machine doesn't run at 100% in loop)

 static int i; static char SyncPeriodCount, SyncPeriods;
 static int64_t LatestSyncTime = 0, EntryTime, NewSyncTime, SyncTime;
 static signed int SyncDiff = 0, WishedPeriod;
 static snd_pcm_sframes_t FramesToSend, SentFrames, FramesLeft, BytesLeft, Slack;
 static byte* SamplePointer;
 static cRSID_Output Output;

 //if no CPU-overload, sync: wait for next inputhandler frame's time
 EntryTime = getEpochTimeMicroseconds();
 if (LatestSyncTime == 0) LatestSyncTime = EntryTime;  //bootstrapping
 NewSyncTime = LatestSyncTime + frametime - SyncDiff;
 WishedPeriod = NewSyncTime - LatestSyncTime;
 SyncPeriods = frametime / SYNC_TIME_GRANULARITY; SyncPeriodCount = 0;
 while ( getEpochTimeMicroseconds() < NewSyncTime && SyncPeriodCount++ <= SyncPeriods ) {
  usleep( SYNC_TIME_GRANULARITY ); //if (++SyncPeriodCount > frametime/SYNC_TIME_GRANULARITY /*SYNC_PERIODS_MAX*/) break; //workaround for a possible problematic gettimeofday() implementation to atleast run the C64 code
 }
 SyncTime = getEpochTimeMicroseconds(); SyncDiff = (SyncTime - LatestSyncTime) - WishedPeriod;  //int WorkLoad = EntryTime - LatestSyncTime; int Period = SyncTime - LatestSyncTime; static double AveragePeriod=10000/*INPUTSCAN_PERIOD*//*CLI_KEYCHECK_PERIOD*/+2; AveragePeriod += (Period - AveragePeriod) / 1000.0; /*printf("%d ",WorkLoad);*/ printf( "Last:..%d Entry:..%d  New:..%d Sync:..%d  Work:%d  Wished:%d Period:%d (average:%.0f) Diff:%d\n", (int)(LatestSyncTime&0xFFFFFFF), (int)(EntryTime&0xFFFFFFF), (int)(NewSyncTime&0xFFFFFFF), (int)(SyncTime&0xFFFFFFF),  WorkLoad, WishedPeriod, Period, AveragePeriod, SyncDiff );
 LatestSyncTime = SyncTime /*EntryTime*/; //getEpochTimeMicroseconds();  FrameTimeOverload = WorkLoad - frametime;

 //if (cRSID.Paused) return;
 //cRSID_C64.SoundStarted=1; //set to inform the rest of the code that sound could be started already (buffer callback works)

 //Refresh shadow registers that remain untouched during the audio-generation, to avoid discrepancies if main thread changes their originators (here in the single thread it won't happen btw)
 cRSID_C64.RealSIDmode = cRSID.RealSIDmode; //this one gets updated at SID-data rocessing too when the audio doesn't run, to let CPU routines use the up-to-date shadowed versions
 cRSID_C64.AudioThread_SIDchipCount = cRSID_C64.SIDchipCount;
 cRSID_C64.Stereo = cRSID_C64.AudioThread_SIDchipCount > 1 ? cRSID.Stereo : CRSID_CHANNELMODE_MONO; //this might be changed regularly during playback by the user, and maybe these too:
 cRSID_C64.HighQualitySID = cRSID.HighQualitySID; cRSID_C64.HighQualityResampler = cRSID.HighQualityResampler;

 FramesToSend = ( cRSID_C64.SampleRate * frametime / MICROSECONDS_IN_A_SECOND ) + 1; //ideally these amount of samples would be sent in every round (if no dropouts/whatever happened)
 Slack = SYNC_TIME_GRANULARITY*2 *cRSID_C64.SampleRate/MICROSECONDS_IN_A_SECOND;  if (Slack > cRSID.SampleBufferLength) Slack = cRSID.SampleBufferLength; //lower buffer-drain threshold to propose sending a bit more samples than needed
 if (SoundDevice != NULL) {
  FramesLeft = snd_pcm_avail_update( SoundDevice );  //mvprintw(0,0, "%d , %d    ", (int)FramesToSend, (int)FramesLeft );  //snd_pcm_wait() contains embedded poll waiting implementation
  if (FramesLeft < 0) { //even if there's no audio for some reason, at least emulate a silent C64
   FramesLeft = FramesToSend; //if (!cRSID.Paused) fprintf( stderr, "Audio error %d (%s) ( returned from snd_pcm_avail_update() )\n", (int)FramesLeft, snd_strerror(FramesLeft) );
  }
  else if (FramesLeft > cRSID.SampleBufferLength) FramesLeft = cRSID.SampleBufferLength; //when stopping audio-updates (e.g. in Y/N dialog), older ALSA might give strange big FramesLeft values here like ~18000
 }
 else { FramesLeft = FramesToSend; }   //mvprintw(0,0, "%d , %d  %llu     ", (int)FramesToSend, (int)FramesLeft, (signed long long int)CurrentTime );

 if (/*SampleBuffer!=NULL &&*/ FramesLeft > 0) { // >= FramesToSend - Slack /*&& FramesLeft <= cRSID.SampleBufferLength*/) { //- SAMPLECHUNK_SIZE_SLACK) { //SampleBufferLength/4) {  //if below threshold, wait until next round to send samples
     //Sometimes on X, ALSA gives FramesLeft value of 1 and is stuck there, so we send any bytes that are to be sent to avoid that...
  BytesLeft = FramesLeft * SAMPLE_FRAMESIZE; //if (BytesLeft > SampleBufferSize) { BytesLeft = SampleBufferSize; } //when stopping audio-updates (e.g. in Y/N dialog), older ALSA might give strange big FramesLeft values here like ~18000

  if (SampleBuffer != NULL) {
   for (i = 0; i < BytesLeft /*SampleBufferSize*/ ; i += SAMPLE_FRAMESIZE) {  // frametime*SampleRate/1000000 ?  //while ( clock() < LatestCallTime + frametime )   //cRSID_generateSound( SampleBuffer, SampleBufferSize );
    Output = cRSID_generateSample();
    SampleBuffer[i+0] = Output.L & 0xFF; SampleBuffer[i+1] = Output.L >> 8;
    //#if (SIDAMOUNT>1)
     SampleBuffer[i+2] = Output.R & 0xFF; SampleBuffer[i+3] = Output.R >> 8;
    //#endif
   }
  }
  else { for (i = 0; i < BytesLeft; i += SAMPLE_FRAMESIZE) cRSID_generateSample(); }

  if (SoundDevice != NULL) {
   SamplePointer = SampleBuffer;
   while (FramesLeft > 0) {
    if ( (SentFrames = snd_pcm_writei( SoundDevice, SamplePointer, FramesLeft )) < 0 ) {  //mvprintw(27,0,"%d %d  %d     ",(int)SentFrames,(int)FramesLeft,EAGAIN);
     if (SentFrames==-EAGAIN) { usleep( SAMPLE_SEND_RETRY_DELAY ); continue; }
     if ( (SentFrames = snd_pcm_recover( SoundDevice, SentFrames, 0 ) ) < 0 ) {
      fprintf( stderr, "ALSA-write failed (unrecoverable): %s\n", snd_strerror(SentFrames) ); return;
    }}
    //else if (SentFrames < FramesLeft) ; //mvprintw(1,0, "%d %d", SentFrames, FramesLeft);
    else {
     FramesLeft -= SentFrames; SamplePointer += SentFrames * SAMPLE_FRAMESIZE;  //mvprintw(29,0,"%d  %d    ", (int)SentFrames,  (int)FramesLeft );
    }
   }
  }

 }
 else if (FramesLeft < 0) { //retry ALSA-sound totally in case of serious fault like broken pipe... (but if the code above still ensures machine-emulation this action is not relevant and won't happen)
  fprintf( stderr, "Audio error %d (%s) ( returned from snd_pcm_avail_update() )\n", (int)FramesLeft, snd_strerror(FramesLeft) );
  SIDwizard_resetEngine(0,1); //return;
 }

 //LatestCallTime = clock(); //NextCallTime; //;
  //mvprintw(33,30,"%d  ", (int)(getEpochTimeMicroseconds()-LatestCallTime) );
 //usleep( frametime );
}
#endif


void cRSID_closeSound (void) {
 //cRSID.Paused = 1;
 #if (USING_SDL)
  SDL_PauseAudio(1);
  if (cRSID_C64.SoundStarted) { //SDL_CloseAudio of SDL might freeze if somehow sound-callback didn't start
   SDL_CloseAudio();
  }
 #elif (USING_ALSA)
  if (SoundDevice != NULL) { //&& cRSID_C64.SoundStarted) {
   snd_pcm_drain( SoundDevice );
   snd_pcm_close( SoundDevice ); usleep(10000);
   SoundDevice = NULL;
  }
  if (SampleBuffer != NULL) { free( SampleBuffer ); SampleBuffer = NULL; }
 #endif
}


void cRSID_startSound (void) {
 #if (USING_SDL)
  SDL_PauseAudio(0);
 #elif (USING_ALSA)
  //snd_pcm_pause( SoundDevice, 0 );
 #endif
}


void cRSID_stopSound (void) {
 cRSID.Paused = 1; //cause immediate stopping in audio-buffer thread, so SID-baseaddress changes during tune-switching won't give segfaults
 #if (USING_SDL)
  SDL_PauseAudio(1);
 #elif (USING_ALSA)
  //snd_pcm_pause( SoundDevice, 1 ); //not all devices support this ( snd_pcm_hw_params_can_pause() can tell )
 #endif
}


#endif //CRSID_PLATFORM_PC


void cRSID_generateSound (FASTVAR unsigned char *buf, FASTVAR unsigned short len) { //'len' here is size in bytes
 //enum { FADE_SCALING = 16, MIX_SCALING = (256*FADE_SCALING) };
 FASTVAR unsigned short i; FASTVAR unsigned char j;
 static cRSID_Output Output;
 //FASTVAR signed short OutputL, OutputR;
 //FASTVAR signed int VolumeMul;

 //Refresh shadow registers that remain untouched during the audio-generation, to avoid discrepancies if main thread changes their originators
 cRSID_C64.RealSIDmode = cRSID.RealSIDmode; //this one gets updated at SID-data rocessing too when the audio doesn't run, to let CPU routines use the up-to-date shadowed versions
 cRSID_C64.AudioThread_SIDchipCount = cRSID_C64.SIDchipCount;
 cRSID_C64.Stereo = cRSID_C64.AudioThread_SIDchipCount > 1 ? cRSID.Stereo : CRSID_CHANNELMODE_MONO;  //this might be changed regularly during playback by the user, and maybe these too:
 cRSID_C64.HighQualitySID = cRSID.HighQualitySID; cRSID_C64.HighQualityResampler = cRSID.HighQualityResampler;

 for (i = 0; i < len; i += SAMPLE_FRAMESIZE) {  //sample-size: 2 (mono) or 4 (stereo)
  /*for(j=0; j<cRSID.PlaybackSpeed; ++j)*/ Output = cRSID_generateSample();
  //VolumeMul = cRSID.MainVolume * cRSID_C64.FadeLevel;
  // /* *(signed short*) &buf[i]*/ Output.L = Output.L * VolumeMul / MIX_SCALING;   //can we expect little-endianness?
  // /* *(signed short*) &buf[i+2]*/ Output.R = Output.R * VolumeMul / MIX_SCALING; //can we expect little-endianness?
  buf[i+0] = Output.L & 0xFF; buf[i+1] = Output.L >> 8;
  //#if (SIDAMOUNT>1)
   buf[i+2] = Output.R & 0xFF; buf[i+3] = Output.R >> 8;
  //#endif
 }
}


INLINE cRSID_Output cRSID_generateSample () { //call this from custom buffer-filler
 enum { FADE_SCALING = 16, MIX_SCALING = 256 }; //(256*FADE_SCALING) };

 //FASTVAR signed short VolumeMul;
 //FASTVAR signed short PSIDdigi;
 static cRSID_Output Output;

 if ( RARELY (cRSID.Paused) ) { Output.L = Output.R = 0; return Output; }

 //If calling cRSID_generateSample() directly, don't forget to keep the audio-thread shadow-variables updated, as seen above in cRSID_generateSound()
 //cRSID_C64.RealSIDmode = cRSID.RealSIDmode; //this one gets updated at SID-data rocessing too when the audio doesn't run, to let CPU routines use the up-to-date shadowed versions


 #ifndef SIDMAKER

 Output = *cRSID_emulateC64();
 //if ( RARELY (cRSID.PSIDdigiMode) ) { PSIDdigi = cRSID_playPSIDdigi(); Output.L += PSIDdigi; Output.R += PSIDdigi; }

 //VolumeMul = cRSID.MainVolume * cRSID_C64.FadeLevel;
 Output.L = (Output.L * cRSID.MainVolume/*VolumeMul*/) / MIX_SCALING; //Having the attenuator before saturation allows avoiding filter/many-SIDs overdrive-distortion
 //#if (SIDAMOUNT>1)
  Output.R = (Output.R * cRSID.MainVolume/*VolumeMul*/) / MIX_SCALING; //(By simply adjusting the main volume knob to a lower level. Real SID distorts as well in those cases btw.)
 //#endif

 if ( RARELY(Output.L>=32767) ) Output.L=32767; else if ( RARELY (Output.L<=-32768) ) Output.L=-32768; //saturation arithmetic on overflow
 //#if (SIDAMOUNT>1)
  if ( RARELY(Output.R>=32767) ) Output.R=32767; else if ( RARELY (Output.R<=-32768) ) Output.R=-32768; //saturation arithmetic on overflow
 //#endif

 #if (OSCILLOSCOPE_SHOWS_ALL_CHANNELS)
  enum {  //scope could be filled before main-volume actualization but this way at least the scope shows if there's high-allchannel-filter-resonance distortion at the current level
   SCOPEDATA_STRETCH = 3, SCOPEDATA_STRETCH_MAX = (1 << SCOPEDATA_STRETCH) - 1,
   SCOPEDATA_STRETCH_TUI = 4, SCOPEDATA_STRETCH_MAX_TUI = (1 << SCOPEDATA_STRETCH_TUI) - 1
  };
  extern unsigned char ScopeData [];
  extern short ScopeDataCnt, ScopeDataLength;
  static unsigned char ScopeDataStretchCnt;
  if (ScopeDataCnt < ScopeDataLength && !ScopeDataStretchCnt) {
   ScopeData[ ScopeDataCnt ] = ( (Output.L + Output.R) / 2 + 32768 ) >> 8;  //if (ScopeData > 0xFF) ScopeData = 0xFF; if (ScopeData < 0) ScopeData = 0; //saturation of possible overdrive
   ++ScopeDataCnt;
  }
  ++ScopeDataStretchCnt; ScopeDataStretchCnt &= /*TUImode? SCOPEDATA_STRETCH_MAX_TUI :*/ SCOPEDATA_STRETCH_MAX;

  //cRSID_C64.IObankRD[0xD41B] = ScopeData; //OSC3 for emulated SIDs' oscilloscope display showing all channels
  //cRSID_C64.IObankRD[0xD41C] = 0xFF; //ENV3 is calculated already into the signal here
 #endif


 #else

  cRSID_emulateC64();

 #endif //ifndef SIDMAKER

 return Output;
}

