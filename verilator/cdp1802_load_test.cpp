#include "Vcdp1802.h"
#include "verilated.h"

#include <cstdint>
#include <cstdio>

static int failures = 0;

static void expect(bool condition, const char* message) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++failures;
    }
}

static void cycle(Vcdp1802& cpu) {
    cpu.CLOCK = 1;
    cpu.eval();
    cpu.CLOCK = 0;
    cpu.eval();
}

static void load_byte(Vcdp1802& cpu, std::uint16_t address, std::uint8_t value) {
    cpu.io_din = value;
    cpu.dma_in_req = 1;
    cycle(cpu);                       // LOAD -> DMA-IN
    cpu.dma_in_req = 0;
    cpu.eval();

    expect(cpu.SC == 2, "DMA-IN must use the S2 state code");
    expect(cpu.ram_wr, "DMA-IN must assert the memory-write strobe");
    expect(cpu.ram_a == address, "DMA-IN must address R(0)");
    expect(cpu.ram_d == value, "DMA-IN must put the external byte on the memory bus");
    cycle(cpu);                       // complete DMA-IN -> LOAD
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcdp1802 cpu;

    cpu.CLOCK = 0;
    cpu.clk_enable = 1;
    cpu.CLEAR_N = 1;
    cpu.WAIT_N = 1;
    cpu.INT_N = 1;
    cpu.dma_in_req = 0;
    cpu.dma_out_req = 0;
    cpu.EF = 0;
    cpu.io_din = 0;
    cpu.ram_q = 0;
    cpu.eval();

    cpu.CLEAR_N = 0;                  // RESET: CLEAR low, WAIT high
    cpu.eval();
    expect(cpu.ram_a == 0, "RESET must clear R(0)");
    expect(cpu.Q == 0, "RESET must clear Q");

    cpu.WAIT_N = 0;                   // LOAD: CLEAR low, WAIT low
    cpu.eval();
    expect(cpu.SC == 1, "idle LOAD must remain in S1");
    expect(!cpu.ram_rd && !cpu.ram_wr, "idle LOAD must not access memory");
    cycle(cpu);

    load_byte(cpu, 0x0000, 0xa5);
    expect(cpu.ram_a == 0x0001, "DMA-IN must increment R(0)");
    load_byte(cpu, 0x0001, 0x5a);
    expect(cpu.ram_a == 0x0002, "successive DMA-IN cycles must advance R(0)");

    cpu.INT_N = 0;
    cycle(cpu);
    expect(cpu.SC == 1, "LOAD must not acknowledge interrupts");
    expect(cpu.ram_a == 0x0002, "idle LOAD must preserve R(0)");
    cpu.INT_N = 1;

    cpu.ram_q = 0xc3;
    cpu.dma_out_req = 1;
    cycle(cpu);                       // LOAD -> DMA-OUT
    cpu.dma_out_req = 0;
    cpu.eval();
    expect(cpu.SC == 2, "DMA-OUT in LOAD must use the S2 state code");
    expect(cpu.ram_rd, "DMA-OUT in LOAD must assert the memory-read strobe");
    expect(cpu.ram_a == 0x0002, "DMA-OUT in LOAD must address R(0)");
    expect(cpu.io_dout == 0xc3, "DMA-OUT must expose the memory byte");
    cycle(cpu);
    expect(cpu.ram_a == 0x0003, "DMA-OUT must increment R(0)");
    expect(cpu.SC == 1, "completed LOAD DMA must return to S1 idle");

    cpu.WAIT_N = 1;                   // return through RESET before RUN
    cpu.eval();
    expect(cpu.ram_a == 0, "RESET after LOAD must restore R(0)");
    cpu.CLEAR_N = 1;
    cpu.eval();
    cycle(cpu);                       // initialization cycle
    expect(cpu.SC == 0, "RUN after initialization must enter fetch");
    expect(cpu.ram_rd && cpu.ram_a == 0, "RUN must fetch from M(0000)");

    cpu.final();
    if (failures != 0) {
        std::fprintf(stderr, "CDP1802 LOAD checks: FAIL (%d mismatches)\n", failures);
        return 1;
    }

    std::puts("CDP1802 LOAD checks: PASS (0 mismatches)");
    return 0;
}
