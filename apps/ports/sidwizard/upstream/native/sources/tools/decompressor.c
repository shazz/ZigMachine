//A simple RLE, dictionary-based pattern-matching, and arithmetic-coding based decompressor by Hermit
//Includable in programs to decompress data compressed with 'compress'


#include "compression.h"

#ifndef VERSION
 #define VERSION ""
#endif


static inline int Compression_getSetDecompressMode (int mode) {
 static int DecompressionMode = COMPRESSION_MODE__NORMAL;
 if (mode != COMPRESSION_MODE__GET) DecompressionMode = mode;
 return DecompressionMode;
}

static inline void Compression_setDecompressMode (int mode) { Compression_getSetDecompressMode( mode ); }

static inline int Compression_getDecompressMode () { return Compression_getSetDecompressMode( COMPRESSION_MODE__GET ); }

static inline int Compression_decompressModeInPlace () { return Compression_getDecompressMode() == COMPRESSION_MODE__IN_PLACE; }

static inline int Compression_decompressModeSFX () { return Compression_getDecompressMode() == COMPRESSION_MODE__SELF_EXTRACT; }
static inline int Compression_decompressModeRLESFX () { return Compression_getDecompressMode() == COMPRESSION_MODE__RLE_SELF_EXTRACT; }



static inline int Compression_readWord (unsigned char* data, int index) {  //read little-endian word from data-array at index
 return ( data[ index + 0 ] & COMPRESSION_LOWBYTE_MASK ) | ( data[ index + 1 ] << COMPRESSION_HIGHBYTE_SHIFTS );
}


static inline int Compression_readVariableLengthNumber (unsigned char* input, int* output) {
 register int ByteCount, Shifts;
 *output = ByteCount = Shifts = 0;
 do {
  *output |= ( ( input[ ByteCount ] & COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEMASK ) >> COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUESHIFTS ) << Shifts;  //shift according to current byte-amount (numeral place)
  Shifts += COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_MULSHIFTS;  //increase shift-amount for upcoming higher bytes
 } while ( input[ ByteCount++ ] & COMPRESSION_VARIABLE_LENGTH_NUMBER_NEXTBYTE_SIGN_BITVALUE );  //until no more bytes
 return ByteCount;
}


static inline int Compression_readVariableLengthNumberWithSFXcheck (unsigned char* input, int* output) {
 register int ByteCount = 0;
 if ( Compression_decompressModeSFX() /*|| Compression_decompressModeRLESFX()*/ ) {  //C64 SFX/MEM has special max. 2byte variable-length number more effective for max value of 128*256 = 32768
  *output = ( input[ ByteCount ] & COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEMASK ) >> COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUESHIFTS;
  if ( input[ ByteCount++ ] & COMPRESSION_VARIABLE_LENGTH_NUMBER_NEXTBYTE_SIGN_BITVALUE ) {
   *output |= ( ( input[ ByteCount++ ] & COMPRESSION_VALUEMASK__BYTE ) >> COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUESHIFTS ) << COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_MULSHIFTS;
  }
 }
 else if ( Compression_decompressModeRLESFX() ) {  //RLE-SFX self-extraction code has space for handling only 1byte (0...255) repeat-count (COMPRESSION_SFX_RLE_SEQUENCE_LENGTH_MAX)
  output[0] = input[0]; return 1;
 }
 else ByteCount = Compression_readVariableLengthNumber( input, output );
 return ByteCount;
}



int Compression_decompressValueRepeats (unsigned char* inputdata, int inputsize, unsigned char* outputdata) {
 int i,j, CheckBase, RepeatCount, OutputSize;  //RunLength-encoded (RLE) data decompression

 for (i = OutputSize = CheckBase = RepeatCount = 0; i < inputsize; ++i) {
  if (RepeatCount >= COMPRESSION_RLE_REPEATCOUNT_COMPRESSION_THRESHOLD) {  //Itt a lenyeg:  :)
   i += Compression_readVariableLengthNumberWithSFXcheck( &inputdata[i], &RepeatCount );
   for (j=0; j < RepeatCount; ++j) outputdata[ OutputSize++ ] = inputdata[ CheckBase ];
   CheckBase = i;  i -= 1;  RepeatCount = 0;
  }
  else {  //detecting repeats
   if ( inputdata[i] == inputdata[ CheckBase ] && i > CheckBase ) {  //matching  //omitting (i > CheckBase) would produce shorter escape-sequence for 1st/adjacent compressed RLE-sequences (2 times the same value with more repeat-count, instead of 3 times plus less repeat-count), this fix breaks backward-compatibility
    outputdata[ OutputSize++ ] = inputdata[i];  //this write should be AFTER the enclosing 'if' not to overwrite checkbase-data in RLE in-place extraction mode
    ++RepeatCount;
   }
   else { outputdata[ OutputSize++ ] = inputdata[i]; CheckBase = i; RepeatCount = 0; }  //not matching
  }
 }

 return OutputSize;
}



static inline int Compression_getPrefixType (unsigned char* input) {  //converts SFX-type to normal type in SFX-mode
 if ( Compression_decompressModeSFX() ) {  //SFX-mode has different prefix-type bit-positions (type-bits are LSBs for smaller C64 decision tree with 'lsr-bcs' pairs, and values without the need to AND-masking)
  return (*input & 3) ? (*input >> 2) | ((*input & 1) << 7) | ((*input & 2) << 5)
           : ( (*input & 4) ? (*input >> 3) | ((*input & 4) << 3) : (*input >> 4) | ((*input & 8) << 1) );
 }
 return *input;
}


static inline int Compression_readSequencePrefix (unsigned char* input, int* offset, int* length) {
 register int Temp, Type, ByteCount = 1;
 Type = Compression_getPrefixType( input );

 if (Type < COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_END) {  //read literal sequence prefix
  *offset = COMPRESSION_PATTERNMATCH_OFFSET_VALUE__LITERAL_SEQUENCE;
  if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_NEXTBYTE) {  //long matchlength16.. in next bytes (variable-length number)
   if ( Compression_decompressModeSFX() ) { *length = input[ ByteCount++ ]; }
   else {
    ByteCount += Compression_readVariableLengthNumber( &input[ ByteCount ], length );
    *length += COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_LITERAL_LENGTH_MIN;
  }}
  else { *length = Type + COMPRESSION_PATTERNMATCH_LITERAL_BYTE1_LENGTH_VALUEDIFF; }  //1byte length1..15 literal-sequence prefix
 }
 else if (Type < COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_END || Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE) {  //read patternmatch length 5.. prefix
  if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE || Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE_DISTANCE0) { //changed in v1.1 //(Type >= COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE_DISTANCE0) {  //read matchlength19.. prefix with length and Distance in next bytes (variable-length numbers)
   if ( Compression_decompressModeSFX() ) {
    *length = input[ ByteCount++ ];  //subtracting min-value just like with matchlen5..19 makes C64 SFX-code a bit shorter and enhances length-range a bit:
    if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE) *length += COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_VALUEDIFF;
   }
   else {
    ByteCount += Compression_readVariableLengthNumber( &input[ ByteCount ], length );  //read match-length value
    *length += COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_BIGGEST_MATCHLENGTH_MIN;
   }
   if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE) {
    ByteCount += Compression_readVariableLengthNumberWithSFXcheck( &input[ ByteCount ], offset );  //read distance (end-offset) value
   }  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE_DISTANCE0:
   else *offset = 0;  //matchlength19.. prefix with length in next bytes (variable-length number) and zero distance (end-offset)
  }
  else {  //read matchlength5..19  with Distance in next bytes (variable-length-number)
   *length = Type - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_VALUEDIFF;
   ByteCount += Compression_readVariableLengthNumberWithSFXcheck( &input[ ByteCount ], offset );  //read distance (end-offset) value
  }
  *offset += *length; //transform distance (end-offset) to start-offset
 }
 else if (Type < COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__END) { //read patternmatch length4 prefix with Distance high-bits in variable-length number
  /*if ( Compression_decompressModeSFX() )*/ *offset = input[ ByteCount++ ];  //disabled emitting a variable-length number for length4 for simpler SFX-extractor code, and using bit7 enhances range to a doubled 0..8192 too as a bonus
  //else ByteCount += Compression_readVariableLengthNumber( &input[ ByteCount ], offset );  //read distance (end-offset) value
  *offset <<= COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_MATCHLENGTH4_DISTANCE_DIVSHIFTS;  //Distance high-bits
  *offset |= Type - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__BASE;  //Distance low-bits
  *offset += (*length = 4);  //transform distance (end-offset) to offset
 }
 else if (Type < COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__END) { //read 1byte patternmatch length3 prefix (single-byte)
  if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__RLE) {
   *offset = COMPRESSION_PATTERNMATCH_OFFSET_VALUE__RLE_SEQUENCE;
   if ( Compression_decompressModeSFX() ) { *length = input[ ByteCount++ ]; }
   else {
    ByteCount += Compression_readVariableLengthNumber( &input[ ByteCount ], length );
    *length += COMPRESSION_PATTERNMATCH_PREFIX_RLE_LENGTH_MIN;
  }}
  else {
   *offset = Type - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE;
   *offset -= COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BASE;  //modified prefix special 1st value shifts the distance-value range by 1
   *offset += (*length = 3);  //transform distance (end-offset) to offset
  }
 }
 else if (Type < COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__END) { //read 1byte patternmatch length2 prefix
  if (Type == COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__END_OF_DATA) {  //for the moment only SFX uses END_OF_DATA signaling (to reduce C64 self-extractor's code-size for end/length-checking) but this value is alwyas reserved for that
   *offset = COMPRESSION_PATTERNMATCH_MATCHLENGTH2_OFFSET_VALUE__END_OF_DATA; *length = 0; return 1;
  }
  else {
   *offset = Type - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__BASE;
   *offset -= COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_BASE;  //likening length2 to length3 for shorter code in SFX asm-code causes shift (and shortening) in the value-range by 1, no much difference in compression-ratio
   *offset += (*length = 2);  //transform distance (end-offset) to offset
  }
 }
 else { //if (Type >= COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3_WITH_NEXTBYTE__BASE) {  //read patternmatch length3 prefix (with lowbits of Distance, followed by next byte of Distance highbits)
  /*if ( !Compression_decompressModeSFX() )*/ *offset = input[ ByteCount++ ]; //improved length3 by using bit7 instead of var-length number not wort being used here
  //else ByteCount += Compression_readVariableLengthNumber( &input[ ByteCount ], offset );  //read distance (end-offset) value
  *offset <<= COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_MATCHLENGTH3_DISTANCE_DIVSHIFTS;  //Distance high-bits
  *offset |= Type - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3_WITH_NEXTBYTE__BASE;
  if ( !Compression_decompressModeSFX() ) *offset += COMPRESSION_PATTERNMATCH_PREFIX_MATCHLENGTH3_BIG_DISTANCE_MIN;  //further optimization of this case, a bit less chance of the need for high-byte
  *offset += (*length = 3);  //transform distance (end-offset) to offset
 }

 return ByteCount;
}



int Compression_decompressPatternMatches (unsigned char* inputdata, int inputsize, unsigned char* outputdata) {
 int i, Temp, InputIndex, PrefixLength, Offset, Length, MatchPrefixRepeatCount = 0, OutputSize;   //Pattern-matched data decompression

 InputIndex = MatchPrefixRepeatCount = OutputSize = 0;

 while (InputIndex < inputsize) {
  PrefixLength = Compression_readSequencePrefix( &inputdata[ InputIndex ], &Offset, &Length );  //printf("Offset:%X, Length:%X, InputIndex %X\n", Offset, Length, InputIndex);

  if (Offset == COMPRESSION_PATTERNMATCH_OFFSET_VALUE__LITERAL_SEQUENCE) {  //simple literal sequence
   InputIndex += PrefixLength;
   for (i=0; i < Length; ++i) outputdata[ OutputSize++ ] = inputdata[ InputIndex++ ];
   #if (COMPRESSION_SHOW)
    if (COMPRESSION_SHOW_STARTINDEX < 0 || ( COMPRESSION_SHOW_STARTINDEX <= OutputSize-Length && OutputSize-Length < COMPRESSION_SHOW_STARTINDEX + COMPRESSION_SHOW_RANGE ) ) {
     printf( "Literal sequence at input[$%.4X] and output[$%.4X]: length:$%X prefix: ", InputIndex-Length-PrefixLength, OutputSize-Length, Length );
     for (i=0; i < PrefixLength; ++i) printf( "$%.2X ", inputdata[ InputIndex - Length - PrefixLength + i ] );  printf( ", data: " );
     for (i=0; i < Length; ++i) printf( "$%.2X ", inputdata[ InputIndex - Length + i ] );  printf("\n");
    }
   #endif
  }

  else if (Offset == COMPRESSION_PATTERNMATCH_OFFSET_VALUE__RLE_SEQUENCE) { //value-RLE, or SFX patternmatch-prefix repeat
   InputIndex += PrefixLength;
   if ( Compression_decompressModeSFX() ) { MatchPrefixRepeatCount = Length; }  //for (i=0; i < (Length << COMPRESSION_HIGHBYTE_SHIFTS); ++i) outputdata[ OutputSize++ ] = inputdata[ InputIndex ];
   else { for (i=0; i < Length; ++i) outputdata[ OutputSize++ ] = inputdata[ InputIndex ]; ++InputIndex; } //an additional step for the RLE-repeated character
  }

  else {  //matching pattern-data reference
   for (i=0; i < Length; ++i) outputdata[ OutputSize + i ] = outputdata[ OutputSize - Offset + i ];
   #if (COMPRESSION_SHOW)
    if (COMPRESSION_SHOW_STARTINDEX < 0 || ( COMPRESSION_SHOW_STARTINDEX <= OutputSize && OutputSize < COMPRESSION_SHOW_STARTINDEX + COMPRESSION_SHOW_RANGE ) ) {
     if (MatchPrefixRepeatCount <= 0) {
      printf( "Pattern-match at output[$%.4X] with output[$%.4X] (distance:%.4X): length:$%X input[%.4X] prefix: ", OutputSize, OutputSize - Offset, Offset-Length, Length, InputIndex );
      for (i=0; i < PrefixLength; ++i) printf( "$%.2X ", inputdata[ InputIndex + i ] );  printf( ", data: " );
      for (i=0; i < Length; ++i) printf( "$%.2X ", outputdata[ OutputSize + i ] );  printf("\n");
     }
     else if (MatchPrefixRepeatCount == 1) printf( "Repeated pattern-match prefix:\n" );
    }
   #endif
   if (MatchPrefixRepeatCount > 0) --MatchPrefixRepeatCount;  //if repeating, don't increase input-index (reusing the same pattern-match prefix)
   else InputIndex += PrefixLength;
   OutputSize += Length;
  }

 }

 return OutputSize;
}



static inline int Compression_readValueBand (unsigned char* data, unsigned int* index) {
 int Value = data[ (*index)++ ] & COMPRESSION_LOWBYTE_MASK;
 if (COMPRESSION_ARITHMETIC_PROBABILITY_BYTECOUNT >= 2) Value |= data[ (*index)++ ] << COMPRESSION_HIGHBYTE_SHIFTS;
 return Value;
}

static int Compressor_readBit (unsigned char* inputbuffer, unsigned int* bufferindex, int inputsize, int* octet, int* octet_bitcounter) {
 register int BitValue;
 if ( (*octet_bitcounter)-- == 0 ) {
  if ( (int)*bufferindex < inputsize ) {
   *octet_bitcounter = COMPRESSION_BITS_PER_BYTE - 1;
   *octet = inputbuffer[ *bufferindex ]; ++(*bufferindex);  if(COMPRESSION_SHOW) printf("Octet:%.2X ",*octet);
  }
  else {  if(COMPRESSION_SHOW)printf("EOF ");
   *octet_bitcounter = 0;  return COMPRESSION_ARITHMETIC_VALUE__BITREAD_EOF;
  }
 }
 BitValue = (*octet >> *octet_bitcounter) & 1;  if(COMPRESSION_SHOW)printf("Bit:%d ",BitValue);
 return BitValue;
}


int Compression_decompressArithmetic (unsigned char* inputdata, int inputsize, unsigned char* outputdata) {  //Implementation loosely based on Mark Nelson's 2014 article 'Data Compression With Arithmetic Coding'
 static enum {  //Arithmetic-coding method of entropy compression / range-encoder (better than binary-oriented Huffman method)
  DISPSHIFTS = (COMPRESSION_ARITHMETIC_CALC_BITCOUNT/*32*/ - COMPRESSION_ARITHMETIC_PROBABILITY_BITCOUNT/*16*/) /*16*/,
  CHARTSHIFTS = (COMPRESSION_ARITHMETIC_CALC_BITCOUNT/*32*/ - COMPRESSION_CHART_WIDTH_SHIFTS/*6*/) /*26*/,
  CHARTWIDTH = (1 << COMPRESSION_CHART_WIDTH_SHIFTS) /*64*/, CHARTPARTCOUNT = 4,
  GRIDMASK = ( ( CHARTWIDTH / CHARTPARTCOUNT ) - 1 ) /*0xF*/
 } ArithmeticDecoding_Specs;
 register int i, j;  register unsigned int Temp, Temp2;  int OutputValue, OutputSize = 0;
 unsigned int InputIndex = 0, LowIndex, ValuebandTableZeroValueCount = 0;
 int Octet = 0x00, OctetBitCounter = 0;
 unsigned int Range, High, Low, InputValue, ScaledInputValue;  //invariant rule: Low <= InputValue < High  (pseudo-infinite variables, always having a 'window' between MSB/Carry ind input-bits of current iteration)
 static unsigned int ValueBands [COMPRESSION_ARITHMETIC_VALUEBANDTABLE_SIZE];  //table of probability-based valuebands/ranges/segments
 static unsigned int HighIndexes [COMPRESSION_ARITHMETIC_VALUEBANDTABLE_SIZE];  //probability indexes of next valid byte-value (pointing to 'high' value's index)

 for (i = 0, InputIndex = LowIndex = ValuebandTableZeroValueCount = 0; i < COMPRESSION_VALUERANGE__BYTE; ++i) {  //read and reconstruct byte-value probability/range model based valueband-table that was used for compression
  if (ValuebandTableZeroValueCount < COMPRESSION_ARITHMETIC_VALUEBANDTABLE_END_ENDVALUE_COUNT) {
   ValueBands[i] = Compression_readValueBand( inputdata, &InputIndex );
   if ( ValueBands[i] == COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_END ) {
    ++ValuebandTableZeroValueCount;
    if (ValuebandTableZeroValueCount >= COMPRESSION_ARITHMETIC_VALUEBANDTABLE_END_ENDVALUE_COUNT) {
     ValueBands[i] = COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE;
   }}
   if (ValueBands[i] != COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE) LowIndex = HighIndexes[LowIndex] = i;
  }
  else { //fill the rest of table with nonexistent byte-value's signal
   ValueBands[i] = COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE;
  }
 }
 HighIndexes[ LowIndex ] = COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA /*+ 1*/;  //'+1' because last $FFFF should have a chance too with very low (8bit) valueband-table resolutions
 ValueBands[ COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA ] = Compression_readValueBand( inputdata, &InputIndex );
 HighIndexes[ COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA ] = COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA + 1;
 ValueBands[ COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA + 1 ] = COMPRESSION_ARITHMETIC_PROBABILITY_MAX/*RANGE*/;  if (COMPRESSION_SHOW) { for (i=0; i < COMPRESSION_ARITHMETIC_VALUEBANDTABLE_SIZE; ++i) if (i >= COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA || ValueBands[i]!=COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE) printf("%.2X:%.4X..[%.2X]  ",i,ValueBands[i],HighIndexes[i]);  printf("\nReading first InputValue bits\n"); }

 for (i = InputValue = Octet = OctetBitCounter = OutputSize = 0 ; i < COMPRESSION_ARITHMETIC_CALC_BITCOUNT; ++i) {  //fill InputValue with initial databits
  Temp = Compressor_readBit( inputdata, &InputIndex, inputsize, &Octet, &OctetBitCounter );
  InputValue <<= 1; InputValue |= Temp;  /*InputValue &= COMPRESSION_ARITHMETIC_CALC_MASK;*/  if(COMPRESSION_SHOW)printf("  InputValue:$%.4X\n",InputValue);
 }
 Low = COMPRESSION_ARITHMETIC_CALC_MIN; High = COMPRESSION_ARITHMETIC_CALC_MAX;
 while (OutputSize < COMPRESSION_BUFFERSIZE_MAX) {
  Range = ( (High - Low) /*+ 1*/ ) >> COMPRESSION_ARITHMETIC_RANGE_CALCSHIFTS;
  ScaledInputValue = ( ( ( InputValue - Low /*+ 1*/ )  ) / Range /*- 1*/ ) << COMPRESSION_ARITHMETIC_RANGE_CALCSHIFTS;
  for (i = OutputValue = 0; i < COMPRESSION_ARITHMETIC_VALUEBANDTABLE_SIZE; ++i) {  //find current byte-value based on probability-based valueband/range/segment
   if ( ValueBands[i] != COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE
        && (ValueBands[i] << COMPRESSION_ARITHMETIC_RANGE_CALCSHIFTS) <= ScaledInputValue
        && ScaledInputValue < ( ValueBands[HighIndexes[i]] << COMPRESSION_ARITHMETIC_RANGE_CALCSHIFTS ) )
   { OutputValue = i; break; }
  }
  if (OutputValue >= COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA) break;  //based on built-in end-of-data 'OutputValue' lookup entry $100
  outputdata[ OutputSize++ ] = OutputValue;  if(COMPRESSION_SHOW){Temp=Low;Temp2=High;}
  High = Low + ( ValueBands[ HighIndexes[ OutputValue ] ] * Range ) - 1;  //High &= COMPRESSION_ARITHMETIC_CALC_MASK;
  Low  = Low + ( ValueBands[ OutputValue ] * Range );  /*Low &= COMPRESSION_ARITHMETIC_CALC_MASK;*/  if(COMPRESSION_SHOW){printf("%6.6d ",OutputSize);for(j=0;j<64;++j) printf("%c",j==(int)(ScaledInputValue>>CHARTSHIFTS)?'@':(j==(int)(InputValue>>CHARTSHIFTS)?'?':(((int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS))||((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS))?((int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS)?'#':'+'):(!(j&GRIDMASK)?'|':'.')))); printf(" %.4X:$%2.2X %.4X..%4.4X %.4X..%.4X..%.4X..%.4X\n",ScaledInputValue>>DISPSHIFTS,OutputValue,ValueBands[OutputValue],ValueBands[HighIndexes[OutputValue]]-1,Temp>>DISPSHIFTS,Low>>DISPSHIFTS,High>>DISPSHIFTS,Temp2>>DISPSHIFTS);}
  while (1) {
   if (High < COMPRESSION_ARITHMETIC_CALC_MID || COMPRESSION_ARITHMETIC_CALC_MID <= Low) {  if(COMPRESSION_SHOW){Temp=Low;Temp2=High;}
    Low <<= 1;  Low &= COMPRESSION_ARITHMETIC_CALC_MASK;
    High = (High << 1) | 1;  High &= COMPRESSION_ARITHMETIC_CALC_MASK;  if(COMPRESSION_SHOW){printf("%6.6d ",OutputSize);for(j=0;j<64;++j) printf("%c",((int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS))||((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS))?((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS)&&(int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS)?'=':((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS)?'-':'+')):(!(j&GRIDMASK)?'|':'.')); printf("   %.4X..%.4X In: ",Low>>DISPSHIFTS,High>>DISPSHIFTS);}
    Temp = Compressor_readBit( inputdata, &InputIndex, inputsize, &Octet, &OctetBitCounter );
    InputValue <<= 1; InputValue |= Temp;  InputValue &= COMPRESSION_ARITHMETIC_CALC_MASK;  if(COMPRESSION_SHOW)printf("-> %.4X\n",InputValue);  //shifting 1s will result in End-of-Data at 'OutputValue' lookup (by entry $100 being $FFFF)
   }
   else if (COMPRESSION_ARITHMETIC_CALC_1PER4 <= Low && High < COMPRESSION_ARITHMETIC_CALC_3PER4) {  if(COMPRESSION_SHOW){Temp=Low;Temp2=High;}  //subtract valuerange-middle ('0.25') from all pseudo-infinite variables? (all are above it, so not going negative)
    Low = (Low << 1) & COMPRESSION_ARITHMETIC_CALC_NOMSB_MASK;  Low &= COMPRESSION_ARITHMETIC_CALC_MASK;
    High = (High << 1) | COMPRESSION_ARITHMETIC_CALC_BITVALUE_MSB | 1;  High &= COMPRESSION_ARITHMETIC_CALC_MASK;  if(COMPRESSION_SHOW){printf("%6.6d ",OutputSize);for(j=0;j<64;++j) printf("%c",((int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS))||((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS))?((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS)&&(int)(Low>>CHARTSHIFTS)<=j&&j<=(int)(High>>CHARTSHIFTS)?'=':((int)(Temp>>CHARTSHIFTS)<=j&&j<=(int)(Temp2>>CHARTSHIFTS)?'-':'+')):(!(j&GRIDMASK)?'|':'.')); printf("   %.4X..%.4X In: ",Low>>DISPSHIFTS,High>>DISPSHIFTS);}  //High -= COMPRESSION_ARITHMETIC_PROBABILITY_PEND_LOW;
    Temp = Compressor_readBit( inputdata, &InputIndex, inputsize, &Octet, &OctetBitCounter );  InputValue -= COMPRESSION_ARITHMETIC_CALC_1PER4;
    InputValue <<= 1; InputValue |= Temp;  InputValue &= COMPRESSION_ARITHMETIC_CALC_MASK;  if(COMPRESSION_SHOW)printf("-> %.4X\n",InputValue);  //shifting 1s will result in End-of-Data at 'OutputValue' lookup (by entry $100 being $FFFF)*/
   }
   else break;
  }
 }

 return OutputSize;
}



int Compression_decompressorCopyData (unsigned char* inputdata, int inputsize, unsigned char* outputdata) {
 int i, OutputSize = inputsize;
 for (i=0; i < inputsize; ++i) outputdata[i] = inputdata[i];
 return OutputSize;
}



static int Compression_decompressDataInMode (unsigned char* data, int inputsize, unsigned char* data2) {
 static enum { BASIC_START_ADDRESS = 0x0801, C64_ADDRESS_MAX = 0xFFFF } SelfExtraction_specs;
 int i, Temp, OutputSize = 0; unsigned char Type = 0x00;
 int InplaceExtractionOffset = 0;  //compressed data of self-compressing file will be moved to this offset at the start of extraction
 int C64outputDataBaseAddress = BASIC_START_ADDRESS;

 if ( Compression_decompressModeSFX() || Compression_decompressModeRLESFX() ) {
  if ( Compression_decompressModeRLESFX() ) {
   Temp = data[ COMPRESSION_RLESFX_HEADER_INDEX__INTERM_END_L ] | ( data[ COMPRESSION_RLESFX_HEADER_INDEX__INTERM_END_H ] << COMPRESSION_HIGHBYTE_SHIFTS );
   inputsize = Temp - Compression_readWord( data, COMPRESSION_SFX_HEADER_INDEX__INTERM_1ST );
  }
  else /*if ( Compression_decompressModeSFX() )*/ inputsize -= COMPRESSION_SFX_HEADER_SIZE;
  InplaceExtractionOffset = Compression_readWord( data, COMPRESSION_SFX_HEADER_INDEX__INPLACE_OFFSET );  if (COMPRESSION_VERBOSE) printf("In-place extraction Offset: %d ($%.4X)\n", InplaceExtractionOffset, InplaceExtractionOffset );
  C64outputDataBaseAddress = Compression_readWord( data, COMPRESSION_SFX_HEADER_INDEX__OUTPUT_1ST );  if (COMPRESSION_VERBOSE) printf("C64 decompressed PRG address: $%.4X\n",C64outputDataBaseAddress);
 }
 else {
  inputsize -= COMPRESSION_HEADER_SIZE; Type = data[ COMPRESSION_HEADER_INDEX__TYPE ];
 }


 if ( (Type & COMPRESSION_HEADER_BITVALUE__TYPE__USED_ARITHMETIC_CODING)
      && !( Compression_decompressModeSFX() || Compression_decompressModeRLESFX() ) ) {
  OutputSize = Compression_decompressArithmetic( &data[ COMPRESSION_HEADER_SIZE ], inputsize, data2 );
 }
 else OutputSize = Compression_decompressorCopyData( &data[
   Compression_decompressModeSFX() ? COMPRESSION_SFX_HEADER_SIZE
    : ( Compression_decompressModeRLESFX() ? COMPRESSION_RLESFX_HEADER_SIZE : COMPRESSION_HEADER_SIZE )
  ], inputsize, data2 );


 if ( ( (Type & COMPRESSION_HEADER_BITVALUE__TYPE__USED_PATTERNMATCHING) || Compression_decompressModeSFX() )
      && !Compression_decompressModeRLESFX() ) {
  if ( Compression_decompressModeSFX() ) {  //in-place decompression in 'data2' (overlapping input and output buffers)
   for (i = OutputSize - 1; i >= 0; --i) data2[ InplaceExtractionOffset + i ] = data2[ i ];  //move sourcedata to end
   OutputSize = Compression_decompressPatternMatches( data2 + InplaceExtractionOffset, OutputSize, data2 );
   data[0] = C64outputDataBaseAddress & COMPRESSION_LOWBYTE_MASK; data[1] = C64outputDataBaseAddress >> COMPRESSION_HIGHBYTE_SHIFTS;
   OutputSize = Compression_decompressorCopyData( data2, OutputSize + COMPRESSION_PRG_HEADER_SIZE, data + COMPRESSION_PRG_HEADER_SIZE );  //2byte PRG-header wasn't compressed into SFX (but is restored)
  }
  else OutputSize = Compression_decompressPatternMatches( data2, OutputSize, data );
 }
 else Compression_decompressorCopyData( data2, OutputSize, data );


 if ( ( (Type & COMPRESSION_HEADER_BITVALUE__TYPE__USED_RLE) && !Compression_decompressModeSFX() )
      || Compression_decompressModeRLESFX() ) {
  if ( Compression_decompressModeRLESFX() ) {  //in-place decompression in 'data' (overlapping input and output buffers)
   for (i = OutputSize - 1; i >= 0; --i) data[ InplaceExtractionOffset + i ] = data[ i ];  //move sourcedata to end
   OutputSize = Compression_decompressValueRepeats( data + InplaceExtractionOffset, OutputSize, data );
   data2[0] = C64outputDataBaseAddress & COMPRESSION_LOWBYTE_MASK; data2[1] = C64outputDataBaseAddress >> COMPRESSION_HIGHBYTE_SHIFTS;
   OutputSize = Compression_decompressorCopyData( data, OutputSize + COMPRESSION_PRG_HEADER_SIZE, data2 + COMPRESSION_PRG_HEADER_SIZE );  //2byte PRG-header wasn't compressed into SFX (but is restored)
  }
  else OutputSize = Compression_decompressValueRepeats( data, OutputSize, data2 );
 }
 else Compression_decompressorCopyData( data, OutputSize, data2 );


 return OutputSize;
}



int Compression_decompressData (unsigned char* data, int inputsize, unsigned char* data2) {
 Compression_setDecompressMode( COMPRESSION_MODE__NORMAL );
 return Compression_decompressDataInMode( data, inputsize, data2 );
}

int Compression_decompressReadOnlyData (unsigned char* source, int inputsize, unsigned char** target) {
 unsigned char *DecompressionBuffer1 = NULL, *DecompressionBuffer2 = NULL; int OutputSize;
 DecompressionBuffer1 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer1 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 DecompressionBuffer2 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer2 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 Compression_decompressorCopyData( source, inputsize, DecompressionBuffer1 );
 OutputSize = Compression_decompressData( DecompressionBuffer1, inputsize, DecompressionBuffer2 );
 if (*target == COMPRESSION_AUTOALLOCATE_DECOMPRESS_TARGET/*NULL*/) {
  *target = (unsigned char*) malloc( OutputSize * sizeof(unsigned char) );
  if (*target == NULL) { free( DecompressionBuffer1 ); free( DecompressionBuffer2 ); return COMPRESSION_RETURNVALUE__ABORT; }
 }
 Compression_decompressorCopyData( DecompressionBuffer2, OutputSize, *target );
 free( DecompressionBuffer1 ); free( DecompressionBuffer2 );
 return OutputSize;
}


int Compression_decompressDataInPlace (unsigned char* data, int inputsize, unsigned char* data2) {
 Compression_setDecompressMode( COMPRESSION_MODE__IN_PLACE );
 return Compression_decompressDataInMode( data, inputsize, data2 );
}


int Compression_decompressSFXdata (unsigned char* data, int inputsize, unsigned char* data2) {
 Compression_setDecompressMode( COMPRESSION_MODE__SELF_EXTRACT );
 return Compression_decompressDataInMode( data, inputsize, data2 );
}

int Compression_decompressRLESFXdata (unsigned char* data, int inputsize, unsigned char* data2) {
 Compression_setDecompressMode( COMPRESSION_MODE__RLE_SELF_EXTRACT );
 return Compression_decompressDataInMode( data, inputsize, data2 );
}


int Compression_decompressReadOnlySFXdata (unsigned char* source, int inputsize, unsigned char** target) {
 unsigned char *DecompressionBuffer1 = NULL, *DecompressionBuffer2 = NULL; int OutputSize;
 DecompressionBuffer1 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer1 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 DecompressionBuffer2 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer2 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 Compression_decompressorCopyData( source, inputsize, DecompressionBuffer1 );
 OutputSize = Compression_decompressSFXdata( DecompressionBuffer1, inputsize, DecompressionBuffer2 );
 if (*target == COMPRESSION_AUTOALLOCATE_DECOMPRESS_TARGET/*NULL*/) *target = malloc( OutputSize * sizeof(unsigned char) );
 if (*target == COMPRESSION_AUTOALLOCATE_DECOMPRESS_TARGET/*NULL*/) {
  *target = (unsigned char*) malloc( OutputSize * sizeof(unsigned char) );
  if (*target == NULL) { free( DecompressionBuffer1 ); free( DecompressionBuffer2 ); return COMPRESSION_RETURNVALUE__ABORT; }
 }
 Compression_decompressorCopyData( DecompressionBuffer2, OutputSize, *target );
 free( DecompressionBuffer1 ); free( DecompressionBuffer2 );
 return OutputSize;
}

int Compression_decompressReadOnlyRLESFXdata (unsigned char* source, int inputsize, unsigned char** target) {
 unsigned char *DecompressionBuffer1 = NULL, *DecompressionBuffer2 = NULL; int OutputSize;
 DecompressionBuffer1 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer1 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 DecompressionBuffer2 = malloc( COMPRESSION_BUFFERSIZE_MAX ); if (DecompressionBuffer2 == NULL) return COMPRESSION_RETURNVALUE__ABORT;
 Compression_decompressorCopyData( source, inputsize, DecompressionBuffer1 );
 OutputSize = Compression_decompressRLESFXdata( DecompressionBuffer1, inputsize, DecompressionBuffer2 );
 if (*target == COMPRESSION_AUTOALLOCATE_DECOMPRESS_TARGET/*NULL*/) {
  *target = (unsigned char*) malloc( OutputSize * sizeof(unsigned char) );
  if (*target == NULL) { free( DecompressionBuffer1 ); free( DecompressionBuffer2 ); return COMPRESSION_RETURNVALUE__ABORT; }
 }
 Compression_decompressorCopyData( DecompressionBuffer2, OutputSize, *target );
 free( DecompressionBuffer1 ); free( DecompressionBuffer2 );
 return OutputSize;
}


