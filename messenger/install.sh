#!/usr/bin/env bash
# onepin 비공개 메신저 설치 스크립트 (Synapse + Element 웹)
# 사용법: sudo ./install.sh
# 여러 번 실행해도 안전합니다 (기존 데이터와 비밀값은 유지).
set -euo pipefail

cd "$(dirname "$0")"
DIR="$(pwd)"

info() { printf '\n\033[1;34m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "root 권한이 필요합니다: sudo ./install.sh"

# ── 1. 설정 파일 ──────────────────────────────────────────────
if [ ! -f .env ]; then
  cp .env.example .env
  info ".env 파일을 만들었습니다. 도메인·이름을 확인하고 다시 실행하세요:"
  echo "    nano $DIR/.env"
  exit 0
fi

set_secret() {  # 비어 있는 비밀값만 생성
  local key="$1"
  if ! grep -qE "^${key}=.+" .env; then
    local val; val="$(openssl rand -hex 32)"
    if grep -qE "^${key}=" .env; then
      sed -i "s|^${key}=.*|${key}=${val}|" .env
    else
      echo "${key}=${val}" >> .env
    fi
  fi
}

# ── 2. 필요한 프로그램 ─────────────────────────────────────────
install_pkgs() {
  if command -v apt-get >/dev/null; then
    apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
  elif command -v dnf >/dev/null; then dnf install -y -q "$@"
  elif command -v yum >/dev/null; then yum install -y -q "$@"
  else die "패키지 관리자를 찾을 수 없습니다. 설치 필요: $*"; fi
}

info "필요한 프로그램 확인"
command -v openssl  >/dev/null || install_pkgs openssl
command -v curl     >/dev/null || install_pkgs curl
command -v envsubst >/dev/null || { command -v apt-get >/dev/null && install_pkgs gettext-base || install_pkgs gettext; }

if ! command -v docker >/dev/null; then
  info "Docker 설치"
  curl -fsSL https://get.docker.com | sh
  systemctl enable --now docker
fi
docker compose version >/dev/null 2>&1 || die "docker compose 플러그인이 없습니다. Docker 를 최신 버전으로 업데이트하세요."

for k in POSTGRES_PASSWORD REGISTRATION_SHARED_SECRET MACAROON_SECRET_KEY FORM_SECRET; do set_secret "$k"; done
chmod 600 .env
set -a; . ./.env; set +a

for v in SERVER_NAME MATRIX_HOST CHAT_HOST BRAND ADMIN_EMAIL ADMIN_USER SYNAPSE_PORT ELEMENT_PORT MAX_UPLOAD_SIZE; do
  [ -n "${!v:-}" ] || die ".env 의 $v 값이 비어 있습니다."
done

VARS='${SERVER_NAME} ${MATRIX_HOST} ${CHAT_HOST} ${BRAND} ${SYNAPSE_PORT} ${ELEMENT_PORT} ${MAX_UPLOAD_SIZE} ${POSTGRES_PASSWORD} ${REGISTRATION_SHARED_SECRET} ${MACAROON_SECRET_KEY} ${FORM_SECRET}'
render() { envsubst "$VARS" < "$1" > "$2"; }

# ── 3. 포트 충돌 확인 ─────────────────────────────────────────
for p in "$SYNAPSE_PORT" "$ELEMENT_PORT"; do
  if ss -tln | awk '{print $4}' | grep -qE "[:.]${p}\$" && ! docker compose ps --status running -q 2>/dev/null | grep -q .; then
    die "포트 $p 를 이미 다른 프로그램이 쓰고 있습니다. .env 에서 SYNAPSE_PORT/ELEMENT_PORT 를 바꾸세요."
  fi
done

# ── 4. Synapse 설정 생성 ──────────────────────────────────────
info "메신저 서버(Synapse) 설정"
mkdir -p data/synapse data/postgres data/element
if [ ! -f "data/synapse/${SERVER_NAME}.signing.key" ]; then
  # 서명 키와 로그 설정을 공식 이미지로 생성
  docker compose run --rm \
    -e SYNAPSE_SERVER_NAME="$SERVER_NAME" -e SYNAPSE_REPORT_STATS=no \
    synapse generate
fi
render templates/homeserver.yaml data/synapse/homeserver.yaml
chown -R 991:991 data/synapse   # Synapse 컨테이너 사용자
chmod 600 data/synapse/homeserver.yaml

render templates/element-config.json data/element/config.json
render templates/well-known-client.json data/well-known-client.json

# ── 5. 실행 ──────────────────────────────────────────────────
info "컨테이너 실행"
docker compose pull -q
docker compose up -d

info "Synapse 시작 대기"
for i in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${SYNAPSE_PORT}/health" >/dev/null 2>&1 && break
  [ "$i" -eq 60 ] && die "Synapse 가 시작되지 않았습니다. 로그 확인: docker compose logs synapse"
  sleep 2
done
echo "Synapse 정상 동작"

# ── 6. 웹서버(Nginx/Apache) 연결 ──────────────────────────────
info "웹서버 연결"
WEB=""
if systemctl is-active --quiet nginx 2>/dev/null; then WEB=nginx
elif systemctl is-active --quiet apache2 2>/dev/null; then WEB=apache2
elif systemctl is-active --quiet httpd 2>/dev/null; then WEB=httpd
elif ! ss -tln | awk '{print $4}' | grep -qE '[:.]80$'; then
  info "웹서버가 없어서 Nginx 를 설치합니다"
  install_pkgs nginx
  systemctl enable --now nginx
  WEB=nginx
fi

case "$WEB" in
  nginx)
    CONF=/etc/nginx/conf.d/onepin-messenger.conf
    [ -d /etc/nginx/conf.d ] || die "/etc/nginx/conf.d 가 없습니다. templates/webserver/nginx.conf 를 수동으로 적용하세요."
    render templates/webserver/nginx.conf "$CONF"
    nginx -t || { rm -f "$CONF"; die "Nginx 설정 오류로 적용을 취소했습니다."; }
    systemctl reload nginx
    ;;
  apache2)
    a2enmod -q proxy proxy_http headers ssl
    CONF=/etc/apache2/sites-available/onepin-messenger.conf
    render templates/webserver/apache.conf "$CONF"
    a2ensite -q onepin-messenger
    apache2ctl configtest || { a2dissite -q onepin-messenger; die "Apache 설정 오류로 적용을 취소했습니다."; }
    systemctl reload apache2
    ;;
  httpd)
    CONF=/etc/httpd/conf.d/onepin-messenger.conf
    render templates/webserver/apache.conf "$CONF"
    apachectl configtest || { rm -f "$CONF"; die "Apache 설정 오류로 적용을 취소했습니다."; }
    systemctl reload httpd
    ;;
  *)
    die "80 포트를 쓰는 웹서버를 인식하지 못했습니다 (호스팅 패널 등). templates/webserver/ 의 설정을 수동으로 적용하세요."
    ;;
esac
echo "$WEB 에 ${MATRIX_HOST}, ${CHAT_HOST} 연결 완료"

# ── 7. HTTPS 인증서 ──────────────────────────────────────────
info "DNS 확인"
MY_IP="$(curl -fsS -4 -m 10 https://api.ipify.org 2>/dev/null || true)"
for h in "$MATRIX_HOST" "$CHAT_HOST"; do
  ip="$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}')"
  if [ -z "$ip" ]; then
    warn "$h 가 DNS 에 없습니다. Cloudflare 에 A 레코드를 추가하세요 (README 참고)."
  elif [ -n "$MY_IP" ] && [ "$ip" != "$MY_IP" ]; then
    warn "$h → $ip (이 서버: $MY_IP). Cloudflare 프록시(주황 구름)가 켜져 있으면 인증서 발급이 실패할 수 있습니다. 'DNS 전용'(회색 구름)으로 바꾸세요."
  else
    echo "$h → $ip OK"
  fi
done

info "HTTPS 인증서 발급 (Let's Encrypt)"
if ! command -v certbot >/dev/null; then
  if [ "$WEB" = nginx ]; then install_pkgs certbot python3-certbot-nginx
  else install_pkgs certbot python3-certbot-apache; fi
fi
CB_PLUGIN=--nginx; [ "$WEB" = nginx ] || CB_PLUGIN=--apache
if certbot "$CB_PLUGIN" --non-interactive --agree-tos --redirect -m "$ADMIN_EMAIL" \
     -d "$MATRIX_HOST" -d "$CHAT_HOST"; then
  echo "인증서 발급 완료"
else
  warn "인증서 발급 실패: DNS 에 ${MATRIX_HOST}, ${CHAT_HOST} 가 이 서버 IP 로 연결됐는지 확인 후 다시 실행하세요."
fi

# ── 8. 관리자 계정 ────────────────────────────────────────────
if [ ! -f data/.admin-created ]; then
  info "관리자 계정(@${ADMIN_USER}:${SERVER_NAME}) 만들기"
  if "$DIR/scripts/add-user.sh" "$ADMIN_USER" --admin; then
    touch data/.admin-created
  else
    warn "관리자 계정을 만들지 못했습니다. 나중에 실행: ./scripts/add-user.sh $ADMIN_USER --admin"
  fi
fi

# ── 완료 ─────────────────────────────────────────────────────
info "설치 완료"
cat <<MSG
  웹 채팅:     https://${CHAT_HOST}
  서버 주소:   https://${MATRIX_HOST}
  아이디 형식: @아이디:${SERVER_NAME}

  사용자 추가: sudo ./scripts/add-user.sh hong
  접속 QR 코드: sudo ./scripts/qr.sh

  ${SERVER_NAME} 에서 앱이 자동으로 서버를 찾게 하려면
  Cloudflare Worker 를 등록하세요: cloudflare/well-known-worker.js (README 참고)
  또는 아래 파일을 https://${SERVER_NAME}/.well-known/matrix/client 로 올리세요:
    $DIR/data/well-known-client.json
MSG
