# [인수인계서] SID 변경 사전·사후 보조 툴 (`SID_Change_Aux_Tool.bat`)

> [!IMPORTANT]
> **2026-11-25~26 구현 현황 (1~4단계 + 3종 실행 환경 하드닝 완료):**
> 기존 `USB_Reboot.bat`을 **WinPE 기반 SID 변경 작업의 사전·사후 보조 툴(`SID_Change_Aux_Tool.bat`)**로 확장하는 **1~4단계 코드 구현, 3차 재귀 코드 리뷰(쓰기 금지 USB / 로컬 / 공유폴더 실행 환경 대응) 및 자동 검증(빌드 검증 + 86개 단위/스모크 테스트)이 완료**되었습니다.
> 상세 의사결정 배경 및 진행 표는 [docs/DIRECTION_AND_DECISIONS.md](docs/DIRECTION_AND_DECISIONS.md)를 참고하세요.
> 다음 단계는 **5단계 실장비 검증(Samsung S8, HP G9, Dell, 실제 WinPE, 메인/클라이언트 공유 프린터, 3종 실행 매체)**입니다.

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

### 2.1 실행 환경 자동 판별 및 메인 메뉴 (`modules/06_Main_Entry.ps1`)
* `$env:SystemDrive -eq "X:"`인 경우 **WinPE 비상 모드**로 자동 분기하여 USB 부팅 로직을 건너뛰고 내장 디스크 부트로더(GPT EFI / MBR) 관리 화면 표시.
* 정상 Windows에서는 제조사(`Samsung`, `HP`, `Dell`, `Standard`) 및 모델명을 표시하고 3개 메뉴 제공:
  * `[1] SID 변경 사전 작업 (잔존 부트로더 탐지/제거 -> USB 부팅)`
  * `[2] SID 변경 사후 작업 (프린터 스풀러 리셋)`
  * `[Q] 종료`
* UEFI 필수 검사는 `[1] 사전 작업` 내부로 이동하여, `[2] 사후 작업`은 USB 없이도, Legacy PC에서도 즉시 실행 가능.
* **실행 매체별 부트스트랩 안전장치 (`modules/01_Bootstrap_And_Helpers.bat`):**
  * **쓰기 금지 USB / 읽기 전용 폴더:** 원본 폴더에 쓰기 0건(RAM 전용 실행). `IsReadOnly` 디스크는 `READONLY_PROTECTED`로 자동 보호.
  * **공유폴더(`\\서버\공유`) / 네트워크 매핑 드라이브(`Z:\`):** 일반 더블클릭 시 UAC Split-Token으로 경로·자격증명이 소실되는 문제를 막기 위해, 권한 상승 직전 로컬 임시 폴더(`%TEMP%` → `%LOCALAPPDATA%\Temp` → `Public\Documents`)로 일시 스테이징 후 Base64 `-EncodedCommand`로 권한 상승하며, RAM 로드 직후 임시 파일을 즉시 삭제(원본 무변경). *(운영 팁: 공유폴더/매핑 드라이브에서는 우클릭 '관리자 권한으로 실행' 대신 **일반 더블클릭**을 사용하세요.)*
  * **로컬 특수문자 경로 및 WinPE/`LanmanServer` 중지 환경:** `SystemDrive == X:` 즉시 통과 및 `fltmc` 보조 관리자 판별로 무한 UAC 루프 방지, Base64 실행으로 `&`, `(`, `)`, `'`, 공백, 한글 경로 깨짐 방지.
  * **안정성 보강:** `Invoke-NativeOem` 30초 기본 타임아웃 + `System32` 절대 경로 우선 해석, `Invoke-SafeReboot` 종료 코드 검증(실패 시 원인 표시).

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

### 2.3 사전 작업 STEP 2: BIOS 진단 및 USB NVRAM 4단계 매칭 (`modules/03_Vendor_Bios_Diagnostics.ps1`, `modules/04_Usb_Matching_And_Reboot.ps1`)
* **OEM 안전 네이티브 실행(`Invoke-NativeOem`):** 한국어 Windows(CP949)에서 `[Console]::OutputEncoding = UTF8` 설정으로 인해 `bcdedit`/`diskpart` 출력이 깨지던 결함을 해결. 실행 중 임시 OEM 코드페이지 전환 + 스트림 OEM 디코딩 + `finally` UTF-8 복원.
* **`bcdedit /enum firmware` 파서 보강:** 영문(`identifier/description/path/device`) 및 한글(`식별자/설명/경로/장치`) 정확 파싱, `{fwbootmgr}` 내 `displayorder` GUID 오인식 방지, 한글 `Windows 부팅 관리자` 필터링, 내장 드라이브 목록이 비어 있을 때의 빈 `Device` 누락 버그 수정.
* **BIOS 보안·차단 요소 감지 (Gate 1):** Secure Boot, HP WMI(`HP_BIOSSetting` 구형/신형 + `Fast Boot`), Dell WMI(`DCIM_BIOSEnumeration` + `Fastboot`), Samsung/AMI 미지원 `[확인 불가]` 원칙 유지.
* **물리 USB 스캔 및 4단계 매칭 + Gate 2:** 드라이브 문자 → 모델명 → 파티션 번호 → 범용 UEFI USB 순 매칭. `[R]` 다시 스캔 지원. 매칭 0건 시 Hot-Plug(`[O]`) vs BIOS 차단(`[B]`) 분기. 매칭 1건 이상이면 반드시 사용자 확인 후 `bcdedit /set {fwbootmgr} bootsequence <GUID>` 실행 및 재부팅.

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
modules/
  01_Bootstrap_And_Helpers.bat           # UAC 래퍼, 안전한 U(), Invoke-NativeOem, bcdedit 파서, [D]/[L]
  02_Bootloader_Conflict_Module.ps1      # GPT EFI + MBR 활성 부트로더 탐지/토글, USB/WinPE 가드, diskpart 폴백
  03_Vendor_Bios_Diagnostics.ps1         # 벤더 식별, UEFI 검사, Secure Boot/HP/Dell/Samsung 진단, Gate 1
  04_Usb_Matching_And_Reboot.ps1         # 물리 USB 스캔, 4단계 NVRAM 매칭, Gate 2, 확인 후 일회성 재부팅
  05_PostSid_Spooler_Module.ps1          # 사후 프린터 스풀러 리셋 + 호스트/클라이언트 상태 진단
  06_Main_Entry.ps1                      # WinPE 자동 분기, 메인 메뉴, 사전 STEP 1 -> STEP 2 순서 강제
tools/
  Build-Tool.ps1                         # modules/ -> SID_Change_Aux_Tool.bat 빌드 및 6종 자동 검증
  Test-Tool.ps1                          # 빌드된 .bat 대상 86개 자동 단위/스모크 테스트
docs/
  DIRECTION_AND_DECISIONS.md             # 방향 전환 결정 사항 및 단계별 진행 현황
HANDOVER.md                              # 본 인수인계서
```

* **빌드 및 검증 명령:**
  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Build-Tool.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Tool.ps1
  ```
* **부가 운영 팁:** USB 루트 상대 경로 바로가기(`.lnk`) — 대상: `cmd.exe /c start "" "\유틸리티\SID_Change_Aux_Tool.bat"`, 시작 위치: `\`, 실행: 최소화.

---

## 4. 현재까지의 진행 상황 및 남은 작업 (5~6단계)

### 완료된 작업 (1~4단계 + 3종 실행 환경 하드닝)
* `tools/Build-Tool.ps1` 빌드·검증 파이프라인(ASCII, CRLF, 폴리글랏 헤더, PS AST 구문, `\uXXXX` 검사, 파괴적 명령 차단) 및 `tools/Test-Tool.ps1` **86개 자동 테스트** 전체 통과.
* 배포 파일명 변경(`USB_Reboot.bat` → `SID_Change_Aux_Tool.bat`).
* 기존 결함 수정 완료: `sources\boot.wim` 가드 누락, 한국어 `bcdedit` OEM 인코딩 깨짐 및 `{fwbootmgr}` 식별자 파싱 버그, `U()` 백슬래시 예외 위험, Gate 0 취소 시 `bcdboot` 오호출, 빈 `internalDriveLetters` 시 Tier 4 누락 버그.
* 메인 메뉴(`[1]` 사전 / `[2]` 사후 / `[Q]` 종료) 및 사전 작업 STEP 1 → STEP 2 순서 강제(`IGNORE` 확인 문구) 구현 완료.
* 사후 작업 프린터 스풀러 리셋 및 호스트/클라이언트 상태 진단 구현 완료(로컬 HP G9 PC 읽기 전용 스모크 테스트 통과).
* 사전 작업 보강 완료: USB/WinPE 매체 보호 강화, 구형 MBR 활성 파티션 탐지·비파괴 전환(`_OLD` + `inactive/active`), 경량 WinPE `diskpart` 폴백(영문/한글).
* **3차 재귀 코드 리뷰 및 3종 실행 환경(쓰기 금지 USB / 로컬 / 공유폴더) 하드닝 완료 (2026-11-25~26):**
  * **부트스트랩(`01`):** WinPE(`X:`) 및 `LanmanServer` 중지 PC 무한 UAC 루프 제거(`fltmc` 폴백), 공유폴더(`\\`)/매핑 드라이브(`Z:\`) UAC 전 자동 로컬 스테이징 + RAM 로드 직후 임시 파일 자동 삭제, Base64 `-EncodedCommand`로 특수문자(`&`, `()`, `'`, 한글) 경로 대응, `Invoke-NativeOem` 30초 타임아웃 및 `System32` 절대 경로 해석, `Invoke-SafeReboot` 오류 표시, Ventoy/Rufus 숨김 FAT12·FAT16(`MbrType 1,4,6`) 추가.
  * **부트로더 모듈(`02`):** `Get-BusyDriveLetters`(`DriveInfo`+`PSDrive`+`Win32_MappedLogicalDisk`+`HKCU/HKU\*\Network`)로 매핑 드라이브 `Z:` 충돌 방지 및 후보 순서 `W` 우선화, 기존 드라이브 문자 덮어쓰기 차단 및 마운트 지연 1.2초 재시도/실패 시 자동 해제, 읽기 전용 디스크 `READONLY_PROTECTED` 보호, 정상 Windows `diskpart` 폴백 시에도 `SystemDrive` 다중 방어 잠금, 다중 ESP 전수 스캔, 대상 존재 충돌 가드, 한국어 `diskpart` `0 디스크...`/`문자` 헤더/다중 단어 파티션 파싱 보강.
  * **벤더·USB 매칭(`03`, `04`):** `Samsung|\bSEC\b` 단어 경계 보강, 동일 브랜드 USB vs 내장 SSD 모델명 교차 오매칭 방지 + 비-USB `SATA`/`NVMe` 배제, STEP 2 `[읽기 전용]` 태그 표시.
  * **사후 스풀러 모듈(`05`, `06`):** `HKEY_USERS\S-1-5-21-*\Printers\Connections` 조회(Over-the-Shoulder UAC 대응), `Get-NetFirewallRule` 폴백 죽은 코드 수정, `Spooler` 중지 시 `[판별 보류]` 역할 표기, `PrinterQueryError` RPC 경고 표시, `Spooler` 미존재 즉시 종료, 사용자 지정 `DefaultSpoolDirectory` 대응, `AsyncWaitHandle` 해제, `bcdboot` 성공/실패 피드백 및 공유폴더 실행 안내 배너 추가.

### 다른 PC AI 에이전트 이어받기 가이드
* **코드 수정 원칙:** `SID_Change_Aux_Tool.bat`를 직접 수정하지 말고 반드시 `modules/*.{bat,ps1}`를 수정한 뒤 `tools/Build-Tool.ps1`로 재생성·검증하고 `tools/Test-Tool.ps1`을 실행할 것.
* **현재 위치:** 1~4단계 구현, 3종 실행 환경(쓰기 금지 USB / 로컬 / 공유폴더) 하드닝 및 **86개 자동 테스트** 통과 상태. 사용자가 5단계 실장비 테스트 결과를 공유하면 발견된 현장 이슈/튜닝을 `modules/`에 반영하고 재빌드·재검증 후 6단계(최종 문서 확정)를 마무리하면 됨.

### 남은 작업 — 5단계 실장비 검증 체크리스트
1. **실행 환경 3종 검증 (쓰기 금지 USB / 로컬 / 공유폴더):**
   * 쓰기 금지 USB에서 실행 시 쓰기 오류 없이 정상 동작 및 STEP 2 `[읽기 전용]` 표기 확인.
   * 공유폴더(`\\서버\공유` 및 매핑 드라이브 `Z:\`)에서 **일반 더블클릭** 시 로컬 스테이징 → UAC 상승 → 메모리 실행 안내 배너 출력 및 임시 파일 잔존 없음 확인.
   * 공유폴더 접속(`Z:` 매핑) 상태에서 STEP 1 ESP 임시 마운트 시 `Z:`와 충돌하지 않는지 확인.
2. **HP Elite Tower 800 G9 (관리자 권한 실행):**
   * `[1]` 사전 작업 진입 → STEP 1 정상 표시 → STEP 2에서 HP WMI(`USB Storage Boot`, `Fast Boot`) 파싱 확인.
   * `[D]` NVRAM 원본(한글 깨짐 없음 확인) 및 `[L]` 디스크 진단 출력 확인.
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
