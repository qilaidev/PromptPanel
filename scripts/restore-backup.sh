#!/bin/zsh

set -euo pipefail

LIVE_APP_SUPPORT_DIR="${HOME}/Library/Application Support/PromptPanel"
DEFAULT_APP_SUPPORT_DIR="${PROMPTPANEL_APP_SUPPORT_DIR:-${LIVE_APP_SUPPORT_DIR}}"
TARGET_APP_SUPPORT_DIR="${DEFAULT_APP_SUPPORT_DIR:A}"
DRY_RUN=0

usage() {
    cat <<'EOF'
Usage: scripts/restore-backup.sh [options] /absolute/path/to/backup.sqlite

Restores the selected backup into the live PromptPanel database location.
The app must be closed before running this script.

Options:
  --target-dir <path>  Restore into a specific PromptPanel App Support directory.
  --dry-run            Validate the backup and target path without modifying files.
  --help               Show this help message.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-dir)
            TARGET_APP_SUPPORT_DIR="${2:A}"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        --*)
            usage >&2
            exit 64
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 1 ]]; then
    usage >&2
    exit 64
fi

BACKUP_SOURCE="${1:A}"
DATABASE_PATH="${TARGET_APP_SUPPORT_DIR}/promptpanel.db"

if [[ ! -f "$BACKUP_SOURCE" ]]; then
    echo "Backup file not found: $BACKUP_SOURCE" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 is required to validate the backup before restore." >&2
    exit 1
fi

INTEGRITY_RESULT="$(sqlite3 "$BACKUP_SOURCE" 'PRAGMA integrity_check;' 2>/dev/null || true)"
if [[ "$INTEGRITY_RESULT" != "ok" ]]; then
    echo "Backup integrity check failed: $BACKUP_SOURCE" >&2
    echo "$INTEGRITY_RESULT" >&2
    exit 1
fi

REQUIRED_TABLES=(
    projects
    entries
    entries_fts
    app_settings
    execution_logs
    grdb_migrations
)

for table_name in "${REQUIRED_TABLES[@]}"; do
    TABLE_EXISTS="$(sqlite3 "$BACKUP_SOURCE" "SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table', 'view') AND name = '$table_name';" 2>/dev/null || true)"
    if [[ "$TABLE_EXISTS" != "1" ]]; then
        echo "Backup schema validation failed: missing required table '$table_name'." >&2
        exit 1
    fi
done

DEFAULT_PROJECT_COUNT="$(sqlite3 "$BACKUP_SOURCE" "SELECT COUNT(*) FROM projects WHERE is_default = 1;" 2>/dev/null || true)"
if [[ -z "$DEFAULT_PROJECT_COUNT" || "$DEFAULT_PROJECT_COUNT" -lt 1 ]]; then
    echo "Backup schema validation failed: no default project found." >&2
    exit 1
fi

CURRENT_PROJECT_REFERENCE_COUNT="$(sqlite3 "$BACKUP_SOURCE" "
    SELECT COUNT(*)
    FROM app_settings
    INNER JOIN projects ON projects.id = app_settings.value
    WHERE app_settings.key = 'current_project_id'
      AND TRIM(COALESCE(app_settings.value, '')) != '';
" 2>/dev/null || true)"
if [[ -z "$CURRENT_PROJECT_REFERENCE_COUNT" || "$CURRENT_PROJECT_REFERENCE_COUNT" -lt 1 ]]; then
    echo "Backup schema validation failed: current_project_id is missing, empty, or points to a non-existent project." >&2
    exit 1
fi

if [[ $DRY_RUN -eq 0 && "$TARGET_APP_SUPPORT_DIR" == "${LIVE_APP_SUPPORT_DIR:A}" ]] && pgrep -x "PromptPanel" >/dev/null 2>&1; then
    echo "PromptPanel is running. Quit the app before restoring a backup." >&2
    exit 1
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo "Backup validation passed: ${BACKUP_SOURCE}"
    echo "Dry run target directory: ${TARGET_APP_SUPPORT_DIR}"
    echo "Dry run target database: ${DATABASE_PATH}"
    exit 0
fi

mkdir -p "$TARGET_APP_SUPPORT_DIR"
chmod 700 "$TARGET_APP_SUPPORT_DIR"

TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
RECOVERY_DIR="${TARGET_APP_SUPPORT_DIR}/Recovery/manual-restore-${TIMESTAMP}"
STAGING_DIR="${TARGET_APP_SUPPORT_DIR}/Recovery/manual-restore-staging-${TIMESTAMP}"
STAGED_DATABASE_PATH="${STAGING_DIR}/promptpanel.db"

cleanup_staging() {
    rm -rf "$STAGING_DIR"
}
trap cleanup_staging EXIT

mkdir -p "$STAGING_DIR"
chmod 700 "$STAGING_DIR"
cp "$BACKUP_SOURCE" "$STAGED_DATABASE_PATH"
chmod 600 "$STAGED_DATABASE_PATH"

STAGED_INTEGRITY_RESULT="$(sqlite3 "$STAGED_DATABASE_PATH" 'PRAGMA integrity_check;' 2>/dev/null || true)"
if [[ "$STAGED_INTEGRITY_RESULT" != "ok" ]]; then
    echo "Staged backup integrity check failed: $STAGED_DATABASE_PATH" >&2
    echo "$STAGED_INTEGRITY_RESULT" >&2
    exit 1
fi

if [[ -e "$DATABASE_PATH" || -e "${DATABASE_PATH}-wal" || -e "${DATABASE_PATH}-shm" ]]; then
    mkdir -p "$RECOVERY_DIR"
    chmod 700 "$RECOVERY_DIR"
    for suffix in "" "-wal" "-shm"; do
        SOURCE_PATH="${DATABASE_PATH}${suffix}"
        if [[ -e "$SOURCE_PATH" ]]; then
            mv "$SOURCE_PATH" "${RECOVERY_DIR}/"
        fi
    done
    echo "Existing database moved to: ${RECOVERY_DIR}"
fi

mv "$STAGED_DATABASE_PATH" "$DATABASE_PATH"
chmod 600 "$DATABASE_PATH"
rm -f "${DATABASE_PATH}-wal" "${DATABASE_PATH}-shm"

echo "Backup restored to: ${DATABASE_PATH}"
