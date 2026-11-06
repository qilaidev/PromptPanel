#!/usr/bin/env bash
set -euo pipefail

# PromptPanel Open-Source Sync Server — Hardened Systemd Deployment Script
# Features:
# - Dedicated unprivileged system user (promptpanel-sync)
# - Strict filesystem & kernel sandboxing (ProtectSystem=strict, ProtectHome=yes, PrivateTmp=yes, NoNewPrivileges=yes)
# - Resource isolation (MemoryMax=128M, CPUQuota=50%)
# - Token-based namespace isolation (each token gets an isolated SQLite WAL database)

SERVICE_NAME="promptpanel-sync"
INSTALL_DIR="/opt/promptpanel-sync"
DATA_DIR="/var/lib/promptpanel-sync"
CONF_DIR="/etc/promptpanel-sync"
PORT="${PP_SYNC_PORT:-18787}"
ALLOWED_TOKENS="${PP_SYNC_ALLOWED_TOKENS:-}"

if ! id -u "$SERVICE_NAME" >/dev/null 2>&1; then
    useradd --system --no-create-home --home-dir "$DATA_DIR" --shell /usr/sbin/nologin "$SERVICE_NAME"
fi

mkdir -p "$INSTALL_DIR" "$DATA_DIR/namespaces" "$DATA_DIR/backups" "$CONF_DIR"
cp "$(dirname "$0")/promptpanel_sync_server.py" "$INSTALL_DIR/promptpanel_sync_server.py"
chmod 755 "$INSTALL_DIR/promptpanel_sync_server.py"
chown -R "$SERVICE_NAME:$SERVICE_NAME" "$DATA_DIR"
chmod 700 "$DATA_DIR"

ENV_FILE="$CONF_DIR/sync.env"
if [[ ! -f "$ENV_FILE" ]] || [[ -n "$ALLOWED_TOKENS" ]]; then
    cat > "$ENV_FILE" <<EOF
PP_SYNC_HOST=0.0.0.0
PP_SYNC_PORT=${PORT}
PP_SYNC_DATA_DIR=${DATA_DIR}
PP_SYNC_ALLOWED_TOKENS=${ALLOWED_TOKENS}
EOF
    chmod 600 "$ENV_FILE"
    chown root:"$SERVICE_NAME" "$ENV_FILE"
    chmod 640 "$ENV_FILE"
fi

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=PromptPanel Open-Source Cloud Sync Server (Isolated)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_NAME}
Group=${SERVICE_NAME}
EnvironmentFile=${ENV_FILE}
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/promptpanel_sync_server.py
Restart=always
RestartSec=2

# Security & Process Isolation
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictSUIDSGID=yes
ReadWritePaths=${DATA_DIR}

# Performance & Resource Isolation
MemoryMax=128M
CPUQuota=50%
LimitNOFILE=16384

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

if command -v ufw >/dev/null 2>&1; then
    if ufw status | grep -q "Status: active"; then
        ufw allow "${PORT}/tcp" comment "PromptPanel Cloud Sync" >/dev/null || true
    fi
fi

echo "PromptPanel Sync Server deployed and running on port ${PORT}."
systemctl status "$SERVICE_NAME" --no-pager -l | head -n 15
