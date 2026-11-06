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
require_screen_recording_permission() {
    local probe="${TMPDIR%/}/promptpanel-screencapture-probe.png"
    rm -f "$probe"
    if screencapture -x "$probe" >/dev/null 2>&1 && [[ -s "$probe" ]]; then
        rm -f "$probe"
        return 0
    fi
    rm -f "$probe"
    cat >&2 <<'PERMISSION_HELP'
capture-ui-qa.sh needs Screen Recording permission for the terminal running it.

  System Settings > Privacy & Security > Screen & System Audio Recording
  enable your terminal (Terminal.app / iTerm / your IDE), then restart it.

Nothing was built and no PromptPanel instance was launched.
PERMISSION_HELP
    return 1
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
DELETE FROM entries;
DELETE FROM projects WHERE is_default = 0;
INSERT INTO projects (id, name, is_default, created_at, updated_at) VALUES
  ('proj-promptpanel', 'PromptPanel', 0, datetime('now'), datetime('now')),
  ('proj-fangzhou', '方舟业务', 0, datetime('now'), datetime('now'));
INSERT INTO entries (id, project_id, title, content, type, is_pinned, sort_order, use_count, last_used_at, created_at, updated_at, tags) VALUES
  ('entry-pp-1', 'proj-promptpanel', 'Bug 修复回执', '问题现象' || char(10) || '根因' || char(10) || '修复内容' || char(10) || '验证结果' || char(10) || '风险与回滚', 'reply', 1, 90, 12, datetime('now', '-1 hour'), datetime('now', '-2 day'), datetime('now', '-1 hour'), '["回执","工程"]'),
  ('entry-pp-2', 'proj-promptpanel', '发布前检查清单', '1. 跑 swift build 和 swift test' || char(10) || '2. 验证权限与自动粘贴链路' || char(10) || '3. 检查数据目录和备份状态', 'note', 0, 70, 6, datetime('now', '-3 hour'), datetime('now', '-2 day'), datetime('now', '-3 hour'), '["发布","检查清单"]'),
  ('entry-pp-3', 'proj-promptpanel', '设计收口提示词', '请基于当前截图判断主链路是否足够紧凑，并给出最值得优先解决的 3 个点。', 'prompt', 0, 50, 4, datetime('now', '-1 day'), datetime('now', '-2 day'), datetime('now', '-1 day'), '["设计","AI"]'),
  ('entry-pp-4', 'proj-promptpanel', '交付说明模板', '本次改动已完成实现、构建验证和窗口级验收，未触及数据结构兼容边界。', 'reply', 0, 40, 2, datetime('now', '-2 day'), datetime('now', '-2 day'), datetime('now', '-2 day'), '["交付"]'),
  ('entry-g-1', '$default_project_id', '通用：代码审计结论', '请直接列出 P0-P2 级问题、根因、影响面和建议修法。', 'prompt', 1, 80, 18, datetime('now', '-40 minute'), datetime('now', '-4 day'), datetime('now', '-40 minute'), '["审计","工程"]'),
  ('entry-g-2', '$default_project_id', '通用：状态同步', '已完成本地验证，下面是当前真实状态与剩余风险。', 'reply', 0, 30, 20, datetime('now', '-5 hour'), datetime('now', '-4 day'), datetime('now', '-5 hour'), '["同步"]'),
  ('entry-g-3', '$default_project_id', '通用：日报摘要', '今天完成了主链路优化、异常链路收口和验证脚本补齐。', 'note', 0, 10, 9, datetime('now', '-3 day'), datetime('now', '-5 day'), datetime('now', '-3 day'), '["日报"]');
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

require_screen_recording_permission

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
