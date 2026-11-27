# RTL CI

[English](CI.md) | **한국어**

이 레포의 GitHub Actions workflow(`.github/workflows/rtl-ci.yml`)가 무엇을, 어떻게 검사하는지 정리한 문서입니다.

## 한눈에 보기

| 항목 | 내용 |
|---|---|
| 실행 시점 | `main`에 push, 모든 pull request, 수동 실행(`workflow_dispatch`) — 단 `.v`/`.sv` 또는 `.github/` 아래 파일이 바뀐 경우에만 |
| 구성 | 프로젝트 폴더마다 job 1개 (matrix), 서로 독립적으로 병렬 실행 |
| 시뮬레이션 | Verilator로 각 프로젝트의 `tb_*.sv` 실행 → 로그로 PASS/FAIL 판정 |
| 합성 체크 | Yosys + yosys-slang으로 RTL 합성 → 합성 가능 여부, 구조 오류, 래치 검사 |
| 툴 설치 | [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (날짜 버전 고정) |

PR 화면의 Checks에 `RTL CI / <프로젝트 폴더>` 형태로 10개가 표시되고, 각 job의 **Summary** 탭에 시뮬레이션 결과와 합성 cell 수가 요약됩니다. 실패하면 원인이 annotation(`::error`)으로 표시됩니다.

## 파일 구성

```
.github/
├── workflows/rtl-ci.yml   # 트리거, 프로젝트 목록(matrix), 툴 설치
├── scripts/sim.sh         # Verilator 빌드·실행 + PASS/FAIL 판정
├── scripts/synth.sh       # Yosys 합성 + check + 래치 검사
├── CI.md                  # 이 문서 (영어)
└── CI.ko.md               # 이 문서 (한국어)
```

## 툴 버전

OSS CAD Suite는 Verilator(`master`), Yosys(`main`), yosys-slang을 매일 새로 빌드하는 **nightly 배포판**입니다. 그대로 최신을 받으면 어느 날 갑자기 결과가 바뀔 수 있어서, workflow 상단의 `OSS_CAD_SUITE_VERSION`에 날짜를 고정해 두었습니다.

```yaml
env:
  OSS_CAD_SUITE_VERSION: '2026-11-26'
```

툴을 올리고 싶을 때는 [릴리스 목록](https://github.com/YosysHQ/oss-cad-suite-build/releases)에서 날짜를 골라 이 값만 바꾸면 됩니다. 실제로 쓰인 버전은 각 job의 `Tool versions` 단계에 출력됩니다.

### 왜 Icarus가 아니라 Verilator인가

처음에는 Icarus Verilog(4-state)로 시작했지만, 이 레포의 TB 중 두 개가 Icarus의 한계에 걸렸습니다.

- `5-10-cpu_hazard_hedge`: Icarus 12는 `$isunknown({a, b})`처럼 concatenation을 넣으면 값과 상관없이 항상 1을 반환 → X가 없는데도 X 체크가 262번 FAIL
- `5-7-CRC_16_CCITT_Parallel`: 함수 안의 `automatic` 변수 선언을 지원하지 않아 컴파일 실패

최신 Verilator에서는 10개 프로젝트가 모두 수정 없이 PASS하므로 Verilator 하나로 통일했습니다. (Ubuntu apt의 Verilator 5.020은 `5-9-cpu`의 reset `for` 루프 안 배열 non-blocking 대입을 지원하지 않고, 상수 대입 최적화 버그도 있어서 사용하지 않습니다.)

## 시뮬레이션 (`sim.sh`)

각 프로젝트 폴더의 `.v`/`.sv` 파일을 모두 넣고 TB 모듈을 top으로 Verilator 빌드(`--binary --timing`) 후 실행합니다. 아래 세 조건을 **모두** 만족해야 통과입니다.

1. 시뮬레이션 프로세스의 종료 코드가 0 (`$fatal`, `$error`로 인한 `$stop` 등은 실패)
2. 로그에 `ERROR`, `FAIL`, `FATAL`, `%Error`가 없음
3. 로그에 프로젝트별 기대 패턴(`expect`)이 있음

| 프로젝트 | TB top | 기대 패턴 | 판정 수준 |
|---|---|---|---|
| 5-3-Cache | `tb_cache` | `$finish` | 끝까지 실행됨 (TB에 자체 판정 없음) |
| 5-4-TPSRAM_DPSRAM | `tb_tpsram` | `$finish` | 끝까지 실행됨 (TB에 자체 판정 없음) |
| 5-6-DDR_Controller | `tb_ddr_ctrl` | `$finish` | 끝까지 실행됨 (TB에 자체 판정 없음) |
| 5-7-CRC_16_CCITT_Parallel | `tb_CRC_16_CCITT_Parallel` | `Please: 5787` | 최종 CRC 값 일치 |
| 5-8-Hamming_decoder | `tb_Hamming_decoder` | `^PASS:` | self-checking |
| 5-9-cpu | `tb_cpu` | `^PASS:` | self-checking |
| 5-10-cpu_hazard_hedge | `tb_cpu_hazard_hedge` | `^PASS:` | self-checking |
| 6-1-sync_fifo | `tb_sync_fifo` | `^PASS:` | self-checking |
| 6-2-async_fifo | `tb_async_fifo` | `^PASS:` | self-checking |
| 6-3-apb_regs | `tb_apb_regs` | `^PASS:` | self-checking |

판정 기능이 없는 TB(Cache, TPSRAM_DPSRAM, DDR_Controller)는 "에러 없이 끝까지 돌았다"만 보장합니다. 이 TB들에 기대값 비교와 `PASS:` 출력을 넣으면 기대 패턴을 `^PASS:`로 바꿔 검사 수준을 올릴 수 있습니다.

### 2-state 시뮬레이션이라는 점

Verilator는 0/1만 표현하는 **2-state** 시뮬레이터라서 X/Z를 보지 못합니다.

- X 전파를 이용한 검사(예: reset 후 제어 신호가 X인지 확인)는 항상 통과합니다.
- reset이 빠진 레지스터도 초기값 0으로 시작하므로 드러나지 않습니다.

현재 TB들은 X가 아니라 값으로 PASS/FAIL을 판정하므로 실질적인 영향은 작습니다. Verilator에 `--fourstate` 플래그가 생기긴 했지만 아직 실험 단계(배열 미지원)라 사용하지 않습니다. 배열까지 지원되면 켜는 것을 검토합니다.

## 합성 체크 (`synth.sh`)

`tb_`로 시작하지 않는 RTL 파일을 yosys-slang(`read_slang`)으로 읽어 Yosys `synth`를 돌립니다. yosys-slang은 SystemVerilog 지원 범위가 Yosys 기본 파서보다 넓어서, 예를 들어 함수 안의 `return`(`6-2-async_fifo`)도 그대로 받아들입니다.

### 무엇을 하는가

PDK(liberty)나 SDC 없이 Yosys 내부의 **generic gate 라이브러리**(`$_AND_`, `$_XOR_`, `$_DFF_PN0_` 등)로 매핑합니다. Synopsys DC의 GTECH에 해당하는 개념입니다.

| DC 단계 | Yosys `synth` 대응 |
|---|---|
| Translation (elaborate → GTECH) | `hierarchy -check`, `proc` (always 블록 → 레지스터/MUX 네트리스트) |
| 상위 수준 최적화 | `fsm`(상태기계 추출·재인코딩), `opt`(상수 전파·불필요 로직 제거), `share`(연산기 공유), `memory`(메모리 추론) |
| Gate mapping | `techmap` (generic gate로 매핑) |
| Logic optimization | `abc -fast` (timing이 아닌 gate 수 기준 논리 최소화) |

즉 target library 없이 `elaborate` 후 GTECH 수준에서 `compile`까지 해보는 정도이며, `compile_ultra`처럼 timing을 맞추는 최적화는 없습니다.

### 실패로 잡는 것

- 문법·elaboration 에러, 없는 모듈, 포트 불일치 (`hierarchy -check`)
- 합성할 수 없는 구문
- `check -assert` 위반: 다중 드라이버, 드라이버 없이 쓰이는 신호, 조합 루프
- **래치 추론**: 조합 `always` 블록의 불완전한 `if`/`case`로 래치가 생기면 실패. 래치가 생겨도 Yosys 합성 자체는 정상 종료되므로, 합성된 netlist에서 래치 cell(`$_DLATCH_*` 등)을 찾아 따로 검사합니다.

### 잡지 못하는 것

- timing, 실제 cell 기준 면적 — cell 수는 generic gate 개수라서 DC area와 비교할 수 없습니다.
- RTL 시뮬레이션과 합성 결과의 동작 차이 (`initial` 블록, 불완전한 sensitivity list 등)
- DC만 거부하는 구문 (반대 경우도 있음)

### 프로젝트별 설정

| 프로젝트 | 합성 top | 비고 |
|---|---|---|
| 5-4-TPSRAM_DPSRAM | `tpsram`, `dpsram` | 독립된 top 두 개를 각각 합성 |
| 5-6-DDR_Controller | `ddr_ctrl` | 같은 파일의 `dram`은 TB용 메모리 모델이라 제외 |
| 5-9-cpu, 5-10-cpu_hazard_hedge | `cpu`, `cpu_hazard_hedge` | `keep` 사용 (아래 참고) |

**`keep`**: CPU top은 포트가 `clk`/`rst`뿐이라 출력이 없어서, 그대로 합성하면 모든 로직이 "쓰이지 않는 로직"으로 지워져 0 cells가 됩니다. `keep`을 주면 모든 wire에 keep 속성을 걸어 로직이 남도록 합니다.

CPU의 cell 수가 큰 것은 메모리 매크로가 없어서 InstMem·DataMem·레지스터 파일이 전부 플립플롭으로 풀리기 때문입니다 (memory compiler 없이 DC를 돌리는 것과 같은 상황).

## 새 프로젝트 추가하기

`rtl-ci.yml`의 `matrix.include`에 한 줄을 추가합니다.

```yaml
- { dir: 7-1-new_project, tb: tb_new_project, expect: '^PASS:', synth: new_project }
```

| 키 | 의미 |
|---|---|
| `dir` | 프로젝트 폴더 (RTL과 TB가 같이 있는 폴더) |
| `tb` | TB top 모듈 이름 |
| `expect` | 통과로 인정할 로그 패턴 (정규식). self-checking TB면 `^PASS:` 권장 |
| `synth` | 합성할 top 모듈 (공백으로 여러 개 가능, `''`이면 합성 생략) |
| `keep` | 출력 포트가 없는 top이면 `keep` |

TB는 성공 시 `PASS: ...`로 시작하는 줄을 출력하고, 실패 시 `$error`/`$fatal`을 쓰도록 작성하면 별도 설정 없이 판정됩니다.

## 로컬에서 실행하기

OSS CAD Suite를 설치하고 `source <설치 경로>/environment`로 환경을 잡은 뒤, 레포 루트에서 CI와 같은 스크립트를 그대로 실행할 수 있습니다.

```bash
# 시뮬레이션: <폴더> <TB top> <기대 패턴>
bash .github/scripts/sim.sh 6-1-sync_fifo tb_sync_fifo '^PASS:'

# 합성: <폴더> "<top ...>" [keep]
bash .github/scripts/synth.sh 6-1-sync_fifo sync_fifo
bash .github/scripts/synth.sh 5-9-cpu cpu keep
```

빌드 산출물은 임시 폴더에 생성되며, `BUILD_DIR=<경로>`로 위치를 지정할 수 있습니다.
