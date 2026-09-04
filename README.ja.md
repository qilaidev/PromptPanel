<div align="center">

<img src="Sources/PromptPanel/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="PromptPanel 项目快贴 — native macOS prompt manager and snippet launcher" width="128" height="128" />

# PromptPanel | 项目快贴

### ChatGPT、Claude、Cursor、Copilot、VS Code、ターミナル向けの macOS ネイティブ Prompt マネージャー / スニペットランチャー

### Native macOS prompt manager and snippet launcher for ChatGPT, Claude, Cursor, Copilot, VS Code, and Terminal.

PromptPanel（项目快贴）は、ローカルファースト設計の **macOS Prompt マネージャー**、**AI Prompt ランチャー**、**コードスニペットランチャー** です。グローバルホットキーを押してローカルの **Prompt library / snippet library** を検索し、再利用可能な prompts、code snippets、templates、instructions を **ChatGPT、Claude、Cursor、Copilot、VS Code、ターミナル、ブラウザ、あるいは任意の入力欄** に貼り付けます。

PromptPanel is a local-first **macOS prompt manager**, **AI prompt launcher**, and **snippet launcher**. It is built for developers and AI power users who reuse multiline prompts, coding templates, project context blocks, terminal commands, and reply snippets across apps.

[![Release: v1.1.2](https://img.shields.io/badge/Release-v1.1.2-blue.svg)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform: macOS 14+](https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg)](https://www.apple.com/macos)
[![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![Apple Silicon & Intel](https://img.shields.io/badge/Arch-Apple%20Silicon%20%26%20Intel-blue.svg)](#インストール)
[![Local-first · No cloud](https://img.shields.io/badge/Local--first-No%20cloud-brightgreen.svg)](#プライバシーとデータ)
[![PRs welcome](https://img.shields.io/badge/PRs-welcome-success.svg)](.github/CONTRIBUTING.md)

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [**日本語**](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md)

[FAQ](docs/FAQ.md) · [ドキュメント](docs/README.md) · [LLM index](llms.txt) · [変更履歴](CHANGELOG.md) · [コントリビュート](.github/CONTRIBUTING.md)

</div>

---

## 30 秒で理解する / 30-Second Summary

| 項目 / Field | 説明 / Answer |
| --- | --- |
| 何であるか / What it is | オープンソースでローカルファーストの macOS Prompt manager and snippet launcher。グローバルホットキーでネイティブパネルを呼び出し、再利用可能なテキストを検索して貼り付ける。 |
| 何を解決するか / Problem solved | ChatGPT、Claude、Cursor、Copilot、VS Code、ターミナルを頻繁に使うユーザーが、同じ system prompt、プロジェクトコンテキスト、コマンドテンプレートを何度もメモから探してコピーする手間をなくす。 |
| 誰に向くか / Audience | AI heavy users、開発者、Prompt engineers、テクニカルライター、PM、コンサルタント、そしてプロジェクトごとに prompt library を分離したい個人開発者。 |
| 主要機能 / Core features | グローバルホットキー、即時検索、プロジェクト分離、`Universal / 共通プロジェクト`、`#tag` フィルタ、クリップボード優先、Accessibility による自動貼り付け、実行ログ、JSON/Markdown インポート/エクスポート。 |
| 技術スタック / Tech stack | Swift 5.10, AppKit `NSPanel`, SwiftUI, SQLite/GRDB, KeyboardShortcuts, Sparkle 2, Swift Package Manager。 |
| クイックスタート / Quick start | `git clone` -> `./scripts/build-app.sh` -> `open dist/PromptPanel.app`。初回起動で Accessibility 権限を付与すれば自動貼り付けが可能。付与しなくてもクリップボードへのコピーは動作する。 |
| 典型的な用途 / Use cases | ChatGPT/Claude role prompt、Cursor project context、PR review checklist、terminal command snippet、meeting notes template、client-specific response template。 |
| UI 言語 / UI language | **アプリの UI は現在、簡体字中国語のみ**です（`CFBundleDevelopmentRegion = zh-Hans`、ローカライズリソースおよびアプリ内の言語切り替えはありません）。ドキュメントは 8 言語で提供され、`README.md` に中国語→英語の UI ラベル対応表があります。保存するプロンプトの内容は言語を問いません。 |
| 制限事項 / Limits | macOS 14+ のみ対応。UI は簡体字中国語のみ。現在の Release には公証済みバイナリはまだ含まれない。クラウド同期、チームコラボレーション、Windows/Linux 版はなし。変数テンプレートは未対応。自動貼り付けは macOS Accessibility 権限に依存する。 |

## PromptPanel とは？ / What is PromptPanel?

**PromptPanel（项目快贴）** は、オープンソースでネイティブな **macOS Prompt 管理ツール** と **snippet launcher** です。とても短い AI ワークフローを中心に設計されています。任意のフォアグラウンドアプリでホットキーを押し、ローカルの Prompt ライブラリを検索し、`Enter` を押すと、内容がまずシステムクリップボードに書き込まれ、次にベストエフォートで現在の入力欄へ自動貼り付けされます。アカウントも、クラウド同期も、テレメトリもなく、コアデータはあなた自身の Mac の中に留まります。

In English: **PromptPanel is a native macOS prompt manager, AI prompt launcher, and local-first snippet manager** for people who reuse prompts and templates across ChatGPT, Claude, Cursor, Copilot, VS Code, Terminal, browsers, and other macOS text fields.

もしあなたが **ChatGPT Prompt 管理 macOS**、**Claude Prompt ライブラリ**、**Cursor コードスニペットマネージャー**、**ローカルファースト Prompt ライブラリ**、**macOS global hotkey paste tool**、**Raycast Snippets alternative for AI prompts**、あるいは **open-source TextExpander alternative for multiline prompts** を探しているなら、PromptPanel はまさにそのニーズに応えます。繰り返し入力する AI 指示、コードスニペット、プロジェクトコンテキストを、ローカルで検索可能かつ監査可能なクイックパネルに変えます。

## こんな経験に覚えはありませんか？ / Does this sound familiar?

PromptPanel が存在するのは、LLM を扱う人なら誰もが毎日直面する、同じ 5 つの問題があるからです。

- 新しい ChatGPT や Claude のチャットに、同じ **role / system prompt**（「あなたはシニアスタッフエンジニアです…」）を 1 日 10 回も打ち直している。
- **AI プロンプトやコードレビューのチェックリスト** で埋まったメモアプリやスクラッチパッドを抱え、`⌘+F` で探し回っている。
- ようやく正しいプロンプトを見つけても、フォーカスが移ったりアプリが合成キーストロークをブロックしたりして、**貼り付けが無言で失敗する**。
- **Cursor / Copilot のプロジェクトコンテキストブロック** は 1 つのファイルに、**ターミナルコマンドのスニペット** は別のファイルに、**PR レビュー用プロンプト** はさらに別のファイルにあり、どれも一箇所からは検索できない。
- 本物のクライアント案件や独自アーキテクチャを **クラウド型 Prompt マネージャー** に入れたくないので、結局プロンプトマネージャーをまったく使わずに終わる。

PromptPanel はそのすべてを、あなたが完全に所有するローカルの SQLite ファイルとともに、1 秒未満のひとつのループに集約します。

## なぜ PromptPanel なのか？ / Why PromptPanel?

ほとんどの「prompt manager」は、ブラウザ拡張機能（1 つのサイトに縛られる）か、AI ワークフロー向けに作られていない汎用スニペットツールのどちらかです。PromptPanel はひとつの短いループを中心に専用設計されています。

> **ホットキー → 検索 → Enter → 内容がアクティブな入力欄に着地する**

それ以外のすべては、このループを高速で、予測可能で、決して欠落しないものにするために存在します。

| こうしたい… | PromptPanel が提供するもの |
|---|---|
| 1 つのウェブサイトだけでなく、**あらゆるアプリ横断** で動くプロンプトライブラリ | グローバルホットキー、ネイティブ macOS パネル、任意のテキストフィールドで動作 |
| **低レイテンシのネイティブループ** — キー押下から入力まで 1 秒未満を目標 | ホットキーからフォーカスまで < 300 ms、検索更新 < 80 ms、実行 < 250 ms を目標 |
| クライアント A のプロンプトがクライアント B に漏れないための **プロジェクト分離** | ファーストクラスの projects と、共有コンテンツ用の組み込み `Universal` プロジェクト |
| 機密性の高いプロンプトを **クラウドに囲い込まれない** | ローカル SQLite。コア機能でのネットワーク通信ゼロ。データはあなたが所有する単一ファイル |
| **無言で失敗しない自動貼り付け** | 自動貼り付けを優先、クリップボードフォールバックは常に有効。貼り付けがブロックされたら明確なトースト表示 |
| **キーボードのみの操作** | 呼び出し → 入力 → 矢印キー → Enter。マウスは一切不要 |
| 監査・フォーク・信頼できるオープンソース | MIT ライセンス、素の Swift、テレメトリなし |

## 誰のためのツールか？ / Who is it for?

- 同じ役割定義、出力フォーマットの制約、コンテキストブロックを再利用する **ChatGPT / Claude / Gemini のヘビーユーザー**
- 同じアーキテクチャ要約やレビューチェックリストを貼り付ける **Cursor / Copilot / Aider ユーザー**
- コミットメッセージの雛形、コードレビューテンプレート、ターミナルコマンド、エラートリアージのスニペットを繰り返し入力する **開発者**
- 異なるスタイルガイドやトーンのルールを持つ複数のクライアント案件をこなす **インディーハッカーやコンサルタント**
- 再利用可能な返信、ステータス更新、仕様の雛形を管理する **テクニカルライターや PM**

「同じ複数行のプロンプトを 1 日 20 回コピペしている」という説明があなたに当てはまるなら、このツールはあなたのために書かれました。

## 機能 / Features

### コア機能（v1.0）

- 🔥 **グローバルホットキー** — 任意のフォアグラウンドアプリからパネルを呼び出し、ショートカットは設定可能
- ⚡ **< 300 ms の入力到達時間** — `NSPanel` ベース、Electron なし、Web ランタイムなし、コールドスタートなし
- 🔍 **即時検索** — タイトルと本文を横断、送信ステップ不要
- 🗂️ **プロジェクト** — クライアント、リポジトリ、コンテキストごとにプロンプトを分離。`Universal` プロジェクトは常に表示
- 📋 **クリップボードフォールバック付き自動貼り付け** — `CGEvent` で ⌘V を送信し、Accessibility 権限がなければ安全にフォールバック
- 🎯 **キーボードファースト** — 矢印キーで移動、Enter で実行、Esc で閉じる
- 📌 **ピン留めとソート** — よく使う項目をピン留めし、手動ソート → 最近使用順 → 使用回数順
- 🌗 **ライト / ダーク / システム** テーマ
- 🪶 **メニューバー常駐** — 呼び出すまで邪魔にならない
- 🚀 **ログイン時に起動** — `SMAppService` を使用
- 🔐 **権限に応じた段階的動作** — Accessibility がなくても、ワンキーコピーと明確な UI ヒントを利用可能
- 📝 **複数行コンテンツ** — テンプレート本文全体に対応、保存時の文字数制限なし
- 📊 **実行ログ** — 貼り付け失敗の診断用
- 🔄 **GitHub Releases 経由の手動アップデート**（Sparkle 自動アップデートは組み込み済みだが既定でオフ。署名済み appcast フィードがホストされ次第、メンテナが有効化する）

### あえて *やらない* こと（プロジェクトの境界）

設計上、PromptPanel はクラウド同期、チームコラボレーション、複雑なワークフローのオーケストレーションを **決して** 追加しません。これらは「後回し」ではなく、永久にスコープ外です。このツールはシングルユーザーでローカル専用のユーティリティであり、それこそが本質です。理由については [PRD §4.2](docs/项目快贴-PRD.md) を参照してください。

## どのように動作するか？ / How does it work?

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

1. 設定したホットキーを押す（`KeyboardShortcuts` ライブラリがシステム全体でキャプチャ）。
2. PromptPanel がアクティブウィンドウ上に `NSPanel` を表示し、検索欄にフォーカスして、現在のプロジェクトと `Universal` プロジェクトのエントリを、ピン → 手動 → 最近使用 → 使用回数の順にソートして表示する。
3. 入力してフィルタリング（ライブ、送信不要）、矢印キーで選択し、`Enter` を押す。
4. 選択した内容は **常に** まずシステムクリップボードに書き込まれる（これが保証であり、クリップボードは無言で失敗しない）。
5. パネルが隠れ、前のアプリがフォーカスを取り戻し、PromptPanel が `CGEvent` 経由で `⌘V` を合成する。Accessibility 権限がない、またはターゲットアプリが合成イベントをブロックする場合は、「Copied — press ⌘V to paste.」というトーストが表示される。
6. 実行はローカルにログされるので、後からアプリごとの貼り付け問題を診断できる。

この分離 — **クリップボードは保証、自動貼り付けはベストエフォート** — こそが、このプロジェクトで最も重要な設計判断です。

## インストール

> **システム要件:** macOS 14 (Sonoma) 以降。Apple Silicon と Intel の両方に対応。

### 選択肢 A — ソースからビルド（プレリリース中の現在の方法）

```bash
# 1. Clone
git clone https://github.com/tytsxai/PromptPanel.git
cd PromptPanel

# 2. Build the .app bundle (signed ad-hoc by default)
./scripts/build-app.sh

# 3. Move it into Applications (or run from dist/)
open dist/PromptPanel.app
```

ビルドの要件:

- macOS 14 SDK を含む Xcode 15+
- Swift 5.10 ツールチェイン（`xcrun swift --version`）

### 選択肢 B — 署名済み・公証済みリリース

GitHub Releases には現在、ソース/ドキュメントのリリースノートのみが含まれており、公証済みバイナリアセットはまだ添付されていません。Developer ID の公証チェーンが完成するまでは、`./scripts/build-app.sh` でローカルにビルドしてください。

### 初回起動時のセットアップ

1. **Accessibility 権限を付与する** — プロンプトが表示されたら許可する。macOS はこれを使って合成 `⌘V` キーストロークを許可します。権限がなくても PromptPanel は確実にクリップボードへコピーします。手動で貼り付けるだけです。
2. **ホットキーを設定する** — `设置 → 偏好 → 快捷键 → 呼出面板` で行います。現在の既定値は `⌥2` です。環境と競合する場合は別のショートカットを選んでください。
3. **プロジェクトを作成する** か、`Universal` にエントリを追加し始めます。

## クイックスタート / Quick start

アプリがビルド済みで起動している（メニューバーにアイコンが見える）前提で：

```text
1. メインウィンドウ → 内容库 (ライブラリ) → 最初のエントリを追加：
   タイトル "review"、本文にコードレビュー用プロンプト、タグは任意
2. ⌥2              → パネルが表示され、検索欄にフォーカス
3. "review" と入力 → コードレビュー用プロンプトに絞り込まれる
4. ↵               → クリップボードに書き込まれ、アクティブな入力欄に貼り付けられる
5. （パネルが閉じる）→ 作業を続行
```

### パネル内の検索構文 / Search syntax

| 入力 | 動作 |
|---|---|
| `review` | エントリのタイトルと本文に対する SQLite **FTS5 前方一致検索** |
| `code rev` | 空白区切りの各トークンが前方一致語となり、AND で結合される |
| `#sql` | `sql` タグの付いたエントリだけに絞り込む。`#tag` トークンはテキスト検索から除外される |
| `#sql migrate` | タグ `sql` **かつ** テキストが `migrate` に一致 |
| *(空)* | 現在のプロジェクトと `Universal` を、ピン → 手動順 → 最近使用 → 使用回数 の順で一覧表示 |

注意：タグフィルタとして使われるのは最初の `#tag` トークンのみで、大文字小文字を区別した完全一致です（`#SQL` は `sql` タグに一致しません）。検索結果は最大 100 件、テキスト照合は前方一致なので、単語の途中（や空白のない CJK 文字列の途中）から取った語句は一致しません。

メインウィンドウを開かずに、パネル内からアクティブなプロジェクトを切り替えられます。キーボードのみで、回り道はありません。`⌘1`–`⌘9` で上位 9 件を直接実行、`⌘C` は貼り付けずにコピー、`⌘P` はパネルを固定、`Esc` で閉じます。

## 設定 / Configuration

| 設定 | 場所 | 備考 |
|---|---|---|
| グローバルホットキー | `设置 → 偏好 → 快捷键 → 呼出面板` | ショートカットは 1 つ。トグル動作: 同じキーで閉じる |
| テーマ | `设置 → 偏好 → 外观 → 主题` | ライト / ダーク / システムに追従 |
| ログイン時に起動 | `设置 → 偏好 → 权限与启动` | `SMAppService` を使用 |
| アップデートチャネル | GitHub Releases（手動） | Sparkle 2 は組み込み済みだが、署名済み appcast がホストされるまで無効。リリース通知を購読し、`.app` を差し替える |
| データベースの場所 | `~/Library/Application Support/PromptPanel/promptpanel.db` | 単一ファイルの SQLite、バックアップが容易 |
| ログ | `~/Library/Logs/PromptPanel/` | メインウィンドウの「Runtime Health」から確認 |

## プライバシーとデータ

- **定義上ローカルファースト。** あなたのプロンプトは Mac 上の単一の SQLite ファイルに保存されます。アプリはあなたのコンテンツをどこにも POST しません。
- **テレメトリなし。** 分析 SDK も、メトリクスのエンドポイントも、クラッシュレポートサービスもありません。
- **ネットワークアクセス** は現在のリリースでゼロです。Sparkle はバンドルされていますが、アップデートフィードは設定されていないため、将来のビルドが appcast を同梱しない限り、外向きの通信は一切発生しません。
- **アカウントなし。** サインインするものは何もありません。
- **オープンソース。** 上記のいずれも `Sources/PromptPanel/Core/` を監査して検証できます。

あなたのプロンプトに独自情報 — 社内アーキテクチャ、クライアント案件、NDA に縛られたコンテキスト — が含まれるなら、これこそがあなたが求める性質です。

## PromptPanel は代替ツールとどう違うか？ / How does PromptPanel compare to alternatives?

> 素早い方向づけであり、けなすものではありません。これらのツールはそれぞれの分野で優れています。

| | **PromptPanel** | TextExpander | Espanso | Raycast Snippets | Alfred Snippets | Browser prompt extensions |
|---|:---:|:---:|:---:|:---:|:---:|:---:|
| オープンソース | ✅ MIT | ❌ | ✅ GPLv3 | 部分的 | ❌ | まちまち |
| macOS ネイティブ（Electron / Web ランタイムなし） | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 任意のアプリで動作（ブラウザだけでない） | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| クイック検索パネル UI（トリガー文字列だけでない） | ✅ | 部分的 | ❌ | ✅ | ✅ | まちまち |
| プロジェクト / コンテキスト分離 | ✅ ファーストクラス | グループ | フォルダ | フォルダ | フォルダ | まれ |
| キーボードのみのフロー | ✅ | 部分的 | ✅ | ✅ | ✅ | まちまち |
| ローカル専用 / クラウドなしの選択肢 | ✅ 既定 | 任意、有料プランはクラウドへ誘導 | ✅ | アカウント必須 | ✅ | 通常クラウド |
| 無料 | ✅ | $$$ | ✅ | フリーミアム | Powerpack が必要 | まちまち |
| AI プロンプトワークフロー専用に構築 | ✅ | ❌ | ❌ | ❌ | ❌ | ✅ ただしブラウザ限定 |

**要するに:** ブラウザの中だけで生きているなら、ブラウザ拡張機能で十分です。Cursor/VS Code/ターミナル/Slack/あらゆる場所で生きているなら、ネイティブでパネルベースのものが必要です。ネイティブでパネルベースの選択肢の中で、PromptPanel はオープンソースで AI プロンプトの形に沿ったものです。

## ワークフローの例 / Workflow examples

PromptPanel を日常でどう使うかの具体例です。これらは PromptPanel が答えるために作られた、ロングテールの「どうすれば…」という問いも兼ねています。

- **標準の role / system prompt で新しい ChatGPT / Claude チャットを立ち上げる。** ホットキー → `role` と入力 → Enter。「あなたはシニアスタッフエンジニアで…」を 200 回目も打ち直す必要はもうありません。
- **Cursor / Copilot のプロジェクトコンテキストブロックを新しいファイルに落とし込む。** 「これがアーキテクチャ、規約、制約です」という複数段落のブロックを一度保存しておき、任意の新しい Cursor セッションにワンキーで貼り付けます。
- **コードレビューのチェックリストを PR ドラフトに貼り付ける。** 長い箇条書きのチェックリストを PromptPanel に置いておき、ひとつのホットキーで GitHub PR の説明に追加します。
- **正確なフラグの組み合わせで繰り返しのターミナルコマンドを実行する。** `kubectl get pods --context=prod --namespace=… -o jsonpath=…` — 一度入力して保存し、短い検索文字列で呼び出します。
- **議事録テンプレートを Notion / Obsidian / Apple Notes に挿入する。** 毎週月曜のスタンドアップで同じテンプレート → ひとつのホットキー、メモアプリのスクラッチパッドからのコピペはゼロ。
- **カスタマーサービス / セールスの返信テンプレートを Slack やメールに送り込む。** テンプレートごとに異なるトーンを、メモフォルダではなくクイック検索パネルから選びます。
- **分離されたプロンプトセットでプロジェクト間を切り替える。** 各プロジェクトグループが独自の role prompt、スニペット、テンプレートを保持するので、コンテキストがクライアント間で混ざりません。

## 技術スタック / Tech stack

- **言語:** Swift 5.10
- **UI:** AppKit（`NSPanel`、`NSStatusItem`）+ SwiftUI
- **ストレージ:** [GRDB.swift](https://github.com/groue/GRDB.swift) による SQLite
- **ホットキー:** [sindresorhus/KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)（内部では Carbon Hot Key）
- **自動貼り付け:** フォーカス復元後に ⌘V を合成する `CGEvent`
- **ログイン項目:** `SMAppService`
- **アップデーター:** [Sparkle 2](https://sparkle-project.org/)
- **配布:** Developer ID + Apple 公証（Mac App Store なし）
- **ビルド:** Swift Package Manager — Xcode プロジェクト不要

完全な意思決定ログは [docs/技术选型.md](docs/技术选型.md) を参照してください。

## プロジェクト構成 / Project layout

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

## ドキュメント / Documentation

公開ドキュメント一式はリポジトリの一部です。

- [ドキュメント索引](docs/README.md)
- [FAQ](docs/FAQ.md)
- [プロダクト PRD](docs/项目快贴-PRD.md)
- [プロジェクト紹介](docs/项目介绍.md)
- [アーキテクチャ](docs/架构说明.md)
- [コアモジュールとロジック](docs/关键模块与核心逻辑.md)
- [API と機能仕様](docs/API与功能说明.md)
- [設定](docs/配置说明.md)
- [デプロイ](docs/部署说明.md)
- [開発規約](docs/开发规范.md)
- [使用例](docs/使用示例.md)
- [運用とトラブルシューティング](docs/运维与排错指南.md)
- [メンテナ引き継ぎガイド](docs/接手维护指南.md)
- [ドキュメント/コード同期マトリクス](docs/文档与代码同步矩阵.md)
- [リリースとリカバリ](docs/生产发布与恢复手册.md)
- [ロードマップとコントリビューションガイド](docs/路线图与贡献指南.md)
- [AI 検索とディスカバラビリティ](docs/ai-search-discoverability.md)
- [完全な LLM コンテキスト](docs/ai-search/llms-full.txt)
- [検索メタデータ JSON-LD](docs/search-metadata.schema.jsonld)
- [コントリビュート](.github/CONTRIBUTING.md)
- [セキュリティ](.github/SECURITY.md)
- [CodeMeta ソフトウェアメタデータ](codemeta.json)

回答エンジンやリポジトリを認識する AI ツール向けには、[llms.txt](llms.txt) または拡張版の [llms-full.txt](docs/ai-search/llms-full.txt) から始めてください。

## 検索と AI ディスカバラビリティ / Search & AI Discoverability

PromptPanel は、ユーザーと回答エンジンがプロジェクトを正確に識別できるよう、従来の SEO と GEO の面をリポジトリ内に保持しています。

- `README.md` と `README.zh-CN.md` は、人間向けのランディングページ要約と最新のスクリーンショットを提供します。
- [llms.txt](llms.txt) は、リポジトリを認識するツール向けの短い AI 可読索引です。
- [docs/ai-search/llms-full.txt](docs/ai-search/llms-full.txt) は、FAQ 形式の回答を備えた拡張版の回答エンジン向けコンテキストです。
- [codemeta.json](codemeta.json) と [Schema.org JSON-LD](docs/search-metadata.schema.jsonld) は、ソフトウェアカタログ、検索クローラー、将来のドキュメントサイト公開に向けてアプリを記述します。
- [AI 検索とディスカバラビリティ](docs/ai-search-discoverability.md) は、正規の表現、検索意図マップ、メンテナンスチェックリストを定義します。

## ロードマップ / Roadmap

PromptPanel は **意図的に小さい** ロードマップに従います。PRD には、永久に対象外の項目（クラウド同期、チーム、ワークフローのオーケストレーション）が明記されています。スコープ内では:

- [x] v1.0 — メインリンク完成: ホットキー → 検索 → 実行、プロジェクト、クリップボードフォールバック、ライト/ダーク、ログイン項目、Sparkle、署名・公証スクリプト
- [x] JSON / Markdown インポート & エクスポート、インポート前の自動バックアップ付き
- [ ] ワンタップの「最後のエントリを繰り返す」
- [ ] 変数テンプレート（`{{name}}` 形式）— メインリンクを遅くせずに追加できる場合のみ

優先順位付けのルールは [docs/路线图与贡献指南.md](docs/路线图与贡献指南.md)、出荷済みの内容は [CHANGELOG.md](CHANGELOG.md)、公開計画は [issues](https://github.com/tytsxai/PromptPanel/issues) を参照してください。

## よくある質問 / Frequently asked questions

より長い FAQ は [FAQ.md](docs/FAQ.md) を参照してください。ここではよくあるものを紹介します。

### PromptPanel は無料ですか？

はい。MIT ライセンスです。有料プランも、使用上限も、アカウントもありません。

### Apple Silicon（M1/M2/M3/M4）で動作しますか？

はい — リリースはユニバーサルバイナリ（arm64 + x86_64）としてビルドされるため、macOS 14 以降の Apple Silicon と Intel の Mac のどちらでもネイティブに動作します。

### 私のプロンプトをどこかに送信しますか？

いいえ。現在のリリースはネットワーク通信を一切行いません。Sparkle はバンドルされていますが、このビルドではアップデートフィードが設定されていないため、外向きのトラフィックはまったく発生しません。あなたのプロンプトの内容が Mac の外に出ることはありません。

### なぜ Accessibility 権限を求めるのですか？

パネルが隠れて前のアプリがフォーカスを取り戻した後に、`⌘V` キーストロークを合成するためです。この権限がなくてもアプリは動作します。クリップボードのステップで止まり、「press ⌘V to paste」というトーストを表示するだけです。

### クラウド同期 / チーム共有 / ワークフローを追加しますか？

いいえ、意図的にしません。それらは [PRD §4.2](docs/项目快贴-PRD.md) で **恒久的な非目標** として記載されています。プロダクトのアイデンティティは「シングルユーザー、ローカル専用、高速」です。そのいずれかを追加すると、プロダクトそのものが変わってしまいます。

### なぜ Electron / Tauri ではないのですか？

このプロダクトの最もホットなパス（グローバルホットキーのタイミング、フォーカス復元、合成キーストロークの注入、Accessibility 権限のフロー）は、macOS のシステム統合に関わる問題です。クロスプラットフォームのシェルは、このプロダクトで重要な機能を何も得られないまま、レイテンシと間接性を増やすだけです。完全な理由は [docs/技术选型.md](docs/技术选型.md) を参照してください。

### バグ報告や機能リクエストはどうすればいいですか？

issue を開いてください: <https://github.com/tytsxai/PromptPanel/issues>。テンプレートを使ってください — お互いのやり取りを節約できます。

### 他のツールから既存のプロンプトをインポートするには？

PromptPanel ライブラリを丸ごと移行するには `Settings → Maintenance → Import JSON` を、Markdown のプロンプトコレクションには `Import MD` を使います。インポートは自動的にまずローカルデータベースのバックアップを作成します。`Export JSON` は無損失の移行に最適で、`Export MD` はレビュー可能な共有に最適です。

## コントリビュート / Contributing

PR を歓迎します — まず [CONTRIBUTING.md](.github/CONTRIBUTING.md) をお読みください。分かりにくい 2 つのルール:

1. **UI の変更は `frontend-draft/` と一致させること。** そのディレクトリがビジュアルの信頼できる情報源です。JSX モックアップと矛盾する Swift ビューを出荷しないでください。
2. **PRD のスコープ内に留まること。** 提案がプロダクトをクラウド / チーム / ワークフローの方向へ押しやるなら、どれほどよく実装されていても「no」です。これはゲートキーピングではなく、このツールが高速で信頼できる理由そのものです。

## 謝辞 / Acknowledgments

PromptPanel は以下の上に成り立っています:

- Gwendal Roué 氏による [GRDB.swift](https://github.com/groue/GRDB.swift)
- Sindre Sorhus 氏による [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)
- Sparkle チームによる [Sparkle](https://github.com/sparkle-project/Sparkle)

…そして、システム統合のパスを可能にしたドキュメントと Stack Overflow の回答を提供してくれた、より広い Swift / AppKit コミュニティに感謝します。

## ライセンス / License

[MIT](LICENSE) © 2026 tytsxai and PromptPanel contributors.

---

<sub>**キーワード**（検索したときに実際に見つけられるように）: macOS prompt manager · AI prompt launcher · ChatGPT prompt manager macOS · Claude prompt library · Cursor snippet manager · Copilot prompt template launcher · open-source TextExpander alternative · Espanso alternative · Raycast snippets alternative · Alfred snippet replacement · global hotkey paste macOS · local-first prompt library · offline AI prompt storage · native Swift NSPanel app · AI workflow productivity tool · prompt template manager macOS · snippet launcher macOS · keyboard-first prompt picker · LLM prompt library Mac · prompt engineering toolkit macOS · Cursor prompt manager · fast local prompt launcher for AI · NDA-safe prompt storage · macOS プロンプト管理 · プロンプトランチャー · スニペットランチャー · ローカルファースト · キーボードファースト。</sub>

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=tytsxai/PromptPanel&type=Date)](https://www.star-history.com/#tytsxai/PromptPanel&Date)
