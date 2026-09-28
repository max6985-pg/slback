# mautrix-telegram 설정 적용 (install.sh 가 브릿지 컨테이너 안에서 실행)
# 공식 예제 설정(/data/config.yaml)을 읽어 필요한 값만 바꿉니다.
import os
from ruamel.yaml import YAML

PATH = "/data/config.yaml"
env = os.environ
yaml = YAML()
yaml.preserve_quotes = True
with open(PATH) as f:
    cfg = yaml.load(f)


def put(path, value):
    node = cfg
    keys = path.split(".")
    for k in keys[:-1]:
        if node.get(k) is None:
            node[k] = {}
        node = node[k]
    node[keys[-1]] = value


server = env["SERVER_NAME"]
admin = f"@{env['ADMIN_USER']}:{server}"

put("homeserver.address", "http://synapse:8008")
put("homeserver.domain", server)
put("homeserver.software", "standard")

put("appservice.address", "http://mautrix-telegram:29317")
put("appservice.hostname", "0.0.0.0")
put("appservice.port", 29317)
put("appservice.database",
    f"postgres://synapse:{env['POSTGRES_PASSWORD']}@postgres/telegram")
put("appservice.id", "telegram")
put("appservice.bot_username", "telegrambot")
put("appservice.bot_displayname", "Telegram 브릿지")

# 텔레그램 쪽 사람은 "(Telegram)" 이 붙어 우리 사용자와 구분됩니다
put("bridge.username_template", "telegram_{userid}")
put("bridge.displayname_template", "{displayname} (Telegram)")

# 우리 서버는 새 방을 기본 암호화하므로 브릿지도 암호화를 지원해야 합니다
put("bridge.encryption.allow", True)
put("bridge.encryption.default", True)
put("bridge.encryption.require", False)

# 릴레이 봇: 텔레그램 단체방에 넣은 봇이 메시지를 대신 전달
put("bridge.relaybot.authless_portals", True)
put("bridge.relaybot.whitelist_group_admins", True)
put("bridge.relaybot.private_chat.invite", [])

# 권한: 관리자만 브릿지 관리, 일반 사용자는 릴레이만 (PUPPETING=on 이면 개인 계정 로그인 허용)
perms = cfg["bridge"].get("permissions")
if perms is None:
    perms = cfg["bridge"]["permissions"] = {}
perms.clear()
perms[server] = "full" if env.get("TELEGRAM_PUPPETING") == "on" else "relaybot"
perms[admin] = "admin"

put("telegram.api_id", int(env["TELEGRAM_API_ID"]))
put("telegram.api_hash", env["TELEGRAM_API_HASH"])
put("telegram.bot_token", env["TELEGRAM_BOT_TOKEN"])

with open(PATH, "w") as f:
    yaml.dump(cfg, f)
print("mautrix-telegram 설정 적용 완료")
