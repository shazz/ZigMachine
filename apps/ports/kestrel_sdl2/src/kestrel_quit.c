/* Quitting a program: back to the GEM desktop it was launched from.
 *
 * A port runs as a GEM program: its disk is a data disk, GEM launches the program file on it (request 3),
 * and the program ends with request 4, which brings the desktop back over the same disk
 * (docs/sealed-loader.js, the board glass's app_request.zig). That is the host's cart-swap protocol: the
 * cart's pollCartRequest export, polled after every frame, answering 4 from the moment the program has
 * quit (as SysInfo and ST Replay do). Every port reaches kestrel_quit() from its own quit:
 *   SDL_Quit()   what a program calls on its way out (GrafX2's main does; klystrack registers it atexit)
 *   the port     when the program's main loop has ended (kestrel_main: pt2's programRunning, GrafX2's and
 *                klystrack's main returning, ChipNomad's mainLoopTriggerQuit)
 * exit() (WASI proc_exit, kestrel_wasi.c) asks for it too before it traps: on an error path the program
 * cannot carry on, and the request is the most a trapped cart can leave behind. */
void kestrel_log(const char *m);

static int quit;

void kestrel_quit(void)
{
    if (quit) return;
    quit = 1;
    kestrel_log("quit: back to the desktop (request 4)");
}

void SDL_Quit(void) { kestrel_quit(); }

/* The host's swap protocol: 0 = carry on, 4 = back to the OS (the desktop, its disk still in the drive). */
__attribute__((export_name("pollCartRequest"))) int pollCartRequest(void) { return quit ? 4 : 0; }
