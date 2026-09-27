#!/usr/bin/env bash
# 접속용 QR 코드를 터미널에 출력하고 PNG 로도 저장합니다.
#   sudo ./scripts/qr.sh           → 웹 채팅 주소 QR
#   sudo ./scripts/qr.sh app       → Element X 앱 접속 링크 QR (서버 주소 자동 입력, 시험 기능)
#   sudo ./scripts/qr.sh ios|android → 앱 설치 QR
#   sudo ./scripts/qr.sh 주소      → 원하는 주소 QR
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

case "${1:-web}" in
  web)     URL="https://${CHAT_HOST}" ;;
  # Element X 가 지원하는 로그인 링크: 앱이 설치돼 있으면 서버가 채워진 로그인 화면으로 이동
  # 앱 버전에 따라 동작이 다를 수 있으니 실제 폰에서 확인 후 배포하세요.
  app)     URL="https://mobile.element.io/element/?account_provider=${SERVER_NAME}" ;;
  ios)     URL="https://apps.apple.com/app/id1631335820" ;;
  android) URL="https://play.google.com/store/apps/details?id=io.element.android.x" ;;
  *)       URL="$1" ;;
esac

if ! command -v qrencode >/dev/null; then
  if command -v apt-get >/dev/null; then apt-get install -y -qq qrencode
  elif command -v dnf >/dev/null; then dnf install -y -q qrencode
  else yum install -y -q qrencode; fi
fi

mkdir -p data/qr
OUT="data/qr/$(echo "$URL" | sed 's|https\?://||; s|[^A-Za-z0-9._-]|_|g').png"
qrencode -t ANSIUTF8 "$URL"
qrencode -s 10 -o "$OUT" "$URL"
echo "$URL"
echo "PNG 저장: $(pwd)/$OUT"
