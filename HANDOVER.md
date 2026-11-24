# [인수인계서] Windows UEFI USB 부팅 도우미 및 다중 디스크 EFI 충돌 방지 도구 (`USB_Reboot.bat`)

> [!IMPORTANT]
> **2026-11-25 방향 전환:** 이 도구는 "WinPE 기반 SID 변경 작업의 사전·사후 보조 툴"로 확장됩니다.
> 새 방향성, 사용자 결정 사항, 단계별 실행 계획은 [docs/DIRECTION_AND_DECISIONS.md](docs/DIRECTION_AND_DECISIONS.md)를 먼저 읽으세요.
> 아래 내용(기존 사양 및 6대 절대 제약사항)은 계속 유효합니다.

---

## 1. 프로젝트 개요 및 최종 목표

* **프로그램 목적**
  * Windows 환경에서 메인보드 부트 메뉴 단축키(F8, F9, F10, F12 등)를 연타하지 않고, 연결된 UEFI 부팅 가능 외장 USB / 외장 SSD(WinPE 등)로 일회성 부팅(`bcdedit /set {fwbootmgr} bootsequence`) 또는 고급 부팅/BIOS 진입을 자동화하는 단일 유틸리티 제작.
  * WinPE에서 SID 변경 등의 작업을 수행하기 전, **보조 데이터 디스크(구형 HDD 등)에 잔존한 구형 EFI 파티션으로 인한 부팅 충돌(자동 복구 진입)을 사전 탐지·무력화**하고, 사고 발생 시 WinPE 환경에서 사후 비상 복구까지 지원하는 올인원 현장 도구 구축.
* **실행 환경**
  * **OS:** Windows 10 / 11 (UEFI 모드) 및 WinPE (`X:` 환경, 예: PhoenixPE).
  * **주 타깃 장비:** 삼성(Samsung S8/S9 등 AMI BIOS), HP(구형 G1~G5 / 신형 G6~G9+), Dell(구형 OptiPlex 3040~3070 / 신형 3080~7010+) 데스크탑 및 일반 표준 UEFI 보드.
  * **주요 부팅 매체:** 다중 파티션 구조(`NTFS + exFAT + Hidden EFI FAT`)의 WinPE USB 및 외장 NVMe/SSD 인클로저(예: Seagate FireCuda SSD).
  * **권한 및 의존성:** 관리자 권한 필수(미보유 시 자동 UAC 상승). 외부 실행 파일이나 별도 `.ps1` 파일 없이 Windows 기본 내장 도구(`PowerShell`, `diskpart`, `bcdedit`, `mountvol`, `shutdown`, `bcdboot`)만 사용.
* **사용자 시나리오**
  1. **사전 점검 및 WinPE 진입 (정상 Windows):** `USB_Reboot.bat` 실행 → 내장 디스크 EFI 충돌 사전 탐지(Gate 0) → 충돌 시 구형 HDD의 `EFI`를 `EFI_OLD`로 비활성화 + 현재 SSD NVRAM 등록 → BIOS 차단 요소 확인(Gate 1) → 연결된 WinPE USB 선택 및 확인 후 일회성 재부팅.
  2. **사후 비상 복구 (WinPE `X:`):** SID 작업 후 부팅이 꼬여 WinPE로 부팅한 상태에서 동일한 `USB_Reboot.bat` 실행 → 자동으로 `[WinPE 비상 모드]` 진입 → 구형 HDD의 `EFI` ↔ `EFI_OLD` 전환.

---

## 2. 핵심 기능 명세

### 2.1 실행 환경 자동 판별 및 벤더 식별
* `$env:SystemDrive -eq "X:"`인 경우 **WinPE 비상 모드**로 자동 분기하여 USB 부팅 로직을 건너뛰고 내장 디스크 EFI 관리 화면만 표시.
* 정상 Windows에서는 `Win32_ComputerSystem`, `Win32_BaseBoard`, `Win32_BIOS`를 조회해 제조사를 `Samsung`, `HP`, `Dell`, `Standard`로 분류.
* `bcdedit /enum {current}`에서 `winload.efi` 존재 여부로 UEFI 모드 검증 (Legacy MBR 모드일 경우 제조사별 부트 메뉴 단축키 안내 후 종료).

### 2.2 Gate 0: 내장 다중 디스크 EFI 충돌 사전 탐지 및 원스톱 조치
* **보호 디스크 자동 잠금:** 정상 Windows에서 `Get-Partition`의 `IsBoot`(현재 OS) 및 `IsSystem`(실제 활성 부팅 EFI) 디스크 번호를 추출해 수정 불가 보호 목록으로 지정.
* **부팅 분리(`SplitBoot`) 감지:** `IsBoot` 디스크와 `IsSystem` 디스크가 다를 경우 `[위험 - 부팅 분리됨]`으로 판정하고 자동 비활성화를 차단.
* **보조 디스크 ESP 정밀 검사:** USB 디스크를 제외한 내장 온라인 디스크 중 GPT EFI GUID(`{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}`) 파티션을 탐색.
  * 기존 문자가 있으면 그대로 사용, 없으면 빈 임시 문자(`Z`~`M` 순)를 `diskpart`로 마운트 → `EFI` / `EFI_OLD` 폴더 존재 여부 확인 → 작업 직후 임시 문자 자동 해제(`remove letter` + `mountvol /d` 폴백).
  * **안전장치:** 대상 파티션에 `Windows\System32\ntoskrnl.exe`나 `sources\boot.wim`이 있으면 OS/설치 매체로 간주하고 즉시 차단. `EFI`와 `EFI_OLD`가 공존하면 수동 확인 안내 후 중단.
* **원스톱 조치(`[A]`):** 파티션 삭제 대신 비파괴 이름 변경(`EFI` → `EFI_OLD`, 내부 `Backup(AppCheck)` 등 사용자 숨김 백업 데이터 보존) 수행 후, 사용자 확인을 거쳐 `bcdboot %SystemRoot% /f UEFI`로 현재 OS SSD를 UEFI NVRAM 1순위로 정식 등록.

### 2.3 Gate 1: BIOS 보안 및 차단 요소 사전 감지 (3사 구형/신형 대응)
* **Secure Boot:** `Confirm-SecureBootUEFI`로 확인. 활성화 시 경고.
* **BIOS USB Boot & Fast Boot 상태 조회:**
  * **HP:** `root\HP\InstrumentedBIOS` (`HP_BIOSSetting`) 조회. 구형 `*Enable,Disable` 형식과 신형 `CurrentValue` 속성 모두 파싱. `USB Storage Boot` 계열 및 `Fast Boot` 동시 감지.
  * **Dell:** `root\dcim\sysman` (`DCIM_BIOSEnumeration`) 조회. 구형(`UsbBoot`, `BootUsb`) 및 신형(`EnableUsbBootSupport`, `UsbBootSupport`, `ExternalUsb`) 속성명과 `Fastboot`(`Minimal` 여부) 동시 감지. Dell Command | Monitor 미설치 시 `UnverifiableDell`로 표기.
  * **Samsung (AMI BIOS) 및 WMI 미지원 보드:** WMI 조회 불가하므로 절대 `ON`으로 추정하지 않고 `[확인 불가]`로 표기. NVRAM 문자열 검사 시 내장 SSD 브랜드(`Samsung`, `Crucial`, `Micron` 등)와 내장 SATA/NVMe 항목을 엄격히 제외.
* **제조사별 BIOS 메뉴 힌트 자동 출력:** HP(F10), Dell(F2), Samsung(F2)별 정확한 USB Boot / Fast Boot 설정 경로 안내.

### 2.4 물리 USB 감지 및 NVRAM 4단계 교차 매칭
* `Get-Disk`로 온라인 외장 USB/외장 SSD(`BusType -eq 'USB'`, `IsRemovable`, `USBSTOR|UASP`)만 필터링하여 내장 디스크 및 NVRAM 과거 유령 항목 배제.
* MSR/복구 파티션을 제외하고 GPT EFI GUID, MBR FAT/EFI 타입(`11, 12, 14, 239`), FAT/FAT32/exFAT, 실제 부팅 파일(`BOOTX64.EFI`, `BCD`) 기준으로 부팅 가능 여부 판별.
* `bcdedit /enum firmware` 파싱 결과와 4단계 우선순위로 매칭:
  1. `[정확 일치 - 드라이브]` (`partition=X:`)
  2. `[정확 일치 - 모델명]` (디스크 `FriendlyName` 단어 매칭)
  3. `[파티션 일치]` (`Partition N` + UEFI/USB 키워드)
  4. `[범용 UEFI USB 항목]` (`USB Hard Drive`, `Removable Device` 등)

### 2.5 Gate 2 (미등록/Hot-Plug 분기) 및 일회성 재부팅
* 물리 USB는 인식됐으나 NVRAM 매칭 결과가 0건일 때:
  * BIOS USB Boot가 확실히 `Enabled`이고 `Fast Boot` 경고가 없으면 **Hot-Plug**로 판단 → `Enter/O` (`shutdown /r /o /f /t 0`, Windows 고급 부팅 '장치 사용') 기본 권장.
  * 그 외(차단 의심, 삼성/AMI, Fast Boot 경고 등) → `Enter/B` (`shutdown /r /fw /f /t 0`, BIOS 펌웨어 설정 진입) 기본 권장.
* 매칭된 USB가 1개 이상이면 목록 출력 후 사용자 확인(`Enter` 또는 번호 입력)을 거쳐 `bcdedit /set {fwbootmgr} bootsequence <GUID>` 실행 후 즉시 재부팅(`shutdown /r /f /t 0`). 실패 시 고급 부팅(`[O]`) 폴백 제공.

---

## 3. UI/UX 및 입출력 구조

* **화면 구성 (콘솔 TUI, UTF-8 출력)**
  1. **헤더:** 시스템 제조사 및 모델명 (`[Samsung/HP/Dell/Standard] (Model)`).
  2. **상태 요약 대시보드:**
     * `Secure Boot` 상태 (녹색/적색)
     * `BIOS USB Boot 옵션` 상태 및 상세 근거 (녹색/황색/적색)
     * `BIOS Fast Boot 옵션` 경고 (해당 시 황색)
     * `BIOS Hint` (제조사별 BIOS 단축키 및 메뉴 경로)
     * `내장 디스크 EFI 충돌` 상태 (녹색/적색)
  3. **단계별 게이트 메뉴 (Gate 0 → Gate 1 → Gate 2 → USB 선택 메뉴)**
* **공통 단축키 및 메뉴 동작**
  * `[Enter]`: 각 게이트의 기본 권장 동작 실행 (Gate 0: 원스톱 조치, Gate 1: BIOS 진입, Gate 2: 장치 사용 또는 BIOS 진입, 최종 메뉴: 단일 USB 즉시 재부팅).
  * `[A]`: 구형 EFI 일괄 비활성화 + NVRAM 정식 등록 (Gate 0).
  * `[E]`: 내장 디스크 EFI 관리 화면 (`EFI` ↔ `EFI_OLD` 개별 토글).
  * `[O]`: Windows 고급 부팅('장치 사용')으로 재부팅.
  * `[B]`: UEFI BIOS 펌웨어 설정으로 재부팅.
  * `[D]`: `bcdedit /enum firmware` 원본 디버그 출력.
  * `[L]`: `Get-Disk` / `Get-Partition` 진단 테이블 출력.
  * `[I]`: 경고 무시하고 다음 단계 진행.
  * `[Q]`: 취소 및 종료.
* **입출력 형식**
  * **입력:** 키보드 단일 문자 또는 숫자 입력(`Read-Host`).
  * **출력:** 콘솔 표준 출력(색상 강조). 별도 로그 파일 생성 없음. 임시 파일 생성 없이 파이프라인으로 `diskpart` 제어.
  * **부가 운영 팁:** USB 루트 상대 경로 바로가기(`.lnk`) 지원 — 대상: `cmd.exe /c start "" "\유틸리티\USB_Reboot.bat"`, 시작 위치: `\`, 실행: 최소화.

---

## 4. 기술 스택 및 아키텍처

* **사용 언어 및 실행 구조:** Batch + PowerShell 단일 파일 하이브리드 (`<# : ... #>` 폴리글랏 패턴).
  * 상단 Batch 래퍼: `SELF_PATH=%~f0` 저장 → `cd /d "%SystemRoot%\System32"` 고정 → `net session` 관리자 권한 체크 및 UAC 상승 → `ReadAllText` + `Invoke-Expression`으로 PowerShell 본문 실행.
* **주요 내장 API / 도구:**
  * PowerShell Storage 모듈 (`Get-Disk`, `Get-Partition`, `Get-Volume`)
  * CIM/WMI (`Get-CimInstance`: `Win32_*`, `root\HP\InstrumentedBIOS`, `root\dcim\sysman`)
  * UEFI/부팅 유틸리티 (`Confirm-SecureBootUEFI`, `bcdedit`, `bcdboot`, `diskpart`, `mountvol`, `shutdown`)
* **모듈화 구조 (단일 파일 내 함수 분리 권장)**
  * `U()` : 유니코드 이스케이프 한글 디코더
  * `Show-BcdDebug` / `Show-DiskDebug` : 현장 진단용 디버그 뷰어
  * `Invoke-WithEspMount` : 임시 마운트/자동 해제 래퍼 (`try/finally` 보장)
  * `Get-InternalEfiReport` / `Invoke-EspToggle` / `Show-EfiManager` : 다중 디스크 EFI 탐지 및 비활성화 모듈
  * 메인 파이프라인: WinPE 분기 → 벤더/BIOS 진단 → Gate 0 → Gate 1 → USB 스캔 및 NVRAM 매칭 → Gate 2 → 일회성 부팅 실행

---

## 5. 현재까지의 진행 상황 및 미해결 이슈

### 이미 구현 완료된 기능
* 100% 순수 ASCII 단일 하이브리드 `.bat` 아키텍처 및 한글 경로/공백 대응.
* ASRock B650M 등 일반 보드에서 미연결 NVRAM 유령 항목 필터링 완료.
* HP G9 외장 SSD(Seagate FireCuda, 숨김 EFI 파티션) 인식 및 4단계 NVRAM 매칭 로직 구현 완료.
* 삼성 S8(AMI BIOS)에서 내장 삼성 SSD 브랜드명으로 인해 `USB Boot`가 `ON`으로 오인식되던 버그 수정 완료.
* HP 구형(`*Enable,Disable`)·신형(`CurrentValue`) 및 Dell 구형·신형 WMI 파싱, `Fast Boot` 감지, 제조사별 BIOS 힌트 출력 구현 완료.
* Gate 0 (내장 다중 디스크 EFI 충돌 사전 탐지, 부팅 분리 차단, `EFI` → `EFI_OLD` 비파괴 비활성화, `bcdboot` NVRAM 등록) 및 WinPE(`X:`) 비상 모드 통합 완료.

### 작성 중이거나 오류 수정·검증이 필요한 기능
* **통합판 실장비 검증 미완료:** Gate 0(EFI 충돌 탐지)과 보강된 HP/Dell/삼성 BIOS 로직이 합쳐진 최신 통합판에 대한 실장비 테스트 필요.
* **WinPE 환경의 PowerShell Storage 모듈 호환성 확인 필요:** 일부 경량 WinPE(PhoenixPE 등)에서 `Get-Disk` / `Get-Partition` cmdlet이 누락되거나 비정상 동작할 경우, WinPE 비상 모드에서 `diskpart` 텍스트 파싱 폴백이 필요할 수 있음.

### 앞으로 남은 작업 목록 (우선순위 순)
1. **삼성 S8(AMI BIOS) 실장비 검증:** `BIOS USB Boot 옵션`이 `[확인 불가]`로 정상 표기되는지, 구형 HDD 연결 상태에서 Gate 0 원스톱 조치 후 SID 작업 및 재부팅 시 부팅 충돌이 재발하지 않는지 확인.
2. **HP Elite Tower 800 G9 재검증:** 수정된 HP WMI(`USB Storage Boot` + `Fast Boot`) 파싱 동작 확인, `[D]`/`[L]` 출력으로 외장 SSD NVRAM 매칭 정확도 튜닝, `[O]`(장치 사용) 부팅 최종 확인.
3. **Dell 데스크탑 실장비 검증:** Dell Command | Monitor 설치/미설치 환경 각각의 WMI 동작 및 폴백 표기 확인.
4. **WinPE 비상 모드 폴백 보강 (필요 시):** 실제 사용 중인 PhoenixPE에서 `Get-Disk` 실행 여부를 테스트하고, 미지원 시 순수 `diskpart` 기반 폴백 로직 추가.

---

## 6. 절대 준수 제약사항

1. **100% 순수 ASCII 파일 유지 (최우선 절대 규칙):**
   * `.bat` 파일 내부에 한글 등 비-ASCII 문자를 단 1바이트도 직접 입력하지 말 것 (CMD 배치 파서의 바이트 오프셋 밀림 오류 방지).
   * 화면에 출력할 모든 한글은 반드시 PowerShell `U()` 함수(`[Regex]::Unescape`)와 `\uXXXX` 유니코드 이스케이프로만 작성할 것. (줄바꿈은 Windows `CRLF` 권장)
2. **단일 하이브리드 파일 구조 유지:**
   * `.ps1` 등 외부 스크립트 파일을 분리하지 않고 `USB_Reboot.bat` 단일 파일로만 배포·실행할 것.
   * 상단 래퍼의 `set "SELF_PATH=%~f0"` 및 `cd /d "%SystemRoot%\System32"` 고정 로직을 임의로 제거하지 말 것.
3. **무확인 즉시 재부팅 금지:**
   * 부팅 가능한 USB가 1개만 감지되더라도 즉시 재부팅하지 말고, 반드시 물리 디스크 정보와 NVRAM 매칭 결과를 출력한 뒤 사용자 확인(`Enter` 또는 번호)을 거쳐 재부팅할 것.
4. **비파괴 EFI 처리 원칙:**
   * 보조 디스크의 구형 EFI 충돌 해결 시 파티션을 삭제(`delete partition`)하거나 포맷하지 말고, 반드시 `EFI` ↔ `EFI_OLD` 폴더 이름 변경 방식만 사용할 것 (내부 숨김 백업 데이터 보존 및 즉시 원상 복구 보장).
5. **WMI 미지원 보드 `ON` 추정 금지:**
   * 삼성(AMI) 및 Dell DCM 미설치 등 WMI로 BIOS 설정을 직접 읽을 수 없는 환경에서는 절대 `BIOS USB Boot`를 `ON(활성화)`으로 단정하지 말고 `[확인 불가]` 또는 `[비활성화 의심]`으로 표기할 것.
6. **보호 디스크 및 OS 파티션 수정 금지:**
   * 정상 Windows에서 `IsBoot` 또는 `IsSystem`으로 식별된 디스크는 어떤 경우에도 EFI 비활성화 대상에서 원천 차단할 것.
