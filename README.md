# SAM_Digital_Circuit_Design

**English** | [한국어](README.ko.md)

[![RTL CI](https://github.com/Minchan6847/SAM_Digital_Circuit_Design/actions/workflows/rtl-ci.yml/badge.svg)](https://github.com/Minchan6847/SAM_Digital_Circuit_Design/actions/workflows/rtl-ci.yml)

Exercises from the online course "Digital circuit design in practice: designing digital IP for computer architecture and SoC protocols" (삼코치).

RTL design and verification of the core digital IP of a small computer system: the memory hierarchy (cache, SRAM, DRAM), storage data integrity (CRC, ECC), a five-stage pipelined CPU, and SoC protocols (FIFO, APB). Each module is designed, simulated, synthesized and documented.

- **Tool:** Quartus-lite-20.1.0.711-windows
- The `README.md` in each folder explains how the module works, with block and state diagrams, waveforms and verification results. Those folder documents are written in Korean.

---

## Projects

### Memory hierarchy

| Project | Description |
|---|---|
| [5-3-Cache](5-3-Cache) | Direct-mapped write-back cache. Handles variable latency with a `req`/`ack` handshake and implements hit and miss, write-back and open-page behavior. |
| [5-4-TPSRAM_DPSRAM](5-4-TPSRAM_DPSRAM) | Two-port (1R1W) and dual-port (2RW) SRAM models. Compares the port configurations and the cost in cells (6T to 8T) and peripheral circuits. |
| [5-6-DDR_Controller](5-6-DDR_Controller) | DDR4-style DRAM controller. State machine (ACT, WR/RD, PRE), timing parameters, DQS strobe, BL8 burst and an open-page policy. |

### Data integrity (NAND)

| Project | Description |
|---|---|
| [5-7-CRC_16_CCITT_Parallel](5-7-CRC_16_CCITT_Parallel) | Byte-parallel CRC-16-CCITT generator, for error **detection**. Includes a comparison of five implementations: hand calculation, bit loop, LUT, serial LFSR and parallel unroll. |
| [5-8-Hamming_decoder](5-8-Hamming_decoder) | Hamming (21,16) SEC encoder and decoder, an ECC for error **correction**. Finds the error position from the syndrome and corrects a single bit. |

> **From detection to correction:** CRC (5-7) only *detects* that an error exists. Hamming ECC (5-8) goes one step further and *corrects* it. Together they are the two halves of NAND flash data integrity.

### Processor

| Project | Description |
|---|---|
| [5-9-cpu](5-9-cpu) | Five-stage pipelined MIPS CPU without hazard handling. IF, ID, EX, MEM and WB are separated by pipeline registers, and branches resolve in MEM. The program itself has to keep RAW-dependent instructions four slots apart and place three NOPs after each branch. |
| [5-10-cpu_hazard_hedge](5-10-cpu_hazard_hedge) | The same CPU with hazard handling. Adds a forwarding unit, hazard detection (load-use stall) and IF flush, and moves branch resolution to ID so the penalty drops from 3 to 1. Adds the `or`, `slt`, `bne` and `j` instructions. |

> **From unhandled to handled:** in 5-9 the software avoids hazards (four-slot spacing between dependent instructions, NOP padding). In 5-10 the hardware resolves them with forwarding, stall and flush. Side by side, the two versions show which restriction each piece of hazard logic removes.

### SoC protocols (FIFO, AMBA)

| Project | Description |
|---|---|
| [6-1-sync_fifo](6-1-sync_fifo) | Single-clock synchronous FIFO. Counter-based occupancy tracking and circular pointers. Depth, width and the almost-full and almost-empty thresholds are parameters. |
| [6-2-async_fifo](6-2-async_fifo) | Asynchronous FIFO that passes data between two independent clocks. CDC with Gray code pointers and two-flop synchronizers, async-assert and sync-deassert reset in each domain, and first-word fall-through output. |
| [6-3-apb_regs](6-3-apb_regs) | Register block that works as an AMBA APB slave. Decodes read and write addresses separately to protect read-only registers, and answers reserved, unaligned and read-only writes with `PSLVERR`. |

> **From synchronous to asynchronous:** 6-1 covers the basic FIFO structure inside one clock. 6-2 splits the same structure across two clock domains and solves the resulting CDC problem with Gray code and synchronizers.

---

## Continuous integration

Whenever a push to `main` or a pull request changes RTL or CI files, GitHub Actions runs each project's testbench with Verilator and synthesizes its RTL with Yosys (synthesizability, `check -assert`, latch check). See [.github/CI.md](.github/CI.md) for what is checked and how to add a project.

---

## Common notes

- Each project consists of RTL sources (`.v`, `.sv`), a testbench, the synthesized netlist schematic and RTL simulation waveforms.
- Diagrams in the documents are written in Mermaid and render directly on GitHub.
- Folder numbers follow the order of the course curriculum.
