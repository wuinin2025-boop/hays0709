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
readonly TEMPLATE_FILE_NAME="deploy/nginx.conf.template"

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
    [[ "$major_version" =~ ^[0-9]+$ && major_version -ge 22 ]] \
        || die "Ubuntu 22.04 or newer is required (detected: ${VERSION_ID:-unknown})"
}

ensure_packages() {
    local required=(git nginx rsync curl)
    if ((ENABLE_HTTPS == 1)); then
        required+=(certbot python3-certbot-nginx)
    fi

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
    command -v systemctl >/dev/null || die "systemd/systemctl is required"
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

install_nginx_config() {
    if [[ -e "$CONFIG_PATH" || -L "$CONFIG_PATH" ]]; then
        grep -Fq "# hays0709 managed configuration" "$CONFIG_PATH" \
            || die "$CONFIG_PATH exists but is not managed by this deployment"
        grep -Eq "server_name[[:space:]]+[^;]*${DOMAIN}([[:space:]]|;)" "$CONFIG_PATH" \
            || die "$CONFIG_PATH has a different server_name; resolve it manually before deploying"
        [[ -L "$ENABLED_LINK" || -e "$ENABLED_LINK" ]] || ln -s "$CONFIG_PATH" "$ENABLED_LINK"
        return
    fi

    local candidate="$TMP_ROOT/nginx.conf.candidate"
    render_nginx_config > "$candidate"
    install -m 644 "$candidate" "$CONFIG_PATH"
    ln -s "$CONFIG_PATH" "$ENABLED_LINK"

    if ! nginx -t; then
        rm -f -- "$ENABLED_LINK" "$CONFIG_PATH"
        die "generated Nginx configuration failed validation"
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
        --include='assets/***' \
        --exclude='*' \
        "$checkout/" "$RELEASE_PATH/"

    [[ -f "$RELEASE_PATH/$INDEX_FILE" ]] || die "release is missing $INDEX_FILE after rsync"
    [[ -d "$RELEASE_PATH/assets" ]] || die "release is missing assets/ after rsync"
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
        "http://$DOMAIN/")" || return 1

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
        "https://$DOMAIN/")" || return 1
    [[ "$status" == "200" ]] && page_marker_check "$body_file"
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
    if ! ensure_nginx_running || ! verify_site; then
        atomic_link "$current_target" "$CURRENT_LINK"
        atomic_link "$previous_target" "$PREVIOUS_LINK"
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

    if ! verify_site; then
        restore_previous_links
        rm -rf -- "$RELEASE_PATH"
        ensure_nginx_running || true
        die "deployment health check failed; restored the previous release"
    fi

    if ((ENABLE_HTTPS == 1)); then
        if ! enable_https || ! verify_site; then
            restore_previous_links
            rm -rf -- "$RELEASE_PATH"
            ensure_nginx_running || true
            die "HTTPS setup or verification failed; restored the previous release"
        fi
    fi

    prune_releases
    log "deployment complete: https://$DOMAIN/"
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
    prepare_directories

    if ((ROLLBACK == 1)); then
        rollback_release
        exit 0
    fi

    resolve_repository
    local checkout
    checkout="$(clone_source)"
    deploy_release "$checkout"
}

main "$@"
