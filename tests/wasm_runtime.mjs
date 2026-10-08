// First-party test-only engine harness. Production artifact has no JS/WASI imports.
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
const file = process.argv[2];
const bounded = process.argv[3] === 'bounded';
const module = await WebAssembly.compile(readFileSync(file));
assert.deepEqual(WebAssembly.Module.imports(module), []);
const instance = await WebAssembly.instantiate(module, {});
const x = instance.exports;
const call = (name, ...args) => x[`gama_wasm_v1_${name}`](...args);
let checks = 0;
const eq = (actual, expected) => { assert.deepEqual(actual, expected); checks++; };
const bytes = () => {
  const ptr = call('frame_ptr') >>> 0, len = call('frame_len') >>> 0;
  assert.ok(ptr + len <= x.memory.buffer.byteLength); checks++;
  return Buffer.from(new Uint8Array(x.memory.buffer, ptr, len)); // copy before another call/growth
};
const initial = readFileSync('tests/parity/swift-baseline/c-embed-initial.gama');
const increment = readFileSync('tests/parity/swift-baseline/c-embed-increment.gama');
eq(call('frame_ptr'), 0); eq(call('frame_len'), 0); eq(call('frame'), -1);
eq(call('key', 999,-1,0,0),-1); eq(call('pointer',0,0,1),-1); eq(call('resize',0,0),-1); eq(call('needs_frame'),-1);
call('shutdown'); call('shutdown');
eq(call('init',24,6),0); eq(call('needs_frame'),1);
eq(call('key',5,-1,0,0),0); eq(call('pointer',1,1,1),0);
eq(call('frame'),1); eq(bytes(),initial); eq(call('needs_frame'),0);
const saved = bytes();
eq(call('key',5,-1,-1,-1),0); eq(bytes(),saved);
eq(call('frame'),1); eq(bytes(),increment); eq(saved,initial);
eq(call('frame'),0); eq(call('frame_ptr'),0); eq(call('frame_len'),0);
for(const scalar of [-1,0xd800,0xdfff,0x110000,2147483647]) eq(call('key',0,scalar,0,0),-2);
for(const scalar of [0,0xffff,0x10ffff,0x0130,0x03a3]) eq(call('key',0,scalar,0,-1),0);
eq(call('needs_frame'),0);
for(const code of [14,99,113,-1]) eq(call('key',code,0,0,0),-2);
for(const [col,row,press] of [[-1,1,1],[11,1,1],[1,0,1],[1,1,0]]) { eq(call('pointer',col,row,press),0); eq(call('needs_frame'),0); }
eq(call('pointer',0,1,-1),0); eq(call('frame'),1); assert.equal(bytes()[56],50); checks++;
eq(call('resize',2147483647,2147483647),0); eq(call('frame'),-3); eq(call('frame_ptr'),0); eq(call('frame_len'),0); eq(call('needs_frame'),1);
eq(call('resize',24,6),0); eq(call('frame'),1); assert.equal(bytes()[56],50); checks++;
if (bounded) {
  // Exhaust a fresh fixture's declared memory before allocator initialization.
  // This proves real init OOM, separate from native failure-preserves-installed tests.
  const exhausted = (await WebAssembly.instantiate(module, {})).exports;
  exhausted.memory.grow(32 - exhausted.memory.buffer.byteLength / 65536);
  eq(exhausted.gama_wasm_v1_init(24,6),-4);
  eq(exhausted.gama_wasm_v1_needs_frame(),-1);
  eq(exhausted.gama_wasm_v1_frame(),-1);
  eq(exhausted.gama_wasm_v1_frame_ptr(),0);
  eq(exhausted.gama_wasm_v1_frame_len(),0);
  exhausted.gama_wasm_v1_shutdown();
  eq(call('resize',1024,1024),0); eq(call('frame'),-4); eq(call('frame_ptr'),0); eq(call('frame_len'),0); eq(call('needs_frame'),1);
  eq(call('resize',24,6),0); eq(call('frame'),1); assert.equal(bytes()[56],50); checks++;
}
eq(call('init',24,6),0); eq(call('frame_ptr'),0); eq(call('frame_len'),0); eq(call('frame'),1); eq(bytes(),initial);
eq(call('resize',-1,0),0); eq(call('frame'),1); const small=bytes(); eq(small.readInt32LE(8),1); eq(small.readInt32LE(12),1);
call('shutdown'); eq(call('frame_ptr'),0); eq(call('frame_len'),0); eq(call('frame'),-1);
console.error(`All ${checks} WASM runtime assertions passed (${process.version}; ${bounded ? 'bounded-memory fixture executes wasm_allocator OOM' : 'production artifact'})`);
