import fs from "node:fs";
import { randomFillSync } from "node:crypto";

const artifact = process.argv[2];
if (!artifact) throw new Error("usage: wasm-runtime-smoke.mjs <gama.wasm>");

let memory;
let html = "";
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
      total += view.getUint32(iovecs + index * 8 + 4, true);
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
  setHTML(pointer, length) { html = decode(pointer, length); },
  setTitle(pointer, length) { title = decode(pointer, length); },
  },
};

const module = await WebAssembly.compile(fs.readFileSync(artifact));
const instance = await WebAssembly.instantiate(module, imports);
memory = instance.exports.memory;

for (const name of ["gama_web_v1_frame", "gama_web_v1_key", "gama_web_v1_pointer", "gama_web_v1_resize"]) {
  if (typeof instance.exports[name] !== "function") throw new Error(`missing export ${name}`);
}

instance.exports._start();
instance.exports.gama_web_v1_resize(40, 8);
instance.exports.gama_web_v1_key(7, 0, 0, 0);
instance.exports.gama_web_v1_pointer(1, 1, 1);
instance.exports.gama_web_v1_pointer(1, 1, 0);
instance.exports.gama_web_v1_frame();

if (title !== "Gama") throw new Error(`unexpected title: ${title}; frames=${frameRequests}; html=${html.length}`);
if (!html.includes("Gama Web")) throw new Error("rendered frame did not reach JavaScript host");
if (frameRequests < 1) throw new Error("reactor never requested a frame");

console.log("OK — WASM event-to-frame runtime smoke");
