<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — nativer macOS-Prompt-Manager und Snippet-Launcher" width="128" height="128" />

# PromptPanel | 项目快贴

### Nativer macOS-Prompt-Manager / Snippet-Launcher für ChatGPT, Claude, Cursor, Copilot, VS Code und Terminal

### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel（项目快贴）ist ein lokal-orientierter **macOS-Prompt-Manager**, **AI-Prompt-Launcher** und **Code-Snippet-Launcher**. Drücke ein globales Tastenkürzel, durchsuche deine lokale **Prompt library / snippet library** und füge wiederverwendbare Prompts, Code-Snippets, Templates und Instructions in **ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, den Browser oder ein beliebiges Eingabefeld** ein.

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.1.2](https://img.shields.io/badge/Release-v1.1.2-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#installation)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#datenschutz--daten)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [**Deutsch**](README.de.md)

[FAQ](docs/FAQ.md) · [Dokumentation](docs/README.md) · [LLM index](llms.txt) · [Änderungsprotokoll](CHANGELOG.md) · [Mitwirken](.github/CONTRIBUTING.md)

</div>

---

## In 30 Sekunden verstehen / 30-Second Summary

| Feld / Field | Antwort / Answer |
| --- | --- |
| Was es ist / What it is | Ein quelloffener, lokal-orientierter macOS-Prompt-Manager und Snippet-Launcher, der über ein globales Tastenkürzel ein natives Panel aufruft, um wiederverwendbaren Text zu durchsuchen und einzufügen. |
| Welches Problem gelöst wird / Problem solved | Nutzer, die häufig ChatGPT, Claude, Cursor, Copilot, VS Code und Terminal verwenden, müssen nicht mehr ständig Notizen durchwühlen oder denselben System-Prompt, Projektkontext oder dieselbe Befehlsvorlage kopieren. |
| Für wen / Audience | AI-Heavy-User, Entwickler, Prompt-Engineers, Technical Writer, PMs, Berater und unabhängige Entwickler, die ihre Prompt library projektweise trennen müssen. |
| Kernfunktionen / Core features | Globales Tastenkürzel, Sofortsuche, Projekttrennung, `Universal`-Projekt (in der App: `通用项目`), `#tag`-Filter, Zwischenablage-Priorität, Accessibility-Auto-Paste, Ausführungsprotokoll, JSON/Markdown-Import/-Export. |
| Tech-Stack / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager. |
| Schnellstart / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`. Nach Erteilung der Accessibility-Berechtigung beim ersten Start ist Auto-Paste möglich; auch ohne Berechtigung wird in die Zwischenablage kopiert. |
| Typische Szenarien / Use cases | ChatGPT/Claude Role-Prompt, Cursor Project-Context, PR-Review-Checkliste, Terminal-Command-Snippet, Meeting-Notes-Template, kundenspezifisches Antwort-Template. |
| UI-Sprache / UI language | **Die App-Oberfläche ist derzeit ausschließlich auf vereinfachtem Chinesisch** (`CFBundleDevelopmentRegion = zh-Hans`; keine Lokalisierungsressourcen, keine Sprachumschaltung in der App). Die Dokumentation liegt in 8 Sprachen vor, und `README.md` enthält eine Zuordnungstabelle Chinesisch→Englisch für die UI-Beschriftungen. Die von dir gespeicherten Prompt-Inhalte sind sprachunabhängig. |
| Einschränkungen / Limits | Nur macOS 14+; Oberfläche nur auf vereinfachtem Chinesisch; das aktuelle Release enthält noch kein notarisiertes Binary-Paket; keine Cloud-Synchronisierung, keine Team-Zusammenarbeit, keine Windows-/Linux-Version; keine Variablen-Templates; Auto-Paste erfordert die macOS-Accessibility-Berechtigung. |

## Was ist PromptPanel? / What is PromptPanel?

**PromptPanel（项目快贴）** ist ein quelloffenes, natives **macOS-Prompt-Management-Tool** und ein **snippet launcher**. Es ist um einen sehr kurzen AI-Workflow herum konzipiert: In einer beliebigen Vordergrund-App ein Tastenkürzel drücken, die lokale Prompt-Bibliothek durchsuchen, `Enter` drücken — der Inhalt wird zuerst in die Systemzwischenablage geschrieben und dann nach bestem Bemühen automatisch in das aktuelle Eingabefeld eingefügt. Kein Konto, keine Cloud-Synchronisierung, keine Telemetrie — deine Kerndaten bleiben auf deinem eigenen Mac.

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

Wenn du nach **ChatGPT Prompt-Management macOS**, **Claude Prompt-Bibliothek**, **Cursor Code-Snippet-Manager**, **lokal-orientierter Prompt-Bibliothek**, **macOS global hotkey paste tool**, **Raycast Snippets alternative for AI prompts** oder **open-source TextExpander alternative for multiline prompts** suchst, dann trifft PromptPanel genau diesen Bedarf: Es verwandelt wiederkehrende AI-Anweisungen, Code-Snippets und Projektkontexte in ein lokales, durchsuchbares und auditierbares Schnellpanel.

## Kommt dir das bekannt vor?

PromptPanel existiert, weil bei jedem, der mit LLMs arbeitet, täglich dieselben fünf Probleme auftauchen:

- Du tippst denselben **Role- / System-Prompt** ("du bist ein Senior Staff Engineer …") zehnmal am Tag erneut in einen frischen ChatGPT- oder Claude-Chat.
- Du pflegst eine Notizen-App oder ein Scratchpad voller **AI-Prompts und Code-Review-Checklisten** und arbeitest dich mit `⌘+F` hindurch.
- Du findest endlich den richtigen Prompt und **das Einfügen schlägt stillschweigend fehl**, weil sich der Fokus verschoben hat oder die App synthetische Tastenanschläge blockiert.
- Dein **Cursor- / Copilot-Projektkontext-Block** liegt in einer Datei, das **Terminal-Command-Snippet** in einer anderen und der **PR-Review-Prompt** in einer dritten — keines davon von einer Stelle aus durchsuchbar.
- Du willst kein echtes Kunden-Briefing oder proprietäre Architektur in einen **Cloud-Prompt-Manager** stecken, und so hast du am Ende gar keinen Prompt-Manager.

PromptPanel fasst all das in einer einzigen Sub-Sekunden-Schleife mit einer lokalen SQLite-Datei zusammen, die vollständig dir gehört.

## Warum PromptPanel?

Die meisten „Prompt-Manager" sind entweder Browser-Erweiterungen (an eine einzige Website gebunden) oder generische Snippet-Tools, die nicht für den AI-Workflow gebaut wurden. PromptPanel ist speziell um eine kurze Schleife herum konzipiert:

> **Tastenkürzel → Suchen → Enter → Inhalt landet im aktiven Eingabefeld**

Alles andere dient dem Zweck, diese Schleife schnell, vorhersehbar und niemals verlustbehaftet zu machen.

| Du willst … | PromptPanel bietet dir |
|---|---|
| Eine Prompt-Bibliothek, die **in jeder App** funktioniert, nicht nur auf einer Website | Globales Tastenkürzel, natives macOS-Panel, funktioniert in jedem Textfeld |
| **Latenzarme native Schleife** — Sub-Sekunden-Ziel von Tastendruck bis zum Tippen | Ziel: < 300 ms Tastenkürzel-bis-Fokus, < 80 ms Suchaktualisierung, < 250 ms Ausführung |
| **Projekttrennung**, damit die Prompts von Kunde A nicht zu Kunde B durchsickern | Erstklassige Projekte + ein eingebautes `Universal`-Projekt für gemeinsame Inhalte |
| **Kein Cloud-Lock-in** für sensible Prompts | Lokales SQLite. Null Netzwerkaufrufe für Kernfunktionen. Deine Daten sind eine einzige Datei, die dir gehört |
| **Auto-Paste, das nicht stillschweigend fehlschlägt** | Zuerst Auto-Paste, immer Fallback auf die Zwischenablage — und ein klarer Hinweis (Toast), falls das Einfügen blockiert wurde |
| **Reine Tastaturbedienung** | Aufrufen → Tippen → Pfeiltasten → Enter. Maus nie erforderlich |
| Open Source, die du prüfen, forken und der du vertrauen kannst | MIT-Lizenz, reines Swift, keine Telemetrie |

## Für wen ist es gedacht?

- **Intensive ChatGPT- / Claude- / Gemini-Nutzer**, die dieselben Rollendefinitionen, Ausgabeformat-Vorgaben und Kontextblöcke wiederverwenden
- **Cursor- / Copilot- / Aider-Nutzer**, die dieselben Architektur-Zusammenfassungen und Review-Checklisten einfügen
- **Entwickler**, die immer wieder Commit-Message-Gerüste, Code-Review-Templates, Terminal-Befehle und Error-Triage-Snippets tippen
- **Indie-Hacker und Berater**, die mehrere Kundenprojekte mit unterschiedlichen Styleguides und Tonalitätsregeln jonglieren
- **Technical Writer und PMs**, die wiederverwendbare Antworten, Status-Updates und Spec-Gerüste pflegen

Wenn „Ich kopiere denselben mehrzeiligen Prompt zwanzigmal am Tag" auf dich zutrifft, wurde dieses Tool für dich geschrieben.

## Funktionen

### Kern (v1.0)

- 🔥 **Globales Tastenkürzel** — rufe das Panel aus jeder Vordergrund-App auf, konfigurierbarer Shortcut
- ⚡ **< 300 ms bis zur Eingabe** — auf `NSPanel` basierend, kein Electron, keine Web-Runtime, kein Cold Start
- 🔍 **Sofortsuche** über Titel und Inhalt, ohne Bestätigungsschritt
- 🗂️ **Projekte** — trenne Prompts nach Kunde, Repo oder Kontext; das `Universal`-Projekt ist immer sichtbar
- 📋 **Auto-Paste mit Fallback auf die Zwischenablage** — nutzt `CGEvent`, um ⌘V zu senden, und weicht bei fehlender Accessibility-Berechtigung sauber aus
- 🎯 **Tastatur zuerst** — mit Pfeiltasten navigieren, mit Enter ausführen, mit Esc schließen
- 📌 **Anheften & Sortieren** — häufige Einträge anheften, manuell sortieren, dann nach Aktualität, dann nach Nutzungshäufigkeit
- 🌗 **Hell / Dunkel / System**-Theme
- 🪶 **In der Menüleiste ansässig** — unauffällig, bis du es aufrufst
- 🚀 **Start bei der Anmeldung** über `SMAppService`
- 🔐 **Berechtigungsbewusste Degradation** — ohne Accessibility erhältst du weiterhin Ein-Tasten-Kopieren und einen klaren UI-Hinweis
- 📝 **Mehrzeiliger Inhalt** — vollständige Template-Texte, keine Längenbegrenzung beim Speichern
- 📊 **Ausführungsprotokoll** zur Diagnose von Paste-Fehlern
- 🔄 **Manuelles Update über GitHub Releases** (Sparkle-Auto-Update ist eingebaut, aber standardmäßig deaktiviert; der Maintainer aktiviert es, sobald ein signierter Appcast-Feed gehostet wird)

### Was ausdrücklich *nicht* getan wird (Projektgrenzen)

Konstruktionsbedingt wird PromptPanel **niemals** Cloud-Synchronisierung, Team-Zusammenarbeit oder komplexe Workflow-Orchestrierung hinzufügen. Das ist kein „später" — es ist für immer außerhalb des Umfangs. Das Tool ist ein Einzelnutzer-, rein lokales Dienstprogramm, und genau das ist der Sinn. Siehe [PRD §4.2](docs/项目快贴-PRD.md) für die Begründung.

## Wie funktioniert es?

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

1. Du drückst das konfigurierte Tastenkürzel (die `KeyboardShortcuts`-Bibliothek erfasst es systemweit).
2. PromptPanel legt ein `NSPanel` über das aktive Fenster, fokussiert das Suchfeld und zeigt die Einträge des aktuellen Projekts sowie des `Universal`-Projekts, sortiert nach Anheften → manuell → Aktualität → Nutzungshäufigkeit.
3. Du tippst, um zu filtern (live, ohne Bestätigung), wählst mit den Pfeiltasten und drückst `Enter`.
4. Der ausgewählte Inhalt wird **immer** zuerst in die Systemzwischenablage geschrieben (das ist die Garantie — die Zwischenablage schlägt nie stillschweigend fehl).
5. Das Panel verschwindet, die vorherige App erhält wieder den Fokus, und PromptPanel synthetisiert ein `⌘V` per `CGEvent`. Fehlt die Accessibility-Berechtigung oder blockiert die Ziel-App synthetische Ereignisse, teilt dir ein Toast mit: „Kopiert — drücke ⌘V zum Einfügen."
6. Die Ausführung wird lokal protokolliert, damit du App-spezifische Paste-Probleme später diagnostizieren kannst.

Diese Trennung — **Zwischenablage als Garantie, Auto-Paste als Best-Effort** — ist die wichtigste Design-Entscheidung des Projekts.

## Installation

> **Systemanforderung:** macOS 14 (Sonoma) oder neuer. Apple Silicon und Intel werden beide unterstützt.

### Option A — Aus dem Quellcode bauen (aktueller Weg während der Vorabversion)

```bash
# 1. Clone
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Build the .app bundle (signed ad-hoc by default)
./scripts/build-app.sh

# 3. Move it into Applications (or run from dist/)
open dist/PromptPanel.app
```

Anforderungen zum Bauen:

- Xcode 15+ mit dem macOS-14-SDK
- Swift-5.10-Toolchain (`xcrun swift --version`)

### Option B — Signiertes & notarisiertes Release

GitHub Releases enthalten derzeit nur Quellcode-/Dokumentations-Release-Notes; es ist noch kein notarisiertes Binary-Asset angehängt. Bis die Developer-ID-Notarisierungskette vollständig ist, baue lokal mit `./scripts/build-app.sh`.

### Einrichtung beim ersten Start

1. **Erteile die Accessibility-Berechtigung**, wenn du dazu aufgefordert wirst. macOS nutzt sie, um synthetische `⌘V`-Tastenanschläge zuzulassen. Ohne sie kopiert PromptPanel weiterhin zuverlässig in die Zwischenablage; du fügst dann nur manuell ein.
2. **Lege dein Tastenkürzel** unter `设置 → 偏好 → 快捷键 → 呼出面板` fest. Der aktuelle Standard ist `⌥2`; wähle ein anderes Kürzel, falls es mit deinem Setup kollidiert.
3. **Erstelle ein Projekt** oder beginne, Einträge zu `Universal` hinzuzufügen.

## Schnellstart

Vorausgesetzt, die App ist gebaut und läuft (Menüleisten-Symbol sichtbar):

```text
1. Hauptfenster → 内容库 (Bibliothek) → ersten Eintrag anlegen:
   Titel "review", Inhalt = dein Code-Review-Prompt, Tags optional
2. ⌥2              → Panel erscheint, Suchfeld fokussiert
3. "review" tippen → filtert auf deinen Code-Review-Prompt
4. ↵               → Inhalt wird kopiert und ins aktive Textfeld eingefügt
5. (Panel schließt) → weiterarbeiten
```

### Suchsyntax im Panel / Search syntax

| Du tippst | Was passiert |
|---|---|
| `review` | **FTS5-Präfixsuche** von SQLite über Titel und Inhalt des Eintrags |
| `code rev` | Jedes durch Leerzeichen getrennte Token ist ein Präfixterm, mit UND verknüpft |
| `#sql` | Filtert auf Einträge mit dem Tag `sql`; das `#tag`-Token wird aus der Textsuche entfernt |
| `#sql migrate` | Tag-Filter `sql` **und** Texttreffer `migrate` |
| *(leer)* | Durchsucht das aktuelle Projekt plus `Universal`, sortiert nach Anheften → manuelle Reihenfolge → Aktualität → Nutzungshäufigkeit |

Hinweise: Nur das erste `#tag`-Token wirkt als Tag-Filter, und es trifft exakt und case-sensitiv (`#SQL` trifft kein `sql`-Tag); Suchergebnisse sind auf 100 Zeilen begrenzt; der Textabgleich ist präfixbasiert, ein Begriff aus der Mitte eines Wortes (oder einer CJK-Folge ohne Leerzeichen) trifft also nicht.

Du kannst das aktive Projekt direkt im Panel wechseln, ohne das Hauptfenster zu öffnen — nur mit der Tastatur, ohne Umweg. `⌘1`–`⌘9` führen die ersten neun Zeilen direkt aus; `⌘C` kopiert ohne Einfügen; `⌘P` fixiert das Panel; `Esc` schließt es.

## Konfiguration

| Einstellung | Ort | Hinweise |
|---|---|---|
| Globales Tastenkürzel | `设置 → 偏好 → 快捷键 → 呼出面板` | Ein Kürzel. Umschaltverhalten: dieselbe Taste schließt |
| Theme | `设置 → 偏好 → 外观 → 主题` | Hell / Dunkel / System folgen |
| Start bei der Anmeldung | `设置 → 权限 → 权限与启动` | Nutzt `SMAppService` |
| Update-Kanal | GitHub Releases (manuell) | Sparkle 2 ist eingebaut, aber deaktiviert, bis ein signierter Appcast gehostet wird; abonniere Release-Benachrichtigungen und ersetze die `.app` |
| Datenbank-Speicherort | `~/Library/Application Support/PromptPanel/promptpanel.db` | Einzeldatei-SQLite, einfach zu sichern |
| Logs | `~/Library/Logs/PromptPanel/` | Über „Runtime Health" im Hauptfenster einsehbar |

## Datenschutz & Daten

- **Lokal-orientiert per Definition.** Deine Prompts liegen in einer einzigen SQLite-Datei auf deinem Mac. Die App sendet deine Inhalte nirgendwohin per POST.
- **Keine Telemetrie.** Keine Analytics-SDKs, keine Metrik-Endpunkte, kein Crash-Reporting-Dienst.
- **Netzwerkzugriff** ist im aktuellen Release gleich null. Sparkle ist gebündelt, aber der Update-Feed ist nicht konfiguriert, sodass überhaupt keine ausgehenden Aufrufe stattfinden, es sei denn, ein zukünftiger Build wird mit einem Appcast ausgeliefert.
- **Keine Konten.** Es gibt nichts, wo man sich anmelden müsste.
- **Open Source.** Prüfe `Sources/PromptPanel/Core/`, um alles Obige zu verifizieren.

Wenn deine Prompts proprietäre Informationen enthalten — interne Architektur, Kunden-Briefings, NDA-gebundenen Kontext — ist genau das die Eigenschaft, die du willst.

## Wie schneidet PromptPanel im Vergleich zu Alternativen ab?

> Schnelle Orientierung, keine Abrechnung. Diese Tools sind gut in dem, was sie tun.

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Browser-Prompt-Erweiterungen |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| Open Source | ✅ MIT | ❌ | ✅ GPLv3 | Teilweise | ❌ | variiert |
| macOS-nativ (kein Electron / keine Web-Runtime) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Funktioniert in jeder App (nicht nur im Browser) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Schnellsuche-Panel-UI (nicht nur Trigger-Strings) | ✅ | teilweise | ❌ | ✅ | ✅ | variiert |
| Projekt- / Kontexttrennung | ✅ erstklassig | Gruppen | Ordner | Ordner | Ordner | selten |
| Reine Tastaturbedienung | ✅ | teilweise | ✅ | ✅ | ✅ | variiert |
| Rein-lokal- / Keine-Cloud-Option | ✅ Standard | optional, kostenpflichtige Stufen drängen zur Cloud | ✅ | Konto erforderlich | ✅ | meist Cloud |
| Kostenlos | ✅ | $$$ | ✅ | Freemium | erfordert Powerpack | variiert |
| Speziell um den AI-Prompt-Workflow herum gebaut | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ aber nur im Browser |

**Kurzfassung:** Wenn du nur im Browser lebst, ist eine Browser-Erweiterung in Ordnung. Wenn du in Cursor/VS Code/Terminal/Slack/überall lebst, willst du etwas Natives, Panel-basiertes. Unter den nativen, Panel-basierten Optionen ist PromptPanel die quelloffene, auf AI-Prompts zugeschnittene.

## Workflow-Beispiele

Konkrete Wege, wie Menschen PromptPanel im Alltag nutzen — diese dienen zugleich als die Long-Tail-„Wie mache ich …"-Fragen, die PromptPanel beantworten soll.

- **Starte einen frischen ChatGPT- / Claude-Chat mit deinem Standard-Role- / System-Prompt.** Tastenkürzel → `role` tippen → Enter. Kein erneutes Eintippen von „Du bist ein Senior Staff Engineer, der …" zum 200. Mal.
- **Füge einen Cursor- / Copilot-Projektkontext-Block in eine neue Datei ein.** Speichere einen mehrabsätzigen „Hier ist die Architektur, die Konventionen und die Einschränkungen"-Block einmal; füge ihn mit einem Tastendruck in jede neue Cursor-Sitzung ein.
- **Füge eine Code-Review-Checkliste in einen PR-Entwurf ein.** Die lange Aufzählungs-Checkliste liegt in PromptPanel; ein Tastenkürzel hängt sie an eine GitHub-PR-Beschreibung an.
- **Feuere einen wiederkehrenden Terminal-Befehl mit exakter Flag-Kombination ab.** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — einmal getippt, gespeichert, mit einem kurzen Suchbegriff aufgerufen.
- **Füge ein Meeting-Notes-Template in Notion / Obsidian / Apple Notes ein.** Jeden Montag beim Standup dasselbe Template → ein Tastenkürzel, null Copy-Paste aus einem Notizen-Scratchpad.
- **Schiebe ein Kundenservice- / Vertriebs-Antwort-Template in Slack oder E-Mail.** Unterschiedliche Tonalität pro Template, ausgewählt aus einem Schnellsuche-Panel statt aus einem Notizen-Ordner.
- **Wechsle zwischen Projekten mit isolierten Prompt-Sets.** Jede Projektgruppe behält ihre eigenen Role-Prompts, Snippets und Templates, sodass der Kontext nie zwischen Kunden durchsickert.

## Tech-Stack

- **Sprache:** Swift 5.10
- **UI:** AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **Speicher:** SQLite über [GRDB.swift](https://github.com/groue/GRDB.swift)
- **Tastenkürzel:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Carbon Hot Key unter der Haube)
- **Auto-Paste:** `CGEvent` synthetisiert ⌘V nach der Fokus-Wiederherstellung
- **Login-Item:** `SMAppService`
- **Updater:** [Sparkle 2](https://sparkle-project.org/)
- **Vertrieb:** Developer ID + Apple-Notarisierung (kein Mac App Store)
- **Build:** Swift Package Manager — kein Xcode-Projekt erforderlich

Siehe [docs/技术选型.md](docs/技术选型.md) für das vollständige Entscheidungsprotokoll.

## Projektstruktur

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

## Dokumentation

Das öffentliche Dokumentationsset ist Teil des Repositorys:

- [Dokumentationsindex](docs/README.md)
- [FAQ](docs/FAQ.md)
- [Produkt-PRD](docs/项目快贴-PRD.md)
- [Projektvorstellung](docs/项目介绍.md)
- [Architektur](docs/架构说明.md)
- [Kernmodule und Logik](docs/关键模块与核心逻辑.md)
- [API- und Funktionsvertrag](docs/API与功能说明.md)
- [Konfiguration](docs/配置说明.md)
- [Deployment](docs/部署说明.md)
- [Entwicklungsstandards](docs/开发规范.md)
- [Anwendungsbeispiele](docs/使用示例.md)
- [Betrieb und Fehlerbehebung](docs/运维与排错指南.md)
- [Maintainer-Übergabeleitfaden](docs/接手维护指南.md)
- [Docs-/Code-Synchronisationsmatrix](docs/文档与代码同步矩阵.md)
- [Release und Wiederherstellung](docs/生产发布与恢复手册.md)
- [Roadmap und Beitragsleitfaden](docs/路线图与贡献指南.md)
- [AI-Suche und Auffindbarkeit](docs/ai-search-discoverability.md)
- [Vollständiger LLM-Kontext](docs/ai-search/llms-full.txt)
- [Such-Metadaten JSON-LD](docs/search-metadata.schema.jsonld)
- [Mitwirken](.github/CONTRIBUTING.md)
- [Sicherheit](.github/SECURITY.md)
- [CodeMeta-Software-Metadaten](codemeta.json)

Für Answer-Engines und repository-bewusste AI-Tools beginne mit [llms.txt](llms.txt) oder dem erweiterten [llms-full.txt](docs/ai-search/llms-full.txt).

## Suche & AI-Auffindbarkeit

PromptPanel hält klassische SEO- und GEO-Flächen im Repo, damit Nutzer und Answer-Engines das Projekt genau identifizieren können:

- `README.md` und `README.zh-CN.md` liefern die menschenlesbare Landingpage-Zusammenfassung und aktuelle Screenshots.
- [llms.txt](llms.txt) ist der kurze AI-lesbare Index für repository-bewusste Tools.
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt) ist der erweiterte Answer-Engine-Kontext mit FAQ-artigen Antworten.
- [codemeta.json](codemeta.json) und [Schema.org JSON-LD](docs/search-metadata.schema.jsonld) beschreiben die App für Software-Kataloge, Such-Crawler und die künftige Veröffentlichung einer Docs-Site.
- [AI-Suche und Auffindbarkeit](docs/ai-search-discoverability.md) definiert die kanonische Formulierung, die Suchintentions-Map und die Wartungs-Checkliste.

## Roadmap

PromptPanel folgt einer **bewusst kleinen** Roadmap. Das PRD listet Punkte auf, die für immer vom Tisch sind (Cloud-Synchronisierung, Teams, Workflow-Orchestrierung). Im Umfang:

- [x] v1.0 — Hauptpfad vollständig: Tastenkürzel → Suchen → Ausführen, Projekte, Zwischenablage-Fallback, Hell/Dunkel, Login-Item, Sparkle, Signatur- & Notarisierungsskripte
- [x] JSON- / Markdown-Import & -Export, mit automatischem Backup vor dem Import
- [ ] „Letzten Eintrag wiederholen" per einem Tastendruck
- [ ] Variablen-Templates (im Stil `{{name}}`) — nur wenn es sich hinzufügen lässt, ohne den Hauptpfad zu verlangsamen

Siehe [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md) für die Priorisierungsregeln, [CHANGELOG.md](CHANGELOG.md) für das bereits Ausgelieferte und [issues](https://github.com/tytsxai/PromptPanel/issues) für die öffentliche Planung.

## Häufig gestellte Fragen

Für eine ausführlichere FAQ siehe [FAQ.md](docs/FAQ.md). Die größten Hits:

### Ist PromptPanel kostenlos?

Ja. MIT-Lizenz. Keine kostenpflichtige Stufe, kein Nutzungslimit, kein Konto.

### Funktioniert es mit Apple Silicon (M1/M2/M3/M4)?

Ja — die Release-Version wird als Universal Binary (arm64 + x86_64) gebaut und läuft damit sowohl auf Apple-Silicon- als auch auf Intel-Macs unter macOS 14+ nativ.

### Sendet es meine Prompts irgendwohin?

Nein. Das aktuelle Release macht null Netzwerkaufrufe. Sparkle ist gebündelt, aber der Update-Feed ist in diesem Build nicht konfiguriert, sodass überhaupt kein ausgehender Verkehr entsteht. Deine Prompt-Inhalte verlassen niemals deinen Mac.

### Warum fragt es nach der Accessibility-Berechtigung?

Um nach dem Verschwinden des Panels und der Fokus-Wiederherstellung deiner vorherigen App einen `⌘V`-Tastenanschlag zu synthetisieren. Ohne diese Berechtigung funktioniert die App weiterhin — sie stoppt nur beim Zwischenablage-Schritt und zeigt dir einen „drücke ⌘V zum Einfügen"-Toast.

### Werdet ihr Cloud-Synchronisierung / Team-Sharing / Workflows hinzufügen?

Nein, bewusst nicht. Diese sind im [PRD §4.2](docs/项目快贴-PRD.md) als **dauerhafte Nicht-Ziele** aufgeführt. Die Identität des Produkts ist „Einzelnutzer, rein lokal, schnell". Eines davon hinzuzufügen würde ändern, was das Produkt ist.

### Warum nicht Electron / Tauri?

Die heißesten Pfade in diesem Produkt (Timing des globalen Tastenkürzels, Fokus-Wiederherstellung, synthetische Tastenanschlag-Injektion, Accessibility-Berechtigungsablauf) sind macOS-Systemintegrations-Belange. Eine plattformübergreifende Hülle fügt Latenz und Indirektion hinzu, ohne Funktionen zu bringen, die für dieses Produkt wichtig sind. Siehe [docs/技术选型.md](docs/技术选型.md) für die vollständige Begründung.

### Wie melde ich einen Bug oder wünsche mir eine Funktion?

Öffne ein Issue: <https://github.com/tytsxai/PromptPanel/issues>. Bitte nutze die Vorlagen — sie ersparen uns beiden Rückfragen.

### Wie importiere ich meine bestehenden Prompts aus einem anderen Tool?

Nutze `Settings → Maintenance → Import JSON` für vollständige PromptPanel-Bibliotheks-Übertragungen oder `Import MD` für Markdown-Prompt-Sammlungen. Importe erstellen zuerst automatisch ein lokales Datenbank-Backup. `Export JSON` eignet sich am besten für verlustfreie Migration; `Export MD` eignet sich am besten für nachvollziehbares Teilen.

## Mitwirken

PRs willkommen — bitte lies zuerst [CONTRIBUTING.md](.github/CONTRIBUTING.md). Zwei nicht offensichtliche Regeln:

1. **UI-Änderungen müssen mit `frontend-draft/` übereinstimmen.** Dieses Verzeichnis ist die maßgebliche Quelle für die Optik; liefere keine Swift-View aus, die dem JSX-Mockup widerspricht.
2. **Bleibe innerhalb des PRD-Umfangs.** Wenn ein Vorschlag das Produkt in Richtung Cloud / Teams / Workflows drängen würde, ist er ein „Nein", egal wie gut er umgesetzt ist. Das ist kein Gatekeeping — es ist der Grund, warum das Tool schnell und vertrauenswürdig ist.

## Danksagungen

PromptPanel steht auf:

- [GRDB.swift](https://github.com/groue/GRDB.swift) von Gwendal Roué
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) von Sindre Sorhus
- [Sparkle](https://github.com/sparkle-project/Sparkle) vom Sparkle-Team

… und der breiteren Swift- / AppKit-Community, deren Dokumentation und Stack-Overflow-Antworten die Systemintegrationspfade erst möglich gemacht haben.

## Lizenz

[MIT](LICENSE) © 2026 tytsxai und PromptPanel-Mitwirkende.

---

<sub>**Keywords** (damit du das hier tatsächlich findest, wenn du suchst): macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage · macOS Prompt-Manager · Prompt-Bibliothek Mac · Snippet-Verwaltung macOS · lokaler AI-Prompt-Launcher · Tastenkürzel-Einfügen macOS.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
