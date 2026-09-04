import { spawn } from "node:child_process";
import { createReadStream, existsSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";

const artifact = process.argv[2];
const successMarker = /^OK;frames=[1-9]\d*;keys=[2-9]\d*;pointers=[2-9]\d*;resizes=[1-9]\d*;rendered=true;accessible=true;state=0->0->1$/;

// Pin the exact state sequence. In particular, a later multi-digit state of
// 10 must not satisfy the expected final state of 1.
const markerExample = "OK;frames=1;keys=2;pointers=2;resizes=1;rendered=true;accessible=true;state=0->0->1";
if (!successMarker.test(markerExample)
    || successMarker.test(markerExample.replace("state=0->0->1", "state=0->1->1"))
    || successMarker.test(markerExample.replace(/1$/, "10"))) {
  throw new Error("browser state-marker parser self-test did not enforce exact 0->0->1");
}
if (artifact === "--self-test") {
  console.log("OK — browser state-marker parser self-test");
  process.exit(0);
}
const root = process.argv[3];
const expectedTitle = process.argv[4];
if (!artifact || !root) {
  throw new Error("usage: browser-runtime-smoke.mjs <gama.wasm> <WebHost> | --self-test");
}

const chromeCandidates = [
  process.env.CHROME_BIN,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter(Boolean);
const chrome = chromeCandidates.find(existsSync);
if (!chrome) throw new Error("Chrome/Chromium is required for the browser runtime gate");

const mime = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".wasm", "application/wasm"],
]);
const server = createServer((request, response) => {
  const pathname = new URL(request.url, "http://127.0.0.1").pathname;
  const file = pathname === "/gama-web-demo.wasm"
    ? artifact
    : join(root, pathname === "/" ? "index.html" : pathname.slice(1));
  if (!existsSync(file)) {
    response.writeHead(404).end("not found");
    return;
  }
  response.setHeader("Content-Type", mime.get(extname(file)) ?? "application/octet-stream");
  createReadStream(file).pipe(response);
});

await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();
// Chrome otherwise may hand this invocation to an already-running interactive
// browser. A private profile makes the smoke deterministic and isolates it
// from extensions, policies, caches, and allocator state in that process.
const profile = mkdtempSync(join(tmpdir(), "gama-chrome-"));
const child = spawn(chrome, [
  "--headless=new", "--disable-gpu", "--no-sandbox", "--disable-extensions",
  "--disable-background-networking", "--no-first-run",
  `--user-data-dir=${profile}`, "--remote-debugging-port=0", "about:blank",
], { stdio: ["ignore", "ignore", "pipe"] });
let errors = "";
child.stderr.on("data", (chunk) => { errors += chunk; });
const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
let socket;
let marker = "";
let pageTitle = "";
const runtimeErrors = [];
try {
  const activePort = join(profile, "DevToolsActivePort");
  for (let attempt = 0; attempt < 150 && !existsSync(activePort); attempt += 1) await delay(100);
  if (!existsSync(activePort)) throw new Error(`Chrome DevTools endpoint did not start: ${errors}`);
  const debugPort = (await import("node:fs/promises")).readFile(activePort, "utf8")
    .then((contents) => contents.split("\n", 1)[0]);
  const target = await fetch(
    `http://127.0.0.1:${await debugPort}/json/new?${encodeURIComponent("about:blank")}`,
    { method: "PUT" },
  ).then((response) => response.json());
  socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  let nextID = 1;
  const pending = new Map();
  socket.addEventListener("message", (event) => {
    const message = JSON.parse(event.data);
    if (message.method === "Runtime.exceptionThrown") {
      runtimeErrors.push(message.params?.exceptionDetails?.exception?.description
        ?? message.params?.exceptionDetails?.text ?? "unknown exception");
    }
    const continuation = pending.get(message.id);
    if (continuation) { pending.delete(message.id); continuation(message); }
  });
  const command = (method, params = {}) => new Promise((resolve) => {
    const id = nextID++;
    pending.set(id, resolve);
    socket.send(JSON.stringify({ id, method, params }));
  });
  await command("Runtime.enable");
  await command("Page.enable");
  await command("Page.navigate", { url: `http://127.0.0.1:${port}/?gama-smoke=1` });
  for (let attempt = 0; attempt < 150; attempt += 1) {
    const result = await command("Runtime.evaluate", {
      expression: "document.getElementById('gama')?.dataset.gamaSmoke || ''",
      returnByValue: true,
    });
    marker = result.result?.result?.value ?? "";
    if (successMarker.test(marker)) break;
    await delay(100);
  }
  const titleResult = await command("Runtime.evaluate", {
    expression: "document.title",
    returnByValue: true,
  });
  pageTitle = titleResult.result?.result?.value ?? "";
} finally {
  socket?.close();
  const closed = new Promise((resolve) => child.once("close", resolve));
  child.kill();
  await Promise.race([closed, delay(3000)]);
  server.close();
  rmSync(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
if (!successMarker.test(marker)) {
  throw new Error(`browser event/frame/accessibility/state marker missing (state must be exactly 0->0->1, with only Enter activating the inline counter); marker=${marker}; runtime=${runtimeErrors.join(" | ")}; stderr=${errors}`);
}
if (expectedTitle !== undefined && pageTitle !== expectedTitle) {
  throw new Error(`browser title mismatch; expected=${expectedTitle}; actual=${pageTitle}`);
}
console.log("OK — browser DOM, keyboard, pointer, resize, rAF, accessibility, and WASM frame smoke");
