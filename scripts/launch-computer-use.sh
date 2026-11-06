#!/bin/zsh

set -euo pipefail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h}
BUILD_OUTPUT_DIR="${REPO_ROOT}/dist/computer-use"
APP_PATH="${BUILD_OUTPUT_DIR}/PromptPanel.app"
QA_ROOT=""
SURFACE="library"
SKIP_BUILD=0
COMPUTER_USE_BUNDLE_ID="com.promptpanel.app.computeruse"
COMPUTER_USE_DISPLAY_NAME="项目快贴 Computer Use"

usage() {
    cat <<'EOF'
Usage: scripts/launch-computer-use.sh [options]

Launch PromptPanel in an isolated QA sandbox so Computer Use can attach
to a visible window immediately.

Options:
  --surface <library|settings|panel>  Which surface to open on launch. Default: library
  --qa-root <path>                    Reuse a specific QA root directory.
  --skip-build                        Reuse the existing app under dist/computer-use.
  --help                              Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --surface)
            SURFACE="$2"
            shift 2
            ;;
        --qa-root)
            QA_ROOT="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
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

case "$SURFACE" in
    library|settings|panel)
        ;;
    *)
        echo "Unsupported surface: $SURFACE" >&2
        exit 64
        ;;
esac

if [[ $SKIP_BUILD -eq 0 ]]; then
    "${REPO_ROOT}/scripts/build-app.sh" \
        --debug \
        --no-archive \
        --output-dir "$BUILD_OUTPUT_DIR" \
        --bundle-identifier "$COMPUTER_USE_BUNDLE_ID" \
        --display-name "$COMPUTER_USE_DISPLAY_NAME"
fi

if [[ -z "$QA_ROOT" ]]; then
    QA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/promptpanel-computer-use.XXXXXX")"
else
    mkdir -p "$QA_ROOT"
fi

APP_SUPPORT_DIR="${QA_ROOT}/AppSupport"
LOGS_DIR="${QA_ROOT}/Logs"
mkdir -p "$APP_SUPPORT_DIR" "$LOGS_DIR"

pkill -f "${APP_PATH}/Contents/MacOS/PromptPanel" >/dev/null 2>&1 || true

env_args=(
    PROMPTPANEL_ALLOW_EXISTING_INSTANCE=1
    PROMPTPANEL_APP_SUPPORT_DIR="$APP_SUPPORT_DIR"
    PROMPTPANEL_LOGS_DIR="$LOGS_DIR"
)

case "$SURFACE" in
    panel)
        env_args+=(
            PROMPTPANEL_QA_OPEN_PANEL_ON_LAUNCH=1
            PROMPTPANEL_QA_OPEN_PANEL_DELAY_MS=700
        )
        ;;
    library|settings)
        env_args+=(
            PROMPTPANEL_QA_OPEN_MAIN_WINDOW_ON_LAUNCH=1
            PROMPTPANEL_QA_OPEN_MAIN_WINDOW_DELAY_MS=500
            PROMPTPANEL_QA_MAIN_WINDOW_TAB="$SURFACE"
        )
        ;;
esac

env "${env_args[@]}" open -na "$APP_PATH"

printf 'PromptPanel Computer Use session is ready.\n'
printf 'App: %s\n' "$APP_PATH"
printf 'Surface: %s\n' "$SURFACE"
printf 'QA root: %s\n' "$QA_ROOT"
printf 'App support: %s\n' "$APP_SUPPORT_DIR"
printf 'Logs: %s\n' "$LOGS_DIR"
printf 'Computer Use app name: %s\n' "$COMPUTER_USE_BUNDLE_ID"
