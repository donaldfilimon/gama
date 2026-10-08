# Terminal adapter contract

`Surface.adaptive(io,args)` selects from stdout, then applies exact `--gama-plain`
and `--gama-tui` arguments in order; the last recognized override wins. Plain
extent is 80×24. Windows provides plain/headless only. `run(host,surface)` and
`runAdaptive(host,io,args)` use the same Host/layout/painter and never exit the
process. Results borrow Host; `declared=false` distinguishes quiescent/quit
fallback success from first-result-wins declared completion. Declared completion
is checked after presentation and does not hold an inputless clean loop open.
`runAdaptive` writes an optional completion message and LF to stderr.

Host and application storage outlive runtime calls. Io backend and surface
storage outlive a terminal lease. Move initialized owning values into stable
storage and use pointers; do not create independent owning copies. All native
entry points enforce executor confinement in every optimization mode. Lease
lifecycle methods are ordinary-thread APIs, not callable from user signal
handlers. The application exclusively owns the terminal, its open-file flags,
and the managed signal dispositions during a lease.

`PreparedFrame.stage` completes paint/encode and the final owned-byte copy.
`deliver` then invokes transport under the same host mutation guard and publishes
without allocation only on success. Drawing promotes a separate candidate plane
after that publication. Allocation failure writes nothing; transport failure may
leave a partial external prefix, but preserves prior internal planes, output and
registrations, and requests retry. Semantic lines replace derived plain rows,
advance grid reconciliation, and are consumed once after successful delivery.
Ordinary plain output uses the injected std.Io backend; its cancellation/blocking
behavior is that backend's contract. Terminal output uses nonblocking writes and
returns OutputStalled after one second without completing the frame. There is no
claim of external-byte rollback or cross-writer atomicity.

Input storage is fixed at 256 bytes, with 64-byte reads. Lone ESC waits 25 ms.
An unfinished CSI/SS3/UTF-8 sequence is discarded at 256 bytes or 250 ms from its
first incomplete observation. InputFull rejects a feed exceeding remaining room
without partial insertion. Invalid UTF-8 drops one leading byte; complete unknown
sequences are consumed; subsequent input can recover. Character events borrow a
four-byte scratch scalar until the next decode call. Scalars are fed through the
shared grapheme-aware editor, so cursor movement/deletion preserves clusters.
SGR mouse preserves the baseline button-agnostic M/m behavior and signed
coordinates, while rejecting integer overflow/underflow. Function keys are F1–F12.
Resize coalesces and takes priority over buffered input. EOF/hangup is explicit.

The POSIX lease duplicates descriptors and uses std termios/sigaction/fcntl APIs.
Raw-mode bit changes match the baseline, but acquisition uses TCSANOW: the prior
TCSAFLUSH operation can wait indefinitely for queued output during reacquisition.
Normal/error release restores settings before one best-effort nonblocking
cursor/reset/newline write, then restores file flags and closes owned descriptors.
The default presentation enables cursor hiding only; optional alternate-screen,
paste, focus and mouse mode negotiation is not inferred from decoder support.

Managed signals are TERM, HUP, INT, QUIT and WINCH. WINCH coalesces while leased.
Fatal rescue never allocates, logs, writes ANSI, waits, locks or spins; it restores
termios/dispositions using raw std APIs, drops its descriptor-reader reference,
then redelivers through the current OS disposition. Immediate syscall failure in
rescue uses `_exit(127)`; normal release reports IOFailure after all restore steps.
No cleanup is promised for SIGKILL or direct external process exit. A hung-up
PTY can reject further termios operations; EOF tests do not claim restoration of
a terminal whose master has already closed.

Each acquisition consumes one of 256 immutable process-lifetime rescue records
and a distinct callback. Exhaustion reports GenerationExhausted before changing
settings/dispositions. The exact static data cost is exposed as
`Terminal.rescue_storage_bytes`; there is no heap allocation for rescue records.
Normal teardown restores actions, disables descriptor readers and waits for
in-flight readers before closing duplicates. Delayed retired callbacks forward
through the current action without installing old dispositions or touching old
FDs. They therefore cannot bypass restoration owned by a later lease. Normal
teardown is the only waiting path; returning displaced handlers run after reader
release. Cooperative callers must not mutate the borrowed lease from a signal
handler or race independent signal-disposition installation with acquisition.

Darwin's sigaction readback omits SA_RESETHAND, despite applying it on delivery.
Default/ignored actions can be captured automatically. A custom Darwin action
without caller metadata fails with UnverifiableDisposition before any mutation.
Use `Terminal.acquireWithActions` or `Surface.dispositions` with the exact
original `Disposition{signal,action}` record retained by the installing caller.
Duplicate, unsupported, missing-custom, or observably mismatched records reject.
The framework checks handler, mask and every observable flag; only the proven
hidden SA_RESETHAND bit relies on caller truth. Records are copied and need not
outlive acquisition. Wrong caller metadata cannot be independently detected.
Consumed one-shot actions are never reinstalled by normal close after rescue.
Acquisition uses each atomic replacement's returned action as the restore record,
so one-shots consumed after preflight remain consumed. Hidden metadata is reused
only for an observably matching custom action. Installing callbacks only queue
events until these records are resolved; failure restores only replaced actions.

Native qualification uses compiled Zig tests/parent/child consumers. On this
macOS the legacy PTY nodes return EAGAIN and installed Zig std lacks Darwin PTY
allocation declarations. `tests/with_pty.py` requires Python 3 and only allocates
with os.openpty, inherits descriptors and execs the Zig consumer; it never changes
or restores termios. `/bin/stty` is test-only and changes dimensions of that owned
slave only. Zig parents inspect held-slave settings before teardown; comparison
excludes Darwin's kernel-generated PENDIN retype latch, not actual mode flags.
Cross-built Linux/Windows objects are compilation evidence, not native execution.
