#!/usr/bin/env bash
# 여러 계정 한 번에 만들기 (계정마다 다른 임시 비밀번호 자동 생성)
#   sudo ./scripts/add-users.sh oris22320770 oris44640660 ...
#   sudo ./scripts/add-users.sh hong:홍길동 kim:김철수        ← 아이디:닉네임
# 닉네임을 안 주면 아이디가 닉네임이 됩니다. 새 계정은 단체방에 자동 입장합니다.
# 비밀번호는 화면에만 출력하고 파일로 저장하지 않습니다.
set -uo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 1 ] || { echo "사용법: $0 아이디[:닉네임] ..."; exit 1; }
set -a; . ./.env; set +a

gen_pw() {  # 영문 소문자+숫자 14자, 둘 다 반드시 포함
  local p
  while :; do
    p="$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 14)"
    [[ "$p" =~ [0-9] && "$p" =~ [a-z] ]] && { printf '%s' "$p"; return; }
  done
}

OK=(); FAIL=()
for arg in "$@"; do
  id="${arg%%:*}"; nick="${arg#*:}"; [ "$nick" = "$arg" ] && nick="$id"
  pw="$(gen_pw)"
  echo "── @${id}:${SERVER_NAME}"
  if ADD_USER_PASSWORD="$pw" ./scripts/add-user.sh "$id" --name "$nick"; then
    OK+=("$(printf '%-20s %-14s %s' "$id" "$pw" "$nick")")
  else
    FAIL+=("$id")
  fi
done

echo
echo "════════ 생성 완료: ${#OK[@]}개 ════════"
printf '%-20s %-14s %s\n' "아이디" "임시비밀번호" "닉네임"
for l in "${OK[@]}"; do echo "$l"; done
[ ${#FAIL[@]} -eq 0 ] || echo "실패: ${FAIL[*]} (이미 있는 아이디이거나 형식 오류)"
echo
echo "로그인: https://${CHAT_HOST}  (앱: Element X, 서버 ${MATRIX_HOST})"
echo "첫 로그인 후 설정 → 보안에서 비밀번호를 꼭 바꾸도록 안내하세요."
