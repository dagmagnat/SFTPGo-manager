#!/usr/bin/env bash
# SFTPGo + Caddy installer for a fresh Ubuntu 24.04 VPS.
# Run: sudo bash install-e-cloudfiles.sh
set -Eeuo pipefail
umask 077

DOMAIN=e-cloudfiles.ru
EXPECTED_IP="${EXPECTED_IP:-}"
APP_DIR=/opt/e-cloudfiles
SFTPGO_IMAGE=drakkan/sftpgo:v2.7.5
CADDY_IMAGE=caddy:2.11.4-alpine
scratch=""

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
valid_ipv4() {
  local octet
  local -a octets
  [[ "$1" != *$'\n'* && "$1" != *$'\r'* ]] || return 1
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  IFS=. read -r -a octets <<< "$1"
  for octet in "${octets[@]}"; do
    ((10#$octet <= 255)) || return 1
  done
}
cleanup() {
  if [[ -n "$scratch" && -d "$scratch" ]]; then
    rm -f -- "$scratch"/*
    rmdir -- "$scratch"
  fi
}
trap cleanup EXIT
trap 'printf "\nInstallation stopped at line %s. Existing data was not removed.\n" "$LINENO" >&2' ERR

[[ "$EUID" == 0 ]] || die 'Run with sudo bash install-e-cloudfiles.sh'
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu && "${VERSION_ID:-}" == 24.04 ]] || die 'This installer requires Ubuntu 24.04.'
[[ ! -e "$APP_DIR" && ! -L "$APP_DIR" ]] || die "$APP_DIR already exists. Do not overwrite an existing installation."
command -v ss >/dev/null || die 'Install iproute2 first.'
busy="$(ss -H -ltn '( sport = :80 or sport = :443 or sport = :18080 )')"
[[ -z "$busy" ]] || die "Ports 80, 443 or 18080 are already in use. Keep the current service; integration is needed first.\n$busy"

if [[ -z "$EXPECTED_IP" ]]; then
  read -r -p 'Enter the public IPv4 address of this VPS: ' EXPECTED_IP || die 'An IPv4 address is required. Run interactively or set EXPECTED_IP.'
fi
valid_ipv4 "$EXPECTED_IP" || die 'Invalid IPv4 address. Enter four numbers from 0 to 255 separated by dots.'

printf '\nInstalling prerequisites...\n'
apt-get update
apt-get install -y ca-certificates curl openssl dnsutils jq

printf '\nChecking DNS for %s...\n' "$DOMAIN"
addresses="$(dig +short A "$DOMAIN" | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/')"
[[ "$addresses" == "$EXPECTED_IP" ]] || die "Set the only A record for $DOMAIN to $EXPECTED_IP (DNS only), then retry. Current IPv4: ${addresses:-none}"
ipv6="$(dig +short AAAA "$DOMAIN" | awk '/:/')"
[[ -z "$ipv6" ]] || die "An AAAA record exists for $DOMAIN. This IPv4 installer requires no AAAA record; review DNS before retrying."

if command -v docker >/dev/null; then
  docker compose version >/dev/null 2>&1 || die 'Docker exists but Compose v2 is missing. Install its matching Compose plugin first.'
else
  for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
      die "Existing package $package requires a manual Docker compatibility check. Nothing was removed."
    fi
  done
  [[ ! -e /etc/apt/sources.list.d/docker.sources && ! -e /etc/apt/sources.list.d/docker.list ]] || die 'An existing Docker apt source needs review first.'
  install -m 0755 -d /etc/apt/keyrings
  curl -fsS https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
  cat > /etc/apt/sources.list.d/docker.sources <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER
  chmod 0644 /etc/apt/sources.list.d/docker.sources
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
docker info >/dev/null

install -d -m 0700 "$APP_DIR"
install -d -m 0750 -o 1000 -g 1000 "$APP_DIR/storage" "$APP_DIR/state"
install -d -m 0750 -o 1000 -g 1000 "$APP_DIR/storage/data" "$APP_DIR/storage/data/shared"
for folder in Documents PDF Presentations Other; do
  install -d -m 0750 -o 1000 -g 1000 "$APP_DIR/storage/data/shared/$folder"
done
scratch="$(mktemp -d)"
admin_password="$(openssl rand -hex 20)"
owner_password="$(openssl rand -hex 20)"
reader_password="$(openssl rand -hex 20)"
cat > "$APP_DIR/.env" <<EOF_ENV
SFTPGO_IMAGE=$SFTPGO_IMAGE
CADDY_IMAGE=$CADDY_IMAGE
ADMIN_PASSWORD=$admin_password
EOF_ENV

cat > "$APP_DIR/compose.yaml" <<'EOF_COMPOSE'
name: e-cloudfiles
services:
  sftpgo:
    image: ${SFTPGO_IMAGE}
    restart: unless-stopped
    stop_grace_period: 40s
    ports:
      - "127.0.0.1:18080:8080"
    environment:
      SFTPGO_DATA_PROVIDER__CREATE_DEFAULT_ADMIN: "true"
      SFTPGO_DEFAULT_ADMIN_USERNAME: "admin"
      SFTPGO_DEFAULT_ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      SFTPGO_HTTPD__BINDINGS__0__PORT: "8080"
      SFTPGO_HTTPD__BINDINGS__0__ADDRESS: "0.0.0.0"
      SFTPGO_HTTPD__BINDINGS__0__ENABLE_WEB_ADMIN: "true"
      SFTPGO_HTTPD__BINDINGS__0__ENABLE_WEB_CLIENT: "true"
      SFTPGO_HTTPD__BINDINGS__0__PROXY_ALLOWED: "172.16.0.0/12,10.0.0.0/8,192.168.0.0/16"
      SFTPGO_HTTPD__BINDINGS__0__CLIENT_IP_PROXY_HEADER: "X-Real-IP"
      SFTPGO_SFTPD__BINDINGS__0__PORT: "0"
      SFTPGO_GRACE_TIME: "30"
    volumes:
      - ./storage:/srv/sftpgo
      - ./state:/var/lib/sftpgo
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
  caddy:
    image: ${CADDY_IMAGE}
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy-data:/data
      - ./caddy-config:/config
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF_COMPOSE

cat > "$APP_DIR/Caddyfile" <<EOF_CADDY
$DOMAIN {
    redir / /web/client/ 302
    reverse_proxy sftpgo:8080 {
        header_up X-Real-IP {remote_host}
    }
}
EOF_CADDY
chmod 0644 "$APP_DIR/Caddyfile"
cat > "$APP_DIR/credentials.txt" <<EOF_CREDENTIALS
Admin panel: https://$DOMAIN/web/admin/
Username: admin
Password: $admin_password

File manager: https://$DOMAIN/web/client/
Username: owner
Password: $owner_password
Permissions: upload, download, rename, delete and manage files in shared folder.

File manager: https://$DOMAIN/web/client/
Username: reader
Password: $reader_password
Permissions: list and download only; public shares disabled.

Passwords in this file are initial values. Changing them in the UI does not update this file.
EOF_CREDENTIALS
chmod 0600 "$APP_DIR/.env" "$APP_DIR/credentials.txt"

cd "$APP_DIR"
docker compose config --quiet
docker compose pull
docker compose run --rm --no-deps caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
# Bootstrap admin and users before exposing the HTTPS endpoint.
docker compose up -d sftpgo
printf 'user = "admin:%s"\n' "$admin_password" > "$scratch/admin.curl"
token=""
for ((attempt=0; attempt<60; attempt++)); do
  if curl --silent --fail --connect-timeout 2 --max-time 5 --config "$scratch/admin.curl" \
    http://127.0.0.1:18080/api/v2/token > "$scratch/token.json"; then
    token="$(jq -er '.access_token' "$scratch/token.json")"
    break
  fi
  sleep 2
done
[[ -n "$token" ]] || die "SFTPGo did not become ready. Check: cd $APP_DIR && docker compose logs --tail=80 sftpgo"
printf 'header = "Authorization: Bearer %s"\n' "$token" > "$scratch/api.curl"

cat > "$scratch/owner.json" <<EOF_OWNER
{"status":1,"username":"owner","password":"$owner_password","home_dir":"/srv/sftpgo/data/shared","permissions":{"/":["*"]},"filesystem":{"provider":0}}
EOF_OWNER
cat > "$scratch/reader.json" <<EOF_READER
{"status":1,"username":"reader","password":"$reader_password","home_dir":"/srv/sftpgo/data/shared","permissions":{"/":["list","download"]},"filesystem":{"provider":0},"filters":{"web_client":["shares-disabled"]}}
EOF_READER
for username in owner reader; do
  curl --silent --show-error --fail --max-time 15 --config "$scratch/api.curl" \
    -H 'Content-Type: application/json' --data-binary "@$scratch/$username.json" \
    http://127.0.0.1:18080/api/v2/users --output /dev/null
done
curl --silent --show-error --fail --max-time 15 --config "$scratch/api.curl" \
  http://127.0.0.1:18080/api/v2/users/reader > "$scratch/reader-saved.json"
jq -e '.permissions["/"] == ["list","download"] and (.filters.web_client | index("shares-disabled") != null)' \
  "$scratch/reader-saved.json" >/dev/null
docker compose up -d caddy

printf '\nWaiting for HTTPS certificate (ports 80/443 must be open at the provider)...\n'
https_ready=0
for ((attempt=0; attempt<30; attempt++)); do
  if curl --silent --fail --connect-timeout 3 --max-time 6 \
    --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/healthz" >/dev/null; then
    https_ready=1
    break
  fi
  sleep 2
done
printf '\nAccounts created. Credentials:\n\n'
cat "$APP_DIR/credentials.txt"
printf '\nFiles on the VPS: %s/storage/data/shared\n' "$APP_DIR"
printf 'Recover initial credentials: sudo cat %s/credentials.txt\n' "$APP_DIR"
if [[ "$https_ready" == 1 ]]; then
  printf '\nHTTPS health check PASSED. Now test upload as owner and download as reader.\n'
else
  printf '\nHTTPS is not ready. Do not enter passwords over plain HTTP.\n'
  printf 'Check DNS and provider firewall, then run: cd %s && docker compose logs --tail=80 caddy\n' "$APP_DIR"
  exit 2
fi
