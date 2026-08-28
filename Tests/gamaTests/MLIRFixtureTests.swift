import Testing

@testable import GamaCore
@testable import GamaMLIR

/// Byte-exact lowering fixtures captured by executing the emitter.
///
/// The older `MLIR` suite records intent with targeted `contains` checks.
/// This suite instead pins complete output so emitter changes are explicit.
@Suite("MLIR fixtures")
struct MLIRFixtureTests {
    private static let frame = Rect(x: 0, y: 0, width: 20, height: 6)

    private func structural(_ node: RenderNode) -> String {
        GamaLowering.lower(module: node, name: "probe")
    }

    private func laid(_ node: RenderNode) -> String {
        GamaLowering.lower(laidOut: LayoutEngine.layout(node, in: Self.frame), name: "probe")
    }

    private func expect(
        _ node: RenderNode,
        structural expectedStructural: String,
        laid expectedLaid: String
    ) {
        #expect(structural(node) == expectedStructural)
        #expect(laid(node) == expectedLaid)
    }

    @Test("empty pins the absent structural attribute dictionary")
    func emptyBytes() {
        expect(
            .empty,
            structural: """
            "gama.module"() ({
              "gama.empty"() : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.empty"() {x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("text pins concrete and default colors plus the SGR bitmask")
    func textBytes() {
        let node = RenderNode.text(
            "Hi",
            style: TextStyle(foreground: .red, attributes: [.bold, .underline])
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.text"() {text = "Hi", fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = "default", sgr = 9 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.text"() {text = "Hi", fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = "default", sgr = 9 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("stack pins container attributes, indentation, and laid child recursion")
    func stackBytes() {
        let node = RenderNode.stack(
            axis: .vertical,
            spacing: 1,
            alignment: .topLeading,
            children: [.text("x", style: .plain)]
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.stack"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {axis = "v", spacing = 1 : i64, halign = "leading", valign = "top"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.stack"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 0 : i64, y = 0 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
              }) {axis = "v", spacing = 1 : i64, halign = "leading", valign = "top", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("overlay pins alignment and laid child placement")
    func overlayBytes() {
        let node = RenderNode.overlay(
            alignment: .bottomTrailing,
            children: [.text("x", style: .plain)]
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.overlay"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {halign = "trailing", valign = "bottom"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.overlay"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 19 : i64, y = 5 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
              }) {halign = "trailing", valign = "bottom", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("LayoutEngine rewrites group to a top-leading overlay")
    func groupBytes() {
        let node = RenderNode.group(children: [.text("a", style: .plain)])
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.group"() ({
                "gama.text"() {text = "a", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.overlay"() ({
                "gama.text"() {text = "a", fg = "default", bg = "default", sgr = 0 : i64, x = 0 : i64, y = 0 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
              }) {halign = "leading", valign = "top", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("spacer pins its minimum and laid frame")
    func spacerBytes() {
        expect(
            .spacer(minLength: 2),
            structural: """
            "gama.module"() ({
              "gama.spacer"() {min = 2 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.spacer"() {min = 2 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("divider pins default foreground and layout-resolved axis")
    func dividerBytes() {
        expect(
            .divider(style: .plain, axis: .horizontal),
            structural: """
            "gama.module"() ({
              "gama.divider"() {fg = "default", axis = "h"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.divider"() {fg = "default", axis = "h", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )

        let nilAxisNode = RenderNode.stack(
            axis: .vertical,
            spacing: 0,
            alignment: .topLeading,
            children: [.divider(style: .plain)]
        )
        #expect(structural(nilAxisNode) == """
        "gama.module"() ({
          "gama.stack"() ({
            "gama.divider"() {fg = "default"} : () -> ()
          }) {axis = "v", spacing = 0 : i64, halign = "leading", valign = "top"} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
        #expect(laid(nilAxisNode) == """
        "gama.module"() ({
          "gama.stack"() ({
            "gama.divider"() {fg = "default", axis = "v", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 1 : i64} : () -> ()
          }) {axis = "v", spacing = 0 : i64, halign = "leading", valign = "top", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("padding pins asymmetric insets and laid inner bounds")
    func paddingBytes() {
        let node = RenderNode.padding(
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.padding"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {top = 1 : i64, leading = 2 : i64, bottom = 3 : i64, trailing = 4 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.padding"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 2 : i64, y = 1 : i64, w = 14 : i64, h = 2 : i64} : () -> ()
              }) {top = 1 : i64, leading = 2 : i64, bottom = 3 : i64, trailing = 4 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("border pins style, title, foreground, and laid inset")
    func borderBytes() {
        let node = RenderNode.border(
            .rounded,
            style: TextStyle(foreground: .red),
            title: "T",
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.border"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {style = "rounded", fg = dense<[224, 64, 64]> : tensor<3xi8>, title = "T"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.border"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 1 : i64, y = 1 : i64, w = 18 : i64, h = 4 : i64} : () -> ()
              }) {style = "rounded", fg = dense<[224, 64, 64]> : tensor<3xi8>, title = "T", x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("background pins concrete color and laid child recursion")
    func backgroundBytes() {
        let node = RenderNode.background(.blue, child: .text("x", style: .plain))
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.background"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {color = dense<[80, 128, 255]> : tensor<3xi8>} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.background"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
              }) {color = dense<[80, 128, 255]> : tensor<3xi8>, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("fixed frame pins the current structural and laid attribute orders")
    func frameBytes() {
        let node = RenderNode.frame(
            width: 10,
            height: 3,
            alignment: .bottomTrailing,
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.frame"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {width = 10 : i64, height = 3 : i64, halign = "trailing", valign = "bottom"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.frame"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 19 : i64, y = 5 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
              }) {halign = "trailing", valign = "bottom", width = 10 : i64, height = 3 : i64, x = 10 : i64, y = 3 : i64, w = 10 : i64, h = 3 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("flex frame shares gama.frame and pins its second order divergence")
    func flexFrameBytes() {
        let node = RenderNode.flexFrame(
            minWidth: 1,
            maxWidth: .max,
            minHeight: 2,
            maxHeight: 5,
            alignment: .bottomTrailing,
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.frame"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {min_width = 1 : i64, max_width = -1 : i64, min_height = 2 : i64, max_height = 5 : i64, halign = "trailing", valign = "bottom"} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.frame"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 19 : i64, y = 5 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
              }) {halign = "trailing", valign = "bottom", min_width = 1 : i64, max_width = -1 : i64, min_height = 2 : i64, max_height = 5 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("styled pins the full text style and laid frame")
    func styledBytes() {
        let node = RenderNode.styled(
            TextStyle(foreground: .red, background: .blue, attributes: [.bold]),
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.styled"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = dense<[80, 128, 255]> : tensor<3xi8>, sgr = 1 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.styled"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
              }) {fg = dense<[224, 64, 64]> : tensor<3xi8>, bg = dense<[80, 128, 255]> : tensor<3xi8>, sgr = 1 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("interactive pins full-width NodeID wrapping and laid recursion")
    func interactiveBytes() {
        let node = RenderNode.interactive(
            id: .root,
            focusable: true,
            child: .text("x", style: .plain)
        )
        expect(
            node,
            structural: """
            "gama.module"() ({
              "gama.interactive"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
              }) {id = -3750763034362895579 : i64, focusable = true} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """,
            laid: """
            "gama.module"() ({
              "gama.interactive"() ({
                "gama.text"() {text = "x", fg = "default", bg = "default", sgr = 0 : i64, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
              }) {id = -3750763034362895579 : i64, focusable = true, x = 0 : i64, y = 0 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
            }) {sym_name = "probe"} : () -> ()

            """
        )
    }

    @Test("string escaping covers exactly quote, backslash, newline, and tab")
    func stringEscapingBytes() {
        let node = RenderNode.text("q:\" b:\\ n:\n t:\t end", style: .plain)
        #expect(structural(node) == #"""
        "gama.module"() ({
          "gama.text"() {text = "q:\" b:\\ n:\n t:\t end", fg = "default", bg = "default", sgr = 0 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """#)
    }

    @Test("a hand-built laid group carries only its frame quad")
    func handBuiltLaidGroupBytes() {
        let child = RenderNode.text("a", style: .plain)
        let node = LaidOutNode(
            node: .group(children: [child]),
            frame: Rect(x: 1, y: 2, width: 20, height: 6),
            children: [
                LaidOutNode(
                    node: child,
                    frame: Rect(x: 1, y: 2, width: 1, height: 1)
                )
            ]
        )
        #expect(GamaLowering.lower(laidOut: node, name: "probe") == """
        "gama.module"() ({
          "gama.group"() ({
            "gama.text"() {text = "a", fg = "default", bg = "default", sgr = 0 : i64, x = 1 : i64, y = 2 : i64, w = 1 : i64, h = 1 : i64} : () -> ()
          }) {x = 1 : i64, y = 2 : i64, w = 20 : i64, h = 6 : i64} : () -> ()
        }) {sym_name = "probe"} : () -> ()

        """)
    }

    @Test("output ends with exactly one newline")
    func outputEndsWithExactlyOneNewline() {
        let text = structural(.text("x", style: .plain))
        #expect(text.hasSuffix("()\n"))
        #expect(!text.hasSuffix("\n\n"))
    }
}
