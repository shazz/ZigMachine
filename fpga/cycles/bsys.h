/* The system image's side of the board's split (decisions.md 2026-10-15, cycles/bsys.c): the
 * cart is the lean image at ZM_CART_IMG_AT, called through its header. Without ZM_SPLIT_SYS
 * (the monolithic image) the cart is linked in and called by name. bmain.c uses the macros. */
#ifndef ZM_BSYS_H
#define ZM_BSYS_H

#include <stdint.h>

#include "host.h"

#ifdef ZM_SPLIT_SYS
/* Find the cart image, refuse one built for another table (console + TRAP_CART_ABI) or none
 * (TRAP_NO_CART), zero its .bss, bind it to zm_sys_table. Before bdisk_boot: the disk sits
 * after the cart's .bss. */
void bsys_link(void);
#define HOST_CART_FRAME(e, dt) zm_cart->frame(HOST_CART(e), dt)
#define HOST_CART_PLANE_ON(e, p) zm_cart->plane_enabled(HOST_CART(e), p)
#define HOST_CART_TAG (zm_cart->tag)
#else
#define HOST_CART_FRAME(e, dt) w2c_cart_frame(HOST_CART(e), dt)
#define HOST_CART_PLANE_ON(e, p) w2c_cart_isPlaneEnabled(HOST_CART(e), p)
#define HOST_CART_TAG ZM_CART
#endif

#endif
