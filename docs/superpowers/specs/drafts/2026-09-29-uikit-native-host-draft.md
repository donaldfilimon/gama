# UIKit native host — draft

Status: Draft. Open questions, not a commitment. Nothing here is built, and
the AppKit host it follows does not exist yet either. Roadmap track 5
([native UI roadmap](../2026-09-29-native-ui-roadmap-design.md)); it depends
on track 3, the AppKit `GamaNativeHostView` of the
[native presentation design](../2026-09-23-native-presentation-design.md)
(ADR 0017).

## The ask

A `UIKitNativeHostView` that presents Gama views as UIKit controls on iOS,
iPadOS, and visionOS, using the same portable pieces as the AppKit host:
`LayoutMetrics`, the `ControlDescriptor` side table, the presentation tree,
and `PresentationDiff`. Only the last step, applying ops to real views,
differs per toolkit. tvOS is an open question.

## Proposed mapping, following the AppKit table

| Presented kind | AppKit view (track 3) | Proposed UIKit view |
| -------------- | --------------------- | ------------------- |
| label | non-editable `NSTextField` | `UILabel`, `numberOfLines = 0` |
| separator | `NSBox` separator | hairline `UIView` with `separator` color |
| container (`background`, `border`) | layer-backed `NSView` | `UIView` with `layer.borderWidth`/`borderColor` |
| `button` with title | `NSButton`, push | `UIButton` with a plain or filled configuration |
| `button` without title | clickable container | `UIControl` subclass hosting the label subtree |
| `toggle` | `NSButton`, checkbox | `UISwitch` beside a `UILabel` (no checkbox on iOS) |
| `textField` | editable `NSTextField` | `UITextField` |
| `progress` | `NSProgressIndicator` | `UIProgressView`, or `UIActivityIndicatorView` when fraction is nil |
| native region | attached `NSView` | attached `UIView` (ADR 0016's `attach(_:to:)` already accepts one) |
| other `interactive` | focusable key-forwarding container | focusable container; hardware keys via `pressesBegan` |

## Differences from AppKit that the design must settle

- **Metrics.** Text measures with `NSAttributedString.boundingRect` on both,
  but UIKit fonts scale with Dynamic Type. Track 1 (UI scaling) owns the
  scaling policy; this host should consume it, not invent one.
- **Events.** Controls use `UIAction` handlers calling `FrameHost.activate`;
  text fields use `editingChanged`. Touch hit-testing is UIKit's, as pointer
  hit-testing is AppKit's.
- **Focus.** UIKit has no `nextKeyView`. Keyboard focus on iPad goes through
  the focus system (`UIFocusGuide`, `canBecomeFocused`), and on visionOS
  through gaze and indirect pinch. How `FrameHost`'s focus order maps onto
  either is unresolved.
- **Accessibility.** As on AppKit, native controls expose their own roles
  and the cell `AccessibilitySnapshot` adapter is not used on this host.
- **Scene ownership.** UIKit scene delegates are deferred scope in
  `tasks/todo.md`. This host is a view; which object owns a `UIWindowScene`
  is outside it.
- **SwiftUI.** `GamaView` in `GamaSwiftUI` would select this host on UIKit
  platforms the same way it selects `GamaNativeHostView` on macOS (open
  question 4 of the SwiftUI embedding design).

## Open questions for the owner

1. **tvOS.** Include it (focus-engine only, no touch, no text entry beyond the
   system keyboard) or leave tvOS on the cell host?
2. **Toggle presentation.** `UISwitch` changes the visual idiom from a
   checkbox. Acceptable, or should toggles stay cell-painted on UIKit?
3. **Focus bridging.** Should Gama's focus order drive UIKit focus
   (`preferredFocusEnvironments`), or should UIKit own focus and report back
   through `FrameHost.focus(_:)` only?
4. **Target placement.** A second file set in `GamaAppleUI` (like the AppKit
   host) or a separate UIKit-only target?
5. **Evidence.** Compile gates exist for iOS, tvOS, and visionOS; no
   simulator runtime test does. Is a simulator smoke (for example through
   `xcodebuild test` on an iOS simulator) a requirement for this track, and
   on which runner?
6. **Android.** The roadmap puts an Android Views host after this one. Should
   the mapping table grow a third column now so both hosts share one
   reviewed vocabulary?
