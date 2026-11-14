/* Force-included into every ChipNomad source: the KESTREL port hooks. */
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void kestrel_throw(const char *message); /* patches/project_io.cpp.sed: a throw stops the cart */
int kestrel_c_mounted(void); /* C: is mounted (kestrel_sdl2 opt/kestrel_wasi_c.c): patches/corelib_file.cpp.sed lists "C" at "/" */
#ifdef __cplusplus
}
#endif
