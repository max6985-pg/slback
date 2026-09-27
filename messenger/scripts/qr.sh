#!/usr/bin/env bash
# 접속용 QR 코드를 터미널에 출력하고 PNG 로도 저장합니다.
#   sudo ./scripts/qr.sh          → 웹 채팅 주소 QR
#   sudo ./scripts/qr.sh 주소     → 원하는 주소 QR
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

URL="${1:-https://${CHAT_HOST}}"

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
