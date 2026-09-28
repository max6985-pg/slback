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

설치가 끝나면 **점검 스크립트**로 한 번에 확인하세요. 문제가 있으면 해결 방법을 알려 줍니다.
```bash
sudo ./scripts/check.sh
```

> ⚠ `SERVER_NAME` 은 사용자 아이디(`@hong:onepin.net`)의 일부라서 **설치 후에는 바꿀 수 없습니다.**

## 사용자 추가
비밀번호는 **12자 이상, 숫자와 영문 소문자 포함**이어야 합니다.
아이디는 **영문 소문자·숫자·`._-`** 만 쓸 수 있습니다. 한글 이름은 로그인 후 프로필의 "표시 이름"으로 설정합니다.

```bash
sudo ./scripts/add-user.sh hong            # 일반 사용자 → @hong:onepin.net
sudo ./scripts/add-user.sh kim --admin     # 관리자
```

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

## 로고·이름 바꾸기
- 이름: `.env` 의 `BRAND` 수정 후 `sudo ./install.sh`
- 로고: `element/custom/logo.svg` 파일 교체 후 `docker compose restart element`

## 운영
```bash
sudo ./scripts/check.sh           # 전체 점검 (컨테이너·주소·인증서·푸시·보안)
docker compose ps                 # 상태
docker compose logs -f synapse    # 로그
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
