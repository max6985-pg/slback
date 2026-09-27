// Cloudflare Worker: onepin.net/.well-known/matrix/* 응답
// 앱에서 "onepin.net" 만 입력해도 matrix.onepin.net 을 자동으로 찾게 해 줍니다.
// 라우트: onepin.net/.well-known/matrix/*
const MATRIX_HOST = "matrix.onepin.net";

export default {
  async fetch(request) {
    const { pathname } = new URL(request.url);
    const headers = {
      "content-type": "application/json",
      "access-control-allow-origin": "*",
    };
    if (pathname === "/.well-known/matrix/client") {
      return new Response(
        JSON.stringify({ "m.homeserver": { base_url: `https://${MATRIX_HOST}` } }),
        { headers },
      );
    }
    return new Response("{}", { status: 404, headers });
  },
};
