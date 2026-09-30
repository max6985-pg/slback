#!/usr/bin/env bash
# 단체방 만들기 + 기존 계정 전부 초대
#   sudo ./scripts/create-group-room.sh
# 관리자 비밀번호를 물어봅니다. 이미 방이 있으면 새로 만들지 않고 빠진 사람만 초대합니다.
# 이후 새로 만드는 계정은 homeserver.yaml 의 auto_join_rooms 로 자동 입장합니다.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env; set +a

ALIAS="#${GROUP_ROOM_ALIAS:-all}:${SERVER_NAME}"
NAME="${GROUP_ROOM_NAME:-전체공지}"
HS="http://127.0.0.1:${SYNAPSE_PORT}"
ADMIN="@${ADMIN_USER}:${SERVER_NAME}"

json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
enc()  { printf '%s' "$1" | sed 's/#/%23/g; s/:/%3A/g; s/@/%40/g; s/!/%21/g'; }
field() { grep -o "\"$1\":\"[^\"]*\"" | head -1 | cut -d'"' -f4; }

read -rsp "관리자(${ADMIN}) 비밀번호: " PW; echo
TOKEN="$(printf '{"type":"m.login.password","identifier":{"type":"m.id.user","user":"%s"},"password":"%s","initial_device_display_name":"create-group-room.sh"}' \
    "$ADMIN_USER" "$(json "$PW")" \
  | curl -fsS -X POST "$HS/_matrix/client/v3/login" -H 'Content-Type: application/json' --data-binary @- \
  | field access_token || true)"
unset PW
[ -n "$TOKEN" ] || { echo "관리자 로그인 실패 (아이디/비밀번호 확인)"; exit 1; }
trap 'curl -fsS -X POST "$HS/_matrix/client/v3/logout" -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1 || true' EXIT
AUTH=(-H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json')

# 1. 방 찾기 또는 만들기
ROOM_ID="$(curl -fsS "${AUTH[@]}" "$HS/_matrix/client/v3/directory/room/$(enc "$ALIAS")" 2>/dev/null | field room_id || true)"
if [ -n "$ROOM_ID" ]; then
  echo "기존 단체방 사용: $ALIAS ($ROOM_ID)"
else
  ROOM_ID="$(printf '{"name":"%s","room_alias_name":"%s","preset":"private_chat","visibility":"private","topic":"%s"}' \
      "$(json "$NAME")" "$(json "${GROUP_ROOM_ALIAS:-all}")" "$(json "$NAME") — 새 계정은 자동으로 들어옵니다" \
    | curl -fsS -X POST "${AUTH[@]}" "$HS/_matrix/client/v3/createRoom" --data-binary @- | field room_id)"
  [ -n "$ROOM_ID" ] || { echo "단체방을 만들지 못했습니다."; exit 1; }
  echo "단체방 생성: $NAME ($ALIAS)"
fi

# 2. 기존 계정 초대 (봇·브릿지·비활성 계정 제외)
USERS="$(curl -fsS "${AUTH[@]}" "$HS/_synapse/admin/v2/users?from=0&limit=1000&guests=false&deactivated=false" \
  | docker compose exec -T synapse python3 -c '
import json, sys
for u in json.load(sys.stdin).get("users", []):
    if not u.get("appservice_id") and not u.get("user_type") and not u.get("deactivated"):
        print(u["name"])')"
MEMBERS="$(curl -fsS "${AUTH[@]}" "$HS/_matrix/client/v3/rooms/$(enc "$ROOM_ID")/joined_members" || true)"

n=0
for u in $USERS; do
  [ "$u" = "$ADMIN" ] && continue
  printf '%s' "$MEMBERS" | grep -q "\"$u\"" && continue
  if printf '{"user_id":"%s"}' "$u" \
      | curl -fsS -X POST "${AUTH[@]}" "$HS/_matrix/client/v3/rooms/$(enc "$ROOM_ID")/invite" --data-binary @- >/dev/null 2>&1; then
    echo "초대: $u"; n=$((n+1))
  fi
done
echo "완료: ${n}명 초대. 각자 로그인해서 초대를 수락하면 됩니다."
echo "앞으로 add-user.sh 로 만드는 계정은 자동으로 $ALIAS 에 들어갑니다."
