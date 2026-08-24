# Backend authoring

Connect a terminal, native view, browser reactor, or embedded host to the same
core semantics.

## Poll-style renderers

Implement ``Renderer`` with a typed `Failure`, current ``Renderer/size``, and
explicit `begin()`, `present(_:)`, `nextEvent(timeoutMillis:)`, and `end()`
lifecycle. `AppRuntime` guarantees an `end()` attempt after a successful
`begin()`, including error and quit paths.

Terminal implementations should make raw-console ownership noncopyable or
reference-unique and restore modes, cursor visibility, alternate screen, code
page, and mouse reporting during teardown.

## Reactor-style hosts

AppKit/UIKit, browser, and foreign-language hosts retain a ``FrameHost``.

The dependency-free `WebHost` is a UI demonstration host, not a general WASI
runtime. It implements the process metadata, clock, random, and output imports
needed by the reactor and returns explicit WASI errors for unsupported calls;
it does not provide a filesystem. Applications needing broader WASI facilities
must supply a complete host and revalidate it with their selected Swift
snapshot.
Translate native resize, key, focus, touch, and pointer callbacks into
``InputEvent`` values. When ``FrameHost/needsFrame`` is true, call
`pump(size:)`, convert the laid-out tree through the shared drawing layer, and
schedule another frame only if the host becomes dirty again.

Keep platform objects and application state out of GamaCore. A backend owns
event translation, metrics, scheduling, drawing, and restoration only.
