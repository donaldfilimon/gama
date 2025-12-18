import Foundation

#if os(macOS)
import AppKit
#endif

#if os(iOS) || os(tvOS)
import UIKit
#endif

/// Protocol for Apple platform controls
public protocol AppleControlProtocol {
    var frame: Rectangle { get set }
    var isEnabled: Bool { get set }
    var isVisible: Bool { get set }
    var tag: Int { get set }

    func setNeedsDisplay()
    func removeFromSuperview()
}

/// Base class for AppKit controls (macOS)
#if os(macOS)
public class AppleControl: AppleControlProtocol {
    internal let nsView: NSView

    public init(nsView: NSView) {
        self.nsView = nsView
    }

    public var frame: Rectangle {
        get {
            let nsRect = nsView.frame
            return Rectangle(left: Int32(nsRect.origin.x),
                           top: Int32(nsRect.origin.y),
                           right: Int32(nsRect.origin.x + nsRect.width),
                           bottom: Int32(nsRect.origin.y + nsRect.height))
        }
        set {
            nsView.frame = NSRect(x: CGFloat(newValue.left),
                                y: CGFloat(newValue.top),
                                width: CGFloat(newValue.width),
                                height: CGFloat(newValue.height))
        }
    }

    public var isEnabled: Bool {
        get {
            if let control = nsView as? NSControl {
                return control.isEnabled
            }
            return true
        }
        set {
            if let control = nsView as? NSControl {
                control.isEnabled = newValue
            }
        }
    }

    public var isVisible: Bool {
        get { return !nsView.isHidden }
        set { nsView.isHidden = !newValue }
    }

    public var tag: Int {
        get { return nsView.tag }
        set { nsView.tag = newValue }
    }

    public func setNeedsDisplay() {
        nsView.needsDisplay = true
    }

    public func removeFromSuperview() {
        nsView.removeFromSuperview()
    }

    public func addToView(_ parentView: NSView) {
        parentView.addSubview(nsView)
    }
}

/// AppKit Button control
public class AppleButton: AppleControl {
    private let nsButton: NSButton

    public init(title: String, frame: Rectangle? = nil) {
        nsButton = NSButton(frame: .zero)
        nsButton.title = title
        nsButton.bezelStyle = .rounded
        nsButton.target = nil
        nsButton.action = nil

        super.init(nsView: nsButton)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var title: String {
        get { return nsButton.title }
        set { nsButton.title = newValue }
    }

    public func setAction(_ target: AnyObject?, action: Selector?) {
        nsButton.target = target
        nsButton.action = action
    }

    public func setButtonType(_ type: NSButton.ButtonType) {
        nsButton.setButtonType(type)
    }

    public var state: NSControl.StateValue {
        get { return nsButton.state }
        set { nsButton.state = newValue }
    }
}

/// AppKit Label (TextField) control
public class AppleLabel: AppleControl {
    private let nsTextField: NSTextField

    public init(text: String = "", frame: Rectangle? = nil) {
        nsTextField = NSTextField(frame: .zero)
        nsTextField.stringValue = text
        nsTextField.isEditable = false
        nsTextField.isSelectable = false
        nsTextField.drawsBackground = false
        nsTextField.isBordered = false

        super.init(nsView: nsTextField)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String {
        get { return nsTextField.stringValue }
        set { nsTextField.stringValue = newValue }
    }

    public var textColor: NSColor {
        get { return nsTextField.textColor ?? .black }
        set { nsTextField.textColor = newValue }
    }

    public var font: NSFont {
        get { return nsTextField.font ?? .systemFont(ofSize: 12) }
        set { nsTextField.font = newValue }
    }

    public var alignment: NSTextAlignment {
        get { return nsTextField.alignment }
        set { nsTextField.alignment = newValue }
    }
}

/// AppKit TextField control
public class AppleTextField: AppleControl {
    private let nsTextField: NSTextField

    public init(text: String = "", frame: Rectangle? = nil) {
        nsTextField = NSTextField(frame: .zero)
        nsTextField.stringValue = text
        nsTextField.isEditable = true
        nsTextField.isSelectable = true
        nsTextField.drawsBackground = true
        nsTextField.isBordered = true

        super.init(nsView: nsTextField)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String {
        get { return nsTextField.stringValue }
        set { nsTextField.stringValue = newValue }
    }

    public var placeholder: String {
        get { return nsTextField.placeholderString ?? "" }
        set { nsTextField.placeholderString = newValue }
    }

    public var isEditable: Bool {
        get { return nsTextField.isEditable }
        set { nsTextField.isEditable = newValue }
    }

    public func setDelegate(_ delegate: NSTextFieldDelegate?) {
        nsTextField.delegate = delegate
    }
}

/// AppKit TextView control
public class AppleTextView: AppleControl {
    private let nsScrollView: NSScrollView
    private let nsTextView: NSTextView

    public init(text: String = "", frame: Rectangle? = nil) {
        nsTextView = NSTextView(frame: .zero)
        nsTextView.string = text

        nsScrollView = NSScrollView(frame: .zero)
        nsScrollView.documentView = nsTextView
        nsScrollView.hasVerticalScroller = true
        nsScrollView.hasHorizontalScroller = true
        nsScrollView.autohidesScrollers = true

        super.init(nsView: nsScrollView)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String {
        get { return nsTextView.string }
        set { nsTextView.string = newValue }
    }

    public var isEditable: Bool {
        get { return nsTextView.isEditable }
        set { nsTextView.isEditable = newValue }
    }

    public var isSelectable: Bool {
        get { return nsTextView.isSelectable }
        set { nsTextView.isSelectable = newValue }
    }

    public func setDelegate(_ delegate: NSTextViewDelegate?) {
        nsTextView.delegate = delegate
    }
}
#endif

/// Base class for UIKit controls (iOS/tvOS)
#if os(iOS) || os(tvOS)
public class AppleControl: AppleControlProtocol {
    internal let uiView: UIView

    public init(uiView: UIView) {
        self.uiView = uiView
    }

    public var frame: Rectangle {
        get {
            let uiRect = uiView.frame
            return Rectangle(left: Int32(uiRect.origin.x),
                           top: Int32(uiRect.origin.y),
                           right: Int32(uiRect.origin.x + uiRect.width),
                           bottom: Int32(uiRect.origin.y + uiRect.height))
        }
        set {
            uiView.frame = CGRect(x: CGFloat(newValue.left),
                                y: CGFloat(newValue.top),
                                width: CGFloat(newValue.width),
                                height: CGFloat(newValue.height))
        }
    }

    public var isEnabled: Bool {
        get { return uiView.isUserInteractionEnabled }
        set { uiView.isUserInteractionEnabled = newValue }
    }

    public var isVisible: Bool {
        get { return !uiView.isHidden }
        set { uiView.isHidden = !newValue }
    }

    public var tag: Int {
        get { return uiView.tag }
        set { uiView.tag = newValue }
    }

    public func setNeedsDisplay() {
        uiView.setNeedsDisplay()
    }

    public func removeFromSuperview() {
        uiView.removeFromSuperview()
    }

    public func addToView(_ parentView: UIView) {
        parentView.addSubview(uiView)
    }
}

/// UIKit Button control
public class AppleButton: AppleControl {
    private let uiButton: UIButton

    public init(title: String, frame: Rectangle? = nil) {
        uiButton = UIButton(type: .system)
        uiButton.setTitle(title, for: .normal)

        super.init(uiView: uiButton)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var title: String? {
        get { return uiButton.title(for: .normal) }
        set {
            if let title = newValue {
                uiButton.setTitle(title, for: .normal)
            }
        }
    }

    public func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
        uiButton.addTarget(target, action: action, for: controlEvents)
    }

    public var isSelected: Bool {
        get { return uiButton.isSelected }
        set { uiButton.isSelected = newValue }
    }

    public var isHighlighted: Bool {
        get { return uiButton.isHighlighted }
        set { uiButton.isHighlighted = newValue }
    }
}

/// UIKit Label control
public class AppleLabel: AppleControl {
    private let uiLabel: UILabel

    public init(text: String = "", frame: Rectangle? = nil) {
        uiLabel = UILabel(frame: .zero)
        uiLabel.text = text

        super.init(uiView: uiLabel)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String? {
        get { return uiLabel.text }
        set { uiLabel.text = newValue }
    }

    public var textColor: UIColor {
        get { return uiLabel.textColor }
        set { uiLabel.textColor = newValue }
    }

    public var font: UIFont {
        get { return uiLabel.font }
        set { uiLabel.font = newValue }
    }

    public var textAlignment: NSTextAlignment {
        get { return uiLabel.textAlignment }
        set { uiLabel.textAlignment = newValue }
    }

    public var numberOfLines: Int {
        get { return uiLabel.numberOfLines }
        set { uiLabel.numberOfLines = newValue }
    }
}

/// UIKit TextField control
public class AppleTextField: AppleControl {
    private let uiTextField: UITextField

    public init(text: String = "", frame: Rectangle? = nil) {
        uiTextField = UITextField(frame: .zero)
        uiTextField.text = text
        uiTextField.borderStyle = .roundedRect

        super.init(uiView: uiTextField)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String? {
        get { return uiTextField.text }
        set { uiTextField.text = newValue }
    }

    public var placeholder: String? {
        get { return uiTextField.placeholder }
        set { uiTextField.placeholder = newValue }
    }

    public var isSecureTextEntry: Bool {
        get { return uiTextField.isSecureTextEntry }
        set { uiTextField.isSecureTextEntry = newValue }
    }

    public func setDelegate(_ delegate: UITextFieldDelegate?) {
        uiTextField.delegate = delegate
    }

    public var keyboardType: UIKeyboardType {
        get { return uiTextField.keyboardType }
        set { uiTextField.keyboardType = newValue }
    }
}

/// UIKit TextView control
public class AppleTextView: AppleControl {
    private let uiTextView: UITextView

    public init(text: String = "", frame: Rectangle? = nil) {
        uiTextView = UITextView(frame: .zero)
        uiTextView.text = text

        super.init(uiView: uiTextView)

        if let frame = frame {
            self.frame = frame
        }
    }

    public var text: String {
        get { return uiTextView.text }
        set { uiTextView.text = newValue }
    }

    public var isEditable: Bool {
        get { return uiTextView.isEditable }
        set { uiTextView.isEditable = newValue }
    }

    public var isSelectable: Bool {
        get { return uiTextView.isSelectable }
        set { uiTextView.isSelectable = newValue }
    }

    public func setDelegate(_ delegate: UITextViewDelegate?) {
        uiTextView.delegate = delegate
    }

    public var font: UIFont? {
        get { return uiTextView.font }
        set { uiTextView.font = newValue }
    }
}
#endif