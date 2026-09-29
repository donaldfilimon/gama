# ADR 0008: iOS and visionOS hosting

Status: Accepted (2026-09-23)

## Context

Until now, Gama Studio ran only on macOS (ADR 0003): `gama-studio` is an
AppKit executable, and its viewport is RealityKit's `ARView`. `StudioModel`
already compiled wherever RealityKit does, but the UI did not. Donald asked
for iOS and visionOS hosting on 2026-09-23 and chose:

- runnable apps plus a gate;
- on visionOS, the 3D scene inside the window, not in a separate volume.

What was measured before designing, on 2026-09-23:

- **Tools.** Xcode 27.2 ships the iOS 27.2 and visionOS 27.2 SDKs and
  simulators. No project generator (XcodeGen, Tuist) is installed.
- **gama's UIKit host.** `GamaHostView` at the pinned revision has a UIKit
  path. It handles taps and hardware-keyboard presses and supports native
  regions.
- **visionOS APIs.** The visionOS SDK has no usable `ARView`, and
  `RealityView`'s camera API is marked unavailable there.
- **Swift version.** The package builds under Xcode's Swift 6.4 as well as
  the pinned 6.5-dev snapshot.
- **Deployment floor.** Typed-throws closures (`GamaGraph`'s node
  definitions) need visionOS 2 at run time.

## Decision

1. **One touch viewport for both platforms.** A SwiftUI `RealityView` is
   wrapped in a `UIHostingController`, whose view fills gama's native
   viewport region (`TouchViewport.swift`). The macOS `ARView` viewport is
   unchanged. Picking and the fallback-light rule move to `ViewportSupport`,
   so the two viewports cannot diverge. The selection highlight is shared,
   measured relative to the stage.
2. **iOS.** A virtual camera looks through the same `OrbitCamera` as
   macOS:
   - drag orbits and pinch zooms;
   - tapping casts its own ray (`OrbitCamera.ray(through:in:fieldOfViewDegrees:)`)
     and takes the nearest hit in front of the eye. SwiftUI's entity
     targeting reports the sample Camera's marker, which contains the eye,
     for every tap: the same trap the macOS viewport's picking avoids.
3. **visionOS.** A window's `RealityView` has no camera, so the stage
   turns and scales instead:
   - drag turns it, and pinch scales it;
   - the orbit pitch tilts it toward the viewer;
   - Frame fits the subject to 0.42 m and places it in front of the window
     plane, since content behind the plane is hidden;
   - taps use SwiftUI's entity targeting (no eye sits inside a shape);
   - "Look through" frames the camera instead.

   The viewport's placeholder text renders blank because the
   `RealityView` is transparent.
4. **Adaptive layout.** `StudioRootView` reads the surface width in cells.
   Below 86 columns, as on an iPhone in portrait, the side-by-side layout
   would leave the viewport no width. The compact layout instead:
   - stacks the viewport above half-width panels;
   - splits the toolbar into two rows of short labels, keeping the same
     action identities.
5. **Hosting in the library, a thin app outside it.**
   `StudioHostViewController` and `GamaStudioView` live in
   `GamaStudioEditor`, now a package product.
   `Apps/GamaStudioApp/GamaStudioApp.xcodeproj` is a hand-written
   multiplatform app target (iOS 18, visionOS 2) that depends on the local
   package; its only source puts `GamaStudioView` in a `WindowGroup`.
   `--smoke` checks the first layout and exits:
   - the host drew;
   - the viewport is attached, visible, and non-empty;
   - the projection matches the document.
6. **Redraws never re-enter the host.** Listeners that repaint gama after
   outside changes (File ▸ Open, viewport taps) defer the repaint to the
   next main-actor turn. On iOS, a document change made by a gama button
   invalidated the host from inside its own event dispatch, which traps on
   an exclusivity conflict. The macOS File-menu hook from ADR 0005 had the
   same defect; `HostRedrawTests` reproduces it with the old code and pins
   the fix.
7. **Platform floor.** visionOS rises from 1 to 2.
8. **The gate adds an `ios and visionos` stage.** It builds the library and
   the app for both simulators with Xcode's toolchain. It then installs the
   app on `iPhone 17` and `Apple Vision Pro` (overridable), launches it
   with `--smoke`, and requires the OK line. It fails closed without Xcode,
   the simulators, or a passing launch.

## Consequences

- Verified by hand on 2026-09-23:
  - **iPhone 17 simulator:** the compact layout; tap-selecting the sphere,
    with the highlight; orbiting by drag; and the inspector's +X, which
    before the redraw fix crashed.
  - **Apple Vision Pro simulator:** the regular layout, the lit scene in
    the window, click-selecting the sphere, and +X.
  - **Where visionOS input reaches the app:** synthetic taps from the
    simulator control tool do not reach visionOS apps at all. Device Hub
    clicks, which are gaze-and-pinch, do.
- Not built:
  - file open and save on iOS and visionOS, which needs a document picker
    (since built: ADR 0009);
  - a software-keyboard route to the console, which needs a hardware
    keyboard today;
  - a separate volumetric window on visionOS;
  - signing for devices. The project signs ad hoc for simulators; a device
    build needs a team.
- `swift test` covers the macOS paths and the shared math (the pick ray).
  The iOS and visionOS code is covered by the build, the launch smoke, and
  the manual checks above, not by unit tests on those platforms.
