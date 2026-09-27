// 알림 서비스 워커 (범위: /push/)
// 푸시에는 메시지 ID·안 읽은 수만 들어 있으므로 내용 없이 "새 메시지" 알림만 표시합니다.
"use strict";

let cfgPromise;
const getCfg = () => (cfgPromise ||= fetch("/push/config.json", { cache: "no-store" })
  .then((r) => r.json())
  .catch(() => { cfgPromise = null; return { brand: "메신저" }; }));

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  let d = {};
  try { d = event.data ? event.data.json() : {}; } catch { /* 형식이 다르면 기본 알림 */ }

  event.waitUntil((async () => {
    const cfg = await getCfg();
    if (typeof d.unread === "number" && self.navigator.setAppBadge) {
      try { d.unread > 0 ? await self.navigator.setAppBadge(d.unread) : await self.navigator.clearAppBadge(); } catch { /* 미지원 */ }
    }
    // iOS 는 푸시마다 알림을 꼭 띄워야 구독이 유지됩니다
    await self.registration.showNotification(cfg.brand, {
      body: "새 메시지가 도착했습니다",
      tag: d.room_id || "message",
      renotify: true,
      icon: "/push/icon-180.png",
      data: { room_id: d.room_id || null },
    });
  })());
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const room = event.notification.data && event.notification.data.room_id;
  const url = new URL(room ? "/#/room/" + room : "/", self.location.origin).href;

  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    const win = wins.find((c) => new URL(c.url).origin === self.location.origin);
    if (win) {
      await win.focus();
      try { await win.navigate(url); } catch { /* 채팅 화면은 다른 서비스 워커 소속이라 이동 불가: 앞으로 가져오기만 */ }
      return;
    }
    await self.clients.openWindow(url);
  })());
});
