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
