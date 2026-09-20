/*
 * Write a Studio III RGB888 palette from eight hardware-indexed colours.
 * Build from the repository root:
 * cc -std=c99 -Wall -Wextra -o tools/studio3-palette/studio3-palette
 *    tools/studio3-palette/studio3-palette.c
 * 0=black, 1=blue, 2=green, 3=cyan, 4=red, 5=magenta, 6=yellow, 7=white
 */
#include <stdio.h>
#include <string.h>

static int hex_value(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static int parse_rgb(const char *text, unsigned char *rgb)
{
	int i;
	int high;
	int low;

	if (*text == '#') ++text;
	if (strlen(text) != 6) return 0;

	for (i = 0; i < 3; ++i) {
		high = hex_value(text[i * 2]);
		low = hex_value(text[i * 2 + 1]);
		if (high < 0 || low < 0) return 0;
		rgb[i] = (unsigned char)((high << 4) | low);
	}
	return 1;
}

int main(int argc, char **argv)
{
	unsigned char palette[24];
	FILE *output;
	int i;

	if (argc != 10) {
		fprintf(stderr, "usage: %s output.pal color0 color1 color2 color3 color4 color5 color6 color7\n", argv[0]);
		fprintf(stderr, "each colour is RRGGBB or #RRGGBB, in Studio III hardware-index order\n");
		return 2;
	}

	for (i = 0; i < 8; ++i) {
		if (!parse_rgb(argv[i + 2], &palette[i * 3])) {
			fprintf(stderr, "error: color%d must be RRGGBB or #RRGGBB\n", i);
			return 2;
		}
	}

	output = fopen(argv[1], "wb");
	if (!output) {
		perror(argv[1]);
		return 1;
	}
	if (fwrite(palette, 1, sizeof(palette), output) != sizeof(palette)) {
		perror(argv[1]);
		fclose(output);
		return 1;
	}
	if (fclose(output)) {
		perror(argv[1]);
		return 1;
	}
	return 0;
}
