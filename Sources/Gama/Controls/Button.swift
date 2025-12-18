import Foundation
import WinSDK

/// Button control
public class Button: BaseControl {
    /// Button styles
    public enum Style: DWORD {
        case pushButton = 0x00000000
        case defPushButton = 0x00000001
        case checkBox = 0x00000002
        case autoCheckBox = 0x00000003
        case radioButton = 0x00000004
        case threeState = 0x00000005
        case autoThreeState = 0x00000006
        case groupBox = 0x00000007
        case userButton = 0x00000008
        case autoRadioButton = 0x00000009
        case pushBox = 0x0000000A
        case ownerDraw = 0x0000000B
        case typeMask = 0x0000000F
        case leftText = 0x00000020
        case text = 0x00000000
        case icon = 0x00000040
        case bitmap = 0x00000080
        case left = 0x00000100
        case right = 0x00000200
        case center = 0x00000300
        case top = 0x00000400
        case bottom = 0x00000800
        case vcenter = 0x00000C00
        case pushLike = 0x00001000
        case multiline = 0x00002000
        case notify = 0x00004000
        case flat = 0x00008000
        case rightButton = 0x00020000
    }
    
    /// Create a button control
    public static func create(
        parent: Window,
        title: String,
        style: Style = .pushButton,
        position: Point,
        size: Size,
        id: Int32 = 0
    ) throws -> Button {
        let className = "BUTTON"
        let buttonStyle: WindowStyleOptions = [
            .child, .visible, .tabstop
        ]
        
        let hwnd = className.withWindowsUTF16 { classNamePtr in
            title.withWindowsUTF16 { titlePtr in
                CreateWindowExW(
                    0,
                    classNamePtr,
                    titlePtr,
                    buttonStyle.rawValue | style.rawValue,
                    position.x, position.y,
                    size.width, size.height,
                    parent.hwnd,
                    HMENU(bitPattern: UInt(id)),
                    GetModuleHandleW(nil),
                    nil
                )
            }
        }
        
        guard let hwnd = hwnd else {
            throw WindowsError.fromLastError()
        }
        
        let window = Window(handle: hwnd)
        return Button(window: window)
    }
    
    /// Initialize button from existing window
    public init(window: Window) {
        super.init(window: window)
    }
    
    /// Check if button is checked (for checkbox/radio)
    public var isChecked: Bool {
        get {
            guard let hwnd = hwnd else { return false }
            return (SendMessageW(hwnd, UINT(BM_GETCHECK), 0, 0) == BST_CHECKED)
        }
        set {
            guard let hwnd = hwnd else { return }
            SendMessageW(hwnd, UINT(BM_SETCHECK), newValue ? WPARAM(BST_CHECKED) : WPARAM(BST_UNCHECKED), 0)
        }
    }
}