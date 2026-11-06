#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
BUILD_OUTPUT_DIR="${REPO_ROOT}/dist/ui-qa"
OUTPUT_DIR="${REPO_ROOT}/docs/ui-qa/latest"
QA_ROOT="${TMPDIR%/}/promptpanel-ui-qa"
APP_PATH="${BUILD_OUTPUT_DIR}/PromptPanel.app/Contents/MacOS/PromptPanel"
APP_SUPPORT_DIR="${QA_ROOT}/app-support"
LOGS_DIR="${QA_ROOT}/logs"
DATABASE_PATH="${APP_SUPPORT_DIR}/promptpanel.db"

usage() {
    cat <<'EOF'
Usage: scripts/capture-ui-qa.sh [--skip-build] [--output-dir <path>]

Captures six window-cropped QA screenshots (dark + light for each surface)
at the unified default sizes:
  - panel-dark.png    / panel-light.png       (快捷面板 560x700)
  - library-dark.png  / library-light.png     (主窗口 · 内容库 1040x760)
  - settings-dark.png / settings-light.png    (主窗口 · 设置 1040x760)
EOF
}

SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

# Every QA instance this script launches, by pid. Killing by pid is the only
# reliable way out: `pkill -f "$APP_PATH"` silently matches nothing when the
# repo path contains non-ASCII characters, and a survivor keeps fighting the
# user's installed PromptPanel for the global hotkey and the Accessibility
# grant long after this script has exited.
typeset -ga QA_APP_PIDS=()

kill_qa_app() {
    local pid
    local alive

    for pid in "${QA_APP_PIDS[@]}"; do
        kill "$pid" >/dev/null 2>&1 || true
    done

    for _ in {1..20}; do
        alive=0
        for pid in "${QA_APP_PIDS[@]}"; do
            if kill -0 "$pid" >/dev/null 2>&1; then
                alive=1
            fi
        done
        if [[ "$alive" -eq 0 ]]; then
            break
        fi
        sleep 0.1
    done

    for pid in "${QA_APP_PIDS[@]}"; do
        kill -9 "$pid" >/dev/null 2>&1 || true
        wait "$pid" 2>/dev/null || true
    done

    # Belt and braces for anything launched by an earlier, interrupted run.
    pkill -f "$APP_PATH" >/dev/null 2>&1 || true
    QA_APP_PIDS=()
}

cleanup() {
    kill_qa_app
}

trap cleanup EXIT INT TERM

# `screencapture` needs Screen Recording permission for whichever terminal runs
# this script. Probe before building or launching anything, so a missing grant
# costs a message instead of a half-finished run.
typeset -g HAS_SCREEN_RECORDING_PERMISSION=0

probe_screen_recording_permission() {
    local probe="${TMPDIR%/}/promptpanel-screencapture-probe.png"
    rm -f "$probe"
    if screencapture -x "$probe" >/dev/null 2>&1 && [[ -s "$probe" ]]; then
        rm -f "$probe"
        HAS_SCREEN_RECORDING_PERMISSION=1
        return 0
    fi
    rm -f "$probe"
    HAS_SCREEN_RECORDING_PERMISSION=0
    echo "Screen Recording permission not available for screencapture; falling back to in-process AppKit window snapshot (PROMPTPANEL_QA_SNAPSHOT_PATH)." >&2
    return 0
}

build_app() {
    "${REPO_ROOT}/scripts/build-app.sh" --debug --no-archive --output-dir "$BUILD_OUTPUT_DIR" >/dev/null
}

bootstrap_database() {
    rm -rf "$QA_ROOT"
    mkdir -p "$APP_SUPPORT_DIR" "$LOGS_DIR"

    env \
        PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1 \
        PROMPTPANEL_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
        PROMPTPANEL_LOGS_DIR="$LOGS_DIR" \
        "$APP_PATH" >/dev/null 2>&1 &
    local pid=$!
    QA_APP_PIDS+=("$pid")
    sleep 2
    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    QA_APP_PIDS=("${(@)QA_APP_PIDS:#$pid}")
}

seed_sample_data() {
    local default_project_id
    default_project_id=$(sqlite3 "$DATABASE_PATH" "SELECT id FROM projects WHERE is_default = 1 LIMIT 1;")

    if [[ -z "$default_project_id" ]]; then
        echo "Failed to locate default project in QA database." >&2
        exit 1
    fi

    sqlite3 "$DATABASE_PATH" <<SQL
BEGIN;
DELETE FROM execution_logs;
DELETE FROM entry_versions;
DELETE FROM entries;
DELETE FROM projects WHERE is_default = 0 AND id != 'builtin-inbox';
INSERT INTO projects (id, name, is_default, group_kind, is_archived, icon_name, created_at, updated_at) VALUES
  ('cat-dev', '开发与代码审查', 0, 'category', 0, 'hammer', datetime('now', '-5 day'), datetime('now', '-1 day')),
  ('cat-video', '视频与内容创作', 0, 'category', 0, 'video', datetime('now', '-4 day'), datetime('now', '-2 day')),
  ('proj-promptpanel', 'PromptPanel', 0, 'project', 0, 'folder', datetime('now', '-3 day'), datetime('now')),
  ('proj-fangzhou', '方舟业务', 0, 'project', 0, 'folder', datetime('now', '-2 day'), datetime('now', '-1 hour')),
  ('proj-legacy', '旧版官网改版', 0, 'project', 1, 'archivebox', datetime('now', '-20 day'), datetime('now', '-10 day'));
INSERT INTO entries (id, project_id, title, content, type, is_pinned, is_completed, sort_order, use_count, last_used_at, created_at, updated_at, tags) VALUES
  ('entry-pp-1', 'proj-promptpanel', 'Bug 修复回执', '问题现象：GitHub README 截图未提交且文档描述滞后于 V7 架构' || char(10) || '根因：docs/ui-qa/latest 曾被写入 .gitignore' || char(10) || '修复内容：重跑 UI 截图并同步全量中英/多语言文档与版本历史' || char(10) || '验证结果：swift test 与 check-docs.sh 全部通过', 'reply', 1, 0, 0, 12, datetime('now', '-1 hour'), datetime('now', '-2 day'), datetime('now', '-1 hour'), '["回执","工程"]'),
  ('entry-pp-2', 'proj-promptpanel', '发布前检查清单', '1. 跑 swift build 和 swift test' || char(10) || '2. 验证权限与自动粘贴链路' || char(10) || '3. 检查数据目录、版本历史与云同步状态', 'todo', 0, 0, 0, 6, datetime('now', '-3 hour'), datetime('now', '-2 day'), datetime('now', '-3 hour'), '["发布","检查清单"]'),
  ('entry-pp-3', 'proj-promptpanel', '设计收口提示词', '请基于当前 macOS 原生毛玻璃与三栏布局判断主链路是否足够紧凑，并给出最值得优先解决的 3 个点。', 'prompt', 0, 0, 0, 4, datetime('now', '-1 day'), datetime('now', '-2 day'), datetime('now', '-1 day'), '["设计","AI"]'),
  ('entry-pp-4', 'proj-promptpanel', '交付说明模板', '本次改动已完成实现、构建验证和窗口级验收，支持三层分组、历史版本回滚与自托管同步。', 'reply', 0, 0, 0, 2, datetime('now', '-2 day'), datetime('now', '-2 day'), datetime('now', '-2 day'), '["交付"]'),
  ('entry-g-1', '$default_project_id', '通用：代码审计结论', '请直接列出 P0-P2 级问题、根因、影响面和建议修法，不要泛泛而谈。', 'prompt', 1, 0, 0, 18, datetime('now', '-40 minute'), datetime('now', '-4 day'), datetime('now', '-40 minute'), '["审计","工程"]'),
  ('entry-g-2', '$default_project_id', '通用：状态同步', '已完成本地验证，下面是当前真实状态与剩余风险。', 'reply', 0, 0, 0, 20, datetime('now', '-5 hour'), datetime('now', '-4 day'), datetime('now', '-5 hour'), '["同步"]'),
  ('entry-cat-dev-1', 'cat-dev', 'Swift 并发与主线程检查', '请审查当前改动是否违反主线程零 I/O 与零 O(n) 聚合规范。', 'prompt', 0, 0, 0, 8, datetime('now', '-6 hour'), datetime('now', '-3 day'), datetime('now', '-6 hour'), '["Swift","并发"]'),
  ('entry-cat-video-1', 'cat-video', '产品演示脚本结构', '痛点引入（5秒）-> 快捷键呼出演示（10秒）-> 核心差异收尾（5秒）。', 'prompt', 0, 0, 0, 5, datetime('now', '-12 hour'), datetime('now', '-3 day'), datetime('now', '-12 hour'), '["视频","脚本"]'),
  ('entry-fz-1', 'proj-fangzhou', '方舟联调环境说明', '网关地址与鉴权 Header 模板，发版前请先跑连通性自检。', 'code', 0, 0, 0, 4, datetime('now', '-2 day'), datetime('now', '-3 day'), datetime('now', '-2 day'), '["联调"]'),
  ('entry-leg-1', 'proj-legacy', '旧版重定向规则归档', '历史静态路径 301 映射清单（已归档备查）。', 'note', 0, 1, 0, 1, datetime('now', '-15 day'), datetime('now', '-20 day'), datetime('now', '-15 day'), '["归档"]'),
  ('entry-inbox-1', 'builtin-inbox', '待办：补齐 GitHub 截图与多语言 README', '更新 panel-light / panel-dark / library-dark / settings-dark 四张主截图并提交入库。', 'todo', 1, 0, 0, 3, datetime('now', '-20 minute'), datetime('now', '-1 day'), datetime('now', '-20 minute'), '["待办","文档"]');
INSERT INTO entry_versions (id, entry_id, version_number, title, content, change_note, created_at) VALUES
  ('ver-g-1-v1', 'entry-g-1', 1, '通用：代码审计结论', '请列出主要问题与建议修法。', '初始版本', datetime('now', '-4 day')),
  ('ver-g-1-v2', 'entry-g-1', 2, '通用：代码审计结论', '请直接列出 P0-P2 级问题、根因、影响面和建议修法，不要泛泛而谈。', '细化 P0-P2 分级输出要求', datetime('now', '-40 minute')),
  ('ver-pp-1-v1', 'entry-pp-1', 1, 'Bug 修复回执', '问题现象 / 根因 / 修复内容 / 验证结果 / 风险与回滚', '初始版本', datetime('now', '-2 day')),
  ('ver-pp-1-v2', 'entry-pp-1', 2, 'Bug 修复回执', '问题现象：GitHub README 截图未提交且文档描述滞后于 V7 架构' || char(10) || '根因：docs/ui-qa/latest 曾被写入 .gitignore' || char(10) || '修复内容：重跑 UI 截图并同步全量中英/多语言文档与版本历史' || char(10) || '验证结果：swift test 与 check-docs.sh 全部通过', '补充 V7 验收详情', datetime('now', '-1 hour'));
INSERT INTO app_settings (key, value) VALUES
  ('current_project_id', 'proj-promptpanel')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
COMMIT;
SQL
}

set_app_theme() {
    local theme="$1"  # system | light | dark
    sqlite3 "$DATABASE_PATH" <<SQL
INSERT INTO app_settings (key, value) VALUES ('app_theme', '$theme')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
SQL
}

set_panel_size() {
    local width="$1"
    local height="$2"
    sqlite3 "$DATABASE_PATH" <<SQL
INSERT INTO app_settings (key, value) VALUES
  ('panel_content_width', '$width'),
  ('panel_content_height', '$height')
ON CONFLICT(key) DO UPDATE SET value = excluded.value;
SQL
}

window_id_for_pid() {
    local pid="$1"
    local min_width="$2"
    local min_height="$3"

    swift -e '
import Foundation
import CoreGraphics

let pid = Int32(CommandLine.arguments[1])!
let minWidth = Double(CommandLine.arguments[2])!
let minHeight = Double(CommandLine.arguments[3])!
let windows = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
    .filter {
        let bounds = $0[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        return width >= minWidth && height >= minHeight
    }

if let candidate = windows.max(by: { lhs, rhs in
    let left = lhs[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let right = rhs[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let leftArea = (left["Width"] as? Double ?? 0) * (left["Height"] as? Double ?? 0)
    let rightArea = (right["Width"] as? Double ?? 0) * (right["Height"] as? Double ?? 0)
    return leftArea < rightArea
}), let id = candidate[kCGWindowNumber as String] as? Int {
    print(id)
}
' "$pid" "$min_width" "$min_height"
}

wait_for_window_id() {
    local pid="$1"
    local min_width="$2"
    local min_height="$3"

    local window_id=""
    for _ in {1..40}; do
        window_id=$(window_id_for_pid "$pid" "$min_width" "$min_height")
        if [[ -n "$window_id" ]]; then
            echo "$window_id"
            return 0
        fi
        sleep 0.25
    done

    echo "Failed to find a window for pid $pid with minimum size ${min_width}x${min_height}." >&2
    return 1
}

capture_window() {
    local output_path="$1"
    local min_width="$2"
    local min_height="$3"
    shift 3

    kill_qa_app
    rm -f "$output_path"

    if [[ "$HAS_SCREEN_RECORDING_PERMISSION" -eq 1 ]]; then
        env \
            PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1 \
            PROMPTPANEL_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
            PROMPTPANEL_LOGS_DIR="$LOGS_DIR" \
            "$@" \
            "$APP_PATH" >/dev/null 2>&1 &
        local pid=$!
        QA_APP_PIDS+=("$pid")

        local window_id
        window_id=$(wait_for_window_id "$pid" "$min_width" "$min_height")
        sleep 1
        screencapture -x -l "$window_id" "$output_path"
        wait_for_valid_capture "$output_path"
    else
        env \
            PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1 \
            PROMPTPANEL_APP_SUPPORT_DIR="$APP_SUPPORT_DIR" \
            PROMPTPANEL_LOGS_DIR="$LOGS_DIR" \
            PROMPTPANEL_QA_SNAPSHOT_PATH="$output_path" \
            "$@" \
            "$APP_PATH" >/dev/null 2>&1 &
        local pid=$!
        QA_APP_PIDS+=("$pid")

        local window_id
        window_id=$(wait_for_window_id "$pid" "$min_width" "$min_height")
        wait_for_valid_capture "$output_path"
    fi

    kill "$pid" >/dev/null 2>&1 || true
    wait "$pid" 2>/dev/null || true
    QA_APP_PIDS=("${(@)QA_APP_PIDS:#$pid}")
}

wait_for_valid_capture() {
    local output_path="$1"

    for _ in {1..50}; do
        if [[ -s "$output_path" ]] && sips -g pixelWidth -g pixelHeight "$output_path" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done

    echo "Failed to capture a readable window screenshot: $output_path" >&2
    return 1
}

assert_capture_set() {
    local missing=0
    local name

    for name in panel-dark.png panel-light.png library-dark.png library-light.png settings-dark.png settings-light.png; do
        if ! [[ -s "$OUTPUT_DIR/$name" ]] || ! sips -g pixelWidth -g pixelHeight "$OUTPUT_DIR/$name" >/dev/null 2>&1; then
            echo "Missing or invalid QA screenshot: $OUTPUT_DIR/$name" >&2
            missing=1
        fi
    done

    if [[ "$missing" -ne 0 ]]; then
        exit 1
    fi
}

mkdir -p "$OUTPUT_DIR"
rm -f \
    "$OUTPUT_DIR"/panel.png "$OUTPUT_DIR"/library.png "$OUTPUT_DIR"/settings.png \
    "$OUTPUT_DIR"/panel-default.png "$OUTPUT_DIR"/panel-min.png \
    "$OUTPUT_DIR"/settings-general.png "$OUTPUT_DIR"/settings-backup.png "$OUTPUT_DIR"/settings-about.png \
    "$OUTPUT_DIR"/panel-dark.png "$OUTPUT_DIR"/panel-light.png \
    "$OUTPUT_DIR"/library-dark.png "$OUTPUT_DIR"/library-light.png \
    "$OUTPUT_DIR"/settings-dark.png "$OUTPUT_DIR"/settings-light.png
# Legacy per-mode files above are cleaned so stale artifacts don't linger.

probe_screen_recording_permission

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    build_app
fi

bootstrap_database
seed_sample_data

# Unified default panel size (matches Constants.panelContentSize = 560x700).
set_panel_size 560 700

# Capture a full set (panel / library / settings) for each theme so the QA
# folder mirrors the design-baseline dark + light variants 1:1.
for theme in dark light; do
    set_app_theme "$theme"

    capture_window "$OUTPUT_DIR/panel-$theme.png" 500 560 \
        PROMPTPANEL_QA_OPEN_PANEL_ON_LAUNCH=1 \
        PROMPTPANEL_QA_OPEN_PANEL_DELAY_MS=700

    capture_window "$OUTPUT_DIR/library-$theme.png" 960 700 \
        PROMPTPANEL_QA_OPEN_MAIN_WINDOW_ON_LAUNCH=1 \
        PROMPTPANEL_QA_OPEN_MAIN_WINDOW_DELAY_MS=500 \
        PROMPTPANEL_QA_MAIN_WINDOW_TAB=library

    capture_window "$OUTPUT_DIR/settings-$theme.png" 960 700 \
        PROMPTPANEL_QA_OPEN_MAIN_WINDOW_ON_LAUNCH=1 \
        PROMPTPANEL_QA_OPEN_MAIN_WINDOW_DELAY_MS=500 \
        PROMPTPANEL_QA_MAIN_WINDOW_TAB=settings
done

assert_capture_set

echo "QA screenshots written to: $OUTPUT_DIR"
