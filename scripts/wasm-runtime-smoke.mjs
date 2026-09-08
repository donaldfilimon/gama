import fs from "node:fs";
import { randomFillSync } from "node:crypto";

const artifact = process.argv[2];
const failedInstall = process.argv[3] === "--failed-install";

const renderedCount = (content) => {
  const match = /\bcount ([0-9]+)\b/.exec(content);
  return match === null ? null : Number.parseInt(match[1], 10);
};
const exactCounterTransition = (initial, activated) => initial === 0 && activated === 1;

// Keep the acceptance parser honest: substring checks make `count 10` look
// like `count 1`, which would allow a later multi-digit state to pass.
if (renderedCount("<span>count 0</span>") !== 0
    || renderedCount("<span>count 1</span>") !== 1
    || renderedCount("<span>count 10</span>") !== 10
    || !exactCounterTransition(0, 1)
    || exactCounterTransition(0, 10)
    || exactCounterTransition(null, 1)) {
  throw new Error("counter-state parser self-test did not enforce exact 0 -> 1");
}
if (artifact === "--self-test") {
  console.log("OK — WASM counter-state parser self-test");
  process.exit(0);
}
if (!artifact) throw new Error("usage: wasm-runtime-smoke.mjs <gama.wasm> [--failed-install] | --self-test");

let memory;
let html = "";
let output = "";
let htmlCalls = 0;
let titleCalls = 0;
let title = "";
let frameRequests = 0;
const decode = (pointer, length) =>
  new TextDecoder().decode(new Uint8Array(memory.buffer, pointer, length));

const wasi = new Proxy({
  args_get: () => 0,
  args_sizes_get(count, bytes) {
    const view = new DataView(memory.buffer);
    view.setUint32(count, 0, true); view.setUint32(bytes, 0, true);
    return 0;
  },
  environ_get: () => 0,
  environ_sizes_get(count, bytes) {
    const view = new DataView(memory.buffer);
    view.setUint32(count, 0, true); view.setUint32(bytes, 0, true);
    return 0;
  },
  clock_time_get(_clock, _precision, output) {
    new DataView(memory.buffer).setBigUint64(output, BigInt(Date.now()) * 1_000_000n, true);
    return 0;
  },
  random_get(pointer, length) {
    randomFillSync(new Uint8Array(memory.buffer, pointer, length));
    return 0;
  },
  fd_write(_fd, iovecs, count, written) {
    const view = new DataView(memory.buffer);
    let total = 0;
    for (let index = 0; index < count; index += 1) {
      const pointer = view.getUint32(iovecs + index * 8, true);
      const length = view.getUint32(iovecs + index * 8 + 4, true);
      output += decode(pointer, length);
      total += length;
    }
    view.setUint32(written, total, true);
    return 0;
  },
  proc_exit(code) { if (code !== 0) throw new Error(`proc_exit(${code})`); return 0; },
}, { get: (target, name) => target[name] ?? (() => 52) });

const imports = {
  wasi_snapshot_preview1: wasi,
  gama: {
  requestFrame() { frameRequests += 1; },
  setHTML(pointer, length) { htmlCalls += 1; html = decode(pointer, length); },
  setTitle(pointer, length) { titleCalls += 1; title = decode(pointer, length); },
  },
};

const module = await WebAssembly.compile(fs.readFileSync(artifact));
const instance = await WebAssembly.instantiate(module, imports);
memory = instance.exports.memory;

for (const name of [
  "gama_web_v1_frame", "gama_web_v1_key", "gama_web_v1_pointer", "gama_web_v1_resize",
  "gama_web_v2_frame", "gama_web_v2_key", "gama_web_v2_pointer", "gama_web_v2_resize",
]) {
  if (typeof instance.exports[name] !== "function") throw new Error(`missing export ${name}`);
}

instance.exports._start();
if (failedInstall) {
  if (!output.includes("WASM fixture: SceneConfigurationError.noPrimaryScene")) {
    throw new Error("fixture did not confirm the first install threw noPrimaryScene");
  }
  // Execute only after WASI startup and the failed first install. Calling
  // Swift exports before startup would test an uninitialized runtime instead.
  for (const tier of [1, 2]) {
    const expected = tier === 1 ? undefined : -1;
    for (const [event, args] of [
      ["frame", []],
      ["key", [7, 0, 0, 0]],
      ["key", [999, 0, 0, 0]],
      ["key", [0, 0x110000, 0, 0]],
      ["pointer", [1, 1, 1]],
      ["pointer", [1, 1, 0]],
      ["resize", [40, 8]],
    ]) {
      const name = `gama_web_v${tier}_${event}`;
      const result = instance.exports[name](...args);
      if (result !== expected) {
        throw new Error(`${name}(${args}) without a host returned ${result}; expected ${expected}`);
      }
      if (htmlCalls !== 0 || titleCalls !== 0 || frameRequests !== 0) {
        throw new Error(`${name} without a host triggered a JavaScript callback`);
      }
    }
  }
  console.log("OK — WASM failed first install; v1=void/no-op; v2=-1 including invalid keys; no host callbacks");
  process.exit(0);
}

const v1Results = [
  instance.exports.gama_web_v1_resize(40, 8),
  instance.exports.gama_web_v1_key(7, 0, 0, 0),
  instance.exports.gama_web_v1_pointer(1, 1, 1),
  instance.exports.gama_web_v1_pointer(1, 1, 0),
  instance.exports.gama_web_v1_frame(),
];
if (v1Results.some((result) => result !== undefined)) {
  throw new Error("gama_web_v1_* ABI must retain void WebAssembly results");
}

const v2Results = [
  instance.exports.gama_web_v2_resize(40, 8),
  instance.exports.gama_web_v2_key(7, 0, 0, 0),
  instance.exports.gama_web_v2_pointer(1, 1, 1),
  instance.exports.gama_web_v2_pointer(1, 1, 0),
  instance.exports.gama_web_v2_frame(),
];
if (v2Results.some((result) => result !== 0)) {
  throw new Error(`gama_web_v2_* accepted calls returned ${v2Results.join(",")}`);
}
if (instance.exports.gama_web_v2_key(999, 0, 0, 0) !== -2
    || instance.exports.gama_web_v2_key(0, 0x110000, 0, 0) !== -2) {
  throw new Error("gama_web_v2_key must reject unknown key codes and invalid Unicode scalars with -2");
}

if (title !== "Gama") throw new Error(`unexpected title: ${title}; frames=${frameRequests}; html=${html.length}`);
if (!html.includes("Gama Web")) throw new Error("rendered frame did not reach JavaScript host");
if (frameRequests < 1) throw new Error("reactor never requested a frame");

// Per-surface @Reactive state (ADR 0011) on this backend: the demo's counter
// is a component built inline on every frame. Enter activates the focused
// button, and the rebuilt frame must paint the exact 0 -> 1 transition.
const initialCount = renderedCount(html);
instance.exports.gama_web_v1_key(5, 0, 0, 0);
instance.exports.gama_web_v1_frame();
const activatedCount = renderedCount(html);
if (!exactCounterTransition(initialCount, activatedCount)) {
  throw new Error(`inline @Reactive state transition must be exactly 0 -> 1; actual=${initialCount} -> ${activatedCount}; html=${html}`);
}

console.log("OK — WASM event-to-frame runtime smoke; state=0->1");
