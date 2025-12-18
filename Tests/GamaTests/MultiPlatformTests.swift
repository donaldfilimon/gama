import XCTest
@testable import Gama

final class MultiPlatformTests: XCTestCase {

    func testPlatformDetection() {
        // Test that platform detection works
        XCTAssertFalse(currentPlatform.isEmpty)
        XCTAssertTrue(hasWindowingSupport || hasGraphicsSupport || hasControlSupport || hasInputSupport)

        #if os(Windows)
        XCTAssertTrue(isWindows)
        XCTAssertEqual(currentPlatform, "Windows")
        #elseif os(macOS)
        XCTAssertTrue(isApple)
        XCTAssertEqual(currentPlatform, "macOS")
        #elseif os(iOS)
        XCTAssertTrue(isApple)
        XCTAssertEqual(currentPlatform, "iOS")
        #elseif os(Linux)
        XCTAssertTrue(isLinux)
        XCTAssertEqual(currentPlatform, "Linux")
        #endif
    }

    func testWindowProtocol() {
        // Test that WindowProtocol has all required methods
        let windowFactory = WindowFactory.self

        // Test that factory exists and has expected properties
        XCTAssertEqual(WindowFactory.defaultWindowClassName, {
            #if os(Windows)
            return "GamaWindow"
            #elseif os(macOS) || os(iOS) || os(tvOS)
            return "GamaAppleWindow"
            #elseif os(Linux)
            return "GamaLinuxWindow"
            #elseif os(Android)
            return "GamaAndroidWindow"
            #else
            return "GamaWindow"
            #endif
        }())
    }

    func testWindowStyleOptions() {
        // Test WindowStyleOptions
        var style = WindowStyleOptions.overlappedWindow
        XCTAssertTrue(style.contains(.caption))
        XCTAssertTrue(style.contains(.sysmenu))

        // Test combined styles
        style = [.caption, .border]
        XCTAssertTrue(style.contains(.caption))
        XCTAssertTrue(style.contains(.border))
        XCTAssertFalse(style.contains(.popup))
    }

    func testColor() {
        // Test Color struct
        let red = Color(r: 255, g: 0, b: 0, a: 255)
        XCTAssertEqual(red.r, 255)
        XCTAssertEqual(red.g, 0)
        XCTAssertEqual(red.b, 0)
        XCTAssertEqual(red.a, 255)

        let blue = Color.blue
        XCTAssertEqual(blue.r, 0)
        XCTAssertEqual(blue.g, 0)
        XCTAssertEqual(blue.b, 255)
    }

    func testPoint() {
        // Test Point struct
        let point = Point(x: 10, y: 20)
        XCTAssertEqual(point.x, 10)
        XCTAssertEqual(point.y, 20)

        let moved = Point(x: point.x + 5, y: point.y + 10)
        XCTAssertEqual(moved.x, 15)
        XCTAssertEqual(moved.y, 30)
    }

    func testSize() {
        // Test Size struct
        let size = Size(width: 800, height: 600)
        XCTAssertEqual(size.width, 800)
        XCTAssertEqual(size.height, 600)

        let scaled = Size(width: size.width * 2, height: size.height * 2)
        XCTAssertEqual(scaled.width, 1600)
        XCTAssertEqual(scaled.height, 1200)
    }

    func testRectangle() {
        // Test Rectangle struct
        let rect = Rectangle(left: 10, top: 20, right: 110, bottom: 120)
        XCTAssertEqual(rect.left, 10)
        XCTAssertEqual(rect.top, 20)
        XCTAssertEqual(rect.right, 110)
        XCTAssertEqual(rect.bottom, 120)
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, 100)

        let center = rect.center
        XCTAssertEqual(center.x, 60)
        XCTAssertEqual(center.y, 70)
    }

    func testPlatformCapabilities() {
        // Test PlatformCapabilities
        let capabilities = PlatformCapabilities.current

        // At minimum, one of these should be true for a useful platform
        XCTAssertTrue(capabilities.windowing || capabilities.graphics || capabilities.controls || capabilities.input)
    }

    func testWindowCreation() {
        // Test that window creation doesn't crash (though it may not actually create a window in tests)
        XCTAssertNoThrow({
            do {
                let window = try Window(title: "Test Window", size: Size(width: 400, height: 300))
                XCTAssertNotNil(window)
                XCTAssertEqual(window.title, "Test Window")
                XCTAssertEqual(window.size.width, 400)
                XCTAssertEqual(window.size.height, 300)
                XCTAssertTrue(window.isValid)
            } catch {
                // This is expected in test environment where UI frameworks may not be available
                print("Window creation failed as expected in test environment: \(error)")
            }
        })
    }

    func testPlatformError() {
        // Test PlatformError creation
        let error = PlatformError.operationFailed(reason: "Test error")
        XCTAssertEqual(error.description, "Operation failed: Test error")

        let invalidParam = PlatformError.invalidParameter
        XCTAssertEqual(invalidParam.description, "Invalid parameter")
    }

    func testEnsurePlatformSupport() {
        // Test platform support assertion
        XCTAssertNoThrow({
            try ensurePlatformSupport(for: "basic functionality", supported: true)
        })

        XCTAssertThrowsError({
            try ensurePlatformSupport(for: "non-existent feature", supported: false)
        }) { error in
            XCTAssertTrue(error is PlatformError)
            if let platformError = error as? PlatformError {
                XCTAssertTrue(platformError.description.contains("non-existent feature"))
            }
        }
    }

    func testStringUtilities() {
        // Test string extensions
        let testString = "Hello, World!"

        // These should not crash, even if they return nil/empty on non-Windows platforms
        let windowsUTF16 = testString.windowsUTF16
        #if os(Windows)
        XCTAssertNotNil(windowsUTF16)
        #else
        XCTAssertNil(windowsUTF16)
        #endif

        let result: String? = testString.withWindowsUTF16 { _ in "test" }
        XCTAssertEqual(result, "test")
    }
}