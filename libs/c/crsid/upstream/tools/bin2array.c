#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define FILENAME_LENGTH_MAX 256

FILE *InputFile, *OutputFile;
char InputFileName[FILENAME_LENGTH_MAX]; //input-file described as 1st command-line parameter
char OutputFileName[FILENAME_LENGTH_MAX]; //output-file
char ArrayName[FILENAME_LENGTH_MAX];

unsigned char hexdigi[16+1]="0123456789ABCDEF";

char* FilExt(char *filename) //get pointer of file-extension from filename string
{  //if no '.' found, point to end of the string
 char* LastDotPos = strrchr(filename,'.');
 if (LastDotPos == NULL) return (filename+strlen(filename)); //make strcmp not to find match, otherwise it would be segmentation fault
 return LastDotPos;
}

void CutExt(char *filename) //cut the extension of the filename by putting 0 at position of '.'
{
 *FilExt(filename)=0; //omit original extension with 0 string-delimiter
}

void ChangeExt(char *filename,const char *newExt) //change the extension of the file
{
 CutExt(filename); //omit original extension with 0 string-delimiter
 strcat(filename,newExt); //expand with new extension
}

int main(int argc, char *argv[])
{
 int i, readata, colcnt=0, rowcnt=0;
 unsigned char digi1,digi2;

 if (argc==1) printf ("\n========================================\n"
                      "Binary file to c/c++ array converter\n"
                      "------------------------------------------\n"
                      "usage:  bin2array <inputfile> [outputfile]\n"
                      "------------------------------------------\n"
                      "  v1.2  2023 Hermit Software         \n"
                      "==========================================\n");

 if ( argc>=2 )
 {
  strcpy(InputFileName,argv[1]);
  InputFile = fopen(InputFileName,"rb"); //!!!important "rb" is for binary (not to check text-control characters)
  if ( InputFile == NULL )
  {
   printf( "\n! Could not open input-file...\n\n" );
   exit(1);
  }
  else
  {
   if(argc<3) { strcpy(OutputFileName,InputFileName); ChangeExt(OutputFileName,".h"); }
   else strcpy(OutputFileName,argv[2]);

   OutputFile = fopen(OutputFileName,"wb"); //!!!important "wb" is for binary (not to check text-control characters)

   //printf("\n\n**** Converting binary file %s to %s .c Array ****.\n---------------------------------------------\n", InputFileName, OutputFileName) );

   if (strchr(OutputFileName,'/')!=NULL) strcpy( ArrayName, strrchr(OutputFileName,'/')+1 );
   else strcpy(ArrayName, OutputFileName);
   CutExt(ArrayName);
   for (i=0;i<strlen(ArrayName);i++) if (ArrayName[i]=='-' || ArrayName[i]==' ' || ArrayName[i]=='.') ArrayName[i]='_';
   fputs("\nstatic const unsigned char ",OutputFile); fputs(ArrayName,OutputFile);
   fputs(" [] =   //array generated from binary by bin2array 1.2 (made in 2023 by Hermit) \n{\n ",OutputFile);

   do
   {
    readata=fgetc(InputFile); //printf("%2X,",(unsigned char)readata);
    if (readata!=EOF)
    {
     digi1=hexdigi[(unsigned char)readata/16]; digi2=hexdigi[(unsigned char)readata&0xF];
     fputs("0x",OutputFile); fputc(digi1,OutputFile); fputc(digi2,OutputFile); fputc(',',OutputFile);
     colcnt++; if (colcnt>=0x20) {rowcnt++;fputs("\n ",OutputFile); /*printf(".");*/ colcnt=0;};
    }
   }
   while (readata!=EOF);
   fputs(/* " 0 */ " \n};",OutputFile);

   //printf("\n\n**** Conversion to .c Array is done.... ****.\n---------------------------------------------\n");

   fclose (OutputFile); fclose(InputFile);
  }
 }
 else printf("\n! Please give the input-file name.\n\n");

 return 0;
}
