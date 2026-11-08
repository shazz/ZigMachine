#define MOUSEKEYPRESS_DURATOIN 20 //18 //11 //*5..ms
#define MOUSEWHEELKEYPRESS_DURATOIN 18 //10 //*5..ms
#define MOUSEKEYPRESS_RELEASE_CNTVALUE 10 //5 //*5..ms

 //      0    1     2    3    4    5   6    7 (DC00/DC01)
 // 0:  del |retu|crri| F7 | F1 | F3 | F5 |crdn | (fe)
 // 1:   3  | W  | A  | 4  | Z  | S  | E  |lSH  | (fd)
 // 2:   5  | R  | D  | 6  | C  | F  | T  | X   | (fb)
 // 3:   7  | Y  | G  | 8  | B  | H  | U  | V   | (f7)
 // 4:   9  | I  | J  | 0  | M  | K  | O  | N   | (ef)
 // 5:   +  | P  | L  | -  | .  | :  | @  | ,   | (df)
 // 6: pound| *  | ;  |HOME|rSH | =  | up | /   | (bf)
 // 7:   1  |back|CTRL| 2  |SPC | C= | Q  |stop | (7f)

static int ShiftedMouseKey[8][8] = { //mouse-made shift-keycombinations
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0}
};

static int CBMmouseKey[8][8] = { //mouse-made C=-keycombinations
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0},
 {0,0,0,0,0,0,0,0}
};


//byte ShiftedKeypressSim=0, CBMkeypressSim=0;
signed char MouseClicked=0, MouseClickX=0, MouseClickY=0, ButtonClickY=0, MouseWheelUp=0, MouseWheelDown=0;
signed char MouseKeyPressDurationCnt=0, MouseShiftedKeypressSim=0, MouseCBMkeypressSim=0, KeySeqCnt=0, FirstPress=0;


void mouseButtonPress() { //printf("%d,%d\n",MouseClickX,MouseClickY); //emulate mouse-click by pressing a key from software
 byte i,j; //printf("%d %d\n",MouseKeyPressDurationCnt,KeySeqCnt);
 /*if (CursorY<1 && CursorX>=30) {
  cRSID_C64.PianoKeyScanCodeRow=0xF; cRSID_C64.PianoKeyScanCodeColumn=0xF;
  CBMkeypressSim=0; for(i=0;i<8;++i) for(j=0;j<8;++j) {ShiftedMouseKey[i][j]=CBMmouseKey[i][j]=0;}
  KeySeqCnt=MouseWheelUp=MouseWheelDown=0;
 }*/
 if (MouseClickX<0) return;
 if (MouseClickY<0) {  //F8 (F7+Shift)
  #ifndef SIDMAKER
  if (MouseClickX >= PIANOROLL_TOGGLE_BUTTON_CHARWIDTH) {
  #endif
   ShiftedMouseKey[0][3] = 1;
  #ifndef SIDMAKER
   PianoRollMode = 0;  //if menu is brought in, piano-roll should disappear
  }
  #endif
 }
 else if(MouseClickX>=30 && MouseClickY<1) {
  if (CursorY>=1 || CursorX<30) ShiftedMouseKey[4][7]=1;
 } // printf("n\n"); } //Shift+N
 else if (MouseClickX>=30 && MouseClickY<25) {
  if(MouseClickX<37 || MouseClickY<5) { //clicked into instrument-window?
   if(FirstPress) { FirstPress=0; if (CursorX>=30 && CursorY<1) KeySeqCnt=2; else KeySeqCnt=1;   if(MouseClickY>=19) KeySeqCnt+=1; }
   if (KeySeqCnt>=2 /*&& ( CursorX<30 || (CursorX>=37 && CursorY>=5) || CursorY>=25 || CursorY<1)*/ ) { //printf("F7\n");
    /*cRSID_C64.*/PianoKeyScanCodeRow=0; /*cRSID_C64.*/PianoKeyScanCodeColumn=3; //F7
   }
   else if (KeySeqCnt==1) {
    if (MouseClickY>=19) {
     if(CursorX>=30 && CursorX<37 && CursorY>=19 && CursorY<25) { KeySeqCnt=-1; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF; }
     else { ShiftedMouseKey[5][1]=1; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF;} //Shift+P
    }
    else { /*cRSID_C64.*/PianoKeyScanCodeRow=0; /*cRSID_C64.*/PianoKeyScanCodeColumn=3; } //F7
   }
   else if (KeySeqCnt==0) {
    if (MouseClickY<5)  { ShiftedMouseKey[1][5]=1; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF; } //printf("Sh+S\n"); } //Shift+S
    else if(MouseClickY>=5 && MouseClickY<14 /*|| (MouseClickY<5 && CursorY>=14)*/) { ShiftedMouseKey[1][1]=1; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF; } //printf("Sh+W\n"); } //Shift+W
    else if (MouseClickY>=14 && MouseClickY<19) { ShiftedMouseKey[5][1]=1; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF; } //printf("Sh+P\n"); } //Shift+P
    else if (MouseClickY>=19) { if(CursorY<19) /*cRSID_C64.*/PianoKeyScanCodeRow=7; /*cRSID_C64.*/PianoKeyScanCodeColumn=2; } //TAB
    else { /*cRSID_C64.*/PianoKeyScanCodeRow=0; /*cRSID_C64.*/PianoKeyScanCodeColumn=3; } //printf("F7\n"); } //F7
   }
  }
  else if (MouseClickX>=37) {
   if(FirstPress && (CursorX>=30 && CursorY<1)) { FirstPress=0; KeySeqCnt=1; }
   if(MouseClickY>=5 && MouseClickY<19) { CBMmouseKey[0][6]=1; MouseCBMkeypressSim=1; } //C=+F5
   else if (MouseClickY>19) { CBMmouseKey[0][3]=1; MouseCBMkeypressSim=1; } //C=+F7
   else /*cRSID_C64.*/PianoKeyScanCodeRow=0; /*cRSID_C64.*/PianoKeyScanCodeColumn=3; //F7
  }
 }
 else {
  if (MouseClickX<30 && MouseClickY<25) {
   if(FirstPress) { FirstPress=0; if(CursorX>=30 || CursorY>=25) KeySeqCnt=3; else KeySeqCnt=1; }    //printf("%d\n",KeySeqCnt);
   if(KeySeqCnt>=2) { if (CursorX>=30 || CursorY>=25) {/*cRSID_C64.*/PianoKeyScanCodeRow=0; /*cRSID_C64.*/PianoKeyScanCodeColumn=6;} } //F5
   else { //pattern TAB-positioning
    if( (MouseClickX<10 && CursorX<10) || (MouseClickX>=10 && MouseClickX<20 && CursorX>=10 && CursorX<20) || (MouseClickX>=20 && CursorX>=20) ) { //column matches
     KeySeqCnt=0; /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF;
    }
    else { //printf("Tabbing\n"); //Tabbing
     /*if ( (MouseClickX>=20 && CursorX>=10 && CursorX<20) || MouseClickX>=10 && MouseClickX<20 && CursorX<10 ) { //step 1 right
      KeySeqCnt=0; cRSID_C64.PianoKeyScanCodeRow=7; cRSID_C64.PianoKeyScanCodeColumn=2;
     }
     else if ( (MouseClickX<10 && CursorX>=10 && CursorX<20) || (MouseClickX>=10 && MouseClickX<20 && CursorX>=20) ) { //step 1 left
      KeySeqCnt=0; ShiftedMouseKey[7][2]=1;
     }*/
     /*else*/ if (MouseClickX>=CursorX) { //step 1..2 right
      /*cRSID_C64.*/PianoKeyScanCodeRow=7; /*cRSID_C64.*/PianoKeyScanCodeColumn=2;
     }
     else if (MouseClickX<CursorX) { //step 1..2 left
      ShiftedMouseKey[7][2]=1;
     }
    }
   }
  }
  else if (MouseClickY>=25) { //printf("Orderlist\n");
   if(FirstPress && (CursorX>=30 && CursorY<1)) { KeySeqCnt=1; FirstPress=0; }
   ShiftedMouseKey[0][6]=1; //F6 (F5+Shift)
  }
 }
 FirstPress=0;
 for(i=0;i<8;++i) for(j=0;j<8;++j) { if (ShiftedMouseKey[i][j]) { MouseShiftedKeypressSim=1; break; } }
 /*cRSID_C64.*/ShiftedKeypressSim=ShiftedKeypressSim|MouseShiftedKeypressSim; /*cRSID_C64.*/CBMkeypressSim=CBMkeypressSim|MouseCBMkeypressSim;
}

void mouseWheelUp() {
 if(CursorX<30 || CursorY>=1) ShiftedMouseKey[6][7]=1; // Shift+/ (Page-Up)
}

void mouseWheelDown() {
 if(CursorX<30 || CursorY>=1) { /*cRSID_C64.*/PianoKeyScanCodeRow=6; /*cRSID_C64.*/PianoKeyScanCodeColumn=7; } // '/' (Page-Down)
}


void mouseKeyReleaseCount() { //keypress emulated only for a short duration
 static byte i,j;
 if (MouseKeyPressDurationCnt>0) {
  --MouseKeyPressDurationCnt;
  if (MouseKeyPressDurationCnt<=MOUSEKEYPRESS_RELEASE_CNTVALUE) { //printf("released %d %d\n",MouseKeyPressDurationCnt,KeySeqCnt);
   /*cRSID_C64.*/PianoKeyScanCodeRow=0xF; /*cRSID_C64.*/PianoKeyScanCodeColumn=0xF;
   MouseShiftedKeypressSim=MouseCBMkeypressSim=0; for(i=0;i<8;++i) for(j=0;j<8;++j) {ShiftedMouseKey[i][j]=CBMmouseKey[i][j]=0;}
   MouseWheelUp=MouseWheelDown=0;
  }
  //else printf("pressed %d %d\n",MouseKeyPressDurationCnt,KeySeqCnt);
 }
 else {
  if (KeySeqCnt>0) { --KeySeqCnt; MouseKeyPressDurationCnt=MOUSEKEYPRESS_DURATOIN; }
  else {
   KeySeqCnt=0;
   //cRSID_C64.PianoKeyScanCodeRow=0xF; cRSID_C64.PianoKeyScanCodeColumn=0xF;
   MouseShiftedKeypressSim=MouseCBMkeypressSim=0;
   for(i=0;i<8;++i) for(j=0;j<8;++j) {ShiftedMouseKey[i][j]=CBMmouseKey[i][j]=0;}
   MouseClicked=MouseWheelUp=MouseWheelDown=0;
  }
 }
}
