# get_freq's interpolation reads frequency_table[96] (one past the table) for a note in the top
# semitone: read 0 there, what the klystrack cart's data has after the table (Makefile says more).
s/^\t\tUint16 f2 = frequency_table\[((note >> 8) + 1)\];/\t\tUint16 f2 = (note >> 8) + 1 < FREQ_TAB_SIZE ? frequency_table[((note >> 8) + 1)] : 0; \/* kt_ref *\//
