/// Studio II, Studio III, and Visicom Color Palettes ///

.gbp files provide alternate two- and four-color palettes for Studio II and 
Visicom. .pal files provide eight-color palettes for Studio III.

.gbp files use the standard MiSTer Game Boy GBP format: four RGB888 colors in
lightest-to-darkest order, followed by four reserved zero bytes.

Additional optional themes are under fun/.

/// Studio II ///

Studio II uses the first value for white and the last entry for black.
The middle values are not used for Studio II. These
palettes apply to CHIP-8 as well.

studio2-default.gbp

White       #FFFFFF
Light gray  #AAAAAA
Dark gray   #555555
Black       #000000

Default Studio II palette.

studio2-amber-terminal.gbp, studio2-green-terminal.gbp, and
studio2-inverted.gbp correspond to the other built-in Studio II presets.


/// Studio III ///

Studio III custom palettes use a headerless .pal file containing eight RGB888
triples in hardware-index order (indices 0 through 7), for 24 bytes total.
Trailing bytes are ignored. The same custom palette applies to the PAL and NTSC
Studio III variants, and loading it does not reset the machine.

tools/studio3-palette/studio3-palette.c creates these files. From the repository root:

    cc -std=c99 -Wall -Wextra -o tools/studio3-palette/studio3-palette tools/studio3-palette/studio3-palette.c
    ./tools/studio3-palette/studio3-palette custom.pal 000000 0000FF 00FF00 00FFFF FF0000 FF00FF FFFF00 FFFFFF

Arguments after the output name are the eight colours at hardware indices 0
through 7. A leading # is accepted. For example, the Original palette is:

    ./tools/studio3-palette/studio3-palette studio3-original.pal 000000 0000FF 00FF00 00FFFF FF0000 FF00FF FFFF00 FFFFFF

The included examples are represented below directly in hardware-index order:

studio3-prototype.pal

0 #000000  1 #123C62  2 #126044  3 #2A9DA2
4 #D95718  5 #B56B73  6 #D6A328  7 #D8D5B5

Prototype Studio III palette. This corresponds to the core's Prototype preset.

studio3-warm.pal

0 #080706  1 #325FA7  2 #52965B  3 #5BB7B1
4 #C95A42  5 #B6779F  6 #D7B646  7 #E6DFC8

Softened phosphors and warm white for ordinary play.

studio3-cool.pal

0 #05080C  1 #3B78C6  2 #3F9C83  3 #54BFC8
4 #CF596E  5 #A479C2  6 #C9C65A  7 #DCE7F5

Cooler blue/cyan emphasis with a pale blue-white.

studio3-pastel.pal

0 #171619  1 #7799C9  2 #86B991  3 #9FD6D1
4 #CB8C89  5 #BA91B8  6 #D6C982  7 #F2EEE1

Low-saturation colours for Doodle, Patterns, and other artwork.

studio3-arcade-neon.pal

0 #06030B  1 #2F4CFF  2 #2EEA74  3 #25E9F2
4 #FF3B58  5 #E75CFF  6 #F6E94A  7 #FFFFFF

Vivid modern colours for homebrew and demonstration use.

studio3-greyscale.pal

0 #000000  1 #1D1D1D  2 #969696  3 #B2B2B2
4 #4C4C4C  5 #6A6A6A  6 #E2E2E2  7 #FFFFFF

Luminance-weighted greys at the normal colour indices.

/// Visicom ///

Visicom maps the four GBP entries to its hardware color indices in reverse
order:

GBP 0 -> index 3 -> Red
GBP 1 -> index 2 -> Yellow
GBP 2 -> index 1 -> Blue
GBP 3 -> index 0 -> Green  (border/background)

Standard MiSTer Game Boy .gbp files may therefore be loaded directly.

visicom-balanced.gbp

Green   #11320C
Red     #D14C38
Yellow  #B9B43D
Blue    #5A93D5

Drawn from all combined sources. MiSTer default.

visicom-boxart-adjusted.gbp

Green   #21391A
Red     #BC674A
Yellow  #C4AD39
Blue    #678CC6

Sampled from Visicom box art (photo by Nicole Express), averaged against
other sources.

fun/visicom-boxart-print.gbp

Green   #4B7841
Red     #D5A696
Yellow  #E7CA51
Blue    #99C8C8

Sampled from a screenshot in Visicom box art (photo by Nicole Express).

visicom-manuals-adjusted.gbp

Green   #1B3511
Red     #C54A32
Yellow  #B9B438
Blue    #4D91B5

Visicom manual print samples adjusted against the combined hardware capture
evidence.

fun/visicom-manuals-print.gbp

Green   #70981C
Red     #C43818
Yellow  #D1C313
Blue    #078C9F

Representative colors sampled from four printed Visicom manual screenshots.

visicom-emma02.gbp

Green   #004000
Red     #FF7070
Yellow  #D0FF70
Blue    #70D0FF

Palette used by Emma 02.

visicom-flip.gbp

Green   #1F3618
Red     #C74C32
Yellow  #B5A443
Blue    #627FB6

Sampled and adjusted from FLiP captures.

visicom-mame.gbp

Green   #004000
Red     #EF454A
Yellow  #B9C42F
Blue    #AFDFE4

Palette used by MAME.

visicom-nicole-express.gbp

Green   #002600
Red     #D52E18
Yellow  #AFB72B
Blue    #2688F2

Sampled and adjusted from Nicole Express captures.
