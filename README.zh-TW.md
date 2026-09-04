<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel — macOS 上的 Prompt 與程式碼片段快捷面板" width="128" height="128" />

# PromptPanel | 项目快贴

### 面向 ChatGPT、Claude、Cursor、Copilot、VS Code 和 Terminal 的 macOS 原生 Prompt 管理器 / 程式碼片段啟動器
### Native macOS prompt manager and snippet launcher for AI workflows

PromptPanel 是一款本地優先的 **macOS Prompt 管理器**、**AI Prompt 啟動器** 和 **程式碼片段啟動器**：全域快捷鍵喚出快捷面板，瞬間檢索你的 **Prompt 庫 / 程式碼片段 / 範本**，把內容一鍵送進 **ChatGPT、Claude、Cursor、Copilot、VS Code、Terminal、瀏覽器或任意輸入框**。

[![Release: v1.1.2](https://img.shields.io/badge/Release-v1.1.2-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon · Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#安裝)
[![本地優先 · 不上雲](https://img.shields.io/badge/本地优先-不上云-brightgreen.svg)](#隱私與資料)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [**繁體中文**](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

[FAQ](docs/FAQ.md) · [文件](docs/README.md) · [LLM 索引](llms.txt) · [變更記錄](CHANGELOG.md) · [貢獻指南](.github/CONTRIBUTING.md)

</div>

---

## 30 秒判斷

| 維度 | 結論 |
|---|---|
| 專案類型 | 開源、本地優先的 macOS Prompt manager / AI prompt launcher / snippet launcher。 |
| 核心問題 | 解決高頻複製貼上同一批 ChatGPT、Claude、Cursor、Copilot、VS Code、Terminal Prompt、專案上下文、命令片段和範本的問題。 |
| 適合族群 | AI 重度使用者、開發者、Prompt engineers、技術寫作者、PM、顧問、需要按專案隔離 Prompt 庫的獨立開發者。 |
| 核心功能 | 全域快捷鍵、即時搜尋、專案隔離、`通用專案 / Universal`、`#tag` 過濾、剪貼簿優先、Accessibility 權限下自動貼上、執行日誌、JSON/Markdown 匯入匯出。 |
| 技術棧 | Swift 5.10、AppKit `NSPanel`、SwiftUI、SQLite/GRDB、KeyboardShortcuts、Sparkle 2、Swift Package Manager。 |
| 快速開始 | `git clone` → `./scripts/build-app.sh` → `open dist/PromptPanel.app`。首次執行建議授予 Accessibility 權限；不授權也能複製到剪貼簿。 |
| 典型情境 | ChatGPT/Claude role prompt、Cursor project context、PR review checklist、terminal command snippet、會議紀要範本、客戶回覆範本。 |
| 介面語言 | 應用程式介面目前**只有簡體中文**（`CFBundleDevelopmentRegion = zh-Hans`，沒有在地化資源，也沒有語言切換入口）。繁體中文使用者看到的會是簡體介面。文件為中英雙語、共 8 個語言版本；詞條內容本身不限語言。 |
| 限制邊界 | 僅支援 macOS 14+；介面僅簡體中文；目前 Release 暫無已公證二進位套件；無雲端同步、無團隊協作、無 Windows/Linux 版本；暫不支援變數範本；自動貼上依賴 macOS Accessibility。 |

## PromptPanel 是什麼？

**PromptPanel（项目快贴）** 是一款開源的 **macOS 原生 Prompt 管理工具 / 片段啟動器**，專門圍繞 AI 使用者的真實工作流設計。在任何前景應用裡——不管是 ChatGPT、Claude、Cursor、VS Code、Terminal，還是瀏覽器——按下你設定的全域快捷鍵，一個輕量面板立刻浮現。打幾個字、Enter，內容就落進目前輸入框。**不需要帳號、不上雲、不依賴任何同步服務。** 你的所有 Prompt 都只在這台 Mac 上。

English positioning: **PromptPanel is a native macOS prompt manager, AI prompt launcher, local-first prompt library, and snippet launcher** for ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and ordinary macOS text fields.

如果你正在找 **AI Prompt 庫**、**TextExpander 替代品（專門為 Prompt 用的）**、**macOS 開源 snippet launcher**，或者想停止把同一段指令一天複製貼上一百遍到 Claude / ChatGPT 裡——這就是 PromptPanel 要解決的問題。

常見搜尋詞也能對應到它：**ChatGPT Prompt 管理 macOS**、**Claude Prompt 庫**、**Cursor 程式碼片段管理器**、**本地優先 Prompt 庫**、**全域快捷鍵貼上工具**、**Raycast Snippets 的 AI Prompt 替代方案**、**開源 TextExpander 替代品**。

## 是不是聽起來很熟？

PromptPanel 之所以存在，是因為高頻 AI 使用者每天都會撞上同樣的 5 件事：

- 每開一個新的 ChatGPT / Claude 對話，就要再敲一遍同樣的 **角色 / system prompt**（「你是一位資深工程師…」）。
- 用備忘錄或文字草稿堆 **AI Prompt + 程式碼審查清單**，每次 `⌘F` 翻一遍。
- 終於找到想要的 Prompt，焦點跳了或對方 app 屏蔽合成按鍵，**貼上靜默失敗**。
- **Cursor / Copilot 的專案上下文**在一個檔案，Terminal 命令在另一個檔案，PR 審查 Prompt 在第三個——沒有一處能一起搜。
- 真正涉密的客戶簡報和架構細節，你不敢丟進 **雲端 Prompt 管理器**，結果乾脆沒有「Prompt 管理器」。

PromptPanel 把上面這些全部塌進一條 sub-second 的鏈路——而你的資料始終在你本機的一個 SQLite 檔案裡。

## 為什麼是 PromptPanel？

市面上的「Prompt 管理工具」要麼是瀏覽器外掛（只在一個網站裡能用），要麼是為通用打字加速設計的、並不貼合 AI 工作流。PromptPanel 圍繞**唯一一條主鏈路**做：

> **快捷鍵 → 搜尋 → Enter → 內容進入目前輸入框**

其他一切都為這條鏈路服務——快、可預期、永遠不會「靜默失敗」。

| 你想要 | PromptPanel 給你 |
|---|---|
| 一個**任何應用都能用**的 Prompt 庫，不限於某個網站 | 全域快捷鍵 + 原生 macOS 面板，任意輸入框可用 |
| **低延遲原生鏈路**——按鍵到能輸入的目標時間明確 | < 300 ms 喚出聚焦目標、< 80 ms 搜尋刷新目標、< 250 ms 執行目標（即 `Constants.swift` 裡的內部預算，超標會寫 warning 日誌） |
| **專案隔離**，A 客戶的 Prompt 不會串到 B 專案裡 | 一等公民的「專案」概念 + 內建不可刪的 `通用專案` |
| 敏感 Prompt **不想上雲** | 本地 SQLite，核心功能零網路呼叫，資料是一個你完全掌握的檔案 |
| **自動貼上不能靜默失敗** | 自動貼上優先 + 剪貼簿永遠兜底，被屏蔽時有清晰提示 |
| 全鍵盤操作 | 喚出 → 輸入 → 方向鍵 → Enter，從頭到尾不用碰滑鼠 |
| 可稽核、可 fork、可信任的開源 | MIT 協議、純 Swift 實作、零遙測 |

## 適合誰用？

- **重度 ChatGPT / Claude / Gemini 使用者**：反覆輸入角色設定、輸出格式約束、上下文範本的人
- **Cursor / Copilot / Aider 使用者**：常常要貼上架構概要、程式碼審查清單
- **開發者**：經常需要插入提交說明範本、程式碼審查範本、Terminal 命令、排障 snippet
- **獨立開發者 / 顧問**：在多個客戶專案間切換，每家有不同的風格指南、tone-of-voice
- **技術寫作者 / PM**：維護可複用的回覆、狀態更新、規範腳手架

如果「我每天要把同一段多行 Prompt 重複輸入二十遍」是在描述你——這工具就是為你寫的。

## 功能一覽

### v1.0 已有

- 🔥 **全域快捷鍵**：在任何前景應用裡都能喚出，可自訂
- ⚡ **< 300 ms 主鏈路**：基於 `NSPanel`，沒有 Electron、沒有 Web 執行環境、沒有冷啟動
- 🔍 **即時搜尋**：按標題或內文即時過濾，不需要點提交
- 🗂️ **專案隔離**：按客戶、儲存庫、上下文區分；`通用專案` 永遠可見
- 📋 **自動貼上 + 剪貼簿兜底**：用 `CGEvent` 模擬 ⌘V，權限缺失時優雅降級
- 🎯 **鍵盤優先**：方向鍵選擇，Enter 執行，Esc 關閉
- 📌 **置頂 / 排序**：常用置頂 → 手動排序 → 最近使用 → 使用次數
- 🌗 **淺色 / 深色 / 跟隨系統**
- 🪶 **選單列常駐**：不打擾，要用就來
- 🚀 **開機啟動**：基於 `SMAppService`
- 🔐 **權限缺失也能用**：沒有 Accessibility 權限時只走「複製」，UI 明確告知
- 📝 **多行內容**：範本內文不限長度
- 📊 **執行日誌**：貼上失敗時可查
- 🔄 **手動更新（GitHub Releases）**：Sparkle 已接入但預設關閉；正式 appcast 託管位就緒後再開啟自動檢查

### 永遠不會做（產品邊界）

PromptPanel **永遠不會**加入雲端同步、團隊協作、複雜工作流編排。這不是「以後再說」，而是「以後也不做」。這個工具就是單使用者、純本地、輕量快速，這才是它存在的理由。詳見 [PRD §4.2](docs/项目快贴-PRD.md)。

## 運作原理

```
   ┌──────────────┐    快捷鍵      ┌──────────────┐    Enter      ┌──────────────┐
   │  任意應用     │  ──────────►  │ PromptPanel  │  ──────────► │   剪貼簿      │
   │  ChatGPT     │   （全域）     │   NSPanel    │  （執行）     │   寫入        │
   │  Claude      │               │              │              └──────┬───────┘
   │  Cursor……    │ ◄──────────── │              │                     │
   └──────────────┘   面板退場     └──────────────┘                     │
          ▲           前景焦點恢復                                       │
          └────────── CGEvent ⌘V （需輔助使用權限） ◄──────────────────┘
                          失敗時：僅剪貼簿 + Toast 提示
```

1. 你按下設定的快捷鍵（`KeyboardShortcuts` 在系統層捕獲）
2. PromptPanel 把 `NSPanel` 彈到目前視窗上方，自動聚焦搜尋框，按「置頂 → 手動排序 → 最近使用 → 使用次數」展示目前專案 + `通用專案` 詞條
3. 你打字過濾（即時，無需提交），方向鍵選擇，Enter
4. **永遠先把內容寫進系統剪貼簿**——這是產品的硬承諾，剪貼簿這一步絕不靜默失敗
5. 面板退場，前一個 app 恢復焦點，PromptPanel 用 `CGEvent` 合成一次 `⌘V`。如果 Accessibility 權限缺失或目標 app 屏蔽合成事件，會有 Toast 告訴你「已複製，按 ⌘V 貼上即可」
6. 執行結果會寫日誌，方便你後續排查特定 app 的相容性問題

**剪貼簿是承諾，自動貼上是盡力而為**——這是整個專案最重要的設計決定。

## 安裝

> **系統要求**：macOS 14 (Sonoma) 及以上，Apple Silicon 與 Intel 都支援。

### 方式 A · 從原始碼建置（目前推薦）

```bash
# 1. 克隆
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. 打 .app 包（默认 ad-hoc 签名）
./scripts/build-app.sh

# 3. 直接运行，或拖进 /Applications
open dist/PromptPanel.app
```

建置依賴：

- Xcode 15+（含 macOS 14 SDK）
- Swift 5.10 工具鏈（`xcrun swift --version` 檢查）

### 方式 B · 已簽名 / 已公證的發布版

目前 GitHub Releases 只承載原始碼 / 文件發布說明，尚未附帶公證二進位產物。Developer ID 公證鏈路補齊前，先用 `./scripts/build-app.sh` 本地建置。

### 首次執行

1. **授予 Accessibility 權限**：用於合成 `⌘V` 模擬按鍵。不授予也能用，只是主鏈路停在剪貼簿那一步、需要你手動貼上
2. **設定快捷鍵**：目前預設是 `⌥2`；如果與你自己的快捷鍵衝突，可以在設定裡改掉
3. **新建一個專案**或者直接往 `通用專案` 裡加詞條

## 快速上手

假設 `.app` 已建置並執行（選單列看得到圖示）：

```text
1. 打開主視窗 → 內容庫 → 新增第一筆詞條：
   標題填 "review"，內文貼你的程式碼審查 Prompt，可選填標籤
2. ⌥2             → 面板浮現，搜尋框自動聚焦
3. 輸入 "review"  → 過濾到你的程式碼審查範本
4. ↵              → 先寫剪貼簿，再貼進目前輸入框
5. （面板退場）    → 繼續手邊工作
```

### 面板內的搜尋語法

| 你輸入 | 實際行為 |
|---|---|
| `review` | 對詞條標題和內文做 SQLite **FTS5 前綴比對** |
| `code rev` | 以空白分隔的每個 token 都是前綴詞，彼此是 AND 關係 |
| `#sql` | 只保留標記 `sql` 標籤的詞條；`#tag` 這個 token 會從文字查詢中移除 |
| `#sql migrate` | 標籤 `sql` **且** 文字命中 `migrate` |
| *(空)* | 瀏覽「目前專案 + 通用專案」，依 置頂 → 手動排序 → 最近使用 → 使用次數 排列 |

注意：一次查詢只取**第一個** `#tag` 當作標籤過濾，且標籤是**精確、區分大小寫**比對（`#SQL` 比對不到 `sql` 標籤）；搜尋結果上限 100 筆；文字比對是前綴式的，因此從詞中間截取的片段（包含中文連寫串的中段）不會命中。

切換目前專案可以直接在面板內完成，不必打開主視窗——純鍵盤，零繞路。`⌘1`–`⌘9` 直達前九列，`⌘C` 只複製不貼上，`⌘P` 固定面板，`Esc` 關閉。

## 設定

> 以下位置是應用程式裡的簡體中文標籤原文。

| 設定項 | 位置 | 說明 |
|---|---|---|
| 全域快捷鍵 | `设置 → 偏好 → 快捷键 → 呼出面板` | 只有這一個快捷鍵，預設 `⌥2`；同一組合再按一次會關閉面板 |
| 主題 | `设置 → 偏好 → 外观 → 主题` | 淺色 / 深色 / 跟隨系統 |
| 詞條排序 | `设置 → 偏好 → 词条排序` | 按使用 / 按等級 / 按最近 / 按字母 |
| 面板行為 | `设置 → 偏好 → 面板行为` | 固定面板、鍵位提示列、緊湊行高、精確面板寬高 |
| 輔助使用權限、開機啟動 | `设置 → 偏好 → 权限与启动` | 權限只影響自動貼上；開機啟動基於 `SMAppService` |
| 備份 / 匯入匯出 / 診斷 | `设置 → 维护 → 维护操作` | `立即备份`、`导出/导入 JSON`、`导出/导入 MD`、`导出诊断` |
| 更新通道 | GitHub Releases（手動） | Sparkle 2 已接入但目前發布未設定 appcast，訂閱 Releases 後手動替換 `.app` 即可 |
| 資料庫位置 | `~/Library/Application Support/PromptPanel/promptpanel.db` | 單檔案，方便備份；同目錄下 `Backups/` 保留 7 份自動備份，`Recovery/` 保留 5 份復原產物 |
| 日誌 | `~/Library/Logs/PromptPanel/` | 主視窗「运行概况」也能查看；執行日誌保留 30 天 |

## 隱私與資料

- **本地優先是定義本身**：所有 Prompt 在你 Mac 的一個 SQLite 檔案裡，內文絕不上傳任何地方
- **零遙測**：沒有埋點、沒有分析 SDK、沒有第三方當機回報
- **網路存取**目前版本為零：Sparkle 已打包但 appcast 未設定，沒有任何對外請求；將來啟用更新檢查時也只拉簽名 feed
- **沒有帳號體系**：根本沒有可登入的東西
- **程式碼開源**：去 `Sources/PromptPanel/Core/` 翻程式碼就能驗證以上說法

如果你的 Prompt 裡有內部架構、客戶簡報、NDA 範圍內的上下文——這正是你想要的屬性。

## 與同類工具對比

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | 瀏覽器 Prompt 外掛 |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| 開源 | ✅ MIT | ❌ | ✅ GPLv3 | 部分 | ❌ | 看外掛 |
| macOS 原生（非 Electron / Web） | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 任意應用可用 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 快捷搜尋面板 | ✅ | 部分 | ❌ | ✅ | ✅ | 看外掛 |
| 專案 / 上下文隔離 | ✅ 一等公民 | groups | folders | folders | folders | 少有 |
| 全鍵盤流 | ✅ | 部分 | ✅ | ✅ | ✅ | 看外掛 |
| 純本地 / 不上雲 | ✅ 預設 | 收費版偏推薦雲 | ✅ | 需帳號 | ✅ | 大多上雲 |
| 免費 | ✅ | $$$ | ✅ | freemium | 需 Powerpack | 看外掛 |
| 專門為 AI Prompt 工作流設計 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ 但限瀏覽器 |

**一句話**：如果你只在瀏覽器裡用，瀏覽器外掛就夠。如果你在 Cursor / VS Code / Terminal / Slack / 各處都需要——那你需要原生面板型工具。在原生面板型工具裡，PromptPanel 是開源、專為 AI Prompt 設計的那個。

## 工作流範例

以下是日常真實用法，也正好對應 PromptPanel 想解決的那些「我該怎麼……」長尾問題。

- **開一個新的 ChatGPT / Claude 對話，直接帶上你的標準 role / system prompt。** 快捷鍵 → 輸入 `role` → Enter。不用第 200 次手敲「你是一位資深工程師……」。
- **把 Cursor / Copilot 的專案上下文區塊塞進新檔案。**「這是架構、慣例和限制」那一大段只存一次，之後任何新的 Cursor session 一個快捷鍵就能貼進去。
- **把程式碼審查清單貼進 PR 描述。** 長長的 checklist 存在 PromptPanel 裡，一個快捷鍵追加到 GitHub PR 描述末尾。
- **送出一條帶精確參數組合的重複終端指令。** `kubectl get pods --context=prod --namespace=… -o jsonpath=…`——敲一次、存起來、用短關鍵字喚出。
- **往 Notion / Obsidian / 備忘錄裡插會議紀要範本。** 每週一站立會都是同一個範本 → 一個快捷鍵，不用再去草稿檔裡翻著複製。
- **把客服 / 業務回覆範本推進 Slack 或郵件。** 不同語氣各存一筆，從快捷面板裡挑，而不是從備忘錄資料夾裡翻。
- **在多個專案之間切換各自獨立的 Prompt 集合。** 每個專案群組保留自己的 role prompt、片段和範本，上下文永遠不會在客戶之間混用。

更細的分情境範例見 [docs/使用示例.md](docs/使用示例.md)。

## 技術棧

- **語言**：Swift 5.10
- **UI**：AppKit (`NSPanel`, `NSStatusItem`) + SwiftUI
- **儲存**：SQLite via [GRDB.swift](https://github.com/groue/GRDB.swift)
- **快捷鍵**：[sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（底層 Carbon Hot Key）
- **自動貼上**：焦點恢復後用 `CGEvent` 合成 ⌘V
- **開機啟動**：`SMAppService`
- **更新**：[Sparkle 2](https://sparkle-project.org/)
- **分發**：Developer ID + Apple 公證（不走 Mac App Store）
- **建置**：Swift Package Manager，無 Xcode 工程

完整選型決策見 [docs/技术选型.md](docs/技术选型.md)。

## 目錄結構

```
PromptPanel/
├── Sources/PromptPanel/
│   ├── App/              # AppDelegate / AppState / 生命周期
│   ├── Core/
│   │   ├── Database/     # SQLite 打开 / 迁移 / 损坏恢复
│   │   ├── Repositories/ # 项目、词条、设置、执行日志
│   │   ├── Services/     # 面板、执行、搜索、维护等核心服务
│   │   ├── Diagnostics/  # 快捷键到面板聚焦的时序诊断
│   │   └── Utils/
│   ├── Integrations/     # 剪贴板 / 粘贴 / 菜单栏 / 快捷键 / 更新器
│   ├── Features/
│   │   ├── Panel/        # QuickPanelView + ViewModel — 主链路
│   │   └── MainWindow/   # 库管理 + 设置
│   └── Resources/        # Info.plist / entitlements / 图标 / Assets
├── Tests/PromptPanelTests/
├── frontend-draft/       # UI 唯一基準（HTML/JSX 設計稿）
├── scripts/              # 构建、公证、发布预检、备份恢复
├── docs/                 # 公开架构、FAQ、PRD、部署、运维、交接文档
├── .github/              # 贡献、安全、行为准则、issue/PR 模板、CI
├── llms.txt              # 面向 AI 搜索 / LLM 的简短项目索引
├── codemeta.json         # 开源软件结构化元数据
└── Package.swift         # SwiftPM 包定义
```

## 文件體系

公開文件會隨儲存庫一起維護：

- [文件總覽](docs/README.md)
- [FAQ](docs/FAQ.md)
- [產品 PRD](docs/项目快贴-PRD.md)
- [專案介紹](docs/项目介绍.md)
- [架構說明](docs/架构说明.md)
- [關鍵模組與核心邏輯](docs/关键模块与核心逻辑.md)
- [API 與功能說明](docs/API与功能说明.md)
- [設定說明](docs/配置说明.md)
- [部署說明](docs/部署说明.md)
- [開發規範](docs/开发规范.md)
- [使用範例](docs/使用示例.md)
- [維運與排錯指南](docs/运维与排错指南.md)
- [接手維護指南](docs/接手维护指南.md)
- [文件與程式碼同步矩陣](docs/文档与代码同步矩阵.md)
- [生產發布與恢復手冊](docs/生产发布与恢复手册.md)
- [路線圖與貢獻指南](docs/路线图与贡献指南.md)
- [AI 搜尋與可發現性](docs/ai-search-discoverability.md)
- [完整 LLM 上下文](docs/ai-search/llms-full.txt)
- [搜尋結構化元資料](docs/search-metadata.schema.jsonld)
- [貢獻指南](.github/CONTRIBUTING.md)
- [安全政策](.github/SECURITY.md)
- [CodeMeta 開源軟體元資料](codemeta.json)

面向 AI 搜尋引擎和儲存庫感知工具，優先讀取 [llms.txt](llms.txt) 或更完整的 [llms-full.txt](docs/ai-search/llms-full.txt)。

## 搜尋與 AI 可發現性

PromptPanel 把傳統 SEO 和 GEO（生成式答案引擎最佳化）入口放在儲存庫裡維護，避免搜尋結果、AI 摘要和 README 說法漂移：

- `README.md` 和 `README.zh-CN.md`：面向真人使用者的入口摘要和目前介面截圖
- [llms.txt](llms.txt)：面向儲存庫感知工具的短索引
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt)：面向答案引擎的完整上下文和 FAQ 式回答
- [codemeta.json](codemeta.json) 與 [Schema.org JSON-LD](docs/search-metadata.schema.jsonld)：面向軟體索引、搜尋爬蟲和未來文件站的結構化元資料
- [AI 搜尋與可發現性](docs/ai-search-discoverability.md)：統一 canonical 描述、搜尋意圖對映和維護清單

## Roadmap

PromptPanel 走的是**刻意收斂**的路線。PRD 已經把「永不做」列出來了（雲端同步、團隊、複雜工作流）。在範圍內：

- [x] v1.0 — 主鏈路完成：快捷鍵 → 搜尋 → 執行、專案、剪貼簿兜底、明暗、開機啟動、Sparkle、簽名 + 公證腳本
- [x] JSON / Markdown 匯入匯出，匯入前自動建立本地備份
- [ ] 一鍵「重複執行上一條詞條」
- [ ] 變數範本（`{{name}}`）—— 僅當不拖累主鏈路時才做

優先順序和取捨規則見 [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md)，已發布內容看 [CHANGELOG.md](CHANGELOG.md)，公開規劃看 [issues](https://github.com/tytsxai/PromptPanel/issues)。

## 常見問題

更長的 FAQ 見 [FAQ.md](docs/FAQ.md)，這裡挑常被問到的：

### 收費嗎？

不收費。MIT 協議，沒有付費檔、沒有用量上限、沒有帳號。

### 介面有繁體中文嗎？

沒有。應用程式介面目前只有**簡體中文**（`CFBundleDevelopmentRegion = zh-Hans`，沒有在地化資源，也沒有語言切換入口），繁體中文使用者看到的會是簡體介面。文件本身是雙語、共 8 個語言版本。詞條內容不受影響，可以用任何語言。繁體或多語系介面目前不在路線圖上；有需求歡迎開 issue 讓需求被看見。

### 快捷鍵 `⌥2` 和其他軟體衝突，能改嗎？

能。`设置 → 偏好 → 快捷键 → 呼出面板`，重新錄一組即可。面板只有這一個快捷鍵，開啟狀態下再按一次就是關閉。如果錄完發現按了沒反應，通常是其他應用或 macOS 系統快捷鍵先占用了這個組合，換一組即可。

### 某個應用裡自動貼上沒作用怎麼辦？

依這個順序排查：

1. 確認 `设置 → 偏好 → 权限与启动` 和系統的「隱私權與安全性 → 輔助使用」都已授權。重新建置 `.app` 之後 macOS 可能把它當成新的二進位檔，需要先移除項目再重新加入。
2. 直接按 `⌘V` 試試。如果手動能貼出正確內容，代表剪貼簿那一步的承諾有兌現，只是合成按鍵被擋了。
3. 看 `设置 → 维护 → 最近执行记录`，每筆失敗都會記錄原因。
4. 有些應用會**主動**拒絕合成事件（密碼欄位、部分安全輸入情境、部分遠端桌面與虛擬機視窗）。這屬於目標應用的政策，不是 PromptPanel 可復原的錯誤。
5. 如果是常用應用且能穩定重現，歡迎開 issue 附上應用名稱、版本和執行日誌裡的失敗原因。

### 支援變數 / 佔位符範本嗎？

暫時不支援，詞條內容是原樣貼上。變數範本（`{{name}}` 形態）在路線圖裡是**有條件**的：只有在不拖慢主鏈路的前提下才會做。

### 怎麼徹底移除並清理資料？

如果之後可能還要用，先 `设置 → 维护 → 导出 JSON` 備份一份。然後從選單列結束、刪掉 `.app`，再清掉這兩個目錄：

```bash
rm -rf ~/Library/Application\ Support/PromptPanel   # 資料庫、Backups/、Recovery/
rm -rf ~/Library/Logs/PromptPanel                   # 執行日誌
```

另外記得在「系統設定 → 隱私權與安全性 → 輔助使用」移除 PromptPanel，開過開機啟動的話也一併移除。

### 支援 Apple Silicon（M1/M2/M3/M4）嗎？

支援。發布包建置為 universal binary（arm64 + x86_64），在 macOS 14+ 的 Apple Silicon 與 Intel 機型上都能原生執行。

### 我的 Prompt 會不會被發到雲上？

不會。目前版本完全沒有網路呼叫。Sparkle 已打包，但 appcast feed 未設定，因此根本不會發出任何對外請求。Prompt 內文從不離開你的 Mac。

### 為什麼要 Accessibility 權限？

為了在面板退場後給前一個 app 合成一次 `⌘V`。不給權限工具也能用，只是停在剪貼簿那一步、需要你手動 `⌘V`。

### 會加雲端同步 / 團隊共享 / 工作流嗎？

不會，這是有意決定。這些項在 [PRD §4.2](docs/项目快贴-PRD.md) 裡被列為**永不做**。產品的核心身份就是「單使用者、純本地、快」，加了那些就不是這個產品了。

### 為什麼不用 Electron / Tauri？

這個產品的關鍵路徑（全域快捷鍵時序、焦點恢復、合成按鍵、Accessibility 權限引導）本來就在 macOS 系統整合層。跨平台殼只會增加延遲和間接性，不會帶來這個產品需要的能力。詳見 [docs/技术选型.md](docs/技术选型.md)。

### 怎麼報 bug 或提需求？

提 issue：<https://github.com/tytsxai/PromptPanel/issues>，請用範本，能減少很多來回。

### 怎麼從其他工具匯入已有 Prompt？

在 `設定 → 維護操作` 裡用 `匯入 JSON` 遷移完整 PromptPanel 詞庫，或用 `匯入 MD` 匯入 Markdown 提示詞集合。匯入前會自動建立本地資料庫備份。`匯出 JSON` 適合無損遷移，`匯出 MD` 適合人工審閱和分享。

## 參與貢獻

歡迎 PR——開始前請先看 [CONTRIBUTING.md](.github/CONTRIBUTING.md)。兩條不太顯然的規則：

1. **UI 改動必須先和 `frontend-draft/` 對齊**：那個目錄是視覺基準，不能讓 Swift 視圖和 JSX 設計稿不一致
2. **不越 PRD 邊界**：如果一個提議會把產品推向雲端 / 團隊 / 工作流，無論實作多好都會被關閉。這不是把門，是這個工具能保持快和可信的根本原因

## 致謝

PromptPanel 站在以下肩膀上：

- [GRDB.swift](https://github.com/groue/GRDB.swift) — Gwendal Roué
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — Sindre Sorhus
- [Sparkle](https://github.com/sparkle-project/Sparkle) — Sparkle 團隊

以及更廣泛的 Swift / AppKit 社群——文件與 Stack Overflow 讓那些系統整合的暗面變得可走通。

## 協議

[MIT](LICENSE) © 2026 tytsxai 與 PromptPanel 貢獻者。

---

<sub>**關鍵詞**（方便你搜到）：macOS Prompt 管理 · AI Prompt 啟動器 · ChatGPT Prompt 管理 macOS · Claude Prompt 庫 · Cursor 程式碼片段管理 · Copilot 範本啟動器 · 開源 TextExpander 替代 · Espanso 替代 · Raycast 替代 · Alfred Snippets 替代 · 全域快捷鍵貼上 · 本地優先 Prompt 庫 · 離線 AI Prompt 儲存 · 原生 Swift NSPanel 應用 · AI 工作流效率工具 · Prompt 範本管理 macOS · macOS 片段啟動器 · 鍵盤優先 Prompt 選擇器 · LLM Prompt 儲存庫 Mac · Prompt 工程工具箱 · Cursor Prompt 管理器 · NDA 安全的本地 Prompt 儲存 · 项目快贴.</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
