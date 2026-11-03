# KESTREL: the QUIT button confirms with a second click, not askBox()'s modal loop (kestrel_port.h)
s/askBox(ASKBOX_YES_NO, "REALLY QUIT ?")/kestrel_confirm_quit()/
