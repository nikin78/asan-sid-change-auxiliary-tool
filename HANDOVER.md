# [인수인계서] SID 변경 사전·사후 보조 툴 (`SID_Change_Aux_Tool.bat`)

> [!IMPORTANT]
> **현재 버전: `v2.4.0` (2026-11-29 작업 기준 — 다중 파티션 `PhoenixPE`/`DISM++`/`Rufus` WinPE USB 인식 전면 개편, 자체 실행 `(일반 내장 공간)` USB 자동 식별 및 1회성 UEFI EFI 직접 부팅 등록 완료):**
> 기존 `USB_Reboot.bat`을 **WinPE 기반 SID 변경 작업의 사전·사후 보조 툴(`SID_Change_Aux_Tool.bat`)**로 확장하고, **다중 파티션(`(EFI) + (부팅파일) + (일반 내장 공간)`) WinPE USB 완벽 인식 및 Hot-Plug 상태 즉시 1회성 EFI 직접 부팅(`Invoke-DirectUsbEfiBootSetup`), 자체 실행 USB(`IsSelfHostUsb`) 자동 우선 선택, 병원 전체 PC 인벤토리(`S4/S5/S8/S9`, `H0/H1/H2/H3/H4/HS/H6/H8`, `D1/D8`) 세대별 프로필, UASP 외장 SSD PnP 분류, 4중 신호 Secure Boot 교차 검증 및 200개 자동/레이아웃 테스트**까지 완료했습니다.
> 사용자 안내서는 [README.md](README.md), 변경 이력은 [CHANGELOG.md](CHANGELOG.md), 상세 의사결정 배경은 [docs/DIRECTION_AND_DECISIONS.md](docs/DIRECTION_AND_DECISIONS.md)를 참고하세요.
> **다음에 해야 할 일:** 개선된 `v2.4.0` 빌드로 **5단계 실장비 재검증(다중 파티션 PhoenixPE/DISM++ USB, Samsung `S8/S9`, HP `H0/H1/H2/H6/H8`, Dell `D1/D8`, 공유 프린터)** 후 최종 확정.

---

## 0. 최근 작업 세션 인수인계 요약 (2026-11-29 `v2.4.0` 다중 파티션 WinPE USB 인식 및 직접 부팅 개편)

### 2026-11-29 완료한 작업 (`v2.3.1` → `v2.4.0` — PhoenixPE / DISM++ / 다중 파티션 자체 실행 USB 미인식·부팅 불가 근본 해결)
1. **다중 파티션 WinPE 부팅 디스크(`PhoenixPE Builder`, `DISM++`, `Rufus UEFI:NTFS`, `Bootice`) 미인식 원인 전수 해결 (`modules/01`, `02`, `04`):**
   * `Get-PhysicalUsbInfo`에서 `DISM++`/`DiskPart`/`Bootice`가 숨김 USB EFI·WinPE 파티션에 부여하는 GPT 복구 GUID(`{de94bba4-06d1-4d40-a16a-bfd50179d6ac}`)를 건너뛰던 치명 버그를 제거하고, 숨김 MBR 타입(`0x12` EISA, `0x17` 숨김 NTFS, `0x27` WinRE) 및 읽기 전용 512바이트 VBR 시그니처 판별(`Get-RawPartitionFsHint`)을 추가.
   * `Find-BestEfiBinaryOnRoot`로 표준 `BOOTX64.EFI`, `bootmgfw.efi`, `grubx64.efi`, `bootmgr.efi`+`BCD`, `\EFI\*\*.efi` 커스텀 PE 로더를 탐색하고, 전용 `FAT12/16/32` EFI 파티션(예: `UEFI_NTFS`, Score 115)을 `NTFS`/`exFAT`(Score 75)보다 우선 선택하도록 점수화(`exFAT` 단독 일반 파티션 오탐 방지).
   * `Find-MatchedUsbNvramEntries`에서 `DISM++`/`bcdboot`로 생성되어 이름이 `"Windows Boot Manager"`인 USB NVRAM 항목도 파티션 경로(`$matchesUsbDev`)가 USB와 일치할 때 Tier 1로 정상 매칭되도록 수정(내장 OS `{bootmgr}` 및 내장 파티션은 계속 차단).
2. **`(EFI) + (부팅파일) + (일반 내장 공간)` 자체 실행 USB 인지 (`Get-SelfHostLocationInfo`):**
   * 일반 내장 공간 파티션에 둔 `SID_Change_Aux_Tool.bat`을 직접 실행할 때 `SELF_PATH`가 위치한 물리 디스크를 `IsSelfHostUsb = $true`(`실행 USB`)로 식별해 내장 디스크 오분류를 막고 USB 목록 최상단에 자동 선택, `모델명 (WinPE 볼륨 라벨)` 표시 지원.
3. **Hot-Plug(NVRAM 미등록) 상태 즉시 1회성 UEFI EFI 직접 부팅 (`Invoke-DirectUsbEfiBootSetup`, `modules/03`, `04`, `06`):**
   * Windows 실행 중 꽂아 NVRAM 목록에 아직 없는 WinPE USB라도 `bcdedit /create ... /application firmware` + `device` + `path` + `bootsequence`로 1회성 `BootNext` 부팅 항목을 직접 등록해 `선택한 USB로 재부팅` 한 번으로 바로 WinPE로 진입(USB 매체 쓰기 0건, 실패 시 고급 부팅 폴백).
   * `RefreshPreSid`에서 기존 NVRAM 매칭 유무와 무관하게 연결된 모든 물리 부팅 USB를 통합 표에 함께 노출하도록 개선.

### 2026-11-28 완료한 작업 (`v2.3.0` → `v2.3.1` — 전 모듈 재귀 코드 리뷰, 엣지 케이스 수정, 사용자용 `README.md` 개편, GitHub Release 배포)
1. **내장 AHCI 핫플러그 디스크 오분류 차단 및 무마운트 볼륨 점검 (`modules/02_Bootloader_Conflict_Module.ps1`):**
   * BIOS에서 SATA Hot-Plug가 켜진 내장 보조 HDD/SSD가 `Capabilities`/`RemovalPolicy`만으로 외장 USB로 빠져 1단계 부트로더 점검에서 누락되던 결함을 수정(`Enum\USB`·`Enum\USBSTOR` 실제 `ContainerID` 일치 시에만 USB로 인정하고 고정 내장 버스는 보존).
   * `Get-UsbPnpDiskLookup`을 `.NET Registry` 직접 조회로 개편해 PnP 경로 내 `[` `]` `*` 와일드카드 버그를 없애고 조회 속도를 단축.
   * 마운트된 `.vhd`/`.vhdx` 가상 디스크(`File Backed Virtual`)를 `VIRTUAL_PROTECTED`로 보호하고, 1단계 읽기 전용 점검 시 `\\?\Volume{GUID}\` 직접 탐색을 우선 수행해 불필요한 `diskpart` 임시 문자 마운트와 탐색기 자동 실행 팝업을 제거.
2. **NVRAM 유령 항목·USB 랜카드·비부팅 데이터 USB 오매칭 차단 (`modules/03`, `04`):**
   * `Get-PreSidStep2Snapshot`에서 비부팅 일반 데이터 USB(`AnyEfiReadyUsb = $false`)까지 4단계 범용 NVRAM 매칭을 허용하던 항상 참(`-or ($usbDisks.Count -gt 0)`) 버그 수정.
   * 이전 작업자의 분리된 USB/디스크에서 남은 `device = unknown` 유령 NVRAM 항목 및 USB 유선랜 동글(`Realtek USB GbE Family Controller`, `Ethernet`, `LAN`)을 후보에서 원천 제외.
   * 모델명 토큰에서 `Plus`, `Pro`, `256GB`, `10G`, 단독 `Realtek` 등 범용 노이즈를 걸러내고 영숫자 경계(`(?<![A-Za-z0-9])...(?![A-Za-z0-9])`)를 적용.
3. **BIOS 교차 검증(Rule #5), 도메인 PC SID 지연 방지, 보안 마스킹 및 GUI 마감 (`modules/01`, `03`, `05`, `06`, `07`):**
   * HP `HP_BIOSOrderedList` 단독으로 `Enabled`를 추정하던 분기를 제거해 Rule #5를 엄격히 유지하고, `HP_BIOSEnumeration` 우선 조회·세미콜론(`;`) 구분자·누락된 `H0` 자산 코드·Dell `DeployedMode` 지원 및 한국어 BIOS 안내 문구 정돈.
   * `Get-LocalMachineSid`에서 `Get-LocalUser`를 1순위로 호출하고 `Win32_UserAccount`에 로컬 도메인 조건을 부여해 AD 도메인/망분리 환경의 WMI 타임아웃을 예방.
   * `ConvertTo-MaskedDiagnosticText` 마스킹 범위 확장(따옴표 값·이스케이프 JSON·`net use`), `RefreshPreSid`/`RefreshPostSid` `finally` 버튼 동기화 보장, `WinPE` 비상 창 DPI/더블클릭/충돌 색상 통일.
4. **일반 사용자 눈높이 `README.md` 전면 재작성 및 GitHub Release `v2.3.1` 배포:**
   * 개발자 배지·복잡한 다이어그램·내부 API 용어를 걷어내고 현장 담당자가 바로 읽고 따라 할 수 있는 자연스러운 안내서로 [`README.md`](README.md)를 개편(관리자/개발자용 상세 명세는 하단 `<details>`에 수록).

### 2026-11-27 완료한 작업 (`v2.2.0` → `v2.3.0` — 실장비 피드백 반영 및 전반적 코드 리뷰 개선)
1. **병원 망분리/교체 대상 PC 전체 인벤토리(9,803대 + 신규 교체분) 기종 매핑 반영 (`modules/03_Vendor_Bios_Diagnostics.ps1`):**
   * `S4/S5`(삼성 구형 i5-650/2300), `S8`(`Samsung DB400T8A`, i5-8500), `S9`(`Samsung DB400T9A`, i5-9500), `H3`(`HP Compaq Pro 6300 / Elite 8300`), `H4/HS`(`HP ProDesk 600 G1`), `H6`(`HP ProDesk 600 G2`), `H8`(`HP ProDesk 600 G3`), `H1`(`HP EliteDesk 800 G8`, i5-11500), `H2`(`HP Elite Tower 800 G9`, i5-12500/13500), `D1`(`Dell OptiPlex 3070/5070/7070`, i5-9500), `D8`(2026 신규 교체 `Dell OptiPlex 7010·7020 / Pro Tower`) 식별 및 세대별 정확한 BIOS 설정 경로 안내 추가.
2. **부팅 디스크 미인식 근본 원인 5종 해결 (`modules/01`, `02`, `04`, `06`):**
   * **UASP 외장 NVMe/SATA 인클로저 PnP `ContainerID`·`Capabilities` 분류 (`Get-UsbPnpDiskLookup`):** `Get-Disk`에서 `BusType=SCSI/NVMe` 및 `IsRemovable=False`로 잡히던 `Realtek RTL9210B-CG`, `HSEN 10G-NVME`, `JMicron Generic PCIE/SATA`, `Seagate FireCuda SSD`를 USB 부모 `ContainerID` 대조로 100% 외장 부팅 디스크로 분류.
   * **외장 인클로저 제품명 `NVMe`/`SATA` 오탐 차단 수정:** `UEFI: HSEN 10G-NVME`, `UEFI: JMicron Generic SATA`가 `\b(SATA|NVMe)\b` 필터에 걸려 내장 디스크로 탈락하던 버그 해결.
   * **무파일 인메모리 `QueryDosDeviceW` 숨김 EFI 커널 볼륨 매핑 (`Resolve-DosDeviceTarget`):** 드라이브 문자가 없는 숨김 ESP(`VTOYEFI`, `UEFI:NTFS`, 다중 파티션 SSD EFI)도 `Volume{GUID}` → `\Device\HarddiskVolumeX`로 직접 매핑해 Tier 1 정확 일치 달성(`UEFI: PMAP` 등 컨트롤러명 표기 포함, `csc.exe`/임시 DLL 0건 유지).
   * **숨김 MBR FAT(`0x11,0x14,0x16,0x1B,0x1C,0x1E`), 미마운트 `Volume{GUID}` 부팅 파일 검사, `Generic Flash Disk`/`UDisk`/`PMAP` Tier 4 보강.**
   * **Hot-Plug 부팅 디스크 UX 개선:** Windows 실행 중 꽂은 정상 부팅 USB를 `부팅 디스크 · 고급 부팅 준비`로 명확히 표시하고 바로 고급 부팅(`장치 사용`)으로 안내.
3. **Secure Boot 및 BIOS USB Boot 탐지 정확도 개선 (`modules/01`, `03`):**
   * **HP G8/G9(`H1/H2`) 체크박스형 WMI 값(`*Checked,Unchecked`) 및 한글 BIOS 로컬라이징 지원, 설정명 공백 `.Trim()`, `HPBIOS_BIOSEnumeration`·`HP_BIOSOrderedList` 병합, 구형 G1~G5 복합 `Configure Legacy Support and Secure Boot` 우선순위 적용**(회색 비활성 `Secure Boot=Enable`로 인한 거짓 충돌 제거).
   * **Dell(`D1/D8`) `AttributeValue` 속성·접두형 열거값(`EnableUsbBoot`/`DisableUsbBoot`/`AllDisable`)·`SecBoot`·`Fastboot=Auto` 안내 및 Lenovo(`Lenovo_BiosSetting`) WMI 추가.**
   * **4중 신호 Secure Boot 교차 검증(`Win32_DeviceGuard` 추가, Legacy MBR `해당 없음` 분리) 및 `HKLM\...\Nls\CodePage\OEMCP` 우선 조회**(영문 지역 형식 설정 한국어 Windows에서 `bcdedit`/`diskpart` CP949 깨짐 방지).
   * `RefreshPreSid` 중복 디스크 스캔 제거 및 **178개 자동/레이아웃 테스트 전항목 통과**.

다른 PC의 AI 에이전트가 이전 채팅 기록 없이 바로 이어받을 수 있도록 오늘 완료한 작업과 수정된 파일을 요약합니다.

### 오늘 완료한 작업 (`v2.1.0` → `v2.1.1` → `v2.2.0`)
1. **WinForms GUI 최초 구현 + 다중 신호 BIOS 교차 검증 엔진 구축 (`v2.1.0`):**
   * 순수 GAC WinForms GUI(`modules/06_Gui_WinForms.ps1`) + 콘솔 `--cli`/WinPE 폴백(`modules/07_Main_Entry.ps1`) 도입.
   * 부팅 모드 3중 신호(`bcdedit` + 레지스트리 + 부팅 디스크 GPT/MBR), Secure Boot 3중 신호, HP Primary/Legacy 분리(`Legacy USB Boot=Disable` 오탐 제거), Dell 숫자 열거형/`biosattributes` 지원, WMI vs NVRAM `Conflict` 감지 엔진 구현.
2. **체계적 SemVer 버저닝 도입 및 `X` 버튼 종료 예외 수정 (`v2.1.1`):**
   * `VERSION` 단일 원본 + `CHANGELOG.md` + `tools/Build-Tool.ps1 -Bump Major|Minor|Patch` 자동 버전 주입·검증 체계 구축.
   * `New-SidAuxMainForm` 반환 후 동적 스코프 소멸로 `Form.OnFormClosed`에서 발생하던 `null 값 식에서 메서드를 호출할 수 없습니다` 예외를 단일 `$ui` 컨텍스트(`$form.Tag`) + `.GetNewClosure()` + Null-Safe `Dispose()`로 근본 해결.
3. **아산병원 데스크톱 디자인 시스템(`asan-desktop-ui`) 전면 적용 + 재귀 코드/시각 감사 (`v2.2.0`):**
   * 4영역 고정 셸(`#005658`/`#006769`/`#F68B1F`/`#0B4F51`), 순수 GDI+ 자체 벡터 심볼·창 아이콘(저작권 로고 없음·HICON 누수 없음), `OwnerDrawFixed` 번호형 탭(`Alt+1`/`Alt+2`/`F5`), 단일 통합 USB `DataGridView`, 비활성 점선 버튼 + 부모 라우팅 사유 툴팁, 비동기 Runspace 프린터 스풀러 초기화, 오류 자동 진단 리포트 저장(민감정보 `[REDACTED]` 마스킹) 적용.
   * 상용 데스크톱 UX 라이팅 기준으로 전 모듈 GUI 문구·버튼에서 `[대괄호]`, `(부가 괄호)`, `!`, `->` 제거.
   * 자동 레이아웃 감사(`1040×720` / `960×640` + 확장 로그 포함 **152/152 PASS**) 및 `DrawToBitmap` 실제 렌더링 PNG 픽셀 육안 감사로 발견한 7건(Tab 2 하단 버튼 잘림, `NVRAM 미등록` 잘림, 내장 디스크 오름차순 정렬, 선택된 충돌 행 적색 유지, 모달 아이콘 통일, 비-OEM 보드사명 표시, 리포트 원본 폴더 쓰기 차단) 모두 수정 완료.
4. **GitHub 사용자용 `README.md` 및 비식별 시각자료 제작:**
   * 실장비 개인정보가 없는 비식별 예시 화면 3종(`docs/images/01_pre_sid_ready.png`, `02_pre_sid_conflict.png`, `03_post_sid_spooler.png`)과 Mermaid 워크플로 다이어그램, 매체별 실행 방법, 제조사별 BIOS 단축키 표를 포함한 [`README.md`](README.md) 작성.

### 오늘 생성·수정된 파일 전체 목록
* **신규 생성:** `README.md`, `VERSION` (`2.2.0`), `CHANGELOG.md`, `modules/06_Gui_WinForms.ps1`, `modules/07_Main_Entry.ps1`, `docs/images/01_pre_sid_ready.png`, `docs/images/02_pre_sid_conflict.png`, `docs/images/03_post_sid_spooler.png`
* **삭제:** `modules/06_Main_Entry.ps1` (`modules/07_Main_Entry.ps1`로 승격·교체)
* **수정:** `SID_Change_Aux_Tool.bat`, `modules/01_Bootstrap_And_Helpers.bat`, `modules/02_Bootloader_Conflict_Module.ps1`, `modules/03_Vendor_Bios_Diagnostics.ps1`, `modules/04_Usb_Matching_And_Reboot.ps1`, `modules/05_PostSid_Spooler_Module.ps1`, `tools/Build-Tool.ps1`, `tools/Test-Tool.ps1`, `HANDOVER.md`, `docs/DIRECTION_AND_DECISIONS.md`

### 다음 AI 에이전트가 이어서 할 일 (5~6단계)
1. 작업 시작 전 `git pull origin main`으로 최신 동기화 확인.
2. 사용자가 **5단계 실장비 테스트** 결과(아래 4절 체크리스트)나 UI/UX 추가 개선 요청을 전달하면, 반드시 **`modules/*.{bat,ps1}`만 수정**하고 `tools\Build-Tool.ps1 -Bump Patch`(또는 `Minor`)로 `SID_Change_Aux_Tool.bat`를 재생성할 것.
3. UI 변경이 포함되면 전역 스킬 `asan-desktop-ui` 기준에 따라 `tools\Test-Tool.ps1`(152개+ 레이아웃 감사) 통과 및 실제 렌더링 스크린샷 시각 검수를 반드시 수행할 것.
4. 실장비 검증이 완료되면 `CHANGELOG.md`, `README.md`, `HANDOVER.md`를 최종 확정하고 태그(`v2.2.x` / `v2.3.0`)와 함께 푸시하여 6단계 마무리.

---

## 1. 프로젝트 개요 및 최종 목표

* **프로그램 목적**
  * **사전 작업(Pre-SID):** WinPE USB 부팅 전,
    1. **STEP 1 (필수 선행):** C드라이브(현재 OS) 외 다른 내장 드라이브에 잔존한 **GPT EFI 파티션(`EFI`) 및 구형 MBR 활성 부팅 파티션(`bootmgr` / `\Boot\BCD`)**을 탐지해 비파괴 무력화(부팅 충돌·자동 복구 진입 사전 차단).
    2. **STEP 2 (사용자 선택):** 제조사별 BIOS 차단 요소 확인 → 물리 USB 및 UEFI NVRAM 4단계 교차 매칭 → 사용자 확인 후 일회성 재부팅(`bcdedit /set {fwbootmgr} bootsequence`) 또는 고급 부팅/BIOS 진입.
  * **사후 작업(Post-SID):** 골든 이미지 복제 PC에서 SID 변경을 마친 뒤, 공유 프린터 이용 시 필요한 **프린터 스풀러 리셋**(대기열 정리 + 서비스 재시작 + `Disabled` 시작 유형 자동 복구) 및 **호스트/클라이언트 공유 상태 진단** 제공.
  * **비상 복구(WinPE `X:`):** SID 작업 후 부팅이 꼬여 WinPE로 부팅한 상태에서 동일한 `SID_Change_Aux_Tool.bat` 실행 시 자동으로 `[WinPE 비상 모드]` 진입 → 내장 디스크 GPT EFI(`EFI` ↔ `EFI_OLD`) 및 MBR(`bootmgr`/`Boot` ↔ `_OLD` + `active`/`inactive`) 복구 전환. Storage 모듈 미지원 경량 WinPE에서도 `diskpart` 호환 모드로 자동 폴백.
* **실행 환경**
  * **OS:** Windows 10 / 11 (UEFI 및 Legacy MBR — 사후 작업은 Legacy에서도 동작) 및 WinPE (`X:`, 예: PhoenixPE).
  * **주 타깃 장비:** 삼성(Samsung S8/S9 등 AMI BIOS), HP(구형 G1~G5 / 신형 G6~G9+), Dell(구형 OptiPlex 3040~3070 / 신형 3080~7010+) 데스크탑 및 일반 표준 UEFI 보드.
  * **주요 부팅 매체:** 다중 파티션 구조(`NTFS + exFAT + Hidden EFI FAT`)의 WinPE USB 및 외장 NVMe/SSD 인클로저(예: Seagate FireCuda SSD).
  * **권한 및 의존성:** 관리자 권한 필수(미보유 시 자동 UAC 상승). 배포물 `SID_Change_Aux_Tool.bat` 1개만으로 동작하며 Windows 기본 내장 도구(`PowerShell`, `diskpart`, `bcdedit`, `mountvol`, `shutdown`, `bcdboot`)만 사용.

---

## 2. 핵심 기능 명세

### 2.1 실행 환경 자동 판별, 아산병원 디자인 시스템 WinForms GUI 및 진입점 (`modules/06_Gui_WinForms.ps1`, `modules/07_Main_Entry.ps1`)
* **아산병원 현장 데스크톱 디자인 시스템(`asan-desktop-ui`) 전면 적용:**
  * **4영역 고정 셸 (`1040×720` 기본 / `960×640` 최소, DPI 100~150% 안전):** `#005658` 딥 틸 2단 헤더 + 순수 GDI+ 자체 벡터 심볼/창 아이콘(저작권 로고 미사용·22바이트 PNG-in-ICO로 HICON 누수 없음) + `#F68B1F` 오렌지 포인트 라인 + `#EDF3F3` 메타 바(`PC명 · 모델명 · OS · 부팅 방식 · SID + 1.5초 즉각 피드백 SID 복사`), 조건부 치명 경고 배너, `OwnerDrawFixed` 번호형 탭(`1. SID 변경 전 준비`, `2. SID 변경 후 프린터 복구`, `Alt+1`/`Alt+2`/`F5` 단축키), 기본 접힘 다크 로그 콘솔(`38px ↔ 114px`, `New-PaddedTextBoxPanel` 패딩 래퍼).
  * **초보자 친화 워크플로 & 단일 통합 USB 표:** 기존 3개 표가 혼재하던 사전 탭을 `1단계`(내장 디스크 점검, 이상 없을 시 접기 가능) + `2단계`(단일 통합 `DataGridView` USB 부팅 표, `#0B4F51` 헤더 · `32px` 행)로 단순화하고, 사후 탭은 4열 핵심 메트릭 타일 + 프린터 목록 + 하단 실행 바로 정돈.
  * **비활성 점선 버튼 + 부모 라우팅 사유 툴팁:** 모든 비활성 버튼을 점선(`Dash`) 테두리·무채색으로 직접 렌더하고, 마우스 오버 시 비활성 사유와 해결 방법을 툴팁으로 즉시 표시. 화면당 핵심 `Primary(#006769)` 버튼 최대 1개 원칙 준수.
  * **상용 한국어 UX 라이팅:** 모든 GUI 문구·버튼에서 `[대괄호]`, `(부가 괄호)`, `!`, `->` 개발자 표기를 배제하고 2~3어절 행동 동사 버튼과 차분한 `~해 주세요` 안내로 통일.
  * **비동기 프린터 스풀러 초기화 & 오류 자동 진단 리포트:** 스풀러 초기화를 백그라운드 Runspace + `Timer` 폴링으로 실행해 UI 멈춤을 제거했고, 오류 시 민감정보가 `[REDACTED]`로 마스킹된 진단 리포트의 로컬 저장/클립보드 복사를 즉시 안내.
* **GUI 우선 실행 + 콘솔 자동 폴백:**
  * 순수 GAC `System.Windows.Forms` / `System.Drawing` 기반(임시 DLL·`csc.exe` 호출 0건으로 쓰기 금지 USB/공유폴더/보안 환경 호환).
  * `SID_Change_Aux_Tool.bat --cli` 인자를 주거나 WinForms 로드 불가(경량 WinPE 등) 환경에서는 기존 콘솔 TUI로 자동 전환.
  * 모든 이벤트 핸들러는 단일 `$ui` 상태 해시테이블(`$form.Tag`) + `.GetNewClosure()`로 바인딩되며, `FormClosing`/`FormClosed`에서 타이머·Runspace·폰트·아이콘을 Null-Safe 해제해 `X` 버튼 종료 예외를 원천 방지.
* **WinPE 비상 모드 (`$env:SystemDrive -eq "X:"`):** USB 부팅 로직을 건너뛰고 내장 디스크 부트로더(GPT EFI / MBR) 전용 비상 복구 화면(GUI 가능 시 전용 비상 창, 불가 시 콘솔 TUI)으로 자동 분기.
* **실행 매체별 부트스트랩 안전장치 (`modules/01_Bootstrap_And_Helpers.bat`):**
  * **PowerShell `-STA` 강제:** WinForms 안정 동작을 위해 일반/UAC 상승 실행 경로 모두 `-STA` 스위치를 적용하고 `--cli` 인자(`SELF_ARG1`)를 유지.
  * **쓰기 금지 USB / 읽기 전용 폴더:** 원본 폴더에 쓰기 0건(RAM 전용 실행). `IsReadOnly` 디스크는 `READONLY_PROTECTED`로 자동 보호.
  * **공유폴더(`\\서버\공유`) / 네트워크 매핑 드라이브(`Z:\`):** 일반 더블클릭 시 UAC Split-Token으로 경로·자격증명이 소실되는 문제를 막기 위해, 권한 상승 직전 로컬 임시 폴더(`%TEMP%` → `%LOCALAPPDATA%\Temp` → `Public\Documents`)로 일시 스테이징 후 Base64 `-EncodedCommand`로 권한 상승하며, RAM 로드 직후 임시 파일을 즉시 삭제(원본 무변경). *(운영 팁: 공유폴더/매핑 드라이브에서는 우클릭 '관리자 권한으로 실행' 대신 **일반 더블클릭**을 사용하세요.)*
  * **로컬 특수문자 경로 및 WinPE/`LanmanServer` 중지 환경:** `SystemDrive == X:` 즉시 통과 및 `fltmc` 보조 관리자 판별로 무한 UAC 루프 방지, Base64 실행으로 `&`, `(`, `)`, `'`, 공백, 한글 경로 깨짐 방지.
  * **안정성 보강:** `Invoke-NativeOem` 30초 기본 타임아웃 + `System32` 절대 경로 우선 해석, `Invoke-SafeRebootCore`/`Invoke-SafeReboot` 종료 코드 검증(실패 시 원인 표시).

### 2.2 사전 작업 STEP 1: 잔존 부트로더 탐지·무력화 및 USB/WinPE 보호 (`modules/02_Bootloader_Conflict_Module.ps1`)
* **순서 강제 UX:** STEP 1에서 충돌 위험이 없으면 `[정상]` 표시 후 바로 STEP 2 진행 가능. 충돌 위험 또는 `SplitBoot` 발견 시 STEP 1을 해결하거나, 명시적 확인 문구 **`IGNORE`**를 입력하기 전에는 STEP 2로 넘어갈 수 없음.
* **보호 디스크 및 USB/WinPE 매체 차단:**
  * 정상 Windows에서 `IsBoot` / `IsSystem` 디스크는 수정 불가 보호 목록으로 잠금(`SplitBoot` 감지 시 자동 조치 차단).
  * 외장 USB(`BusType=USB`, `IsRemovable`, `USBSTOR|UASP`)는 내장 부트로더 점검 대상에서 원천 제외.
  * 외장 NVMe 인클로저가 내장처럼 보이는 경우까지 대비하여, 동일 디스크 내 형제 파티션 또는 대상 파티션에 `sources\boot.wim`, `sources\install.wim/esd`, `ventoy\ventoy.json`, `PhoenixPE.cfg`, `boot\boot.sdi+sources`, 또는 `EFI\Microsoft` 없이 `EFI\BOOT\BOOTX64.EFI`만 존재하는 경우 `WINPE_MEDIA`/`WINPE_BLOCKED`로 자동 차단.
  * `Windows\System32\ntoskrnl.exe`가 있는 파티션은 OS 파티션으로 자동 차단(구형 단일 파티션 MBR OS+부트로더 공존 시 `MBR_OS_BLOCKED` 경고 표시 후 자동 변경 차단).
* **GPT EFI 및 구형 MBR 활성 파티션 비파괴 조치:**
  * **GPT EFI:** `EFI` ↔ `EFI_OLD` 이름 변경 (내부 백업 데이터 보존).
  * **MBR 활성 부팅 파티션(CSM 보드 충돌 대비):** 보조 MBR 디스크의 활성 파티션에 `bootmgr` 또는 `\Boot\BCD`가 있으면 충돌 위험으로 탐지. `+R/+S/+H` 속성 해제 후 `bootmgr` → `bootmgr_OLD`, `Boot` → `Boot_OLD` 이름 변경 + `diskpart inactive` 실행(실패 시 롤백). 복구 시 원복 + `diskpart active`.
  * **취소 흐름 보강:** 원스톱 조치(`[A]`)에서 사용자가 개별 변경을 취소(`N`)해 실제 변경 건수가 0이면 `bcdboot` 등록 프롬프트를 건너뜀.
* **WinPE `diskpart` 폴백:** `Get-Disk`/`Get-Partition`이 없거나 실패하는 경량 WinPE에서는 `diskpart` (`list disk` / `detail disk` / `list partition` / `detail partition`) 영문·한글 출력 파서로 자동 전환.

### 2.3 사전 작업 STEP 2: 다중 신호 BIOS 교차 검증 및 USB NVRAM 4단계 매칭 (`modules/03_Vendor_Bios_Diagnostics.ps1`, `modules/04_Usb_Matching_And_Reboot.ps1`)
* **OEM 안전 네이티브 실행(`Invoke-NativeOem`):** 한국어 Windows(CP949)에서 `[Console]::OutputEncoding = UTF8` 설정으로 인해 `bcdedit`/`diskpart` 출력이 깨지던 결함을 해결. 실행 중 임시 OEM 코드페이지 전환 + 스트림 OEM 디코딩 + `finally` UTF-8 복원.
* **`bcdedit /enum firmware` 파서 보강:** 영문(`identifier/description/path/device`) 및 한글(`식별자/설명/경로/장치`) 정확 파싱, `{fwbootmgr}` 내 `displayorder` GUID 오인식 방지, 한글 `Windows 부팅 관리자` 필터링, 내장 드라이브 목록이 비어 있을 때의 빈 `Device` 누락 버그 수정.
* **다중 신호 BIOS 교차 검증 엔진 (오탐 최소화):**
  * **부팅 모드 3중 신호(`Get-BootModeDiagnostics`):** `bcdedit /enum {current}` + `HKLM:\...\SecureBoot\State` 존재 / `PEFirmwareType` + OS 부팅 디스크 `PartitionStyle`(`GPT`/`MBR`) 교차 검증.
  * **Secure Boot 3중 신호(`Resolve-SecureBootCrossCheck`):** `Confirm-SecureBootUEFI` + 레지스트리 `UEFISecureBootEnabled` + `bcdedit` 상호 대조(충돌 시 `Conflict` 경고).
  * **HP/Dell 정밀 분리 및 교차 판정(`Resolve-HpBiosDiagnostics`, `Resolve-DellBiosDiagnostics`, `Resolve-BiosCrossCheckVerdict`):** HP에서 `Primary UEFI USB Boot`와 `Legacy USB Boot`/포트 제어를 분리해 `Legacy USB Boot = Disable` 오탐 제거; Dell `DCIM_BIOSEnumeration` + `biosattributes` 보조 네임스페이스 지원 및 숫자 열거형(`PossibleValues`) 안전 매핑; WMI 결과와 실제 NVRAM USB 부팅 항목 유무를 교차 비교해 불일치 시 `Conflict` 판정 + `[D]` / GUI 진단 리포트(`Format-BiosCrossCheckReport`) 제공. Samsung/AMI 등 미지원 보드 `[확인 불가]` 원칙 유지.
* **물리 USB 스캔 및 4단계 매칭 + Gate 2:** 드라이브 문자 → 모델명 → 파티션 번호 → 범용 UEFI USB 순 매칭. `[R]` / GUI 다시 스캔 지원. 매칭 0건 시 Hot-Plug(`[O]`) vs BIOS 차단(`[B]`) 분기. 매칭 1건 이상이면 반드시 사용자 확인 후 `bcdedit /set {fwbootmgr} bootsequence <GUID>` 실행 및 재부팅.

### 2.4 사후 작업: 프린터 스풀러 리셋 및 호스트/클라이언트 진단 (`modules/05_PostSid_Spooler_Module.ps1`)
* **역할 자동 판별:** 공유 중인 로컬 프린터가 있으면 `[호스트(메인 프린터 PC)]`, 없으면 `[클라이언트]`로 표시하며, 화면 상단에 "메인 프린터 PC와 클라이언트 PC 각각에서 한 번씩 실행하세요" 안내.
* **상태 표시 (테스트 대신 진단 정보 표시, 자기 자신 연결 테스트 미수행):**
  * **공통:** 컴퓨터 이름, 현재 Machine SID(`Win32_UserAccount` 로컬 계정 기준), `Spooler` 서비스 상태 및 시작 유형, `PRINTERS` 대기열 파일 수(`.SPL`/`.SHD`), 설치된 프린터 목록.
  * **호스트:** 공유 프린터 목록(`\\PC명\공유명`), 파일 및 프린터 공유 인바운드 방화벽 규칙 상태(`@FirewallAPI.dll,-28502`, 영문/한글 공용), 네트워크 프로필(`Public` 시 경고).
  * **클라이언트:** 연결된 네트워크 프린터(`Get-Printer`/`Win32_Printer` + `HKCU:\Printers\Connections`) 및 원격 호스트 SMB(445) 빠른 응답 확인(1초 타임아웃, 로컬 PC 제외).
* **안전 스풀러 리셋 (기존 프린터·드라이버·공유 설정 비삭제):**
  1. `Spooler` 및 실행 중인 의존 서비스 중지 (10초 타임아웃 시 `spoolsv` 프로세스 안전 종료)
  2. `%SystemRoot%\System32\spool\PRINTERS\*` 파일만 정리 (폴더 유지)
  3. `Spooler` 시작 유형이 `Disabled`면 `Automatic`으로 자동 복구
  4. `Spooler` 및 기존 의존 서비스 재시작 후 결과 리포트 출력

---

## 3. 저장소 구조 및 개발/빌드 워크플로

```text
SID_Change_Aux_Tool.bat                  # 최종 단일 배포 파일 (100% 순수 ASCII, CRLF)
README.md                                # GitHub 사용자용 프로그램 명세 및 사용 가이드 (시각자료 포함)
VERSION                                  # 단일 버전 원본 (SemVer MAJOR.MINOR.PATCH, 순수 ASCII)
CHANGELOG.md                             # 버전별 변경 이력 (Keep a Changelog 형식)
modules/
  01_Bootstrap_And_Helpers.bat           # UAC 래퍼(-STA/--cli), 버전 메타데이터, U(), Invoke-NativeOem, bcdedit 파서
  02_Bootloader_Conflict_Module.ps1      # GPT EFI + MBR 활성 부트로더 탐지/토글, USB/WinPE 가드, diskpart 폴백
  03_Vendor_Bios_Diagnostics.ps1         # 벤더 식별, 3중 신호 BootMode/SecureBoot, HP/Dell 교차 검증, 사전 안내 엔진
  04_Usb_Matching_And_Reboot.ps1         # 물리 USB 스캔, 4단계 NVRAM 매칭, Gate 2, 확인 후 일회성 재부팅
  05_PostSid_Spooler_Module.ps1          # 사후 프린터 스풀러 리셋, 호스트/클라이언트 상태 진단 및 사후 안내 엔진
  06_Gui_WinForms.ps1                    # 아산병원 디자인 시스템 기반 순수 GAC WinForms GUI (사전/사후/진단/WinPE)
  07_Main_Entry.ps1                      # WinPE 자동 분기, GUI 우선 실행 + 콘솔 TUI 폴백(--cli)
tools/
  Build-Tool.ps1                         # VERSION 기반 버전 주입(-Bump 지원), modules/ -> .bat 빌드 및 자동 검증
  Test-Tool.ps1                          # 빌드된 .bat 대상 178개 자동 단위/GUI 레이아웃/버전 정합성 테스트
docs/
  DIRECTION_AND_DECISIONS.md             # 방향 전환 결정 사항 및 단계별 진행 현황
  images/                                # README.md용 비식별 GUI 미리보기 PNG (01~03)
HANDOVER.md                              # 본 인수인계서
```

* **체계적 버저닝 및 릴리스 관리 규칙 (SemVer `MAJOR.MINOR.PATCH`):**
  * **단일 원본(`VERSION`):** 모든 버전 표기(배치 헤더, GUI 제목/상태바, 콘솔 배너, BIOS 진단 리포트)는 루트 [`VERSION`](VERSION) 파일에서 읽어 `tools\Build-Tool.ps1`이 빌드 시 `__TOOL_VERSION__`, `__BUILD_DATE__`, `__BUILD_COMMIT__` 플레이스홀더에 자동 주입하고 정합성을 검증함.
  * **버전 올리기 기준:**
    * `Patch` (`2.1.x`): 버그 수정, 오탐/파서 보정, UI 소폭 조정
    * `Minor` (`2.x.0`): 하위 호환 신규 기능(새 진단 항목, UX 개편 등)
    * `Major` (`x.0.0`): 구조·동작 방식의 큰 전환
  * **릴리스 절차:**
    1. `modules/` 수정 후 아래 빌드 명령(필요 시 `-Bump Patch|Minor|Major` 사용)으로 버전 갱신 및 `.bat` 재생성
    2. [`CHANGELOG.md`](CHANGELOG.md)에 `[vX.Y.Z]` 섹션 기록
    3. `tools\Test-Tool.ps1`으로 178개 테스트(레이아웃 감사·버전·`CHANGELOG.md` 정합성 포함) 전항목 통과 확인
    4. Git 커밋 후 `git tag -a vX.Y.Z -m "..."` 주석 태그 생성 및 원격 푸시(`--follow-tags`)
* **빌드 및 검증 명령:**
  ```powershell
  # 현재 VERSION 그대로 빌드 및 검증
  powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\Build-Tool.ps1
  # 버전 자동 증가(Patch / Minor / Major) 후 빌드
  powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\Build-Tool.ps1 -Bump Patch
  # 전체 자동 테스트 (178개: 코어 + 병원 기종/UASP/숨김 ESP + BIOS 교차 검증 + WinForms GUI 레이아웃 감사 + 버전 정합성)
  powershell -STA -NoProfile -ExecutionPolicy Bypass -File tools\Test-Tool.ps1
  ```
* **부가 운영 팁:** USB 루트 상대 경로 바로가기(`.lnk`) — 대상: `cmd.exe /c start "" "\유틸리티\SID_Change_Aux_Tool.bat"`, 시작 위치: `\`, 실행: 최소화. 콘솔 전용 실행이 필요할 때는 `--cli` 인자 추가.

---

## 4. 현재까지의 진행 상황 및 남은 작업 (5~6단계)

### 완료된 작업 (1~4단계 + 3종 실행 환경 하드닝 + `v2.1.0`/`v2.1.1` GUI·BIOS 교차 검증·버저닝)
* `tools/Build-Tool.ps1` 빌드·검증 파이프라인(ASCII, CRLF, 폴리글랏 헤더, PS AST 구문, `\uXXXX` 검사, 파괴적 명령 차단, 버전/플레이스홀더 정합성 검증) 및 `tools/Test-Tool.ps1` **132개 자동 테스트** 전체 통과.
* 배포 파일명 변경(`USB_Reboot.bat` → `SID_Change_Aux_Tool.bat`).
* 기존 결함 수정 완료: `sources\boot.wim` 가드 누락, 한국어 `bcdedit` OEM 인코딩 깨짐 및 `{fwbootmgr}` 식별자 파싱 버그, `U()` 백슬래시 예외 위험, Gate 0 취소 시 `bcdboot` 오호출, 빈 `internalDriveLetters` 시 Tier 4 누락 버그.
* 메인 메뉴(`[1]` 사전 / `[2]` 사후 / `[Q]` 종료) 및 사전 작업 STEP 1 → STEP 2 순서 강제(`IGNORE` 확인 문구) 구현 완료.
* 사후 작업 프린터 스풀러 리셋 및 호스트/클라이언트 상태 진단 구현 완료(로컬 HP G9 PC 읽기 전용 스모크 테스트 통과).
* 사전 작업 보강 완료: USB/WinPE 매체 보호 강화, 구형 MBR 활성 파티션 탐지·비파괴 전환(`_OLD` + `inactive/active`), 경량 WinPE `diskpart` 폴백(영문/한글).
* **3차 재귀 코드 리뷰 및 3종 실행 환경(쓰기 금지 USB / 로컬 / 공유폴더) 하드닝 완료 (`v2.0.1`):**
  * **부트스트랩(`01`):** WinPE(`X:`) 및 `LanmanServer` 중지 PC 무한 UAC 루프 제거(`fltmc` 폴백), 공유폴더(`\\`)/매핑 드라이브(`Z:\`) UAC 전 자동 로컬 스테이징 + RAM 로드 직후 임시 파일 자동 삭제, Base64 `-EncodedCommand`로 특수문자(`&`, `()`, `'`, 한글) 경로 대응, `Invoke-NativeOem` 30초 타임아웃 및 `System32` 절대 경로 해석, `Invoke-SafeReboot` 오류 표시, Ventoy/Rufus 숨김 FAT12·FAT16(`MbrType 1,4,6`) 추가.
  * **부트로더 모듈(`02`):** `Get-BusyDriveLetters`(`DriveInfo`+`PSDrive`+`Win32_MappedLogicalDisk`+`HKCU/HKU\*\Network`)로 매핑 드라이브 `Z:` 충돌 방지 및 후보 순서 `W` 우선화, 기존 드라이브 문자 덮어쓰기 차단 및 마운트 지연 1.2초 재시도/실패 시 자동 해제, 읽기 전용 디스크 `READONLY_PROTECTED` 보호, 정상 Windows `diskpart` 폴백 시에도 `SystemDrive` 다중 방어 잠금, 다중 ESP 전수 스캔, 대상 존재 충돌 가드, 한국어 `diskpart` `0 디스크...`/`문자` 헤더/다중 단어 파티션 파싱 보강.
  * **벤더·USB 매칭(`03`, `04`):** `Samsung|\bSEC\b` 단어 경계 보강, 동일 브랜드 USB vs 내장 SSD 모델명 교차 오매칭 방지 + 비-USB `SATA`/`NVMe` 배제, STEP 2 `[읽기 전용]` 태그 표시.
  * **사후 스풀러 모듈(`05`, `07`):** `HKEY_USERS\S-1-5-21-*\Printers\Connections` 조회(Over-the-Shoulder UAC 대응), `Get-NetFirewallRule` 폴백 죽은 코드 수정, `Spooler` 중지 시 `[판별 보류]` 역할 표기, `PrinterQueryError` RPC 경고 표시, `Spooler` 미존재 즉시 종료, 사용자 지정 `DefaultSpoolDirectory` 대응, `AsyncWaitHandle` 해제, `bcdboot` 성공/실패 피드백 및 공유폴더 실행 안내 배너 추가.
* **WinForms GUI + 다중 신호 BIOS 교차 검증 엔진 (`v2.1.0`):**
  * 순수 GAC WinForms GUI(`06_Gui_WinForms.ps1`) 도입(사전 STEP 1→2 잠금 UX, 물리 USB/NVRAM 가시성 목록, 사후 스풀러 탭, 상황 맞춤 추천 액션 배너, BIOS 교차 검증 상세 창, WinPE 비상 창) + `--cli`/경량 WinPE 자동 콘솔 폴백(`07_Main_Entry.ps1`).
  * 3중 신호 부팅 모드·Secure Boot 교차 검증, HP `Legacy USB Boot` 오탐 제거, Dell 숫자 열거형/보조 네임스페이스 대응, WMI vs NVRAM `Conflict` 감지 엔진 구축.
* **체계적 SemVer 버저닝 + WinForms `X` 버튼 종료 예외 수정 (`v2.1.1`):**
  * `VERSION` + `CHANGELOG.md` + `Build-Tool.ps1 -Bump Major|Minor|Patch` 자동 버전 주입·검증 체계 구축 및 Git 태그(`v2.1.1`) 적용.
  * PowerShell 동적 스코프로 인해 `New-SidAuxMainForm` 반환 후 `OnFormClosed`/클릭 핸들러에서 로컬 변수가 `$null`이 되던 결함을 `$ui`/`$form.Tag` + `.GetNewClosure()` + Null-Safe `Dispose()`로 근본 해결. 실제 `ShowDialog()` → `Close()` → `OnFormClosed` 및 버튼 `PerformClick()` 자동 테스트를 추가하여 회귀 차단.

* **아산병원 데스크톱 디자인 시스템(`asan-desktop-ui`) 전면 개편 및 재귀 코드·시각 감사 (`v2.2.0`):**
  * 4영역 고정 셸(`#005658`/`#006769`/`#F68B1F`/`#0B4F51`), 자체 GDI+ 벡터 심볼·창 아이콘, `OwnerDrawFixed` 번호형 탭, `DataGridView` 단일 통합 USB 표, 점선 비활성 버튼 + 부모 라우팅 사유 툴팁, 비동기 Runspace 프린터 스풀러 초기화, 오류 자동 진단 리포트 저장(민감정보 `[REDACTED]` 마스킹), 상용 한국어 UX 라이팅 전면 적용.
  * 재귀 코드 리뷰 및 실제 렌더링 스크린샷 시각 감사로 발견한 항목 반영: 내장 디스크 `DiskNumber` 오름차순 정렬, 비-OEM 보드 `Standard` 대신 실제 보드사 표기, `NVRAM 미등록` 컬럼 잘림 해소, 선택된 충돌 행 적색 유지, 모달 창 아이콘 통일, `Save-LocalDiagnosticReportFile` 원본 폴더 쓰기 차단, `1040×720`/`960×640`(확장 로그 포함) 자동 레이아웃 감사 포함 **152개 테스트 전체 통과**.

### 다른 PC AI 에이전트 이어받기 가이드
* **코드 수정 원칙:** `SID_Change_Aux_Tool.bat`를 직접 수정하지 말고 반드시 `modules/*.{bat,ps1}`를 수정한 뒤 `tools/Build-Tool.ps1`(기능·버그 변경 시 `-Bump Patch|Minor|Major` 병행 및 `CHANGELOG.md` 갱신)로 재생성·검증하고 `tools/Test-Tool.ps1`을 실행할 것. UI 변경 시 반드시 `asan-desktop-ui` 스킬 지침에 따라 자동 레이아웃 감사 및 실제 렌더링 스크린샷 시각 감사를 수행할 것.
* **현재 위치:** `v2.3.0` (병원 전체 PC 인벤토리 `S4~S9`/`H0~H8`/`D1·D8` 세대별 프로필 반영, UASP 외장 NVMe/SSD 인클로저 PnP 분류, 무파일 `QueryDosDeviceW` 숨김 EFI 커널 볼륨 매핑, HP G8/G9 체크박스·한글 BIOS·Dell·Lenovo·4중 신호 `Win32_DeviceGuard` Secure Boot 교차 검증, **178개 자동 테스트** 및 픽셀 시각 감사 통과 상태). 사용자가 5단계 실장비 테스트 결과를 공유하면 발견된 현장 이슈/튜닝을 `modules/`에 반영하고 버전을 올려 재빌드·재검증 후 6단계(최종 문서 확정)를 마무리하면 됨.

### 남은 작업 — 5단계 실장비 검증 체크리스트
1. **실행 환경 3종 + WinForms GUI 기본 동작 검증 (쓰기 금지 USB / 로컬 / 공유폴더):**
   * WinForms GUI 정상 실행, 추천 액션 배너 표시, 각 버튼 클릭 및 창 우측 상단 `X` 버튼 정상 종료(예외 팝업 없음) 확인; `--cli` 콘솔 폴백 정상 동작 확인.
   * 쓰기 금지 USB에서 실행 시 쓰기 오류 없이 정상 동작 및 STEP 2 `[읽기 전용]` 표기 확인.
   * 공유폴더(`\\서버\공유` 및 매핑 드라이브 `Z:\`)에서 **일반 더블클릭** 시 로컬 스테이징 → UAC 상승 → 메모리 실행 안내 배너 출력 및 임시 파일 잔존 없음 확인.
   * 공유폴더 접속(`Z:` 매핑) 상태에서 STEP 1 ESP 임시 마운트 시 `Z:`와 충돌하지 않는지 확인.
2. **HP Elite Tower 800 G9 (관리자 권한 실행):**
   * 사전 작업 진입 → STEP 1 정상 표시 → STEP 2에서 HP WMI(`USB Storage Boot`와 `Legacy USB Boot` 분리 판정, `Fast Boot`) 및 BIOS 교차 검증 상세 리포트 확인.
   * `[D]` / 진단 창의 NVRAM 원본(한글 깨짐 없음 확인) 및 `[L]` 디스크 진단 출력 확인.
   * 외장 SSD/USB 연결 후 4단계 NVRAM 매칭 및 `[O]`(장치 사용) / 일회성 부팅 검증.
3. **Samsung S8 (AMI BIOS + 보조 구형 HDD):**
   * STEP 1에서 보조 HDD 구형 GPT EFI 또는 MBR 활성 부트로더가 `[충돌 위험]`으로 잡히고 STEP 2가 잠기는지 확인.
   * `[A]` 원스톱 조치 취소(`N`) 시 `bcdboot` 건너뜀 확인 → 다시 `[A]` 승인(`Y`) 후 비활성화 및 `bcdboot` 성공 메시지 확인.
   * STEP 2에서 `BIOS USB Boot 옵션`이 `[확인 불가]`로 정상 표기되는지 확인 후 WinPE SID 작업 → 재부팅 시 부팅 충돌 미발생 검증.
4. **Dell 데스크탑 (DCM 설치 / 미설치):**
   * DCM 설치 시 `DCIM_BIOSEnumeration` 파싱, 미설치 시 `UnverifiableDell`(`[확인 불가]`) 표기 확인.
5. **실제 WinPE (PhoenixPE 등 `X:` 환경):**
   * `SID_Change_Aux_Tool.bat` 실행 시 UAC 루프 없이 `[WinPE 비상 모드]` 자동 진입 확인.
   * Storage 모듈 유/무에 따른 정상 스캔 또는 `diskpart` 호환 모드 동작 및 `EFI`↔`EFI_OLD`, MBR `_OLD`↔원복 검증.
6. **사후 작업 실전 검증 (메인 프린터 PC + 클라이언트 PC):**
   * SID 변경 후 메인 프린터 PC에서 `[2]` 실행 → `[호스트(메인 프린터 PC)]` 판별, 공유 프린터/방화벽/네트워크 프로필 표시 확인 → 스풀러 리셋 실행.
   * 클라이언트 PC에서 `[2]` 실행 → `[클라이언트]` 판별, 연결된 네트워크 프린터 및 호스트 SMB(445) 응답 표시 확인 → 스풀러 리셋 실행 → 공유 프린터 테스트 인쇄 정상 확인.
7. **6단계 마무리:** 실장비 검증 중 발견된 튜닝 사항 반영 후 최종 `Build-Tool.ps1` / `Test-Tool.ps1` 통과 및 문서 최종 확정.

---

## 5. 절대 준수 제약사항 (계속 유효)

1. **100% 순수 ASCII 파일 유지 (최우선 절대 규칙):**
   * `.bat` 및 `modules/` 내부에 한글 등 비-ASCII 문자를 단 1바이트도 직접 입력하지 말 것 (`Build-Tool.ps1`이 강제 검증).
   * 모든 한글은 `U()` 함수와 `\uXXXX` 유니코드 이스케이프로 작성하고, 줄바꿈은 Windows `CRLF` 유지.
2. **단일 하이브리드 파일 구조 유지:**
   * 배포물은 `SID_Change_Aux_Tool.bat` 단일 파일 1개로 유지(`SELF_PATH=%~f0`, `cd /d "%SystemRoot%\System32"` 래퍼 보존).
3. **무확인 즉시 재부팅 금지:**
   * 부팅 가능한 USB가 1개만 감지되더라도 반드시 목록 출력 및 사용자 확인 후 재부팅.
4. **비파괴 부트로더 처리 원칙:**
   * 파티션 삭제(`delete partition`)·포맷(`format`) 절대 금지. GPT는 `EFI` ↔ `EFI_OLD`, MBR은 `bootmgr`/`Boot` ↔ `_OLD` (+ `inactive`/`active`) 방식만 사용.
5. **WMI 미지원 보드 `ON` 추정 금지:**
   * 삼성(AMI), Dell DCM 미설치 등 WMI 조회 불가 환경에서는 절대 `ON(활성화)`으로 단정하지 않고 `[확인 불가]` 또는 `[비활성화 의심]` 표기.
6. **보호 디스크·OS·WinPE 매체 수정 금지:**
   * 정상 Windows의 `IsBoot`/`IsSystem` 디스크, `ntoskrnl.exe` OS 파티션, 외장 USB 및 WinPE/설치 매체(`sources\boot.wim`, `EFI\BOOT` 단독 등)는 수정 대상에서 원천 차단.
