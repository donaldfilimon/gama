import Testing
@testable import GamaCore

@Suite
struct LayoutTests {
    @Test func vstackTwoTexts() {
        let box = Layout.layout(VStack { Text("hi"); Text("!") }, in: Size(width: 10, height: 10))
        #expect(box.size == Size(width: 2, height: 2))
        #expect(box.children[0].rect.origin == Point(x: 0, y: 0))
        #expect(box.children[1].rect.origin == Point(x: 0, y: 1))
    }

    @Test func hstackSpacerEatsLeftover() {
        let node = HStack {
            Text("A")
            Spacer()
            Text("Z")
        }
        let box = Layout.layout(node, in: Size(width: 10, height: 1))
        #expect(box.children[0].rect.origin.x == 0)
        #expect(box.children[2].rect.origin.x == 9)
        #expect(box.children[1].rect.size.width == 8)
    }

    @Test func frameMaxWidthClamps() {
        let node = Frame(maxWidth: 3) { Text("hello") }
        let box = Layout.layout(node, in: Size(width: 80, height: 1))
        #expect(box.size.width == 3)
    }

    @Test func paddingGrowsMeasuredSize() {
        let node = Padding(1) { Text("A") }
        let box = Layout.layout(node, in: Size(width: 20, height: 20))
        #expect(box.size == Size(width: 3, height: 3))
        #expect(box.children[0].rect.origin == Point(x: 1, y: 1))
    }

    @Test func listClipsToProposedHeight() {
        let node = List(id: "l", selected: 0) {
            Text("0")
            Text("1")
            Text("2")
            Text("3")
            Text("4")
        }
        let box = Layout.layout(node, in: Size(width: 8, height: 3))
        #expect(box.children.count == 3)
    }
}
