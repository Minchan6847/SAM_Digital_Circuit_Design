# RTL CI

**English** | [한국어](CI.ko.md)

This document explains what the GitHub Actions workflow (`.github/workflows/rtl-ci.yml`) checks and how.

## At a glance

| Item | Details |
|---|---|
| When it runs | Push to `main`, every pull request, and manual runs (`workflow_dispatch`), but only when `.v`/`.sv` files or files under `.github/` change |
| Structure | One job per project folder (matrix); jobs run in parallel and independently |
| Simulation | Runs each project's `tb_*.sv` with Verilator and decides PASS/FAIL from the log |
| Synthesis check | Synthesizes the RTL with Yosys + yosys-slang and checks that it is synthesizable, structurally sound and latch-free |
| Tool installation | [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build), pinned to a dated release |

The pull request's Checks list shows 10 entries named `RTL CI / <project folder>`. Each job's **Summary** tab shows the simulation result and the synthesized cell count. When a job fails, the cause appears as an annotation (`::error`).

## Files

```
.github/
├── workflows/rtl-ci.yml   # triggers, project list (matrix), tool installation
├── scripts/sim.sh         # Verilator build and run + PASS/FAIL decision
├── scripts/synth.sh       # Yosys synthesis + checks + latch check
├── CI.md                  # this document (English)
└── CI.ko.md               # this document (Korean)
```

## Tool versions

OSS CAD Suite is a **nightly distribution** that rebuilds Verilator (`master`), Yosys (`main`) and yosys-slang every day. Always taking the newest build could change the results from one day to the next, so the workflow pins a date in `OSS_CAD_SUITE_VERSION` at the top.

```yaml
env:
  OSS_CAD_SUITE_VERSION: '2026-11-26'
```

To update the tools, pick a date from the [release list](https://github.com/YosysHQ/oss-cad-suite-build/releases) and change only this value. The versions actually used are printed in each job's `Tool versions` step.

### Why Verilator instead of Icarus

The CI started with Icarus Verilog (4-state), but two testbenches in this repository hit Icarus limitations:

- `5-10-cpu_hazard_hedge`: Icarus 12 returns 1 for `$isunknown` on a concatenation such as `{a, b}` regardless of the values. The monitor in [`tb_cpu_hazard_hedge.sv` lines 187–197](../5-10-cpu_hazard_hedge/tb_cpu_hazard_hedge.sv#L187-L197) checks seven control signals at once with `$isunknown({ut.MemRead_EX, ut.MemWrite_EX, ...})`, so this X check failed 262 times even though no signal was X.
- `5-7-CRC_16_CCITT_Parallel`: Icarus does not support `automatic` variable declarations inside functions. The `ReverseBits` function declares `automatic logic [7:0] temp = data, ii = 0;` in [`tb_CRC_16_CCITT_Parallel.sv` line 76](../5-7-CRC_16_CCITT_Parallel/tb_CRC_16_CCITT_Parallel.sv#L76), so the testbench did not compile.

All 10 projects pass on a recent Verilator without changes, so the CI uses Verilator only.

Verilator 5.020 from Ubuntu apt is not used, because no single set of options passes all 10 projects with it:

- With default optimization, Verilator 5.020 drops constant writes to a variable that is also written from an `initial` block. The coverage flags in `5-10-cpu_hazard_hedge`, such as `saw_mem_forward = 1'b1` in [`tb_cpu_hazard_hedge.sv` line 203](../5-10-cpu_hazard_hedge/tb_cpu_hazard_hedge.sv#L203), therefore never become 1, and 14 coverage checks fail.
- With `-O0`, that bug goes away, but Verilator 5.020 rejects `5-9-cpu` with `BLKLOOPINIT` ("Delayed assignment to array inside for loops"). The cause is the reset loop in [`DataMem.sv` lines 17–19](../5-9-cpu/DataMem.sv#L17-L19), which clears memory with `for (int i = 0; i < 128; i++) mem[i] <= 32'd0;`.

## Simulation (`sim.sh`)

All `.v`/`.sv` files in the project folder are built with Verilator (`--binary --timing`) using the testbench module as the top, and the result is run. A project passes only if **all three** conditions hold:

1. The simulation process exits with code 0 (a `$fatal`, or a `$stop` caused by `$error`, counts as a failure).
2. The log contains no `ERROR`, `FAIL`, `FATAL` or `%Error`.
3. The log contains the project's expected pattern (`expect`).

| Project | TB top | Expected pattern | What a pass means |
|---|---|---|---|
| 5-3-Cache | `tb_cache` | `$finish` | Ran to the end (the TB has no self-check) |
| 5-4-TPSRAM_DPSRAM | `tb_tpsram` | `$finish` | Ran to the end (the TB has no self-check) |
| 5-6-DDR_Controller | `tb_ddr_ctrl` | `$finish` | Ran to the end (the TB has no self-check) |
| 5-7-CRC_16_CCITT_Parallel | `tb_CRC_16_CCITT_Parallel` | `Please: 5787` | Final CRC value matches |
| 5-8-Hamming_decoder | `tb_Hamming_decoder` | `^PASS:` | Self-checking |
| 5-9-cpu | `tb_cpu` | `^PASS:` | Self-checking |
| 5-10-cpu_hazard_hedge | `tb_cpu_hazard_hedge` | `^PASS:` | Self-checking |
| 6-1-sync_fifo | `tb_sync_fifo` | `^PASS:` | Self-checking |
| 6-2-async_fifo | `tb_async_fifo` | `^PASS:` | Self-checking |
| 6-3-apb_regs | `tb_apb_regs` | `^PASS:` | Self-checking |

For the testbenches without a self-check (Cache, TPSRAM_DPSRAM, DDR_Controller), a pass only guarantees that the simulation ran to the end without errors. Adding expected-value comparisons and a `PASS:` line to these testbenches would let the expected pattern change to `^PASS:` and raise the level of checking.

### Two-state simulation

Verilator is a **two-state** simulator that represents only 0 and 1, so it cannot see X or Z.

- Checks that rely on X propagation (for example, checking that control signals are not X after reset) always pass.
- A register with a missing reset starts at 0, so the missing reset does not show.

The current testbenches decide PASS/FAIL from values, not from X, so the practical impact is small. Verilator now has a `--fourstate` flag, but it is still experimental (arrays are not supported), so the CI does not use it. Turning it on will be considered once it supports arrays.

## Synthesis check (`synth.sh`)

The RTL files (every file whose name does not start with `tb_`) are read with yosys-slang (`read_slang`) and synthesized with Yosys `synth`. yosys-slang supports more of SystemVerilog than Yosys's built-in parser; for example, it accepts `return` inside a function (`6-2-async_fifo`) as written.

### What it does

Without a PDK (liberty) or SDC, the design is mapped to Yosys's internal **generic gate library** (`$_AND_`, `$_XOR_`, `$_DFF_PN0_`, …). This corresponds to GTECH in Synopsys DC.

| DC step | Yosys `synth` equivalent |
|---|---|
| Translation (elaborate → GTECH) | `hierarchy -check`, `proc` (always blocks → register/MUX netlist) |
| High-level optimization | `fsm` (state machine extraction and re-encoding), `opt` (constant propagation, removal of unused logic), `share` (resource sharing), `memory` (memory inference) |
| Gate mapping | `techmap` (mapping to generic gates) |
| Logic optimization | `abc -fast` (logic minimization by gate count, not timing) |

In DC terms, this is roughly an `elaborate` followed by a `compile` at the GTECH level, without a target library. There is no timing-driven optimization such as `compile_ultra`.

### What it catches

- Syntax and elaboration errors, missing modules, port mismatches (`hierarchy -check`)
- Unsynthesizable constructs
- `check -assert` violations: multiple drivers, signals used without a driver, combinational loops
- **Inferred latches**: the job fails if an incomplete `if`/`case` in a combinational `always` block creates a latch. Yosys finishes synthesis normally even when it infers a latch, so the script looks for latch cells (`$_DLATCH_*` and similar) in the synthesized netlist.

### What it does not catch

- Timing, or area in real cells. The cell count is a count of generic gates and cannot be compared with DC area.
- Behavior differences between RTL simulation and the synthesized result (`initial` blocks, incomplete sensitivity lists, etc.)
- Constructs that only DC rejects (and the other way around)

### Per-project settings

| Project | Synthesis top | Notes |
|---|---|---|
| 5-4-TPSRAM_DPSRAM | `tpsram`, `dpsram` | Two independent tops, synthesized separately |
| 5-6-DDR_Controller | `ddr_ctrl` | `dram` in the same file is a memory model for the TB, so it is excluded |
| 5-9-cpu, 5-10-cpu_hazard_hedge | `cpu`, `cpu_hazard_hedge` | Uses `keep` (see below) |

**`keep`**: the CPU tops have only `clk` and reset ports and no outputs. Synthesized as is, all logic would be removed as unused, leaving 0 cells. `keep` puts a keep attribute on every wire so the logic stays.

The CPU cell counts are large because there are no memory macros: InstMem, DataMem and the register file all become flip-flops (the same situation as running DC without a memory compiler).

## Adding a project

Add one line to `matrix.include` in `rtl-ci.yml`:

```yaml
- { dir: 7-1-new_project, tb: tb_new_project, expect: '^PASS:', synth: new_project }
```

| Key | Meaning |
|---|---|
| `dir` | Project folder (the folder that holds both the RTL and the TB) |
| `tb` | TB top module name |
| `expect` | Log pattern (regular expression) that counts as a pass. `^PASS:` is recommended for self-checking TBs |
| `synth` | Top module(s) to synthesize (several, separated by spaces; `''` skips synthesis) |
| `keep` | `keep` if the top has no output ports |

A testbench that prints a line starting with `PASS: ...` on success and uses `$error`/`$fatal` on failure is judged correctly without any extra setup.

## Running locally

Install OSS CAD Suite and set up the environment with `source <install path>/environment`. Then run the same scripts as the CI from the repository root:

```bash
# Simulation: <folder> <TB top> <expected pattern>
bash .github/scripts/sim.sh 6-1-sync_fifo tb_sync_fifo '^PASS:'

# Synthesis: <folder> "<top ...>" [keep]
bash .github/scripts/synth.sh 6-1-sync_fifo sync_fifo
bash .github/scripts/synth.sh 5-9-cpu cpu keep
```

Build outputs go to a temporary folder. Set `BUILD_DIR=<path>` to choose the location.
