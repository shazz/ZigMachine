
#include "file.h"

#if (UNCOMPRESSED_NATIVES)
#else
 #include "../native/sources/tools/decompressor.c"
#endif


byte prevcompzptr=0, prevdecozptr=0;

#ifndef SIDMAKER
 byte ConfigPlayerType=0xFF, SelectedPlayerType=0, SelectedTuningType=0;
#endif
byte* ArgFileNamePtr=NULL;

static char* ExeNames [] = { "", EXENAME EXENAMETAIL_1SID, EXENAME EXENAMETAIL_2SID, EXENAME EXENAMETAIL_3SID, EXENAME EXENAMETAIL_4SID };
#ifndef SIDMAKER
static char* ExeNames_GUI [] = { "", EXENAME EXENAMETAIL_GUI EXENAMETAIL_1SID, EXENAME EXENAMETAIL_GUI EXENAMETAIL_2SID, EXENAME EXENAMETAIL_GUI EXENAMETAIL_3SID, EXENAME EXENAMETAIL_GUI EXENAMETAIL_4SID };
static char* ExeNames_PlayerType [] = { EXENAME EXENAMETAIL_NORMAL, EXENAME EXENAMETAIL_MEDIUM, EXENAME EXENAMETAIL_LIGHT, EXENAME EXENAMETAIL_EXTRA, EXENAME EXENAMETAIL_BARE, EXENAME EXENAMETAIL_DEMO };
static char* ExeNames_GUI_PlayerType [] = { EXENAME EXENAMETAIL_GUI EXENAMETAIL_NORMAL, EXENAME EXENAMETAIL_GUI EXENAMETAIL_MEDIUM, EXENAME EXENAMETAIL_GUI EXENAMETAIL_LIGHT, EXENAME EXENAMETAIL_GUI EXENAMETAIL_EXTRA, EXENAME EXENAMETAIL_GUI EXENAMETAIL_BARE, EXENAME EXENAMETAIL_GUI EXENAMETAIL_DEMO };
#endif
static char* WorkfileExtensions [] = { "", WORKFILE_EXTENSION_1SID, WORKFILE_EXTENSION_2SID, WORKFILE_EXTENSION_3SID, WORKFILE_EXTENSION_4SID };
static char* MagicStrings [] = { "", MAGICSTRING_1SID, MAGICSTRING_2SID, MAGICSTRING_3SID, MAGICSTRING_4SID };
static char DriverTypePositions [] = { -1, TUNE_DRIVERTYPE_POS_1SID, TUNE_DRIVERTYPE_POS_2SID, TUNE_DRIVERTYPE_POS_3SID, TUNE_DRIVERTYPE_POS_4SID };
static char TuningTypePositions [] = { -1, TUNE_TUNINGTYPE_POS_1SID, TUNE_TUNINGTYPE_POS_2SID, TUNE_TUNINGTYPE_POS_3SID, TUNE_TUNINGTYPE_POS_4SID };

byte ExampleDir[C64DIRLIST_SIZE_MAX] = { 0x01, 0x00,0x00,0x00,0x00,0x00,0x00, 'D','I','S','K',' ','N','A','M','E', '\0',
                                 0x01,0x02,0x03,0x04, '\"', 'F','I','L','E','N','A','M','E','-','1','.','S','W','M', '\"', '\0',
                                 0x00,0x02,0x02,0x01, '\"', 'F','I','L','E','N','A','M','E','2','.','S','W','M', '\"', '\0',
                                 0x00,0x00,0x06,0x05, '\"', 'F','I','L','E','N','A','M','E',' ','3','.','S','W','M', '\"', '\0',
                                 0x00,0x00,0x08,0x02, '\"', 'F','I','L','E','N','A','M','E','4','.','S','W','M', '\"', '\0',
                                 0x00,0x00,0x08,0x02, RETURNcode };
char StartUpPath[PATH_LENGTH_MAX]=".";
char C64drivePaths[DRIVE_AMOUNT][PATH_LENGTH_MAX]={".",".",".",".",".",".",".","."};
char C64driveChanged=0;
byte* C64dirList = ExampleDir;
int DirSize = 0;
char FolderKeys[DIR_FILES_MAX][C64_FILENAME_LENGTH_MAX];
int  FolderValues[DIR_FILES_MAX]; //char FolderValues[DIR_FILES_MAX][FILENAME_LENGTH_MAX];
int FolderAmount=0;
word ProgressSig=0, PrevProgressSig=0;

typedef struct { char *Name; unsigned char IsFile; unsigned char IsDir; } direntry;

FILE *fp = NULL;
byte DirectoryRead=0;
word DirReadCnt=0;
int FileAmount=0; direntry dirlist[DIR_FILES_MAX];
static int FolderKeyCharIndex=0;
static byte FileName[16+10+4+1]="";

char* SIDwizardFolderName = "";
//char FileDialogDirectory [PATH_LENGTH_MAX+2] = "."; //moved outside of GUI folder



static void updateSIDamount (char amount) {
 cRSID_C64.SIDchipCount = amount;
 DriverTypePos=DriverTypePositions[ cRSID_C64.SIDchipCount ]; TuningTypePos=TuningTypePositions[ cRSID_C64.SIDchipCount ];
 WorkfileExtension = WorkfileExtensions[ cRSID_C64.SIDchipCount ]; MagicString = MagicStrings[ cRSID_C64.SIDchipCount ];
}


//#ifndef SIDMAKER
char* filExt (byte* filename) { //get pointer of file-extension from filename string  //if no '.' found, point to end of the string
 char* LastDotPos = strrchr((const char*)filename,'.'); if (LastDotPos == NULL) return (char*) ((const char*)filename+strlen((const char*)filename)); //make strcmp not to find match, otherwise it would be segmentation fault
 return LastDotPos;
}
void cutExt (byte* filename) { *filExt(filename)='\0'; } //cut the extension of the filename by putting 0 at position of '.'  //omit original extension with 0 string-delimiter
//#else
char* filExt2(char *filename) { //get pointer of file-extension from filename string  //if no '.' found, point to end of the string
 static int i, firstdot;
 for(i=strlen(filename); i>0; --i) if (filename[i]=='.') firstdot=i;
 return &filename[firstdot];
}
//#endif


void initDiskIO() {
 wr(diskZPloadStatus,DISKSTATUS_OK); wr(diskZPdrive,DEFAULT_DRIVE); wr(0xBA,DEFAULT_DRIVE) //wr(diskZPargLoad,0);
}


INLINE void handleCHRIO (void) { //called at faster (samplerate) pace for faster byte-by-byte transfer
 int data=0;
 FASTVAR byte DiskZPloadStatus;

 DiskZPloadStatus = rd(diskZPloadStatus);

 if ( RARELY (DiskZPloadStatus/*rd(diskZPloadStatus)*/==DISKCMD_CHRIN) ) { ++ProgressSig;
  if (!DirectoryRead) /*(strcmp(FileName,"$"))*/ { //printf("%p\n",fp);
   if (fp!=NULL) {
    data=fgetc(fp); //if(data!=EOF) printf("%2.2X\n",data);
    if(data!=EOF) { wr(diskZPdata,data); wr(diskZPloadStatus,DISKSTATUS_OK); }
    else { wr(diskZPdata,0x00); wr(diskZPloadStatus,DISKSTATUS_EOF); }
   }
   else { wr(diskZPdata,RETURNcode); wr(diskZPloadStatus,DISKSTATUS_NOINPUT); }
  }
  else { //send disk-directory bytes
   data = C64dirList[DirReadCnt]; //ExampleDir[DirReadCnt];
   if(DirReadCnt<DirSize) { //<sizeof(ExampleDir)) {
    wr(diskZPdata,data); wr(diskZPloadStatus,DISKSTATUS_OK); ++DirReadCnt; //printf("%2.2X \n",data);
   }
   else {
    DirectoryRead=0; wr(diskZPdata,0x00); wr(diskZPloadStatus,DISKSTATUS_EOF);
   }
  }
 }
 else if ( RARELY (DiskZPloadStatus/*rd(diskZPloadStatus)*/==DISKCMD_CHROUT) ) { ++ProgressSig;
  if (fp!=NULL) {
   data=rd(diskZPdata);
   fputc(data,fp); //printf("o:%2.2X\n",data);
   wr(diskZPloadStatus,DISKSTATUS_OK);
  }
 }
 if ( RARELY ( rd(compzptr)!=prevcompzptr || rd(decozptr)!=prevdecozptr ) ) {
  ++ProgressSig;
  prevcompzptr=rd(compzptr); prevdecozptr=rd(decozptr);
 }
}


int cmpstr(char *string1, char *string2) { //compare strings alphabetically for sorting
 for (;;) {
  unsigned char char1 = tolower(*string1++); unsigned char char2 = tolower(*string2++);
  if (char1 < char2) return -1; if (char1 > char2) return 1; if ((!char1) || (!char2)) return 0;
}}


static INLINE void wrDir(byte data) { C64dirList[DirSize]=data; if(DirSize<C64DIRLIST_SIZE_MAX) ++DirSize; }
static INLINE void wrDirFolder(byte data) { wrDir(data); FolderKeys[FolderAmount][FolderKeyCharIndex]=data; ++FolderKeyCharIndex; }

void readDir (char* extension) {
 static int i=0,j=0,first=0; //,FolderKeyCharIndex=0;
 static DIR *Directory; static struct dirent *DirEntry; static struct stat st;
 static char path[PATH_LENGTH_MAX]=""; //static char DirListName[256]="";
 static direntry entrytmp;

 if (rd(diskZPdrive)!=DEFAULT_DRIVE) C64driveChanged=1;
 if ( C64driveChanged==0 && !strcmp(C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN],".") ) { //if no other drives used stick to the original working code
  getcwd(path, PATH_LENGTH_MAX);
  Directory = opendir(".");
 }
 else { //new code using more drives
  chdir(StartUpPath); //gives back starting point for relative-paths //realpath(C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN],path);
  strcpy(path,C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN]);
  chdir(path); getcwd(path, PATH_LENGTH_MAX); //printf("readfolder: device:%d--%s--%s--\n",rd(diskZPdrive),path,C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN]);
  Directory = opendir("."); //path);
 }
 FileAmount=0; DirSize=0; //counts entries
 if(Directory==NULL) { /*printf("can't read folder --%s--\n",path);*/ wr(diskZPloadStatus,DISKSTATUS_NOTFOUND); return; }

 while ((DirEntry = readdir(Directory))) { //printf("__%s__\n",DirEntry->d_name);
  stat(DirEntry->d_name, &st);
  if (st.st_mode & S_IFDIR) { dirlist[FileAmount].IsFile=0; dirlist[FileAmount].IsDir=1; }
  else { dirlist[FileAmount].IsFile=1; dirlist[FileAmount].IsDir=0; }
  #ifndef SIDMAKER
  if ( (!dirlist[FileAmount].IsFile && strcmp(DirEntry->d_name,".")) || !strcmp(extension,filExt((byte*)DirEntry->d_name)) ) { //printf("__%s__\n",DirEntry->d_name);
   dirlist[FileAmount].Name=strdup(DirEntry->d_name);
  #else
  if ( (!dirlist[FileAmount].IsFile && strcmp(DirEntry->d_name,".")) || !strcmp(extension,filExt2(DirEntry->d_name)) ) {
   dirlist[FileAmount].Name=strdup(DirEntry->d_name); //printf("__%s__%s__\n",extension,filExt2(DirEntry->d_name));
   if (!strcmp(filExt2(dirlist[FileAmount].Name),".exe.prg") || !strcmp(filExt2(dirlist[FileAmount].Name),".c64.prg")
   || !strcmp(filExt2(dirlist[FileAmount].Name),".drv.prg") || !strcmp(filExt2(dirlist[FileAmount].Name),".swp.prg") ) cutExt(dirlist[FileAmount].Name);  //strcpy(DirListName,dirlist[i].Name);
  #endif
   FileAmount++;
  }
 }
 closedir(Directory); //printf("readcloseddir %s %d\n",extension,FileAmount);

 for (i=0; i<FileAmount; i++) {
  first=i;
  for (j=i+1; j<FileAmount; j++) {
   if ( dirlist[j].IsFile<dirlist[first].IsFile
   || ( dirlist[j].IsFile==dirlist[first].IsFile && cmpstr(dirlist[j].Name,dirlist[first].Name)<0 ) ) {
    first=j;
  }}
  if (first!=i) { entrytmp=dirlist[i]; dirlist[i]=dirlist[first]; dirlist[first]=entrytmp; }
 }

 DirSize=0; FolderAmount=0;
 wrDir(0x01);
 for (i=0; i<6; ++i) wrDir(0x00);
 for (i=0; i<35/*24*/ && path[i]!='\0'; ++i) { wrDir(toupper(path[i])); /*printf("%2.2X\n",toupper(path[i]));*/ }   wrDir('\0');
 for(i=0;i<FileAmount;++i) { //printf("--%s--\n",dirlist[i].Name);
  for (j=0; j<4; ++j) wrDir(0x00); //filesize in BCD?
  wrDir('\"');
  if (dirlist[i].IsFile) { //simple file
   for (j=0; j<16 && dirlist[i].Name[j]!='\0'; ++j) wrDir(toupper(dirlist[i].Name[j])); //filename itself
  }
  else { //folder
   wrDir(FOLDER_CHARCODE); FolderKeyCharIndex=0; //add directory sign
   if (strlen(dirlist[i].Name)>12-1) { //doesn't fit into 11 chars
    for (j=0; j<12-1-2; ++j) wrDirFolder(toupper(dirlist[i].Name[j])); //foldername itself
    wrDirFolder(TOOLONG_CHARCODE);
    for(j=FolderAmount-1; j>=0; --j) { if( !strncmp(FolderKeys[j],FolderKeys[FolderAmount],10) ) break; }
    if(j>0) {
     if ( ('1'<=FolderKeys[j][10] && FolderKeys[j][10]<'9') || ('A'<=FolderKeys[j][10] && FolderKeys[j][10]<'Z') ) wrDirFolder( FolderKeys[j][10]+1 );
     else wrDirFolder( 'A' ); //if 1..9 exceeded, continue with a..z
    }
    else wrDirFolder('1');
   }
   else { //fits into 11 chars
    for (j=0; dirlist[i].Name[j]!='\0'; ++j) wrDirFolder(toupper(dirlist[i].Name[j])); //filename itself
    //for (; j<12-1; ++j) wrDir(' ');
   }
   FolderKeys[FolderAmount][FolderKeyCharIndex]='\0'; FolderValues[FolderAmount]=i; ++FolderAmount; //strcpy( FolderValues[FolderAmount], dirlist[i].Name );
   //for (j=0; j<4; ++j) wrDir(toupper(extension[j])); //cheat: add extension directory to enable folders displayed in vanilla SID-Wizard lister)
  }
  wrDir('\"'); wrDir('\0');
 }
 for (j=0; j<4; ++j) wrDir(0x00); //free bytes in BCD?
 wrDir(RETURNcode);  //for(i=0;i<DirSize;++i) {if(C64dirList[i]) printf("%c",C64dirList[i]); else printf("\n");}
 //for(i=0; i<FolderAmount; ++i) printf("--%s--%s--\n",FolderKeys[i],dirlist[FolderValues[i]].Name);

 //closedir(Directory); //printf("readcloseddir %s %d\n",extension,FileAmount);
 wr(diskZPloadStatus,DISKSTATUS_OK);
}


static INLINE void safeClose () { //(FILE* fp) {
 if(fp!=NULL) { fclose(fp); fp=NULL; }
}

static void checkChangeDriveFolder () {
 static byte prevDevice=0; //*prevFolder[PATH_LENGTH_MAX]="";
 if (rd(diskZPdrive)!=DEFAULT_DRIVE) C64driveChanged=1;
 if (C64driveChanged && rd(diskZPdrive)!=prevDevice) { //new code using more drives
  chdir(C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN]); //printf("checkfolder: device:%d--%s--\n",rd(diskZPdrive),C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN]); printf("folder changed\n");
 }
 prevDevice=rd(diskZPdrive);
}

static INLINE void openFileName(byte operation) {
 static int i;
 static char* Operation= "rb"; static char* Operations[2]={"rb","wb"};
 const char* FileNamePtr = (const char*) FileName; //for str.. functions not to warn

 Operation = Operations[operation];
 for (i=0; i<(int)sizeof(FileName) && i<rd(diskZPnameLen); ++i) FileName[i] = tolower ( rd( (rd(diskZPnameHi)<<8) + rd(diskZPnameLo) + i ) );
 FileName[i]='\0'; //printf("--%s-- %d -> ",FileName,rd(diskZPnameLen));
 if (strstr(FileNamePtr,",p,w")!=NULL) *strstr(FileNamePtr,",p,w")='\0';
 if (strstr(FileNamePtr,",s,w")!=NULL) *strstr(FileNamePtr,",s,w")='\0'; // printf("--%s-- %d \n",FileNamePtr,rd(diskZPnameLen));
 if ( strcmp(FileNamePtr,"$") && strcmp(FileNamePtr,"@swconfig") && strcmp(filExt(FileName),WorkfileExtension) && strcmp(filExt(FileName),".swi")
      && strcmp(filExt(FileName),".c64") && strcmp(filExt(FileName),".drv") && strcmp(filExt(FileName),".swp") && strcmp(filExt(FileName),".bin") && strcmp(filExt(FileName),".exe")
      && strcmp(filExt(FileName),".sid") && strcmp(filExt(FileName),".prg") ) { fp=NULL; return; }
 #ifndef SIDMAKER
 if(!strcmp(FileNamePtr,"@swconfig")) ConfigPlayerType=0; //default
 #endif
 if (ArgFileNamePtr==NULL || !strcmp(FileNamePtr,"@swconfig") /*|| !strcmp(FileNamePtr,"$")*/ ) { //printf(" %s %p\n",FileNamePtr,ArgFileNamePtr);
  if(strcmp(FileNamePtr,"$")) { //not dir-read? (then config)
   if ( operation==1 && ( !strcmp(filExt(FileName),".c64") || !strcmp(filExt(FileName),".drv") || !strcmp(filExt(FileName),".swp") || !strcmp(filExt(FileName),".exe") ) ) strcat((char*)FileNamePtr,".prg");
   fp=fopen(FileNamePtr,Operation);  //if (fp==NULL && operation==0) { strcat(FileNamePtr,".prg");  fp=fopen(FileNamePtr,Operation); }
  }
  else {
    DirectoryRead=1;
  }
 }
 else { //argument-file
  if ( ArgFileNamePtr && strcmp(FileNamePtr,"$") ) { //not dir-read character? open it
   fp=fopen((const char*)ArgFileNamePtr,Operation); //printf("--%s--%s-- %2.2X\n",FileName,ArgFileNamePtr,rd(diskZPloadStatus));
  }
 }
}


static INLINE void handleDiskIO () { //communicates with KERNAL.bin through diskZP variables
 static int i=0; //, DirReadCnt=0;
 static byte /*DirectoryRead=0,*/ /*FileName[16+10+4+1]="",*/ FolderName[16+10+4+1]="."; static int data=0; //static FILE *fp=NULL; //filaname might get appended by disk-commands
 static byte DiskZPloadStatus;
 //#ifdef SIDMAKER
  static char FiltExt[5]=WORKFILE_EXTENSION_1SID; //WorkfileExtension; // ".swm";
 //#endif
 const char* FileNamePtr = (const char*) FileName; //for str.. functions not to warn

 //printf("%2.2X\n",rd(diskZPloadStatus));
 switch ( DiskZPloadStatus = rd(diskZPloadStatus) ) {
  case DISKCMD_LOAD: { //if ( rd(diskZPloadStatus) == DISKCMD_LOAD ) {  //file-load requested
   DirectoryRead=0; checkChangeDriveFolder();
   openFileName(0);
   i = (rd(diskZPstartHi)<<8) + rd(diskZPstartLo);
   if ( fp != NULL ) {
    fgetc(fp);fgetc(fp); //skip prg-header (loadaddress)
    while ( (data=fgetc(fp)) != EOF ) { //printf("%4.4X:%2.2X \n",i,data);
     wr(i, data); ++i;
    }
    safeClose(/*fp*/); wr(diskZPendLo,i&0xFF); wr(diskZPendHi,i>>8);
    if (ArgFileNamePtr!=NULL) {
     chdir(dirname((char*)ArgFileNamePtr));
     ArgFileNamePtr=NULL; //arg-file loading is one-shot only
    }
    wr(diskZPloadStatus,DISKSTATUS_OK);
   }
   else wr(diskZPloadStatus,DISKSTATUS_NOTFOUND);
   //printf("%2.2X: %4.4X,%2.2X:--%s-- -> %4.4X\n",rd(diskZPloadStatus), (rd(diskZPnameHi)<<8) + rd(diskZPnameLo), rd(diskZPnameLen), FileName, (rd(diskZPstartHi)<<8)+rd(diskZPstartLo) );
   #ifndef SIDMAKER
    if(!strcmp(FileNamePtr,"@swconfig") || !strcmp(FileNamePtr,"@swconfig.prg")) {
     ConfigPlayerType=SelectedPlayerType=rd( (rd(diskZPstartHi)<<8) + rd(diskZPstartLo) + CONFIG_DRIVERTYPE_POS );
     SelectedTuningType=rd( (rd(diskZPstartHi)<<8) + rd(diskZPstartLo) + CONFIG_TUNINGTYPE_POS );
    }
   #endif
  } break;
  case DISKCMD_SAVE: { //else if ( rd(diskZPloadStatus) == DISKCMD_SAVE ) { //file-save requested
   DirectoryRead=0; checkChangeDriveFolder();
   openFileName(0);
   if (fp!=NULL && strcmp(FileNamePtr,"@swconfig") ) { safeClose(/*fp*/); wr(diskZPloadStatus,DISKSTATUS_FILEEXISTS); }
   else { //create new file
    openFileName(1);
    if ( fp != NULL ) {
     if(strcmp(filExt(FileName),".sid")) { fputc(rd(diskZPstartLo),fp); fputc(rd(diskZPstartHi),fp); } //write load-address into header first
     for ( i = (rd(diskZPstartHi)<<8) + rd(diskZPstartLo) ; i < (rd(diskZPendHi)<<8) + rd(diskZPendLo); ++i ) fputc(rd(i),fp); //printf("fex\n");
     safeClose(/*fp*/); wr(diskZPloadStatus,DISKSTATUS_OK);
    }
    else wr(diskZPloadStatus,DISKSTATUS_NOTFOUND);
   }
  } break;
  case DISKCMD_OPEN: { //else if( rd(diskZPloadStatus) == DISKCMD_OPEN ) { //file-open requested
   DirectoryRead=0; checkChangeDriveFolder();
   openFileName(0);  //printf("OPEN --%s-- , ArgFile: --%s--\n",FileNamePtr,ArgFileNamePtr); //gets filename
   if( !strcmp(filExt(FileName),".bin") || !strcmp(filExt(FileName),".c64") || !strcmp(filExt(FileName),".drv") || !strcmp(filExt(FileName),".swp") || !strcmp(filExt(FileName),".exe") || !strcmp(filExt(FileName),".sid") ) { //open for write-operations?
    //printf("Write-OPEN\n");
    if (fp!=NULL) { safeClose(/*fp*/); wr(diskZPloadStatus,DISKSTATUS_FILEEXISTS); }
    else { //write / create new file
     openFileName(1);
     if(fp!=NULL) { wr(diskZPloadStatus,DISKSTATUS_OK); }  //printf("wtf\n"); }
     else { wr(diskZPloadStatus,DISKSTATUS_NOTFOUND); }  //printf("%s notfound\n",FileName); }
    }
   }
   else { //open for read-operations
    if (DirectoryRead) /*strcmp(FileName,"$"))*/ {
     #ifndef SIDMAKER
      for(i=0;i<3;++i) FiltExt[i+1]=tolower(cRSID_C64.RAMbank[0x400+35+i]);
      readDir(FiltExt); //readDir(WorkfileExtension);
     #else
      for(i=0;i<3;++i) FiltExt[i+1]=tolower(cRSID_C64.RAMbank[0x400+35+i]); //printf("--%s--%s--\n",FiltExt,WorkfileExtension);
      if (!strcmp(FiltExt,".exe")) readDir(".exe.prg");
      else if (!strcmp(FiltExt,".c64")) readDir(".c64.prg");
      else if (!strcmp(FiltExt,".drv")) readDir(".drv.prg");
      else if (!strcmp(FiltExt,".swp")) readDir(".swp.prg");
      else readDir(FiltExt);
     #endif
     DirReadCnt=0;   //wr(diskZPloadStatus,DISKSTATUS_OK); set in readDir()
    }
    else if (fp!=NULL) { wr(diskZPloadStatus,DISKSTATUS_OK); } //printf("OK\n"); }
    else { wr(diskZPloadStatus,DISKSTATUS_NOTFOUND); } //printf("%s notfound\n",FileName); }
   }
  } break;
  case DISKCMD_CLOSE: { //else if ( rd(diskZPloadStatus) == DISKCMD_CLOSE ) {
   if (DirectoryRead || !strcmp(FileNamePtr,"$")) DirectoryRead=0;
   else if(fp!=NULL ) safeClose(/*fp*/);
   wr(diskZPloadStatus,DISKSTATUS_OK);  //printf("CLOSE_OK\n");
  } break;
  case DISKCMD_CHDIR: { //else if ( rd(diskZPloadStatus) == DISKCMD_CHDIR ) { //printf("%d\n",rd(diskZPnameLen));
   //for(i=0; i<FolderAmount; ++i) printf("--%s--%s--\n",FolderKeys[i],dirlist[FolderValues[i]].Name);
   for (i=rd(diskZPnameLen)-1; i>0; --i) {
    if ( (rd((rd(diskZPnameHi)<<8) + rd(diskZPnameLo) + i) & 0x7F)!=' ' && (rd((rd(diskZPnameHi)<<8) + rd(diskZPnameLo) + i) & 0x7F)!='\"' ) {
     FolderName[i]='\0'; break;
   }}
   for (--i; i>=0; --i) FolderName[i] = toupper ( rd( (rd(diskZPnameHi)<<8) + rd(diskZPnameLo) + i + 1) & 0x7F );
   //printf("*--%s--\n",FolderName); //for (i=0;FolderName[i]!='\0';++i) printf("%2.2X ", FolderName[i]);
   for(i=0;i<FolderAmount;++i) { //printf("--%s-- vs  --%s--%s--\n",FolderName,FolderKeys[i],dirlist[FolderValues[i]].Name);
    if(!strcmp(FolderKeys[i],(char*)FolderName)) {
     chdir(dirlist[FolderValues[i]].Name);
     getcwd(C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN], PATH_LENGTH_MAX); //printf("--%s--%s--%s--\n",FolderName,dirlist[FolderValues[i]].Name,C64drivePaths[rd(diskZPdrive)-DRIVENUM_MIN]);
     break;
   }}
   wr(diskZPloadStatus,DISKSTATUS_OK);
  } break;
  //else MIDI
 }

}


char folderExists (char* path) { static struct stat st; return ( stat(path, &st) != -1 ); }

char* makePath (char* folderpath, char* filename) { //don't assing the output to a variable, use it only on demand...
 static char PathAndFileName [PATH_LENGTH_MAX+2+FILENAME_LENGTH_MAX+2];
 snprintf( PathAndFileName, PATH_LENGTH_MAX+2+FILENAME_LENGTH_MAX, "%s%s%s", folderpath, DIR_SEPARATOR, filename );
 return PathAndFileName; //not preferable in C to return pointer of internal array, but this at least avoids memory-leak
}

static char* addHomeFolderPath (char* basename) { //don't assing the output to a variable, use it only on demand...
 char *HomeFolder = getenv("HOME");
 #ifdef WINDOWS
 if (HomeFolder == NULL) HomeFolder = getenv("USERPROFILE");
 #endif
 return makePath( HomeFolder, basename );
}

static char* getSIDwizardFolderPath () { //don't assing the output to a variable, use it only on demand...
 static char Path [PATH_LENGTH_MAX+4+FILENAME_LENGTH_MAX+4];
 strncpy( Path, addHomeFolderPath( SIDWIZARD_USER_SUBFOLDER ), PATH_LENGTH_MAX+2+FILENAME_LENGTH_MAX+2 );
 return Path; //not preferable in C to return pointer of internal array, but this at least avoids memory-leak
}


static char readConfigFileData (FILE* file, char load) {
 int i; static char SettingName [32];

 static struct LoadedConfigData {
  char C64drivePaths [DRIVE_AMOUNT] [PATH_LENGTH_MAX+2];
  int Zoom;
  int MainVolume;
  int Stereo;
  int HighQualitySID;
  int HighQualityResampler;
  int SelectedSIDmodel;
  int HQborder;
  char MIDIdeviceName [MIDI_NAME_LENGTH_MAX+1];
 } LoadedConfigData;

 char Difference = 0;
 //these rows should be kept in sync with saveConfigFile() rows:
 for (i=0; i<DRIVE_AMOUNT; ++i) {
  sprintf( SettingName, "C64drivePaths[%d]=%%s\n", DRIVENUM_MIN + i );
  if ( fscanf( file, SettingName, (char*) &LoadedConfigData.C64drivePaths[i] ) == 1 ) {
   if ( strcmp( C64drivePaths[i], LoadedConfigData.C64drivePaths[i] ) ) Difference = 1;
   if (load) strcpy( C64drivePaths[i], LoadedConfigData.C64drivePaths[i] );
  }
  else if (C64drivePaths[i][0] != '\0') Difference = 1;
 }
 if ( fscanf( file, "Zoom=%d\n", &LoadedConfigData.Zoom ) == 1 ) {
  if (Zoom != LoadedConfigData.Zoom) Difference = 1;
  if (load) Zoom = (signed char) LoadedConfigData.Zoom;
 }
 if ( fscanf( file, "MainVolume=%d\n", &LoadedConfigData.MainVolume ) == 1 ) {
  if (cRSID.MainVolume != LoadedConfigData.MainVolume) Difference = 1;
  if (load) cRSID.MainVolume = (unsigned char) LoadedConfigData.MainVolume;
 }
 if ( fscanf( file, "Stereo=%d\n", &LoadedConfigData.Stereo ) == 1 ) {
  if (cRSID.Stereo != LoadedConfigData.Stereo) Difference = 1;
  if (load) cRSID.Stereo = (unsigned char) LoadedConfigData.Stereo;
 }
 if ( fscanf( file, "HighQualitySID=%d\n", &LoadedConfigData.HighQualitySID ) == 1 ) {
  if (cRSID.HighQualitySID != LoadedConfigData.HighQualitySID) Difference = 1;
  if (load) cRSID.HighQualitySID = LoadedConfigData.HighQualitySID;
 }
 if ( fscanf( file, "HighQualityResampler=%d\n", &LoadedConfigData.HighQualityResampler ) == 1 ) {
  if (cRSID.HighQualityResampler != LoadedConfigData.HighQualityResampler) Difference = 1;
  if (load) cRSID.HighQualityResampler = LoadedConfigData.HighQualityResampler;
 }
 if ( fscanf( file, "SelectedSIDmodel=%d\n", &LoadedConfigData.SelectedSIDmodel ) == 1 ) {
  if (cRSID.SelectedSIDmodel != LoadedConfigData.SelectedSIDmodel) Difference = 1;
  if (load) cRSID.SelectedSIDmodel = LoadedConfigData.SelectedSIDmodel;
 }
 if ( fscanf( file, "HQborder=%d\n", &LoadedConfigData.HQborder ) == 1 ) {
  if (BorderAlias != LoadedConfigData.HQborder) Difference = 1;
  if (load) BorderAlias = LoadedConfigData.HQborder;
 }
 if ( fscanf( file, "MIDIdeviceName=%s\n", (char*) &LoadedConfigData.MIDIdeviceName ) == 1 ) {
  if ( strcmp( (char*)ArgMIDIname, LoadedConfigData.MIDIdeviceName ) ) Difference = 1;
  if (load) strcpy( (char*)ArgMIDIname, LoadedConfigData.MIDIdeviceName );
 }
 else if (ArgMIDIname[0] != '\0') Difference = 1;
 return Difference;
}


static void loadConfigFile () {
 FILE *file;
 if ( ( file = fopen( makePath( getSIDwizardFolderPath(), CONFIGFILE_NAME ), "r" ) ) == NULL ) {
  printf( "There's no config file saved yet. Will create it upon exit.\n" );
 }
 else { readConfigFileData( file, 1 ); fclose( file ); }
}


static void saveConfigFile () {
 int i; static char SettingName [32];
 FILE *file; char Difference = 0;

 if ( ( file = fopen( makePath( getSIDwizardFolderPath(), CONFIGFILE_NAME ), "r" ) ) == NULL )
 { printf( "Couldn't open a config-file yet for change-checking! Trying to save it anyway (for the first time)...\n" ); }
 else { Difference = readConfigFileData( file, 0 ); fclose( file ); if ( !Difference ) return; }
 if ( ( file = fopen( makePath( getSIDwizardFolderPath(), CONFIGFILE_NAME ), "w" ) ) != NULL ) {
  //these rows should be kept in sync with readConfigFiledata() rows:
  for (i=0; i<DRIVE_AMOUNT; ++i) {
   sprintf( SettingName, "C64drivePaths[%d]=%%s\n", DRIVENUM_MIN + i );
   fprintf( file, SettingName, C64drivePaths[i] );
  }
  fprintf( file, "Zoom=%d\n", Zoom );
  fprintf( file, "MainVolume=%d\n", cRSID.MainVolume );
  fprintf( file, "Stereo=%d\n", cRSID.Stereo );
  fprintf( file, "HighQualitySID=%d\n", cRSID.HighQualitySID );
  fprintf( file, "HighQualityResampler=%d\n", cRSID.HighQualityResampler );
  fprintf( file, "SelectedSIDmodel=%d\n", cRSID.SelectedSIDmodel );
  fprintf( file, "HQborder=%d\n", BorderAlias );
  fprintf( file, "MIDIdeviceName=%s\n", (char*)ArgMIDIname );
  fclose( file );
 }
 else { printf( "Couldn't write the config-file, current settings got lost on exit.\n" ); }
}


void decrunchC64code (const unsigned char* indata, int insize) {
 enum { C64_MEMORY_TOP = 0x10000 };
 int i, OutSize;
 #if (UNCOMPRESSED_NATIVES)
 for (i=2; i < insize; ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = indata[i]; }
 #else
 static unsigned char DecrunchBuffer [C64_MEMORY_TOP + 1]; //needed because writing to end of RAMbank would overwrite important IRQ/etc.vectors
 //const unsigned char* InDataTop = indata + insize-1; //-1 needed because of bin2array's auto-appended extra closing '0'
 //unsigned char *OutDataPtr; //, *OutDataTop = &DecrunchBuffer[C64_MEMORY_TOP];  //printf( "%p, %p %d\n", OutDataTop, indata, insize-1 );  //&C64->RAMbank[ C64_MEMORY_TOP ];
 Compression_decompressorCopyData( (unsigned char*) indata, insize, DecrunchBuffer ); //OutDataPtr =  //exoraw_decrunch( InDataTop, OutDataTop );
 OutSize = Compression_decompressData( DecrunchBuffer, insize, &C64->RAMbank[ BASIC_START_ADDRESS - 2 ] ); //OutDataTop - OutDataPtr;  //printf( "%p,%p, %d, %p %d\n", OutDataTop, OutDataPtr, OutSize, indata, insize-1 );
 //for (i=2; i < OutSize; ++i) C64->RAMbank[ BASIC_START_ADDRESS+ (i-2) ] = *(OutDataPtr + i);  //for (; i < C64_MEMORY_TOP; ++i) C64->RAMbank[ i ] = 0;
 #endif
}


void loadNativeC64code () {
 int i;

#ifndef SIDMAKER  //SID-Wizard:

 #if (!FORCED_SDL_EVENTS)
 if (!TUImode)
 #endif
 {
 #if (ENABLED_SDL)
  switch (cRSID_C64.SIDchipCount) {
   case 1: //#if (SIDAMOUNT==1)
    decrunchC64code(SID_Wizard,sizeof(SID_Wizard)-1); //for (i=2; i < (int)sizeof(SID_Wizard/*SID_Wizard_1_8*/); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard[i]; } //SID_Wizard_1_8[i]; }
    break;
   case 2: //#elif (SIDAMOUNT==2)
    decrunchC64code(SID_Wizard_2SID,sizeof(SID_Wizard_2SID)-1); //for (i=2; i < (int)sizeof(SID_Wizard_2SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_2SID[i]; }
    break;
   case 3: //#elif (SIDAMOUNT==3)
    decrunchC64code(SID_Wizard_3SID,sizeof(SID_Wizard_3SID)-1); //for (i=2; i < (int)sizeof(SID_Wizard_3SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_3SID[i]; }
    break;
   case 4: //#elif (SIDAMOUNT==4)
    decrunchC64code(SID_Wizard_4SID,sizeof(SID_Wizard_4SID)-1); //for (i=2; i < (int)sizeof(SID_Wizard_4SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_4SID[i]; }
    break;
  } //#endif
 #endif
 }
 #if (!FORCED_SDL_EVENTS)
 else
 #endif
 {
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  switch (cRSID_C64.SIDchipCount) {
   case 1: //#if (SIDAMOUNT==1)
    decrunchC64code(SID_Wizard_for_TUI,sizeof(SID_Wizard_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Wizard_for_TUI/*SID_Wizard_1_8*/); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_for_TUI[i]; } //SID_Wizard_1_8[i]; }
    break;
   case 2: //#elif (SIDAMOUNT==2)
    decrunchC64code(SID_Wizard_2SID_for_TUI,sizeof(SID_Wizard_2SID_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Wizard_2SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_2SID_for_TUI[i]; }
    break;
   case 3: //#elif (SIDAMOUNT==3)
    decrunchC64code(SID_Wizard_3SID_for_TUI,sizeof(SID_Wizard_3SID_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Wizard_3SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_3SID_for_TUI[i]; }
    break;
   case 4: //#elif (SIDAMOUNT==4)
    decrunchC64code(SID_Wizard_4SID_for_TUI,sizeof(SID_Wizard_4SID_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Wizard_4SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Wizard_4SID_for_TUI[i]; }
    break;
  } //#endif
 #endif
 }

#else   //SID-Maker:

 #if (!FORCED_SDL_EVENTS)
 if (!TUImode)
 #endif
 {
 #if (ENABLED_SDL)
  switch (cRSID_C64.SIDchipCount) {
   case 1: //#if (SIDAMOUNT==1)
    if (SFXsupport) { //#ifdef SFX_SUPPORT
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SFX,sizeof(SID_Maker_ROM_SFX)-1);
     else decrunchC64code(SID_Maker_SFX,sizeof(SID_Maker_SFX)-1); //for (i=2; i < (int)sizeof(SID_Maker_SFX); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_SFX[i]; }
    }
    else if (SWPsupport) { //#elif defined(SWP_SUPPORT)
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SWP,sizeof(SID_Maker_ROM_SWP)-1);
     else decrunchC64code(SID_Maker_SWP,sizeof(SID_Maker_SWP)-1); //for (i=2; i < (int)sizeof(SID_Maker_SWP); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_SWP[i]; }
    }
    else if (EchoSupport) //#elif defined(ECHO_SUPPORT)
     decrunchC64code(SID_Maker_echo,sizeof(SID_Maker_echo)-1); //for (i=2; i < (int)sizeof(SID_Maker_echo); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_echo[i]; }
    else { //#else
     if (ROMsupport) decrunchC64code(SID_Maker_ROM,sizeof(SID_Maker_ROM)-1);
     else decrunchC64code(SID_Maker,sizeof(SID_Maker)-1); //for (i=2; i < (int)sizeof(SID_Maker); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker[i]; }
    } //#endif
    break;
   case 2: //#elif (SIDAMOUNT==2)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SWP_2SID,sizeof(SID_Maker_ROM_SWP_2SID)-1);
     else decrunchC64code(SID_Maker_SWP_2SID,sizeof(SID_Maker_SWP_2SID)-1);
    }
    else {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_2SID,sizeof(SID_Maker_ROM_2SID)-1);
     else decrunchC64code(SID_Maker_2SID,sizeof(SID_Maker_2SID)-1); //for (i=2; i < (int)sizeof(SID_Maker_2SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_2SID[i]; }
    }
    break;
   case 3: //#elif (SIDAMOUNT==3)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SWP_3SID,sizeof(SID_Maker_ROM_SWP_3SID)-1);
     else decrunchC64code(SID_Maker_SWP_3SID,sizeof(SID_Maker_SWP_3SID)-1);
    }
    else {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_3SID,sizeof(SID_Maker_ROM_3SID)-1);
     else decrunchC64code(SID_Maker_3SID,sizeof(SID_Maker_3SID)-1); //for (i=2; i < (int)sizeof(SID_Maker_3SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_3SID[i]; }
    }
    break;
   case 4: //#elif (SIDAMOUNT==4)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SWP_4SID,sizeof(SID_Maker_ROM_SWP_4SID)-1);
     else decrunchC64code(SID_Maker_SWP_4SID,sizeof(SID_Maker_SWP_4SID)-1);
    }
    else {
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_4SID,sizeof(SID_Maker_ROM_4SID)-1);
     else decrunchC64code(SID_Maker_4SID,sizeof(SID_Maker_4SID)-1); //for (i=2; i < (int)sizeof(SID_Maker_4SID); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_4SID[i]; }
    }
    break;
  } //#endif
 #endif
 }
 #if (!FORCED_SDL_EVENTS)
 else
 #endif
 {
 #if (ENABLED_TUI_KEYS) //(ENABLED_TUI)
  switch (cRSID_C64.SIDchipCount) {
   case 1: //#if (SIDAMOUNT==1)
    if (SFXsupport) { //#ifdef SFX_SUPPORT
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SFX_for_TUI,sizeof(SID_Maker_ROM_SFX_for_TUI)-1);
     else decrunchC64code(SID_Maker_SFX_for_TUI,sizeof(SID_Maker_SFX_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Maker_SFX_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_SFX_for_TUI[i]; }
    }
    else if (SWPsupport) { //#elif defined(SWP_SUPPORT)
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_SWP_for_TUI,sizeof(SID_Maker_ROM_SWP_for_TUI)-1);
     else decrunchC64code(SID_Maker_SWP_for_TUI,sizeof(SID_Maker_SWP_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Maker_SWP_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_SWP_for_TUI[i]; }
    }
    else if (EchoSupport) //#elif defined(ECHO_SUPPORT)
     decrunchC64code(SID_Maker_echo_for_TUI,sizeof(SID_Maker_echo_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Maker_echo_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_echo_for_TUI[i]; }
    else { //#else
     if (ROMsupport) decrunchC64code(SID_Maker_ROM_for_TUI,sizeof(SID_Maker_ROM_for_TUI)-1);
     else decrunchC64code(SID_Maker_for_TUI,sizeof(SID_Maker_for_TUI)-1); //for (i=2; i < (int)sizeof(SID_Maker_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_for_TUI[i]; }
    } //#endif
    break;
   case 2: //#elif (SIDAMOUNT==2)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_SWP_2SID_for_TUI, sizeof(SID_Maker_ROM_SWP_2SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_SWP_2SID_for_TUI, sizeof(SID_Maker_SWP_2SID_for_TUI)-1 );
    }
    else {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_2SID_for_TUI, sizeof(SID_Maker_ROM_2SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_2SID_for_TUI, sizeof(SID_Maker_2SID_for_TUI)-1 ); //for (i=2; i < (int)sizeof(SID_Maker_2SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_2SID_for_TUI[i]; }
    }
    break;
   case 3: //#elif (SIDAMOUNT==3)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_SWP_3SID_for_TUI, sizeof(SID_Maker_ROM_SWP_3SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_SWP_3SID_for_TUI, sizeof(SID_Maker_SWP_3SID_for_TUI)-1 );
    }
    else {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_3SID_for_TUI, sizeof(SID_Maker_ROM_3SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_3SID_for_TUI, sizeof(SID_Maker_3SID_for_TUI)-1 ); //for (i=2; i < (int)sizeof(SID_Maker_3SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_3SID_for_TUI[i]; }
    }
    break;
   case 4: //#elif (SIDAMOUNT==4)
    if (SWPsupport) {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_SWP_4SID_for_TUI, sizeof(SID_Maker_ROM_SWP_4SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_SWP_4SID_for_TUI, sizeof(SID_Maker_SWP_4SID_for_TUI)-1 );
    }
    else {
     if (ROMsupport) decrunchC64code( SID_Maker_ROM_4SID_for_TUI, sizeof(SID_Maker_ROM_4SID_for_TUI)-1 );
     else decrunchC64code( SID_Maker_4SID_for_TUI, sizeof(SID_Maker_4SID_for_TUI)-1 ); //for (i=2; i < (int)sizeof(SID_Maker_4SID_for_TUI); ++i) { C64->RAMbank [ BASIC_START_ADDRESS + (i-2) ] = SID_Maker_4SID_for_TUI[i]; }
    }
    break;
  } //#endif
 #endif
 }

#endif

}