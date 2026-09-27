// 알림 켜기 페이지 (/push/)
// 1) 홈 화면 앱으로 실행되면 알림 상태를 확인한 뒤 채팅(/)으로 이동
// 2) 처음이면 로그인 → 알림 권한 → 웹 푸시 구독 → Synapse 에 푸셔 등록
// 알림 전용 세션은 암호화 키가 없어 메시지를 읽을 수 없고, 푸셔는 메시지 ID 만 받습니다(event_id_only).
"use strict";

(async () => {
  const STATE_KEY = "onepin-push";
  const SKIP_KEY = "onepin-push-skip";
  const SKIP_DAYS = 7;

  const $ = (id) => document.getElementById(id);
  const VIEWS = ["loading", "install", "unsupported", "login", "on", "denied"];
  const show = (v) => VIEWS.forEach((x) => { $("v-" + x).hidden = x !== v; });

  const store = {
    get(k) { try { return JSON.parse(localStorage.getItem(k)); } catch { return null; } },
    set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, JSON.stringify(v)); } catch { /* 사생활 보호 모드 등 */ } },
  };

  let st = store.get(STATE_KEY);
  const params = new URLSearchParams(location.search);
  const launchedAsApp = params.has("app");
  const goChat = () => location.replace("/");
  document.querySelectorAll("[data-go-chat]").forEach((b) => b.addEventListener("click", () => {
    if (!st) store.set(SKIP_KEY, Date.now());   // 알림을 안 켠 채 넘어가면 7일 동안 묻지 않음
    goChat();
  }));

  const ua = navigator.userAgent;
  const isIOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const standalone = matchMedia("(display-mode: standalone)").matches || navigator.standalone === true;
  const supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
  const deviceName = () => (isIOS ? "iPhone" : /Android/.test(ua) ? "Android" : "브라우저");

  if (navigator.clearAppBadge) navigator.clearAppBadge().catch(() => {});

  let cfg;
  try {
    cfg = await (await fetch("/push/config.json", { cache: "no-store" })).json();
  } catch {
    return launchedAsApp ? goChat() : show("unsupported");
  }

  if (isIOS && !standalone) return show("install");
  if (!supported) return show("unsupported");

  // ── Matrix API ────────────────────────────────────────────
  async function api(path, { token, method = "GET", body } = {}) {
    const headers = {};
    if (token) headers.Authorization = "Bearer " + token;
    if (body) headers["Content-Type"] = "application/json";
    const r = await fetch(cfg.homeserver + "/_matrix/client/v3" + path, {
      method, headers, body: body ? JSON.stringify(body) : undefined,
      referrerPolicy: "no-referrer", credentials: "omit", cache: "no-store",
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const e = new Error(data.error || "HTTP " + r.status);
      e.status = r.status;
      e.code = data.errcode;
      throw e;
    }
    return data;
  }

  // ── 웹 푸시 구독 ───────────────────────────────────────────
  const b64uToBytes = (s) => {
    const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4));
    return Uint8Array.from(b, (c) => c.charCodeAt(0));
  };
  const bytesToB64u = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

  await navigator.serviceWorker.register("/push/sw.js", { scope: "/push/" });
  const reg = await navigator.serviceWorker.ready;

  async function subscribe() {
    let sub = await reg.pushManager.getSubscription();
    // 서버 VAPID 키가 바뀌었으면 새로 구독
    const key = sub && sub.options && sub.options.applicationServerKey;
    if (sub && key && bytesToB64u(key) !== cfg.vapidPublicKey) {
      await sub.unsubscribe();
      sub = null;
    }
    if (!sub) {
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: b64uToBytes(cfg.vapidPublicKey),
      });
    }
    return sub;
  }

  function setPusher(token, sub) {
    const j = sub.toJSON();
    return api("/pushers/set", {
      token, method: "POST",
      body: {
        kind: "http",
        app_id: cfg.appId,
        pushkey: j.keys.p256dh,
        app_display_name: cfg.brand,
        device_display_name: deviceName(),
        lang: "ko",
        append: false,
        data: {
          url: cfg.gatewayUrl,
          format: "event_id_only",   // 내용·보낸 사람 없이 메시지 ID 만
          endpoint: j.endpoint,
          auth: j.keys.auth,
          events_only: true,
          only_last_per_room: true,
        },
      },
    });
  }

  function showOn(st) {
    $("t-on").textContent = st.userId + " 계정의 새 메시지를 이 기기(" + deviceName() + ")로 알려 드립니다.";
    show("on");
  }

  // ── 시작: 이미 켜져 있으면 상태 점검 후 채팅으로 ─────────────
  if (Notification.permission === "denied") {
    return launchedAsApp && store.get(SKIP_KEY) ? goChat() : show("denied");
  }
  if (st && Notification.permission === "granted") {
    try {
      await api("/account/whoami", { token: st.token });
      const sub = await subscribe();
      const { pushers = [] } = await api("/pushers", { token: st.token });
      const p256dh = sub.toJSON().keys.p256dh;
      if (sub.endpoint !== st.endpoint || !pushers.some((p) => p.pushkey === p256dh && p.app_id === cfg.appId)) {
        await setPusher(st.token, sub);
        st.endpoint = sub.endpoint;
        store.set(STATE_KEY, st);
      }
      return launchedAsApp ? goChat() : showOn(st);
    } catch (e) {
      if (e.status === 401) {          // 세션이 로그아웃됨 → 다시 로그인
        store.set(STATE_KEY, null);
        st = null;
      } else {                         // 네트워크 문제 등: 채팅은 계속 쓸 수 있게
        return launchedAsApp ? goChat() : showOn(st);
      }
    }
  }

  const skippedAt = store.get(SKIP_KEY);
  if (launchedAsApp && skippedAt && Date.now() - skippedAt < SKIP_DAYS * 864e5) return goChat();
  show("login");

  // ── 로그인 → 알림 켜기 ──────────────────────────────────────
  const msg = (el, text, err) => { el.textContent = text; el.classList.toggle("err", !!err); };

  $("f-login").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const btn = $("b-login");
    const m = $("m-login");
    btn.disabled = true;
    msg(m, "");
    let token = null;
    try {
      // iOS 는 버튼을 누른 직후에만 권한 요청이 가능하므로 가장 먼저 호출
      const perm = await Notification.requestPermission();
      if (perm !== "granted") return show("denied");

      msg(m, "로그인 중…");
      const res = await api("/login", {
        method: "POST",
        body: {
          type: "m.login.password",
          identifier: { type: "m.id.user", user: $("i-user").value.trim() },
          password: $("i-pass").value,
          initial_device_display_name: cfg.brand + " 알림 전용 (" + deviceName() + ")",
        },
      });
      token = res.access_token;
      $("i-pass").value = "";

      msg(m, "알림 등록 중…");
      const sub = await subscribe();
      await setPusher(token, sub);

      st = { token, userId: res.user_id, deviceId: res.device_id, endpoint: sub.endpoint };
      store.set(STATE_KEY, st);
      store.set(SKIP_KEY, null);
      token = null;
      if (launchedAsApp) return goChat();
      showOn(st);
    } catch (e) {
      if (token) api("/logout", { token, method: "POST", body: {} }).catch(() => {});
      const text = e.code === "M_FORBIDDEN" ? "아이디 또는 비밀번호가 맞지 않습니다."
        : e.code === "M_LIMIT_EXCEEDED" ? "시도가 너무 많습니다. 잠시 후 다시 해 주세요."
        : "알림을 켜지 못했습니다: " + e.message;
      msg(m, text, true);
    } finally {
      btn.disabled = false;
    }
  });

  // ── 알림 끄기: 푸셔 삭제 + 알림 전용 세션 로그아웃 + 구독 해제 ──
  $("b-off").addEventListener("click", async () => {
    const m = $("m-on");
    $("b-off").disabled = true;
    msg(m, "끄는 중…");
    try {
      const sub = await reg.pushManager.getSubscription();
      if (st && st.token) {
        if (sub) await api("/pushers/set", { token: st.token, method: "POST",
          body: { kind: null, app_id: cfg.appId, pushkey: sub.toJSON().keys.p256dh } }).catch(() => {});
        await api("/logout", { token: st.token, method: "POST", body: {} }).catch(() => {});
      }
      if (sub) await sub.unsubscribe();
    } finally {
      store.set(STATE_KEY, null);
      st = null;
      $("b-off").disabled = false;
      msg(m, "");
      show("login");
    }
  });
})();
