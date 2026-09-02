// ---------------------------------------------------------------------------
// Headless Verilator harness for the RCA Studio II MiSTer core.
//
// No SDL / ImGui / OpenGL: this builds and runs anywhere, which makes it
// usable for scripted regression testing. It can
//   * load a BIOS and a cartridge over the simulated HPS ioctl bus
//   * run for a given number of video frames
//   * write a PNG / PPM / ASCII screenshot at chosen frames
//   * dump CPU + video + memory state at chosen frames
//   * inject keypad presses at chosen frames
//
// Build:  make headless          Run: ./obj_dir_headless/Vtop --help
// ---------------------------------------------------------------------------

#include <verilated.h>
#include "Vtop.h"
#include "Vtop___024root.h"

#include <zlib.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <set>
#include <map>

// ---------------------------------------------------------------------------
// Convenience accessors into the verilated design.
// --public-flat-rw exposes every internal signal on the root scope.
// ---------------------------------------------------------------------------
#define RS(sig)   (top->rootp->top__DOT__rcastudio__DOT__##sig)
#define CPU(sig)  (top->rootp->top__DOT__rcastudio__DOT__cdp1802__DOT__##sig)
#define PIX(sig)  (top->rootp->top__DOT__rcastudio__DOT__pixie_video__DOT__cdp1861__DOT__##sig)
#define ROM0      (top->rootp->top__DOT__rcastudio__DOT__rom0__DOT__mem)
#define ROM1      (top->rootp->top__DOT__rcastudio__DOT__rom1__DOT__mem)
#define ROM2      (top->rootp->top__DOT__rcastudio__DOT__rom2__DOT__mem)
#define ROM3      (top->rootp->top__DOT__rcastudio__DOT__rom3__DOT__mem)
#define ROM4      (top->rootp->top__DOT__rcastudio__DOT__rom4__DOT__mem)
#define SRAM      (top->rootp->top__DOT__rcastudio__DOT__sram__DOT__mem)    // the 512 bytes of RAM, $0800-$09FF
#define COLRAM    (top->rootp->top__DOT__rcastudio__DOT__colour_ram)         // 64 CDP1864 colour cells

static Vtop* top = nullptr;
static vluint64_t main_time = 0;
double sc_time_stamp() { return (double)main_time; }

static uint8_t rom_byte(int slot, int addr) {
    switch (slot) {
        case 0: return ROM0[addr];
        case 1: return ROM1[addr];
        case 2: return ROM2[addr];
        case 3: return ROM3[addr];
        default: return ROM4[addr];
    }
}

static void set_rom_byte(int slot, int addr, uint8_t data) {
    switch (slot) {
        case 0: ROM0[addr] = data; break;
        case 1: ROM1[addr] = data; break;
        case 2: ROM2[addr] = data; break;
        case 3: ROM3[addr] = data; break;
        default: ROM4[addr] = data; break;
    }
}

static std::vector<uint8_t> read_binary(const std::string& path) {
    FILE* f = fopen(path.c_str(), "rb");
    if (!f) { fprintf(stderr, "error: cannot open %s\n", path.c_str()); exit(2); }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::vector<uint8_t> data((size_t)n);
    if (n > 0 && fread(data.data(), 1, (size_t)n, f) != (size_t)n) {
        fprintf(stderr, "error: short read on %s\n", path.c_str()); exit(2);
    }
    fclose(f);
    return data;
}

// Apply one cartridge image to an expected ROM image and return its final
// $08-$0F page-ownership mask. This mirrors the RTL loader closely enough to
// check sequential downloads without treating stale BRAM bytes as visible ROM.
static uint8_t apply_cart_image(std::vector<uint8_t>& rom, const std::string& path, int machine) {
    const std::vector<uint8_t> data = read_binary(path);
    const bool st2 = data.size() >= 4 && data[0] == 'R' && data[1] == 'C' &&
                     data[2] == 'A' && data[3] == '2';
    uint8_t pages = 0;

    for (size_t i = 0; i < data.size(); i++) {
        size_t addr;
        bool write = false;

        if (st2) {
            // The four magic bytes reach the raw base before st2_mode latches.
            // They are intentionally not page ownership; valid payload replaces
            // them when page $08 is actually supplied.
            if (i < 4) {
                addr = ((machine == 3 ? 0x800u : 0x400u) + i) & 0xfffu;
                write = true;
            } else if (i >= 0x100) {
                size_t block = (i >> 8) - 1;
                if (block < 64 && 0x40 + block < data.size()) {
                    uint8_t page = data[0x40 + block];
                    bool valid = (page & 0xf0) == 0 &&
                        (machine == 3
                            ? (page & 0x08) != 0
                            : page > 3 && page != 8 && page != 9 &&
                              !((machine == 1 || machine == 2) && page == 0x0b));
                    if (valid) {
                        addr = ((size_t)(page & 0x0f) << 8) | (i & 0xff);
                        write = true;
                    }
                }
            }
        } else if (machine != 3 || i < 0x800) {
            addr = ((machine == 3 ? 0x800u : 0x400u) + i) & 0xfffu;
            write = true;
        }

        if (!write) continue;
        rom[addr] = data[i];
        bool claim = (addr & 0x800) && (machine == 3 || (addr & 0x600));
        bool format_known = st2 ? i >= 0x100 : i >= 3;
        if (claim && format_known) pages |= (uint8_t)(1u << ((addr >> 8) & 7));
    }
    return pages;
}

// Put the CPU bus on one address for a clock so the synchronous ROM and its
// registered decode select are observed together, exactly as the CPU sees them.
static uint8_t read_cpu_bus(uint16_t addr) {
    top->clk_48 = 0;
    CPU(state) = 2;       // EXECUTE
    CPU(IR) = 0x01;       // LDN R1: read R1 without changing it
    CPU(R)[1] = addr;
    top->eval();
    top->clk_48 = 1;
    top->eval();
    uint8_t data = (uint8_t)RS(ram_q);
    top->clk_48 = 0;
    top->eval();
    return data;
}

// ---------------------------------------------------------------------------
// PNG writer (zlib, 8-bit RGB, no external image library)
// ---------------------------------------------------------------------------
static void put_be32(std::vector<uint8_t>& v, uint32_t x) {
    v.push_back((x >> 24) & 0xff); v.push_back((x >> 16) & 0xff);
    v.push_back((x >> 8) & 0xff);  v.push_back(x & 0xff);
}

static void png_chunk(FILE* f, const char* type, const uint8_t* data, size_t len) {
    std::vector<uint8_t> hdr;
    put_be32(hdr, (uint32_t)len);
    fwrite(hdr.data(), 1, hdr.size(), f);
    fwrite(type, 1, 4, f);
    if (len) fwrite(data, 1, len, f);
    uLong crc = crc32(0L, Z_NULL, 0);
    crc = crc32(crc, (const Bytef*)type, 4);
    if (len) crc = crc32(crc, (const Bytef*)data, (uInt)len);
    std::vector<uint8_t> tail;
    put_be32(tail, (uint32_t)crc);
    fwrite(tail.data(), 1, tail.size(), f);
}

// rgb is w*h*3 bytes
static bool write_png(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { fprintf(stderr, "error: cannot write %s\n", path.c_str()); return false; }

    static const uint8_t sig[8] = { 137, 'P', 'N', 'G', '\r', '\n', 26, '\n' };
    fwrite(sig, 1, 8, f);

    std::vector<uint8_t> ihdr;
    put_be32(ihdr, (uint32_t)w);
    put_be32(ihdr, (uint32_t)h);
    ihdr.push_back(8);              // bit depth
    ihdr.push_back(2);              // colour type: truecolour RGB
    ihdr.push_back(0);              // deflate
    ihdr.push_back(0);              // adaptive filtering
    ihdr.push_back(0);              // no interlace
    png_chunk(f, "IHDR", ihdr.data(), ihdr.size());

    // Raw scanlines, each prefixed with filter type 0.
    std::vector<uint8_t> raw;
    raw.reserve((size_t)h * (1 + (size_t)w * 3));
    for (int y = 0; y < h; y++) {
        raw.push_back(0);
        raw.insert(raw.end(), rgb.begin() + (size_t)y * w * 3,
                              rgb.begin() + (size_t)(y + 1) * w * 3);
    }

    uLongf clen = compressBound((uLong)raw.size());
    std::vector<uint8_t> comp(clen);
    if (compress2(comp.data(), &clen, raw.data(), (uLong)raw.size(), 9) != Z_OK) {
        fprintf(stderr, "error: zlib compress failed\n"); fclose(f); return false;
    }
    png_chunk(f, "IDAT", comp.data(), clen);
    png_chunk(f, "IEND", nullptr, 0);
    fclose(f);
    return true;
}

static bool write_ppm(const std::string& path, int w, int h, const std::vector<uint8_t>& rgb) {
    FILE* f = fopen(path.c_str(), "wb");
    if (!f) { fprintf(stderr, "error: cannot write %s\n", path.c_str()); return false; }
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(rgb.data(), 1, rgb.size(), f);
    fclose(f);
    return true;
}

// ---------------------------------------------------------------------------
// Frame capture
// ---------------------------------------------------------------------------
static const int MAX_W = 2048;
static const int MAX_H = 1024;

// {R,G,B} -> one character. Black is a space and white is '#', exactly as the
// pre-colour harness printed them, so every Studio II capture and the whole §9
// comparison is byte-identical. The six chromatic values only ever
// appear on a CDP1864 machine, and get their initials.
static inline char ascii_for(uint8_t rgb) {
    switch (rgb & 7) {
        case 0: return ' ';   // black
        case 1: return 'B';   // blue
        case 2: return 'G';   // green
        case 3: return 'C';   // cyan
        case 4: return 'R';   // red
        case 5: return 'M';   // magenta
        case 6: return 'Y';   // yellow
        default: return '#';  // white
    }
}

struct FrameGrabber {
    std::vector<uint8_t> pix;   // MAX_W * MAX_H, 0 or 1
    int col = 0, line = 0;
    int width = 0, height = 0;  // active extents of the frame being built
    int last_width = 0, last_height = 0;
    bool prev_vs = false, prev_hs = false;
    long frame = 0;
    bool complete = false;      // a full frame has been captured at least once

    FrameGrabber() : pix((size_t)MAX_W * MAX_H, 0) {}

    // Returns true on the clock where a frame boundary was crossed.
    // `rgb` is {R,G,B}, one bit per channel, matching the core's video output.
    // The Studio II is monochrome so only 0 and 7 ever occur, which is what
    // keeps the ASCII output byte-identical to the pre-colour harness.
    bool clock(bool vs, bool hs, bool de, uint8_t rgb) {
        bool boundary = false;

        if (vs && !prev_vs) {
            last_width = width; last_height = height;
            if (last_width > 0 && last_height > 0) complete = true;
            frame++;
            boundary = true;
        }

        if (hs && !prev_hs) {
            if (col > 0) line++;
            col = 0;
        }

        if (boundary) { line = 0; col = 0; width = 0; height = 0; }

        if (de && line < MAX_H && col < MAX_W) {
            pix[(size_t)line * MAX_W + col] = rgb & 7;
            col++;
            if (col > width) width = col;
            if (line + 1 > height) height = line + 1;
        }

        prev_vs = vs; prev_hs = hs;
        return boundary;
    }

    // Snapshot of the frame that just finished, as RGB.
    void to_rgb(std::vector<uint8_t>& out, int& w, int& h, int scale) const {
        w = last_width * scale;
        h = last_height * scale;
        out.assign((size_t)w * h * 3, 0);
        for (int y = 0; y < last_height; y++) {
            for (int x = 0; x < last_width; x++) {
                uint8_t c = pix[(size_t)y * MAX_W + x];
                uint8_t r = (c & 4) ? 0xFF : 0x00;
                uint8_t g = (c & 2) ? 0xFF : 0x00;
                uint8_t b = (c & 1) ? 0xFF : 0x00;
                for (int sy = 0; sy < scale; sy++) {
                    for (int sx = 0; sx < scale; sx++) {
                        size_t o = (((size_t)y * scale + sy) * w + ((size_t)x * scale + sx)) * 3;
                        out[o] = r; out[o + 1] = g; out[o + 2] = b;
                    }
                }
            }
        }
    }

    void to_ascii(FILE* f) const {
        fprintf(f, "    +");
        for (int x = 0; x < last_width; x++) fputc('-', f);
        fprintf(f, "+\n");
        for (int y = 0; y < last_height; y++) {
            fprintf(f, "%3d |", y);
            for (int x = 0; x < last_width; x++)
                fputc(ascii_for(pix[(size_t)y * MAX_W + x]), f);
            fprintf(f, "|\n");
        }
        fprintf(f, "    +");
        for (int x = 0; x < last_width; x++) fputc('-', f);
        fprintf(f, "+\n");
    }

    uint32_t hash() const {
        uint32_t h = 2166136261u;   // FNV-1a
        for (int y = 0; y < last_height; y++)
            for (int x = 0; x < last_width; x++)
                h = (h ^ pix[(size_t)y * MAX_W + x]) * 16777619u;
        return h;
    }

    bool blank() const {
        for (int y = 0; y < last_height; y++)
            for (int x = 0; x < last_width; x++)
                if (pix[(size_t)y * MAX_W + x]) return false;
        return true;
    }
};

// ---------------------------------------------------------------------------
// ioctl download driver (stands in for the HPS)
// ---------------------------------------------------------------------------
struct Download {
    std::string path;
    int index;
};

struct IoctlDriver {
    std::vector<Download> queue;
    size_t qpos = 0;
    std::vector<uint8_t> data;
    size_t pos = 0;
    int gap = 0;
    bool active = false;
    bool finished = false;

    void add(const std::string& path, int index) { queue.push_back({ path, index }); }

    bool load_next() {
        while (qpos < queue.size()) {
            const Download& d = queue[qpos++];
            FILE* f = fopen(d.path.c_str(), "rb");
            if (!f) { fprintf(stderr, "error: cannot open %s\n", d.path.c_str()); exit(2); }
            fseek(f, 0, SEEK_END);
            long n = ftell(f);
            fseek(f, 0, SEEK_SET);
            data.resize((size_t)n);
            if (n > 0 && fread(data.data(), 1, (size_t)n, f) != (size_t)n) {
                fprintf(stderr, "error: short read on %s\n", d.path.c_str()); exit(2);
            }
            fclose(f);
            pos = 0;
            active = true;
            top->ioctl_index = (uint16_t)d.index;
            fprintf(stderr, "[ioctl] %s -> index %d (%ld bytes)\n", d.path.c_str(), d.index, n);
            return true;
        }
        finished = true;
        return false;
    }

    // Called immediately before each rising-edge eval.
    void tick() {
        if (!active) {
            top->ioctl_download = 0;
            top->ioctl_wr = 0;
            if (gap > 0) { gap--; return; }
            if (!finished) load_next();
            return;
        }
        if (pos < data.size()) {
            top->ioctl_download = 1;
            top->ioctl_wr = 1;
            top->ioctl_addr = (uint32_t)pos;
            top->ioctl_dout = data[pos];
            pos++;
        } else {
            top->ioctl_download = 0;
            top->ioctl_wr = 0;
            active = false;
            gap = 256;   // let reset settle between downloads
        }
    }
};

// ---------------------------------------------------------------------------
// Keypad injection
// ---------------------------------------------------------------------------
// PS/2 set-2 scancodes, matching the table in rtl/rcastudioii.sv.
static const uint8_t PS2_A[10] = { 0x22,0x16,0x1E,0x26,0x15,0x1D,0x24,0x1C,0x1B,0x23 };   // keypad A, 3x4 layout: X=0, 123 / QWE / ASD
static const uint8_t PS2_B[10] = { 0x41,0x3D,0x3E,0x46,0x3C,0x43,0x44,0x3B,0x42,0x4B };   // keypad B, 3x4 layout: ,=0, 789 / UIO / JKL

struct KeyEvent {
    long frame;
    int  hold;      // frames to hold
    uint8_t code;
    bool pressed;   // filled in during scheduling
};

// ---------------------------------------------------------------------------
// State dump
// ---------------------------------------------------------------------------
static const char* state_name(int s) {
    switch (s) {
        case 0: return "RESET";  case 1: return "FETCH";     case 2: return "EXECUTE";
        case 3: return "EXECUTE2"; case 4: return "BRANCH2"; case 5: return "BRANCH3";
        case 6: return "SKIP";   case 7: return "DMA_IN";    case 8: return "DMA_OUT";
        case 9: return "INTERRUPT"; default: return "?";
    }
}
static const char* sc_name(int s) {
    switch (s) {
        case 0: return "S0 fetch"; case 1: return "S1 execute";
        case 2: return "S2 dma";   case 3: return "S3 interrupt"; default: return "?";
    }
}

static void dump_state(FILE* f, long frame, const FrameGrabber& fg, bool with_vram) {
    fprintf(f, "===== frame %ld  (sim time %llu) =====\n", frame,
            (unsigned long long)main_time);

    fprintf(f, "-- CDP1802 --\n");
    fprintf(f, "  state   %-10s (state_n %s)\n", state_name(CPU(state)), state_name(CPU(state_n)));
    fprintf(f, "  SC      %d (%s)   IE %d   Q %d\n", CPU(SC), sc_name(CPU(SC)), CPU(IE), CPU(Q));
    fprintf(f, "  I:N     %X%X       D %02X  DF %d  T %02X  B %02X\n",
            CPU(I), CPU(N), CPU(D), CPU(DF), CPU(T), CPU(B));
    fprintf(f, "  P %X  X %X   PC=R[%X]=%04X\n", CPU(P), CPU(X), CPU(P), CPU(R)[CPU(P)]);
    fprintf(f, "  EF %X (EF4 %d EF3 %d EF2 %d EF1 %d)  INT_N %d  DMAO_req %d\n",
            CPU(EF), (CPU(EF) >> 3) & 1, (CPU(EF) >> 2) & 1,
            (CPU(EF) >> 1) & 1, CPU(EF) & 1, CPU(INT_N), CPU(dma_out_req));
    fprintf(f, "  bus     a=%04X q=%02X d=%02X rd=%d wr=%d\n",
            CPU(ram_a), CPU(ram_q), CPU(ram_d), CPU(ram_rd), CPU(ram_wr));
    fprintf(f, "  io      n=%d inp=%d out=%d   unsupported=%d\n",
            CPU(io_n), CPU(io_inp), CPU(io_out), CPU(unsupported));
    for (int i = 0; i < 16; i++) {
        if (i % 8 == 0) fprintf(f, "  R%X-R%X  ", i, i + 7);
        fprintf(f, "%04X ", CPU(R)[i]);
        if (i % 8 == 7) fprintf(f, "\n");
    }

    fprintf(f, "-- Cartridge mapping --\n");
    {
        static const char* pn[] = {"NONE","CROSS","SPACEWAR","FREEWAY","BOWLING","BASEBALL","HOMEBREW","GUNFIGHTER","8WAY","DOODLE","HB2P","RACE","TENNIS","CHIP8","CLIMB","EXPLORER"};
        int pr = top->rootp->top__DOT__rcastudio__DOT__profile;
        fprintf(f, "  cart CRC16 %04X  ->  profile %d (%s)\n",
                top->rootp->top__DOT__rcastudio__DOT__cart_crc, pr,
                (pr >= 0 && pr < (int)(sizeof(pn) / sizeof(pn[0]))) ? pn[pr] : "?");
    }
    fprintf(f, "-- Pixie / video --\n");
    fprintf(f, "  display_enabled %d  dma_cnt %d  vcount %d  hcount %d\n",
            PIX(display_enabled), PIX(dma_cnt), PIX(vcount), PIX(hcount));
    fprintf(f, "  INT %d  DMAO %d  EFx %d   HS %d VS %d HB %d VB %d DE %d\n",
            RS(INT), RS(DMAO), RS(EFx),
            top->VGA_HS, top->VGA_VS, top->VGA_HB, top->VGA_VB, top->VGA_DE);
    fprintf(f, "  frame %dx%d  hash %08X  %s\n",
            fg.last_width, fg.last_height, fg.hash(), fg.blank() ? "BLANK" : "has content");

    fprintf(f, "-- Input --\n");
    fprintf(f, "  keylatch %X  playerA %03X  playerB %03X\n",
            RS(keylatch), RS(playerA), RS(playerB));

    // The 64 CDP1864 colour cells, laid out as they appear on screen: 8 columns
    // across by 8 row-groups down. Printed in the 1864's own pin order, matching
    // tools/refemu's --colour, so the two can be diffed without a permutation in
    // the way.
    if (with_vram && (RS(machine) == 1)) {
        fprintf(f, "-- CDP1864 colour RAM (row group x column), 1864 pin order --\n");
        for (int g = 0; g < 8; g++) {
            fprintf(f, "  g%d:", g);
            for (int c = 0; c < 8; c++) fprintf(f, " %d", (int)COLRAM[g * 8 + c]);
            fprintf(f, "\n");
        }
    }
    if (with_vram) {
        fprintf(f, "-- Display RAM $0900-$09FF --\n");
        for (int r = 0; r < 256; r += 16) {
            fprintf(f, "  %04X: ", 0x900 + r);
            for (int c = 0; c < 16; c++) fprintf(f, "%02X ", SRAM[0x100 + r + c]);
            fprintf(f, "\n");
        }
        fprintf(f, "-- System RAM $0800-$08FF --\n");
        for (int r = 0; r < 256; r += 16) {
            fprintf(f, "  %04X: ", 0x800 + r);
            for (int c = 0; c < 16; c++) fprintf(f, "%02X ", SRAM[r + c]);
            fprintf(f, "\n");
        }
    }
    fprintf(f, "\n");
}

// ---------------------------------------------------------------------------
static void usage(const char* argv0) {
    printf(
"Headless Verilator sim for the RCA Studio II MiSTer core.\n"
"\n"
"Usage: %s [options]\n"
"\n"
"  Software\n"
"    --bios FILE          BIOS image, ioctl index 0   (default ../rom/studio2.rom)\n"
"    --cart FILE          cartridge image, ioctl index 1 (raw: Studio $0400, Visicom $0800)\n"
"    --chip8-fw FILE      Marcel's 768-byte companion, ioctl index $0103\n"
"    --manual-chip8-fw FILE  same image through the F4 OSD path, ioctl index 4\n"
"    --ch8 FILE           CHIP-8 program, ioctl index 3\n"
"    --loader-check       verify all five ROM slots and CHIP-8 address mapping\n"
"\n"
"  Run length\n"
"    --frames N           stop after N video frames (default 300)\n"
"    --max-cycles N       hard cycle cap (default 400000000)\n"
"\n"
"  Screenshots\n"
"    --shot N[,N...]      capture at these frame numbers (repeatable)\n"
"    --shot-every N       capture every N frames\n"
"    --shot-last          capture the final frame\n"
"    --outdir DIR         output directory (default ./out)\n"
"    --prefix NAME        filename prefix (default from cart/bios name)\n"
"    --scale N            pixel scale for PNG output (default 4)\n"
"    --ppm                also write .ppm alongside the .png\n"
"    --ascii              also print the frame as ASCII art\n"
"\n"
"  State dumps\n"
"    --dump N[,N...]      dump CPU/video state at these frames (repeatable)\n"
"    --dump-every N       dump every N frames\n"
"    --vram               include $0800-$09FF hexdumps in state dumps\n"
"    --dump-file FILE     write dumps here instead of stdout\n"
"\n"
"  Machine\n"
"    --machine NAME       studio2 (default), mpt02/studio3 (PAL CDP1864),\n"
"                         studio3ntsc (CDP1861 + 1862 colour + 1863 tone), or\n"
"                         visicom (Toshiba COM-100). The Studio IIIs are colour\n"
"                         machines: PAL is a 312-line frame with 192 display\n"
"                         lines and colour RAM at $B00. The Visicom is NTSC like\n"
"                         the Studio II but gets its colour from a second bit\n"
"                         plane $200 above the first, so it has no colour RAM.\n"
"                         Each needs its own --bios.\n"
"\n"
"  Input\n"
"    --joy-map N          OSD \"Joystick\" profile, and switch \"Mapping\" to Manual:\n"
"                         0 none/keypad-only, 1 cross, 2 spacewar, 3 freeway,\n"
"                         4 bowling, 5 baseball, 6 homebrew, 7 gunfighter,\n"
"                         8 8-way, 9 doodle, 10 2P homebrew, 11 Race,\n"
"                         12 Tennis, 13 CHIP-8, 14 Climber/Outbreak,\n"
"                         15 Space Explorer. Omit for auto-detection.\n"
"    --joy MASK@F[:H]     drive joystick 0 with MASK (bit0 right, 1 left, 2 down,\n"
"                         3 up, 4 fire, 5 extra, 6 start, 17:8 A0..A9,\n"
"                         27:18 B0..B9) at frame F for H frames.\n"
"    --joy2 MASK@F[:H]    same, joystick 1\n"
"    --players N          OSD Players setting: 0 auto, 1 one player, 2 two\n"
"    --beeper-tune NAME   Studio II tuning: medium (default), high, higher,\n"
"                         highest, low, lower, or lowest\n"
"    --ntsc-tone-pitch P  Studio III NTSC pitch: original (default) or pal\n"
"    --swap FILE@FRAME    download another cartridge at frame F, like an OSD\n"
"                         load while the machine is running\n"
"    --press KEY@F[:H]    press KEY at frame F, hold H frames (default 4).\n"
"                         KEY is a0..a9 (player A) or b0..b9 (player B),\n"
"                         or a raw hex PS/2 scancode like 0x16.\n"
"\n"
"  Tracing\n"
"    --trace-cpu N        log the first N instructions executed (PC, opcode, regs)\n"
"    --trace-from F       only start the CPU trace at frame F\n"
"    --trace-vwr          log CPU writes to the display page's top/bottom two rows\n"
"                         with the writing PC (VWR_ALL=1 env: the whole page)\n"
"\n"
"  Misc\n"
"    --trace-q            log every Q edge with frame, tick and beeper state\n"
"    --frame-log          print one line per frame (frame, size, hash)\n"
"    --quiet              suppress per-frame progress\n"
"    --help\n", argv0);
}

static void parse_list(const char* s, std::set<long>& out) {
    const char* p = s;
    while (*p) {
        char* end;
        long v = strtol(p, &end, 10);
        if (end == p) break;
        out.insert(v);
        p = end;
        while (*p == ',' || *p == ' ') p++;
    }
}

int main(int argc, char** argv) {
    std::string bios = "../rom/studio2.rom";
    std::string cart;
    std::string chip8_fw;
    int chip8_fw_index = 0x0103;
    std::string ch8;
    std::string outdir = "out";
    std::string prefix;
    std::string dumpfile;
    long frames = 300;
    long max_cycles = 400000000L;
    int  scale = 4;
    int  shot_every = 0, dump_every = 0;
    bool want_ppm = false, want_ascii = false, want_vram = false;
    bool loader_check = false;
    bool shot_last = false, frame_log = false, quiet = false;
    long trace_cpu = 0, trace_from = 0;
    bool trace_r0 = false;
    bool trace_vwr = false;
    unsigned long long trace_cyc_from = 0, trace_cyc_to = 0;
    bool trace_q = false;
    uint32_t joy_mask = 0; long joy_from = -1, joy_to = -1;
    uint32_t joy2_mask = 0; long joy2_from = -1, joy2_to = -1;
    std::string swap_file; long swap_frame = -1; bool swap_done = false;
    // Mid-run firmware load and machine switch, to replay the OSD flow of
    // switching machines on a running core (docs/handoff.md, 2026-08-19).
    std::string swap0_file; long swap0_frame = -1; bool swap0_done = false;
    uint8_t  machine_at = 0; long machine_at_frame = -1; bool machine_at_done = false;
    uint8_t  joy_override = 0;   // applied once top exists
    bool     joy_manual   = false;
    uint8_t  machine = 0;   // 0 studio2, 1 studio3 PAL, 2 studio3 NTSC, 3 Visicom
    uint8_t  beeper_tune = 0; // 0 medium/reference; remaining values follow the OSD
    bool     ntsc_pal_pitch = false;
    bool     ce_div4 = false;  // run the hardware's /4 pixel enable (4x slower)
    uint32_t ram_junk_seed = 0;  // pre-fill RAM with junk (0 = boot with zeroed RAM)
    long     press_phase = 0;    // delay key events N clks past their frame boundary
    uint8_t  players_mode = 0;
    // Q gates the Studio II's beeper; track its edges so the core can be compared
    // against the reference emulator's Q even though AUDIO_L/R are still tied off.
    bool q_prev = false; long q_edges = 0, q_on_frames = 0; long q_last_chg = 0;
    bool a_prev = false; long a_edges = 0;   // beeper output transitions
    std::set<long> shots, dumps;
    std::vector<KeyEvent> keys;

    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&](const char* what) -> const char* {
            if (i + 1 >= argc) { fprintf(stderr, "error: %s needs an argument\n", what); exit(1); }
            return argv[++i];
        };
        if      (a == "--help" || a == "-h") { usage(argv[0]); return 0; }
        else if (a == "--bios")       bios = next("--bios");
        else if (a == "--cart")       cart = next("--cart");
        else if (a == "--chip8-fw") {
            chip8_fw = next("--chip8-fw");
            chip8_fw_index = 0x0103;
        }
        else if (a == "--manual-chip8-fw") {
            chip8_fw = next("--manual-chip8-fw");
            chip8_fw_index = 4;
        }
        else if (a == "--ch8")        ch8 = next("--ch8");
        else if (a == "--loader-check") loader_check = true;
        else if (a == "--outdir")     outdir = next("--outdir");
        else if (a == "--prefix")     prefix = next("--prefix");
        else if (a == "--dump-file")  dumpfile = next("--dump-file");
        else if (a == "--frames")     frames = atol(next("--frames"));
        else if (a == "--max-cycles") max_cycles = atol(next("--max-cycles"));
        else if (a == "--scale")      scale = atoi(next("--scale"));
        else if (a == "--shot")       parse_list(next("--shot"), shots);
        else if (a == "--dump")       parse_list(next("--dump"), dumps);
        else if (a == "--trace-cpu")  trace_cpu = atol(next("--trace-cpu"));
        else if (a == "--trace-r0")   trace_r0 = true;
        else if (a == "--trace-vwr")  trace_vwr = true;
        else if (a == "--trace-cyc") {
            std::string t = next("--trace-cyc");   // FROM:TO in sim time
            size_t co = t.find(':');
            trace_cyc_from = strtoull(t.c_str(), nullptr, 0);
            trace_cyc_to = (co != std::string::npos) ? strtoull(t.c_str()+co+1, nullptr, 0) : trace_cyc_from + 4000;
        }
        else if (a == "--trace-from") trace_from = atol(next("--trace-from"));
        else if (a == "--shot-every") shot_every = atoi(next("--shot-every"));
        else if (a == "--dump-every") dump_every = atoi(next("--dump-every"));
        else if (a == "--shot-last")  shot_last = true;
        else if (a == "--ppm")        want_ppm = true;
        else if (a == "--ascii")      want_ascii = true;
        else if (a == "--vram")       want_vram = true;
        else if (a == "--joy") {
            std::string t = next("--joy");
            size_t at = t.find('@'); if (at == std::string::npos) { fprintf(stderr,"error: --joy needs MASK@FRAME\n"); exit(1); }
            int hold = 4; std::string rest = t.substr(at+1);
            size_t co = rest.find(':');
            if (co != std::string::npos) { hold = atoi(rest.c_str()+co+1); rest = rest.substr(0,co); }
            joy_mask = (uint32_t)strtoul(t.substr(0,at).c_str(), nullptr, 0);
            joy_from = atol(rest.c_str()); joy_to = joy_from + hold;
        }
        else if (a == "--joy2") {
            std::string t = next("--joy2");
            size_t at = t.find('@'); if (at == std::string::npos) { fprintf(stderr,"error: --joy2 needs MASK@FRAME\n"); exit(1); }
            int hold = 4; std::string rest = t.substr(at+1);
            size_t co = rest.find(':');
            if (co != std::string::npos) { hold = atoi(rest.c_str()+co+1); rest = rest.substr(0,co); }
            joy2_mask = (uint32_t)strtoul(t.substr(0,at).c_str(), nullptr, 0);
            joy2_from = atol(rest.c_str()); joy2_to = joy2_from + hold;
        }
        else if (a == "--players")    players_mode = (uint8_t)atoi(next("--players"));
        else if (a == "--swap0") {
            std::string t = next("--swap0");
            size_t at = t.rfind('@');
            if (at == std::string::npos) { fprintf(stderr, "error: --swap0 needs FILE@FRAME\n"); exit(1); }
            swap0_file = t.substr(0, at);
            swap0_frame = atol(t.c_str() + at + 1);
        }
        else if (a == "--machine-at") {
            std::string t = next("--machine-at");
            size_t at = t.rfind('@');
            if (at == std::string::npos) { fprintf(stderr, "error: --machine-at needs NAME@FRAME\n"); exit(1); }
            std::string m = t.substr(0, at);
            machine_at_frame = atol(t.c_str() + at + 1);
            if      (m == "studio2") machine_at = 0;
            else if (m == "mpt02" || m == "studio3" || m == "studio3pal") machine_at = 1;
            else if (m == "studio3ntsc" || m == "ntsc") machine_at = 2;
            else if (m == "visicom" || m == "com100") machine_at = 3;
            else { fprintf(stderr, "error: unknown machine %s\n", m.c_str()); exit(1); }
        }
        else if (a == "--swap") {
            std::string t = next("--swap");
            size_t at = t.rfind('@');
            if (at == std::string::npos) { fprintf(stderr,"error: --swap needs FILE@FRAME\n"); exit(1); }
            swap_file = t.substr(0, at);
            swap_frame = atol(t.c_str() + at + 1);
        }
        else if (a == "--ce4")     ce_div4 = true;
        else if (a == "--ram-junk") ram_junk_seed = (uint32_t)strtoul(next("--ram-junk"), nullptr, 0);
        else if (a == "--press-phase") press_phase = atol(next("--press-phase"));
        else if (a == "--machine") {
            std::string m = next("--machine");
            if      (m == "studio2") machine = 0;
            else if (m == "mpt02" || m == "studio3" || m == "studio3pal") machine = 1;
            else if (m == "studio3ntsc" || m == "ntsc") machine = 2;
            else if (m == "visicom" || m == "com100") machine = 3;
            else { fprintf(stderr, "error: --machine must be studio2, mpt02/studio3, studio3ntsc or visicom\n"); return 1; }
        }
        else if (a == "--beeper-tune") {
            std::string t = next("--beeper-tune");
            if      (t == "medium")  beeper_tune = 0;
            else if (t == "high")    beeper_tune = 1;
            else if (t == "higher")  beeper_tune = 2;
            else if (t == "highest") beeper_tune = 3;
            else if (t == "lowest")  beeper_tune = 4;
            else if (t == "lower")   beeper_tune = 5;
            else if (t == "low")     beeper_tune = 6;
            else { fprintf(stderr, "error: --beeper-tune must be medium, high, higher, highest, lowest, lower or low\n"); return 1; }
        }
        else if (a == "--ntsc-tone-pitch") {
            std::string t = next("--ntsc-tone-pitch");
            if      (t == "original") ntsc_pal_pitch = false;
            else if (t == "pal")      ntsc_pal_pitch = true;
            else { fprintf(stderr, "error: --ntsc-tone-pitch must be original or pal\n"); return 1; }
        }
        else if (a == "--joy-map") { joy_override = (uint8_t)atoi(next("--joy-map")); joy_manual = true; }
        else if (a == "--trace-q")    trace_q = true;
        else if (a == "--frame-log")  frame_log = true;
        else if (a == "--quiet")      quiet = true;
        else if (a == "--press") {
            std::string s = next("--press");
            size_t at = s.find('@');
            if (at == std::string::npos) { fprintf(stderr, "error: --press needs KEY@FRAME\n"); exit(1); }
            std::string k = s.substr(0, at);
            std::string rest = s.substr(at + 1);
            int hold = 4;
            size_t colon = rest.find(':');
            if (colon != std::string::npos) { hold = atoi(rest.c_str() + colon + 1); rest = rest.substr(0, colon); }
            uint8_t code;
            if (k.size() >= 2 && (k[0] == 'a' || k[0] == 'A') && k[1] >= '0' && k[1] <= '9')
                code = PS2_A[k[1] - '0'];
            else if (k.size() >= 2 && (k[0] == 'b' || k[0] == 'B') && k[1] >= '0' && k[1] <= '9')
                code = PS2_B[k[1] - '0'];
            else
                code = (uint8_t)strtol(k.c_str(), nullptr, 0);
            keys.push_back({ atol(rest.c_str()), hold, code, true });
        }
        else { fprintf(stderr, "error: unknown option %s (try --help)\n", argv[0]); usage(argv[0]); return 1; }
    }

    if (prefix.empty()) {
        const std::string& src = !ch8.empty() ? ch8 : (cart.empty() ? bios : cart);
        size_t slash = src.find_last_of('/');
        prefix = (slash == std::string::npos) ? src : src.substr(slash + 1);
        size_t dot = prefix.find_last_of('.');
        if (dot != std::string::npos) prefix = prefix.substr(0, dot);
        for (char& c : prefix) if (c == ' ' || c == '(' || c == ')' || c == '+') c = '_';
    }

    // Expand key events into press/release pairs sorted by frame.
    std::multimap<long, std::pair<uint8_t, bool>> key_sched;
    for (const KeyEvent& k : keys) {
        key_sched.insert({ k.frame, { k.code, true } });
        key_sched.insert({ k.frame + k.hold, { k.code, false } });
    }

    if (!shots.empty() || shot_every || shot_last) {
        std::string cmd = "mkdir -p '" + outdir + "'";
        if (system(cmd.c_str()) != 0) { fprintf(stderr, "error: cannot create %s\n", outdir.c_str()); return 2; }
    }

    FILE* df = stdout;
    if (!dumpfile.empty()) {
        df = fopen(dumpfile.c_str(), "w");
        if (!df) { fprintf(stderr, "error: cannot write %s\n", dumpfile.c_str()); return 2; }
    }

    Verilated::commandArgs(argc, argv);
    top = new Vtop();
    top->joy_override = joy_override;
    top->joy_manual   = joy_manual;
    top->machine = machine;
    top->beeper_tune = beeper_tune;
    top->ntsc_pal_pitch = ntsc_pal_pitch;
    top->ce_div4 = ce_div4 ? 1 : 0;
    top->players = players_mode;

    IoctlDriver io;
    // The native firmware goes into the selected machine's boot slot, exactly
    // as MiSTer's bootN.rom autoload does: index[5:0]=0 with slot in [7:6].
    // Loading with a flat index 0 would land every machine's BIOS in the
    // Studio II BRAM and machines 1-3 would boot from an empty ROM.
    io.add(bios, machine << 6);
    if (!chip8_fw.empty()) io.add(chip8_fw, chip8_fw_index);
    if (!cart.empty()) io.add(cart, 1);
    if (!ch8.empty()) io.add(ch8, 3);

    FrameGrabber fg;

    top->clk_48 = 0; top->clk_24 = 0;
    top->ioctl_download = 0; top->ioctl_upload = 0; top->ioctl_wr = 0;
    top->ioctl_addr = 0; top->ioctl_dout = 0; top->ioctl_din = 0; top->ioctl_index = 0;
    top->ps2_key = 0; top->inputs = 0;
    top->eval();

    // Give the loader check a known background in every slot. It can then
    // prove both positive routing and that rejected/unsupported bytes did not
    // modify any destination.
    if (loader_check)
        for (int slot = 0; slot < 5; slot++)
            for (int addr = 0; addr < 0x1000; addr++)
                set_rom_byte(slot, addr, 0xA5);

    // Pre-fill the RAM arrays with junk before the machine boots. On hardware
    // the 512-byte RAM (and the Visicom's plane-1 RAM) is wiped only by CLEAR:
    // it survives firmware/cartridge loads and OSD machine switches, so a
    // Visicom booted after a Studio II session starts with the Studio II's
    // leftovers. The sim's arrays start zeroed, which hid the Visicom
    // display-base rotation (docs/handoff.md, 2026-08-19). A simple xorshift
    // keyed by --ram-junk SEED makes that difference reproducible.
    if (ram_junk_seed) {
        uint32_t s = ram_junk_seed;
        auto nxt = [&s]() { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return (uint8_t)s; };
        for (int i = 0; i < 512; i++) SRAM[i] = nxt();
        for (int i = 0; i < 256; i++)
            top->rootp->top__DOT__rcastudio__DOT__sram2__DOT__mem[i] = nxt();
    }

    long cycles = 0;
    int  clk24_div = 0;
    bool ps2_toggle = false;
    long last_reported = -1;
    long clks_in_frame = 0;

    while (fg.frame <= frames && cycles < max_cycles && !Verilated::gotFinish()) {

        // --- rising edge ---
        if (!swap_done && swap_frame >= 0 && fg.frame >= swap_frame) {
            io.add(swap_file, 1);
            io.finished = false;
            swap_done = true;
        }
        if (!machine_at_done && machine_at_frame >= 0 && fg.frame >= machine_at_frame) {
            top->machine = machine_at;
            machine_at_done = true;
        }
        if (!swap0_done && swap0_frame >= 0 && fg.frame >= swap0_frame) {
            // Firmware swaps target whichever machine is selected *now*, so a
            // --machine-at that already fired routes the file to that slot.
            io.add(swap0_file, (int)top->machine << 6);
            io.finished = false;
            swap0_done = true;
        }
        io.tick();
        top->joystick_0 = (fg.frame >= joy_from && fg.frame < joy_to) ? joy_mask : 0;
        top->joystick_1 = (fg.frame >= joy2_from && fg.frame < joy2_to) ? joy2_mask : 0;

        // Key events scheduled for this frame. --press-phase delays them N
        // clks past the frame boundary: a real key lands at an arbitrary
        // machine cycle, and the phase at which the software's poll loop sees
        // it propagates into everything it does next (display enables, ISR
        // locks). Injecting only at frame boundaries samples exactly one of
        // those phases.
        auto range = key_sched.equal_range(fg.frame);
        if (clks_in_frame < press_phase) range.second = range.first;  // not yet
        for (auto it = range.first; it != range.second; ) {
            ps2_toggle = !ps2_toggle;
            top->ps2_key = (uint16_t)((ps2_toggle ? (1 << 10) : 0) |
                                      (it->second.second ? (1 << 9) : 0) |
                                      it->second.first);
            if (!quiet)
                fprintf(stderr, "[key] frame %ld: %s scancode 0x%02X\n",
                        fg.frame, it->second.second ? "press" : "release", it->second.first);
            it = key_sched.erase(it);
            break;   // one event per clock so each toggle is seen
        }

        top->clk_48 = 1;
        if (++clk24_div >= 2) { clk24_div = 0; top->clk_24 = !top->clk_24; }
        top->eval();

        if (loader_check && io.finished && !io.active && (swap_frame < 0 || swap_done)) break;

        // CPU instruction trace. FETCH puts the PC on the bus; the opcode is
        // valid one state later, in EXECUTE (the dpram has 1 cycle latency).
        if (trace_cpu > 0 && fg.frame >= trace_from) {
            static uint16_t pending_pc = 0;
            static bool have_pc = false;
            if (CPU(state) == 1 /*FETCH*/) { pending_pc = CPU(ram_a); have_pc = true; }
            else if (CPU(state) == 2 /*EXECUTE*/ && have_pc) {
                have_pc = false;
                printf("%08llu  PC=%04X  op=%02X  P=%X X=%X D=%02X DF=%d  "
                       "R0=%04X R1=%04X R2=%04X R3=%04X R4=%04X R5=%04X R8=%04X RB=%04X  "
                       "IE=%d Q=%d EF=%X\n",
                       (unsigned long long)main_time, pending_pc, CPU(ram_q),
                       CPU(P), CPU(X), CPU(D), CPU(DF),
                       CPU(R)[0], CPU(R)[1], CPU(R)[2], CPU(R)[3],
                       CPU(R)[4], CPU(R)[5], CPU(R)[8], CPU(R)[0xB],
                       CPU(IE), CPU(Q), CPU(EF));
                if (--trace_cpu == 0) printf("[trace-cpu limit reached]\n");
            }
        }

        // Machine-cycle trace: one line per cpu_ce, in a time window.
        if (trace_cyc_from && main_time >= trace_cyc_from && main_time < trace_cyc_to) {
            if (RS(cpu_ce)) {
                static const char* SN[] = {"RESET","FETCH","EXEC","EX3","B2","B3","SKIP","DMAI","DMAO","INTR","IDLE"};
                int st = CPU(state);
                printf("cyc %08llu st=%-5s Ra=%X Rwd=%04X R0=%04X R1=%04X dmao=%d v=%d h=%d sc=%d\n",
                       (unsigned long long)main_time, st<=10?SN[st]:"?",
                       (int)((CPU(action)>>2)&0xF), (int)CPU(Rwd), CPU(R)[0], CPU(R)[1],
                       (int)PIX(DMAO), (int)PIX(vcount), (int)PIX(hcount), (int)CPU(SC));
            }
        }

        // VRAM write trace: log CPU writes into the display page's top and
        // bottom two rows ($0900-$090F, $09F0-$09FF), with the PC that did it.
        if (trace_vwr && fg.frame >= trace_from) {
            static bool prev_wr = false;
            bool wr = RS(cpu_wr) != 0;
            if (wr && !prev_wr) {
                unsigned a = RS(ram_a) & 0xFFFF;
                if (a >= 0x0900 && a <= 0x09FF) {
                    unsigned off = a & 0xFF;
                    if (getenv("VWR_ALL") || off < 0x10 || off >= 0xF0)
                        printf("vwr %08llu f=%ld v=%3d addr=%04X data=%02X pc=%04X\n",
                               (unsigned long long)main_time, fg.frame,
                               (int)PIX(vcount), a, (int)RS(ram_d), CPU(R)[CPU(P)]);
                }
            }
            prev_wr = wr;
        }

        // Per-scanline R0 trace: one line per HSync, while enabled.
        if (trace_r0 && fg.frame >= trace_from) {
            static bool prev_hs2 = false;
            bool hs = top->VGA_HS;
            if (hs && !prev_hs2)
                printf("%08llu line f=%ld v=%3d R0=%04X pc=%04X dmao=%d int=%d efx=%d de=%d\n",
                       (unsigned long long)main_time,
                       fg.frame, (int)PIX(vcount), CPU(R)[0], CPU(R)[CPU(P)],
                       (int)PIX(DMAO), (int)PIX(INT), (int)PIX(EFx),
                       (int)RS(pixie_video__DOT__cdp1861__DOT__display_enabled));
            prev_hs2 = hs;
        }

        // Sample video on the rising edge (ce_pix is tied high in sim.v)
        // Capture the bitmap window, not the whole raster. The core emits a full
        // NTSC/PAL raster now (border painted in the background colour), so
        // VGA_DE would give 88x242 / 88x292 frames and invalidate every recorded
        // score. bitmap_de marks the 64x128 / 64x192 bitmap alone.
        bool boundary = fg.clock(top->VGA_VS, top->VGA_HS,
                                 top->rootp->top__DOT__bitmap_de != 0,
                                 (uint8_t)((top->VGA_R ? 4 : 0) |
                                           (top->VGA_G ? 2 : 0) |
                                           (top->VGA_B ? 1 : 0)));
        if (boundary) clks_in_frame = 0; else clks_in_frame++;

        {
            bool a_now = (int16_t)top->rootp->top__DOT__audio > 0;
            if (a_now != a_prev) { a_prev = a_now; a_edges++; }
            bool q_now = CPU(Q) != 0;
            if (q_now != q_prev) {
                if (q_prev) q_on_frames += (fg.frame - q_last_chg);
                q_last_chg = fg.frame;
                q_prev = q_now;
                q_edges++;
                if (trace_q)
                    printf("Q %d frame %ld  (audio edges so far %ld)  tick %llu "
                           "live=%u control=%u drive=%u amp=%u on_ticks=%u\n",
                           q_now ? 1 : 0, (long)fg.frame, a_edges,
                           (unsigned long long)main_time,
                           (unsigned)RS(snd_half), (unsigned)RS(snd_control_half),
                           (unsigned)RS(snd_drive_half), (unsigned)RS(snd_amp),
                           (unsigned)RS(snd_on_ticks));
            }
        }

        if (boundary && fg.complete) {
            long f = fg.frame - 1;   // the frame that just finished

            bool do_shot = shots.count(f) || (shot_every && f % shot_every == 0) ||
                           (shot_last && f == frames - 1);
            bool do_dump = dumps.count(f) || (dump_every && f % dump_every == 0);

            if (frame_log)
                printf("frame %6ld  %3dx%-3d  hash %08X  %s\n",
                       f, fg.last_width, fg.last_height, fg.hash(),
                       fg.blank() ? "blank" : "");

            if (do_shot) {
                std::vector<uint8_t> rgb; int w, h;
                fg.to_rgb(rgb, w, h, scale);
                char name[512];
                snprintf(name, sizeof(name), "%s/%s_f%05ld.png", outdir.c_str(), prefix.c_str(), f);
                write_png(name, w, h, rgb);
                if (!quiet) fprintf(stderr, "[shot] %s (%dx%d source %dx%d)\n",
                                    name, w, h, fg.last_width, fg.last_height);
                if (want_ppm) {
                    snprintf(name, sizeof(name), "%s/%s_f%05ld.ppm", outdir.c_str(), prefix.c_str(), f);
                    write_ppm(name, w, h, rgb);
                }
                if (want_ascii) {
                    printf("--- frame %ld (%dx%d) ---\n", f, fg.last_width, fg.last_height);
                    fg.to_ascii(stdout);
                }
            }

            if (do_dump) dump_state(df, f, fg, want_vram);

            if (!quiet && !frame_log && f / 60 != last_reported) {
                last_reported = f / 60;
                fprintf(stderr, "[run] frame %ld/%ld  cycles %ld\n", f, frames, cycles);
            }
        }

        // --- falling edge ---
        top->clk_48 = 0;
        top->eval();

        main_time++;
        cycles++;
    }

    if (loader_check) {
        std::vector<std::vector<uint8_t>> expected(5, std::vector<uint8_t>(0x1000, 0xA5));
        const std::vector<uint8_t> bios_data = read_binary(bios);
        for (size_t i = 0; i < bios_data.size() && i < 0x1000; i++) expected[machine][i] = bios_data[i];

        uint8_t expected_pages = 0;
        if (!cart.empty()) expected_pages = apply_cart_image(expected[machine], cart, machine);
        if (!swap_file.empty()) expected_pages = apply_cart_image(expected[machine], swap_file, machine);

        bool fw_valid = false;
        if (!chip8_fw.empty()) {
            const std::vector<uint8_t> fw_data = read_binary(chip8_fw);
            for (size_t i = 0; i < fw_data.size() && i < 0x300; i++) expected[4][i] = fw_data[i];
            fw_valid = fw_data.size() >= 0x300;
        }

        bool ch8_accepted = fw_valid && (machine != 3) && !ch8.empty();
        if (!ch8.empty()) {
            const std::vector<uint8_t> ch8_data = read_binary(ch8);
            if (ch8_accepted) {
                for (size_t i = 0; i < ch8_data.size() && i < 0x900; i++) {
                    size_t addr = (i < 0x500) ? (0x300 + i) : (0xC00 + i - 0x500);
                    expected[4][addr] = ch8_data[i];
                }
            }
            ch8_accepted = ch8_accepted && !ch8_data.empty();
        }

        int failures = 0;
        for (int slot = 0; slot < 5; slot++) {
            for (int addr = 0; addr < 0x1000; addr++) {
                uint8_t got = rom_byte(slot, addr);
                if (got != expected[slot][addr]) {
                    if (failures < 12)
                        printf("FAIL rom%d[$%03X] = %02X, expected %02X\n",
                               slot, addr, got, expected[slot][addr]);
                    failures++;
                }
            }
        }
        if ((RS(chip8_fw_loaded) != 0) != fw_valid) {
            printf("FAIL chip8_fw_loaded = %u, expected %u\n",
                   (unsigned)RS(chip8_fw_loaded), fw_valid ? 1u : 0u);
            failures++;
        }
        if ((RS(chip8_loaded) != 0) != ch8_accepted) {
            printf("FAIL chip8_loaded = %u, expected %u\n",
                   (unsigned)RS(chip8_loaded), ch8_accepted ? 1u : 0u);
            failures++;
        }

        if ((uint8_t)RS(cart_page) != expected_pages) {
            printf("FAIL cart_page = %02X, expected %02X\n",
                   (unsigned)RS(cart_page), (unsigned)expected_pages);
            failures++;
        }

        // Visicom's resident half is always visible. Its cartridge half is
        // visible page by page, and an omitted page must return $FF even though
        // a preceding cartridge's bytes remain physically present in ROM3.
        if (machine == 3) {
            for (int page = 0; page < 16; page++) {
                for (int offset : {0x00, 0xff}) {
                    int addr = (page << 8) | offset;
                    bool visible = page < 8 || (expected_pages & (1u << (page - 8)));
                    uint8_t want = visible ? expected[3][addr] : 0xff;
                    uint8_t got = read_cpu_bus((uint16_t)addr);
                    if (got != want) {
                        printf("FAIL Visicom bus[$%03X] = %02X, expected %02X\n",
                               addr, got, want);
                        failures++;
                    }
                }
            }
        }

        // Activation follows the applied machine without discarding the game:
        // all three Studio selections use ROM4 and Visicom suppresses it.
        top->clk_48 = 0;
        top->eval();
        RS(chip8_loaded) = 1;
        for (int m = 0; m < 4; m++) {
            top->machine = m;
            top->eval();
            bool expected_active = m != 3;
            if ((RS(chip8_active) != 0) != expected_active) {
                printf("FAIL chip8_active on machine %d = %u, expected %u\n", m,
                       (unsigned)RS(chip8_active), expected_active ? 1u : 0u);
                failures++;
            }
        }

        // The automatic CHIP-8 profile is one-player movement on keypad A:
        // up/left/down/right -> 5/7/8/9, Start -> 1, Fire -> F, Extra -> 0.
        top->machine = 0;
        top->players = 0;
        top->joy_manual = 0;
        const int chip8_joy_bits[] = {3, 1, 2, 0, 6, 4, 5};
        const int chip8_a_keys[]   = {5, 7, 8, 9, 1, -1, 0};
        const int chip8_b_keys[]   = {-1, -1, -1, -1, -1, 6, -1};
        for (size_t i = 0; i < sizeof(chip8_joy_bits) / sizeof(chip8_joy_bits[0]); i++) {
            top->joystick_0 = 1u << chip8_joy_bits[i];
            top->eval();
            unsigned expected_a = chip8_a_keys[i] < 0 ? 0u : (1u << chip8_a_keys[i]);
            unsigned expected_b = chip8_b_keys[i] < 0 ? 0u : (1u << chip8_b_keys[i]);
            if ((unsigned)RS(joyA_active) != expected_a || (unsigned)RS(joyB_active) != expected_b) {
                printf("FAIL CHIP-8 input bit %d mapped to A=$%03X B=$%03X, expected A=$%03X B=$%03X\n",
                       chip8_joy_bits[i], (unsigned)RS(joyA_active), (unsigned)RS(joyB_active),
                       expected_a, expected_b);
                failures++;
            }
        }
        if ((unsigned)RS(auto_profile) != 13u) {
            printf("FAIL CHIP-8 auto profile = %u, expected 13\n", (unsigned)RS(auto_profile));
            failures++;
        }

        // Manual-profile spot checks cover simultaneous keypad presses,
        // dedicated layouts, and profiles whose routing changes with Players.
        auto expect_profile_players = [&](unsigned profile, unsigned player_mode,
                                          uint32_t joy0, uint32_t joy1,
                                          unsigned expected_a, unsigned expected_b,
                                          const char* name) {
            top->joy_manual = 1;
            top->joy_override = profile;
            top->players = player_mode;
            top->joystick_0 = joy0;
            top->joystick_1 = joy1;
            top->eval();
            if ((unsigned)RS(joyA_active) != expected_a ||
                (unsigned)RS(joyB_active) != expected_b) {
                printf("FAIL %s mapped to A=$%03X B=$%03X, expected A=$%03X B=$%03X\n",
                       name, (unsigned)RS(joyA_active), (unsigned)RS(joyB_active),
                       expected_a, expected_b);
                failures++;
            }
        };
        auto expect_profile = [&](unsigned profile, uint32_t joy, unsigned expected_a,
                                  unsigned expected_b, const char* name) {
            expect_profile_players(profile, 0, joy, 0, expected_a, expected_b, name);
        };
        expect_profile(3, (1u << 4) | (1u << 5) | (1u << 1),
                       (1u << 2) | (1u << 0), 1u << 4,
                       "Freeway accelerate+hard+left");
        expect_profile(3, 1u << 6, 0, 1u << 0, "Freeway normal Start");
        expect_profile(8, 1u << 4, 1u << 5, 0, "Flappy Fire");
        expect_profile(11, (1u << 4) | (1u << 1), (1u << 2) | (1u << 4), 0,
                       "Race accelerate+left");
        expect_profile_players(12, 1, (1u << 3) | (1u << 4) | (1u << 5), 0,
                               0, (1u << 2) | (1u << 5) | (1u << 0),
                               "Squash one-player controls");
        expect_profile_players(12, 1, 1u << 6, 0, 1u << 1, 0,
                               "Squash one-player Start");
        expect_profile_players(12, 2, (1u << 3) | (1u << 4) | (1u << 5),
                               (1u << 2) | (1u << 0) | (1u << 5),
                               (1u << 2) | (1u << 5) | (1u << 0),
                               (1u << 8) | (1u << 6) | (1u << 0),
                               "Tennis two-player controls");
        expect_profile_players(12, 2, 1u << 6, 0, 1u << 2, 0,
                               "Tennis two-player Start");
        expect_profile(14, (1u << 5) | (1u << 1), 1u << 4, 1u << 4,
                       "Outbreak fast-left");
        expect_profile(14, 1u << 4, 0, 1u << 1, "Climber/Outbreak replay");
        expect_profile(15, (1u << 4) | (1u << 5) | (1u << 3) | (1u << 1),
                       1u << 0, (1u << 1) | (1u << 5), "Space Explorer lock+fire");

        top->joystick_0 = 0;
        top->players = players_mode;
        top->joy_manual = joy_manual;
        top->joy_override = joy_override;
        top->machine = machine;

        // A machine reset/CLEAR must retain the selected game.
        top->rootp->top__DOT__clear_key = 1;
        top->clk_48 = 1;
        top->eval();
        top->clk_48 = 0;
        top->eval();
        top->rootp->top__DOT__clear_key = 0;
        if (!RS(chip8_loaded)) {
            printf("FAIL machine reset cleared chip8_loaded\n");
            failures++;
        }

        // F1, F2, and either interpreter load path each exit CHIP-8. Exercise
        // all four classifications without a write; activation changes at
        // transfer start, not by size.
        const int exit_indices[] = {1, 2, 4, 0x0103};
        for (int index : exit_indices) {
            RS(chip8_loaded) = 1;
            top->ioctl_index = index;
            top->ioctl_download = 1;
            top->ioctl_wr = 0;
            top->clk_48 = 1;
            top->eval();
            top->clk_48 = 0;
            top->eval();
            if (RS(chip8_loaded)) {
                printf("FAIL ioctl index %d did not clear chip8_loaded\n", index);
                failures++;
            }
            if ((index == 4 || index == 0x0103) && RS(chip8_fw_loaded)) {
                printf("FAIL replacement interpreter did not invalidate chip8_fw_loaded\n");
                failures++;
            }
            top->ioctl_download = 0;
            top->clk_48 = 1;
            top->eval();
            top->clk_48 = 0;
            top->eval();
        }

        printf("CHIP-8 loader: %s (%d mismatch%s)\n", failures ? "FAIL" : "PASS",
               failures, failures == 1 ? "" : "es");
        top->final();
        if (df != stdout) fclose(df);
        delete top;
        return failures ? 1 : 0;
    }

    printf("\n");
    printf("audio: %ld output edges, %ld Q edges\n", a_edges, q_edges);
    printf("done: %ld frames in %ld cycles\n", fg.frame, cycles);
    printf("      last frame %dx%d, hash %08X, %s\n",
           fg.last_width, fg.last_height, fg.hash(),
           fg.blank() ? "BLANK (nothing was drawn)" : "has content");
    if (cycles >= max_cycles) printf("      NOTE: stopped on --max-cycles\n");
    if (!fg.complete)         printf("      WARNING: no complete frame was ever captured\n");

    top->final();
    if (df != stdout) fclose(df);
    delete top;
    return 0;
}
