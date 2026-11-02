/* Force-included into every ChipNomad source: the KESTREL port hooks. */
#pragma once
#ifdef __cplusplus
extern "C" {
#endif
void kestrel_throw(const char *message); /* patches/project_io.cpp.sed: a throw stops the cart */
#ifdef __cplusplus
}
#endif
