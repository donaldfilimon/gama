// gama.js — browser host for a Gama WASM reactor module.
// Instantiates gama-web-demo.wasm with WASI stubs + the "gama" import module,
// then forwards DOM events into the exported gama_web_v2_* entry points, and
// Pointer Events into the v3 pointer tier (ADR 0018).
//
// Uses the v2 export tier for frames, keys and resizes, and
// gama_web_v3_pointer_event for every pointer sample; never v1. v2 is
// argument-compatible with v1 but returns
// a status: 0 accepted, -1 no host installed, -2 invalid input
// (docs/backends/WASM.md). The status matters here because the demo installs
// with `try?`: a failed install is silent inside the module, v1 calls then
// no-op forever, and the page would sit on its boot overlay. v2 reports -1 on
// the very first call, which is what turns that into a named failure.
// v3 keeps the same statuses. scripts/check-wasm.sh requires the three v2
// calls and the v3 pointer call, and rejects any v1 call.

const root = document.getElementById("gama");
const boot = document.getElementById("boot");
const fatal = document.getElementById("fatal");
const statusRow = document.getElementById("status");
const statusText = document.getElementById("status-text");
const configuredTitle = document.title;
let memory = null;
let exports = null;
let framePending = false;
let booted = false;
// `ready` flips only when boot has fully succeeded, and input before that is
// dropped: a click during a multi-megabyte load would otherwise reach a
// module with no exports yet, and `guarded` would read the resulting
// TypeError as a lost host and leave a page that says ready but ignores
// everything. `dead` is set once the host is gone for good, and every
// listener checks it, so a failure is reported once, not per keystroke.
let ready = false;
let dead = false;
let warnedRejectedKey = false;
const smoke = { frames: 0, keys: 0, pointers: 0, resizes: 0 };
let grid = { cols: 0, rows: 0 };

const utf8 = new TextDecoder("utf-8");
const str = (ptr, len) => utf8.decode(new Uint8Array(memory.buffer, ptr, len));
let wasiText = "";

// The shell is optional: the smoke serves this same file, and a future host
// page may drop the chrome entirely, so every element above is addressed
// defensively rather than assumed present.
function setStatus(state, text) {
  // A reported failure is final; a frame or resize that lands afterwards must
  // not paint the status line back to ready.
  if (dead && state !== "failed") return;
  if (statusRow) statusRow.dataset.state = state;
  if (statusText) statusText.textContent = text;
}

// A machine-readable failure marker on the surface itself, so a driver can
// read it without depending on the page shell around it.
function showFatal(stage, error) {
  root.dataset.gamaFailure = stage;
  setStatus("failed", `failed during ${stage}`);
  boot?.setAttribute("hidden", "");
  if (!fatal) return;
  fatal.textContent = "";
  const heading = document.createElement("b");
  heading.textContent = `Gama failed to start during ${stage}.`;
  fatal.append(heading, document.createTextNode(String(error?.stack || error)));
  fatal.removeAttribute("hidden");
}

// ── v2 status handling ─────────────────────────────────────────────────
class HostMissing extends Error {}

// Every export result passes through here: an integer compare per call, and
// work only on the rare non-zero result. -2 is returned to the caller, which
// is the only one that knows what an invalid input means for its event.
function checked(result, name) {
  if (result === 0 || result === -2) return result;
  if (result === -1) {
    const output = wasiText.trim();
    throw new HostMissing(
      `${name} returned -1: no Gama host is installed.`
      + (output ? `\nmodule output: ${output}` : ""),
    );
  }
  throw new Error(`${name} returned unexpected status ${result}`);
}

// After boot, a host that reports -1 was installed and then lost, which is an
// invariant break rather than a user error: surface it once, then stop.
function guarded(work) {
  if (dead) return undefined;
  try {
    return work();
  } catch (error) {
    dead = true;
    showFatal(error instanceof HostMissing ? "host lost" : "event handling", error);
    throw error;
  }
}

// ── Imports the module expects (module "gama") ─────────────────────────
const gamaImports = {
  setHTML(ptr, len) {
    root.innerHTML = str(ptr, len);
    root.setAttribute("aria-label", root.innerText.trim() || "Gama application");
    smoke.frames += 1;
    if (!booted) {
      booted = true;
      boot?.setAttribute("hidden", "");
      setStatus("ready", `ready · ${grid.cols}×${grid.rows} cells · wasm32`);
    }
  },
  setTitle(ptr, len) { document.title = configuredTitle || str(ptr, len); },
  requestFrame() {
    if (framePending) return;
    framePending = true;
    requestAnimationFrame(() => {
      framePending = false;
      guarded(() => checked(exports.gama_web_v2_frame(), "gama_web_v2_frame"));
    });
  },
};

// Minimal WASI shims — enough for a reactor that never touches the FS.
const wasiStubs = new Proxy({
  fd_write: (_fd, iovecs, count, written) => {
    const view = new DataView(memory.buffer);
    let bytesWritten = 0;
    for (let index = 0; index < count; index += 1) {
      const pointer = view.getUint32(iovecs + index * 8, true);
      const length = view.getUint32(iovecs + index * 8 + 4, true);
      wasiText += str(pointer, length);
      bytesWritten += length;
    }
    view.setUint32(written, bytesWritten, true);
    return 0;
  },
  fd_close: () => 8, fd_seek: () => 8, fd_fdstat_get: () => 8,
  environ_get: () => 0, environ_sizes_get: (count, bytes) => {
    const view = new DataView(memory.buffer);
    view.setUint32(count, 0, true); view.setUint32(bytes, 0, true);
    return 0;
  },
  args_get: () => 0, args_sizes_get: (count, bytes) => {
    const view = new DataView(memory.buffer);
    view.setUint32(count, 0, true); view.setUint32(bytes, 0, true);
    return 0;
  },
  clock_time_get: (_clock, _precision, output) => {
    const nanos = BigInt(Date.now()) * 1_000_000n;
    new DataView(memory.buffer).setBigUint64(output, nanos, true);
    return 0;
  },
  random_get: (pointer, length) => {
    const destination = new Uint8Array(memory.buffer, pointer, length);
    for (let offset = 0; offset < length; offset += 65536) {
      const chunk = destination.subarray(offset, Math.min(length, offset + 65536));
      crypto.getRandomValues(chunk);
    }
    return 0;
  },
  // WASI command modules call proc_exit after `main`; a browser reactor keeps
  // its instance alive so exported event functions remain callable.
  proc_exit: (code) => {
    if (code !== 0) throw new Error(`proc_exit(${code}): ${wasiText}`);
    return 0;
  },
}, {
  // Unknown imports are unsupported, never silently successful.
  get(target, name) { return target[name] ?? (() => 52); },
});

// ── Cell metrics, padding, and resize ──────────────────────────────────
// The surface's own padding is part of the pointer mapping and of the usable
// area. Reading it back instead of hardcoding it keeps a CSS edit from
// silently shifting every click by a cell.
function surfacePadding() {
  const style = getComputedStyle(root);
  return {
    left: parseFloat(style.paddingLeft) || 0,
    top: parseFloat(style.paddingTop) || 0,
    right: parseFloat(style.paddingRight) || 0,
    bottom: parseFloat(style.paddingBottom) || 0,
  };
}

function cellMetrics() {
  const probe = document.createElement("pre");
  probe.className = "gama-row";
  // Ten columns, then divide: one glyph's subpixel advance rounds badly at
  // this size, and a width that is off by a fraction of a pixel compounds
  // into a whole column of drift across an 80-column grid.
  probe.textContent = "MMMMMMMMMM";
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.pointerEvents = "none";
  root.appendChild(probe);
  const r = probe.getBoundingClientRect();
  root.removeChild(probe);
  return { w: (r.width / 10) || 8, h: r.height || 17 };
}
let cell = { w: 8, h: 17 };

function notifyResize() {
  const pad = surfacePadding();
  // clientWidth/clientHeight include padding, so subtract it to get the
  // area the grid can actually paint into.
  const usableWidth = root.clientWidth - pad.left - pad.right;
  const usableHeight = root.clientHeight - pad.top - pad.bottom;
  const cols = Math.max(1, Math.floor(usableWidth / cell.w));
  const rows = Math.max(1, Math.floor(usableHeight / cell.h));
  if (cols === grid.cols && rows === grid.rows) return;
  grid = { cols, rows };
  checked(exports.gama_web_v2_resize(cols, rows), "gama_web_v2_resize");
  smoke.resizes += 1;
  if (booted) setStatus("ready", `ready · ${cols}×${rows} cells · wasm32`);
}

// ── Keyboard: DOM → Gama key codes ─────────────────────────────────────
// 1=up 2=down 3=left 4=right 5=enter 6=escape 7=tab 8=backspace
// 9=delete 10=home 11=end 12=pageUp 13=pageDown 100+n=Fn 0=printable
const keyCodes = {
  ArrowUp: 1, ArrowDown: 2, ArrowLeft: 3, ArrowRight: 4,
  Enter: 5, Escape: 6, Tab: 7, Backspace: 8, Delete: 9,
  Home: 10, End: 11, PageUp: 12, PageDown: 13,
};

root.addEventListener("keydown", (e) => {
  if (dead || !ready) return;
  let code = keyCodes[e.key] ?? 0;
  if (code === 0 && /^F(\d{1,2})$/.test(e.key)) {
    code = 99 + Number(e.key.slice(1));
  }
  let ch = 0;
  if (code === 0) {
    if (e.key.length !== 1) return;          // unmapped special key
    ch = e.key.codePointAt(0);
  }
  const status = guarded(() => checked(
    exports.gama_web_v2_key(code, ch, e.shiftKey ? 1 : 0, e.ctrlKey ? 1 : 0),
    "gama_web_v2_key",
  ));
  // -2 means Gama did not take the key (F14 and up, or a lone surrogate), so
  // leave it to the browser instead of swallowing it. preventDefault therefore
  // runs after the call, not before it. Warn once; a keypress is not an error
  // worth putting on the page.
  if (status === -2) {
    if (!warnedRejectedKey) {
      warnedRejectedKey = true;
      console.warn(`Gama did not accept key ${JSON.stringify(e.key)}; leaving it to the browser`);
    }
    return;
  }
  e.preventDefault();
  smoke.keys += 1;
});

// ── Pointer: Pointer Events → v3 samples (ADR 0018) ────────────────────
// The page only translates; Gama recognizes taps, drags, long presses, hover
// and scroll. Codes are the wire tables GamaEmbed.h names GAMA_EMBED_POINTER_*.
const PHASE = { down: 0, move: 1, up: 2, cancel: 3, hover: 4, scroll: 5, stationary: 6 };
const KIND = { mouse: 0, touch: 1, pen: 2 };
// DOM numbers the middle button 1 and the right button 2; Gama numbers the
// secondary (right) button 1 and the middle button 2.
const BUTTON = { 0: 0, 1: 2, 2: 1 };
function modifierBits(e) {
  return (e.shiftKey ? 1 : 0) | (e.ctrlKey ? 2 : 0) | (e.altKey ? 4 : 0) | (e.metaKey ? 8 : 0);
}
function gridPos(e) {
  const r = root.getBoundingClientRect();
  const pad = surfacePadding();
  return {
    col: Math.floor((e.clientX - r.left - pad.left) / cell.w),
    row: Math.floor((e.clientY - r.top - pad.top) / cell.h),
  };
}
// The captured pointer and where it was last seen, so the long-press timer
// can deliver a stationary sample for that same pointer.
let captured = null;
let deadlineTimer = 0;
function sendPointer(phase, kind, button, modifiers, p, scroll, pointerId) {
  return guarded(() => checked(exports.gama_web_v3_pointer_event(
    phase, kind, button, modifiers, p.col, p.row, scroll.cols, scroll.rows,
    pointerId | 0, performance.now(),
  ), "gama_web_v3_pointer_event"));
}
// After every sample, re-arm (or clear) the one-shot long-press timer from
// the deadline Gama publishes; -3 means no press is waiting on one.
function armDeadline() {
  clearTimeout(deadlineTimer);
  deadlineTimer = 0;
  const deadline = exports.gama_web_v3_pointer_deadline();
  if (deadline < 0 || captured === null) return;
  deadlineTimer = setTimeout(() => {
    deadlineTimer = 0;
    if (dead || captured === null) return;
    const { kind, pointerId, p } = captured;
    guarded(() => checked(exports.gama_web_v3_pointer_event(
      PHASE.stationary, kind, 0, 0, p.col, p.row, 0, 0, pointerId | 0,
      Math.max(performance.now(), deadline),
    ), "gama_web_v3_pointer_event"));
    armDeadline();
  }, Math.max(0, deadline - performance.now()));
}
function onPointer(phase, e) {
  const kind = KIND[e.pointerType] ?? KIND.mouse;
  const p = gridPos(e);
  const status = sendPointer(
    phase, kind, e.button >= 0 ? (BUTTON[e.button] ?? e.button) : 0, modifierBits(e), p,
    { cols: 0, rows: 0 }, e.pointerId,
  );
  if (status !== 0) return;
  if (phase === PHASE.down) captured = { kind, pointerId: e.pointerId, p };
  else if (captured !== null && e.pointerId === captured.pointerId) {
    captured.p = p;
    if (phase === PHASE.up || phase === PHASE.cancel) captured = null;
  }
  armDeadline();
  smoke.pointers += 1;
}
root.addEventListener("pointerdown", (e) => {
  // Focus even while loading, so the first key after boot lands here.
  root.focus();
  if (dead || !ready) return;
  // Keep the drag's samples coming when the pointer leaves the surface. A
  // synthetic event has no active pointer to capture, which throws.
  try { root.setPointerCapture(e.pointerId); } catch {}
  onPointer(PHASE.down, e);
});
root.addEventListener("pointermove", (e) => {
  if (dead || !ready) return;
  onPointer(e.buttons !== 0 ? PHASE.move : PHASE.hover, e);
});
root.addEventListener("pointerup", (e) => {
  if (dead || !ready) return;
  onPointer(PHASE.up, e);
});
root.addEventListener("pointercancel", (e) => {
  if (dead || !ready) return;
  onPointer(PHASE.cancel, e);
});
// Leaving the surface without a press is a hover outside the grid, which
// clears hover; a captured drag keeps its samples through the capture.
root.addEventListener("pointerleave", (e) => {
  if (dead || !ready || captured !== null) return;
  sendPointer(PHASE.hover, KIND[e.pointerType] ?? KIND.mouse, 0, modifierBits(e),
    { col: -1, row: -1 }, { cols: 0, rows: 0 }, e.pointerId);
});
// Wheel deltas accumulate into whole cells: pixels by the cell size, lines
// one per row, pages by the grid. Positive rows reveal the lines below,
// which is the DOM's deltaY sign already.
const wheelRemainder = { cols: 0, rows: 0 };
root.addEventListener("wheel", (e) => {
  if (dead || !ready) return;
  e.preventDefault();
  const scale = e.deltaMode === 1 ? { x: 1, y: 1 }
    : e.deltaMode === 2 ? { x: grid.cols, y: grid.rows }
    : { x: 1 / cell.w, y: 1 / cell.h };
  wheelRemainder.cols += e.deltaX * scale.x;
  wheelRemainder.rows += e.deltaY * scale.y;
  const cols = Math.trunc(wheelRemainder.cols);
  const rows = Math.trunc(wheelRemainder.rows);
  if (cols === 0 && rows === 0) return;
  wheelRemainder.cols -= cols;
  wheelRemainder.rows -= rows;
  sendPointer(PHASE.scroll, KIND.mouse, 0, modifierBits(e), gridPos(e), { cols, rows }, 0);
  smoke.pointers += 1;
}, { passive: false });

// ── Boot ───────────────────────────────────────────────────────────────
// Instantiate from a fully materialized response so MIME/proxy behavior cannot
// change compilation semantics across dependency-free static hosts. Each stage
// names itself, so a failure reaches the page instead of leaving a blank
// surface and a console line nobody is looking at.
let stage = "fetch";
try {
  const response = await fetch("./gama-web-demo.wasm");
  if (!response.ok) throw new Error(`HTTP ${response.status} ${response.statusText}`);
  stage = "instantiate";
  const { instance } = await WebAssembly.instantiate(
    await response.arrayBuffer(),
    { gama: gamaImports, wasi_snapshot_preview1: wasiStubs },
  );
  exports = instance.exports;
  memory = exports.memory;
  const tier = [
    ...["frame", "key", "resize"].map((event) => `gama_web_v2_${event}`),
    "gama_web_v3_pointer_event", "gama_web_v3_pointer_deadline",
  ];
  const missing = tier.filter((name) => typeof exports[name] !== "function");
  if (missing.length > 0) {
    throw new Error(`module does not export the v2/v3 tier: ${missing.join(", ")}`);
  }

  stage = "initialize";
  // Reactor init runs top-level code (GamaWeb.install) exactly once.
  if (typeof exports._initialize === "function") exports._initialize();
  else exports._start?.();

  // The first export call is the install check: a module whose install failed
  // answers -1 here, and `checked` turns that into a HostMissing named for
  // this stage rather than a page that never paints.
  stage = "install";
  cell = cellMetrics();
  notifyResize();

  stage = "first frame";
  new ResizeObserver(() => guarded(notifyResize)).observe(root);
  root.focus();
  checked(exports.gama_web_v2_frame(), "gama_web_v2_frame");
  ready = true;

  // A webfont that resolves after first paint changes the cell advance, so
  // re-measure and re-fit once the font set settles. Guarded: document.fonts
  // is absent in some embedders.
  document.fonts?.ready.then(() => {
    const measured = cellMetrics();
    if (Math.abs(measured.w - cell.w) < 0.01 && Math.abs(measured.h - cell.h) < 0.01) return;
    cell = measured;
    guarded(notifyResize);
  }).catch(() => {});
} catch (error) {
  dead = true;
  showFatal(stage, error);
  throw error;
}

// Deterministic browser-only acceptance hook. It exercises real DOM event
// listeners, ResizeObserver-compatible sizing, requestAnimationFrame, WASM,
// and accessible output; normal hosts never enable it.
if (new URLSearchParams(location.search).get("gama-smoke") === "1") {
  const renderedCount = () => /\bcount ([0-9]+)\b/.exec(root.textContent)?.[1] ?? "none";
  const state = [renderedCount()];
  root.dispatchEvent(new KeyboardEvent("keydown", { key: "Tab", bubbles: true }));
  const bounds = root.getBoundingClientRect();
  const at = { clientX: bounds.left + 12, clientY: bounds.top + 28, bubbles: true };
  const pointer = { ...at, pointerId: 1, pointerType: "mouse", isPrimary: true };
  root.dispatchEvent(new PointerEvent("pointermove", { ...pointer, buttons: 0 }));
  root.dispatchEvent(new PointerEvent("pointerdown", { ...pointer, button: 0, buttons: 1 }));
  root.dispatchEvent(new PointerEvent("pointerup", { ...pointer, button: 0, buttons: 0 }));
  root.dispatchEvent(new WheelEvent("wheel", { ...at, deltaY: 3, deltaMode: 1, cancelable: true }));
  // The grid is already fitted, and notifyResize now returns early when the
  // dimensions are unchanged, so force the resize the marker counts.
  grid = { cols: 0, rows: 0 };
  notifyResize();
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  state.push(renderedCount());

  // Only this real Enter keydown activates the focused button. The three
  // readings distinguish initial state, non-activating event coverage, and
  // activation of an inline @Reactive component (ADR 0011).
  root.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }));
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  state.push(renderedCount());
  const accessible = root.getAttribute("role") === "application"
    && root.getAttribute("aria-label")?.includes("Gama Web");
  const rendered = root.textContent.includes("Gama Web");
  root.dataset.gamaSmoke = [
    "OK", `frames=${smoke.frames}`, `keys=${smoke.keys}`,
    `pointers=${smoke.pointers}`, `resizes=${smoke.resizes}`,
    `rendered=${rendered}`, `accessible=${accessible}`, `state=${state.join("->")}`,
  ].join(";");
}
