# KESTREL: no threads; the scope loop body runs once a frame from frame() (kestrel_scopes_tick).
s/^\tscopeThread = SDL_CreateThread(scopeThreadFunc, "scope thread", NULL);/\treturn true; \/* KESTREL: ticked from frame() *\/\n&/
$a\
\
void kestrel_scopes_tick(void) /* KESTREL: the scope thread loop body, without its wait */\
{\
\tif (config.realVuMeters)\
\t\tupdateRealVuMeters();\
\tupdateScopes();\
}
# KESTREL: the scope's samples land inside its box (kestrel_fb_dirty, kestrel_sdl.c)
s/^\t\t\tuint32_t \*scopeDrawPtr = &video.frameBuffer\[(71 \* SCREEN_W) + scopeX\];$/&\n\t\t\tkestrel_fb_dirty(scopeX, 55, SCOPE_WIDTH, SCOPE_HEIGHT);/
