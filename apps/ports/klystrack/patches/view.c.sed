# KESTREL (round 4): src/view.c's my_draw_view runs each view through kestrel_views.c, which skips a view on an
# event-free repaint when nothing it reads changed (its draws are kept from last frame: kestrel_view.c).
s/^\t\t\tview->handler(domain, &area, &event, view->param);$/\t\t\tkestrel_view_run(view, domain, \&area, \&event, iter); \/* KESTREL *\//
/^void my_draw_view(const View\* views, const SDL_Event \*_event, GfxDomain \*domain)$/i\
void kestrel_view_run(const View *view, GfxDomain *dom, const SDL_Rect *area, const SDL_Event *event, int iter); /* KESTREL: kestrel_views.c */
# klystron's gui/view.c has the same name (patches apply by file name): its draw_view (the dialogs') is unchanged.
/^void draw_view(GfxDomain \*dest, const View\* views, const SDL_Event \*_event)$/i\
/* KESTREL: unchanged; klystrack's main views go through src/view.c's my_draw_view (patches/view.c.sed). */
