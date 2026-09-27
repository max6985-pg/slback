#!/usr/bin/env bash
# 사용자 추가: sudo ./scripts/add-user.sh 아이디 [--admin]
# 비밀번호는 실행 중에 입력합니다.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -ge 1 ] || { echo "사용법: $0 아이디 [--admin]"; exit 1; }
USER_ID="$1"
ADMIN_FLAG="--no-admin"; [ "${2:-}" = "--admin" ] && ADMIN_FLAG="--admin"

set -a; . ./.env; set +a

if ! [[ "$USER_ID" =~ ^[a-z0-9._=/-]+$ ]]; then
  echo "아이디는 영문 소문자, 숫자, . _ = - / 만 쓸 수 있습니다 (예: hong, kim.minsu)."
  exit 1
fi

read -rsp "@${USER_ID}:${SERVER_NAME} 비밀번호: " PW; echo
read -rsp "비밀번호 확인: " PW2; echo
[ "$PW" = "$PW2" ] || { echo "비밀번호가 일치하지 않습니다."; exit 1; }
[ ${#PW} -ge 8 ]   || { echo "비밀번호는 8자 이상이어야 합니다."; exit 1; }

docker compose exec -T synapse register_new_matrix_user \
  -c /data/homeserver.yaml -u "$USER_ID" -p "$PW" "$ADMIN_FLAG" http://localhost:8008

echo "완료: @${USER_ID}:${SERVER_NAME}"
