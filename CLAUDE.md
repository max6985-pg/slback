# slback 작업 메모

사용자와는 한국어로 대화합니다. 주 사용 언어: Java, PHP.

## 비공개 메신저 (`messenger/`)
Matrix(Synapse) + Element 웹, 우리끼리만 쓰는 메신저 설치 세트. 사용법은 `messenger/README.md`.

- 도메인: `onepin.net` (DNS: Cloudflare)
  - `matrix.onepin.net` → Synapse, `chat.onepin.net` → Element 웹
  - 아이디 형식 `@아이디:onepin.net` (SERVER_NAME 은 설치 후 변경 불가)
  - `www.onepin.net` = 상품권 사이트(Next.js), `cms.onepin.net` = CMS
- 서버 1대에 전부 설치 (`sudo ./install.sh`)
- 인증서: Cloudflare 원본 인증서(`messenger/certs/origin.pem`, `origin.key`), SSL 모드 Full (strict)
  - 없으면 Let's Encrypt (HTTP 인증, 또는 `.env` 의 `CF_API_TOKEN` 으로 DNS 인증)
- 비공개 설정: 가입 차단, federation 차단, 새 방 기본 암호화
- 보안 강화(PR #1): Element 외부 서비스 호출 차단(위젯·통합관리자·VoIP·URL 미리보기 등),
  비밀번호 12자 이상, 로그인 속도 제한, 보안 헤더(HSTS 등). README 는 회색 구름(DNS only) 권장
- 웹 푸시 알림(PR #1): 자체 Sygnal(내부망 전용) + `/push/` PWA 페이지, 알림에 메시지 내용 미포함
- 모바일: 공식 Element X 앱 + 서버 주소 입력 (`scripts/qr.sh app` 로 자동입력 링크 QR, 실기기 확인 필요)

### 현재 상태 (2026-09-28)
- 설치 세트 완성, 브랜치 `claude/trusting-maxwell-rmuypp` 에 푸시됨 (보안·푸시 기능은 max6985-pg/slback#1 로 병합)
- **서버에는 아직 설치 안 됨.** 사용자가 작업을 중단시킴
- 확인 결과: `*.onepin.net` 와일드카드가 주황 구름(프록시)으로 상품권 사이트를 가리킴
  → `matrix`/`chat` 도 현재 상품권 사이트가 응답함
- 클라우드 세션에서는 SSH 불가(ssh 미설치 + 네트워크 차단).
  이어서 하려면 서버에서 Claude Code 를 실행하는 방식 권장

### 남은 일
1. Cloudflare 원본 인증서 발급 → 서버 `messenger/certs/` 에 저장
2. 와일드카드(또는 `matrix`/`chat` 레코드)가 메신저 서버 IP 를 가리키는지 확인
3. 서버에서 `sudo ./install.sh` 실행 → 관리자 계정 생성
4. `https://matrix.onepin.net/_matrix/client/versions` 응답 확인
5. (선택) Cloudflare Worker 로 `onepin.net/.well-known/matrix/client` 등록
6. (선택) 완전 자동 서버 연결이 필요하면 안드로이드 자체 빌드 앱

## 기타
- 사칭 주의 공지 문구: `notes/사칭주의-공지.md`
- 시그널을 임시 비공개 메신저로 사용 중 (그룹 링크는 "관리자 승인 필요" 권장)
