#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

readonly SITE_NAME="hays0709"
readonly DEFAULT_REPO_URL="https://github.com/wuinin2025-boop/hays0709.git"
readonly APP_ROOT="/opt/${SITE_NAME}"
readonly RELEASES_DIR="${APP_ROOT}/releases"
readonly CURRENT_LINK="${APP_ROOT}/current"
readonly PREVIOUS_LINK="${APP_ROOT}/previous"
readonly CONFIG_DIR="/etc/nginx/sites-available"
readonly ENABLED_DIR="/etc/nginx/sites-enabled"
readonly CONFIG_PATH="${CONFIG_DIR}/${SITE_NAME}.conf"
readonly ENABLED_LINK="${ENABLED_DIR}/${SITE_NAME}.conf"
readonly INDEX_FILE="瀚纳仕H5 demo-启动舱.html"
readonly APP_PATH="/hays"
readonly TEMPLATE_FILE_NAME="deploy/nginx.conf.template"
readonly SERVICE_TEMPLATE_FILE_NAME="deploy/hays0709.service.template"
readonly SERVICE_NAME="${SITE_NAME}.service"
readonly SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"
readonly ENV_PATH="/etc/${SITE_NAME}.env"

DOMAIN=""
BRANCH="main"
REPO_URL=""
CERTBOT_EMAIL=""
ENABLE_HTTPS=0
ROLLBACK=0
KEEP_RELEASES=5
PROJECT_ROOT=""
SCRIPT_DIR=""
TMP_ROOT=""
RELEASE_PATH=""
OLD_CURRENT=""
OLD_PREVIOUS=""

log() {
    printf '[hays0709] %s\n' "$*"
}

die() {
    printf '[hays0709] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage:
  sudo bash scripts/deploy.sh --domain example.com [options]

Options:
  --domain DOMAIN       ASCII fully-qualified domain name (required)
  --branch REF          Git branch or tag to deploy (default: main)
  --repo-url URL        Git repository URL (defaults to this checkout's origin)
  --https               Obtain/configure a certificate with Certbot
  --email EMAIL         Required with --https for the certificate contact
  --keep-releases N     Keep current, previous, and N-2 additional releases (default: 5)
  --rollback            Swap current and previous releases instead of deploying
  -h, --help            Show this help
USAGE
}

cleanup() {
    if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then
        rm -rf -- "$TMP_ROOT"
    fi
}

trap cleanup EXIT

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --domain)
                (($# >= 2)) || die "--domain requires a value"
                DOMAIN="$2"
                shift 2
                ;;
            --branch)
                (($# >= 2)) || die "--branch requires a value"
                BRANCH="$2"
                shift 2
                ;;
            --repo-url)
                (($# >= 2)) || die "--repo-url requires a value"
                REPO_URL="$2"
                shift 2
                ;;
            --https)
                ENABLE_HTTPS=1
                shift
                ;;
            --email)
                (($# >= 2)) || die "--email requires a value"
                CERTBOT_EMAIL="$2"
                shift 2
                ;;
            --keep-releases)
                (($# >= 2)) || die "--keep-releases requires a number"
                KEEP_RELEASES="$2"
                shift 2
                ;;
            --rollback)
                ROLLBACK=1
                shift
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

validate_inputs() {
    [[ -n "$DOMAIN" ]] || die "--domain is required"
    [[ "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]] \
        || die "domain must be an ASCII fully-qualified domain name without a port or wildcard"
    [[ -n "$BRANCH" && "$BRANCH" != -* && "$BRANCH" != *[[:space:]]* ]] \
        || die "branch/ref must be non-empty and must not begin with '-' or contain whitespace"
    [[ "$KEEP_RELEASES" =~ ^[3-9][0-9]*$ ]] \
        || die "--keep-releases must be an integer of at least 3"
    if ((ENABLE_HTTPS == 1)); then
        [[ -n "$CERTBOT_EMAIL" ]] || die "--email is required with --https"
        [[ "$CERTBOT_EMAIL" != *[[:space:]]* && "$CERTBOT_EMAIL" == *@*.* ]] \
            || die "--email must be a valid non-whitespace email address"
    fi
}

require_root() {
    ((EUID == 0)) || die "run this script with sudo"
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || die "/etc/os-release is unavailable; Ubuntu is required"
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required (detected: ${ID:-unknown})"
    local major_version="${VERSION_ID%%.*}"
    [[ "$major_version" =~ ^[0-9]+$ && "$major_version" -ge 22 ]] \
        || die "Ubuntu 22.04 or newer is required (detected: ${VERSION_ID:-unknown})"
}

ensure_packages() {
    local required=(git nginx rsync curl iproute2 python3 ca-certificates)

    local missing=()
    local package
    for package in "${required[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} > 0)); then
        log "installing missing packages: ${missing[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y "${missing[@]}"
    fi

    command -v git >/dev/null || die "git is unavailable"
    command -v nginx >/dev/null || die "nginx is unavailable"
    command -v rsync >/dev/null || die "rsync is unavailable"
    command -v curl >/dev/null || die "curl is unavailable"
    command -v ss >/dev/null || die "ss is unavailable"
    command -v systemctl >/dev/null || die "systemd/systemctl is required"
}

ensure_node_runtime() {
    local current_major=0
    if command -v node >/dev/null 2>&1; then
        current_major="$(node -p 'Number(process.versions.node.split(".")[0])' 2>/dev/null || printf '0')"
    fi
    if [[ "$current_major" =~ ^[0-9]+$ && "$current_major" -ge 18 ]]; then
        return 0
    fi

    log "installing Node.js 22 runtime"
    local setup_script="$TMP_ROOT/nodesource-setup.sh"
    curl --fail --silent --show-error --location \
        https://deb.nodesource.com/setup_22.x \
        --output "$setup_script"
    bash "$setup_script"
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y nodejs
    command -v node >/dev/null || die "Node.js installation failed"
    [[ "$(node -p 'Number(process.versions.node.split(".")[0])')" -ge 18 ]] \
        || die "Node.js 18 or newer is required"
}

ensure_https_packages() {
    ((ENABLE_HTTPS == 1)) || return 0

    local required=(certbot python3-certbot-nginx)
    local missing=()
    local package
    for package in "${required[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} > 0)); then
        log "installing missing HTTPS packages: ${missing[*]}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y "${missing[@]}"
    fi

    command -v certbot >/dev/null || die "certbot is unavailable"
}

detect_https_port_conflict() {
    ((ENABLE_HTTPS == 1)) || return 0
    command -v ss >/dev/null 2>&1 || die "ss is required to inspect port 443"

    local listeners
    listeners="$(ss -H -ltnp 'sport = :443' 2>/dev/null || true)"
    [[ -n "$listeners" ]] || return 0
    if grep -qi 'nginx' <<<"$listeners"; then
        return 0
    fi

    printf '%s\n' "$listeners" >&2
    die "Port 443 is occupied by a non-Nginx service. If it is x-ui/Xray, deploy HTTP first, then run: sudo bash scripts/configure-xray-fallback.sh --domain $DOMAIN"
}

resolve_repository() {
    if [[ -z "$REPO_URL" ]]; then
        if git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            REPO_URL="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null || true)"
        fi
        REPO_URL="${REPO_URL:-$DEFAULT_REPO_URL}"
    fi
}

prepare_directories() {
    install -d -m 755 "$APP_ROOT" "$RELEASES_DIR" "$APP_ROOT/config-backups" "$CONFIG_DIR" "$ENABLED_DIR"
}

render_nginx_config() {
    local template="$PROJECT_ROOT/$TEMPLATE_FILE_NAME"
    [[ -f "$template" ]] || die "missing Nginx template: $template"

    local rendered
    rendered="$(< "$template")"
    rendered="${rendered//__DOMAIN__/$DOMAIN}"
    rendered="${rendered//__SITE_ROOT__/$CURRENT_LINK}"
    rendered="${rendered//__INDEX_FILE__/$INDEX_FILE}"
    printf '%s\n' "$rendered"
}

ensure_nginx_site_link() {
    if [[ -L "$ENABLED_LINK" ]]; then
        local link_target
        link_target="$(readlink -f "$ENABLED_LINK" || true)"
        [[ "$link_target" == "$CONFIG_PATH" ]] \
            || die "$ENABLED_LINK points to a different Nginx configuration"
    elif [[ -e "$ENABLED_LINK" ]]; then
        die "$ENABLED_LINK exists and is not the managed site symlink"
    else
        ln -s "$CONFIG_PATH" "$ENABLED_LINK"
    fi
}

install_nginx_config() {
    if [[ -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]; then
        grep -Fq "# hays0709 managed configuration" "$CONFIG_PATH" \
            || die "$CONFIG_PATH exists but is not managed by this deployment"
        grep -Eq "server_name[[:space:]]+[^;]*${DOMAIN}([[:space:]]|;)" "$CONFIG_PATH" \
            || die "$CONFIG_PATH has a different server_name; resolve it manually before deploying"
        ensure_nginx_api_proxy
        ensure_nginx_hays_path
        ensure_nginx_site_link
        return
    fi

    local candidate="$TMP_ROOT/nginx.conf.candidate"
    render_nginx_config > "$candidate"
    install -m 644 "$candidate" "$CONFIG_PATH"
    ensure_nginx_site_link

    if ! nginx -t; then
        rm -f -- "$ENABLED_LINK" "$CONFIG_PATH"
        die "generated Nginx configuration failed validation"
    fi
}

ensure_nginx_api_proxy() {
    grep -Fq 'location ^~ /api/fortune' "$CONFIG_PATH" && return 0

    local candidate="$TMP_ROOT/nginx.conf.with-api"
    local backup="$APP_ROOT/config-backups/nginx-before-api-$(date -u +%Y%m%d%H%M%S).conf"
    python3 - "$CONFIG_PATH" "$candidate" <<'PY'
from pathlib import Path
import sys

source_path, target_path = map(Path, sys.argv[1:])
source = source_path.read_text(encoding="utf-8")
needle = "    location / {"
exact_proxy = "    location = /api/fortune {"
prefix_proxy = "    location ^~ /api/fortune {"
proxy = """    location ^~ /api/fortune {
        proxy_pass http://127.0.0.1:5173;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 60s;
        proxy_send_timeout 60s;
    }

"""
if exact_proxy in source:
    upgraded = source.replace(exact_proxy, prefix_proxy, 1)
elif needle in source:
    upgraded = source.replace(needle, proxy + needle, 1)
else:
    raise SystemExit("managed Nginx config has no application location block")
target_path.write_text(upgraded, encoding="utf-8")
PY
    cp -a "$CONFIG_PATH" "$backup"
    install -m 644 "$candidate" "$CONFIG_PATH"
    if ! nginx -t; then
        install -m 644 "$backup" "$CONFIG_PATH"
        nginx -t || true
        die "Nginx API proxy upgrade failed validation; restored the previous configuration"
    fi
}

ensure_nginx_hays_path() {
    if grep -Fq "location = ${APP_PATH} {" "$CONFIG_PATH" &&
        grep -Fq "location ^~ ${APP_PATH}/" "$CONFIG_PATH" &&
        grep -Fq "try_files \"/${INDEX_FILE}\" =404;" "$CONFIG_PATH" &&
        grep -Fq "absolute_redirect off;" "$CONFIG_PATH"; then
        return 0
    fi

    local candidate="$TMP_ROOT/nginx.conf.with-hays-path"
    local backup="$APP_ROOT/config-backups/nginx-before-hays-path-$(date -u +%Y%m%d%H%M%S).conf"
    python3 - "$CONFIG_PATH" "$candidate" "$APP_PATH" "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

source_path, target_path = map(Path, sys.argv[1:3])
app_path, index_file = sys.argv[3:5]
source = source_path.read_text(encoding="utf-8")
old_root = """    location / {
        try_files $uri $uri/ =404;
    }
"""
path_routes = f"""    location = / {{
        return 302 {app_path}/;
    }}

    location = {app_path} {{
        return 301 {app_path}/;
    }}

    location = {app_path}/ {{
        try_files "/{index_file}" =404;
    }}

    location ^~ {app_path}/assets/ {{
        rewrite ^{app_path}/(.*)$ /$1 break;
        try_files $uri =404;
        expires 7d;
        add_header Cache-Control "public, max-age=604800, immutable" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    }}

    location ^~ {app_path}/ {{
        rewrite ^{app_path}/(.*)$ /$1 break;
        try_files $uri $uri/ =404;
    }}

    location / {{
        return 404;
    }}
"""

legacy_index = f"try_files /{index_file} =404;"
quoted_index = f'try_files "/{index_file}" =404;'

if legacy_index in source:
    source = source.replace(legacy_index, quoted_index, 1)
elif old_root in source:
    source = source.replace(old_root, path_routes, 1)
else:
    raise SystemExit("managed Nginx config has no legacy root try_files location to replace")

if "absolute_redirect off;" not in source:
    source = source.replace("    charset utf-8;\n", "    charset utf-8;\n    absolute_redirect off;\n", 1)

target_path.write_text(source, encoding="utf-8")
PY
    cp -a "$CONFIG_PATH" "$backup"
    install -m 644 "$candidate" "$CONFIG_PATH"
    if ! nginx -t; then
        install -m 644 "$backup" "$CONFIG_PATH"
        nginx -t || true
        die "Nginx /hays path upgrade failed validation; restored the previous configuration"
    fi
}

nginx_is_https() {
    [[ -f "$CONFIG_PATH" ]] && grep -Eq 'listen[[:space:]]+(\[::\]:)?443([[:space:];]|.*ssl)|return[[:space:]]+(301|308)[[:space:]]+https://' "$CONFIG_PATH"
}

ensure_nginx_running() {
    if ! nginx -t; then
        log "Nginx configuration test failed" >&2
        return 1
    fi
    if systemctl is-active --quiet nginx; then
        if ! systemctl reload nginx; then
            log "failed to reload Nginx" >&2
            return 1
        fi
    else
        if ! systemctl enable --now nginx; then
            log "failed to start Nginx" >&2
            return 1
        fi
    fi
}

clone_source() {
    local checkout="$TMP_ROOT/source"
    log "cloning $REPO_URL ref $BRANCH" >&2
    git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO_URL" "$checkout"
    [[ -f "$checkout/$INDEX_FILE" ]] || die "source is missing $INDEX_FILE"
    [[ -f "$checkout/瀚纳仕H5 demo.html" ]] || die "source is missing 瀚纳仕H5 demo.html"
    [[ -d "$checkout/assets" ]] || die "source is missing assets/"
    [[ -f "$checkout/server.mjs" ]] || die "source is missing server.mjs"
    [[ -f "$checkout/$SERVICE_TEMPLATE_FILE_NAME" ]] || die "source is missing $SERVICE_TEMPLATE_FILE_NAME"
    printf '%s\n' "$checkout"
}

create_release() {
    local checkout="$1"
    local timestamp
    timestamp="$(date -u +%Y%m%d%H%M%S)-$$"
    RELEASE_PATH="$RELEASES_DIR/$timestamp"
    install -d -m 755 "$RELEASE_PATH"

    rsync -a --delete \
        --include='*.html' \
        --include='server.mjs' \
        --include='assets/***' \
        --exclude='*' \
        "$checkout/" "$RELEASE_PATH/"

    [[ -f "$RELEASE_PATH/$INDEX_FILE" ]] || die "release is missing $INDEX_FILE after rsync"
    [[ -d "$RELEASE_PATH/assets" ]] || die "release is missing assets/ after rsync"
    [[ -f "$RELEASE_PATH/server.mjs" ]] || die "release is missing server.mjs after rsync"
}

ensure_server_env_file() {
    if [[ ! -e "$ENV_PATH" ]]; then
        cat > "$ENV_PATH" <<'EOF'
# Add HAYS_AI_API_KEY here to enable live AI generation.
# HAYS_AI_API_KEY=replace-with-your-key
HAYS_AI_API_BASE_URL=https://api.deepseek.com
HAYS_AI_MODEL=deepseek-v4-flash
HAYS_AI_TIMEOUT_MS=45000
HOST=127.0.0.1
PORT=5173
EOF
    fi
    chown root:www-data "$ENV_PATH"
    chmod 640 "$ENV_PATH"
}

install_app_service() {
    local template="$PROJECT_ROOT/$SERVICE_TEMPLATE_FILE_NAME"
    [[ -f "$template" ]] || die "missing systemd template: $template"
    install -m 644 "$template" "$SERVICE_PATH"
    ensure_server_env_file
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null
}

restart_app_service() {
    if ! systemctl restart "$SERVICE_NAME"; then
        log "failed to restart $SERVICE_NAME" >&2
        return 1
    fi
    systemctl is-active --quiet "$SERVICE_NAME"
}

stop_app_service() {
    systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
}

api_proxy_health_check() {
    local attempt status
    for attempt in $(seq 1 20); do
        status="$(curl --silent --show-error --max-time 2 \
            --output /dev/null \
            --write-out '%{http_code}' \
            'http://127.0.0.1:5173/api/fortune/status' 2>/dev/null || true)"
        [[ "$status" == "200" ]] && return 0
        sleep 1
    done
    return 1
}

atomic_link() {
    local target="$1"
    local link="$2"
    local temporary="${link}.tmp.$$"
    rm -f -- "$temporary"
    ln -s -- "$target" "$temporary"
    mv -Tf -- "$temporary" "$link"
}

read_link_target() {
    local link="$1"
    if [[ -L "$link" ]]; then
        readlink -f "$link" || true
    fi
}

remember_current_links() {
    OLD_CURRENT="$(read_link_target "$CURRENT_LINK")"
    OLD_PREVIOUS="$(read_link_target "$PREVIOUS_LINK")"
}

publish_release() {
    if [[ -n "$OLD_CURRENT" ]]; then
        atomic_link "$OLD_CURRENT" "$PREVIOUS_LINK"
    fi
    atomic_link "$RELEASE_PATH" "$CURRENT_LINK"
}

restore_previous_links() {
    if [[ -n "$OLD_CURRENT" ]]; then
        atomic_link "$OLD_CURRENT" "$CURRENT_LINK"
    else
        rm -f -- "$CURRENT_LINK"
    fi
    if [[ -n "$OLD_PREVIOUS" ]]; then
        atomic_link "$OLD_PREVIOUS" "$PREVIOUS_LINK"
    else
        rm -f -- "$PREVIOUS_LINK"
    fi
}

page_marker_check() {
    local body_file="$1"
    grep -Fq '今天的班' "$body_file"
}

http_health_check() {
    local body_file="$TMP_ROOT/http.body"
    local status
    status="$(curl --silent --show-error --max-time 15 \
        --resolve "$DOMAIN:80:127.0.0.1" \
        --output "$body_file" \
        --write-out '%{http_code}' \
        "http://$DOMAIN$APP_PATH/")" || return 1

    if nginx_is_https; then
        [[ "$status" == "301" || "$status" == "308" ]]
    else
        [[ "$status" == "200" ]] && page_marker_check "$body_file"
    fi
}

https_health_check() {
    local body_file="$TMP_ROOT/https.body"
    local status
    status="$(curl --silent --show-error --fail --max-time 15 \
        --resolve "$DOMAIN:443:127.0.0.1" \
        --output "$body_file" \
        --write-out '%{http_code}' \
        "https://$DOMAIN$APP_PATH/")" || return 1
    [[ "$status" == "200" ]] && page_marker_check "$body_file"
}

public_api_health_check() {
    local status
    if nginx_is_https; then
        status="$(curl --silent --show-error --max-time 15 \
            --resolve "$DOMAIN:443:127.0.0.1" \
            --output /dev/null \
            --write-out '%{http_code}' \
            "https://$DOMAIN/api/fortune/status")" || return 1
    else
        status="$(curl --silent --show-error --max-time 15 \
            --resolve "$DOMAIN:80:127.0.0.1" \
            --output /dev/null \
            --write-out '%{http_code}' \
            "http://$DOMAIN/api/fortune/status")" || return 1
    fi
    [[ "$status" == "200" ]]
}

report_ai_configuration() {
    local response
    if nginx_is_https; then
        response="$(curl --silent --show-error --max-time 15 \
            --resolve "$DOMAIN:443:127.0.0.1" \
            "https://$DOMAIN/api/fortune/status" 2>/dev/null || true)"
    else
        response="$(curl --silent --show-error --max-time 15 \
            --resolve "$DOMAIN:80:127.0.0.1" \
            "http://$DOMAIN/api/fortune/status" 2>/dev/null || true)"
    fi
    if grep -Fq '"configured":true' <<< "$response"; then
        log "AI generation is configured"
    else
        log "WARNING: AI proxy is reachable, but HAYS_AI_API_KEY is not configured in $ENV_PATH" >&2
    fi
}

verify_site() {
    if ! http_health_check; then
        log "HTTP health check failed; expected the configured virtual host to serve the launch page" >&2
        return 1
    fi
    if nginx_is_https && ! https_health_check; then
        log "HTTPS health check failed; expected HTTP 200 containing 今天的班" >&2
        return 1
    fi
    if ! public_api_health_check; then
        log "API proxy health check failed; expected GET /api/fortune/status to return HTTP 200" >&2
        return 1
    fi
    report_ai_configuration
}

backup_config_for_certbot() {
    local backup="$TMP_ROOT/nginx.before-certbot.conf"
    cp -a "$CONFIG_PATH" "$backup"
    printf '%s\n' "$backup"
}

restore_config_backup() {
    local backup="$1"
    install -m 644 "$backup" "$CONFIG_PATH"
    nginx -t && systemctl reload nginx
}

enable_https() {
    local backup
    backup="$(backup_config_for_certbot)"
    log "configuring HTTPS with Certbot"
    if ! certbot --nginx \
        --non-interactive \
        --agree-tos \
        --keep-until-expiring \
        --redirect \
        --email "$CERTBOT_EMAIL" \
        -d "$DOMAIN"; then
        restore_config_backup "$backup" || true
        return 1
    fi
    if ! nginx -t; then
        restore_config_backup "$backup" || true
        return 1
    fi
    systemctl reload nginx
}

prune_releases() {
    local keep_additional=$((KEEP_RELEASES - 2))
    local kept=0
    local current_target previous_target release_name release_path
    current_target="$(read_link_target "$CURRENT_LINK")"
    previous_target="$(read_link_target "$PREVIOUS_LINK")"

    while IFS= read -r release_name; do
        [[ -n "$release_name" ]] || continue
        release_path="$RELEASES_DIR/$release_name"
        [[ "$release_path" == "$current_target" || "$release_path" == "$previous_target" ]] && continue
        if ((kept < keep_additional)); then
            kept=$((kept + 1))
        else
            rm -rf -- "$release_path"
        fi
    done < <(find "$RELEASES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -E '^[0-9]{14}-[0-9]+$' | sort -r)
}

rollback_release() {
    [[ -L "$CURRENT_LINK" && -L "$PREVIOUS_LINK" ]] \
        || die "no previous release is available for rollback"

    local current_target previous_target
    current_target="$(read_link_target "$CURRENT_LINK")"
    previous_target="$(read_link_target "$PREVIOUS_LINK")"
    [[ -d "$current_target" && -d "$previous_target" ]] \
        || die "current or previous release link is broken"

    atomic_link "$previous_target" "$CURRENT_LINK"
    atomic_link "$current_target" "$PREVIOUS_LINK"
    if ! restart_app_service || ! api_proxy_health_check || ! ensure_nginx_running || ! verify_site; then
        atomic_link "$current_target" "$CURRENT_LINK"
        atomic_link "$previous_target" "$PREVIOUS_LINK"
        restart_app_service || true
        ensure_nginx_running || true
        die "rollback health check failed; restored the pre-rollback release"
    fi
    log "rollback complete: $previous_target is now current"
}

deploy_release() {
    local checkout="$1"
    remember_current_links
    create_release "$checkout"
    install_nginx_config
    ensure_nginx_running
    publish_release
    install_app_service

    if ! restart_app_service || ! api_proxy_health_check || ! verify_site; then
        restore_previous_links
        rm -rf -- "$RELEASE_PATH"
        if [[ -n "$OLD_CURRENT" ]]; then
            restart_app_service || true
        else
            stop_app_service
        fi
        ensure_nginx_running || true
        die "deployment service or health check failed; restored the previous release"
    fi

    if ((ENABLE_HTTPS == 1)); then
        if ! enable_https || ! verify_site; then
            restore_previous_links
            rm -rf -- "$RELEASE_PATH"
            if [[ -n "$OLD_CURRENT" ]]; then
                restart_app_service || true
            else
                stop_app_service
            fi
            ensure_nginx_running || true
            die "HTTPS setup or verification failed; restored the previous release"
        fi
    fi

    prune_releases
    log "deployment complete: https://$DOMAIN$APP_PATH/"
}

main() {
    parse_args "$@"
    validate_inputs
    require_root
    require_ubuntu

    SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
    TMP_ROOT="$(mktemp -d -t "${SITE_NAME}.XXXXXX")"

    ensure_packages
    ensure_node_runtime
    detect_https_port_conflict
    ensure_https_packages
    prepare_directories

    if ((ROLLBACK == 1)); then
        install_app_service
        rollback_release
        exit 0
    fi

    resolve_repository
    local checkout
    checkout="$(clone_source)"
    deploy_release "$checkout"
}

main "$@"
