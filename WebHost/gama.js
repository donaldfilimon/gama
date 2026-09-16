// gama.js — browser host for a Gama WASM reactor module.
// Instantiates gama-web-demo.wasm with WASI stubs + the "gama" import module,
// then forwards DOM events into the exported gama_web_v1_* entry points.
//
// Stays on the v1 export tier. The v2 tier is argument-compatible and returns
// a status instead of void (docs/backends/WASM.md); adopting it is a separate
// change that also updates the export grep in scripts/check-wasm.sh, and
// folding it in here would make a smoke failure ambiguous.

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
const smoke = { frames: 0, keys: 0, pointers: 0, resizes: 0 };
let grid = { cols: 0, rows: 0 };

const utf8 = new TextDecoder("utf-8");
const str = (ptr, len) => utf8.decode(new Uint8Array(memory.buffer, ptr, len));
let wasiText = "";

// The shell is optional: the smoke serves this same file, and a future host
// page may drop the chrome entirely, so every element above is addressed
// defensively rather than assumed present.
function setStatus(state, text) {
  if (statusRow) statusRow.dataset.state = state;
  if (statusText) statusText.textContent = text;
}

function showFatal(stage, error) {
  setStatus("failed", `failed during ${stage}`);
  boot?.setAttribute("hidden", "");
  if (!fatal) return;
  fatal.textContent = "";
  const heading = document.createElement("b");
  heading.textContent = `Gama failed to start during ${stage}.`;
  fatal.append(heading, document.createTextNode(String(error?.stack || error)));
  fatal.removeAttribute("hidden");
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
      exports.gama_web_v1_frame();
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
  exports.gama_web_v1_resize(cols, rows);
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
  let code = keyCodes[e.key] ?? 0;
  if (code === 0 && /^F(\d{1,2})$/.test(e.key)) {
    code = 99 + Number(e.key.slice(1));
  }
  let ch = 0;
  if (code === 0) {
    if (e.key.length !== 1) return;          // unmapped special key
    ch = e.key.codePointAt(0);
  }
  e.preventDefault();
  exports.gama_web_v1_key(code, ch, e.shiftKey ? 1 : 0, e.ctrlKey ? 1 : 0);
  smoke.keys += 1;
});

// ── Pointer ────────────────────────────────────────────────────────────
function gridPos(e) {
  const r = root.getBoundingClientRect();
  const pad = surfacePadding();
  return {
    col: Math.floor((e.clientX - r.left - pad.left) / cell.w),
    row: Math.floor((e.clientY - r.top - pad.top) / cell.h),
  };
}
root.addEventListener("mousedown", (e) => {
  root.focus();
  const p = gridPos(e);
  exports.gama_web_v1_pointer(p.col, p.row, 1);
  smoke.pointers += 1;
});
root.addEventListener("mouseup", (e) => {
  const p = gridPos(e);
  exports.gama_web_v1_pointer(p.col, p.row, 0);
  smoke.pointers += 1;
});

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

  stage = "initialize";
  // Reactor init runs top-level code (GamaWeb.install) exactly once.
  if (typeof exports._initialize === "function") exports._initialize();
  else exports._start?.();

  stage = "first frame";
  cell = cellMetrics();
  new ResizeObserver(notifyResize).observe(root);
  notifyResize();
  root.focus();
  exports.gama_web_v1_frame();

  // A webfont that resolves after first paint changes the cell advance, so
  // re-measure and re-fit once the font set settles. Guarded: document.fonts
  // is absent in some embedders.
  document.fonts?.ready.then(() => {
    const measured = cellMetrics();
    if (Math.abs(measured.w - cell.w) < 0.01 && Math.abs(measured.h - cell.h) < 0.01) return;
    cell = measured;
    notifyResize();
  }).catch(() => {});
} catch (error) {
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
  root.dispatchEvent(new MouseEvent("mousedown", {
    clientX: bounds.left + 12, clientY: bounds.top + 28, bubbles: true,
  }));
  root.dispatchEvent(new MouseEvent("mouseup", {
    clientX: bounds.left + 12, clientY: bounds.top + 28, bubbles: true,
  }));
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
