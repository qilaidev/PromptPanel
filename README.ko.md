<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — native macOS prompt manager and snippet launcher" width="128" height="128" />

# PromptPanel | 项目快贴

### ChatGPT, Claude, Cursor, Copilot, VS Code 및 터미널을 위한 macOS 네이티브 프롬프트 관리자 / 스니펫 런처
### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel(项目快贴)은 로컬 우선(local-first) **macOS 프롬프트 관리자**, **AI 프롬프트 런처**, **코드 스니펫 런처**입니다. 전역 단축키를 누르면 로컬 **prompt library / snippet library**를 검색하여, 재사용 가능한 prompts, code snippets, templates, instructions를 **ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, 브라우저 또는 임의의 입력 필드**에 붙여넣을 수 있습니다.

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.4.0](https://img.shields.io/badge/Release-v1.4.0-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#설치)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#개인정보-및-데이터)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [**한국어**](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

[FAQ](docs/FAQ.md) · [문서](docs/README.md) · [LLM index](llms.txt) · [변경 이력](CHANGELOG.md) · [기여 안내](.github/CONTRIBUTING.md)

</div>

---

## 30초 요약 / 30-Second Summary

| 항목 / Field | 설명 / Answer |
| --- | --- |
| 무엇인가 / What it is | 오픈 소스, 로컬 우선 macOS prompt manager and snippet launcher. 전역 단축키로 네이티브 패널을 불러내 재사용 가능한 텍스트를 검색하고 붙여넣습니다. |
| 어떤 문제를 해결하는가 / Problem solved | ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal을 자주 쓰는 사용자가 노트를 반복해서 뒤지거나 동일한 system prompt, 프로젝트 컨텍스트, 명령 템플릿을 매번 복사하지 않도록 합니다. |
| 누구를 위한 것인가 / Audience | AI heavy users, 개발자, Prompt engineers, 기술 문서 작성자, PM, 컨설턴트, 그리고 프로젝트별로 prompt library를 분리해야 하는 인디 개발자. |
| 핵심 기능 / Core features | 전역 단축키, 즉시 검색, 프로젝트 격리, `Universal / 공용 프로젝트`, `#tag` 필터, 클립보드 우선, Accessibility 자동 붙여넣기, 실행 로그, JSON/Markdown 가져오기·내보내기. |
| 기술 스택 / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager. |
| 빠른 시작 / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`. 첫 실행 시 Accessibility 권한을 부여하면 자동 붙여넣기가 가능하며, 부여하지 않아도 클립보드에 복사됩니다. |
| 대표 시나리오 / Use cases | ChatGPT/Claude role prompt, Cursor project context, PR review checklist, terminal command snippet, meeting notes template, client-specific response template. |
| UI 언어 / UI language | **앱 인터페이스는 현재 간체 중국어만 지원**합니다(`CFBundleDevelopmentRegion = zh-Hans`, 현지화 리소스와 앱 내 언어 전환 없음). 문서는 8개 언어로 제공되며 `README.md`에 중국어→영어 UI 레이블 대응표가 있습니다. 저장하는 프롬프트 내용 자체는 언어 제한이 없습니다. |
| 제한 사항 / Limits | macOS 14+ 만 지원. UI는 간체 중국어만 지원. 현재 릴리스에는 공증된 바이너리 패키지가 아직 없음. 클라우드 동기화 없음, 팀 협업 없음, Windows/Linux 버전 없음. 변수 템플릿 미지원. 자동 붙여넣기는 macOS Accessibility 권한에 의존함. |

## PromptPanel이란? / What is PromptPanel?

**PromptPanel(项目快贴)**은 오픈 소스, 네이티브 **macOS 프롬프트 관리 도구**이자 **snippet launcher**입니다. 아주 짧은 AI 워크플로 하나를 중심으로 설계되었습니다. 즉, 임의의 포그라운드 앱에서 단축키를 누르고, 로컬 프롬프트 라이브러리를 검색한 뒤 `Enter`를 누르면, 내용이 먼저 시스템 클립보드에 기록되고, 이어서 현재 입력 필드에 최선을 다해 자동으로 붙여넣어집니다. 계정도, 클라우드 동기화도, 텔레메트리도 없으며 핵심 데이터는 여러분의 Mac에 그대로 남습니다.

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

**ChatGPT Prompt 관리 macOS**, **Claude Prompt 라이브러리**, **Cursor 코드 스니펫 관리자**, **로컬 우선 Prompt 라이브러리**, **macOS global hotkey paste tool**, **Raycast Snippets alternative for AI prompts** 또는 **open-source TextExpander alternative for multiline prompts**를 검색하고 있다면, PromptPanel이 바로 그 요구에 해당합니다. 반복 입력하는 AI 지시문, 코드 스니펫, 프로젝트 컨텍스트를 로컬에서 검색·감사 가능한 단축 패널 하나로 바꿔 줍니다.

## 이런 상황이 익숙한가요?

PromptPanel은 LLM으로 작업하는 사람이라면 매일 마주치는 다섯 가지 문제 때문에 존재합니다.

- 새로운 ChatGPT나 Claude 대화창에 동일한 **role / system prompt**("you are a senior staff engineer…")를 하루에 열 번씩 다시 입력합니다.
- **AI 프롬프트와 코드 리뷰 체크리스트**로 가득 찬 메모 앱이나 스크래치패드를 두고, `⌘+F`로 그 안을 헤집습니다.
- 마침내 알맞은 프롬프트를 찾았는데, 포커스가 옮겨졌거나 앱이 합성 키 입력을 막아서 **붙여넣기가 조용히 실패**합니다.
- **Cursor / Copilot project context 블록**은 한 파일에, **terminal command snippet**은 다른 파일에, **PR-review prompt**는 또 다른 파일에 흩어져 있어 한 곳에서 검색할 수 없습니다.
- 실제 고객 브리프나 독점 아키텍처를 **클라우드 prompt manager**에 넣고 싶지 않아, 결국 아무 prompt manager도 쓰지 않게 됩니다.

PromptPanel은 이 모든 것을, 여러분이 완전히 소유하는 로컬 SQLite 파일 하나와 함께 1초 미만의 단일 루프로 압축합니다.

## 왜 PromptPanel인가?

대부분의 "prompt manager"는 브라우저 확장(한 사이트에 종속됨)이거나, AI 워크플로를 위해 만들어지지 않은 범용 스니펫 도구입니다. PromptPanel은 하나의 짧은 루프를 중심으로 특별히 설계되었습니다.

> **단축키 → 검색 → 엔터 → 내용이 활성 입력 필드에 안착**

그 밖의 모든 것은 이 루프를 빠르고, 예측 가능하며, 절대 손실 없게 만드는 데 쓰입니다.

| 원하는 것… | PromptPanel이 제공하는 것 |
|---|---|
| 한 웹사이트가 아니라 **모든 앱에서** 동작하는 prompt library | 전역 단축키, 네이티브 macOS 패널, 어떤 텍스트 필드에서든 동작 |
| **저지연 네이티브 루프** — 키 입력부터 타이핑까지 1초 미만 목표 | 단축키-포커스 < 300 ms 목표, 검색 갱신 < 80 ms 목표, 실행 < 250 ms 목표 |
| 고객 A의 프롬프트가 고객 B로 새지 않도록 하는 **프로젝트 격리** | 일급(first-class) 프로젝트 + 공용 콘텐츠를 위한 내장 `Universal` 프로젝트 |
| 민감한 프롬프트에 대한 **클라우드 종속 없음** | 로컬 SQLite. 핵심 기능에 대한 네트워크 호출 제로. 여러분의 데이터는 여러분이 소유하는 단일 파일 |
| **조용히 실패하지 않는 자동 붙여넣기** | 자동 붙여넣기 우선, 클립보드 폴백 상시 — 붙여넣기가 차단되면 명확한 토스트 표시 |
| **키보드만으로 조작** | 호출 → 입력 → 화살표 키 → Enter. 마우스는 전혀 필요 없음 |
| 감사·포크·신뢰할 수 있는 오픈 소스 | MIT 라이선스, 순수 Swift, 텔레메트리 없음 |

## 누구를 위한 것인가?

- 동일한 역할 정의, 출력 형식 제약, 컨텍스트 블록을 재사용하는 **헤비 ChatGPT / Claude / Gemini 사용자**
- 같은 아키텍처 요약과 리뷰 체크리스트를 붙여넣는 **Cursor / Copilot / Aider 사용자**
- 커밋 메시지 골격, 코드 리뷰 템플릿, 터미널 명령, 오류 분류 스니펫을 반복 입력하는 **개발자**
- 서로 다른 스타일 가이드와 어조 규칙을 가진 여러 고객 프로젝트를 다루는 **인디 해커와 컨설턴트**
- 재사용 가능한 답변, 상태 업데이트, 사양 골격을 관리하는 **기술 문서 작성자와 PM**

"같은 여러 줄 프롬프트를 하루에 스무 번 복사·붙여넣기 한다"가 여러분 이야기라면, 이 도구는 여러분을 위해 만들어졌습니다.

## 기능

### 핵심 (v1.0)

- 🔥 **전역 단축키** — 어떤 포그라운드 앱에서든 패널을 호출, 단축키 설정 가능
- ⚡ **< 300 ms 입력까지의 시간** — `NSPanel` 기반, Electron 없음, 웹 런타임 없음, 콜드 스타트 없음
- 🔍 제목과 본문 전반에 대한 **즉시 검색**, 제출 단계 없음
- 🗂️ **프로젝트** — 고객, 저장소, 컨텍스트별로 프롬프트 격리. `Universal` 프로젝트는 항상 표시됨
- 📋 **클립보드 폴백을 갖춘 자동 붙여넣기** — `CGEvent`로 ⌘V를 전송하며, Accessibility 권한이 없으면 매끄럽게 폴백
- 🎯 **키보드 우선** — 화살표 키로 이동, Enter로 실행, Esc로 닫기
- 📌 **고정 및 frecency 정렬** — 항상 위에 두어야 하는 항목은 고정하고, 나머지는 `사용 횟수 × 2^(-미사용 일수 / 90)` 점수로 정렬됩니다. 자주 쓰는 항목은 자동으로 올라오고, 쓰지 않게 된 항목은 스스로 내려갑니다
- 🌗 **라이트 / 다크 / 시스템** 테마
- 🪶 **메뉴 막대 상주** — 호출하기 전까지는 방해되지 않음
- 🚀 `SMAppService`를 통한 **로그인 시 실행**
- 🔐 **권한 인식 성능 저하 처리** — Accessibility가 없어도 원키 복사와 명확한 UI 힌트를 제공
- 📝 **여러 줄 콘텐츠** — 전체 템플릿 본문, 저장 시 길이 제한 없음
- 📊 붙여넣기 실패 진단을 위한 **실행 로그**
- 🔄 **GitHub Releases를 통한 수동 업데이트** (Sparkle 자동 업데이트가 연결되어 있지만 기본적으로 꺼진 채 배포됨. 서명된 appcast 피드가 호스팅되면 관리자가 활성화할 예정)

### 명시적으로 *하지 않는 것* (프로젝트 경계)

설계상 PromptPanel은 클라우드 동기화, 팀 협업, 복잡한 워크플로 오케스트레이션을 **절대** 추가하지 않습니다. 이는 "나중에"가 아니라 영원히 범위 밖입니다. 이 도구는 단일 사용자, 로컬 전용 유틸리티이며 그것이 핵심입니다. 근거는 [PRD §4.2](docs/项目快贴-PRD.md)를 참고하세요.

## 어떻게 동작하나요?

```
   ┌──────────────┐    hotkey     ┌──────────────┐    select    ┌──────────────┐
   │  any app     │  ──────────►  │ PromptPanel  │  ──────────► │  clipboard   │
   │ (ChatGPT,    │   (global)    │  NSPanel     │   (Enter)    │   (write)    │
   │  Claude,     │               │              │              └──────┬───────┘
   │  Cursor…)    │ ◄──────────── │              │                     │
   └──────────────┘  paste / focus└──────────────┘                     │
          ▲                         restored                            │
          └────────── CGEvent ⌘V (Accessibility permission) ◄───────────┘
                          fallback: clipboard only + toast
```

1. 설정된 단축키를 누릅니다(`KeyboardShortcuts` 라이브러리가 시스템 전역에서 캡처).
2. PromptPanel이 활성 창 위에 `NSPanel`을 띄우고, 검색 필드에 포커스를 주며, 현재 프로젝트와 `Universal` 프로젝트의 항목을 고정 → frecency 점수 → 최근순 → 사용 횟수 순으로 정렬해 표시합니다.
3. 입력해 필터링하고(실시간, 제출 없음), 화살표로 선택한 뒤 `Enter`를 누릅니다.
4. 선택된 콘텐츠는 **항상** 먼저 시스템 클립보드에 기록됩니다(이것이 보증입니다 — 클립보드는 절대 조용히 실패하지 않습니다).
5. 패널이 숨겨지고, 이전 앱이 포커스를 되찾으며, PromptPanel이 `CGEvent`로 `⌘V`를 합성합니다. Accessibility 권한이 없거나 대상 앱이 합성 이벤트를 차단하면, "Copied — press ⌘V to paste."라는 토스트가 안내합니다.
6. 실행은 로컬에 기록되므로 나중에 앱별 붙여넣기 문제를 진단할 수 있습니다.

이 분리 — **보증으로서의 클립보드, 최선의 노력으로서의 자동 붙여넣기** — 는 이 프로젝트에서 가장 중요한 단일 설계 결정입니다.

## 설치

> **시스템 요구 사항:** macOS 14 (Sonoma) 이상. Apple Silicon과 Intel 모두 지원.

### 옵션 A — 소스에서 빌드 (사전 릴리스 단계의 현재 경로)

```bash
# 1. Clone
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Build the .app bundle (signed ad-hoc by default)
./scripts/build-app.sh

# 3. Move it into Applications (or run from dist/)
open dist/PromptPanel.app
```

빌드에 필요한 것:

- macOS 14 SDK를 포함한 Xcode 15+
- Swift 5.10 툴체인 (`xcrun swift --version`)

### 옵션 B — 서명 및 공증된 릴리스

GitHub Releases는 현재 소스/문서 릴리스 노트만 담고 있으며, 공증된 바이너리 자산은 아직 첨부되지 않았습니다. Developer ID 공증 체인이 완료되기 전까지는 `./scripts/build-app.sh`로 로컬에서 빌드하세요.

### 첫 실행 설정

1. 안내가 나오면 **Accessibility 권한을 부여**하세요. macOS는 이를 통해 합성 `⌘V` 키 입력을 허용합니다. 권한이 없어도 PromptPanel은 여전히 클립보드에 안정적으로 복사하며, 붙여넣기만 수동으로 하면 됩니다.
2. `设置 → 偏好 → 快捷键 → 呼出面板`에서 **단축키를 지정**하세요. 현재 기본값은 `⌥2`이며, 설정과 충돌하면 다른 단축키를 고르세요.
3. **프로젝트를 만들거나** `Universal`에 항목 추가를 시작하세요.

## 빠른 시작

앱이 빌드되어 실행 중이라는 전제하에(메뉴 막대에 아이콘이 보임):

```text
1. 메인 창 → 内容库 (라이브러리) → 첫 항목 추가:
   제목 "review", 본문에 코드 리뷰 프롬프트, 태그는 선택
2. ⌥2              → 패널이 나타나고 검색 필드에 포커스
3. "review" 입력   → 코드 리뷰 프롬프트로 필터링
4. ↵               → 클립보드에 복사된 뒤 활성 텍스트 필드에 붙여넣기
5. (패널이 닫힘)   → 계속 작업
```

### 패널 검색 문법 / Search syntax

| 입력 | 동작 |
|---|---|
| `review` | 항목 제목과 본문에 대한 SQLite **FTS5 접두사 매칭** |
| `code rev` | 공백으로 구분된 각 토큰이 접두사 검색어가 되며 AND로 결합됨 |
| `#sql` | `sql` 태그가 붙은 항목만 필터링. `#tag` 토큰은 텍스트 질의에서 제외됨 |
| `#sql migrate` | 태그 `sql` **그리고** 텍스트 `migrate` 일치 |
| *(비움)* | 현재 프로젝트와 `Universal`을 고정 → frecency → 최근순 → 사용 횟수로 정렬해 표시 |

참고: 태그 필터로 사용되는 것은 첫 번째 `#tag` 토큰뿐이며 대소문자를 구분하는 정확 일치입니다(`#SQL`은 `sql` 태그에 일치하지 않음). 검색 결과는 최대 100건이고, 텍스트 매칭은 접두사 기반이라 단어 중간(또는 공백 없는 CJK 문자열 중간)에서 잘라낸 조각은 일치하지 않습니다.

메인 창을 열지 않고도 패널 안에서 활성 프로젝트를 전환할 수 있습니다 — 키보드만으로, 우회 없이. `⌘1`–`⌘9`는 상위 9개 항목을 바로 실행하고, `⌘C`는 붙여넣기 없이 복사, `⌘P`는 패널 고정, `Esc`는 닫기입니다.

## 구성

| 설정 | 위치 | 비고 |
|---|---|---|
| 전역 단축키 | `设置 → 偏好 → 快捷键 → 呼出面板` | 단축키 하나. 토글 동작: 같은 키로 닫힘 |
| 테마 | `设置 → 偏好 → 外观 → 主题` | 라이트 / 다크 / 시스템 따르기 |
| 로그인 시 실행 | `设置 → 偏好 → 权限与启动` | `SMAppService` 사용 |
| 업데이트 채널 | GitHub Releases (수동) | Sparkle 2가 연결되어 있으나 서명된 appcast가 호스팅되기 전까지는 비활성. 릴리스 알림을 구독하고 `.app`을 교체하세요 |
| 데이터베이스 위치 | `~/Library/Application Support/PromptPanel/promptpanel.db` | 단일 파일 SQLite, 백업이 쉬움 |
| 로그 | `~/Library/Logs/PromptPanel/` | 메인 창의 "Runtime Health"에서 확인 |

## 개인정보 및 데이터

- **정의상 로컬 우선.** 여러분의 프롬프트는 Mac의 단일 SQLite 파일에 저장됩니다. 앱은 여러분의 콘텐츠를 어디에도 POST하지 않습니다.
- **텔레메트리 없음.** 분석 SDK 없음, 메트릭 엔드포인트 없음, 크래시 리포팅 서비스 없음.
- **네트워크 접근**은 현재 릴리스에서 제로입니다. Sparkle이 번들되어 있으나 업데이트 피드가 구성되어 있지 않으므로, 향후 빌드에 appcast가 포함되지 않는 한 아웃바운드 호출은 전혀 발생하지 않습니다.
- **계정 없음.** 로그인할 대상이 아무것도 없습니다.
- **오픈 소스.** 위 내용을 검증하려면 `Sources/PromptPanel/Core/`를 감사하세요.

여러분의 프롬프트에 독점 정보 — 내부 아키텍처, 고객 브리프, NDA로 묶인 컨텍스트 — 가 담겨 있다면, 바로 이 특성이 여러분이 원하는 것입니다.

## PromptPanel은 대안들과 어떻게 비교되나요?

> 빠른 이해를 돕기 위한 것이지 깎아내리는 것이 아닙니다. 이 도구들은 각자 잘하는 일이 있습니다.

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Browser prompt extensions |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| 오픈 소스 | ✅ MIT | ❌ | ✅ GPLv3 | 부분적 | ❌ | 다양함 |
| macOS 네이티브 (Electron / 웹 런타임 없음) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 모든 앱에서 동작 (브라우저만이 아님) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 빠른 검색 패널 UI (트리거 문자열만이 아님) | ✅ | 부분적 | ❌ | ✅ | ✅ | 다양함 |
| 프로젝트 / 컨텍스트 격리 | ✅ 일급 | 그룹 | 폴더 | 폴더 | 폴더 | 드묾 |
| 키보드 전용 흐름 | ✅ | 부분적 | ✅ | ✅ | ✅ | 다양함 |
| 로컬 전용 / 클라우드 없음 옵션 | ✅ 기본값 | 선택적, 유료 등급이 클라우드로 유도 | ✅ | 계정 필요 | ✅ | 대개 클라우드 |
| 무료 | ✅ | $$$ | ✅ | 프리미엄 | Powerpack 필요 | 다양함 |
| AI 프롬프트 워크플로에 특화되어 제작됨 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ 단, 브라우저 전용 |

**요약:** 브라우저에서만 산다면 브라우저 확장으로 충분합니다. Cursor/VS Code/Terminal/Slack/어디에서나 산다면, 네이티브이고 패널 기반인 것을 원할 것입니다. 네이티브 패널 기반 옵션 중에서 PromptPanel은 오픈 소스이면서 AI 프롬프트에 맞춰진 것입니다.

## 워크플로 예시

사람들이 PromptPanel을 매일 사용하는 구체적인 방법들 — 이는 PromptPanel이 답하기 위해 만들어진 롱테일 "어떻게 하나요…" 질문 역할도 겸합니다.

- **표준 role / system prompt로 새 ChatGPT / Claude 대화를 시작합니다.** 단축키 → `role` 입력 → Enter. "You are a senior staff engineer who…"를 200번째로 다시 입력할 필요가 없습니다.
- **Cursor / Copilot project-context 블록을 새 파일에 넣습니다.** 여러 문단짜리 "여기 아키텍처, 컨벤션, 제약이 있다" 블록을 한 번만 저장해 두고, 어떤 새 Cursor 세션에든 키 한 번으로 붙여넣습니다.
- **코드 리뷰 체크리스트를 PR 초안에 붙여넣습니다.** 긴 불릿 체크리스트가 PromptPanel에 저장되어 있고, 단축키 하나로 GitHub PR 설명에 추가됩니다.
- **정확한 플래그 조합으로 반복 터미널 명령을 실행합니다.** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — 한 번 입력해 저장하고, 짧은 검색 문자열로 불러냅니다.
- **회의록 템플릿을 Notion / Obsidian / Apple Notes에 삽입합니다.** 매주 월요일 스탠드업마다 같은 템플릿 → 단축키 하나, 메모 앱 스크래치패드에서의 복사·붙여넣기 제로.
- **고객 서비스 / 세일즈 답변 템플릿을 Slack이나 이메일에 넣습니다.** 템플릿마다 다른 어조를, 메모 폴더가 아니라 빠른 검색 패널에서 골라 씁니다.
- **격리된 프롬프트 세트를 가진 프로젝트 간을 전환합니다.** 각 프로젝트 그룹이 자체 role prompts, snippets, templates를 유지하므로 컨텍스트가 고객 간에 절대 섞이지 않습니다.

## 기술 스택

- **언어:** Swift 5.10
- **UI:** AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **저장소:** [GRDB.swift](https://github.com/groue/GRDB.swift)를 통한 SQLite
- **단축키:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (내부적으로 Carbon Hot Key)
- **자동 붙여넣기:** 포커스 복원 후 ⌘V를 합성하는 `CGEvent`
- **로그인 항목:** `SMAppService`
- **업데이터:** [Sparkle 2](https://sparkle-project.org/)
- **배포:** Developer ID + Apple 공증 (Mac App Store 없음)
- **빌드:** Swift Package Manager — Xcode 프로젝트 불필요

전체 의사 결정 기록은 [docs/技术选型.md](docs/技术选型.md)를 참고하세요.

## 프로젝트 구성

```
PromptPanel/
├── Sources/PromptPanel/
│   ├── App/              # AppDelegate, AppState, lifecycle
│   ├── Core/
│   │   ├── Database/     # SQLite open / migrate / recover
│   │   ├── Repositories/ # Project, Entry, Settings, Log
│   │   ├── Services/     # PanelService, ExecuteService, SearchService…
│   │   ├── Diagnostics/  # Hotkey-to-focus timing
│   │   └── Utils/
│   ├── Integrations/     # Clipboard, Paste (CGEvent), Tray, Hotkey, Updater
│   ├── Features/
│   │   ├── Panel/        # QuickPanelView + ViewModel — the hero feature
│   │   └── MainWindow/   # Library + Settings
│   └── Resources/        # Info.plist, entitlements, AppIcon, Assets
├── Tests/PromptPanelTests/
├── frontend-draft/       # UI source-of-truth (HTML/JSX mockups)
├── scripts/              # build-app.sh, notarize, release readiness, restore
├── docs/                 # public architecture, FAQ, PRD, release, ops, handoff docs
├── .github/              # contribution, security, conduct, issue/PR templates, CI
├── llms.txt              # short AI-search / LLM-readable project index
├── codemeta.json         # structured open-source software metadata
└── Package.swift         # SwiftPM package definition
```

## 문서

공개 문서 세트는 저장소의 일부입니다.

- [문서 색인](docs/README.md)
- [FAQ](docs/FAQ.md)
- [제품 PRD](docs/项目快贴-PRD.md)
- [프로젝트 소개](docs/项目介绍.md)
- [아키텍처](docs/架构说明.md)
- [핵심 모듈과 로직](docs/关键模块与核心逻辑.md)
- [API 및 기능 명세](docs/API与功能说明.md)
- [구성](docs/配置说明.md)
- [배포](docs/部署说明.md)
- [개발 표준](docs/开发规范.md)
- [사용 예시](docs/使用示例.md)
- [운영 및 문제 해결](docs/运维与排错指南.md)
- [관리자 인수인계 가이드](docs/接手维护指南.md)
- [문서/코드 동기화 매트릭스](docs/文档与代码同步矩阵.md)
- [릴리스 및 복구](docs/生产发布与恢复手册.md)
- [로드맵 및 기여 가이드](docs/路线图与贡献指南.md)
- [AI 검색 및 검색 노출](docs/ai-search-discoverability.md)
- [전체 LLM 컨텍스트](docs/ai-search/llms-full.txt)
- [검색 메타데이터 JSON-LD](docs/search-metadata.schema.jsonld)
- [기여 안내](.github/CONTRIBUTING.md)
- [보안](.github/SECURITY.md)
- [CodeMeta 소프트웨어 메타데이터](codemeta.json)

응답 엔진과 저장소 인식 AI 도구를 위해서는 [llms.txt](llms.txt) 또는 확장된 [llms-full.txt](docs/ai-search/llms-full.txt)에서 시작하세요.

## Search & AI Discoverability

PromptPanel은 사용자와 응답 엔진이 프로젝트를 정확히 식별할 수 있도록 전통적인 SEO와 GEO 표면을 저장소 안에 유지합니다.

- `README.md`와 `README.zh-CN.md`는 사람이 보는 랜딩 페이지 요약과 최신 스크린샷을 제공합니다.
- [llms.txt](llms.txt)는 저장소 인식 도구를 위한 짧은 AI 판독용 색인입니다.
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt)는 FAQ 형식의 답변을 담은 확장된 응답 엔진 컨텍스트입니다.
- [codemeta.json](codemeta.json)과 [Schema.org JSON-LD](docs/search-metadata.schema.jsonld)는 소프트웨어 카탈로그, 검색 크롤러, 향후 문서 사이트 게시를 위해 앱을 설명합니다.
- [AI 검색 및 검색 노출](docs/ai-search-discoverability.md)은 표준 표현, 검색 의도 지도, 유지 관리 체크리스트를 정의합니다.

## 로드맵

PromptPanel은 **의도적으로 작은** 로드맵을 따릅니다. PRD에는 영원히 논외인 항목(클라우드 동기화, 팀, 워크플로 오케스트레이션)이 나열되어 있습니다. 범위 안에서는:

- [x] v1.0 — 메인 링크 완료: 단축키 → 검색 → 실행, 프로젝트, 클립보드 폴백, 라이트/다크, 로그인 항목, Sparkle, 서명 및 공증 스크립트
- [x] JSON / Markdown 가져오기 및 내보내기, 가져오기 전 자동 백업
- [ ] 원탭 "마지막 항목 반복"
- [ ] 변수 템플릿 (`{{name}}` 형식) — 메인 링크를 느리게 하지 않고 추가할 수 있는 경우에만

우선순위 규칙은 [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md), 배포된 내용은 [CHANGELOG.md](CHANGELOG.md), 공개 계획은 [issues](https://github.com/tytsxai/PromptPanel/issues)를 참고하세요.

## 자주 묻는 질문

더 긴 FAQ는 [FAQ.md](docs/FAQ.md)를 참고하세요. 대표적인 질문들:

### PromptPanel은 무료인가요?

네. MIT 라이선스. 유료 등급 없음, 사용량 제한 없음, 계정 없음.

### Apple Silicon (M1/M2/M3/M4)에서 동작하나요?

네 — 릴리스는 유니버설 바이너리(arm64 + x86_64)로 빌드되므로 macOS 14 이상의 Apple Silicon과 Intel Mac 모두에서 네이티브로 실행됩니다.

### 제 프롬프트를 어딘가로 전송하나요?

아니요. 현재 릴리스는 네트워크 호출을 전혀 하지 않습니다. Sparkle이 번들되어 있지만 이 빌드에서는 업데이트 피드가 구성되어 있지 않아 아웃바운드 트래픽이 전혀 발생하지 않습니다. 여러분의 프롬프트 콘텐츠는 절대 Mac을 떠나지 않습니다.

### 왜 Accessibility 권한을 요청하나요?

패널이 숨겨지고 이전 앱이 포커스를 되찾은 뒤 `⌘V` 키 입력을 합성하기 위함입니다. 이 권한이 없어도 앱은 여전히 동작하며, 클립보드 단계에서 멈추고 "press ⌘V to paste" 토스트를 보여줄 뿐입니다.

### 클라우드 동기화 / 팀 공유 / 워크플로를 추가할 건가요?

아니요, 의도적으로 그렇습니다. 이들은 [PRD §4.2](docs/项目快贴-PRD.md)에 **영구적인 비목표**로 나열되어 있습니다. 제품의 정체성은 "단일 사용자, 로컬 전용, 빠름"입니다. 이 중 어느 것을 추가해도 제품이 무엇인지가 바뀝니다.

### 왜 Electron / Tauri가 아닌가요?

이 제품에서 가장 뜨거운 경로(전역 단축키 타이밍, 포커스 복원, 합성 키 입력 주입, Accessibility 권한 흐름)는 macOS 시스템 통합 문제입니다. 크로스 플랫폼 셸은 이 제품에 중요한 어떤 기능도 얻지 못한 채 지연과 간접 계층만 추가합니다. 전체 근거는 [docs/技术选型.md](docs/技术选型.md)를 참고하세요.

### 버그를 신고하거나 기능을 요청하려면 어떻게 하나요?

이슈를 여세요: <https://github.com/tytsxai/PromptPanel/issues>. 템플릿을 사용해 주세요 — 서로의 왕복을 줄여 줍니다.

### 다른 도구의 기존 프롬프트를 어떻게 가져오나요?

전체 PromptPanel 라이브러리 이전에는 `Settings → Maintenance → Import JSON`을, Markdown 프롬프트 모음에는 `Import MD`를 사용하세요. 가져오기는 먼저 로컬 데이터베이스 백업을 자동으로 생성합니다. 무손실 마이그레이션에는 `Export JSON`이, 검토 가능한 공유에는 `Export MD`가 가장 적합합니다.

## 기여

PR을 환영합니다 — 먼저 [CONTRIBUTING.md](.github/CONTRIBUTING.md)를 읽어 주세요. 명확하지 않은 규칙 두 가지:

1. **UI 변경은 `frontend-draft/`와 일치해야 합니다.** 그 디렉터리가 시각적 요소의 기준(source of truth)입니다. JSX 목업과 모순되는 Swift 뷰를 배포하지 마세요.
2. **PRD의 범위 안에 머무세요.** 제안이 제품을 클라우드 / 팀 / 워크플로 쪽으로 밀어붙인다면, 얼마나 잘 구현되었든 "아니오"입니다. 이는 문지기 노릇이 아니라 — 이 도구가 빠르고 신뢰할 수 있는 이유입니다.

## 감사의 말

PromptPanel은 다음 위에 서 있습니다:

- Gwendal Roué의 [GRDB.swift](https://github.com/groue/GRDB.swift)
- Sindre Sorhus의 [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- Sparkle 팀의 [Sparkle](https://github.com/sparkle-project/Sparkle)

…그리고 시스템 통합 경로를 가능하게 해 준 문서와 Stack Overflow 답변을 남긴 더 넓은 Swift / AppKit 커뮤니티에 감사드립니다.

## 라이선스

[MIT](LICENSE) © 2026 tytsxai and PromptPanel contributors.

---

<sub>**키워드** (검색할 때 실제로 찾을 수 있도록): macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage · macOS 프롬프트 관리자 · AI 프롬프트 런처 · 로컬 우선 프롬프트 라이브러리 · macOS 스니펫 런처 · 키보드 우선 프롬프트 선택기.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
