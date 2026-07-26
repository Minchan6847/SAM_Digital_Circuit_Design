# Asynchronous FIFO

서로 독립적인 두 clock(`wclk`, `rclk`) 사이에서 data를 전달하는 asynchronous FIFO입니다. Write와 read가 각자의 clock domain에서 동작하며, 두 domain을 잇는 pointer 교환은 **Gray code + 2-stage flip-flop synchronizer**로 처리합니다. Clock frequency·phase 관계가 전혀 없어도 data 무결성이 보장되는 것이 목표입니다.

- Gray code pointer + 2-flop synchronizer 기반 CDC
- Async-assert / sync-deassert reset을 각 domain에 독립 적용
- First-word fall-through(FWFT) 출력

---

## Interface

### Parameters

| Parameter | Default | 설명 |
|---|---|---|
| `DEPTH` | 8 | FIFO entry 개수. **2의 거듭제곱이어야 함** |
| `WIDTH` | 8 | Data word 비트 width |

내부 파생 constant는 다음과 같습니다.

| Constant | 값 | 설명 |
|---|---|---|
| `ADDR_W` | `$clog2(DEPTH)` | Memory address width (`DEPTH=8` → 3) |
| `PTR_W` | `ADDR_W + 1` | Pointer width. **Address보다 1비트 넓음** (`DEPTH=8` → 4) |
| `FULL_COMPARE_MASK` | `{2'b11, 0...}` | full 판정용 mask (`PTR_W=4` → `4'b1100`) |

### Ports

| Port | Direction | Domain | 설명 |
|---|---|---|---|
| `rstn` | in | 공통 | Asynchronous active-low reset |
| `wclk` | in | write | Write clock |
| `push` | in | write | Write 요청 |
| `din[WIDTH-1:0]` | in | write | Write data |
| `full` | out | write | Full (write domain registered output) |
| `rclk` | in | read | Read clock |
| `pop` | in | read | Read 요청 |
| `dout[WIDTH-1:0]` | out | read | Read data (FWFT, `empty=0`일 때 valid) |
| `empty` | out | read | Empty (read domain registered output) |

`full`은 write domain에서만, `empty`는 read domain에서만 의미를 가집니다. 각 domain의 소비자는 자기 쪽 flag만 보면 됩니다.

---

## Block Diagram

![async_fifo block diagram](async_fifo-block_diagram.png)

Synchronizer는 **받는 쪽 domain 안에** 있습니다. `wgray`를 받는 2-flop sync는 `rclk`으로, `rgray`를 받는 쪽은 `wclk`으로 동작하기 때문입니다. 그래서 domain 경계를 실제로 건너는 것은 **굵은 화살표 두 개, 즉 Gray pointer 두 개뿐**이고, 그 화살표는 곧바로 synchronizer의 입력 flop에 도착합니다. Metastability가 발생할 수 있는 지점이 이 두 곳으로 한정된다는 뜻입니다.

Data(`mem`)는 domain을 건너지 않습니다. Write domain이 쓴 자리를 read domain이 나중에 읽을 뿐입니다. Pointer 교환이 안전하면 data도 안전하다는 것이 이 구조의 논리입니다.

---

## Design

### 왜 Gray code인가

두 clock이 asynchronous이므로, 한 domain의 pointer를 다른 domain에서 sampling하는 순간 값이 바뀌고 있을 수 있습니다. **Binary counter는 한 번 증가할 때 여러 비트가 동시에 바뀝니다.** 예를 들어 `0111 → 1000`은 4비트가 전부 뒤집히는데, 이 순간 sampling하면 각 비트가 제각각 옛값/새값으로 잡혀 `1111`이나 `0000` 같은 **존재한 적 없는 값**이 나올 수 있습니다. Pointer가 엉뚱한 값으로 읽히면 full/empty 판정이 무너집니다.

Gray code는 인접한 두 값이 **정확히 한 비트만** 다릅니다.

```
bin2gray(bin) = (bin >> 1) ^ bin
```

한 비트만 바뀌므로, 전이 중에 sampling해도 결과는 **옛값 아니면 새값** 둘 중 하나입니다. 어느 쪽이 잡히든 실제로 존재했던 valid한 pointer 값이고, 최악의 경우 한 cycle 뒤처진 값일 뿐입니다. 뒤처진 값은 뒤에서 설명할 conservative 판정 덕분에 안전합니다.

`DEPTH`가 2의 거듭제곱이어야 하는 이유도 여기 있습니다. Gray code의 순환은 2의 거듭제곱 주기에서만 "마지막 값 → 첫 값"도 한 비트 차이가 되기 때문입니다.

### Pointer가 Address보다 1비트 넓은 이유

`PTR_W = ADDR_W + 1`로, 실제 memory address(`ADDR_W`)보다 한 비트를 더 씁니다. 이 extra MSB는 **몇 바퀴 돌았는지**를 기록합니다.

- Memory access에는 하위 `ADDR_W`비트만 사용: `mem[wbin[ADDR_W-1:0]]`
- 판정에는 `PTR_W`비트 전체 사용

이 비트가 없으면 empty와 full이 구분되지 않습니다. 두 경우 모두 address가 같기 때문입니다. Extra bit가 있으면 같은 address라도 write가 read보다 한 바퀴 앞섰는지(full) 같은 바퀴인지(empty)를 구분할 수 있습니다. Synchronous FIFO에서 `count` register가 하던 역할을, asynchronous FIFO에서는 이 한 비트가 대신합니다.

### empty 판정 — Read domain

```systemverilog
empty_next = (rgray_next == wgray_sync_rclk);
```

Read pointer가 synchronize된 write pointer를 따라잡으면 empty입니다. Gray code에서도 **전체 비트가 같다 = 두 pointer가 같다**이므로 단순 동등 비교로 충분합니다.

### full 판정 — Write domain

```systemverilog
localparam logic [PTR_W-1:0] FULL_COMPARE_MASK = {2'b11, {(PTR_W-2){1'b0}}};
full_next = (wgray_next == (rgray_sync_wclk ^ FULL_COMPARE_MASK));
```

Binary pointer 기준으로 full은 "**address는 같고 extra MSB만 다르다**", 즉 `wbin = rbin + 2^(PTR_W-1)`입니다. 이것을 Gray 영역으로 옮기면 왜 **상위 두 비트**를 뒤집는지 나옵니다.

XOR은 linear하므로,

```
gray_w ^ gray_r = (bin_w ^ bin_r) ^ ((bin_w ^ bin_r) >> 1)
                = 2^(PTR_W-1) ^ 2^(PTR_W-2)
                = {2'b11, 0...}          ← FULL_COMPARE_MASK
```

즉 두 Gray pointer가 상위 두 비트만 다르고 나머지가 같으면 full state입니다. 코드에서는 synchronize된 read pointer에 mask를 XOR해 "full state라면 나와야 할 write pointer 값"을 만들고, 그것과 실제 다음 write pointer를 비교합니다.

`DEPTH=8`(`PTR_W=4`, mask `4'b1100`) 기준 실제 값으로 확인하면 다음과 같습니다.

| `wbin` | `wgray` | `rbin` | `rgray` | `rgray ^ 1100` | full |
|---|---|---|---|---|:---:|
| `1000` (8) | `1100` | `0000` (0) | `0000` | `1100` | ✅ |
| `1001` (9) | `1101` | `0001` (1) | `0001` | `1101` | ✅ |
| `1100` (12) | `1010` | `0100` (4) | `0110` | `1010` | ✅ |
| `0100` (4) | `0110` | `0000` (0) | `0000` | `1100` | ❌ (4칸만 참) |

### 2-stage Flip-flop Synchronizer

```systemverilog
(* async_reg = "true" *) logic [PTR_W-1:0] rgray_meta_wclk, rgray_sync_wclk;
```

각 Gray pointer는 상대 domain에서 flip-flop 두 개를 거쳐 받습니다. 첫 번째 flop(`_meta`)은 setup/hold를 위반해 metastable state에 빠질 수 있지만, 한 clock 주기 동안 안정화될 시간을 준 뒤 두 번째 flop(`_sync`)이 다시 잡아 안정된 값을 만듭니다. Metastability를 완전히 없앨 수는 없고 **MTBF를 실용적인 수준까지 높이는** 것이 목적입니다.

`(* async_reg = "true" *)` attribute는 synthesis·place & route 도구에 "이 flop들은 synchronizer chain이니 물리적으로 가깝게 붙여라"라고 지시합니다. 두 flop 사이 routing이 길면 안정화 시간이 줄어 MTBF가 나빠지기 때문입니다.

### Flag의 Conservative 특성 (안전한 방향으로만 틀림)

Synchronize에 2 clock이 걸리므로 각 domain이 보는 상대 pointer는 항상 **과거의 값**입니다. 그 결과 두 flag는 다음과 같이 한쪽으로만 틀립니다.

| Flag | 사용하는 정보 | 오차 방향 | 결과 |
|---|---|---|---|
| `full` | 뒤처진 read pointer | 실제보다 **여유를 적게** 봄 | Read가 방금 일어났는데도 잠시 full 유지 |
| `empty` | 뒤처진 write pointer | 실제보다 **data를 적게** 봄 | Write가 방금 일어났는데도 잠시 empty 유지 |

두 오차 모두 **성능만 조금 손해 보고 정확성은 해치지 않는 방향**입니다. Full이 아닌데 full이라고 하는 건 write를 잠시 늦출 뿐이고, data가 있는데 empty라고 하는 건 read를 잠시 늦출 뿐입니다. 반대 방향(full인데 `full`이 안 뜨는 것, empty인데 `empty`가 안 뜨는 것)은 data 손상·유실로 이어지는데, 이 구조에서는 원리적으로 발생하지 않습니다.

Flag는 combinational 결과(`full_next`/`empty_next`)를 pointer와 **같은 cycle에 함께 register**하므로, flag와 pointer 사이에 추가 latency는 없습니다.

### Reset — Async assert, Sync deassert

```systemverilog
always_ff @(posedge wclk or negedge rstn)
    if (!rstn) wrst_pipe <= '0;
    else       wrst_pipe <= {wrst_pipe[0], 1'b1};
assign wrstn = wrst_pipe[1];
```

외부 `rstn`은 clock과 무관하게 즉시 assert되지만, **deassert 시점은 각 domain의 clock에 맞춰 정렬**됩니다. `rstn`이 풀리면 shift register에 1이 두 clock에 걸쳐 밀려 들어가고, 그 출력(`wrstn`/`rrstn`)이 실제 logic의 reset으로 쓰입니다.

Deassert를 synchronize하지 않으면 reset이 풀리는 순간이 clock edge와 겹쳐 recovery/removal timing을 위반하고, 일부 flop만 reset에서 빠져나오는 state가 생길 수 있습니다. Asynchronous FIFO에서는 이것이 두 pointer의 불일치로 직결되므로 특히 중요합니다. 두 domain이 각자 독립된 reset synchronizer를 갖는 것도 같은 이유입니다.

### FWFT 출력

```systemverilog
assign dout = empty ? '0 : mem[rbin[ADDR_W-1:0]];
```

읽을 data가 있으면 `pop` 없이도 선두 word가 `dout`에 나와 있습니다. 소비자는 `empty=0`을 확인하고 `dout`을 읽은 뒤 `pop`으로 pointer를 넘기면 됩니다.

Memory는 `wclk`에 synchronous로 쓰고 combinational logic으로 읽으므로, synthesis 시 block RAM이 아니라 **distributed RAM(LUT RAM)** 으로 추론되는 것이 일반적입니다. Depth가 큰 FIFO에서 block RAM을 쓰려면 registered output 방식으로 바꿔야 합니다.

### Fire 조건

```systemverilog
assign write_fire = push && !full;
assign read_fire  = pop  && !empty;
```

Synchronous FIFO의 "full state에서 push+pop 동시 처리" 같은 예외는 없습니다. 두 domain이 독립적이라 같은 cycle이라는 개념 자체가 성립하지 않고, 각자 자기 flag만 보고 판단합니다.

### Parameter 검증

`initial` block에서 `DEPTH >= 2`, **`DEPTH`가 2의 거듭제곱**(`DEPTH & (DEPTH-1) == 0`), `WIDTH >= 1`을 확인하고 위반 시 `$fatal`로 정지시킵니다. Gray pointer 구조가 2의 거듭제곱을 전제하므로, 잘못된 depth를 조용히 넘기지 않는 것이 중요합니다.

---

## Verification

`tb_async_fifo.sv`는 `DEPTH=8`, `WIDTH=8` 구성에서 두 clock을 서로소에 가까운 주기로 돌리며 검증하는 self-checking testbench입니다.

### Clock 설정

| Clock | 반주기 | 주기 |
|---|---|---|
| `wclk` | 4 ns | 8 ns |
| `rclk` | 5 ns | 10 ns |

`4 + 8n = 5 + 10m`을 만족하는 정수 해가 없으므로 **두 rising edge는 simulation 내내 절대 겹치지 않습니다.** Edge가 겹치면 simulator의 event 처리 순서에 따라 결과가 달라져 검증이 모호해지는데, 이를 원천 차단한 설정입니다. 동시에 두 domain의 phase 관계가 계속 미끄러지므로 CDC timing이 다양한 조합으로 자연스럽게 커버됩니다.

### 검증 방식

**Domain별 독립 monitor** — 자극을 주는 task와 검사하는 logic이 분리되어 있습니다.

- `always @(posedge wclk)` — DUT가 실제로 수락한 write(`push && !full`)를 감지해 `model_q`에 `push_back`하고 `accepted_writes` 증가
- `always @(posedge rclk)` — 실제로 수락된 read(`pop && !empty`)에서 `dout`을 `model_q.pop_front()`와 비교, `accepted_reads` 증가

두 monitor가 각자의 clock에서 독립적으로 동작하기 때문에, "요청했는데 수락되지 않은" 경우와 "수락된" 경우가 자동으로 구분됩니다. Reference queue가 비었는데 read가 수락되면 그 자체로 error 처리됩니다.

**`checking_enabled` gate** — Reset 구간에서는 monitor를 꺼 두어, reset synchronize가 끝나기 전의 과도 state가 오검출로 이어지지 않게 합니다.

**Backpressure 인지 driver** — `write_word()`/`read_word()`는 요청을 걸어 놓고 **수락될 때까지 기다립니다.**

```systemverilog
while (!accepted) begin
    @(posedge wclk);
    accepted = !full;
end
```

이 구조 덕분에 FIFO가 full이거나 empty일 때 자동으로 stall했다가 재개하며, CDC latency로 flag가 늦게 풀리는 상황도 자연스럽게 견딥니다.

**Timeout guard** — `#20000` 경과 시 `$fatal("TIMEOUT")`. Backpressure 대기가 영원히 풀리지 않는 버그(예: full이 영영 안 내려감)를 hang 대신 명시적 실패로 잡아냅니다.

### 검증 Scenario (실행 순서)

#### 1단계 — Reset deassert와 초기 state

`rstn`을 `#37`에 deassert합니다. 37 ns는 두 clock 어느 쪽의 rising edge와도 겹치지 않는 시점이라, **async deassert가 실제로 asynchronous하게** 들어갑니다. 이후 각 domain에서 4 clock씩 기다려 내부 reset synchronizer가 정착하게 한 뒤 검사를 활성화합니다.

| 검사 | 기대값 |
|---|---|
| `expect_full(0)` | Reset 후 full 아님 |
| `expect_empty(1)` | Reset 후 empty |

#### 2단계 — Fill: 용량까지 채우기

`0x10`부터 `0x17`까지 `DEPTH`개(8개)를 씁니다. 각 write는 수락될 때까지 대기하므로 실제로 8개가 모두 들어갑니다.

| 검사 | 기대값 |
|---|---|
| `expect_full(1)` | 정확히 `DEPTH`개에서 full assert |

#### 3단계 — full state에서 write 거부

`0xEE`를 실은 `push`를 3 clock 동안 유지한 뒤, `accepted_writes`가 **변하지 않았는지** 확인합니다. 값 자체를 검사하는 대신 monitor의 counter로 판정하므로, "요청은 갔지만 수락되지 않았다"를 정확히 검증합니다. `0xEE`가 실제로 버려졌다는 것은 이후 drain 순서에 나타나지 않음으로도 재확인됩니다.

#### 4단계 — CDC latency를 통과하는 read·write 교환

```systemverilog
fork
    read_word();
    write_word(8'h80);
join
```

이 단계가 이 testbench의 핵심입니다. Full state에서 read domain이 한 word를 빼내지만, **write domain의 `full`은 즉시 내려가지 않습니다.** Read pointer가 Gray code로 encode되고 2-stage synchronizer를 통과해 write domain에 도달해야 비로소 `full`이 deassert됩니다.

`write_word(8'h80)`은 그동안 요청을 유지한 채 대기하다가, `full`이 풀리는 순간 수락됩니다. 즉 **CDC round-trip latency가 실제로 존재하고, 그것이 끝나면 정상 복구된다**는 것을 동시에 확인합니다. 교환이 끝나면 occupancy는 다시 `DEPTH`입니다.

#### 5단계 — Drain: 순서 보존 확인

`DEPTH`개를 읽어 비웁니다. 나오는 순서는 `0x11` … `0x17` 다음 4단계에서 넣은 `0x80`이어야 하며, monitor가 매 read마다 reference queue와 대조합니다.

| 검사 | 기대값 |
|---|---|
| `expect_empty(1)` | 전부 빠져나온 뒤 empty |

#### 6단계 — empty state에서 read 거부

`pop`을 3 clock 유지한 뒤 `accepted_reads`가 변하지 않았는지 확인합니다. 3단계의 대칭 case입니다.

#### 7단계 — Random 동시 traffic

```systemverilog
fork
    writer_thread : 48회 write, 매회 0–2 wclk 간격
    reader_thread : 48회 read,  매회 0–3 rclk 간격
join
```

두 thread가 서로 다른 random 간격으로 동시에 동작합니다. Read 쪽 평균 간격이 더 길고 `rclk`이 더 느리므로 FIFO는 자주 full이 되고, write 쪽이 backpressure로 stall했다 재개하는 상황이 반복됩니다. 이 구간에서 자연히 커버되는 것들은 다음과 같습니다.

- Pointer wraparound (48회 > `DEPTH`=8, 여러 바퀴 순환)
- 양방향 CDC synchronize의 반복 발생
- full/empty 경계를 오가는 다양한 phase 조합
- Backpressure 하에서의 data 순서 보존

#### 8단계 — 종료 정합성 검사

Traffic 종료 후 4 `rclk` 대기하고 세 가지를 확인합니다.

| 검사 | 의미 |
|---|---|
| `model_q.size() == 0` | 쓴 data가 하나도 남김없이 읽혔는가 |
| `accepted_writes == accepted_reads` | 수락된 transaction 수가 양쪽에서 일치하는가 |
| `expect_empty(1)` | 최종 state가 empty인가 |

세 검사가 함께 통과해야 data 유실도 중복도 없었음이 확정됩니다. 모두 통과하면 `PASS: async_fifo completed all checks`, 하나라도 실패하면 error 수와 함께 `$fatal`입니다.

### Coverage 요약

| 검증 항목 | 해당 단계 |
|---|---|
| Reset deassert 후 초기 flag | 1 |
| full assert 경계 | 2 |
| full state에서 write 거부 | 3 |
| CDC latency 후 full deassert 및 write 재개 | 4 |
| empty assert 경계 | 5 |
| empty state에서 read 거부 | 6 |
| Pointer wraparound | 7 |
| 양방향 CDC 반복 synchronize | 4, 7 |
| Backpressure 하 data 순서 보존 | 5, 7 |
| Data 유실·중복 없음 | 8 |
| Hang 방지 | Timeout guard |

---

## Files

- `async_fifo.sv` — Asynchronous FIFO RTL (Gray pointer, 2-flop synchronizer, FWFT)
- `tb_async_fifo.sv` — self-checking testbench (domain별 monitor + backpressure driver + random traffic)
- `async_fifo-block_diagram.png` — 위 block diagram
- `async_fifo-netlist_schematic.png` — 합성 netlist schematic
- `tb_async_fifo-RTL_sim-1.png` / `-2.png` / `-3.png` — TB RTL simulation waveform

---

## Reference Images

### Netlist Schematic

![async_fifo netlist schematic](async_fifo-netlist_schematic.png)

### RTL Simulation Waveforms

![tb_async_fifo RTL simulation 1](tb_async_fifo-RTL_sim-1.png)

![tb_async_fifo RTL simulation 2](tb_async_fifo-RTL_sim-2.png)

![tb_async_fifo RTL simulation 3](tb_async_fifo-RTL_sim-3.png)
