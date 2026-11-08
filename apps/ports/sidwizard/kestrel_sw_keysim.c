/* Opening a song at start, as upstream's PC version does with a file given on its command line (SIDwizard.c:
 * the argument file is read for its player and tuning type, then key presses are simulated: the start-up menu's
 * player type and tuning, then F8, Down, Return, Return in the editor, the file dialog opening that file). Ported
 * as it is, in its own 5 ms ticks (sw_tick). Included by kestrel_sw.c. */

#define SW_BOOT_SONG "FLASHBAK.SWM"            /* Hermit's "Flash It Back", on the floppy (upstream examples/) */

static byte sw_arg_file[65536];
static char sw_arg_name[64];
static byte FilePlayerType, FileTuningType;
static short KeySimEditorWaitCnt = KEYSIM_EDITORWAIT, KeySimRepeatDelay = KEYSIM_REPEATDELAY,
             KeySimPressDuration = KEYSIM_PRESSDURATION, KeySimStartupDelayCnt = KEYSIM_STARTUPDELAY,
             KeySimRepeatDelayCnt = KEYSIM_REPEATDELAY;
static byte PlayerSelected, TuningSelected, LoadKeyCnt;

/* main()'s argument loop for a work file: the data after the load address, checked for its magic string. */
static void sw_keysim_open(const char *name)
{
    FILE *fp = fopen(name, "rb");
    int data;
    if (!fp) { kestrel_log("sidwizard: no song to open at start"); return; }
    fgetc(fp); fgetc(fp);                                  /* the prg header (load address) */
    while ((data = fgetc(fp)) != EOF && ArgFileDataSize < (int)sizeof sw_arg_file) sw_arg_file[ArgFileDataSize++] = (byte)data;
    fclose(fp);
    for (int j = 0; j < 4; j++) if (sw_arg_file[j] != MagicString[j]) { kestrel_log("sidwizard: not a .swm"); ArgFileDataSize = 0; return; }
    FilePlayerType = sw_arg_file[DriverTypePos]; FileTuningType = sw_arg_file[TuningTypePos];
    strncpy(sw_arg_name, name, sizeof sw_arg_name - 1);
}

/* The start-up menu: player type, then tuning, one simulated key a round. */
static void sw_keysim_menu(void)
{
    if (KeySimRepeatDelayCnt > 0) {
        KeySimRepeatDelayCnt--;
        if (KeySimRepeatDelayCnt < KeySimRepeatDelay - KeySimPressDuration) {
            simulateKey_DOWN(0); simulateKey_UP(0); simulateKey_RIGHT(0); simulateKey_RETURN(0);
        }
        else if (SelectedPlayerType < FilePlayerType) simulateKey_DOWN(1);
        else if (SelectedPlayerType > FilePlayerType) simulateKey_UP(1);
        else if (!PlayerSelected) PlayerSelected = 1;
        else if (SelectedTuningType != FileTuningType) simulateKey_RIGHT(1);
        else { simulateKey_RETURN(1); TuningSelected = 1; }
        return;
    }
    if (PlayerSelected && TuningSelected) {
        KeySimStartupDelayCnt = -1;
        simulateKey_DOWN(0); simulateKey_UP(0); simulateKey_RIGHT(0); simulateKey_RETURN(0);
    }
    KeySimRepeatDelayCnt = KeySimRepeatDelay;
    if (!PlayerSelected) {
        if (SelectedPlayerType < FilePlayerType) ++SelectedPlayerType;
        else if (SelectedPlayerType > FilePlayerType) --SelectedPlayerType;
    } else if (SelectedTuningType != FileTuningType) { if (++SelectedTuningType > 3) SelectedTuningType = 0; }
}

/* In the editor: F8 (disk menu), Down (load), Return (the dialog opens the argument file), Return. */
static void sw_keysim_load(void)
{
    if (KeySimRepeatDelayCnt <= 0) { KeySimRepeatDelayCnt = KeySimRepeatDelay; ++LoadKeyCnt; return; }
    KeySimRepeatDelayCnt--;
    if (KeySimRepeatDelayCnt < KeySimRepeatDelay - KeySimPressDuration) {
        simulateKey_F8(0); simulateKey_DOWN(0); simulateKey_RETURN(0);
    }
    else if (LoadKeyCnt == 0) simulateKey_F8(1);
    else if (LoadKeyCnt == 1) simulateKey_DOWN(1);
    else if (LoadKeyCnt == 2) { simulateKey_RETURN(1); ArgFileNamePtr = (byte *)sw_arg_name; }
    else if (LoadKeyCnt == 3) simulateKey_RETURN(1);
    else {
        ArgLoading = 0; KeySimEditorWaitCnt = -1;
        simulateKey_F8(0); simulateKey_DOWN(0); simulateKey_RETURN(0);
        kestrel_log("sidwizard: song opened");
    }
}

static void sw_keysim(void)
{
    if (ArgFileDataSize <= 0) { if (KeySimStartupDelayCnt > 0) KeySimStartupDelayCnt--; return; }
    if (KeySimStartupDelayCnt > 0) { ArgLoading = 1; KeySimStartupDelayCnt--; return; }
    if (ConfigPlayerType == 0xFF) return;                  /* the start-up menu is not up yet */
    if (KeySimStartupDelayCnt == 0) { sw_keysim_menu(); return; }
    if (KeySimEditorWaitCnt < 0) return;
    if (KeySimEditorWaitCnt > 0) { KeySimEditorWaitCnt--; return; }
    sw_keysim_load();
}
