# Synchronous FIFO

단일 클럭 동기식 FIFO(First-In First-Out) 버퍼입니다. 하나의 `clk`로 push(쓰기)와 pop(읽기)을 처리하며, 파라미터로 깊이·폭·almost-full/almost-empty 임계값을 조정할 수 있습니다. First-word fall-through(FWFT) 방식이라 읽을 데이터가 있으면 pop을 기다리지 않고 `dout`에 미리 나와 있습니다.

- **Tool:** Quartus-lite-20.1.0.711-windows
- 카운터 기반 occupancy 추적 + 순환(circular) 포인터 구조

---

## Interface

### Parameters

| 파라미터 | 기본값 | 설명 |
|---|---|---|
| `DEPTH` | 8 | FIFO 엔트리 개수 |
| `WIDTH` | 32 | 데이터 워드 비트 폭 |
| `AF_LEVEL` | 1 | almost-full 여유 임계값. `count >= DEPTH - AF_LEVEL`일 때 `a_full` 어서트 |
| `AE_LEVEL` | 1 | almost-empty 임계값. `count <= AE_LEVEL`일 때 `a_empty` 어서트 |

### Ports

| 포트 | 방향 | 설명 |
|---|---|---|
| `clk` | in | 클럭 |
| `rstn` | in | 비동기 active-low 리셋 |
| `push` | in | 쓰기 요청 |
| `pop` | in | 읽기 요청 |
| `din[WIDTH-1:0]` | in | 쓰기 데이터 |
| `dout[WIDTH-1:0]` | out | 읽기 데이터 (FWFT, `empty=0`일 때만 유효) |
| `full` | out | 가득 참 |
| `empty` | out | 비어 있음 |
| `a_full` | out | almost-full |
| `a_empty` | out | almost-empty |

---

## Block Diagram

```mermaid
flowchart LR
    push["push"] --> FIRE
    pop["pop"] --> FIRE
    full -.-> FIRE
    empty -.-> FIRE

    FIRE["fire 판정<br/>push_fire / pop_fire"]

    FIRE -->|push_fire| WR["wr_ptr<br/>순환 카운터"]
    FIRE -->|pop_fire| RD["rd_ptr<br/>순환 카운터"]
    FIRE --> CNT["count<br/>occupancy"]

    din["din"] --> MEM["mem 배열<br/>DEPTH x WIDTH"]
    WR -->|write addr| MEM
    RD -->|read addr| MEM
    MEM --> DOUT["dout<br/>FWFT"]
    empty -.->|0 강제| DOUT

    CNT --> FLAG["플래그 비교기"]
    FLAG --> full["full"]
    FLAG --> empty["empty"]
    FLAG --> af["a_full"]
    FLAG --> ae["a_empty"]
```

실선은 데이터, 점선은 되먹임되는 상태 신호입니다. 플래그가 전부 `count` 하나에서 나오고, 그 플래그가 다시 fire 판정으로 되돌아가는 고리가 이 설계의 뼈대입니다.

---

## Design

### 상태 추적

포인터 두 개와 카운터 하나로 상태를 관리합니다.

- `wr_ptr` — 다음에 쓸 위치. push가 실제로 일어날 때(`push_fire`) 증가하고, `DEPTH-1`에서 0으로 되돌아갑니다(순환).
- `rd_ptr` — 다음에 읽을 위치. pop이 실제로 일어날 때(`pop_fire`) 같은 방식으로 순환합니다.
- `count` — 현재 저장된 워드 수. full/empty/almost 플래그가 전부 이 값 하나에서 파생됩니다.

`wr_ptr == rd_ptr`은 "비어 있음"과 "가득 참"에서 모두 성립하기 때문에 포인터만으로는 둘을 구분할 수 없습니다. 그래서 별도의 `count`를 두어 두 상태를 명확히 구분합니다.

플래그는 모두 조합 논리입니다.

```
full    = (count == DEPTH)
empty   = (count == 0)
a_full  = (count >= DEPTH - AF_LEVEL)
a_empty = (count <= AE_LEVEL)
```

### push_fire / pop_fire

요청 신호(`push`/`pop`)가 실제 동작으로 이어지는지는 별도로 판단합니다.

- `pop_fire = pop && !empty` — 비어 있으면 pop 요청은 무시됩니다.
- `push_fire = push && (!full || pop_fire)` — 가득 차 있으면 push는 무시되지만, **같은 사이클에 유효한 pop이 일어나면** 한 칸이 비므로 push도 받아들입니다.

이 "full 상태에서 push+pop 동시 처리" 덕분에 가득 찬 상태에서도 매 사이클 한 워드를 교체(pop 후 push)하며 스루풋을 유지할 수 있습니다.

요청 조합과 FIFO 상태에 따른 동작을 정리하면 다음과 같습니다.

| `push` | `pop` | 상태 | `push_fire` | `pop_fire` | `count` |
|:---:|:---:|---|:---:|:---:|:---:|
| 0 | 0 | — | 0 | 0 | 유지 |
| 1 | 0 | 여유 있음 | 1 | 0 | +1 |
| 1 | 0 | **full** | 0 | 0 | 유지 (push 무시) |
| 0 | 1 | 데이터 있음 | 0 | 1 | −1 |
| 0 | 1 | **empty** | 0 | 0 | 유지 (pop 무시) |
| 1 | 1 | 중간 상태 | 1 | 1 | 유지 (동시 통과) |
| 1 | 1 | **full** | 1 | 1 | 유지 (**교체**) |
| 1 | 1 | **empty** | 1 | 0 | +1 (push만 수용) |

굵게 표시한 세 행이 경계 조건이고, 테스트벤치가 집중적으로 검증하는 지점이기도 합니다.

### First-word fall-through

`dout = empty ? '0 : mem[rd_ptr]`로, 읽을 데이터가 있으면 pop 어서트를 기다리지 않고 항상 선두 워드가 출력에 나와 있습니다. 소비자는 `empty=0`을 확인하고 `dout`을 곧바로 읽은 뒤 pop으로 포인터를 넘기면 됩니다(표준 FIFO의 "pop 후 다음 사이클에 데이터 등장"과 다른 점).

### 파라미터 검증

`initial` 블록에서 `DEPTH >= 1`, `WIDTH >= 1`, `AF_LEVEL <= DEPTH`, `AE_LEVEL <= DEPTH`를 확인하고, 위반 시 `$fatal`로 정지시켜 잘못된 파라미터 조합을 조기에 잡습니다.

---

## Verification

`tb_sync_fifo.sv`는 `DEPTH=4`, `WIDTH=8`, `AF_LEVEL=1`, `AE_LEVEL=1` 구성에서 참조 모델과 DUT를 매 트랜잭션 비교하는 self-checking 테스트벤치입니다.

### 검증 방식

**참조 모델** — SystemVerilog 큐 `model_q[$]`가 골든 모델입니다. DUT와 무관하게 같은 자극을 받아 독립적으로 갱신되고, 매 사이클 DUT와 대조됩니다.

**`cycle(push, pop, din)` 태스크** — 트랜잭션 하나를 처리하는 단위이며, 순서는 다음과 같습니다.

1. `@(negedge clk)`에서 입력을 인가 (셋업 여유 확보, 클럭 에지와 분리)
2. 인가 직전 상태로 `push_fire`/`pop_fire`를 참조 모델 쪽에서도 계산 — RTL과 같은 식(`pop && count!=0`, `push && (count!=DEPTH || pop_fire)`)을 TB에 독립 구현해 둠
3. `@(posedge clk)`에서 `dout`을 샘플링. `pop_fire`가 예상되면 `model_q.pop_front()` 값과 비교 → 불일치 시 `data mismatch` 에러
4. `push_fire`가 예상되면 모델 큐에 `push_back`
5. `#1` 후 `check_flags()` — `full`/`empty`/`a_full`/`a_empty` 네 플래그를 모델 큐 크기 기준 기댓값과 각각 대조

**타임아웃 가드** — 별도 `initial`에서 `#5000` 경과 시 `$fatal("TIMEOUT")`으로 행(hang)을 방지합니다.

**종료 판정** — `error_count == 0`이면 `PASS: sync_fifo completed all checks`, 아니면 에러 수와 함께 `$fatal`로 실패 처리합니다.

### 검증 시나리오 (실행 순서)

리셋은 `rstn=0`으로 3클럭 유지 후 negedge에서 해제하고, 곧바로 `check_flags()`로 초기 상태(`count=0` → `empty=1`, `a_empty=1`)를 확인합니다. 이후 24개 트랜잭션이 순서대로 진행됩니다.

#### 1단계 — Fill: 플래그 전이 경계 확인

빈 상태에서 가득 찰 때까지 연속 push하며, 각 플래그가 정확한 occupancy에서 바뀌는지 확인합니다.

| # | 호출 | 동작 | count | 확인 포인트 |
|:---:|---|---|:---:|---|
| 1 | `cycle(1,0,8'h10)` | push 10 | 1 | `empty` 해제 |
| 2 | `cycle(1,0,8'h11)` | push 11 | 2 | `a_empty` 해제 (2 > `AE_LEVEL`) |
| 3 | `cycle(1,0,8'h12)` | push 12 | 3 | `a_full` 어서트 (3 >= `DEPTH-AF_LEVEL`) |
| 4 | `cycle(1,0,8'h13)` | push 13 | 4 | `full` 어서트 |

#### 2단계 — Full 경계: push 무시 / 동시 요청 교체

| # | 호출 | 동작 | count | 확인 포인트 |
|:---:|---|---|:---:|---|
| 5 | `cycle(1,0,8'hEE)` | **무시** | 4 | full에서 `push_fire=0`. 0xEE는 유실되어야 하며, 이후 pop 순서에 나타나지 않음으로 검증 |
| 6 | `cycle(1,1,8'h14)` | pop 10 **＋** push 14 | 4 | full에서 동시 요청 → `push_fire=1`, `pop_fire=1`. occupancy 유지하며 **교체** |

6번은 이 설계의 핵심 케이스입니다. 일반적인 FIFO라면 full일 때 push를 거부하지만, 여기서는 같은 사이클의 pop이 자리를 비우므로 받아들입니다.

#### 3단계 — Drain: 순서 보존 및 플래그 역방향 전이

| # | 호출 | 동작 | count | 확인 포인트 |
|:---:|---|---|:---:|---|
| 7 | `cycle(0,1,'0)` | pop 11 | 3 | |
| 8 | `cycle(0,1,'0)` | pop 12 | 2 | `a_full` 해제 |
| 9 | `cycle(0,1,'0)` | pop 13 | 1 | `a_empty` 어서트 |
| 10 | `cycle(0,1,'0)` | pop 14 | 0 | `empty` 어서트 |

10번에서 마지막으로 나오는 값이 6번에 넣은 `0x14`라는 점이 중요합니다. 5번의 `0xEE`가 실제로 버려졌고, 6번의 push는 큐 맨 뒤에 제대로 들어갔음을 함께 증명합니다.

#### 4단계 — Empty 경계: pop 무시 / 동시 요청 push 우선

| # | 호출 | 동작 | count | 확인 포인트 |
|:---:|---|---|:---:|---|
| 11 | `cycle(0,1,'0)` | **무시** | 0 | empty에서 `pop_fire=0`. `rd_ptr` 불변 |
| 12 | `cycle(1,1,8'h30)` | push 30만 | 1 | empty에서 동시 요청 → `push_fire=1`, `pop_fire=0`. 쓴 값을 같은 사이클에 그대로 빼내지 않음 |
| 13 | `cycle(0,1,'0)` | pop 30 | 0 | 12번의 데이터가 정상 저장됐는지 확인 |

#### 5단계 — Wraparound: 포인터 순환

`DEPTH=4`이므로 포인터는 3에서 0으로 되돌아갑니다. push와 pop을 섞어 진행해 `wr_ptr`과 `rd_ptr`이 **서로 다른 시점에 독립적으로** wrap하도록 만든 구간입니다.

| # | 호출 | 동작 | count | 포인터 |
|:---:|---|---|:---:|---|
| 14 | `cycle(1,0,8'h20)` | push 20 → `mem[2]` | 1 | `wr_ptr` 2→3 |
| 15 | `cycle(1,0,8'h21)` | push 21 → `mem[3]` | 2 | `wr_ptr` 3→0 **wrap** |
| 16 | `cycle(1,0,8'h22)` | push 22 → `mem[0]` | 3 | `a_full` 어서트 |
| 17 | `cycle(0,1,'0)` | pop 20 | 2 | `rd_ptr` 2→3 |
| 18 | `cycle(1,0,8'h23)` | push 23 → `mem[1]` | 3 | |
| 19 | `cycle(1,0,8'h24)` | push 24 → `mem[2]` | 4 | `full` 어서트 |
| 20 | `cycle(0,1,'0)` | pop 21 | 3 | `rd_ptr` 3→0 **wrap** |
| 21 | `cycle(0,1,'0)` | pop 22 | 2 | |
| 22 | `cycle(0,1,'0)` | pop 23 | 1 | |
| 23 | `cycle(0,1,'0)` | pop 24 | 0 | `empty` 어서트 |

랩어라운드가 두 번(15번 쓰기, 20번 읽기) 일어나는 동안에도 `0x20 → 0x24` 순서가 그대로 유지되는지가 이 단계의 판정 기준입니다. 물리적 주소는 뒤섞이지만 논리적 FIFO 순서는 보존되어야 합니다.

### 커버리지 요약

| 검증 항목 | 해당 트랜잭션 |
|---|---|
| 리셋 후 초기 플래그 | 리셋 직후 |
| 네 플래그의 상승/하강 경계 | 1~4, 7~10 |
| full에서 push 무시 | 5 |
| full에서 동시 push+pop (교체) | 6 |
| empty에서 pop 무시 | 11 |
| empty에서 동시 push+pop (push 우선) | 12 |
| 데이터 순서 보존 (FIFO 성질) | 7~10, 20~23 |
| `wr_ptr` 랩어라운드 | 15 |
| `rd_ptr` 랩어라운드 | 20 |
| 행(hang) 방지 | 타임아웃 가드 |

---

## Files

- `sync_fifo.sv` — FIFO RTL (파라미터화, FWFT)
- `tb_sync_fifo.sv` — self-checking 테스트벤치 (참조 모델 + 경계 조건 + 타임아웃)
- `sync_fifo-netlist_schematic.png` — 합성 네트리스트 schematic
- `tb_sync_fifo-RTL_sim.png` — TB RTL 시뮬레이션 파형

---

## Reference Images

### Netlist Schematic

![sync_fifo netlist schematic](sync_fifo-netlist_schematic.png)

### RTL Simulation Waveform

![tb_sync_fifo RTL simulation](tb_sync_fifo-RTL_sim.png)
