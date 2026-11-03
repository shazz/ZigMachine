// gen/memmap.vh's localparams for a module of the compositor. memmap.vh has an
// include guard, and a `define is global to a compilation unit, so in a read of
// several modules only the first one to include it would get the constants.
// Every compositor module includes this instead, which drops the guard first.
`undef ZM_MEMMAP_VH
`include "memmap.vh"
