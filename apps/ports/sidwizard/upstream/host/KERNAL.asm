;----------------------------------------------------------------------------------------------
;                 KERNAL ROM substitute for host's emulation of C64 drive/MIDI/etc.

;ROM routine jumptable addresses
KERNAL .block
SETNAM = $ffbd  ;Set file name parameters. Input: A = File name length; X/Y = Pointer to file name. (Real address: $FDF9)
SETLFS = $ffba  ;Set file parameters. Input: A = Logical number; X = Device number; Y = Secondary address. (Real address: $FE00)
OPEN   = $ffc0  ;Open file. (Must call SETLFS and SETNAM beforehands.) Used registers: A, X, Y. (Real address: ($031A), $F34A)
CLOSE  = $ffc3  ;Close file. Input: A = Logical number. Used registers: A, X, Y. (Real address: ($031C), $F291.)
CHKIN  = $ffc6  ;Define file as default input. (Must call OPEN beforehands.) Input: X = Logical number. Used registers: A, X. (Real address: ($031E), $F20E)
CHRIN  = $ffcf  ;Read byte from default input (for keyboard, read a line from the screen). (If not keyboard, must call OPEN and CHKIN beforehands.) Output: A = Byte read. Used registers: A, Y. (Real address: ($0324), $F157.)
CHKOUT = $ffc9  ;Open a channel for output (Registers affected:  A, X), input: A=data, X = logical file number , Real address: ($0320), $F250.
CHROUT = $ffd2  ;(BSOUT) Write byte to default output. (If not screen, must call OPEN and CHKOUT beforehands.) Input: A = Byte to write. (Real address: ($0326), $F1CA)
CLRCHN = $ffcc  ;Close default input/output files (for serial bus, send UNTALK and/or UNLISTEN); restore default input/output to keyboard/screen. Used registers: A, X. (Real address: ($0322), $F333)
SCINIT = $ff81  ;Initialize VIC; restore default input/output to keyboard/screen; clear screen; set PAL/NTSC switch and interrupt timer. Used registers: A, X, Y. (Real address: $FF5B.)
LOAD   = $ffd5  ;LOAD. Load or verify file. (Must call SETLFS and SETNAM beforehands.) Input: A: 0 = Load, 1-255 = Verify; X/Y = Load address (if secondary address = 0).
                ;Output: Carry: 0 = No errors, 1 = Error; A = KERNAL error code (if Carry = 1); X/Y = Address of last byte loaded/verified plus 1 (if Carry = 0). Used registers: A, X, Y. (Real address: $F49E.)  
LOAD2  = $f4a5  ;the entry point that ILOAD refers to
SAVE   = $ffd8  ;SAVE. Save file. (Must call SETLFS and SETNAM beforehands.) Input: A = Address of zero page register holding start address of memory area to save; 
                ;X/Y = End address of memory area plus 1. Output: Carry: 0 = No errors, 1 = Error; A = KERNAL error code (if Carry = 1). (Real address: $F5DD.)
SAVE2  = $f5ed  ;the entry point that ISAVE refers to
READST = $ffb7  ;Fetch status of current device, value of ST variable. (For RS232, status is cleared.),No Input , Output: A = Device status., Used registers: A.,Real address: $FE07.
CHDIR  = $FF40  ;change directory, custom artificial function for SID-Wizard emulator (an RTS plus 2 NOPs in original KERNAL), setlfs and setnam should be called before as with OPEN/LOAD/SAVE
;Indirect ROM addresses (possibly used by cartridge fastloaders)
IOPEN = $031A   ;Indirect entry to Kernal OPEN Routine ($F34A).
ICLOSE= $031C   ;Indirect entry to Kernal CLOSE Routine ($F291).
ICHKIN= $031E   ;Indirect entry to Kernal CHKIN Routine ($F20E).
ICKOUT= $0320   ;Indirect entry to Kernal CHKOUT Routine ($F250).
ICLRCH= $0322   ;Indirect entry to Kernal CLRCHN Routine ($F333).
IBASIN= $0324   ;Indirect entry to Kernal CHRIN Routine ($F157).
IBSOUT= $0326   ;Indirect entry to Kernal CHROUT Routine ($F1CA).
ICLALL= $032C   ;Indirect entry to Kernal CLALL Routine ($F32F).
ILOAD = $0330   ;Indirect entry to Kernal LOAD Routine ($F4A5).
ISAVE = $0332   ;Indirect entry to Kernal SAVE Routine ($F5ED).
;possible resulting error codes after a READST (with their addresses in ROM):
IOerror .block
NO_ERROR              = 0
TOO_MANY_FILES        = 1 ;$F6FB
FILE_OPEN             = 2 ;$F6FE
FILE_NOT_OPEN         = 3 ;$F701
FILE_NOT_FOUND        = 4 ;$F704
DEVICE_NOT_PRESENT    = 5 ;$F707
NOT_INPUT_FILE        = 6 ;$F70A
NOT_OUTPUT_FILE       = 7 ;$F70D
MISSING_FILENAME      = 8 ;$F710
ILLEGAL_DEVICE_NUMBER = 9 ;$F713
.bend
.bend
;ROMIRQ = $ea31  ;default value for $0314,$0315 ROM IRQ vectors
;ROMRTI = $ea86 ;the RTI command at the end of $EA31 IRQ routine, used as 'dummyirq' in case of banksel=$36/$37 (KERNAL-ROM turned on)

;same in KERNAL.asm, host/file.c and HerMIDI-C64.asm

;should be same in host/midi.c
midiZP=$BE
midiZPmidiStatus=midiZP+0
 MIDICMD_INITMIDI=8
 MIDICMD_CLOSEMIDI=9
 MIDISTATUS_GETMIDIDATA=10
 MIDISTATUS_GOTMIDIDATA=11
 MIDISTATUS_NOTFOUND=$F1
MIDIeventRead=midiZP+1 ;midiZPreading=midiZP+1
MIDIeventWritten=$CF
MIDI_EOD = $FD

;Routines used by SID-Wizard and SID-Maker:
diskZP = $F6; //Be careful not to be used by SID-Wizard/SID-Maker!
diskZPnameLo=diskZP+0
 ;MIDIeventRead=diskZPnameLo
diskZPnameHi=diskZP+1
diskZPnameLen=diskZP+2
 ;MIDIeventWritten=diskZPnameLen ;MIDIbufNum=diskZPnameLen
diskZPloadStatus=diskZP+3 ;must be the same in HerMIDI-C64.asm
 DISKSTATUS_OK=0
 DISKCMD_OPEN=1
 DISKCMD_CLOSE=2
 DISKCMD_CHRIN=3
 DISKCMD_CHROUT=4
 DISKCMD_LOAD=5
 DISKCMD_SAVE=6
 DISKCMD_CHDIR=7
 ;DISKCMD_INITMIDI=8
 ;DISKCMD_CLOSEMIDI=9
 ;DISKCMD_GETMIDIDATA=10
 ;DISKCMD_GOTMIDIDATA=11
 DISKSTATUS_NODEVICE=$F0
 DISKSTATUS_NOTFOUND=$F1
 DISKSTATUS_EOF=$F2
 DISKSTATUS_FILEEXISTS=$F3
 DISKSTATUS_NOINPUT=$F4
diskZPstartLo=diskZP+4
diskZPstartHi=diskZP+5
diskZPendLo=diskZP+6
diskZPendHi=diskZP+7
diskZPdata=diskZP+8                  ;clashes with player-ZP
diskZPdrive=diskZP+9 ;device-number  ;clashes with player-ZP
;diskZPargLoad=

*=$E000
            .fill $2000, $60 ;RTS everywhere by default

*=KERNAL.SETNAM ;X:filename-addressLo, Y:filename-addressHi, A:filename-length
            jmp SETNAM
*=KERNAL.SETLFS ;X:device-number (for OPEN: A:logical-number, Y:secondary-address)
            jmp SETLFS
*=KERNAL.OPEN ;(SETLFS before: A:logical-number, X:device-number, Y:secondary-address)
            jmp OPEN
*=KERNAL.CLOSE ;A:logical-number
            jmp CLOSE
*=KERNAL.LOAD ;X:loadaddress-Lo, Y:loadaddress-Hi
            jmp LOAD
*=KERNAL.SAVE ;A:zeropage-address holding load-address, X:endaddress-Lo, Y:endaddress-Hi
            jmp SAVE
*=KERNAL.READST
            jmp READST
*=KERNAL.CHKIN ;X logical number, sets default input from now on (instead of keyboard)
            rts
*=KERNAL.CHRIN ;outputs character that's read from file into A
            jmp CHRIN
*=KERNAL.CHROUT ;sends A to file
            jmp CHROUT
*=KERNAL.CLRCHN
            rts
*=KERNAL.CHDIR ;change dir (artificial func. in SWemu)
            jmp CHDIR


*=$E000 ;do the actual operations where there is more space

;jumptable
InitMIDI    jmp INIT_MIDI    ;$E000
GetMIDIdata jmp GET_MIDIDATA ;$E003
CloseMIDI   jmp CLOSE_MIDI   ;$E006
;MIDIinitialized  .byte 0
;MIDIeventWritten .byte 0
MIDIbuf1    .fill 32+10, MIDI_EOD ;$FD    ;$E009 ;MIDI_EOD ;in HerMIDI-C64.asm too
;MIDIbuf2    .fill 32         ;$E029

SETNAM      stx diskZPnameLo ;X:filename-addressLo, Y:filename-addressHi, A:filename-length
            sty diskZPnameHi
            sta diskZPnameLen
            lda #DISKSTATUS_OK
            sta diskZPloadStatus
            rts


SETLFS      stx diskZPdrive ;X:device-number (for OPEN: A:logical-number, Y:secondary-address)
            rts


OPEN        ;lda diskZPargLoad ;(SETLFS before: A:logical-number, X:device-number, Y:secondary-address)
            ;bne normalOPEN
normalOPEN  lda #DISKCMD_OPEN
            sta diskZPloadStatus
chkOpenRdy  lda diskZPloadStatus
            cmp #DISKCMD_OPEN
            beq chkOpenRdy ;wait for C-program to open file
            jmp chkExitStat


CLOSE       lda #DISKCMD_CLOSE
            sta diskZPloadStatus
chkClosRdy  lda diskZPloadStatus
            cmp #DISKCMD_CLOSE
            beq chkClosRdy ;wait for C-program to close file
            rts


CHRIN       lda #DISKCMD_CHRIN
            sta diskZPloadStatus
chkChInRdy  lda diskZPloadStatus
            cmp #DISKCMD_CHRIN
            beq chkChInRdy ;wait for C-program to read byte
            lda diskZPdata
            rts


CHROUT      sta diskZPdata  ;sends A to file
            lda #DISKCMD_CHROUT
            sta diskZPloadStatus
chkChOutRdy lda diskZPloadStatus
            cmp #DISKCMD_CHROUT
            beq chkChOutRdy ;wait for C-program to read byte
            rts


LOAD        ;sei
            stx diskZPstartLo ;X:loadaddress-Lo, Y:loadaddress-Hi
            sty diskZPstartHi
            lda #DISKCMD_LOAD
            sta diskZPloadStatus
chkLoadRdy  lda diskZPloadStatus
            cmp #DISKCMD_LOAD
            beq chkLoadRdy ;wait for C-program to load data
            ldx diskZPendLo
            ldy diskZPendHi
            jmp chkExitStat


SAVE        stx diskZPendLo ;A:zeropage-address holding load-address, X:endaddress-Lo, Y:endaddress-Hi
            sty diskZPendHi
            sta diskZPstartLo
            lda #0
            sta diskZPstartHi
            ldy #0
            lda (diskZPstartLo),y
            pha
            iny
            lda (diskZPstartLo),y
            sta diskZPstartHi
            pla
            sta diskZPstartLo
            lda #DISKCMD_SAVE
            sta diskZPloadStatus
chkSaveRdy  lda diskZPloadStatus
            cmp #DISKCMD_SAVE
            beq chkSaveRdy ;wait for C-program to load data

chkExitStat cmp #DISKSTATUS_OK
            bne exitError
exitOK      lda #KERNAL.IOerror.NO_ERROR
            clc
            rts
exitError   jsr READST2
            sec
            rts


READST      lda diskZPloadStatus
            cmp #DISKSTATUS_OK
            bne READST2
            lda #KERNAL.IOerror.NO_ERROR
            rts
READST2     cmp #DISKSTATUS_NODEVICE
            bne +
            lda #KERNAL.IOerror.DEVICE_NOT_PRESENT
            rts
+           cmp #DISKSTATUS_NOINPUT
            bne +
            lda #KERNAL.IOerror.NOT_INPUT_FILE
            rts
+           cmp #DISKSTATUS_NOTFOUND
            bcs +
+           lda #KERNAL.IOerror.FILE_NOT_FOUND ;return error in C and errorcode in A
            rts


CHDIR       ;custom routine for the SID-Wizard emulator
            lda #DISKCMD_CHDIR
            sta diskZPloadStatus
chkChdirRdy lda diskZPloadStatus
            cmp #DISKCMD_CHDIR
            beq chkChdirRdy ;wait for C-program to change directory
            ;check DISKSTATUS_OK? (should be handled in SW as 'not found' or 'no disk')
            rts



INIT_MIDI ;Init PC-MIDI and return success (C=0) or fail (C=1)
.if (MIDI==1)
;chkMIDIiRdy lda diskZPloadStatus
;            cmp #DISKCMD_CLOSEMIDI
;            beq chkMIDIiRdy ;wait for C-program to init MIDI
            lda #MIDICMD_INITMIDI ;DISKCMD_INITMIDI
            sta midiZPmidiStatus ;diskZPloadStatus
            ;inc $d020
;chkMIDIiRdy lda diskZPloadStatus
            ;cmp #DISKCMD_INITMIDI
            ;beq chkMIDIiRdy ;wait for C-program to init MIDI
            clc ;prepare OK
            ;lda diskZPloadStatus ;was it successful?
            ;cmp #DISKSTATUS_OK
            ;beq +
            ;sec ;Error
+
.else
            sec ;Error
.fi
            rts


GET_MIDIDATA ;input:X, don't write X
;.if (MIDI==1)
;            cpx #0
;            bne loadBufData
;            lda #DISKCMD_GETMIDIDATA
;            sta diskZPloadStatus
;loadBufData lda MIDIeventWritten
;            bne loadBufData ;wait for complete MIDI-event to arrive before processing
;            lda MIDIbuf1,x
;            ;bit MIDIbufNum
;            ;bpl +
;            ;lda MIDIbuf2,x
;+           cmp #MIDI_EOD ;$FD ;MIDI_EOD
;            beq switchBuf
;            cpx #25 ;MaxBuffSize
;            bcc +
;switchBuf   ldy #DISKCMD_GOTMIDIDATA
;            sty diskZPloadStatus
            ;pha
            ;lda MIDIbufNum
            ;eor #$80
            ;sta MIDIbufNum
            ;pla
;+
;.else
            lda #MIDI_EOD ;$FD
;.fi
            rts


CLOSE_MIDI ;Close PC-MIDI
.if (MIDI==1)
;chkMIDIcRdy lda diskZPloadStatus
;            cmp #DISKCMD_INITMIDI
;            beq chkMIDIcRdy ;wait for C-program to init MIDI
            lda #MIDICMD_CLOSEMIDI ;DISKCMD_CLOSEMIDI
            sta midiZPmidiStatus ;diskZPloadStatus
;chkMIDIcRdy lda diskZPloadStatus
            ;cmp #DISKCMD_CLOSEMIDI
            ;beq chkMIDIcRdy ;wait for C-program to init MIDI
.fi
            rts