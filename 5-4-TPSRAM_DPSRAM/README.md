# Two-Port & Dual-Port SRAM (TPSRAM / DPSRAM)

동일한 메모리 배열을 서로 다른 포트 구성으로 구현한 두 SRAM 모델입니다. 파라미터로 깊이/폭을 조절할 수 있는 behavioral RTL이며, 합성 시 실제 SRAM 매크로로 대체되는 것을 가정합니다.

| 모듈 | 포트 구성 | 별칭 | 한 사이클에 가능한 동작 |
|---|---|---|---|
| `tpsram` | 쓰기 전용 1 + 읽기 전용 1 | two-port / simple dual-port (1R1W) | 서로 다른 주소에 읽기 **1** + 쓰기 **1** 동시 |
| `dpsram` | 읽기/쓰기 겸용 2 | dual-port / true dual-port (2RW) | 포트마다 읽기 **또는** 쓰기, 두 포트 독립 |

공통점: 단일 클럭 동기식, 파라미터 `DEPTH=8` · `WIDTH=32` (기본), 읽기는 **registered read**라 요청 다음 사이클에 데이터가 나옵니다(1-cycle latency).

---

## TPSRAM (`tpsram.sv`)

읽기 포트와 쓰기 포트가 **물리적으로 분리**된 SRAM입니다. 두 포트가 각자의 주소를 가지므로, 한 사이클에 한 주소를 읽으면서 다른 주소에 쓸 수 있습니다.

### Ports

| Signal | Dir | Width | 설명 |
|---|---|---|---|
| `clk` | in | 1 | 공통 클럭 (주석의 `rclk`처럼 읽기 클럭 분리도 가능한 구조) |
| `we` | in | 1 | 쓰기 enable |
| `re` | in | 1 | 읽기 enable |
| `wa` | in | `DEPTH_LOG` | 쓰기 주소 |
| `ra` | in | `DEPTH_LOG` | 읽기 주소 |
| `wd` | in | `WIDTH` | 쓰기 데이터 |
| `rd` | out | `WIDTH` | 읽기 데이터 (registered) |

### 동작

```verilog
always @(posedge clk) if (we) mem[wa] <= wd;   // 쓰기 포트
always @(posedge clk) if (re) rd     <= mem[ra];  // 읽기 포트 (registered read)
```

- 쓰기와 읽기가 독립된 always 블록이라 **동시에** 일어날 수 있습니다 (1R1W).
- `rd`가 레지스터라 `re`를 준 **다음 사이클**에 데이터가 나옵니다.
- **같은 주소를 동시에 읽고 쓰면(`ra == wa`)** read-first(옛 데이터)가 됩니다. 두 대입 모두 non-blocking이라 `rd`는 갱신 전 값을 샘플링하기 때문입니다. (시뮬레이션으로 확인: 새 값 쓰기와 동시 읽기 시 `rd`는 이전 값, 새 값은 그 다음 읽기부터 반영)

> `cs`(chip select)가 따로 없고 `we`/`re`가 각 포트의 enable 역할을 합니다.

`cache` 모듈이 tag/data 저장소로 이 TPSRAM을 인스턴스화합니다 (tag `4x4b`, data `4x32b`).

---

## DPSRAM (`dpsram.sv`)

**두 포트(A/B) 모두 읽기·쓰기가 가능한** true dual-port SRAM입니다. 각 포트는 매 사이클 읽기 **또는** 쓰기 중 하나를 하고, 두 포트는 같은 메모리 배열을 공유합니다.

### Ports

| Signal | Dir | Width | 설명 |
|---|---|---|---|
| `clk` | in | 1 | 공통 클럭 (주석의 `clk_b`처럼 포트별 클럭 분리도 가능한 구조) |
| `cs_a` / `cs_b` | in | 1 | 포트 A/B chip select (활성화) |
| `we_a` / `we_b` | in | 1 | 포트 A/B 쓰기 enable |
| `ad_a` / `ad_b` | in | `DEPTH_LOG` | 포트 A/B 주소 |
| `wd_a` / `wd_b` | in | `WIDTH` | 포트 A/B 쓰기 데이터 |
| `rd_a` / `rd_b` | out | `WIDTH` | 포트 A/B 읽기 데이터 (registered) |

### 동작

```verilog
always @(posedge clk)
    if      (cs_a & we_a) mem[ad_a] <= wd_a;   // 포트 A 쓰기
    else if (cs_a)        rd_a      <= mem[ad_a];  // 포트 A 읽기

always @(posedge clk)
    if      (cs_b & we_b) mem[ad_b] <= wd_b;   // 포트 B 쓰기
    else if (cs_b)        rd_b      <= mem[ad_b];  // 포트 B 읽기
```

- 각 포트는 `cs & we`면 쓰기, `cs`만이면 읽기 — **읽기와 쓰기를 동시에 하지는 못합니다** (포트당 한 동작).
- `cs=0`이면 그 포트는 idle (동작·전력 소모 없음).
- 두 포트가 **다른 주소**를 접근하면 완전히 독립적으로 동작합니다.
- **충돌(conflict) 주의:**
  - 두 포트가 같은 주소에 **동시 쓰기** → 이 코드에선 포트 B 블록이 나중에 평가되어 B 값이 남습니다(정의된 동작이 아니라 코드 순서에 의존하므로, 실제 매크로에선 금지 케이스).
  - 한 포트가 쓰는 주소를 다른 포트가 **동시 읽기** → 읽는 쪽은 옛 값을 얻습니다(read-first).

---

## TPSRAM vs DPSRAM

| | TPSRAM (1R1W) | DPSRAM (2RW) |
|---|---|---|
| 포트 수 | 2 (읽기 전용 + 쓰기 전용) | 2 (둘 다 읽기/쓰기) |
| 한 사이클 최대 | 읽기 1 + 쓰기 1 | (읽기/쓰기) × 2, 조합 자유 |
| 같은 주소 동시 쓰기 | 불가능 (쓰기 포트 1개) | 충돌 — 회피 필요 |
| 대표 용도 | FIFO 버퍼, 비디오/오디오 스트리밍, 클럭 도메인 브릿징 | 멀티코어 공유 메모리(MPSoC), 그래픽 VRAM, 네트워크 라우터/스위치 |

### 대표 용도 상세

**TPSRAM (1R1W)** — 한쪽에서 쓰고 다른 쪽에서 읽는, 방향이 고정된 스트리밍 흐름에 잘 맞습니다.
- **FIFO 버퍼:** write pointer로 쓰고 read pointer로 읽는 선입선출 구조. 1W/1R 패턴 그 자체입니다.
- **비디오/오디오 스트리밍:** 픽셀·오디오 샘플을 실시간으로 한쪽에서 쓰고 다른 쪽에서 읽어내는 처리.
- **클럭 도메인 브릿징:** 송신부와 수신부 클럭이 다를 때 사이에 두는 버퍼. (진정한 CDC는 read/write에 별도 클럭을 쓰는 dual-clock 버전으로 확장했을 때이며, 이 저장소의 RTL은 단일 클럭입니다 — 주석의 `rclk`가 그 확장 여지를 보여줍니다.)

**DPSRAM (2RW)** — 두 주체가 같은 메모리를 동시에 양방향으로 접근해야 할 때 씁니다.
- **멀티코어 공유 메모리(MPSoC):** 여러 CPU/DSP 코어가 같은 데이터를 공유하며 동시에 접근하는 SoC.
- **그래픽 VRAM:** CPU가 프레임 버퍼에 쓰는 동안 GPU가 화면 출력용으로 읽어가는 구조.
- **네트워크 라우터/스위치:** 서로 다른 인터페이스가 패킷 데이터를 동시에 참조·라우팅할 때.

### 셀 레벨 비용 (single-port 대비)

포트를 하나 더 붙인다는 점은 두 SRAM이 같으므로, **셀 트랜지스터 수는 두 경우 모두 6T → 8T**로 늘어납니다. 다만 추가되는 **BL 개수는 다릅니다.**

- single-port 셀(6T): cross-coupled inverter 4T + access transistor 2T, **WL 1개 + BL 쌍(BL/BLB)**
- 두 번째 포트 추가 시 공통: access transistor 2개 + **WL 1개 추가**
- 추가되는 BL은 포트 성격에 따라 다름:

| | 추가 WL | 추가 BL | 이유 |
|---|---|---|---|
| TPSRAM (1R1W) | 1개 | **1개** (single-ended) | 두 번째 포트가 **읽기 전용**이라 한 방향만 읽으면 됨 → differential 불필요 |
| DPSRAM (2RW) | 1개 | **1쌍(BL/BLB, 2개)** | 두 번째 포트도 **쓰기 가능**이라 differential 구동 필요 |

즉 TPSRAM의 read 포트는 single-ended read bitline **1개**만 추가되어, 8T이면서도 DPSRAM보다 셀 면적·전력에서 유리합니다. DPSRAM은 양 포트 모두 read/write를 지원하느라 BL 쌍이 온전히 추가됩니다.

**주변 회로(periphery)** 차이도 여기서 이어집니다.

- **TPSRAM (1R1W):** read 포트가 single-ended라 write driver·sense amp를 한 방향만 완전 지원하면 되고, 비대칭 최적화가 가능합니다.
- **DPSRAM (2RW):** 양쪽 포트가 모두 읽기·쓰기를 지원해야 하므로 write driver·sense amp를 **양 포트에 대칭으로 2벌** 갖춰야 하고, write-write 충돌 처리까지 필요해 주변 회로가 더 큽니다.

핵심 차이는 "쓰기 포트가 몇 개냐"입니다. 셀 트랜지스터는 둘 다 8T지만, TPSRAM은 읽기 전용 포트 덕에 BL이 1개만 늘고 주변 회로도 단순한 반면, DPSRAM은 BL 쌍 추가 + 대칭 주변 회로 + 충돌 관리 비용이 더 듭니다.

---

## Testbench (`tb_tpsram.sv`)

`tpsram`과 `dpsram`을 **하나의 TB에서 동시에** 검증합니다. `fork ... join`으로 4개 프로세스를 병렬 실행합니다.

| 프로세스 | 대상 | 동작 |
|---|---|---|
| `tpsram_write` | TPSRAM | `mem[i] = 0x10+i` 순차 기록 (i=0..7 → `0x10~0x17`) |
| `tpsram_read` | TPSRAM | 2 사이클 뒤 `ra=0..7` 순차 읽기 (쓰기와 동시 진행) |
| `dpsram_port_a` | DPSRAM 포트 A | 하위 절반(`0~3`)에 `0x20+i` 쓰고, 이후 상위 절반(`4~7`)을 읽기 |
| `dpsram_port_b` | DPSRAM 포트 B | 상위 절반(`4~7`)에 `0x30+i` 쓰고, 이후 하위 절반(`0~3`)을 읽기 |

### 검증 포인트

**TPSRAM** — 쓰기와 읽기가 겹쳐 진행되며, registered read라 `rd`는 한 사이클 지연되어 `0x10, 0x11, ... 0x17`이 순서대로 나옵니다. 1R1W가 정상 동작함을 보여줍니다.

**DPSRAM** — 포트 A는 하위(`0x20~0x23`), 포트 B는 상위(`0x34~0x37`) — **서로 겹치지 않는 주소**에 씁니다. 그런 다음 서로 **교차로 읽어**:

- 포트 A가 상위 절반을 읽으면 → 포트 B가 쓴 `0x34~0x37`
- 포트 B가 하위 절반을 읽으면 → 포트 A가 쓴 `0x20~0x23`

이렇게 두 포트가 같은 메모리를 공유한다는 점(한쪽이 쓴 값을 다른 쪽이 읽을 수 있음)을 확인합니다.

최종 DPSRAM 메모리: `mem[0..3] = 0x20~0x23` (A 기록), `mem[4..7] = 0x34~0x37` (B 기록).

---

## Reference Images

- `TPSRAM_netlist_schematic.png` — TPSRAM 합성 네트리스트 schematic
- `DPSRAM_netlist_schematic.png` — DPSRAM 합성 네트리스트 schematic
- `tb_tpsram_RTL_sim.png` — TB RTL 시뮬레이션 파형 (위 값들이 파형으로 확인됨)

![TPSRAM netlist schematic](TPSRAM_netlist_schematic.png)

![DPSRAM netlist schematic](DPSRAM_netlist_schematic.png)

![RTL simulation waveform](tb_tpsram_RTL_sim.png)
