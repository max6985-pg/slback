# onepin 비공개 메신저

Matrix(Synapse) 서버와 Element 웹으로 만든, **우리끼리만 쓰는 메신저**입니다.

- 가입이 막혀 있어서 관리자가 만든 계정만 쓸 수 있습니다
- 다른 Matrix 서버와 연결하지 않습니다 (federation 차단)
- 새 대화방은 기본으로 종단간 암호화됩니다
- 외부 서비스(통합 관리자·지도·신고·링크 미리보기 등)에 접속하지 않도록 막아 두었습니다 (아래 **보안** 참고)
- 기존 CMS(`cms.onepin.net`)는 그대로 두고, 서브도메인 2개만 추가합니다

```
cms.onepin.net     → 기존 CMS (변경 없음)
chat.onepin.net    → Element 웹 (브라우저 채팅 화면)
matrix.onepin.net  → Synapse 메신저 서버
```

## 준비물
- root 권한이 있는 리눅스 서버 (Ubuntu/Debian/Rocky 등), 여유 메모리 2GB 이상
- Cloudflare DNS 에 `chat`, `matrix` A 레코드 추가 (아래 참고)

## Cloudflare DNS 설정 (설치 전에)
메신저 서버로 `matrix.onepin.net`, `chat.onepin.net` 이 연결돼야 합니다. 두 방법 중 하나를 고르세요.

> 🔒 **보안이 최우선이면 방법 B(회색 구름)를 쓰세요.**
> 주황 구름은 Cloudflare 가 HTTPS 를 풀어서 다시 암호화하기 때문에, Cloudflare 가 **로그인 비밀번호, 접속 토큰,
> 누가 언제 누구와 대화하는지(메타데이터)** 를 볼 수 있습니다. 메시지 내용은 종단간 암호화로 보호되지만,
> 회색 구름이면 암호화가 사용자 기기 ↔ 우리 서버 사이에서만 풀립니다.

### 방법 A — 주황 구름(프록시) + Cloudflare 원본 인증서 (편의 우선)
와일드카드 `*` 나 `matrix`·`chat` 레코드가 **이 서버로** 프록시되고 있으면 DNS 는 그대로 둡니다.

1. Cloudflare → onepin.net → **SSL/TLS → Origin Server → Create Certificate**
   - 호스트 이름: `*.onepin.net`, `onepin.net` (기본값), 유효기간 15년 → Create
2. 서버에 파일 두 개로 저장 (채팅·깃에 올리지 마세요, `certs/` 는 git 에서 제외됨)
   ```bash
   mkdir -p slback/messenger/certs
   sudo nano slback/messenger/certs/origin.pem   # "Origin Certificate" 내용 붙여넣기
   sudo nano slback/messenger/certs/origin.key   # "Private Key" 내용 붙여넣기
   ```
3. **SSL/TLS → Overview → Full (strict)** 로 설정
4. `sudo ./install.sh` 실행 → 원본 인증서를 자동으로 인식해 443 포트에 적용합니다
5. 업로드는 무료 요금제 기준 100MB 까지

> 이미 다른 사이트용 Cloudflare 원본 인증서(`*.onepin.net`)가 서버에 있으면 그 파일을 복사해 써도 됩니다.

### 방법 B — 회색 구름(DNS only) (보안 우선, 권장)
DNS → Records 에 전용 레코드를 추가합니다 (와일드카드보다 우선 적용).

| Type | Name | IPv4 address | Proxy status |
|---|---|---|---|
| A | `matrix` | 서버 IP | **DNS only (회색 구름)** |
| A | `chat` | 서버 IP | **DNS only (회색 구름)** |

> 어느 방법이든 Cloudflare 가 가리키는 **원본 서버가 메신저를 설치한 서버**여야 합니다.
> CMS(`cms.onepin.net`)·`www` 레코드는 건드리지 않습니다.

### 앱에서 `onepin.net` 만 입력해도 되게 하기 (선택)
Cloudflare 대시보드 → **Workers & Pages → Create → Worker**
1. `cloudflare/well-known-worker.js` 내용을 붙여 넣고 Deploy
2. Worker 의 **Settings → Domains & Routes → Add route**: `onepin.net/.well-known/matrix/*` (Zone: onepin.net)
3. 확인: 브라우저에서 `https://onepin.net/.well-known/matrix/client` 열면 JSON 이 나오면 성공

(Worker 대신 onepin.net 웹 서버에 `data/well-known-client.json` 파일을 올려도 됩니다.
이 단계가 없으면 앱에서 `matrix.onepin.net` 을 입력하면 됩니다.)

## 설치 (3단계)

```bash
# 1. 받기
git clone -b claude/trusting-maxwell-rmuypp https://github.com/max6985-pg/slback.git
cd slback/messenger

# 2. 설정 파일 만들고 도메인·이름 확인
sudo ./install.sh          # .env 가 생성되고 멈춤
sudo nano .env             # SERVER_NAME, BRAND 등 확인

# 3. 설치 (관리자 비밀번호 입력 요청이 나옵니다)
sudo ./install.sh
```

`install.sh` 가 하는 일:
1. Docker 가 없으면 설치
2. DB 비밀번호 등 비밀값 자동 생성 (`.env`, git 에 올라가지 않음)
3. Synapse + PostgreSQL + Element 웹 실행 (내부 포트 `127.0.0.1` 에만 열림)
4. 기존 Nginx 또는 Apache 에 서브도메인 연결 (없으면 Nginx 설치)
5. HTTPS 적용 (`certs/` 의 Cloudflare 원본 인증서, 없으면 Let's Encrypt 발급)
6. 관리자 계정 생성

> ⚠ `SERVER_NAME` 은 사용자 아이디(`@hong:onepin.net`)의 일부라서 **설치 후에는 바꿀 수 없습니다.**

## 사용자 추가
비밀번호는 **12자 이상, 숫자와 영문 소문자 포함**이어야 합니다.
아이디는 **영문 소문자·숫자·`._-`** 만 쓸 수 있습니다. 한글 이름은 로그인 후 프로필의 "표시 이름"으로 설정합니다.

```bash
sudo ./scripts/add-user.sh hong            # 일반 사용자 → @hong:onepin.net
sudo ./scripts/add-user.sh kim --admin     # 관리자
sudo ./scripts/add-user.sh double --name 더블   # 닉네임(표시 이름)까지 설정
sudo ./scripts/add-users.sh hong kim:김철수 lee   # 여러 명 한 번에 (계정마다 임시 비밀번호 자동 생성)
```

## 단체방 (자동 입장)
새로 만드는 계정은 **자동으로 단체방(`#all:onepin.net`, 이름 "전체공지")에 들어갑니다.**
방 이름과 주소는 `.env` 의 `GROUP_ROOM_NAME`, `GROUP_ROOM_ALIAS` 로 바꿀 수 있습니다.

처음 한 번만 방을 만들고, 이미 있는 계정을 초대합니다.
```bash
sudo ./scripts/create-group-room.sh   # 관리자 비밀번호 입력
```
- 이미 있는 계정: 초대가 가므로 로그인해서 **수락**하면 됩니다.
- 이후 `add-user.sh` 로 만드는 계정: 자동으로 입장합니다.
- 다시 실행해도 안전합니다. 방은 새로 만들지 않고, 빠진 사람만 초대합니다.
- 공지 전용으로 쓰려면 방 설정 → **역할 및 권한** → "메시지 보내기"를 관리자만으로 바꾸세요.

## 휴대폰 (아이폰·안드로이드)

### 방법 1 — 웹앱 + 푸시 알림 (앱 스토어 없이)
휴대폰 브라우저로 **`https://chat.onepin.net/push/`** 를 엽니다.

| | 아이폰 | 안드로이드 |
|---|---|---|
| 브라우저 | **Safari** (iOS 16.4 이상) | Chrome |
| 설치 | 공유(□↑) → **홈 화면에 추가** → 홈 화면 아이콘으로 실행 | 메뉴(⋮) → **홈 화면에 추가** (선택) |
| 알림 켜기 | 아이디·비밀번호 입력 → **알림 허용** | 같음 |

- 알림을 켠 뒤에는 홈 화면 아이콘을 누르면 바로 채팅(Element 웹)이 열립니다. 채팅 화면에서 **한 번 더 로그인**하세요.
  (알림용 로그인과 채팅용 로그인은 따로입니다)
- 알림은 **"새 메시지가 도착했습니다"** 로만 표시됩니다. 누르면 해당 대화방이 열립니다.
- 끄기: `https://chat.onepin.net/push/` 를 다시 열고 **이 기기 알림 끄기**.
- 설정 → 보안 → 세션 목록에 **"OnePin 메신저 알림 전용 (iPhone)"** 세션이 보입니다. 암호화 키가 없어 메시지를 읽을 수 없는 알림 전용 세션이며,
  이 세션을 로그아웃하면 그 기기의 알림이 꺼집니다.

**푸시 알림의 보안**
```
Synapse ──(내부망)──▶ Sygnal ──(암호화)──▶ Apple/Google 푸시 서버 ──▶ 휴대폰
```
- Synapse 는 메시지 **ID·안 읽은 수만** 보내고 내용·보낸 사람·방 이름은 보내지 않습니다 (`push.include_content: false`, `event_id_only`)
- 그마저 휴대폰만 풀 수 있게 암호화(Web Push 암호화, RFC 8291)되어 Apple/Google 은 **"몇 시에 이 기기로 알림이 갔다"** 만 압니다
- Sygnal 은 외부 포트를 열지 않고, Apple·Google·Mozilla·Microsoft 푸시 서버로만 전송합니다
- 서명 키: `data/sygnal/vapid_private.pem` (백업 대상. 바꾸면 모든 기기에서 알림을 다시 켜야 함)

### 방법 2 — Element X 앱
1. App Store / Play 스토어에서 **Element X** 설치
2. "서버 변경" → `onepin.net` 입력 (또는 `matrix.onepin.net`)
3. 받은 아이디·비밀번호로 로그인

`onepin.net` 만 입력하려면 위의 **Cloudflare Worker** 설정이 필요합니다.
Element X 의 푸시 알림은 Element 사(matrix.org)의 푸시 서버를 거칩니다. 우리 서버만 쓰려면 방법 1 을 쓰세요.

## QR 코드
```bash
sudo ./scripts/qr.sh           # 웹 채팅 주소
sudo ./scripts/qr.sh ios       # 아이폰 Element X 설치
sudo ./scripts/qr.sh android   # 안드로이드 Element X 설치
sudo ./scripts/qr.sh app       # 앱 접속 링크: 서버 주소 자동 입력 (시험 기능)
```
터미널에 QR 이 나오고, PNG 파일이 `data/qr/` 에 저장됩니다. 인쇄하거나 공지에 붙여 쓰세요.

`app` QR 은 앱이 설치된 폰에서 찍으면 서버 주소가 채워진 로그인 화면으로 이동하도록 만든 링크입니다.
Element X 버전에 따라 동작이 다를 수 있으니 **아이폰·안드로이드에서 한 번씩 확인한 뒤** 배포하세요.
안 되면 앱에서 `onepin.net` 을 직접 입력하면 됩니다.

> 카메라로 찍어 **로그인까지 자동으로 되는 기능**(Element X 의 "QR 로그인")은
> 별도 인증 서버(MAS)가 필요해서 이 기본 설치에는 포함되지 않습니다.

## 텔레그램 브릿지 (선택)
텔레그램 단체방과 우리 메신저 방을 연결해서, 양쪽 메시지가 서로 전달되게 합니다.
기본은 **릴레이 봇 방식**입니다. 텔레그램 단체방에 우리 봇을 넣으면 봇이 메시지를 옮겨 줍니다.
개인 텔레그램 계정으로 로그인할 필요가 없습니다.

### 1. 텔레그램에서 준비
1. **API 정보**: https://my.telegram.org 로그인 → **API development tools** → 앱 생성 → `api_id`, `api_hash` 복사
2. **봇 만들기**: 텔레그램에서 `@BotFather` → `/newbot` → 봇 토큰 복사
3. **봇이 단체방 메시지를 읽도록 설정**: `@BotFather` → `/setprivacy` → 봇 선택 → **Disable**

### 2. 서버에서 켜기
`.env` 에 입력합니다 (채팅·깃에 올리지 마세요).
```bash
TELEGRAM_BRIDGE=on
TELEGRAM_API_ID=1234567
TELEGRAM_API_HASH=0123456789abcdef0123456789abcdef
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
```
그다음 `sudo ./install.sh` 를 다시 실행합니다. 브릿지 설치와 Synapse 연결까지 자동으로 합니다.

### 3. 단체방 연결
1. 텔레그램 단체방에 봇을 **초대하고 관리자로 지정**합니다.
2. 텔레그램 단체방에서 `/portal` 을 입력하면 우리 메신저에 연결된 방이 만들어집니다.
3. 텔레그램 단체방에서 `/invite @admin:onepin.net` 을 입력해 우리 사용자를 초대합니다.
4. Element 에서 초대를 수락하면 끝입니다.

- 텔레그램 사람은 Element 에서 `이름 (Telegram)` 으로 보입니다.
- 우리 쪽 메시지는 텔레그램에 봇 이름으로 `이름: 메시지` 형태로 전달됩니다.

### 끄기
`.env` 에서 `TELEGRAM_BRIDGE=off` 로 바꾸고 `sudo ./install.sh` 를 실행합니다.

### ⚠ 보안 주의
- **연결된 방의 메시지는 텔레그램 서버로 넘어갑니다.** 종단간 암호화의 보호를 받지 못합니다.
  민감한 업무 대화는 **브릿지하지 않은 방**에서만 하세요.
- 공지 전달용 단체방처럼 **용도를 정해서 필요한 방만** 연결하세요.
- `TELEGRAM_PUPPETING=on` 을 켜면 사용자가 자기 텔레그램 계정으로 로그인할 수 있습니다.
  이때 텔레그램 **인증코드**를 입력하게 되므로, 사칭 사기와 헷갈리지 않도록 **off 를 권장**합니다.

## 로고·이름 바꾸기
- 이름: `.env` 의 `BRAND` 수정 후 `sudo ./install.sh`
- 로고: `element/custom/logo.svg` 파일 교체 후 `docker compose restart element`

## 운영
```bash
docker compose ps                 # 상태
docker compose logs -f synapse    # 로그
docker compose logs -f mautrix-telegram   # 텔레그램 브릿지 로그
docker compose logs -f sygnal     # 푸시 알림 로그
docker compose pull && docker compose up -d   # 업데이트
```

**백업 대상**: `messenger/.env` 와 `messenger/data/` 폴더 전체
(DB 는 `docker compose exec postgres pg_dump -U synapse synapse > backup.sql` 로도 백업 가능)

## 보안
설치할 때 아래 설정이 자동으로 적용됩니다.

| 항목 | 설정 |
|---|---|
| 가입 | 막힘. 관리자가 `add-user.sh` 로 만든 계정만 사용 |
| 다른 서버 연동 | 차단 (federation 없음, 외부 키 서버 없음) |
| 메시지 | 새 방은 모두 종단간 암호화. **서버 관리자도 내용을 볼 수 없음** |
| 외부 접속 | 통합 관리자(scalar.vector.im), 위젯, 지도, 오류 신고, 외부 TURN(turn.matrix.org), 링크 미리보기 모두 끔 |
| 영상·음성 통화 | 꺼 둠 (외부 통화 서버를 쓰지 않도록). 자체 TURN 서버를 설치한 뒤 켤 수 있음 |
| 비밀번호 | 12자 이상, 숫자·영문 소문자 필수. 로그인 5회 실패 시 잠시 차단 |
| 프로필 | 같은 방에 있는 사용자에게만 공개 |
| 기록 | 접속 IP 7일, 삭제한 메시지 원본 1일 후 완전 삭제 |
| 웹 | HTTPS 강제(HSTS), 주소 유출 방지(Referrer), 위치·카메라·마이크 권한 차단 |
| 푸시 알림 | 메시지 ID·안 읽은 수만 암호화해서 전송 (내용·보낸 사람 없음). 자체 푸시 서버(Sygnal) 사용 |
| 서버 포트 | Synapse·Element·DB 는 `127.0.0.1` 에만 열림, Sygnal 은 내부망 전용. 관리자 API(`/_synapse/admin`)는 외부에 열지 않음 |

**사용자에게 꼭 안내할 것**
1. 첫 로그인 후 **설정 → 보안 → 보안 키(복구 키) 설정**. 이 키가 없으면 기기를 잃었을 때 이전 대화를 복구할 수 없습니다. 서버 관리자도 복구해 줄 수 없습니다.
2. 새 기기로 로그인하면 기존 기기에서 **"세션 확인"**을 해 주세요. 확인 안 된 기기는 방마다 경고가 표시됩니다.
3. 대화 상대 프로필에서 **"확인(Verify)"** 을 한 번 해 두면 중간자 공격을 막을 수 있습니다.

**서버 관리자가 할 일**
- 서버는 SSH 키 로그인만 허용, 방화벽은 22·80·443 만 열기
- `.env`, `data/`, `certs/` 는 절대 외부로 공유하지 말 것 (백업도 암호화해서 보관)
- 한 달에 한 번 `docker compose pull && docker compose up -d` 로 보안 업데이트

## 참고
- 영상·음성 통화를 쓰려면 TURN 서버(coturn)를 추가로 설치하고 `templates/element-config.json` 의 `UIFeature.voip` 를 `true` 로 바꿔야 합니다
- Synapse·Element 는 AGPL-3.0 라이선스입니다. 내부 사용은 문제없습니다

---

## 통화 (음성·영상)

Element Call / MatrixRTC 방식. **통화 내용도 메시지처럼 종단간 암호화**되고, 중계 서버는 암호문만 전달합니다.

| 구성요소 | 하는 일 | 노출 |
| --- | --- | --- |
| `livekit` | 음성·영상 중계(SFU) | UDP `LK_UDP_START~END`, TCP 7881 (공개) · 신호 7880 (내부만) |
| `lk-jwt` | 계정 확인 후 통화 입장권 발급 | 내부만 (`/livekit/jwt` 로 프록시) |
| `element-call` | PC 브라우저 통화 화면 | `CALL_HOST` |

### 준비물

1. `CALL_HOST` 용 **DNS A 레코드** (예: `call.example.com` → 서버 IP). Cloudflare 라면 **회색 구름** 권장.
2. **방화벽**: UDP `50100-50200` 과 TCP `7881`. `install.sh` 가 자동으로 엽니다.
3. `SERVER_NAME` 도메인이 **다른 사이트일 때는 추가 설정이 필요합니다** — 아래 참고.

### `SERVER_NAME` 이 다른 사이트를 가리킬 때 (중요)

아이디가 `@사람:example.com` 인데 `example.com` 이 별개의 웹사이트라면, 통화 인증 서비스가
`https://example.com/.well-known/matrix/server` 를 읽지 못해 **통화가 401 로 끝납니다.**
(그 다음 후보인 `example.com:8448` 로 가서 시간 초과)

해결: 그 도메인에서 아래 한 줄만 응답하게 합니다.

```json
{"m.server": "matrix.example.com:443"}
```

Cloudflare 를 쓴다면 **Redirect Rule** 하나면 됩니다.

| 항목 | 값 |
| --- | --- |
| 조건 | URI Path **equals** `/.well-known/matrix/server` |
| 동작 | Static · 301 |
| 이동 주소 | `https://matrix.example.com/.well-known/matrix/server` |

원래 사이트에 없는 경로만 넘기므로 기존 서비스에 영향이 없습니다.
`MATRIX_HOST` 쪽은 `install.sh` 가 정적 파일로 내주도록 설정합니다.

> Synapse 의 `serve_server_wellknown: true` 는 쓰지 마세요. `SERVER_NAME:443` 을 내주기 때문에
> 똑같이 실패합니다.

### 잘 안 될 때 — 실제로 겪은 것들

| 증상 | 원인 |
| --- | --- |
| **통화 버튼은 보이는데 눌러도 아무 일 없음** | `matrix_rtc.transports` 에 `url` 만 있고 `livekit_service_url` 이 없음. Element X 26.09 는 구경로를 쓴다. 둘 다 넣을 것 |
| 통화 요청이 404 | `msc4512_enabled` 가 꺼져 있어 전달 경로가 등록되지 않음 |
| 앱서비스 설정이 무시됨 | Synapse 1.161 은 `io.element.msc4512.proxy_prefix` 처럼 접두사 붙은 키만 읽는다. 기동 로그 `Loaded application service:` 에서 `proxy_prefix: None` 인지 확인 |
| 계정 확인이 404 | Synapse listener 에 `openid` 리소스가 빠짐 |
| `relative URL without a base` | `LIVEKIT_CS_API_URL_OVERRIDES` 에 `https://` 를 안 붙임 |
| **고쳤는데도 계속 401** | `lk-jwt` 가 실패한 조회 결과를 캐시한다. `docker compose restart lk-jwt` |
| Synapse 가 기동 실패 | `livekit-appservice.yaml` 이 root 소유 600. `chown 991:991` 필요 |
| 브라우저에서 카메라·마이크가 안 잡힘 | 웹서버의 `Permissions-Policy` 가 막고 있음. 채팅/통화 호스트에는 `camera=(self), microphone=(self)` 로 |
| 통화 화면이 채팅 안에서 안 열림 | 전역 `X-Frame-Options` 때문. `CALL_HOST` 에서 해제하고 CSP `frame-ancestors` 로만 제어 |
| Element 웹에 통화 버튼이 없음 | `UIFeature.widgets` 가 `false`. 통화 화면은 위젯으로 뜬다 |
| 방화벽을 열었는데 안 통함 | `iptables -S` 의 줄번호는 `-N` 줄 때문에 어긋난다. `--line-numbers` 로 REJECT 위치를 구해 그 **앞**에 넣을 것. 그리고 **tcpdump 는 차단 전 패킷을 잡으므로 도달 확인에 쓰면 안 된다** — `nc -u -l` 로 실제 수신을 볼 것 |

### 확인 방법

```bash
# 중계 서버 목록이 보이는지 (로그인 토큰 필요)
curl -H "Authorization: Bearer $TOKEN" \
  https://matrix.example.com/_matrix/client/unstable/org.matrix.msc4143/rtc/transports

# 앱과 같은 경로로 입장권이 나오는지 → jwt 가 오면 성공
curl -X POST -H 'Content-Type: application/json' \
  -d '{"room":"!방:example.com","openid_token":{...},"device_id":"..."}' \
  https://matrix.example.com/livekit/jwt/sfu/get
```

`docker compose logs livekit` 에 `participant active ... connectionType: udp` 가 찍히면 실제로 연결된 것입니다.

### 데스크톱 앱 주의

맥·윈도우 **Element 데스크톱 앱은 자체 설정을 쓰기 때문에 통화 화면을 `call.element.io`(외부)에서
불러옵니다.** 통화 미디어는 우리 서버로 오지만 화면은 외부에서 받아옵니다.
외부 접속을 완전히 막으려면 앱 설정 파일에서 `element_call.url` 을 `CALL_HOST` 로 지정하거나,
브라우저(`CHAT_HOST`)를 쓰세요.

### 아직 안 된 것

- `templates/webserver/nginx*.conf` 에는 통화 설정이 들어 있지 않습니다 (Apache 만 실제로 검증).
- PC 브라우저 통화는 대기실이 열리는 것까지 확인했고, 실제 연결은 모바일(Element X)로만 확인했습니다.

---

## 접속 안내 페이지

`scripts/make-guide.sh` 가 QR 이 포함된 안내 페이지를 만듭니다. 접속한 기기를 판별해
**휴대폰에서는 QR 대신 바로 눌리는 링크**를, PC 에서는 QR 을 보여줍니다.

```bash
sudo ./scripts/make-guide.sh /var/www/private
```

`PRIVATE_HOST` 용 DNS 레코드와 웹서버 설정은 따로 해야 합니다.
