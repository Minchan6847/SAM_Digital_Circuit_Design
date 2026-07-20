# SAM_Digital_Circuit_Design

[삼코치] 디지털 회로설계 실무 : Computer Architecture 와 SoC 프로토콜 Digital IP 설계하기 - 실습

Computer Architecture와 SoC 프로토콜의 핵심 Digital IP들을 직접 RTL로 설계하고 검증한 실습 모음입니다. 메모리 계층(캐시·SRAM·DRAM)부터 저장장치 데이터 무결성(CRC·ECC)까지, 각 모듈을 설계·시뮬레이션·합성하고 문서로 정리했습니다.

- **Tool:** Quartus-lite-20.1.0.711-windows
- 각 폴더의 `README.md`에 동작 원리, 블록/상태 다이어그램, 파형, 검증 결과가 정리되어 있습니다.

---

## Projects

### 메모리 계층 (Memory Hierarchy)

| 프로젝트 | 설명 |
|---|---|
| [5-3-Cache](5-3-Cache) | Direct-mapped write-back 캐시. `req`/`ack` 핸드셰이크로 가변 지연을 처리하고, hit/miss·write-back·open-page 동작을 구현. |
| [5-4-TPSRAM_DPSRAM](5-4-TPSRAM_DPSRAM) | Two-port(1R1W)·Dual-port(2RW) SRAM 모델. 포트 구성 차이와 셀(6T→8T)·주변 회로 비용까지 비교. |
| [5-6-DDR_Controller](5-6-DDR_Controller) | DDR4-style DRAM 컨트롤러. FSM(ACT→WR/RD→PRE), 타이밍 파라미터, DQS 스트로브, BL8 버스트, open-page 정책 구현. |

### 데이터 무결성 (Data Integrity — NAND)

| 프로젝트 | 설명 |
|---|---|
| [5-7-CRC_16_CCITT_Parallel](5-7-CRC_16_CCITT_Parallel) | CRC-16-CCITT byte-parallel 생성기. 오류 **검출**용. 손계산·비트루프·LUT·직렬 LFSR·병렬 unroll 5가지 구현 비교 포함. |
| [5-8-Hamming_decoder](5-8-Hamming_decoder) | Hamming (21,16) SEC 인코더/디코더. 오류 **정정**용 ECC. syndrome으로 오류 위치를 찾아 단일 비트 정정. |

> **검출 → 정정 흐름:** CRC(5-7)는 오류가 있는지 *검출*만 하고, Hamming/ECC(5-8)는 한발 더 나아가 오류를 *정정*합니다. NAND flash 데이터 무결성의 두 축을 이룹니다.

---

## 공통 사항

- 각 프로젝트는 RTL 소스(`.v`/`.sv`), 테스트벤치, 합성 네트리스트 schematic, RTL 시뮬레이션 파형으로 구성됩니다.
- 문서의 다이어그램은 Mermaid로 작성되어 GitHub에서 바로 렌더링됩니다.
- 폴더 번호는 강의 커리큘럼 순서를 따릅니다.
