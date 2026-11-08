


static INLINE cRSID_Output* cRSID_emulateLightSIDs () { //lightweight (all at samplerate-pace) SID-emulations: oscillators, waveforms, filter and complete output stages
 //static enum { VOLUME_MAX=0xF, CHANNELS=3+1 } SIDspecs; //digi-channel is counted too in attenuation

 FASTVAR signed int Tmp, Tmp2;
 static cRSID_Output Output;

 switch (cRSID_C64.Stereo) {
  case CRSID_CHANNELMODE_MONO: { //if ( MOSTLY (cRSID_C64.Stereo==0 /*|| cRSID_C64.AudioThread_SIDchipCount==1*/) ) { //mono
   Output.L /*= Output.R*/ = cRSID_emulateSID_light( &cRSID_C64.SID[1] );
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
    if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) Output.L += cRSID_emulateSID_light( &cRSID_C64.SID[2] );
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
    if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) Output.L += cRSID_emulateSID_light( &cRSID_C64.SID[3] );
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
    if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) Output.L += cRSID_emulateSID_light( &cRSID_C64.SID[4] );
   } //#endif
   Output.R = Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount; //better being multiplied in a single place than for all SIDs
  } break;
  case CRSID_CHANNELMODE_STEREO: { //else { //stereo
   Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[1] );
   if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_LEFT) )  { Output.L = Tmp * 2; Output.R=0; }
   else if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_RIGHT) ) { Output.R = Tmp * 2; Output.L=0; }
   else Output.L = Output.R = Tmp;
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
   if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[2] );
    if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_LEFT)  Output.L += Tmp * 2;
    else if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_RIGHT) Output.R += Tmp * 2;
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
   if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[3] );
    if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_LEFT) )  Output.L += Tmp * 2;
    else if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_RIGHT) ) Output.R += Tmp * 2;
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
   if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[4] );
    if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_LEFT)  Output.L += Tmp * 2;
    else if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_RIGHT) Output.R += Tmp * 2;
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   } //#endif
   Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
   Output.R /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
  } break;
  case CRSID_CHANNELMODE_NARROW: {
   Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[1] );
   if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_LEFT) )  //Output.L = Tmp * 2;
   { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L = Tmp + Tmp2; Output.R = Tmp - Tmp2; }
   else if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_RIGHT) )  //Output.R = Tmp * 2;
   { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R = Tmp + Tmp2; Output.L = Tmp - Tmp2; }
   else Output.L = Output.R = Tmp;
   if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[2] );
    if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_LEFT)  //Output.L += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2; }
    else if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_RIGHT)  //Output.R += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2; }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[3] );
    if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_LEFT) )  //Output.L += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2; }
    else if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_RIGHT) )  //Output.R += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2; }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSID_light( &cRSID_C64.SID[4] );
    if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_LEFT)  //Output.L += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2; }
    else if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_RIGHT)  //Output.R += Tmp * 2;
    { Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2; }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
   Output.R /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
  } break;
 }
 return &Output;
}



static INLINE void cRSID_emulateOversampledSIDwaves () { //averaging oversampler, only oscillators & waveforms (called at samplerate-pace)
 FASTVAR unsigned char HQsampleCount = 0;
 static cRSID_SIDwavOutput SIDwavOutput;

 HQsampleCount=0;
 cRSID_C64.SID[1].NonFiltedSample = cRSID_C64.SID[1].FilterInputSample = 0;
 if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
  cRSID_C64.SID[2].NonFiltedSample = cRSID_C64.SID[2].FilterInputSample = 0;
 } //#endif
 if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
  cRSID_C64.SID[3].NonFiltedSample = cRSID_C64.SID[3].FilterInputSample = 0;
 } //#endif
 if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
  cRSID_C64.SID[4].NonFiltedSample = cRSID_C64.SID[4].FilterInputSample = 0;
 } //#endif
 while (cRSID_C64.OverSampleCycleCnt <= cRSID_C64.SampleClockRatio) {
  SIDwavOutput = cRSID_emulateHQwaves( &cRSID_C64.SID[1], CRSID_OVERSAMPLING_CYCLES );
  cRSID_C64.SID[1].NonFiltedSample += SIDwavOutput.NonFilted; cRSID_C64.SID[1].FilterInputSample += SIDwavOutput.FilterInput;
  if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
   if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
    SIDwavOutput = cRSID_emulateHQwaves( &cRSID_C64.SID[2], CRSID_OVERSAMPLING_CYCLES );
    cRSID_C64.SID[2].NonFiltedSample += SIDwavOutput.NonFilted; cRSID_C64.SID[2].FilterInputSample += SIDwavOutput.FilterInput;
   }
  } //#endif
  if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
   if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
    SIDwavOutput = cRSID_emulateHQwaves( &cRSID_C64.SID[3], CRSID_OVERSAMPLING_CYCLES );
    cRSID_C64.SID[3].NonFiltedSample += SIDwavOutput.NonFilted; cRSID_C64.SID[3].FilterInputSample += SIDwavOutput.FilterInput;
   }
  } //#endif
  if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
   if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
    SIDwavOutput = cRSID_emulateHQwaves( &cRSID_C64.SID[4], CRSID_OVERSAMPLING_CYCLES );
    cRSID_C64.SID[4].NonFiltedSample += SIDwavOutput.NonFilted; cRSID_C64.SID[4].FilterInputSample += SIDwavOutput.FilterInput;
   }
  } //#endif
  ++HQsampleCount;
  cRSID_C64.OverSampleCycleCnt += (CRSID_OVERSAMPLING_CYCLES << CRSID_CLOCK_FRACTIONAL_BITS);
 }
 cRSID_C64.OverSampleCycleCnt -= cRSID_C64.SampleClockRatio;
 //fast resampler - averaging of accumulated samples:
 cRSID_C64.SID[1].NonFiltedSample /= HQsampleCount; cRSID_C64.SID[1].FilterInputSample /= HQsampleCount;
 if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
  if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
   cRSID_C64.SID[2].NonFiltedSample /= HQsampleCount; cRSID_C64.SID[2].FilterInputSample /= HQsampleCount;
  }
 } //#endif
 if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
  if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
   cRSID_C64.SID[3].NonFiltedSample /= HQsampleCount; cRSID_C64.SID[3].FilterInputSample /= HQsampleCount;
  }
 } //#endif
 if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
  if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
   cRSID_C64.SID[4].NonFiltedSample /= HQsampleCount; cRSID_C64.SID[4].FilterInputSample /= HQsampleCount;
  }
 } //#endif
}



static INLINE cRSID_Output* cRSID_emulateOversampledSIDoutputs () { //called at samplerate-pace, filters and complete output stages
 static enum { VOLUME_MAX=0xF, CHANNELS=3+1 } SIDspecs; //digi-channel is counted too in attenuation

 FASTVAR signed int Tmp, Tmp2;
 static cRSID_Output Output;

 switch (cRSID_C64.Stereo) {  //if ( MOSTLY (cRSID_C64.Stereo==0 /*|| cRSID_C64.AudioThread_SIDchipCount==1*/) ) { //mono
  case CRSID_CHANNELMODE_MONO: {
   Output.L /*= Output.R*/ = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[1] ); //, cRSID_C64.HighQualityResampler );
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
    if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) Output.L += cRSID_emulateSIDoutputStage( &cRSID_C64.SID[2] ); //, cRSID_C64.HighQualityResampler );
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
    if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) Output.L += cRSID_emulateSIDoutputStage( &cRSID_C64.SID[3] ); //, cRSID_C64.HighQualityResampler );
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
    if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) Output.L += cRSID_emulateSIDoutputStage( &cRSID_C64.SID[4] ); //, cRSID_C64.HighQualityResampler );
   } //#endif
   Output.R = Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount; //better being multiplied in a single place than for all SIDs
  } break;
  case CRSID_CHANNELMODE_STEREO: { //else { //stereo
   Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[1] ); //, cRSID_C64.HighQualityResampler );
   if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_LEFT) ) { Output.L = Tmp * 2; Output.R=0; }
   else if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_RIGHT) ) { Output.R = Tmp * 2; Output.L=0; }
   else Output.L = Output.R = Tmp;
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
    if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
     Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[2] ); //, cRSID_C64.HighQualityResampler );
     if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_LEFT)  Output.L += Tmp * 2;
     else if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_RIGHT) Output.R += Tmp * 2;
     else { Output.L += Tmp; Output.R += Tmp; }
    }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
    if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
     Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[3] ); //, cRSID_C64.HighQualityResampler );
     if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_LEFT) ) Output.L += Tmp * 2;
     else if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_RIGHT) ) Output.R += Tmp * 2;
     else { Output.L += Tmp; Output.R += Tmp; }
    }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
    if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
     Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[4] ); //, cRSID_C64.HighQualityResampler );
     if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_LEFT)  Output.L += Tmp * 2;
     else if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_RIGHT) Output.R += Tmp * 2;
     else { Output.L += Tmp; Output.R += Tmp; }
    }
   } //#endif
   Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
   Output.R /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
  } break;
  case CRSID_CHANNELMODE_NARROW: {  //narrowed stereo (channels are closer to each other and the center)
   Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[1] ); //, cRSID_C64.HighQualityResampler );
   if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_LEFT) ) {
    Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L = Tmp + Tmp2; Output.R = Tmp - Tmp2;
   }
   else if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_RIGHT) ) {
    Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R = Tmp + Tmp2; Output.L = Tmp - Tmp2;
   }
   else Output.L = Output.R = Tmp;
   if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[2] ); //, cRSID_C64.HighQualityResampler );
    if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_LEFT) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2;
    }
    else if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_RIGHT) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2;
    }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[3] ); //, cRSID_C64.HighQualityResampler );
    if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_LEFT) ) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2;
    }
    else if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_RIGHT) ) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2;
    }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
    Tmp = cRSID_emulateSIDoutputStage( &cRSID_C64.SID[4] ); //, cRSID_C64.HighQualityResampler );
    if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_LEFT) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.L += Tmp + Tmp2; Output.R += Tmp - Tmp2;
    }
    else if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_RIGHT) {
     Tmp2 = Tmp >> CRSID_CHANNELPANNING_DIVSHIFTS;  Output.R += Tmp + Tmp2; Output.L += Tmp - Tmp2;
    }
    else { Output.L += Tmp; Output.R += Tmp; }
   }
   Output.L /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
   Output.R /= cRSID_C64.Attenuation; //( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation );  // * cRSID_C64.AudioThread_SIDchipCount;
  } break;
 }
 return &Output;
}



static INLINE void cRSID_emulateHQresampledSIDs () { //oscillators, waveforms, filter and attenuation (main-volume) (called at samplerate-pace, but core at oversampled rate)
 static enum {
  //RESAMPLER_FRACTIONAL_BITS = 12,
  FRACTIONAL_MUL = (1 << CRSID_RESAMPLER_FRACTIONAL_BITS), //4096 $1000
  FRACTIONAL_AND = (FRACTIONAL_MUL-1), //4095 $0FFF
  INTEGER_AND = (-FRACTIONAL_MUL), //$F000
  RESAMPLEBUFFER_SIZE = 16, //entries
   RESAMPLEBUFFER_SIZE_MUL = (RESAMPLEBUFFER_SIZE << CRSID_RESAMPLER_FRACTIONAL_BITS),
  SINCWINDOW_PERIODS = (CRSID_RESAMPLER_SINCWINDOW_PERIODS), //12, //half-sines
   SINCWINDOW_HALF1_LAST_PERIOD = (SINCWINDOW_PERIODS/2-1),
  SINCPERIOD_SAMPLES = (CRSID_RESAMPLER_SINCPERIOD_SAMPLES), //128, //entries
   SINCWINDOW_SIZE = (SINCWINDOW_PERIODS*SINCPERIOD_SAMPLES), //1536
   SINCPERIOD_BITS = ( CRSID_BYTE_LOG2( SINCPERIOD_SAMPLES ) ), //7, //log2(SINCPERIOD_SAMPLES)
    SINCPERIOD_BITS_REVERSE = (CRSID_RESAMPLER_FRACTIONAL_BITS-SINCPERIOD_BITS),
  //SINCWINDOW_RESOLUTION = 11, //bits
   SINCWINDOW_MAGNITUDE = (CRSID_RESAMPLER_SINCWINDOW_MAGNITUDE) //(1 << SINCWINDOW_RESOLUTION) //SINCWINDOW_VALUE_MAX = 2048 // (2**SINCWINDOW_RESOLUTION)
 } AudioResamplerParameters;

 FASTVAR signed int Tmp, Left, Right;
 FASTVAR signed char Mono, ResampleBufWritePos = 0;
 FASTVAR int SincWindowPos;
 static int ResampleBufPos=0, NextResampleBufPos=FRACTIONAL_MUL;
 static signed int ResampleBufferL [RESAMPLEBUFFER_SIZE] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
 static signed int ResampleBufferR [RESAMPLEBUFFER_SIZE] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
 #include "SincWindow.h"

 cRSID_precalculateHQoutputParameters( &cRSID_C64.SID[1] );
 if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
  if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) cRSID_precalculateHQoutputParameters( &cRSID_C64.SID[2] );
 } //#endif
 if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
  if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) cRSID_precalculateHQoutputParameters( &cRSID_C64.SID[3] );
 } //#endif
 if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
  if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) cRSID_precalculateHQoutputParameters( &cRSID_C64.SID[4] );
 } //#endif
 Mono = (cRSID_C64.Stereo==CRSID_CHANNELMODE_MONO) /*|| cRSID_C64.AudioThread_SIDchipCount==1*/;

 while (ResampleBufPos < NextResampleBufPos) {
  ResampleBufWritePos = (ResampleBufPos >> CRSID_RESAMPLER_FRACTIONAL_BITS) - SINCWINDOW_HALF1_LAST_PERIOD;
   if (ResampleBufWritePos < 0) ResampleBufWritePos += RESAMPLEBUFFER_SIZE;
  SincWindowPos = SINCPERIOD_SAMPLES - ( (ResampleBufPos & FRACTIONAL_AND) >> SINCPERIOD_BITS_REVERSE );

  if ( MOSTLY (Mono) ) { //mono
   Left /*= Right*/ = cRSID_emulateHQresampledSID( &cRSID_C64.SID[1], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
    if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) Left += cRSID_emulateHQresampledSID( &cRSID_C64.SID[2], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
    if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) Left += cRSID_emulateHQresampledSID( &cRSID_C64.SID[3], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
    if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) Left += cRSID_emulateHQresampledSID( &cRSID_C64.SID[4], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
   } //#endif
   //Right = Left;
   while (SincWindowPos < SINCWINDOW_SIZE) { //Resampling subsequent stereo samples to output-sample-buffer
    ResampleBufferL[ResampleBufWritePos] += (Left * SincWindow[SincWindowPos]) / SINCWINDOW_MAGNITUDE; // >> SINCWINDOW_RESOLUTION;
    ++ResampleBufWritePos; if (ResampleBufWritePos >= RESAMPLEBUFFER_SIZE) ResampleBufWritePos=0;
    SincWindowPos += SINCPERIOD_SAMPLES;
   }
  }
  else { //stereo
   Tmp = cRSID_emulateHQresampledSID( &cRSID_C64.SID[1], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
   if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_LEFT) ) { Left = Tmp * 2; Right=0; }
   else if ( RARELY (cRSID_C64.SID[1].Channel == CRSID_CHANNEL_RIGHT) ) { Right = Tmp * 2; Left=0; }
   else Left = Right = Tmp;
   if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
    if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) {
     Tmp = cRSID_emulateHQresampledSID( &cRSID_C64.SID[2], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
     if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_LEFT)  Left += Tmp * 2;
     else if (cRSID_C64.SID[2].Channel == CRSID_CHANNEL_RIGHT) Right += Tmp * 2;
     else { Left += Tmp; Right += Tmp; }
    }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
    if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) {
     Tmp = cRSID_emulateHQresampledSID( &cRSID_C64.SID[3], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
     if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_LEFT) ) Left += Tmp * 2;
     else if ( UNLIKELY (cRSID_C64.SID[3].Channel == CRSID_CHANNEL_RIGHT) ) Right += Tmp * 2;
     else { Left += Tmp; Right += Tmp; }
    }
   } //#endif
   if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
    if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) {
     Tmp = cRSID_emulateHQresampledSID( &cRSID_C64.SID[4], CRSID_OVERSAMPLING_CYCLES ); //.Mix;
     if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_LEFT)  Left += Tmp * 2;
     else if (cRSID_C64.SID[4].Channel == CRSID_CHANNEL_RIGHT) Right += Tmp * 2;
     else { Left += Tmp; Right += Tmp; }
    }
   } //#endif
   while (SincWindowPos < SINCWINDOW_SIZE) { //Resampling subsequent stereo samples to output-sample-buffer
    ResampleBufferL[ResampleBufWritePos] += (Left * SincWindow[SincWindowPos]) / SINCWINDOW_MAGNITUDE; // >> SINCWINDOW_RESOLUTION;
    ResampleBufferR[ResampleBufWritePos] += (Right * SincWindow[SincWindowPos]) / SINCWINDOW_MAGNITUDE; // >> SINCWINDOW_RESOLUTION;
    ++ResampleBufWritePos; if (ResampleBufWritePos >= RESAMPLEBUFFER_SIZE) ResampleBufWritePos=0;
    SincWindowPos += SINCPERIOD_SAMPLES;
   }
  }

  ResampleBufPos += cRSID_C64.OversampleClockRatio;
 }

 if (ResampleBufPos >= RESAMPLEBUFFER_SIZE_MUL) ResampleBufPos -= RESAMPLEBUFFER_SIZE_MUL;
  NextResampleBufPos = (ResampleBufPos & INTEGER_AND) + FRACTIONAL_MUL;
 cRSID_C64.ResampledOutput.L = ResampleBufferL[ResampleBufWritePos] / cRSID_C64.OversampleClockRatioReciproc;
  ResampleBufferL[ResampleBufWritePos] = 0;
 if ( RARELY (!Mono) ) { //stereo
  cRSID_C64.ResampledOutput.R = ResampleBufferR[ResampleBufWritePos] / cRSID_C64.OversampleClockRatioReciproc;
   ResampleBufferR[ResampleBufWritePos] = 0;
 }
}



static INLINE cRSID_Output* cRSID_emulateHQresampledSIDoutputs () { //called at samplerate-pace, only adding digi and final attenuation
 static enum { VOLUME_MAX=0xF, CHANNELS=3+1 } SIDspecs; //digi-channel is counted too in attenuation

 FASTVAR signed int Tmp;
 static cRSID_Output Output;

 cRSID_emulateHQresampledSIDdigi( &cRSID_C64.SID[1], &cRSID_C64.ResampledOutput );
 if (cRSID_C64.SIDchipCount >= 2) { //#if (SIDAMOUNT>=2)
  if ( TIGHTLY (cRSID_C64.SID[2].BaseAddress != 0) ) cRSID_emulateHQresampledSIDdigi( &cRSID_C64.SID[2], &cRSID_C64.ResampledOutput );
 } //#endif
 if (cRSID_C64.SIDchipCount >= 3) { //#if (SIDAMOUNT>=3)
  if ( TIGHTLY (cRSID_C64.SID[3].BaseAddress != 0) ) cRSID_emulateHQresampledSIDdigi( &cRSID_C64.SID[3], &cRSID_C64.ResampledOutput );
 } //#endif
 if (cRSID_C64.SIDchipCount >= 4) { //#if (SIDAMOUNT>=4)
  if ( TIGHTLY (cRSID_C64.SID[4].BaseAddress != 0) ) cRSID_emulateHQresampledSIDdigi( &cRSID_C64.SID[4], &cRSID_C64.ResampledOutput );
 } //#endif

 Output.L = cRSID_C64.ResampledOutput.L / cRSID_C64.Attenuation; //( ( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation ) );  // * cRSID_C64.AudioThread_SIDchipCount ); //better being multiplied in a single place than for all SIDs
 Output.R = TIGHTLY (cRSID_C64.Stereo!=CRSID_CHANNELMODE_MONO /*&& cRSID_C64.AudioThread_SIDchipCount>1*/) ?
             cRSID_C64.ResampledOutput.R / cRSID_C64.Attenuation //( ( (CHANNELS*VOLUME_MAX) + cRSID_C64.Attenuation ) ) // * cRSID_C64.AudioThread_SIDchipCount )
             : Output.L;

 return &Output; //&cRSID_C64.ResampledOutput; //&Output;
}



static INLINE short cRSID_playPSIDdigi () {
 //static cRSID_C64instance* C64 = &cRSID_C64;

 enum PSIDdigiSpecs {
  D418_VOL_RANGE=0x10, DIGI_MAX = (D418_VOL_RANGE-1), DIGI_MASK=(DIGI_MAX), DIGI_MID = (D418_VOL_RANGE/2),
  OUTPUT_RESOLUTION=16, SID_CHANNELS=3+1, NOMINAL_DIGI_RANGE = ( (1 << OUTPUT_RESOLUTION) / SID_CHANNELS ), //16384
  DIGI_VOLUME=128 /*55*/, DIGI_VOLUME_DENOM=16, NOMINAL_DIGI_MUL = (NOMINAL_DIGI_RANGE / D418_VOL_RANGE), //1024
  DIGI_MUL = (NOMINAL_DIGI_MUL * DIGI_VOLUME / DIGI_VOLUME_DENOM) * CRSID_PRESAT_ATT_DENOM / CRSID_PRESAT_ATT_NOM
 };

 FASTVAR unsigned char Shifts;
 static unsigned char PlaybackEnabled=0, NybbleCounter=0, RepeatCounter=0;
 FASTVAR unsigned short RatePeriod;
 static unsigned short SampleAddress = 0;
 static int Output=0; //need to be static to keep level between calls
 static int PeriodCounter = 0;

 if ( cRSID_C64.IObankWR[0xD41D] ) {
  PlaybackEnabled = (cRSID_C64.IObankWR[0xD41D] >= 0xFE);
  PeriodCounter = 0; NybbleCounter = 0;
  SampleAddress = cRSID_C64.IObankWR[0xD41E] + (cRSID_C64.IObankWR[0xD41F]<<8);
  RepeatCounter = cRSID_C64.IObankWR[0xD43F];
 }
 cRSID_C64.IObankWR[0xD41D] = 0;

 if (PlaybackEnabled) {
  RatePeriod = cRSID_C64.IObankWR[0xD45D] + (cRSID_C64.IObankWR[0xD45E]<<8);
  if (RatePeriod) PeriodCounter += cRSID_C64.CPUfrequency / RatePeriod;
  if ( PeriodCounter >= cRSID_C64.SampleRate ) {
   PeriodCounter -= cRSID_C64.SampleRate;

   if ( SampleAddress < cRSID_C64.IObankWR[0xD43D] + (cRSID_C64.IObankWR[0xD43E]<<8) ) {
    if (NybbleCounter) {
     Shifts = cRSID_C64.IObankWR[0xD47D] ? 4:0;
     ++SampleAddress;
    }
    else Shifts = cRSID_C64.IObankWR[0xD47D] ? 0:4;
    Output = ( ( (cRSID_C64.RAMbank[SampleAddress]>>Shifts) & DIGI_MASK) - DIGI_MID ) * DIGI_MUL; //* DIGI_VOLUME; //* (cRSID_C64.IObankWR[0xD418]&0xF);
    NybbleCounter^=1;
   }
   else if (RepeatCounter) {
    SampleAddress = cRSID_C64.IObankWR[0xD47F] + (cRSID_C64.IObankWR[0xD47E]<<8);
    RepeatCounter--;
   }

  }
 }

 return (Output / cRSID_C64.Attenuation);
}

