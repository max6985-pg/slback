#!/usr/bin/env bash
# 사용자 추가: sudo ./scripts/add-user.sh 아이디 [--name 닉네임] [--admin]
#   예) sudo ./scripts/add-user.sh double --name 더블
# 비밀번호는 실행 중에 입력합니다. 닉네임을 안 주면 아이디가 닉네임이 됩니다.
set -euo pipefail
cd "$(dirname "$0")/.."

usage() { echo "사용법: $0 아이디 [--name 닉네임] [--admin]"; exit 1; }
[ $# -ge 1 ] || usage
USER_ID="$1"; shift
ADMIN_FLAG="--no-admin"
NICK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --admin) ADMIN_FLAG="--admin" ;;
    --name)  [ $# -ge 2 ] || usage; NICK="$2"; shift ;;
    *) usage ;;
  esac
  shift
done

set -a; . ./.env; set +a

if ! [[ "$USER_ID" =~ ^[a-z0-9._=/-]+$ ]]; then
  echo "아이디는 영문 소문자, 숫자, . _ = - / 만 쓸 수 있습니다 (예: hong, kim.minsu)."
  exit 1
fi

read -rsp "@${USER_ID}:${SERVER_NAME} 비밀번호: " PW; echo
read -rsp "비밀번호 확인: " PW2; echo
[ "$PW" = "$PW2" ] || { echo "비밀번호가 일치하지 않습니다."; exit 1; }
[ ${#PW} -ge 12 ]  || { echo "비밀번호는 12자 이상이어야 합니다."; exit 1; }
[[ "$PW" =~ [0-9] && "$PW" =~ [a-z] ]] || { echo "비밀번호에 숫자와 영문 소문자를 모두 넣어 주세요."; exit 1; }

# 비밀번호는 명령줄(ps 에 보임)이 아니라 표준입력으로 전달
printf '%s' "$PW" | docker compose exec -T synapse register_new_matrix_user \
  -c /data/homeserver.yaml -u "$USER_ID" --password-file /dev/stdin "$ADMIN_FLAG" http://localhost:8008

# 닉네임(표시 이름) 설정: 방금 만든 계정으로 잠깐 로그인해서 바꾸고 바로 로그아웃
if [ -n "$NICK" ]; then
  HS="http://127.0.0.1:${SYNAPSE_PORT}"
  json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  TOKEN="$(printf '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"%s"},"password":"%s","initial_device_display_name":"add-user.sh"}' \
      "$USER_ID" "$(json "$PW")" \
    | curl -fsS -X POST "$HS/_matrix/client/v3/login" -H 'Content-Type: application/json' --data-binary @- \
    | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || true)"
  if [ -n "$TOKEN" ]; then
    printf '{"displayname":"%s"}' "$(json "$NICK")" \
      | curl -fsS -X PUT "$HS/_matrix/client/v3/profile/@${USER_ID}:${SERVER_NAME}/displayname" \
          -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' --data-binary @- >/dev/null \
      && echo "닉네임 설정: $NICK" || echo "⚠ 닉네임을 설정하지 못했습니다. 로그인 후 설정에서 바꿔 주세요."
    curl -fsS -X POST "$HS/_matrix/client/v3/logout" -H "Authorization: Bearer $TOKEN" >/dev/null || true
  else
    echo "⚠ 닉네임을 설정하지 못했습니다 (로그인 실패). 로그인 후 설정에서 바꿔 주세요."
  fi
fi
unset PW PW2 TOKEN

echo "완료: @${USER_ID}:${SERVER_NAME}${NICK:+ (닉네임: $NICK)}"
