#include "Vstudio2_palette.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdio>

static int failures = 0;

static void expect_rgb(Vstudio2_palette& top, uint32_t expected, const char* name) {
    top.eval();
    const uint32_t got = top.rgb & 0xFFFFFFu;
    if (got != expected) {
        std::printf("FAIL %-42s got #%06X expected #%06X\n",
                    name, got, expected);
        failures++;
    }
}

static void write_byte(Vstudio2_palette& top, unsigned addr, uint8_t value) {
    top.ioctl_addr = addr;
    top.ioctl_data = value;
    top.ioctl_wr = 1;
    top.clk_sys = 0;
    top.eval();
    top.clk_sys = 1;
    top.eval();
    top.clk_sys = 0;
    top.eval();
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vstudio2_palette top;
    top.clk_sys = 0;
    top.ioctl_wr = 0;
    top.studio2_download = 0;
    top.studio3_download = 0;
    top.visicom_download = 0;
    top.video_bg = 0;

    const std::array<std::array<uint32_t, 2>, 4> studio2 = {{
        {{0x000000, 0xFFFFFF}}, {{0x000000, 0xFFBF5A}},
        {{0x000000, 0x8FFF63}}, {{0xFFFFFF, 0x000000}}
    }};
    top.machine = 0;
    for (unsigned preset = 0; preset < studio2.size(); preset++) {
        top.studio2_select = preset;
        top.video = 0;
        expect_rgb(top, studio2[preset][0], "Studio II preset background");
        top.video = 4;
        expect_rgb(top, studio2[preset][1], "Studio II preset foreground");
    }

    const std::array<uint8_t, 16> studio2_custom = {
        0x12, 0x34, 0x56, 0xAA, 0xBB, 0xCC, 0x66, 0x77,
        0x88, 0x9A, 0xBC, 0xDE, 0, 0, 0, 0
    };
    top.studio2_select = 4;
    top.studio2_download = 1;
    for (unsigned i = 0; i < 15; i++) write_byte(top, i, studio2_custom[i]);
    top.video = 4;
    expect_rgb(top, 0xFFFFFF, "Incomplete Studio II GBP is not committed");
    write_byte(top, 15, studio2_custom[15]);
    top.studio2_download = 0;
    expect_rgb(top, 0x123456, "Studio II custom foreground");
    top.video = 0;
    expect_rgb(top, 0x9ABCDE, "Studio II custom background");

    const std::array<std::array<uint32_t, 4>, 7> visicom = {{
        {{0x11320C, 0x5A93D5, 0xB9B43D, 0xD14C38}},
        {{0x21391A, 0x678CC6, 0xC4AD39, 0xBC674A}},
        {{0x004000, 0x70D0FF, 0xD0FF70, 0xFF7070}},
        {{0x1F3618, 0x627FB6, 0xB5A443, 0xC74C32}},
        {{0x004000, 0xAFDFE4, 0xB9C42F, 0xEF454A}},
        {{0x1B3511, 0x4D91B5, 0xB9B438, 0xC54A32}},
        {{0x002600, 0x2688F2, 0xAFB72B, 0xD52E18}}
    }};
    top.machine = 3;
    for (unsigned preset = 0; preset < visicom.size(); preset++) {
        top.visicom_select = preset;
        for (unsigned index = 0; index < 4; index++) {
            top.vis_index = index;
            expect_rgb(top, visicom[preset][index], "Visicom preset index");
        }
    }

    const std::array<uint8_t, 16> visicom_custom = {
        0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80,
        0x90, 0xA0, 0xB0, 0xC0, 0, 0, 0, 0
    };
    top.visicom_select = 7;
    top.visicom_download = 1;
    for (unsigned i = 0; i < 15; i++) write_byte(top, i, visicom_custom[i]);
    top.vis_index = 3;
    expect_rgb(top, 0xD14C38, "Incomplete Visicom GBP is not committed");
    write_byte(top, 15, visicom_custom[15]);
    top.visicom_download = 0;
    const std::array<uint32_t, 4> visicom_custom_expected = {
        0xA0B0C0, 0x708090, 0x405060, 0x102030
    };
    for (unsigned index = 0; index < 4; index++) {
        top.vis_index = index;
        expect_rgb(top, visicom_custom_expected[index], "Visicom custom reverse mapping");
    }

    const std::array<uint32_t, 8> studio3_original = {
        0x000000, 0x0000FF, 0x00FF00, 0x00FFFF,
        0xFF0000, 0xFF00FF, 0xFFFF00, 0xFFFFFF
    };
    const std::array<uint32_t, 8> studio3_prototype = {
        0x000000, 0x123C62, 0x126044, 0x2A9DA2,
        0xD95718, 0xB56B73, 0xD6A328, 0xD8D5B5
    };
    const std::array<uint32_t, 8> studio3_warm = {
        0x080706, 0x325FA7, 0x52965B, 0x5BB7B1,
        0xC95A42, 0xB6779F, 0xD7B646, 0xE6DFC8
    };
    const std::array<uint32_t, 8> studio3_cool = {
        0x05080C, 0x3B78C6, 0x3F9C83, 0x54BFC8,
        0xCF596E, 0xA479C2, 0xC9C65A, 0xDCE7F5
    };
    for (unsigned machine : {1u, 2u}) {
        top.machine = machine;
        top.video_bg = 0;
        for (unsigned index = 0; index < 8; index++) {
            top.video = index;
            top.studio3_select = 0;
            expect_rgb(top, studio3_original[index], "Studio III original preset");
            top.studio3_select = 1;
            expect_rgb(top, studio3_prototype[index], "Studio III prototype preset");
            top.studio3_select = 2;
            expect_rgb(top, studio3_warm[index], "Studio III warm preset");
            top.studio3_select = 3;
            expect_rgb(top, studio3_cool[index], "Studio III cool preset");
        }
    }
    top.video = 7;
    top.video_bg = 1;
    top.studio3_select = 0;
    expect_rgb(top, 0x808080, "Studio III original background half");
    top.studio3_select = 1;
    expect_rgb(top, 0x6C6A5A, "Studio III prototype background half");
    top.video_bg = 0;

    std::array<uint8_t, 24> studio3_custom{};
    std::array<uint32_t, 8> studio3_custom_expected{};
    for (unsigned index = 0; index < 8; index++) {
        studio3_custom[index * 3 + 0] = 0x10 + index;
        studio3_custom[index * 3 + 1] = 0x20 + index;
        studio3_custom[index * 3 + 2] = 0x30 + index;
        studio3_custom_expected[index] = ((0x10u + index) << 16) |
                                         ((0x20u + index) << 8) |
                                          (0x30u + index);
    }
    top.studio3_select = 4;
    top.studio3_download = 1;
    for (unsigned i = 0; i < 23; i++) write_byte(top, i, studio3_custom[i]);
    top.video = 0;
    expect_rgb(top, 0x000000, "Incomplete Studio III PAL is not committed");
    write_byte(top, 23, studio3_custom[23]);
    write_byte(top, 24, 0xEE);
    write_byte(top, 31, 0xDD);
    top.studio3_download = 0;
    for (unsigned machine : {1u, 2u}) {
        top.machine = machine;
        for (unsigned index = 0; index < 8; index++) {
            top.video = index;
            expect_rgb(top, studio3_custom_expected[index],
                       "Studio III custom PAL on both variants");
        }
    }

    top.final();
    if (failures) {
        std::printf("Palette checks: FAIL (%d mismatch%s)\n",
                    failures, failures == 1 ? "" : "es");
        return 1;
    }
    std::puts("Palette checks: PASS (0 mismatches)");
    return 0;
}
