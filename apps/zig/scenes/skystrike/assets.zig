// --------------------------------------------------------------------------
// The game's files and banks, as tools/skystrike/extract_assets.py cut them
// from the Automation 258 disk (the SKYSTRKE\ folder, LSD-depacked) and from
// the compiled program STRVAP (the banks the STOS compiler linked in).
// --------------------------------------------------------------------------
const DIR = "../../assets/screens/skystrike/";

/// STOS "pack"ed screens ($06071963): banks 5 and 6, the hall of fame, the paper.
pub const SKYPIC1 = @embedFile(DIR ++ "skypic1.pac");
pub const SKYPIC2 = @embedFile(DIR ++ "skypic2.pac");
pub const HIPIC = @embedFile(DIR ++ "hipic.pac");
pub const NEWS = @embedFile(DIR ++ "news.pac");
/// Bank 1, the sprites ($19861987): 123 low-res images and a PALT palette.
pub const SPRITES = @embedFile(DIR ++ "sprites.bnk");
/// Bank 8, the screen objects: 160 bytes a screen type, 8 an object.
pub const SCREENS = @embedFile(DIR ++ "screens.bnk");
/// STOS's 8x8 low-res character set, glyphs $20-$FF.
pub const FONT = @embedFile(DIR ++ "font.bin");
pub const DATA_DAT = @embedFile(DIR ++ "data.dat");
pub const MISSIONS_DAT = @embedFile(DIR ++ "missions.dat");
pub const SCRNDATA_DAT = @embedFile(DIR ++ "scrndata.dat");
pub const SPITFIRE_HSC = @embedFile(DIR ++ "spitfire.hsc");
