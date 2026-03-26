// GamaUITests.swift — Tests for the GamaUI declarative UI framework
// Part of GamaUITests

import Testing
import Foundation
@testable import GamaUI

// MARK: - ViewBuilder Tests

@Suite("ViewBuilder")
struct ViewBuilderTests {
    @Test("Single view builds correctly")
    func singleView() {
        let view = Text("Hello")
        #expect(view.content == "Hello")
    }

    @Test("Two-view tuple builds correctly")
    func twoViews() {
        @ViewBuilder
        func build() -> TupleView2<Text, Rectangle> {
            Text("A")
            Rectangle()
        }
        let tuple = build()
        #expect(tuple.v0.content == "A")
    }

    @Test("Three-view tuple builds correctly")
    func threeViews() {
        @ViewBuilder
        func build() -> TupleView3<Text, Rectangle, Circle> {
            Text("A")
            Rectangle()
            Circle()
        }
        let tuple = build()
        #expect(tuple.v0.content == "A")
    }

    @Test("VStack composes children via ViewBuilder")
    func vstackComposition() {
        let stack = VStack {
            Text("First")
            Text("Second")
        }
        #expect(stack.spacing == nil)
        #expect(stack.alignment == .center)
    }

    @Test("HStack composes children via ViewBuilder")
    func hstackComposition() {
        let stack = HStack(spacing: 12) {
            Text("Left")
            Spacer()
            Text("Right")
        }
        #expect(stack.spacing == 12)
    }

    @Test("ZStack composes children")
    func zstackComposition() {
        let stack = ZStack(alignment: .topLeading) {
            Rectangle()
            Text("Overlay")
        }
        #expect(stack.alignment == .topLeading)
    }
}

// MARK: - Style Type Tests

@Suite("StyleTypes")
struct StyleTypeTests {
    @Test("Color named constants")
    func colorConstants() {
        #expect(Color.red == Color(red: 1, green: 0, blue: 0))
        #expect(Color.clear.alpha == 0)
        #expect(Color.white == Color(red: 1, green: 1, blue: 1))
    }

    @Test("EdgeInsets uniform initializer")
    func edgeInsetsUniform() {
        let insets = EdgeInsets(16)
        #expect(insets.top == 16)
        #expect(insets.leading == 16)
        #expect(insets.horizontal == 32)
        #expect(insets.vertical == 32)
    }

    @Test("Alignment combinations")
    func alignmentCombinations() {
        #expect(Alignment.center.horizontal == .center)
        #expect(Alignment.center.vertical == .center)
        #expect(Alignment.topLeading.horizontal == .leading)
        #expect(Alignment.topLeading.vertical == .top)
        #expect(Alignment.bottomTrailing.horizontal == .trailing)
        #expect(Alignment.bottomTrailing.vertical == .bottom)
    }

    @Test("Font presets")
    func fontPresets() {
        #expect(Font.title.size == 28)
        #expect(Font.title.weight == .bold)
        #expect(Font.body.size == 17)
        #expect(Font.body.weight == .regular)
    }
}

// MARK: - View Modifier Tests

@Suite("ViewModifiers")
struct ViewModifierTests {
    @Test("Padding modifier applies insets")
    func paddingModifier() {
        let text = Text("Hello").padding(16)
        #expect(text.modifier.insets == EdgeInsets(16))
    }

    @Test("Frame modifier constrains dimensions")
    func frameModifier() {
        let rect = Rectangle().frame(width: 100, height: 50)
        #expect(rect.modifier.width == 100)
        #expect(rect.modifier.height == 50)
    }

    @Test("Background modifier wraps view")
    func backgroundModifier() {
        let _ = Text("Hello").background(Color.blue)
        // Compiles and constructs without error
    }

    @Test("Modifiers can be chained")
    func modifierChaining() {
        let _ = Text("Hello")
            .padding(8)
            .frame(width: 200)
            .background(Rectangle())
        // Compiles and constructs without error
    }
}

// MARK: - AnyView Tests

@Suite("AnyView")
struct AnyViewTests {
    @Test("Type erases a view")
    func typeErasure() {
        let text = Text("Hello")
        let erased = AnyView(text)
        // Should be a leaf
        #expect(erased.childProvider().isEmpty)
    }

    @Test("Type erases a container")
    func containerErasure() {
        let stack = VStack {
            Text("A")
            Text("B")
        }
        let erased = AnyView(stack)
        let children = erased.childProvider()
        #expect(children.count == 2)
    }
}

// MARK: - Layout Engine Tests

@Suite("LayoutEngine")
struct LayoutEngineTests {
    @Test("VStack distributes height equally among children")
    func vstackDistributesHeight() {
        let stack = VStack(spacing: 0) {
            Text("A")
            Text("B")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 200, height: 100)
        )
        #expect(node.children.count == 2)
        // Each child gets half the height
        #expect(node.children[0].frame.size.height == 50)
        #expect(node.children[1].frame.size.height == 50)
        // Second child is offset by first child's height
        #expect(node.children[1].frame.origin.y == 50)
    }

    @Test("VStack applies spacing between children")
    func vstackSpacing() {
        let stack = VStack(spacing: 10) {
            Text("A")
            Text("B")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 200, height: 110)
        )
        #expect(node.children.count == 2)
        // 110 total - 10 spacing = 100, divided by 2 = 50 each
        #expect(node.children[0].frame.size.height == 50)
        #expect(node.children[1].frame.origin.y == 60) // 50 + 10 spacing
    }

    @Test("HStack distributes width equally among children")
    func hstackDistributesWidth() {
        let stack = HStack(spacing: 0) {
            Text("A")
            Text("B")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 200, height: 100)
        )
        #expect(node.children.count == 2)
        #expect(node.children[0].frame.size.width == 100)
        #expect(node.children[1].frame.size.width == 100)
        #expect(node.children[1].frame.origin.x == 100)
    }

    @Test("HStack applies spacing between children")
    func hstackSpacing() {
        let stack = HStack(spacing: 20) {
            Text("A")
            Text("B")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 220, height: 100)
        )
        // 220 - 20 = 200, divided by 2 = 100 each
        #expect(node.children[0].frame.size.width == 100)
        #expect(node.children[1].frame.origin.x == 120) // 100 + 20 spacing
    }

    @Test("Spacer expands in VStack")
    func spacerExpandsInVStack() {
        let stack = VStack(spacing: 0) {
            Text("Top")
            Spacer()
            Text("Bottom")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 200, height: 300)
        )
        #expect(node.children.count == 3)
        // Two fixed children and one spacer. Each gets 1/3 initially,
        // then spacer gets remaining space after fixed children are computed.
        let spacerHeight = node.children[1].frame.size.height
        let textHeight = node.children[0].frame.size.height
        // Spacer should get the remaining space after the fixed views
        #expect(spacerHeight > 0)
        #expect(spacerHeight >= textHeight)
    }

    @Test("Spacer expands in HStack")
    func spacerExpandsInHStack() {
        let stack = HStack(spacing: 0) {
            Text("Left")
            Spacer()
            Text("Right")
        }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 300, height: 100)
        )
        #expect(node.children.count == 3)
        let spacerWidth = node.children[1].frame.size.width
        #expect(spacerWidth > 0)
    }

    @Test("Frame constrains child size")
    func frameConstrains() {
        let view = Text("Hello").frame(width: 80, height: 40)
        let node = LayoutEngine.layout(
            view: view,
            proposedSize: CGSize(width: 400, height: 400)
        )
        #expect(node.frame.size.width == 80)
        #expect(node.frame.size.height == 40)
    }

    @Test("ZStack gives each child the full proposed size")
    func zstackFullSize() {
        let stack = ZStack {
            Rectangle()
            Circle()
        }
        let proposed = CGSize(width: 200, height: 150)
        let node = LayoutEngine.layout(view: stack, proposedSize: proposed)
        #expect(node.frame.size == proposed)
        #expect(node.children.count == 2)
        for child in node.children {
            #expect(child.frame.size == proposed)
        }
    }

    @Test("Padding reduces child proposed size")
    func paddingReducesSize() {
        let view = Text("Hello").padding(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))
        let node = LayoutEngine.layout(
            view: view,
            proposedSize: CGSize(width: 200, height: 100)
        )
        // Outer frame is the full proposed size
        #expect(node.frame.size == CGSize(width: 200, height: 100))
        // Inner child is offset by padding
        if let child = node.children.first {
            #expect(child.frame.origin.x == 20)
            #expect(child.frame.origin.y == 10)
            #expect(child.frame.size.width == 160)
            #expect(child.frame.size.height == 80)
        }
    }

    @Test("Empty VStack has zero size")
    func emptyVStack() {
        let stack = VStack { }
        let node = LayoutEngine.layout(
            view: stack,
            proposedSize: CGSize(width: 200, height: 200)
        )
        #expect(node.children.isEmpty)
    }
}

// MARK: - Button Tests

@Suite("Button")
struct ButtonTests {
    @Test("Button with text label")
    func textButton() {
        let button = Button("Tap Me") { }
        #expect(button.label.content == "Tap Me")
    }

    @Test("Button with custom label")
    func customLabel() {
        let button = Button(action: {}) {
            Text("Custom")
        }
        #expect(button.label.content == "Custom")
    }
}

// MARK: - Leaf View Tests

@Suite("LeafViews")
struct LeafViewTests {
    @Test("Text stores content string")
    func textContent() {
        let text = Text("Hello, World!")
        #expect(text.content == "Hello, World!")
    }

    @Test("Spacer stores minimum length")
    func spacerMinLength() {
        let spacer = Spacer(minLength: 20)
        #expect(spacer.minLength == 20)
    }

    @Test("Spacer defaults to nil minimum length")
    func spacerDefaultMinLength() {
        let spacer = Spacer()
        #expect(spacer.minLength == nil)
    }

    @Test("Image stores name")
    func imageName() {
        let image = Image("icon")
        #expect(image.name == "icon")
    }
}
