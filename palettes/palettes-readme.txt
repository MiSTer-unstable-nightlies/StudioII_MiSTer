Studio II and Visicom Color Palettes

.gbp files provide alternate two- and four-color palettes for Studio II and 
Visicom.

The core uses the standard MiSTer Game Boy GBP format: four RGB888 colors in
lightest-to-darkest order, followed by four reserved zero bytes.

Studio II

Studio II uses the first and last values for white and the last entry for 
black, respectively. The middle values are not used for Studio II. These
palettes apply to CHIP-8 as well.

studio2-default.gbp

White       #FFFFFF
Light gray  #AAAAAA
Dark gray   #555555
Black       #000000

Default Studio II palette.

Visicom

Visicom maps the four GBP entries to its hardware color indices in reverse
order:

GBP 0 -> index 3 -> Blue
GBP 1 -> index 2 -> Yellow
GBP 2 -> index 1 -> Red
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

visicom-boxart-print.gbp

Green   #4B7841
Red     #D5A696
Yellow  #E7CA51
Blue    #99C8C8

Sampled from a screenshot in Visicom box art (photo by Nicole Express).

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