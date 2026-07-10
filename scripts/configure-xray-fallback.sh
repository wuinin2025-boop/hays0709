#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly SITE_NAME="hays0709"
readonly CONFIG_PATH="/etc/nginx/sites-available/${SITE_NAME}.conf"
readonly ENABLED_LINK="/etc/nginx/sites-enabled/${SITE_NAME}.conf"
readonly SITE_ROOT="/opt/${SITE_NAME}/current"
readonly INDEX_FILE="瀚纳仕H5 demo-启动舱.html"
readonly BACKUP_ROOT="/root/${SITE_NAME}-server-backups"
readonly XRAY_CONFIG="/usr/local/x-ui/bin/config.json"

DOMAIN=""
X_UI_DB="/etc/x-ui/x-ui.db"
HTTP1_PORT="8443"
HTTP2_PORT="8444"
BACKUP_DIR=""
ROLLBACK_ARMED=0

log() {
    printf '[hays0709-xray] %s\n' "$*"
}

die() {
    printf '[hays0709-xray] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  sudo bash scripts/configure-xray-fallback.sh --domain example.com [options]

Options:
  --domain DOMAIN       Domain served by the existing Xray TLS inbound (required)
  --x-ui-db PATH        x-ui SQLite database (default: /etc/x-ui/x-ui.db)
  --http1-port PORT     Nginx loopback HTTP/1.1 port (default: 8443)
  --http2-port PORT     Nginx loopback h2c port (default: 8444)
  -h, --help            Show this help
USAGE
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --domain)
                (($# >= 2)) || die "--domain requires a value"
                DOMAIN="$2"
                shift 2
                ;;
            --x-ui-db)
                (($# >= 2)) || die "--x-ui-db requires a value"
                X_UI_DB="$2"
                shift 2
                ;;
            --http1-port)
                (($# >= 2)) || die "--http1-port requires a value"
                HTTP1_PORT="$2"
                shift 2
                ;;
            --http2-port)
                (($# >= 2)) || die "--http2-port requires a value"
                HTTP2_PORT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

validate_port() {
    local name="$1"
    local value="$2"
    [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1024 && "$value" -le 65535 ]] \
        || die "$name must be an integer from 1024 to 65535"
    [[ "$value" != "443" ]] || die "$name cannot be 443"
}

validate_inputs() {
    [[ -n "$DOMAIN" ]] || die "--domain is required"
    [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] \
        || die "domain must be an ASCII fully-qualified domain name"
    [[ "$X_UI_DB" == /* ]] || die "--x-ui-db must be an absolute path"
    validate_port "--http1-port" "$HTTP1_PORT"
    validate_port "--http2-port" "$HTTP2_PORT"
    [[ "$HTTP1_PORT" != "$HTTP2_PORT" ]] || die "HTTP/1.1 and HTTP/2 ports must differ"
}

require_environment() {
    ((EUID == 0)) || die "run this script with sudo"
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable"
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required"

    local command_name
    for command_name in nginx python3 curl ss systemctl; do
        command -v "$command_name" >/dev/null 2>&1 || die "$command_name is required"
    done
    systemctl cat x-ui >/dev/null 2>&1 || die "x-ui systemd service was not found"
    [[ -f "$X_UI_DB" ]] || die "x-ui database was not found: $X_UI_DB"
    [[ -f "$CONFIG_PATH" ]] || die "deploy the site with scripts/deploy.sh before configuring Xray fallback"
    grep -Fq '# hays0709 managed configuration' "$CONFIG_PATH" \
        || die "$CONFIG_PATH is not managed by this project"
    [[ -e "$ENABLED_LINK" ]] || die "$ENABLED_LINK is not enabled"

    local listeners
    listeners="$(ss -H -ltnp 'sport = :443' 2>/dev/null || true)"
    [[ -n "$listeners" ]] || die "nothing is listening on public port 443"
    grep -Eqi 'xray|x-ui' <<<"$listeners" \
        || die "port 443 is not owned by Xray/x-ui; use scripts/deploy.sh --https instead"
}

check_loopback_port() {
    local port="$1"
    local listeners
    listeners="$(ss -H -ltnp "sport = :$port" 2>/dev/null || true)"
    [[ -z "$listeners" ]] && return 0
    grep -qi 'nginx' <<<"$listeners" \
        || die "127.0.0.1:$port is already used by a non-Nginx service"
}

create_backup() {
    install -d -m 700 "$BACKUP_ROOT"
    BACKUP_DIR="$BACKUP_ROOT/$(date -u +%Y%m%d%H%M%S)-$$"
    install -d -m 700 "$BACKUP_DIR"
    cp -a -- "$CONFIG_PATH" "$BACKUP_DIR/nginx.conf"
    python3 - "$X_UI_DB" "$BACKUP_DIR/x-ui.db" <<'PY'
import sqlite3
import sys

source_path, backup_path = sys.argv[1:]
with sqlite3.connect(source_path) as connection:
    with sqlite3.connect(backup_path) as backup_connection:
        connection.backup(backup_connection)
PY
    chmod 600 "$BACKUP_DIR/x-ui.db"
    ROLLBACK_ARMED=1
    log "backup created: $BACKUP_DIR"
}

rollback() {
    local status="${1:-1}"
    trap - ERR
    if ((ROLLBACK_ARMED == 1)) && [[ -n "$BACKUP_DIR" ]]; then
        log "rollback: restoring Nginx and x-ui backups" >&2
        install -m 644 "$BACKUP_DIR/nginx.conf" "$CONFIG_PATH" || true
        systemctl stop x-ui || true
        rm -f -- "${X_UI_DB}-wal" "${X_UI_DB}-shm"
        cp -a -- "$BACKUP_DIR/x-ui.db" "$X_UI_DB" || true
        systemctl restart x-ui || true
        nginx -t && systemctl reload nginx || true
    fi
    exit "$status"
}

on_error() {
    local status=$?
    local line="$1"
    log "configuration failed near line $line" >&2
    rollback "$status"
}

trap 'on_error "$LINENO"' ERR

render_nginx_config() {
    cat <<EOF
# hays0709 managed configuration
# Public TLS terminates at Xray; browser traffic falls back to these loopback listeners.
server {
    listen 127.0.0.1:${HTTP1_PORT};
    listen 127.0.0.1:${HTTP2_PORT} http2;
    server_name ${DOMAIN};

    root ${SITE_ROOT};
    index "${INDEX_FILE}";
    charset utf-8;

    gzip on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;

    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location = /api/fortune {
        proxy_pass http://127.0.0.1:5173;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(?:png|jpg|jpeg|gif|webp|svg|ico|woff2?)\$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800, immutable" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF
}

install_nginx_fallback_config() {
    local candidate
    candidate="$(mktemp -t hays0709-nginx.XXXXXX)"
    render_nginx_config > "$candidate"
    install -m 644 "$candidate" "$CONFIG_PATH"
    rm -f -- "$candidate"
    nginx -t
    if systemctl is-active --quiet nginx; then
        systemctl reload nginx
    else
        systemctl enable --now nginx
    fi
}

update_x_ui_fallbacks() {
    python3 - "$X_UI_DB" "$DOMAIN" "$HTTP1_PORT" "$HTTP2_PORT" <<'PY'
import json
import sqlite3
import sys

db_path, domain, http1_port, http2_port = sys.argv[1:]
connection = sqlite3.connect(db_path)
connection.row_factory = sqlite3.Row

rows = connection.execute(
    "SELECT id, protocol, stream_settings FROM inbounds WHERE port = 443 AND enable = 1"
).fetchall()
if len(rows) != 1:
    raise SystemExit(f"expected exactly one enabled x-ui inbound on port 443, found {len(rows)}")

inbound = rows[0]
if inbound["protocol"] != "vless":
    raise SystemExit("the port 443 inbound must use VLESS fallback support")

try:
    stream = json.loads(inbound["stream_settings"] or "{}")
except json.JSONDecodeError as error:
    raise SystemExit(f"invalid x-ui stream_settings JSON: {error}")

if stream.get("security") != "tls":
    raise SystemExit("the port 443 Xray inbound must terminate TLS")
tls = stream.get("tlsSettings") or {}
server_name = tls.get("serverName") or ""
if server_name and server_name != domain:
    raise SystemExit(f"Xray TLS serverName is {server_name!r}, expected {domain!r}")
if not tls.get("certificates"):
    raise SystemExit("the port 443 Xray inbound has no TLS certificate configured")

columns = {row[1] for row in connection.execute("PRAGMA table_info(inbound_fallbacks)")}
inbound_id = inbound["id"]
fallbacks = [
    ("h2", f"127.0.0.1:{http2_port}", 0),
    ("http/1.1", f"127.0.0.1:{http1_port}", 1),
    ("", f"127.0.0.1:{http1_port}", 2),
]

with connection:
    if {"master_id", "child_id", "sort_order"}.issubset(columns):
        connection.execute("DELETE FROM inbound_fallbacks WHERE master_id = ?", (inbound_id,))
        connection.executemany(
            """
            INSERT INTO inbound_fallbacks
                (master_id, child_id, name, alpn, path, dest, xver, sort_order)
            VALUES (?, 0, '', ?, '', ?, 0, ?)
            """,
            [(inbound_id, alpn, dest, order) for alpn, dest, order in fallbacks],
        )
    elif "inbound_id" in columns:
        connection.execute("DELETE FROM inbound_fallbacks WHERE inbound_id = ?", (inbound_id,))
        connection.executemany(
            """
            INSERT INTO inbound_fallbacks (inbound_id, name, alpn, path, dest, xver)
            VALUES (?, '', ?, '', ?, 0)
            """,
            [(inbound_id, alpn, dest) for alpn, dest, _ in fallbacks],
        )
    else:
        raise SystemExit("unsupported x-ui inbound_fallbacks schema")
PY
}

verify_generated_xray_config() {
    local attempt
    for attempt in $(seq 1 20); do
        if [[ -f "$XRAY_CONFIG" ]] && python3 - "$XRAY_CONFIG" "$HTTP1_PORT" "$HTTP2_PORT" <<'PY'
import json
import sys

path, http1_port, http2_port = sys.argv[1:]
expected = [
    {"alpn": "h2", "dest": f"127.0.0.1:{http2_port}"},
    {"alpn": "http/1.1", "dest": f"127.0.0.1:{http1_port}"},
    {"dest": f"127.0.0.1:{http1_port}"},
]
with open(path, encoding="utf-8") as config_file:
    config = json.load(config_file)
matches = [
    inbound.get("settings", {}).get("fallbacks", [])
    for inbound in config.get("inbounds", [])
    if inbound.get("port") == 443
]
if matches != [expected]:
    raise SystemExit(1)
PY
        then
            return 0
        fi
        sleep 1
    done
    return 1
}

wait_for_xray_listener() {
    local attempt listeners
    for attempt in $(seq 1 30); do
        listeners="$(ss -H -ltnp 'sport = :443' 2>/dev/null || true)"
        if grep -Eqi 'xray|x-ui' <<<"$listeners"; then
            return 0
        fi
        sleep 1
    done
    log "Xray did not begin listening on port 443 within 30 seconds" >&2
    return 1
}

check_page() {
    local output="$1"
    grep -Fq '今天的班' "$output"
}

verify_nginx_fallbacks() {
    local http1_body http2_body
    http1_body="$(mktemp -t hays0709-http1.XXXXXX)"
    http2_body="$(mktemp -t hays0709-http2.XXXXXX)"

    curl --http1.1 --silent --show-error --fail --max-time 15 \
        --header "Host: $DOMAIN" \
        --output "$http1_body" \
        "http://127.0.0.1:$HTTP1_PORT/"
    check_page "$http1_body"

    curl --http2-prior-knowledge --silent --show-error --fail --max-time 15 \
        --header "Host: $DOMAIN" \
        --output "$http2_body" \
        "http://127.0.0.1:$HTTP2_PORT/"
    check_page "$http2_body"
    rm -f -- "$http1_body" "$http2_body"
}

verify_public_https() {
    local body
    body="$(mktemp -t hays0709-https.XXXXXX)"
    curl --http1.1 --silent --show-error --fail --max-time 20 \
        --resolve "$DOMAIN:443:127.0.0.1" \
        --output "$body" \
        "https://$DOMAIN/"
    check_page "$body"
    rm -f -- "$body"
}

main() {
    parse_args "$@"
    validate_inputs
    require_environment
    check_loopback_port "$HTTP1_PORT"
    check_loopback_port "$HTTP2_PORT"
    create_backup

    install_nginx_fallback_config
    update_x_ui_fallbacks
    systemctl restart x-ui
    systemctl is-active --quiet x-ui
    wait_for_xray_listener
    verify_generated_xray_config
    verify_nginx_fallbacks
    verify_public_https

    ROLLBACK_ARMED=0
    log "Xray fallback is active; backup retained at $BACKUP_DIR"
    log "HTTPS verified: https://$DOMAIN/"
}

main "$@"
