# KESTREL: the chips are kestrel_chip.cpp's (upstream's SoundChipAY, its writes also posted on the BARD queue)
/^static SoundChip\* defaultChipFactory/i\
SoundChip* kestrel_chip_ay(int index, int sampleRate, ChipSetup setup); /* KESTREL: kestrel_chip.cpp */
s/^  return new SoundChipAY(sampleRate, setup);$/  return kestrel_chip_ay(chipIndex, sampleRate, setup); \/* KESTREL *\//
