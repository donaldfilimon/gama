import { spawn } from "node:child_process";
import { createReadStream, existsSync, mkdtempSync, rmSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { extname, join } from "node:path";

// Flags are separated from positionals so `--failed-install` can sit anywhere
// without shifting the optional expected-title argument bundle-web.sh passes.
const args = process.argv.slice(2);
const failedInstall = args.includes("--failed-install");
const positional = args.filter((arg) => arg === "--self-test" || !arg.startsWith("--"));
const artifact = positional[0];
const successMarker = /^OK;frames=[1-9]\d*;keys=[2-9]\d*;pointers=[2-9]\d*;resizes=[1-9]\d*;rendered=true;accessible=true;state=0->0->1$/;

// Pin the exact state sequence. In particular, a later multi-digit state of
// 10 must not satisfy the expected final state of 1.
const markerExample = "OK;frames=1;keys=2;pointers=2;resizes=1;rendered=true;accessible=true;state=0->0->1";
if (!successMarker.test(markerExample)
    || successMarker.test(markerExample.replace("state=0->0->1", "state=0->1->1"))
    || successMarker.test(markerExample.replace(/1$/, "10"))) {
  throw new Error("browser state-marker parser self-test did not enforce exact 0->0->1");
}
// --failed-install serves a module whose only install throws. A v2 host must
// read the -1 from its first export call and name the failure on the surface;
// a v1 host has no status to read and would sit on its boot overlay, so this
// is the check that the page actually consumes the v2 tier.
const failedInstallReported = (state) => state.failure === "install"
  && state.status === "failed"
  && state.text.includes("no Gama host is installed");
const reportedExample = { failure: "install", status: "failed", text: "gama_web_v2_resize returned -1: no Gama host is installed." };
if (!failedInstallReported(reportedExample)
    || failedInstallReported({ ...reportedExample, failure: "first frame" })
    || failedInstallReported({ ...reportedExample, status: "loading" })
    || failedInstallReported({ ...reportedExample, text: "" })) {
  throw new Error("failed-install parser self-test did not require stage, status, and host diagnosis together");
}
if (artifact === "--self-test") {
  console.log("OK — browser state-marker and failed-install parser self-tests");
  process.exit(0);
}
const root = positional[1];
const expectedTitle = positional[2];
if (!artifact || !root) {
  throw new Error("usage: browser-runtime-smoke.mjs <gama.wasm> <WebHost> [title] [--failed-install] | --self-test");
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
// Without these two listeners a launch failure is indistinguishable from a
// slow start: `spawn` reports ENOENT/EACCES through an `error` event, and a
// browser that dies on startup can exit before writing a byte to stderr, so
// the wait below would otherwise time out carrying an empty diagnostic.
let spawnError = "";
child.on("error", (error) => { spawnError = error.message; });
let exit = null;
child.on("exit", (code, signal) => { exit = { code, signal }; });
const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
let socket;
let marker = "";
let failureState = { failure: "", status: "", text: "" };
let pageTitle = "";
let preBootInput = "";
const runtimeErrors = [];
try {
  const activePort = join(profile, "DevToolsActivePort");
  // Startup budget, not a proof budget. A hosted runner measured Chrome alive
  // and retrying `dbus/bus.cc` connections for the whole of a 15s window
  // without ever publishing the endpoint, so 15s failed a browser that was
  // still coming up. Every assertion below is unchanged: this waits longer
  // for a live browser and gives up immediately on a dead one, which fails a
  // genuinely broken browser sooner than the old fixed wait did.
  const startupBudgetMs = 60_000;
  const deadline = Date.now() + startupBudgetMs;
  while (!existsSync(activePort) && exit === null && !spawnError && Date.now() < deadline) {
    await delay(100);
  }
  if (!existsSync(activePort)) {
    const waited = `${((startupBudgetMs - Math.max(deadline - Date.now(), 0)) / 1000).toFixed(1)}s`;
    const cause = [
      `binary=${chrome}`,
      spawnError ? `spawn=${spawnError}` : null,
      exit ? `exited early: code=${exit.code} signal=${exit.signal}` : spawnError ? null : "still running",
      `stderr=${errors.trim() || "<empty>"}`,
    ].filter(Boolean).join("; ");
    throw new Error(`Chrome DevTools endpoint did not start after ${waited}: ${cause}`);
  }
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
  // Real users click and type while a multi-megabyte module is still loading.
  // Fire input at the moment `WebAssembly.instantiate` is called, before the
  // host has any exports, and mark that it happened. Pre-boot input must be
  // dropped: it may not activate anything (the pinned 0->0->1 sequence still
  // has to hold) and it may not poison the host into ignoring later input.
  await command("Page.addScriptToEvaluateOnNewDocument", {
    source: `(() => {
      const instantiate = WebAssembly.instantiate;
      WebAssembly.instantiate = function (...args) {
        const surface = document.getElementById("gama");
        if (surface) {
          const init = { bubbles: true, cancelable: true };
          surface.dispatchEvent(new KeyboardEvent("keydown", { ...init, key: "Enter" }));
          surface.dispatchEvent(new MouseEvent("mousedown", init));
          surface.dispatchEvent(new MouseEvent("mouseup", init));
          surface.dataset.gamaPreBootInput = "sent";
        }
        return instantiate.apply(this, args);
      };
    })();`,
  });
  await command("Page.navigate", {
    url: `http://127.0.0.1:${port}/${failedInstall ? "" : "?gama-smoke=1"}`,
  });
  for (let attempt = 0; failedInstall && attempt < 150; attempt += 1) {
    const result = await command("Runtime.evaluate", {
      expression: `JSON.stringify({
        failure: document.getElementById('gama')?.dataset.gamaFailure || '',
        status: document.getElementById('status')?.dataset.state || '',
        text: document.getElementById('fatal')?.textContent || '',
      })`,
      returnByValue: true,
    });
    failureState = JSON.parse(result.result?.result?.value ?? "{}");
    if (failedInstallReported(failureState)) break;
    await delay(100);
  }
  for (let attempt = 0; !failedInstall && attempt < 150; attempt += 1) {
    const result = await command("Runtime.evaluate", {
      expression: "document.getElementById('gama')?.dataset.gamaSmoke || ''",
      returnByValue: true,
    });
    marker = result.result?.result?.value ?? "";
    if (successMarker.test(marker)) break;
    await delay(100);
  }
  const preBoot = await command("Runtime.evaluate", {
    expression: "document.getElementById('gama')?.dataset.gamaPreBootInput || ''",
    returnByValue: true,
  });
  preBootInput = preBoot.result?.result?.value ?? "";
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
if (preBootInput !== "sent") {
  throw new Error(`pre-boot input was never injected, so the load-time path went unexercised; marker=${preBootInput || "<empty>"}`);
}
if (failedInstall) {
  if (!failedInstallReported(failureState)) {
    throw new Error(`failed install was not reported through the v2 tier; state=${JSON.stringify(failureState)}; runtime=${runtimeErrors.join(" | ")}; stderr=${errors}`);
  }
  console.log(`OK — browser names a failed install from the v2 status (stage=${failureState.failure})`);
  process.exit(0);
}
if (!successMarker.test(marker)) {
  throw new Error(`browser event/frame/accessibility/state marker missing (state must be exactly 0->0->1, with only Enter activating the inline counter); marker=${marker}; runtime=${runtimeErrors.join(" | ")}; stderr=${errors}`);
}
if (expectedTitle !== undefined && pageTitle !== expectedTitle) {
  throw new Error(`browser title mismatch; expected=${expectedTitle}; actual=${pageTitle}`);
}
console.log("OK — browser DOM, keyboard, pointer, resize, rAF, accessibility, WASM frame, and pre-boot input smoke");
