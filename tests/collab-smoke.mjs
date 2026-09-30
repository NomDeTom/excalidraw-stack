// Collaboration tripwire: two clients join one room through the given origin, one
// broadcasts, the other must receive it. Exercises the relay, the reverse proxy's
// /socket.io/ route and the socket.io protocol version -- the parts that break silently.
// Not a UI test.
//
//   npm install && node collab-smoke.mjs http://localhost:3000     # the stack
//   node collab-smoke.mjs http://<hub address>                      # a hub with --with-collab
import { io } from "socket.io-client";

const origin = process.argv[2] || "http://localhost:3000";
const room = `smoke-${Date.now()}`;
const payload = new Uint8Array([1, 2, 3, 4]);
const fail = (msg) => {
  console.error(`FAIL: ${msg}`);
  process.exit(1);
};
setTimeout(() => fail(`no relay through ${origin}/socket.io/ within 10 s`), 10000);

const join = () =>
  new Promise((resolve, reject) => {
    const s = io(origin, { transports: ["websocket", "polling"], reconnection: false });
    s.on("connect_error", (e) => reject(e));
    s.on("init-room", () => s.emit("join-room", room));
    s.on("first-in-room", () => resolve(s));
    s.on("room-user-change", () => resolve(s));
  });

const a = await join().catch((e) => fail(`connect: ${e.message}`));
const b = await join().catch((e) => fail(`connect: ${e.message}`));
b.on("client-broadcast", (data) => {
  const got = new Uint8Array(data);
  if (got.length !== payload.length || got.some((v, i) => v !== payload[i])) {
    fail("payload arrived altered");
  }
  console.log(`ok: relay through ${origin}/socket.io/ (room ${room})`);
  a.close();
  b.close();
  process.exit(0);
});
setTimeout(() => a.emit("server-broadcast", room, payload, new Uint8Array(12)), 300);
