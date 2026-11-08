#ifndef INCLUDED__COMPRESSION_HEADER
#define INCLUDED__COMPRESSION_HEADER


#define COMPRESSION_PROGRESS 1  //show compression progress (percentage)
#define COMPRESSION_VERIFY   1  //check right in the compressor app if decompressed data matches (if debug enabled, compressor routine stores inputbyte-addresses for input/output-comparison debugging)
#define COMPRESSION_DEBUG    1  //set to 1 for printf() messages about some internal operations/problems (without this nothing is printed, trying to solve problems quietly)
#define COMPRESSION_VERBOSE  0  //print some extra info like reductions in all compression steps (size-difference/offset statistics)
#define COMPRESSION_SHOW     0  //set to 1 for nice printf() tables showing byte-by-byte/bit-by-bit internal behaviour (of arithmetic coding)
 #define COMPRESSION_SHOW_STARTINDEX  -1  //0x1000  //uncompressed data-index where showing should start, -1 means no filtering (showing all)
 #define COMPRESSION_SHOW_RANGE       0x0100        //show in this range starting at startindex
//#define COMPRESSION_PRINTF  (COMPRESSION_PROGRESS || COMPRESSION_VERBOSE || COMPRESSION_SHOW || COMPRESSION_DEBUG)
#define COMPRESSION_DEBUG_VERIFICATION  (COMPRESSION_VERIFY && COMPRESSION_DEBUG)

#include <stdlib.h>
//#if (COMPRESSION_PRINTF)
 #include <stdio.h>
//#endif


#ifndef COMPRESSION_SFX_HEADER_SIZE  //keep some future-compatibility with some gap for additional code, but positions and size of SFX/self-extract header should be calculated in compressor.c
 #define COMPRESSION_SFX_HEADER_SIZE 0x100 //- COMPRESSION_PRG_HEADER_SIZE //(_binary_selfextract_prg_end - _binary_selfextract_prg_start)
#endif
#ifndef COMPRESSION_RLESFX_HEADER_SIZE  //keep some future-compatibility with some gap for additional code, but positions and size of RLESFX/self-extract header should be calculated in compressor.c
 #define COMPRESSION_RLESFX_HEADER_SIZE 0x100 //- COMPRESSION_PRG_HEADER_SIZE //(_binary_selfextract_prg_end - _binary_selfextract_prg_start)
#endif

#define COMPRESSION_AUTOALLOCATE_DECOMPRESS_TARGET  NULL  //if the target pointer is set to NULL, it will be auto-allocated by decompressor


static enum {  //Common header for Hermit's compressor and decompressor (the actual specification of the format)
 COMPRESSION_MODE__GET = 0,  //solved get-set of compression/decompression-mode (SFX/etc.) by this special enum-value
 COMPRESSION_MODE__NORMAL,  //using 2 non-overlapping buffers
 COMPRESSION_MODE__IN_PLACE,  //could be usable by C decompressor
 COMPRESSION_MODE__SELF_EXTRACT,  //using a single buffer (in-place)
 COMPRESSION_MODE__RLE_SELF_EXTRACT,  //using a single buffer (in-place)  //requested by Oswald at CSDb

 COMPRESSION_VALUE_BITCOUNT = 32,
  COMPRESSION_VALUE_MAX = (signed int) 0xFFFFFFFF, //( (1 << COMPRESSION_VALUE_BITCOUNT) - 1 ) /*0xFFFFFFFF*/,
  COMPRESSION_SIGNED_VALUE_MAX = 0x7FFFFFFF, //( (1 << (COMPRESSION_VALUE_BITCOUNT - 1) ) - 1 ) /*0x7FFFFFFF*/,
 COMPRESSION_BUFFERSIZE_BITCOUNT = 20,
  COMPRESSION_BUFFERSIZE_MAX = (1 << COMPRESSION_BUFFERSIZE_BITCOUNT) /*1048576 bytes*/,  //to be on the safe side (against segfaults and endless loops)

 //fine-tuning the multi-method compression by enabling/disabling different methods:
 COMPRESSION_ENABLED_RLE = 1,  //whether to use (the advised and adaptive) RLE-compression before compressing wih pattern-matching (also helps arithmetic-coding to avoid too big probability of a long-running value)
  COMPRESSION_ADAPTIVE_RLE = 1,  //whether enabled RLE is unused when it actually increases the compressed output file-size compared to the input-filesize
 COMPRESSION_ENABLED_PATTERNMATCHING = 1,  //whether to use (the highly advised and most efficient adaptive) dictionary/patternmatch-compression before compressing wih arithmetic-coding
  COMPRESSION_ADAPTIVE_PATTERNMATCHING = 1,  //whether enabled pattern-matching compression is unused when it actually increases the compressed output file-size compared to the input-filesize
 COMPRESSION_ENABLED_ARITHMETIC_CODING = 1,  //whether to enable (the advised but adaptive) arithmetic-coding compression after compressing wih pattern-matching
  COMPRESSION_ADAPTIVE_ARITHMETIC_CODING = 1,  //whether enabled arithmetic-coding is unused in compression when it's probability-model header actually increases the compressed output file-size compared to the input-filesize

 COMPRESSION_BITS_PER_BYTE = 8, COMPRESSION_VALUERANGE__BYTE = /*256*/ (1 << COMPRESSION_BITS_PER_BYTE),
  COMPRESSION_VALUEMASK__BYTE = /*0xFF*/ (COMPRESSION_VALUERANGE__BYTE - 1),
   COMPRESSION_VALUEMAX__BYTE = /*0xFF*/ COMPRESSION_VALUEMASK__BYTE,
  COMPRESSION_HIGHBYTE_SHIFTS = COMPRESSION_BITS_PER_BYTE, COMPRESSION_LOWBYTE_MASK = COMPRESSION_VALUEMASK__BYTE,
 COMPRESSION_RETURNVALUE__ABORT = -1,  //this tells that the given compression method should be terminated and cancelled for some reason

 COMPRESSION_PRG_HEADER_SIZE = 2,  //values should match the offset of the assembled selfextract.asm/.prg's operands:
 COMPRESSION_MEM_HEADER_SIZE = 2,  //'MEM' format's header is little-endian 16bit decompression target-address
 COMPRESSION_C64_ADDRESS_RANGE = 0x10000, COMPRESSION_C64_ADDRESS_MAX = /*0xFFFF*/ (COMPRESSION_C64_ADDRESS_RANGE - 1),

 COMPRESSION_HEADER_SIZE = 1,  //1 byte header tells about the format
  COMPRESSION_HEADER_INDEX__TYPE = 0,  //type/variant/format-specifier byte of header (currently the only one)
   COMPRESSION_HEADER_BITVALUE__TYPE__USED_RLE = (1 << 7) /*bit8,value$80*/,
   COMPRESSION_HEADER_BITVALUE__TYPE__USED_PATTERNMATCHING = (1 << 6) /*bit6,value$40*/,
   COMPRESSION_HEADER_BITVALUE__TYPE__USED_ARITHMETIC_CODING = (1 << 5) /*bit5,value$20*/,  //if adaptive output was very small, didn't use arithmetic compression (with header of max. 256/512byte valuebands-table)
    //COMPRESSION_HEADER_BITVALUE__TYPE__ARITHMETIC_CODING_3BYTE_VALUEBANDS = (1 << 4) /*bit4,value$10*/,  //might be needed later for bigger resolution?
 COMPRESSION_INPLACE_DECOMPRESSION_EXTRA_SAFETY_GAP = 0, // /*1*/COMPRESSION_PATTERNMATCH_PREFIX_SIZE__END_OF_DATA, //to be on the safe side, always have at least a minimal slack/gap between compressed and decompressed data for in-place decompression (e.g. for 1byte end-of-data signal or prefix), but better having this fully automatic in compressor.c
 COMPRESSION_INPLACE_HEADER_SIZE = 2,
   COMPRESSION_INPLACE_HEADER_INDEX__OFFSET = 0x00,
    COMPRESSION_INPLACE_HEADER_INDEX__OFFSET_LOW = COMPRESSION_INPLACE_HEADER_INDEX__OFFSET,
    COMPRESSION_INPLACE_HEADER_INDEX__OFFSET_HIGH = (COMPRESSION_INPLACE_HEADER_INDEX__OFFSET + 1),
 //COMPRESSION_SFX_HEADER_SIZE = 0x100, //- COMPRESSION_PRG_HEADER_SIZE, //(_binary_selfextract_prg_end - _binary_selfextract_prg_start),  //positions and size of SFX/self-extract header should be calculated in compressor.c
  COMPRESSION_SFX_HEADER_INDEX__INPLACE_OFFSET  = 0x04,  //given in BASIC program-line number to save space
  COMPRESSION_SFX_HEADER_INDEX__MOVE_HIGHCOUNT  = 0x1F,
  COMPRESSION_SFX_HEADER_INDEX__MOVE_INDEXINIT  = 0x21,
  COMPRESSION_SFX_HEADER_INDEX__MOVESOURCE_END  = 0x24,
  COMPRESSION_SFX_HEADER_INDEX__MOVETARGET_END  = 0x27,
  COMPRESSION_SFX_HEADER_INDEX__INTERM_1ST      = 0x38,  //address/pointer of moved (intermediate) compressed data's 1st byte
  COMPRESSION_SFX_HEADER_INDEX__OUTPUT_1ST      = 0x3A,  //address-highbyte of to-be-decompressed output data's 1st byte
   COMPRESSION_RLESFX_HEADER_INDEX__INTERM_END_L = 0x3D,  //address/pointer-lowbyte of moved (intermediate) compressed data's end (place after last byte)
   COMPRESSION_RLESFX_HEADER_INDEX__INTERM_END_H = 0x3F,  //address/pointer-highbyte of moved (intermediate) compressed data's end (place after last byte)
  COMPRESSION_SFX_HEADER_INDEX__PROGRESS_VRAM_WRITE = 0xF4,//? //(COMPRESSION_SFX_HEADER_INDEX__RUN_ADDRESS - 10) ?  //progress-indication address to disable if VRAM is used as decompression-target
   COMPRESSION_SFX__PROGRESS_VRAM_ADDRESS = (0x0400 + 40*25 - 1),  //last character of screen is used for countdown progress-indicator
   COMPRESSION_SFX__PROGRESS_COUNT_SIZE_THRESHOLD = 0x4000,  //below this uncompressed size progress-countdown is not displayed as it is so fast there's no need
  COMPRESSION_SFX_HEADER_INDEX__RUN_ADDRESS     = 0xFE,//?  //decompressed app's start address (might be BASIC SYS address or direct address
   COMPRESSION_SFX_NOMOVE_HEADER_INDEX__RUN_ADDRESS = COMPRESSION_SFX_HEADER_INDEX__RUN_ADDRESS,  //for variant with no input-data moving before decrunching
   COMPRESSION_SFX_FALLBACK_JUMPADDRESS = 0x080D,

 COMPRESSION_SFX_VARIABLE_LENGTH_NUMBER_SIZE_UNSUPPORTED = 0x3F,

 COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_NEXTBYTE_SIGNBIT_COUNT = 1,
 COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEBIT_COUNT = 7,  //1 bit per byte is used for storing variable-length numbers
  COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_DIVSHIFTS = COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEBIT_COUNT /*7*/,
  COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_MULSHIFTS = COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEBIT_COUNT /*7*/,
  COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUERANGE = /*0x80*/ (1 << COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEBIT_COUNT),
   COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEMASK = /*0x7F*/ (COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUERANGE - 1),
    COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEMAX = /*0x7F*/ COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUEMASK,
 COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUESHIFTS = 0, //1,  //REVERTED: from v1.1 LSB is used as 'nextbyte' flag (for shorter C64 SFX-code)
  COMPRESSION_VARIABLE_LENGTH_NUMBER_NEXTBYTE_SIGN_BITVALUE = 0x80, //REVERTED  /*0x01*/ ( 1 << (COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_VALUESHIFTS - 1) ), //0x80,  //little-endian variable-length numbers

 //RLE compression config and details  //Important note: repeat-count here is not meant to be the total count of the same value, but minus 1: literally the count of the occurrence of the same value AFTER the first occurrence (not including the first)
 COMPRESSION_RLE_REPEATCOUNT_COMPRESSION_THRESHOLD = 2, //3  //smallest repeat-count has the 1-byte overhead of repeat-count but still need to be escaped by the value repeated x times
 //COMPRESSION_SFX_RLE_REPEATCOUNT_SIZE_MAX = 1, //2 /*bytes*/,  //RLE-SFX self-extraction code has space for handling only 1byte (0...255) repeat-count
  COMPRESSION_SFX_RLE_SEQUENCE_LENGTH_MAX = /*0x101*/(COMPRESSION_VALUEMAX__BYTE + COMPRESSION_RLE_REPEATCOUNT_COMPRESSION_THRESHOLD), //0x7F, //0x7FFF, //( (1 << (COMPRESSION_SFX_RLE_REPEATCOUNT_SIZE_MAX * BITS_PER_BYTE - COMPRESSION_VARIABLE_LENGTH_NUMBER_BYTE_NEXTBYTE_SIGNBIT_COUNT) ) - 1 ),

 //Pattern-matching and literal-sequence config and details:
 COMPRESSION_PATTERNMATCH_PREFIX_SIZE_MIN = 1, //2, //Thrive in code for fitting distance+length prefix into a single byte if distance and length is below 8, or below 16 when combined/summed
 COMPRESSION_PATTERNMATCH_SFX_LITERAL_PREFIX_SIZE_MAX = 2,  //the literal-sequence prefix is restricted by SFX format to max. 2 bytes
 COMPRESSION_PATTERNMATCH_RLE_PREFIX_SIZE_MIN = 2,  //not including the byte-value repeated by RLE
 COMPRESSION_PATTERNMATCH_PREFIX_SIZE_MAX = 8,  //prefix-size wouldn't ever go above this (unlike something is absolutely wrong)
  COMPRESSION_PATTERNMATCH_SFX_SEQUENCE_LENGTH_MAX = /*$F7*/ (COMPRESSION_VALUEMAX__BYTE - COMPRESSION_PATTERNMATCH_PREFIX_SIZE_MAX),  //decreases decrunch-code size by not needing to read/check seq/match-length high-byte (decompression ratio doesn't suffer much as long sequenes are rare)
  //COMPRESSION_PATTERNMATCH_SFX_VARIABLE_LENGTH_NUMBER_SIZE_MAX = 2, //minimum 2  //C64 extractor code might get bigger because of the need to handle rare big distance/length numbers, so this sets a limit in compression
  //COMPRESSION_PATTERNMATCH_SFX_PREFIX_SIZE_MAX = 3, //C64 extractor code might get bigger because of the need to handle rare big distance/length numbers, so this sets a limit in compression
  COMPRESSION_PATTERNMATCH_INVALID_PREFIX_SIZE_VALUE = 0x3F, //compression will surely avoid considering prefix of this size (used for invalid/unimplemented cases of prefix-writer function)
   COMPRESSION_PATTERNMATCH_PREFIX_SIZE_UNSUPPORTED = COMPRESSION_PATTERNMATCH_INVALID_PREFIX_SIZE_VALUE, //0x3E,  //used as signal that given prefix-format is not supported (by SFX self-extract code or others)
    //COMPRESSION_PATTERNMATCH_VARIABLE_LENGTH_NUMBER_SIZE_UNSUPPORTED = COMPRESSION_PATTERNMATCH_PREFIX_SIZE_UNSUPPORTED,  //COMPRESSION_SFX_VARIABLE_LENGTH_NUMBER_SIZE_UNSUPPORTED
  //COMPRESSION_PATTERNMATCH_SIZEDATA_LENGTH_MIN = 1, COMPRESSION_PATTERNMATCH_SIZEDATA_LENGTH_EXPECTED_MAX = 1,
  //COMPRESSION_PATTERNMATCH_DISTANCEDATA_LENGTH_MIN = 1, COMPRESSION_PATTERNMATCH_DISTANCEDATA_LENGTH_EXPECTED_MAX = 2,
 COMPRESSION_PATTERNMATCH_IGNORE_SAMESIZE_PREFIX = 1, //0 or 1, if 0, short pattern is substituted with same-size prefix (unnecessary work, statistics show considerably worse compression ratio)
  COMPRESSION_PATTERNMATCH_LENGTH_COMPRESSION_THRESHOLD = /*2*/ (COMPRESSION_PATTERNMATCH_PREFIX_SIZE_MIN + COMPRESSION_PATTERNMATCH_IGNORE_SAMESIZE_PREFIX), //we're adaptive now //(COMPRESSION_PATTERNMATCH_DISTANCEDATA_LENGTH_MIN/*EXPECTED_MAX*/ + COMPRESSION_PATTERNMATCH_SIZEDATA_LENGTH_EXPECTED_MAX) /*2*/, //it's not worth matching/compressing below this amount of bytes due to distance+size data overhead, yielding same or bigger total size of datachunk
 COMPRESSION_PATTERNMATCH_LITERAL_PREFIX_OVERHEAD_COMPENSATION = 0, //1, //extra bytes added to minimum literal-sequence length to compensate for overhead of added prefix (seems to decrease compression ratio as kills many pattern-matching opportunities)
  COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_MINIMUM_SIZE = /*1*/ (COMPRESSION_PATTERNMATCH_PREFIX_SIZE_MIN + COMPRESSION_PATTERNMATCH_LITERAL_PREFIX_OVERHEAD_COMPENSATION), //minimum literal-sequence size that is worth prefixing (with not too much prefix-overhead)
 COMPRESSION_PATTERNMATCH_OFFSET_VALUE__LITERAL_SEQUENCE = 0x00, //sign for literal sequence is zero offset (distance+length)
 COMPRESSION_PATTERNMATCH_OFFSET_VALUE__RLE_SEQUENCE = 0x7FFFFFFF, //sign for literal sequence is zero offset (distance+length)
  COMPRESSION_PATTERNMATCH_OFFSET_VALUE__MATCH_REPEAT = COMPRESSION_PATTERNMATCH_OFFSET_VALUE__RLE_SEQUENCE,  //must be the same (handled as such in the code)
  COMPRESSION_PATTERNMATCH_LENGTH_RLE_COMPRESSION_THRESHOLD = /*3*/ (COMPRESSION_PATTERNMATCH_RLE_PREFIX_SIZE_MIN + 1), //including byte-value to be repeated by RLE
  COMPRESSION_PATTERNMATCH_RLE_REPEAT_SUPPORTED_PREFIXSIZE = 2, //currently C64 self-extractor only supports this matchprefix-size to be RLE-encoded
 COMPRESSION_PATTERNMATCH_MATCHLENGTH2_OFFSET_VALUE__END_OF_DATA = 0x00, //COMPRESSION_PATTERNMATCH_OFFSET_VALUE__LITERAL_SEQUENCE,
 //prefixing format: a lot depends on the prefix's 1st byte (how much really short sequences are worth compressing), fitting as much info to it as possible
 //$00     : literal sequence, next variable-length number is coming with bigger length-values 16..143..whatever (in SFX-mode: 1byte 0..247)
 //$01..$0F: literal-sequence of length 1..15  (NOTE: SFX-mode has the prefix-type bits in LSBs for smaller 'lsr-bcs' decision-tree)
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_NEXTBYTE = 0x00, //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_MAX /*0xF*/, //changed in v1.1
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_LENGTH_MIN = 0x01,  //changed in v1.1
 COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_LENGTH_MIN = 1,  //allow as small as 1 instead of COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_MINIMUM_SIZE below
  COMPRESSION_PATTERNMATCH_LITERAL_BYTE1_LENGTH_VALUEDIFF = /*0*/ (COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_LENGTH_MIN - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_LENGTH_MIN),
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_MAX = 0x0F,
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_LITERAL_LENGTH_MAX = /*15*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_MAX-1 + COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_LENGTH_MIN),  // 0xE + COMPRESSION_PATTERNMATCH_LITERAL_SEQUENCE_LENGTH_MIN,
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_LITERAL_LENGTH_MIN = /*16*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_LITERAL_LENGTH_MAX + 1), //not added in SFX-mode
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_END = (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_MAX + 1),
 //$10     : following bytes are variable-length number of big matchlength (in SFX-mode: 1byte 0..247), distance is 0 (prefix 1byte less in this special case, when e.g. pattern-match previous sequence is without any gaps, like with long repeats of non-RLE sources)
 //$12..$1F: pattern-matchlength 5..18, followed by variable-length number of distance (endoffset) value
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE = 0x10,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE_DISTANCE0 = /*0x10*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE+0), //(COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE + 0xE) /*0x1E*/,  //changed in v1.1
  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE = /*0x11*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE+1), //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_MAX /*0x1F*/,  //changed in v1.1
   //COMPRESSION_PATTERNMATCH_PREFIX_SFX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE = /*0x01*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE),
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_RANGE = 0x10,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_MIN = /*0x11*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE + 1/*2*/),  //changed in v1.1
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIGGER_MATCHLENGTH_MAX = /*0x1F*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE + 0xF,
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_MIN = 5, //4,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_VALUEDIFF = /*4*/ ( COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_MIN - (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_MIN - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE) ),
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIGGER_MATCHLENGTH_MAX_NONSHIFTED = /*0x0E*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIGGER_MATCHLENGTH_MAX - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_MIN), //(COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE_DISTANCE0-1 - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE) /*$0D*/,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIGGER_MATCHLENGTH_MAX = /*19*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIGGER_MATCHLENGTH_MAX_NONSHIFTED + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIG_MATCHLENGTH_MIN),
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_BIGGEST_MATCHLENGTH_MIN = /*20*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_BIGGER_MATCHLENGTH_MAX + 1),
  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_BIGGEST_MATCHLENGTH_MAX = COMPRESSION_PATTERNMATCH_SFX_SEQUENCE_LENGTH_MAX,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_END = /*0x20*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_RANGE),
 //$20..$3F: pattern-matchlength 4 with distance low-bits (0..31) in byte1, followed by distance high-bits in next byte (appears more often (~8%) than single-byte prefix in 4.3% of cases)
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__BASE = 0x20,  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_END,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4_WITH_NEXTBYTE__BASE = COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__BASE /*0x20*/,
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_BITCOUNT = 5,
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_RANGE = (1 << COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_BITCOUNT) /*32*/,
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_MAX = (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_RANGE - 1) /*31*/,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_MASK = COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_MAX /*$1F*/,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_MATCHLENGTH4_DISTANCE_DIVSHIFTS = COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_BITCOUNT,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__END = (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH4_DISTANCE_RANGE) /*$40*/,
 //$40     : following bytes are variable-length number of big matchlength (in SFX-mode: 1byte 0..247), followed by variable-length distance value
 //$41..$7E: pattern-matchlength 3 with Distance-value 0..61 (a single-byte prefix, expected in 11% of cases)
 //$7F     : RLE-sequence with length (repeat-count) in 2nd byte (& 3rd byte), followed by repeated byte-value in 4th byte
 //          (For SFX it's the repeat-count of the whole patternmatch-prefix following it, in case it would be repeated)
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE = 0x40, //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH4__END,
  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__END_OF_DATA = /*$40*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE = /*0x40*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE+0),  //brougth here in v1.1
   COMPRESSION_PATTERNMATCH_PREFIX_SFX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE = /*0x00*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__BIG_MATCHLENGTH_NEXTBYTE - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE),
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BASE = 1, //value-range is shifted by nextbyte added above (in v1.1)
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BITCOUNT = 6,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE = /*$40*/ (1 << COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BITCOUNT),
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUE_MAX = /*$3F*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE - 1),
    COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUE__RLE = /*$3F*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUE_MAX,
     COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__RLE = /*0x7F*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUE__RLE),
    COMPRESSION_PATTERNMATCH_PREFIX_RLE_LENGTH_MIN = 1, //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__LITERAL_LENGTH_MIN
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_RANGE = /*62*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BASE - (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE-COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUE__RLE) ),
 //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_MIN = 0,
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_MAX = /*61*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_RANGE - 1),
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__END = /*$80*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE),
 //$80     : 'END of data' prefix, mainly for SFX-mode (C64 self-extraction format), but could be used for other purposes too (e.g. for streaming when size/end of data is not known)
 //$81..$BF: pattern-matchlength 2 with distance 0..62 (a single-byte prefix, expected in 10% of cases)
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__BASE = 0x80, //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3__END,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__END_OF_DATA = /*$80*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__BASE,
  COMPRESSION_PATTERNMATCH_PREFIX_SIZE__END_OF_DATA = 1,
   COMPRESSION_SFX_EXTRACTED_DATA_ENDADDRESS_MAX = (COMPRESSION_C64_ADDRESS_RANGE - COMPRESSION_PATTERNMATCH_PREFIX_SIZE__END_OF_DATA /*- COMPRESSION_PATTERNMATCH_SFX_LITERAL_PREFIX_SIZE_MAX*/),  //worst-case scenario: a full 64k program ending with a 2bite-prefix literal, 2+1=3byte extra memory would be needed to in-place decompress with the 1byte endsignal at the end
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_BASE = /*1*/COMPRESSION_PATTERNMATCH_PREFIX_SIZE__END_OF_DATA, //value-range is shifted by added END_OF_DATA value
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_BITCOUNT = 6,
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_VALUERANGE = /*64*/ (1 << COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_BITCOUNT),
   COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_RANGE = /*63*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_VALUERANGE - COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_BASE ),
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_MAX = /*62*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_RANGE - 1),
  //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_DISTANCE_MASK = /*$3F*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_VALUERANGE - 1),
  COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__END = (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__BASE + COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH2_VALUERANGE) /*$C0*/,
 //$C0..$FF: pattern-matchlength 3 with distance lowbits (0..63) followed by Distance-value high-bits in a byte (no more, as it's not worth' compressing
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH3_WITH_NEXTBYTE__BASE = 0xC0, //COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_VALUE__MATCHLENGTH2__END,
 COMPRESSION_PATTERNMATCH_PREFIX_MATCHLENGTH3_BIG_DISTANCE_MIN = /*62*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_RANGE,  //further optimization of this case, a bit less chance of the need for high-byte
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_MASK = /*0x3F*/ (COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_VALUERANGE - 1),
 COMPRESSION_PATTERNMATCH_PREFIX_BYTE2_MATCHLENGTH3_DISTANCE_DIVSHIFTS = /*6*/ COMPRESSION_PATTERNMATCH_PREFIX_BYTE1_MATCHLENGTH3_DISTANCE_BITCOUNT,

 //Arithmetic-coding method config and details:
 COMPRESSION_ARITHMETIC_PROBABILITY_BYTECOUNT = 2, //minimum 2! //resolution of valueband-table stored at the beginning of the file, for 64kbytes of data, 16bit resolution is really necessary because some values can have 65535 times more chance than others occurring only once (though this is a rare case but possible), with less bits normalization or saturation/truncating is performed (yielding worse compression ratios)
  COMPRESSION_ARITHMETIC_PROBABILITY_BITCOUNT = (COMPRESSION_ARITHMETIC_PROBABILITY_BYTECOUNT * 8) /*16*/,  //16bit resolution has max. 512byte table but still produces smaller compressed output for large-enough files
   COMPRESSION_ARITHMETIC_PROBABILITY_RANGE = (1 << COMPRESSION_ARITHMETIC_PROBABILITY_BITCOUNT) /*0x10000*/,
    COMPRESSION_ARITHMETIC_PROBABILITY_MASK = (COMPRESSION_ARITHMETIC_PROBABILITY_RANGE-1) /*0xFFFF*/,
     COMPRESSION_ARITHMETIC_PROBABILITY_MAX = COMPRESSION_ARITHMETIC_PROBABILITY_MASK /*0xFFFF*/,
     COMPRESSION_ARITHMETIC_PROBABILITY_MIN = 0x0000,
 COMPRESSION_ARITHMETIC_VALUEBANDTABLE_SIZE = (COMPRESSION_VALUERANGE__BYTE + 2),  //the value-range of a byte, plus built-in End-of-Data value $100 and its last band high-value $10000
 COMPRESSION_ARITHMETIC_VALUE__END_OF_DATA = COMPRESSION_VALUERANGE__BYTE /*0x100*/,  //arithmetic-coding compressor outputs this for the decoder as end-of-data value, encoded into the bitstream
 COMPRESSION_ARITHMETIC_VALUE__BITREAD_EOF = 1, //-1,  //this is the real end-of-filedata sign generated upon bitread when end of datastream encountered, value '1' might get closer to End-of-Data value(range)
  COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_NONE = COMPRESSION_ARITHMETIC_PROBABILITY_MAX,
  COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_MIN = COMPRESSION_ARITHMETIC_PROBABILITY_MIN /*0x0000*/,
   COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_END = COMPRESSION_ARITHMETIC_VALUE__VALUEBANDTABLE_MIN,  //$0000 is the 'low' of most frequent value, so valueband the second $0000 value can be used to tell end of probability-model valueband-table in the compressed file
   COMPRESSION_ARITHMETIC_VALUEBANDTABLE_END_ENDVALUE_COUNT = 2,  //after this count of endvalue the valueband-table of input-datastream is considered ended
 COMPRESSION_ARITHMETIC_CALC_BITCOUNT = COMPRESSION_VALUE_BITCOUNT,
 COMPRESSION_ARITHMETIC_CALC_MIN = 0, COMPRESSION_ARITHMETIC_CALC_MAX = COMPRESSION_VALUE_MAX /*0xFFFFFFFF*/,
  COMPRESSION_ARITHMETIC_CALC_MASK = COMPRESSION_ARITHMETIC_CALC_MAX,
  COMPRESSION_ARITHMETIC_RANGE_CALCSHIFTS = (COMPRESSION_ARITHMETIC_CALC_BITCOUNT/*32*/ - COMPRESSION_ARITHMETIC_PROBABILITY_BITCOUNT/*16*/) /*16*/,
 COMPRESSION_CHART_WIDTH_SHIFTS = 6 /*64 characterss*/
} Compression_Secifications;


//Some of these would cause enum-overflaw as enum is signed int, so using defines
#define COMPRESSION_ARITHMETIC_CALC_MID  (unsigned int) ( 1 << (COMPRESSION_ARITHMETIC_CALC_BITCOUNT-1) ) /*0x80000000*/
#define  COMPRESSION_ARITHMETIC_CALC_1PER4  (unsigned int) (COMPRESSION_ARITHMETIC_CALC_MID / 2) /*0x40000000*/
#define   COMPRESSION_ARITHMETIC_CALC_3PER4  (unsigned int) (COMPRESSION_ARITHMETIC_CALC_MID + COMPRESSION_ARITHMETIC_CALC_1PER4) /*0xC0000000*/
#define  COMPRESSION_ARITHMETIC_CALC_BITVALUE_MSB  (unsigned int) COMPRESSION_ARITHMETIC_CALC_MID /*0x80000000*/
#define  COMPRESSION_ARITHMETIC_CALC_NOMSB_MASK  (unsigned int) (COMPRESSION_ARITHMETIC_CALC_MID - 1) /*0x7FFFFFFF*/


int Compression_decompressReadOnlyData (unsigned char* source, int inputsize, unsigned char** target);  //easier-to use (allocates & deallocates intermediate buffers automatically, if target is NULL, it's auto-allocated too)
int Compression_decompressReadOnlySFXdata (unsigned char* source, int inputsize, unsigned char** target);  //easier-to use (allocates & deallocates intermediate buffers automatically, if target is NULL, it's auto-allocated too)
int Compression_decompressReadOnlyRLESFXdata (unsigned char* source, int inputsize, unsigned char** target);  //easier-to use (allocates & deallocates intermediate buffers automatically, if target is NULL, it's auto-allocated too)

int Compression_compressReadOnlyData (unsigned char* source, int inputsize, unsigned char* target);  //easier-to use (allocates & deallocates intermediate buffers automatically)
int Compression_compressReadOnlyDataToSFX (unsigned char* source, int inputsize, unsigned char* target);  //easier-to use (allocates & deallocates intermediate buffers automatically)
int Compression_compressReadOnlyDataToRLESFX (unsigned char* source, int inputsize, unsigned char* target);  //easier-to use (allocates & deallocates intermediate buffers automatically)


int Compression_decompressData (unsigned char* data, int inputsize, unsigned char* data2);  //Decompress with all methods: Arithmetic (if it was used to compress) then Dictionary then RLE (if used)
int Compression_decompressSFXdata (unsigned char* data, int inputsize, unsigned char* data2);
int Compression_decompressRLESFXdata (unsigned char* data, int inputsize, unsigned char* data2);

int Compression_compressData (unsigned char* data, int inputsize, unsigned char* data2);  //Compress with all methods: RLE (if used) then Dictionary then Arithmetic (if enabled and reduces size)
int Compression_compressDataToSFX (unsigned char* data, int inputsize, unsigned char* data2);
int Compression_compressDataToRLESFX (unsigned char* data, int inputsize, unsigned char* data2);


int Compression_decompressValueRepeats (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //RLE decompression

int Compression_decompressPatternMatches (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //Dictionary/pattern-matching method

int Compression_decompressArithmetic (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //Arithmetic-coded data decompression

int Compression_decompressorCopyData (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //simple copying from input buffer to output-buffer (e.g. to substitute unused decompresison-method)


int Compression_compressValueRepeats (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //RLE

int Compression_compressPatternMatches (unsigned char* inputdata, register int inputsize, unsigned char* outputdata);  //Dictionary/pattern-matching method

int Compression_compressArithmetic (unsigned char* inputdata, register int inputsize, unsigned char* outputdata);  //Arithmetic-coding

int Compression_compressorCopyData (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //simple copying from input buffer to output-buffer (e.g. to substitute unused compresison-method)

int Compression_compareData (unsigned char* inputdata, int inputsize, unsigned char* outputdata);  //comparison of input and output buffers, stops when difference found and returns difference's location (index), or -1 if no difference


#endif //INCLUDED__COMPRESSION_HEADER