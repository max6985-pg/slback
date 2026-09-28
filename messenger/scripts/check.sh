#!/usr/bin/env bash
# 설치 상태 점검: sudo ./scripts/check.sh
# 컨테이너·내부 연결·외부 주소·인증서·푸시를 확인하고 문제가 있으면 해결 방법을 알려 줍니다.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

[ -f .env ] || { echo "✖ .env 가 없습니다. 먼저 sudo ./install.sh 를 실행하세요."; exit 1; }
set -a; . ./.env; set +a

FAIL=0
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✖\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '      → %s\n' "$2"; FAIL=$((FAIL+1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }
http_code() { curl -s -o /dev/null -m 10 -w '%{http_code}' "$@" 2>/dev/null; }

head_ "1. 컨테이너"
for svc in postgres synapse sygnal element admin livekit lk-jwt element-call; do
  if docker compose ps --status running -q "$svc" 2>/dev/null | grep -q .; then ok "$svc 실행 중"
  else bad "$svc 가 실행 중이 아닙니다" "docker compose logs --tail 30 $svc 결과를 확인하세요"; fi
done

head_ "2. 서버 내부 연결"
[ "$(http_code "http://127.0.0.1:${SYNAPSE_PORT}/health")" = 200 ] && ok "Synapse 응답" \
  || bad "Synapse 가 응답하지 않습니다 (127.0.0.1:${SYNAPSE_PORT})" "docker compose logs --tail 30 synapse"
[ "$(http_code "http://127.0.0.1:${ELEMENT_PORT}/")" = 200 ] && ok "Element 웹 응답" \
  || bad "Element 웹이 응답하지 않습니다 (127.0.0.1:${ELEMENT_PORT})" "docker compose logs --tail 30 element"
[ "$(http_code "http://127.0.0.1:${ELEMENT_PORT}/push/config.json")" = 200 ] && ok "알림 켜기 페이지(/push/) 준비됨" \
  || bad "/push/ 페이지 파일이 없습니다" "sudo ./install.sh 를 다시 실행하세요"
if docker compose exec -T synapse python -c \
     "import urllib.request; urllib.request.urlopen('http://${SYGNAL_IP}:5000/health', timeout=5)" >/dev/null 2>&1; then
  ok "Synapse → 푸시 서버(Sygnal) 연결"
else
  bad "Synapse 가 푸시 서버(${SYGNAL_IP})에 연결하지 못합니다" "docker compose logs --tail 30 sygnal (다른 네트워크와 겹치면 .env 의 PUSH_SUBNET/SYGNAL_IP 변경 후 install.sh)"
fi

head_ "3. 외부 주소 (인터넷에서 접속)"
code="$(http_code "https://${MATRIX_HOST}/_matrix/client/versions")"
case "$code" in
  200) ok "https://${MATRIX_HOST} 메신저 서버 접속됨" ;;
  000) bad "https://${MATRIX_HOST} 에 접속할 수 없습니다" "Cloudflare DNS 에 ${MATRIX_HOST%%.*} 레코드가 이 서버를 가리키는지 확인 (README 'Cloudflare DNS 설정')" ;;
  52*) bad "Cloudflare 가 이 서버에 연결하지 못합니다 (HTTP $code)" "Cloudflare SSL/TLS 모드가 Full (strict) 인지, 서버 443 포트가 열려 있는지 확인" ;;
  404) bad "https://${MATRIX_HOST} 가 다른 사이트로 연결됩니다 (404)" "와일드카드(*) 레코드가 다른 서버를 가리키고 있습니다. ${MATRIX_HOST%%.*} A 레코드를 이 서버 IP 로 추가하세요" ;;
  *)   bad "https://${MATRIX_HOST} 응답 이상 (HTTP $code)" "웹서버 설정 확인: nginx -t 또는 apachectl configtest" ;;
esac
code="$(http_code "https://${CHAT_HOST}/push/config.json")"
case "$code" in
  200) ok "https://${CHAT_HOST} 채팅·알림 페이지 접속됨" ;;
  000) bad "https://${CHAT_HOST} 에 접속할 수 없습니다" "Cloudflare DNS 에 ${CHAT_HOST%%.*} 레코드 추가" ;;
  404) bad "https://${CHAT_HOST} 가 다른 사이트로 연결됩니다 (404)" "와일드카드(*) 레코드가 다른 서버를 가리키고 있습니다. ${CHAT_HOST%%.*} A 레코드를 이 서버 IP 로 추가하세요" ;;
  *)   bad "https://${CHAT_HOST} 응답 이상 (HTTP $code)" "Cloudflare SSL/TLS 모드(Full strict)와 웹서버 설정 확인" ;;
esac
if curl -fsS -m 10 "https://${SERVER_NAME}/.well-known/matrix/client" 2>/dev/null | grep -q "$MATRIX_HOST"; then
  ok "앱에서 '${SERVER_NAME}' 만 입력해도 됨 (.well-known)"
else
  printf '  - 앱에서는 %s 를 입력하세요 (%s 만 입력하려면 README 의 Cloudflare Worker 설정)\n' "$MATRIX_HOST" "$SERVER_NAME"
fi

head_ "4. 인증서"
if [ -s certs/origin.pem ]; then
  end="$(openssl x509 -in certs/origin.pem -noout -enddate 2>/dev/null | cut -d= -f2)"
  [ -n "$end" ] && ok "Cloudflare 원본 인증서 사용 (만료: $end)" || bad "certs/origin.pem 을 읽을 수 없습니다" "Cloudflare 에서 받은 인증서 내용을 다시 붙여 넣으세요"
  openssl x509 -in certs/origin.pem -noout -checkend 2592000 >/dev/null 2>&1 || bad "원본 인증서가 30일 안에 만료됩니다" "Cloudflare 에서 새로 발급 후 certs/ 교체"
elif command -v certbot >/dev/null && certbot certificates 2>/dev/null | grep -q "$MATRIX_HOST"; then
  ok "Let's Encrypt 인증서 사용 (자동 갱신)"
else
  bad "HTTPS 인증서가 없습니다" "README 'Cloudflare DNS 설정' 방법 A(원본 인증서)로 certs/ 에 넣고 install.sh 재실행"
fi

head_ "5. 보안"
[ "$(stat -c %a .env 2>/dev/null)" = 600 ] && ok ".env 권한 600" || bad ".env 를 다른 사용자가 읽을 수 있습니다" "chmod 600 .env"
[ -s data/sygnal/vapid_private.pem ] && [ "$(stat -c %a data/sygnal/vapid_private.pem)" = 600 ] && ok "푸시 서명 키 보호됨" \
  || bad "푸시 서명 키가 없거나 권한이 넓습니다" "sudo ./install.sh 재실행"
if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE "^(0\.0\.0\.0|\*|\[::\]):(${SYNAPSE_PORT}|${ELEMENT_PORT}|5432|5000)$"; then
  bad "내부 포트가 외부에 열려 있습니다" "docker-compose.yml 의 ports 가 127.0.0.1 로 시작하는지 확인"
else
  ok "내부 포트는 127.0.0.1 에만 열림"
fi
[ "$(http_code "https://${MATRIX_HOST}/_synapse/admin/v1/server_version")" = 404 ] && ok "관리자 API 는 외부에서 막힘" \
  || { [ "$(http_code "https://${MATRIX_HOST}/_matrix/client/versions")" = 200 ] && bad "관리자 API(/_synapse/admin)가 외부에 열려 있습니다" "웹서버 설정에서 /_synapse/admin 을 막으세요"; }

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32m모두 정상입니다.\033[0m 휴대폰에서 https://%s/push/ 를 열어 알림을 켜세요.\n' "$CHAT_HOST"
else
  printf '\033[31m문제 %d개\033[0m — 위의 → 안내를 따라 해결하거나, 이 화면을 그대로 복사해서 물어보세요.\n' "$FAIL"
  exit 1
fi
