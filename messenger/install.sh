#!/usr/bin/env bash
# onepin 비공개 메신저 설치 스크립트 (Synapse + Element 웹 + 푸시 알림 + 텔레그램 브릿지(선택))
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

set_default() {  # 예전 .env 에 없는 설정은 기본값으로 추가
  grep -qE "^${1}=" .env || echo "${1}=${2}" >> .env
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

for k in POSTGRES_PASSWORD REGISTRATION_SHARED_SECRET MACAROON_SECRET_KEY FORM_SECRET LK_AS_TOKEN LK_HS_TOKEN LK_SECRET; do set_secret "$k"; done
# LiveKit API 키는 접두사가 있어야 한다
if ! grep -qE '^LK_KEY=.+' .env; then
  if grep -qE '^LK_KEY=' .env; then sed -i "s|^LK_KEY=.*|LK_KEY=API$(openssl rand -hex 6)|" .env
  else echo "LK_KEY=API$(openssl rand -hex 6)" >> .env; fi
fi
set_default PUSH_APP_ID net.onepin.push
set_default PUSH_SUBNET 10.250.250.0/29
set_default SYGNAL_IP 10.250.250.4
set_default ADMIN_PORT 8090
set_default JWT_PORT 8070
set_default CALL_PORT 8092
set_default LK_JWT_IP 10.250.250.5
set_default LK_UDP_START 50100
set_default LK_UDP_END 50200
set_default CALL_HOST "call.${SERVER_NAME:-example.com}"
# 통화 미디어가 들어올 공인 IP. 비어 있으면 자동으로 알아낸다.
grep -qE '^NODE_IP=.+' .env || sed -i "s|^NODE_IP=.*|NODE_IP=$(curl -s --max-time 8 https://ifconfig.me || hostname -I | awk '{print $1}')|" .env
grep -qE '^NODE_IP=' .env || echo "NODE_IP=$(curl -s --max-time 8 https://ifconfig.me || hostname -I | awk '{print $1}')" >> .env
set_default TELEGRAM_BRIDGE off
set_default TELEGRAM_PUPPETING off
chmod 600 .env
set -a; . ./.env; set +a

for v in SERVER_NAME MATRIX_HOST CHAT_HOST CALL_HOST BRAND ADMIN_EMAIL ADMIN_USER SYNAPSE_PORT ELEMENT_PORT ADMIN_PORT JWT_PORT CALL_PORT MAX_UPLOAD_SIZE PUSH_APP_ID PUSH_SUBNET SYGNAL_IP LK_KEY LK_SECRET LK_AS_TOKEN LK_HS_TOKEN LK_JWT_IP LK_UDP_START LK_UDP_END NODE_IP; do
  [ -n "${!v:-}" ] || die ".env 의 $v 값이 비어 있습니다."
done

VARS='${SERVER_NAME} ${MATRIX_HOST} ${CHAT_HOST} ${CALL_HOST} ${BRAND} ${ADMIN_EMAIL} ${SYNAPSE_PORT} ${ELEMENT_PORT} ${ADMIN_PORT} ${JWT_PORT} ${CALL_PORT} ${MAX_UPLOAD_SIZE} ${POSTGRES_PASSWORD} ${REGISTRATION_SHARED_SECRET} ${MACAROON_SECRET_KEY} ${FORM_SECRET} ${CERT_DIR} ${WELLKNOWN_DIR} ${PUSH_APP_ID} ${SYGNAL_IP} ${VAPID_PUBLIC_KEY} ${LK_KEY} ${LK_SECRET} ${LK_AS_TOKEN} ${LK_HS_TOKEN} ${LK_JWT_IP} ${LK_UDP_START} ${LK_UDP_END} ${NODE_IP}'
WELLKNOWN_DIR="$DIR/data/well-known"; export WELLKNOWN_DIR
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
HS_BEFORE="$(sha256sum data/synapse/homeserver.yaml 2>/dev/null || true)"
render templates/homeserver.yaml data/synapse/homeserver.yaml

# ── 4-0. 텔레그램 브릿지 (선택) ────────────────────────────────
set_env() {  # .env 값 바꾸기/추가
  if grep -qE "^${1}=" .env; then sed -i "s|^${1}=.*|${1}=${2}|" .env; else echo "${1}=${2}" >> .env; fi
}
if [ "${TELEGRAM_BRIDGE:-off}" = on ]; then
  info "텔레그램 브릿지 설정"
  for v in TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_BOT_TOKEN; do
    [ -n "${!v:-}" ] || die ".env 의 $v 값이 비어 있습니다 (README '텔레그램 브릿지' 참고)."
  done
  [[ "$TELEGRAM_API_ID" =~ ^[0-9]+$ ]] || die "TELEGRAM_API_ID 는 숫자여야 합니다."
  set_env COMPOSE_PROFILES telegram
  export COMPOSE_PROFILES=telegram
  mkdir -p data/telegram data/synapse/appservices

  # 브릿지 전용 DB (같은 PostgreSQL 안의 telegram DB)
  docker compose up -d --wait postgres
  docker compose exec -T postgres psql -U synapse -d synapse -tAc \
    "SELECT 1 FROM pg_database WHERE datname='telegram'" | grep -q 1 \
    || docker compose exec -T postgres psql -U synapse -d synapse -c "CREATE DATABASE telegram" >/dev/null

  # 첫 실행: 공식 이미지가 예제 설정을 만들고 종료합니다
  [ -f data/telegram/config.yaml ] || docker compose run --rm --no-deps mautrix-telegram >/dev/null 2>&1 || true
  [ -f data/telegram/config.yaml ] || die "브릿지 설정 파일을 만들지 못했습니다: docker compose run --rm --no-deps mautrix-telegram"

  docker compose run --rm --no-deps -T --entrypoint python3 \
    -e SERVER_NAME -e ADMIN_USER -e POSTGRES_PASSWORD -e TELEGRAM_PUPPETING \
    -e TELEGRAM_API_ID -e TELEGRAM_API_HASH -e TELEGRAM_BOT_TOKEN \
    mautrix-telegram - < templates/telegram/configure.py

  # 두 번째 실행: Synapse 등록 파일(registration.yaml)을 만들고 종료합니다
  [ -f data/telegram/registration.yaml ] || docker compose run --rm --no-deps mautrix-telegram >/dev/null 2>&1 || true
  [ -f data/telegram/registration.yaml ] || die "브릿지 등록 파일을 만들지 못했습니다: docker compose logs mautrix-telegram"

  cp data/telegram/registration.yaml data/synapse/appservices/telegram.yaml
  # 기존 앱서비스 목록(통화용 livekit 등)에 항목만 추가. 같은 키를 또 쓰면 앞의 목록이 사라진다
  if grep -q '^app_service_config_files:' data/synapse/homeserver.yaml; then
    sed -i '/^app_service_config_files:/a\  - /data/appservices/telegram.yaml' data/synapse/homeserver.yaml
  else
    printf '\napp_service_config_files:\n  - /data/appservices/telegram.yaml\n' >> data/synapse/homeserver.yaml
  fi
  echo "텔레그램 브릿지 연결 완료"
else
  if grep -qE '^COMPOSE_PROFILES=.*telegram' .env; then
    info "텔레그램 브릿지 끄기"
    docker compose stop mautrix-telegram >/dev/null 2>&1 || true
    set_env COMPOSE_PROFILES ""
  fi
  export COMPOSE_PROFILES=
fi

chown -R 991:991 data/synapse   # Synapse 컨테이너 사용자
chmod 600 data/synapse/homeserver.yaml
HS_AFTER="$(sha256sum data/synapse/homeserver.yaml)"

render templates/element-config.json data/element/config.json
render templates/well-known-client.json data/well-known-client.json
render templates/admin-config.json data/admin-config.json

# ── 4-2. 통화(음성·영상) ──────────────────────────────────────
info "통화 설정"
mkdir -p data/livekit data/element-call "$WELLKNOWN_DIR"
render templates/livekit.yaml            data/livekit/livekit.yaml
render templates/element-call-config.json data/element-call/config.json
render templates/well-known-server.json   "$WELLKNOWN_DIR/server"
render templates/livekit-appservice.yaml  data/synapse/livekit-appservice.yaml
# Synapse 가 읽어야 하므로 소유자를 맞춘다. root 소유 600 이면 Synapse 가 기동에 실패한다.
chown 991:991 data/synapse/livekit-appservice.yaml
chmod 640 data/synapse/livekit-appservice.yaml
chmod 600 data/livekit/livekit.yaml

# 통화 미디어용 포트 열기 (UDP 범위 + TCP 대체 통로)
open_port() {  # 프로토콜 포트
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "$2/$1" >/dev/null 2>&1
  elif command -v iptables >/dev/null; then
    local chain=INPUT
    iptables -L RH-Firewall-1-INPUT -n >/dev/null 2>&1 && chain=RH-Firewall-1-INPUT
    iptables -C "$chain" -p "$1" -m state --state NEW -m "$1" --dport "$2" -j ACCEPT 2>/dev/null && return
    # REJECT/DROP 규칙 "앞"에 넣어야 한다. iptables -S 의 줄번호는 -N 줄 때문에 어긋나므로
    # --line-numbers 로 실제 위치를 구한다.
    local n; n=$(iptables -L "$chain" --line-numbers -n | awk '$2=="REJECT"||$2=="DROP"{print $1; exit}')
    if [ -n "$n" ]; then iptables -I "$chain" "$n" -p "$1" -m state --state NEW -m "$1" --dport "$2" -j ACCEPT
    else iptables -A "$chain" -p "$1" -m state --state NEW -m "$1" --dport "$2" -j ACCEPT; fi
  fi
}
open_port udp "${LK_UDP_START}:${LK_UDP_END}"
open_port tcp 7881
command -v netfilter-persistent >/dev/null && netfilter-persistent save >/dev/null 2>&1 || \
  { [ -d /etc/iptables ] && iptables-save > /etc/iptables/rules.v4 2>/dev/null; } || true

# ── 4-1. 푸시 알림 (Sygnal + 알림 켜기 페이지 /push/) ──────────
info "푸시 알림 설정"
mkdir -p data/sygnal data/push
VAPID_KEY=data/sygnal/vapid_private.pem
if [ ! -s "$VAPID_KEY" ]; then
  # 웹 푸시 서명 키 (P-256). 바꾸면 모든 기기에서 알림을 다시 켜야 합니다
  ( umask 077; openssl ecparam -name prime256v1 -genkey -noout -out "$VAPID_KEY" )
fi
chmod 600 "$VAPID_KEY"
VAPID_PUBLIC_KEY="$(openssl ec -in "$VAPID_KEY" -pubout -outform DER 2>/dev/null | tail -c 65 | base64 -w0 | tr '+/' '-_' | tr -d '=')"
[ ${#VAPID_PUBLIC_KEY} -eq 87 ] || die "VAPID 공개키를 만들지 못했습니다 ($VAPID_KEY 확인)."
export VAPID_PUBLIC_KEY
render templates/sygnal.yaml data/sygnal/sygnal.yaml
chmod 600 data/sygnal/sygnal.yaml
for f in index.html manifest.json config.json; do render "templates/push/$f" "data/push/$f"; done
cp templates/push/app.js templates/push/sw.js data/push/

# ── 5. 실행 ──────────────────────────────────────────────────
info "컨테이너 실행"
docker compose pull -q || warn "이미지 업데이트를 받지 못했습니다 (Docker Hub 제한 등). 이미 받은 이미지로 계속합니다."

# 서버에서 IPv6 가 꺼져 있으면 Element 웹(nginx, [::]:80)과 관리자 화면(static-web-server, [::]:8080)이
# 주소를 열지 못해 계속 재시작됨 → IPv4 만 쓰도록 덮어쓰기 (docker-compose.override.yml 은 자동으로 읽힘)
if [ ! -e /proc/net/if_inet6 ]; then
  warn "이 서버는 IPv6 가 꺼져 있어 채팅·관리자 화면을 IPv4 전용으로 실행합니다."
  docker run --rm --entrypoint cat vectorim/element-web:latest /etc/nginx/templates/default.conf.template \
    | sed '/listen[[:space:]]*\[::\]/d' > data/element/default.conf.template
  cat > docker-compose.override.yml <<'OVR'
# install.sh 가 생성 (서버 IPv6 꺼짐): 웹 화면들을 IPv4 전용으로 실행
services:
  element:
    volumes:
      - ./data/element/default.conf.template:/etc/nginx/templates/default.conf.template:ro
  admin:
    environment:
      SERVER_HOST: 0.0.0.0
OVR
else
  rm -f docker-compose.override.yml data/element/default.conf.template
fi

docker compose up -d --remove-orphans
# 설정이 바뀌었으면 Synapse 재시작 (처음 설치 때는 불필요)
if [ -n "$HS_BEFORE" ] && [ "$HS_BEFORE" != "$HS_AFTER" ]; then
  docker compose restart synapse
fi

# 모든 컨테이너가 떠 있는지 확인 (재시작 반복 감지)
sleep 5
for svc in postgres synapse sygnal element admin livekit lk-jwt element-call; do
  docker compose ps --status running -q "$svc" | grep -q . \
    || warn "$svc 컨테이너가 실행 중이 아닙니다: docker compose logs $svc"
done

info "Synapse 시작 대기"
for i in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${SYNAPSE_PORT}/health" >/dev/null 2>&1 && break
  [ "$i" -eq 60 ] && die "Synapse 가 시작되지 않았습니다. 로그 확인: docker compose logs synapse"
  sleep 2
done
echo "Synapse 정상 동작"

# 홈 화면 아이콘: 로고(SVG)를 PNG 로 변환, 안 되면 Element 기본 아이콘 사용
make_icon() {  # 크기 출력파일
  if command -v rsvg-convert >/dev/null || install_pkgs librsvg2-bin >/dev/null 2>&1 || install_pkgs librsvg2-tools >/dev/null 2>&1; then
    rsvg-convert -w "$1" -h "$1" -b white element/custom/logo.svg -o "$2" 2>/dev/null && return 0
  fi
  curl -fsS "http://127.0.0.1:${ELEMENT_PORT}/vector-icons/$1.png" -o "$2" 2>/dev/null
}
for sz in 180 512; do
  [ -s "data/push/icon-$sz.png" ] && [ "data/push/icon-$sz.png" -nt element/custom/logo.svg ] && continue
  make_icon "$sz" "data/push/icon-$sz.png" || warn "홈 화면 아이콘(icon-$sz.png)을 만들지 못했습니다."
done
if [ "${TELEGRAM_BRIDGE:-off}" = on ]; then
  sleep 5
  docker compose ps --status running mautrix-telegram -q | grep -q . \
    || warn "텔레그램 브릿지가 실행되지 않았습니다: docker compose logs mautrix-telegram"
fi

# ── 6. 웹서버(Nginx/Apache) 연결 ──────────────────────────────
# 인증서: certs/origin.pem + certs/origin.key (Cloudflare 원본 인증서) 가 있으면 그것을 사용,
#         없으면 Let's Encrypt 로 발급 (7단계)
CERT_DIR="$DIR/certs"
if [ -s "$CERT_DIR/origin.pem" ] && [ -s "$CERT_DIR/origin.key" ]; then
  CERT_MODE=cloudflare
  chmod 600 "$CERT_DIR/origin.key"
  SUFFIX=-ssl
  info "Cloudflare 원본 인증서 사용 ($CERT_DIR)"
else
  CERT_MODE=letsencrypt
  SUFFIX=
  warn "certs/origin.pem, certs/origin.key 가 없어 Let's Encrypt 로 발급합니다 (README 'Cloudflare 인증서' 참고)."
fi
export CERT_DIR

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
    render "templates/webserver/nginx${SUFFIX}.conf" "$CONF"
    nginx -t || { rm -f "$CONF"; die "Nginx 설정 오류로 적용을 취소했습니다."; }
    systemctl reload nginx
    ;;
  apache2)
    a2enmod -q proxy proxy_http proxy_wstunnel headers ssl rewrite   # wstunnel: 통화 신호(웹소켓)
    CONF=/etc/apache2/sites-available/onepin-messenger.conf
    render "templates/webserver/apache${SUFFIX}.conf" "$CONF"
    a2ensite -q onepin-messenger
    apache2ctl configtest || { a2dissite -q onepin-messenger; die "Apache 설정 오류로 적용을 취소했습니다."; }
    systemctl reload apache2
    ;;
  httpd)
    [ "$CERT_MODE" = cloudflare ] && { rpm -q mod_ssl >/dev/null 2>&1 || install_pkgs mod_ssl; }
    CONF=/etc/httpd/conf.d/onepin-messenger.conf
    render "templates/webserver/apache${SUFFIX}.conf" "$CONF"
    apachectl configtest || { rm -f "$CONF"; die "Apache 설정 오류로 적용을 취소했습니다."; }
    systemctl reload httpd
    ;;
  *)
    die "80 포트를 쓰는 웹서버를 인식하지 못했습니다 (호스팅 패널 등). templates/webserver/ 의 설정을 수동으로 적용하세요."
    ;;
esac
echo "$WEB 에 ${MATRIX_HOST}, ${CHAT_HOST} 연결 완료"

# ── 7. HTTPS 인증서 (Let's Encrypt, 원본 인증서가 없을 때만) ─────
if [ "$CERT_MODE" = cloudflare ]; then
  info "인증서: Cloudflare 원본 인증서 적용 완료 (SSL/TLS 모드를 Full (strict) 로 설정하세요)"
else
# CF_API_TOKEN 이 있으면 Cloudflare DNS 인증 → 주황 구름(프록시)·와일드카드 레코드에서도 발급됨
# 없으면 HTTP 인증 → matrix/chat 레코드가 회색 구름(DNS only)이어야 함
info "DNS 확인"
MY_IP="$(curl -fsS -4 -m 10 https://api.ipify.org 2>/dev/null || true)"
for h in "$MATRIX_HOST" "$CHAT_HOST"; do
  ip="$(getent ahostsv4 "$h" 2>/dev/null | awk 'NR==1{print $1}')"
  if [ -z "$ip" ]; then
    warn "$h 가 DNS 에 없습니다. Cloudflare 에 A 레코드를 추가하세요 (README 참고)."
  elif [ -n "$MY_IP" ] && [ "$ip" != "$MY_IP" ]; then
    if [ -n "${CF_API_TOKEN:-}" ]; then
      echo "$h → $ip (Cloudflare 프록시 경유, 원본 서버가 이 서버($MY_IP)인지 Cloudflare 에서 확인하세요)"
    else
      warn "$h → $ip (이 서버: $MY_IP). Cloudflare 프록시(주황 구름)면 .env 에 CF_API_TOKEN 을 넣거나 회색 구름으로 바꾸세요."
    fi
  else
    echo "$h → $ip OK"
  fi
done

info "HTTPS 인증서 발급 (Let's Encrypt)"
CB_INSTALLER=nginx; [ "$WEB" = nginx ] || CB_INSTALLER=apache
if [ -n "${CF_API_TOKEN:-}" ]; then
  install_pkgs certbot "python3-certbot-$CB_INSTALLER" python3-certbot-dns-cloudflare
  CF_INI=/etc/letsencrypt/onepin-cloudflare.ini
  mkdir -p /etc/letsencrypt
  ( umask 077; echo "dns_cloudflare_api_token = ${CF_API_TOKEN}" > "$CF_INI" )
  CB_AUTH=(--authenticator dns-cloudflare --dns-cloudflare-credentials "$CF_INI" --dns-cloudflare-propagation-seconds 30)
else
  install_pkgs certbot "python3-certbot-$CB_INSTALLER"
  CB_AUTH=(--authenticator "$CB_INSTALLER")
fi
if [ "${SKIP_CERTBOT:-0}" = 1 ]; then
  warn "SKIP_CERTBOT=1 — 인증서 발급을 건너뜁니다 (Cloudflare 가 HTTPS 를 처리하는 구성)"
elif certbot "${CB_AUTH[@]}" --installer "$CB_INSTALLER" --non-interactive --agree-tos --redirect \
     -m "$ADMIN_EMAIL" -d "$MATRIX_HOST" -d "$CHAT_HOST" -d "$CALL_HOST"; then
  echo "인증서 발급 완료"
  [ -n "${CF_API_TOKEN:-}" ] && echo "Cloudflare SSL/TLS 모드를 'Full (strict)' 로 설정하세요 (Flexible 이면 무한 리디렉션)."
else
  warn "인증서 발급 실패: README 의 'Cloudflare DNS 설정' 을 확인 후 다시 실행하세요."
fi
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
  알림 켜기:   https://${CHAT_HOST}/push/   (휴대폰에서 열어 홈 화면에 추가)
  서버 주소:   https://${MATRIX_HOST}
  아이디 형식: @아이디:${SERVER_NAME}

  텔레그램 브릿지: ${TELEGRAM_BRIDGE:-off}  (사용법: README "텔레그램 브릿지")
  사용자 추가: sudo ./scripts/add-user.sh hong
  접속 QR 코드: sudo ./scripts/qr.sh

  ${SERVER_NAME} 에서 앱이 자동으로 서버를 찾게 하려면
  Cloudflare Worker 를 등록하세요: cloudflare/well-known-worker.js (README 참고)
  또는 아래 파일을 https://${SERVER_NAME}/.well-known/matrix/client 로 올리세요:
    $DIR/data/well-known-client.json
MSG
