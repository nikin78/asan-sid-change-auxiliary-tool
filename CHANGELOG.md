# 변경 이력 (CHANGELOG)

이 프로젝트는 [Semantic Versioning (SemVer)](https://semver.org/) 규칙(`MAJOR.MINOR.PATCH`)을 따릅니다.
단일 버전 기준 파일은 [VERSION](VERSION)이며, `tools/Build-Tool.ps1`가 빌드 시 `SID_Change_Aux_Tool.bat`에 버전·빌드 일자·Git 커밋을 자동 주입·검증합니다.

* **MAJOR:** 프로젝트 목적·아키텍처의 큰 전환
* **MINOR:** 하위 호환되는 신규 기능 추가
* **PATCH:** 버그 수정, 안정화, 소규모 UI/UX 개선

---

## [v2.4.0] - 2026-11-29

### 추가 및 대폭 개선 (Added / Overhauled)
* **다중 파티션 WinPE 부팅 디스크(`PhoenixPE Builder`, `DISM++`, `Rufus UEFI:NTFS`, `Bootice`, `Ventoy`) 인식 엔진 전면 개편 (`modules/01`, `02`, `04`):**
  * **GPT 복구 GUID(`{de94bba4-06d1-4d40-a16a-bfd50179d6ac}`) 스킵 버그 제거:** `DISM++`, `DiskPart`, `Bootice` 등이 USB의 숨김 EFI·WinPE 파티션에 부여하는 복구 GUID 파티션을 통째로 건너뛰어 `(일반 내장 공간)`만 남고 부팅 디스크 미인식으로 빠지던 치명 결함을 해결.
  * **숨김 MBR 파티션 타입 확장 및 무마운트 VBR 파일시스템 판별 (`Get-RawPartitionFsHint`):** `Bootice` EISA 숨김 EFI(`0x12`), 숨김 NTFS(`0x17`), WinRE(`0x27`)를 추가하고, `Get-Volume`이 `$null`을 반환하는 숨김 파티션도 디스크 오프셋 읽기 전용 512바이트 VBR 시그니처(`FAT12/16/32`, `NTFS`, `exFAT`)로 정확히 식별.
  * **정밀 EFI 부트로더 탐색 및 우선순위 점수화 (`Find-BestEfiBinaryOnRoot`):** `\EFI\BOOT\BOOTX64.EFI`, `\EFI\Microsoft\Boot\bootmgfw.efi`, `\EFI\BOOT\grubx64.efi`, `\bootmgr.efi`+`BCD`, 2단계 `\EFI\*\*.efi` 커스텀 로더까지 전수 탐색하되(`memtest.efi`·`Rufus` 드라이버 제외), 전용 `FAT` EFI 파티션(예: `UEFI_NTFS`)을 `NTFS`/`exFAT`보다 우선 선택하도록 점수화(`exFAT` 데이터 파티션 단독 오탐 방지).
  * **`DISM++`/`bcdboot` 계열 `"Windows Boot Manager"` USB NVRAM 항목 매칭 허용 (`Find-MatchedUsbNvramEntries`):** 파티션 경로(`device`)가 내장 디스크가 아닌 연결된 USB 파티션과 정확히 일치할 때는 설명이 `"Windows Boot Manager"`라도 제외하지 않고 1단계(Tier 1) 정확 일치로 매칭.
* **자체 실행(`(EFI) + (부팅파일) + (일반 내장 공간)` 구조에서 실행) USB 자동 인지 (`Get-SelfHostLocationInfo`):**
  * 다중 파티션 USB의 일반 저장 공간 파티션에 `SID_Change_Aux_Tool.bat`을 넣어 실행할 때 자기 자신의 물리 디스크를 `실행 USB`(`IsSelfHostUsb`)로 최우선 정렬·자동 선택하고, 고정형(`Fixed`)으로 잡히는 외장 SSD/USB도 내장 디스크로 오분류되지 않도록 보호.
  * 목록에 `모델명 (WinPE 볼륨 라벨)`과 확인된 EFI 파티션 문자를 함께 표시해 직관성 향상.
* **NVRAM 미등록(Hot-Plug) WinPE USB 1회성 직접 EFI 부팅 등록 (`Invoke-DirectUsbEfiBootSetup`, `modules/03`, `04`, `06`):**
  * Windows가 켜진 상태에서 꽂아 메인보드 NVRAM에 아직 올라오지 않은 WinPE USB라도, 확인된 EFI 파티션과 `.efi` 경로를 이용해 임시 펌웨어 부팅 항목(`bcdedit /create ... /application firmware` + `bootsequence`)을 1회성(`BootNext`)으로 직접 등록하고 즉시 해당 USB로 재부팅(USB 원본 쓰기 0건 유지, 실패 시 고급 부팅 자동 폴백).
  * 단일 통합 USB 표(`RefreshPreSid`)에서 일부 NVRAM 항목 존재 시 다른 물리 USB가 숨겨지던 `if/elseif` 분기를 통합해 연결된 모든 부팅 USB가 누락 없이 표시되도록 개선.

---

## [v2.3.1] - 2026-11-28

### 버그 수정 및 안정화 (Fixed / Hardened)
* **내장 AHCI 핫플러그 SATA 디스크 및 마운트된 가상 디스크(`.vhdx`) 분류 안전장치 강화 (`modules/02_Bootloader_Conflict_Module.ps1`):**
  * BIOS에서 SATA Hot-Plug가 켜진 보조 내장 HDD/SSD가 `Capabilities`/`RemovalPolicy`만으로 외장 USB로 오분류되어 1단계 잔존 부트로더 점검에서 누락되던 문제를 해결(`Enum\USB`·`Enum\USBSTOR` 실제 `ContainerID` 일치 및 내장 버스 제외 가드 적용).
  * `Get-UsbPnpDiskLookup`을 직접 `.NET Registry` 조회 방식으로 전환해 PnP 인스턴스 ID 내 특수문자(`[`, `]`, `*`) 와일드카드 오류를 차단하고 스캔 속도를 개선.
  * 탐색기에 마운트된 `.vhd`/`.vhdx` 파일(`BusType = File Backed Virtual`)을 `VIRTUAL_PROTECTED`(`가상 디스크 보호됨`)로 자동 보호하고, 미마운트 부트 파티션 점검 시 `\\?\Volume{GUID}\` 직접 탐색을 우선 수행해 불필요한 임시 문자 할당(`diskpart`)과 탐색기 자동 실행 창을 최소화.
* **USB NVRAM 매칭 오탐 및 유령(`unknown`) 항목 원천 차단 (`modules/03`, `04`):**
  * 일반 데이터용 비부팅 USB(`AnyEfiReadyUsb = $false`) 연결 시에도 4단계 범용 NVRAM 매칭이 무조건 허용되던 조건식 결함을 수정.
  * 과거 연결 이력만 남은 끊어진 NVRAM 유령 항목(`device = unknown`)과 USB 유선랜 어댑터(`Realtek USB GbE Family Controller`, `Ethernet`, `LAN` 등)가 부팅 USB로 오매칭되지 않도록 차단.
  * 모델명 단일 토큰에서 용량·수식어(`Plus`, `Pro`, `256GB`, `10G`, 단독 `Realtek` 등) 노이즈를 제외하고 영숫자 경계(`(?<![A-Za-z0-9])...(?![A-Za-z0-9])`)를 적용해 부분 문자열 오탐 차단.
* **BIOS 진단 정확도, 도메인 PC 응답성 및 GUI 마감 보강 (`modules/01`, `02`, `03`, `05`, `06`, `07`):**
  * HP `HP_BIOSOrderedList`(`UEFI Boot Order`) 단독으로 `USB Boot = Enabled`로 단정하지 않도록 보정(절대 규칙 #5 준수), `HP_BIOSEnumeration` 우선 조회 및 세미콜론(`;`) 구분자·`H0` 자산 코드·Dell `DeployedMode` 지원 추가.
  * `Get-LocalMachineSid`에서 로컬 SAM(`Get-LocalUser`)을 우선 조회하고 `Win32_UserAccount`에 로컬 `Domain` 필터를 추가해 망분리/도메인 PC에서의 WMI 지연 방지.
  * 진단 리포트 마스킹(`ConvertTo-MaskedDiagnosticText`)을 따옴표 값·이스케이프 JSON·`net use` 자격증명까지 확장하고, GUI 팝업/상태 동기화(`finally` 내 `SyncButtonStates`, 유효 SID 검증, WinPE 비상 창 DPI·더블클릭·충돌 행 강조, 한국어 BIOS 안내 문구)를 다듬음.
* **문서 개편 (`README.md`):** 현장 작업자가 바로 읽고 따라 하기 쉽도록 안내서 문체와 구성을 자연스러운 한국어 중심으로 전면 재작성.

---

## [v2.3.0] - 2026-11-27

### 추가 및 고도화 (Added / Enhanced)
* **병원 실장비 인벤토리 기반 기종 프로필(`S4/S5/S8/S9`, `H0/H1/H2/H3/H4/HS/H6/H8`, `D1/D8`) 정밀 식별 (`modules/03_Vendor_Bios_Diagnostics.ps1`):**
  * `Win32_ComputerSystem`, `Win32_ComputerSystemProduct`, `HKLM\...\BIOS`, CPU 세대 및 병원 자산명(`CYYNNNNXX`)을 교차 분석해 삼성 `DB400T8A/DB400T9A`(`S8/S9`), HP `ProDesk 600 G1~G3`(`H4/HS/H6/H8`), HP `EliteDesk 800 G8 / Elite Tower 800 G9`(`H1/H2`), Dell `OptiPlex 3070~7070`(`D1`) 및 2026 신규 보급 `OptiPlex 7010·7020 / Dell Pro Tower`(`D8`)를 정확히 식별하고 세대별 맞춤 BIOS 경로 안내를 제공.
* **외장 NVMe/SSD 인클로저(UASP) 및 숨김 EFI 부팅 디스크 인식 엔진 전면 개선 (`modules/01`, `02`, `04`):**
  * **PnP `ContainerID` · `Capabilities` 기반 UASP 외장 SSD 분류 (`Get-UsbPnpDiskLookup`):** `Realtek RTL9210B-CG`, `HSEN 10G-NVME`, `JMicron Generic PCIE/SATA`, `Seagate FireCuda SSD` 등 `Get-Disk`에서 `BusType=SCSI/NVMe`·`IsRemovable=False`로 보고되던 외장 UASP 부팅 디스크를 내장 디스크로 오분류하지 않고 100% 부팅 USB로 인식.
  * **외장 인클로저 모델명 `NVMe`/`SATA` 오탐 배제 수정:** 제품명에 `NVMe` 또는 `SATA`가 포함된 외장 부팅 디스크(`HSEN 10G-NVME`, `JMicron Generic SATA` 등)가 내장 버스로 오인되어 NVRAM 후보에서 탈락하던 버그 수정.
  * **무파일 인메모리 `QueryDosDeviceW` 커널 볼륨 매핑 (`Resolve-DosDeviceTarget`):** 드라이브 문자가 없는 숨김 EFI/Ventoy(`VTOYEFI`)/Rufus(`UEFI:NTFS`) 파티션도 `Volume{GUID}` → `\Device\HarddiskVolumeX`로 즉시 매핑하여 1단계(Tier 1) 정확 일치 달성(임시 DLL/`csc.exe` 호출 0건 유지).
  * **숨김 MBR FAT 파티션(`0x11, 0x14, 0x16, 0x1B, 0x1C, 0x1E`), 미마운트 `Volume{GUID}` 부팅 파일 탐색 및 `PMAP`/`UDisk`/`Generic Flash Disk` NVRAM 매칭 지원.**
  * **Windows 실행 중 연결(Hot-Plug)된 부팅 디스크 UX 개선 (`modules/06_Gui_WinForms.ps1`):** 부팅 파일이 검증된 Hot-Plug USB를 경고성 `NVRAM 미등록` 대신 `부팅 디스크 · 고급 부팅 준비`로 명확히 표시하고 바로 고급 부팅(`장치 사용`)으로 연결.
* **Secure Boot 및 제조사별 BIOS USB Boot 탐지 정확도 대폭 강화 (`modules/03_Vendor_Bios_Diagnostics.ps1`):**
  * **HP G8/G9(`H1/H2`) 체크박스형 WMI 값(`*Checked,Unchecked`) 및 한글 BIOS 로컬라이징 완벽 지원:** 기존 `Enable/Disable`만 검사하여 HP G8/G9에서 `USB Storage Boot`·`Fast Boot`·`Secure Boot`가 미확인으로 빠지던 결함 해결, `HPBIOS_BIOSEnumeration`·`HP_BIOSOrderedList` 병합 조회 및 구형 G1~G5 복합 `Configure Legacy Support and Secure Boot` 우선순위 적용(회색 비활성 `Secure Boot=Enable`로 인한 거짓 충돌 제거).
  * **Dell WMI(`D1/D8`) 호환성 강화:** `AttributeValue` 속성, 접두형 열거값(`EnableUsbBoot`/`DisableUsbBoot`/`AllDisable`), `SecBoot`, `Fastboot=Auto` 미인식 시 안내 보강.
  * **Lenovo(`Lenovo_BiosSetting`) WMI 지원 추가 및 4중 신호 Secure Boot 교차 검증(`Win32_DeviceGuard` 추가, Legacy MBR `해당 없음` 분리).**
  * **시스템 OEM 코드페이지(`HKLM\...\Nls\CodePage\OEMCP`) 우선 조회:** 한국어 Windows에서 국가/지역 형식만 영문(`en-US`)으로 바꾼 PC에서도 `bcdedit`/`diskpart` 한글 출력이 깨지지 않도록 보강.

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
