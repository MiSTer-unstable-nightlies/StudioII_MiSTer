#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int read_component(unsigned color, const char *component, unsigned char *out)
{
    char line[128];
    char *end;
    long value;

    for (;;) {
        printf("Color %u %s (0-255): ", color, component);
        if (!fgets(line, sizeof line, stdin)) {
            fputs("\nInput ended unexpectedly.\n", stderr);
            return 0;
        }

        errno = 0;
        value = strtol(line, &end, 10);
        while (*end == ' ' || *end == '\t') ++end;

        if (errno == 0 && end != line && (*end == '\n' || *end == '\0') &&
            value >= 0 && value <= 255) {
            *out = (unsigned char)value;
            return 1;
        }

        fputs("Please enter a decimal value from 0 through 255.\n", stderr);
    }
}

int main(int argc, char **argv)
{
    unsigned char palette[16] = {0};
    const char *output_name;
    FILE *fp;
    unsigned color;

    if (argc != 2) {
        fprintf(stderr, "Usage: %s output.vcp\n", argv[0]);
        return EXIT_FAILURE;
    }

    output_name = argv[1];

    puts("Visicom Color Palette (.vcp) creator");
    puts("Enter RGB888 values for hardware color indices 0-3.\n");

    for (color = 0; color < 4; ++color) {
        if (!read_component(color, "R", &palette[color * 3 + 0]) ||
            !read_component(color, "G", &palette[color * 3 + 1]) ||
            !read_component(color, "B", &palette[color * 3 + 2])) {
            return EXIT_FAILURE;
        }
        putchar('\n');
    }

    fp = fopen(output_name, "wb");
    if (!fp) {
        fprintf(stderr, "Could not open '%s' for writing: %s\n",
                output_name, strerror(errno));
        return EXIT_FAILURE;
    }

    if (fwrite(palette, 1, sizeof palette, fp) != sizeof palette) {
        fprintf(stderr, "Could not write '%s': %s\n",
                output_name, strerror(errno));
        fclose(fp);
        return EXIT_FAILURE;
    }

    if (fclose(fp) != 0) {
        fprintf(stderr, "Could not finish writing '%s': %s\n",
                output_name, strerror(errno));
        return EXIT_FAILURE;
    }

    printf("Wrote %s (16 bytes).\n", output_name);
    return EXIT_SUCCESS;
}
