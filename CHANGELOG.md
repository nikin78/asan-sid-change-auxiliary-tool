# 변경 이력 (CHANGELOG)

이 프로젝트는 [Semantic Versioning (SemVer)](https://semver.org/) 규칙(`MAJOR.MINOR.PATCH`)을 따릅니다.
단일 버전 기준 파일은 [VERSION](VERSION)이며, `tools/Build-Tool.ps1`가 빌드 시 `SID_Change_Aux_Tool.bat`에 버전·빌드 일자·Git 커밋을 자동 주입·검증합니다.

* **MAJOR:** 프로젝트 목적·아키텍처의 큰 전환
* **MINOR:** 하위 호환되는 신규 기능 추가
* **PATCH:** 버그 수정, 안정화, 소규모 UI/UX 개선

---

## [v2.2.0] - 2026-11-26

### 전면 개편 (UI/UX · 아산병원 데스크톱 디자인 시스템 적용)
* **서울아산병원 현장 유틸리티 디자인 시스템(`asan-desktop-ui`) 전면 적용 (`modules/06_Gui_WinForms.ps1`):**
  * **4영역 고정 셸(`1040×720` 기본 / `960×640` 최소, DPI 100~150% 안전):** `#005658` 딥 틸 2단 헤더 + 자체 GDI+ 벡터 심볼/창 아이콘(저작권 로고 미사용·HICON 누수 없음) + `#F68B1F` 오렌지 포인트 라인 + `#EDF3F3` 메타 바(`PC명 · 모델명 · OS · 부팅 방식 · SID + 즉각 피드백 SID 복사`), 조건부 치명 경고 배너, `OwnerDrawFixed` 번호형 탭(`Alt+1`/`Alt+2`), 기본 접힘 다크 로그 콘솔(`38px ↔ 114px`, `New-PaddedTextBoxPanel` 여백 래퍼).
  * **초보자 친화 워크플로 재구성 및 혼잡도 제거:** 2개로 겹쳐 있던 물리 USB / NVRAM 표를 **단일 통합 USB 부팅 표(`DataGridView`, `#0B4F51` 헤더 · `32px` 행)**로 통합하고, `1단계` / `2단계` 배지 카드·이상 없을 시 1단계 접기 기능·사후 작업 4열 상태 메트릭 타일 도입.
  * **비활성 점선 버튼 + 부모 라우팅 사유 툴팁:** 모든 비활성 버튼을 점선(`Dash`) 테두리·무채색으로 직접 렌더링하고, 마우스 오버 시 비활성 사유와 해결 방법을 즉시 안내. 화면당 핵심 `Primary(#006769)` 버튼 최대 1개 원칙 적용.
  * **상용 한국어 UX 라이팅 전면 개편:** 모든 GUI 안내·버튼·상태 문구에서 `[대괄호]`, `(부가 괄호)`, `!`, `->` 개발자 스크립트체를 제거하고 2~3어절 행동 중심 버튼 문구와 평서문 안내로 통일 (`modules/01`, `02`, `03`, `05`, `06`).
  * **오류 자동 진단 리포트 저장 및 민감정보 마스킹:** 작업 오류 발생 시 진단 리포트를 자동 구성해 로컬 폴더 저장 또는 클립보드 복사를 안내하며, 민감 패턴을 `[REDACTED]`로 자동 마스킹.
  * **비동기 프린터 스풀러 초기화:** 별도 백그라운드 Runspace + `Timer` 폴링으로 전환해 초기화 중 UI 멈춤(`응답 없음`) 현상을 제거하고 실시간 로그 표시.
* **자동 레이아웃 감사 및 시각 검증 추가 (`tools/Test-Tool.ps1`):** `1040×720` / `960×640`(확장 로그 포함) 전 탭 버튼 잘림·겹침·최소 그리드 높이·비활성 툴팁·상용 문구·`Anchor=Right` 금지 자동 감사 추가.

---

## [v2.1.1] - 2026-11-26

### 버그 수정 (Fixed)
* **WinForms GUI `X` 버튼 종료 예외(`null 값 식에서 메서드를 호출할 수 없습니다`) 및 버튼 이벤트 클로저 버그 수정:** `New-SidAuxMainForm` 반환 후 PowerShell 동적 스코프 소멸로 인해 `OnFormClosed` 및 클릭 이벤트 핸들러 내부 변수가 `$null`이 되던 결함을 해결. 모든 UI 컨트롤·폰트·상태를 단일 `$ui` 컨텍스트(`$form.Tag`)로 통합하고 `.GetNewClosure()` 및 null-safe `Dispose()` 가드 적용.
* **WinForms ListView 기본 컬럼 폭 최적화:** 기본 창 크기에서 불필요한 가로 스크롤바가 생기지 않도록 디스크/USB/NVRAM/프린터 컬럼 폭 조정.

### 개선 (Changed)
* **체계적 버저닝 파이프라인 도입:**
  * 루트 `VERSION` 단일 기준 파일 및 `CHANGELOG.md` 신설.
  * `tools/Build-Tool.ps1`에 SemVer 검증, `-Bump Major|Minor|Patch` 옵션, 빌드 시 `__TOOL_VERSION__` / `__BUILD_DATE__` / `__BUILD_COMMIT__` 자동 주입 및 `-VerifyOnly` 버전 일치 검증 추가.
  * `tools/Test-Tool.ps1`에 `VERSION`/`CHANGELOG.md` 정합성 검사 및 실제 WinForms `ShowDialog()`→`Close()`·`PerformClick()` 이벤트 클로저 회귀 테스트(`UnhandledExceptionMode::ThrowException`) 추가.

---

## [v2.1.0] - 2026-11-26

### 추가 (Added)
* **WinForms 데스크톱 GUI (`modules/06_Gui_WinForms.ps1`):** 순수 GAC 어셈블리 기반(C# 임시 컴파일·외부 DLL 없음), 사전/사후 2탭 구조, 물리 USB 및 NVRAM 매칭 표, BIOS 교차 검증 상세 팝업(클립보드 복사), WinPE 비상 복구 GUI, GUI 불가/CLI(`--cli`) 환경 콘솔 자동 폴백.
* **다중 신호 BIOS 교차 검증 엔진 (`modules/03_Vendor_Bios_Diagnostics.ps1`):**
  * 부팅 모드 3신호(`bcdedit` + 레지스트리 + 부팅 디스크 GPT/MBR), Secure Boot 3신호(`Confirm-SecureBootUEFI` + 레지스트리 + WMI, 예외 시 무음 OFF 오탐 차단).
  * HP `HP_BIOSSetting`+`HP_BIOSEnumeration` Primary/Legacy 분리(`Legacy USB Boot=Disable` 오탐 제거), Dell 타입 안전 enum 조회 및 `biosattributes` 폴백.
  * WMI vs NVRAM 충돌 감지(`Conflict` 판정) 및 상황별 권장 액션 가이드 엔진(`Get-PreSidGuidance` / `Get-PostSidGuidance`).
* PowerShell `-STA` 실행 래퍼 보강.

---

## [v2.0.1] - 2026-11-25

### 개선 및 수정 (Changed / Fixed)
* **3종 실행 환경(쓰기 금지 USB / 로컬 / 공유폴더) 재귀 리뷰 및 하드닝:**
  * 공유폴더(`\\서버\공유`)·매핑 드라이브(`Z:\`) 실행 시 UAC Split-Token 경로 소실 방지를 위한 자동 로컬 스테이징 + RAM 로드 직후 임시 파일 자동 삭제.
  * WinPE(`X:`) 및 `LanmanServer` 중지 환경 무한 UAC 루프 제거(`fltmc` 폴백), Base64 `-EncodedCommand` 특수문자 경로 대응.
  * `Get-BusyDriveLetters`로 매핑 드라이브 `Z:` 충돌 방지, 읽기 전용 디스크 `READONLY_PROTECTED` 보호, Ventoy/Rufus 숨김 FAT12·FAT16(`MbrType 1,4,6`) 지원.
  * 한국어 `diskpart` 파서 보강, 동일 브랜드 USB vs 내장 SSD 교차 오매칭 방지, `Get-NetFirewallRule` 폴백·`PrinterQueryError`·`Spooler` 중지 시 `[판별 보류]` 표시 보강.

---

## [v2.0.0] - 2026-11-25

### 변경 (Changed)
* 배포 파일명을 `USB_Reboot.bat` → `SID_Change_Aux_Tool.bat`로 개편하고 **WinPE 기반 SID 변경 사전·사후 통합 보조 툴**로 확장.
* 사전 작업 STEP 1(GPT EFI + 구형 MBR 활성 부트로더 비파괴 정리, `IGNORE` 확인 강제) → STEP 2(BIOS 진단 및 USB 부팅) 통합 흐름 구축.
* 사후 작업 프린터 스풀러 리셋 및 호스트(메인 프린터 PC)/클라이언트 상태 진단 모듈 추가.
* 경량 WinPE `diskpart` 폴백, OEM 안전 네이티브 실행기(`Invoke-NativeOem`), `tools/Build-Tool.ps1` / `tools/Test-Tool.ps1` 자동 검증 체계 구축.

---

## [v1.0.0] - 2026-11-24

### 추가 (Added)
* 초기 단일 하이브리드 `.bat` 유틸리티(`USB_Reboot.bat`): UEFI USB 일회성 재부팅, Gate 0 다중 디스크 GPT EFI 충돌 탐지·비활성화, Samsung/HP/Dell WMI 진단, WinPE(`X:`) 비상 모드.
