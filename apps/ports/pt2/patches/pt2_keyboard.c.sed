# KESTREL: Esc on the main screen and Alt+Q confirm with a second press, not askBox()'s modal loop (kestrel_port.h)
s/askBox(ASKBOX_YES_NO, "REALLY QUIT ?")/kestrel_confirm_quit()/
