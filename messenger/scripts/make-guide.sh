#!/usr/bin/env bash
# 접속 안내 페이지(QR 포함)를 만듭니다.
#   sudo ./scripts/make-guide.sh                 → data/private/ 에 생성
#   sudo ./scripts/make-guide.sh /var/www/private → 원하는 곳에 생성
# 만든 뒤 웹서버에서 그 폴더를 PRIVATE_HOST 로 서비스하면 됩니다.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a
OUT="${1:-$PWD/data/private}"
: "${PRIVATE_HOST:=private.${SERVER_NAME}}"
export PRIVATE_HOST

command -v qrencode >/dev/null || {
  if command -v apt-get >/dev/null; then apt-get install -y -qq qrencode
  elif command -v dnf >/dev/null; then dnf install -y -q qrencode
  else yum install -y -q qrencode; fi; }

mkdir -p "$OUT/qr"
# 앱 서버 자동 연결 링크는 서버 주소를 쓴다. Element X 가 이 주소로 로그인 화면을 연다.
qrencode -s 18 -m 2 -o "$OUT/qr/app.png"  "https://mobile.element.io/element/?account_provider=${MATRIX_HOST}"
qrencode -s 18 -m 2 -o "$OUT/qr/web.png"  "https://${CHAT_HOST}"
qrencode -s 18 -m 2 -o "$OUT/qr/push.png" "https://${CHAT_HOST}/push/"
qrencode -s 18 -m 2 -o "$OUT/qr/self.png" "https://${PRIVATE_HOST}"
qrencode -s 18 -m 2 -o "$OUT/qr/ios.png"  "https://apps.apple.com/app/id1631335820"
qrencode -s 18 -m 2 -o "$OUT/qr/and.png"  "https://play.google.com/store/apps/details?id=io.element.android.x"

envsubst '${BRAND} ${SERVER_NAME} ${MATRIX_HOST} ${CHAT_HOST} ${PRIVATE_HOST}' \
  < www/private/index.html > "$OUT/index.html"

echo "안내 페이지: $OUT/index.html"
echo "주소: https://${PRIVATE_HOST}  (DNS 레코드와 웹서버 설정이 따로 필요합니다)"
