# onepin 비공개 메신저

Matrix(Synapse) 서버와 Element 웹으로 만든, **우리끼리만 쓰는 메신저**입니다.

- 가입이 막혀 있어서 관리자가 만든 계정만 쓸 수 있습니다
- 다른 Matrix 서버와 연결하지 않습니다 (federation 차단)
- 새 대화방은 기본으로 종단간 암호화됩니다
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
Cloudflare 대시보드 → onepin.net → **DNS → Records** 에서 두 개를 추가합니다.

| Type | Name | IPv4 address | Proxy status |
|---|---|---|---|
| A | `matrix` | 서버 IP | **DNS only (회색 구름)** |
| A | `chat` | 서버 IP | **DNS only (회색 구름)** |

- **회색 구름(DNS only)을 권장**합니다. 주황 구름(프록시)을 켜면 인증서 발급이 실패하거나,
  무료 요금제는 업로드가 100MB 로 제한됩니다.
- 설치 후 꼭 주황 구름을 쓰고 싶다면: SSL/TLS 모드를 **Full (strict)** 로 두고, `.env` 의 `MAX_UPLOAD_SIZE` 를 100M 이하로 유지하세요.
- CMS(`cms.onepin.net`) 레코드는 건드리지 않습니다.

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
5. Let's Encrypt HTTPS 인증서 발급
6. 관리자 계정 생성

> ⚠ `SERVER_NAME` 은 사용자 아이디(`@hong:onepin.net`)의 일부라서 **설치 후에는 바꿀 수 없습니다.**

## 사용자 추가
아이디는 **영문 소문자·숫자·`._-`** 만 쓸 수 있습니다. 한글 이름은 로그인 후 프로필의 "표시 이름"으로 설정합니다.

```bash
sudo ./scripts/add-user.sh hong            # 일반 사용자 → @hong:onepin.net
sudo ./scripts/add-user.sh kim --admin     # 관리자
```

## 휴대폰 (아이폰·안드로이드)
1. App Store / Play 스토어에서 **Element X** 설치
2. "서버 변경" → `onepin.net` 입력 (또는 `matrix.onepin.net`)
3. 받은 아이디·비밀번호로 로그인

`onepin.net` 만 입력하려면 위의 **Cloudflare Worker** 설정이 필요합니다.

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
docker compose ps                 # 상태
docker compose logs -f synapse    # 로그
docker compose pull && docker compose up -d   # 업데이트
```

**백업 대상**: `messenger/.env` 와 `messenger/data/` 폴더 전체
(DB 는 `docker compose exec postgres pg_dump -U synapse synapse > backup.sql` 로도 백업 가능)

## 참고
- 영상·음성 통화를 쓰려면 TURN 서버(coturn)를 추가로 설치해야 합니다
- Synapse·Element 는 AGPL-3.0 라이선스입니다. 내부 사용은 문제없습니다
