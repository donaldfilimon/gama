// LayoutEngine.swift — Constraint-based layout engine
// Part of GamaUI

#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

// MARK: - LayoutNode

/// A computed layout node representing a positioned view in the layout tree.
public struct LayoutNode: Sendable, Equatable {
    /// The frame of this node in its parent's coordinate space.
    public var frame: CGRect

    /// The computed child layout nodes.
    public var children: [LayoutNode]

    /// Creates a layout node with the given frame and children.
    public init(frame: CGRect, children: [LayoutNode] = []) {
        self.frame = frame
        self.children = children
    }
}

// MARK: - LayoutEngine

/// A recursive constraint-based layout engine.
///
/// The engine traverses the view hierarchy, computing frames for each view
/// based on the proposed size from the parent and the intrinsic sizing
/// behavior of each view type.
public enum LayoutEngine {
    /// Default spacing between stack children when none is specified.
    public static let defaultSpacing: Double = 8

    /// Default leaf view size for views without intrinsic sizing.
    public static let defaultLeafSize = CGSize(width: 10, height: 10)

    /// Computes the layout tree for a view within the proposed size.
    ///
    /// - Parameters:
    ///   - view: The view to lay out.
    ///   - proposedSize: The size offered by the parent.
    /// - Returns: A `LayoutNode` tree with computed frames.
    public static func layout<V: View>(view: V, proposedSize: CGSize) -> LayoutNode {
        let anyView = AnyView(view)
        return layoutAnyView(anyView, proposedSize: proposedSize)
    }

    /// Lays out a type-erased view.
    internal static func layoutAnyView(_ view: AnyView, proposedSize: CGSize) -> LayoutNode {
        let behavior = view.layoutBehavior
        let children = view.childProvider()

        switch behavior {
        case .leaf:
            return LayoutNode(
                frame: CGRect(origin: .zero, size: proposedSize)
            )

        case .spacer:
            return LayoutNode(
                frame: CGRect(origin: .zero, size: proposedSize)
            )

        case let .vStack(spacing, _):
            return layoutVStack(
                children: children,
                spacing: spacing ?? defaultSpacing,
                proposedSize: proposedSize
            )

        case let .hStack(spacing, _):
            return layoutHStack(
                children: children,
                spacing: spacing ?? defaultSpacing,
                proposedSize: proposedSize
            )

        case .zStack:
            return layoutZStack(
                children: children,
                proposedSize: proposedSize
            )

        case let .padded(insets):
            return layoutPadded(
                children: children,
                insets: insets,
                proposedSize: proposedSize
            )

        case let .framed(width, height, _):
            return layoutFramed(
                children: children,
                width: width,
                height: height,
                proposedSize: proposedSize
            )

        case .background, .foregroundColor:
            return layoutPassthrough(
                children: children,
                proposedSize: proposedSize
            )

        case .modified, .erased:
            if let first = children.first {
                return layoutAnyView(first, proposedSize: proposedSize)
            }
            return LayoutNode(frame: CGRect(origin: .zero, size: proposedSize))
        }
    }

    // MARK: - VStack Layout

    /// Lays out children vertically, distributing height along the primary axis.
    internal static func layoutVStack(
        children: [AnyView],
        spacing: Double,
        proposedSize: CGSize
    ) -> LayoutNode {
        guard !children.isEmpty else {
            return LayoutNode(frame: CGRect(origin: .zero, size: .zero))
        }

        let totalSpacing = spacing * Double(children.count - 1)
        let availableHeight = proposedSize.height - totalSpacing

        // Classify children as spacers or fixed
        var spacerIndices: [Int] = []
        var fixedIndices: [Int] = []

        for (index, child) in children.enumerated() {
            if case .spacer = child.layoutBehavior {
                spacerIndices.append(index)
            } else {
                fixedIndices.append(index)
            }
        }

        // First pass: compute sizes for non-spacer children
        let fixedCount = fixedIndices.count
        let spacerCount = spacerIndices.count

        let heightPerFixed: Double
        if spacerCount > 0 {
            // If there are spacers, give fixed children their fair share
            heightPerFixed = fixedCount > 0 ? availableHeight / Double(fixedCount + spacerCount) : 0
        } else {
            // No spacers, divide equally among all children
            heightPerFixed = availableHeight / Double(children.count)
        }

        // Compute child sizes
        var childSizes: [CGSize] = Array(repeating: .zero, count: children.count)
        var totalFixedHeight: Double = 0

        for index in fixedIndices {
            let childProposed = CGSize(width: proposedSize.width, height: heightPerFixed)
            let childNode = layoutAnyView(children[index], proposedSize: childProposed)
            childSizes[index] = childNode.frame.size
            totalFixedHeight += childNode.frame.size.height
        }

        // Distribute remaining space to spacers
        let remainingForSpacers = max(0, availableHeight - totalFixedHeight)
        let heightPerSpacer = spacerCount > 0 ? remainingForSpacers / Double(spacerCount) : 0

        for index in spacerIndices {
            let minLength: Double
            if case let .spacer(min) = children[index].layoutBehavior {
                minLength = min ?? 0
            } else {
                minLength = 0
            }
            childSizes[index] = CGSize(
                width: proposedSize.width,
                height: max(minLength, heightPerSpacer)
            )
        }

        // Position children
        var childNodes: [LayoutNode] = []
        var yOffset: Double = 0

        for (index, child) in children.enumerated() {
            let size = childSizes[index]
            let childNode: LayoutNode

            if case .spacer = child.layoutBehavior {
                childNode = LayoutNode(
                    frame: CGRect(x: 0, y: yOffset, width: size.width, height: size.height)
                )
            } else {
                let proposed = CGSize(width: proposedSize.width, height: size.height)
                var node = layoutAnyView(child, proposedSize: proposed)
                node.frame.origin = CGPoint(x: 0, y: yOffset)
                childNode = node
            }

            childNodes.append(childNode)
            yOffset += size.height + spacing
        }

        let totalHeight = yOffset - spacing
        return LayoutNode(
            frame: CGRect(x: 0, y: 0, width: proposedSize.width, height: max(0, totalHeight)),
            children: childNodes
        )
    }

    // MARK: - HStack Layout

    /// Lays out children horizontally, distributing width along the primary axis.
    internal static func layoutHStack(
        children: [AnyView],
        spacing: Double,
        proposedSize: CGSize
    ) -> LayoutNode {
        guard !children.isEmpty else {
            return LayoutNode(frame: CGRect(origin: .zero, size: .zero))
        }

        let totalSpacing = spacing * Double(children.count - 1)
        let availableWidth = proposedSize.width - totalSpacing

        // Classify children as spacers or fixed
        var spacerIndices: [Int] = []
        var fixedIndices: [Int] = []

        for (index, child) in children.enumerated() {
            if case .spacer = child.layoutBehavior {
                spacerIndices.append(index)
            } else {
                fixedIndices.append(index)
            }
        }

        let fixedCount = fixedIndices.count
        let spacerCount = spacerIndices.count

        let widthPerFixed: Double
        if spacerCount > 0 {
            widthPerFixed = fixedCount > 0 ? availableWidth / Double(fixedCount + spacerCount) : 0
        } else {
            widthPerFixed = availableWidth / Double(children.count)
        }

        // Compute child sizes
        var childSizes: [CGSize] = Array(repeating: .zero, count: children.count)
        var totalFixedWidth: Double = 0

        for index in fixedIndices {
            let childProposed = CGSize(width: widthPerFixed, height: proposedSize.height)
            let childNode = layoutAnyView(children[index], proposedSize: childProposed)
            childSizes[index] = childNode.frame.size
            totalFixedWidth += childNode.frame.size.width
        }

        // Distribute remaining space to spacers
        let remainingForSpacers = max(0, availableWidth - totalFixedWidth)
        let widthPerSpacer = spacerCount > 0 ? remainingForSpacers / Double(spacerCount) : 0

        for index in spacerIndices {
            let minLength: Double
            if case let .spacer(min) = children[index].layoutBehavior {
                minLength = min ?? 0
            } else {
                minLength = 0
            }
            childSizes[index] = CGSize(
                width: max(minLength, widthPerSpacer),
                height: proposedSize.height
            )
        }

        // Position children
        var childNodes: [LayoutNode] = []
        var xOffset: Double = 0

        for (index, child) in children.enumerated() {
            let size = childSizes[index]
            let childNode: LayoutNode

            if case .spacer = child.layoutBehavior {
                childNode = LayoutNode(
                    frame: CGRect(x: xOffset, y: 0, width: size.width, height: size.height)
                )
            } else {
                let proposed = CGSize(width: size.width, height: proposedSize.height)
                var node = layoutAnyView(child, proposedSize: proposed)
                node.frame.origin = CGPoint(x: xOffset, y: 0)
                childNode = node
            }

            childNodes.append(childNode)
            xOffset += size.width + spacing
        }

        let totalWidth = xOffset - spacing
        return LayoutNode(
            frame: CGRect(x: 0, y: 0, width: max(0, totalWidth), height: proposedSize.height),
            children: childNodes
        )
    }

    // MARK: - ZStack Layout

    /// Lays out children overlaid, each receiving the full proposed size.
    internal static func layoutZStack(
        children: [AnyView],
        proposedSize: CGSize
    ) -> LayoutNode {
        var childNodes: [LayoutNode] = []
        for child in children {
            let node = layoutAnyView(child, proposedSize: proposedSize)
            childNodes.append(node)
        }
        return LayoutNode(
            frame: CGRect(origin: .zero, size: proposedSize),
            children: childNodes
        )
    }

    // MARK: - Padded Layout

    /// Lays out a child with padding insets subtracted from the proposed size.
    internal static func layoutPadded(
        children: [AnyView],
        insets: EdgeInsets,
        proposedSize: CGSize
    ) -> LayoutNode {
        let innerSize = CGSize(
            width: max(0, proposedSize.width - insets.horizontal),
            height: max(0, proposedSize.height - insets.vertical)
        )

        var childNodes: [LayoutNode] = []
        if let child = children.first {
            var node = layoutAnyView(child, proposedSize: innerSize)
            node.frame.origin = CGPoint(x: insets.leading, y: insets.top)
            childNodes.append(node)
        }

        return LayoutNode(
            frame: CGRect(origin: .zero, size: proposedSize),
            children: childNodes
        )
    }

    // MARK: - Framed Layout

    /// Lays out a child constrained to a fixed width and/or height.
    internal static func layoutFramed(
        children: [AnyView],
        width: Double?,
        height: Double?,
        proposedSize: CGSize
    ) -> LayoutNode {
        let constrainedSize = CGSize(
            width: width ?? proposedSize.width,
            height: height ?? proposedSize.height
        )

        var childNodes: [LayoutNode] = []
        if let child = children.first {
            let node = layoutAnyView(child, proposedSize: constrainedSize)
            childNodes.append(node)
        }

        return LayoutNode(
            frame: CGRect(origin: .zero, size: constrainedSize),
            children: childNodes
        )
    }

    // MARK: - Passthrough Layout

    /// Passes the proposed size through to the first child.
    internal static func layoutPassthrough(
        children: [AnyView],
        proposedSize: CGSize
    ) -> LayoutNode {
        if let child = children.first {
            return layoutAnyView(child, proposedSize: proposedSize)
        }
        return LayoutNode(frame: CGRect(origin: .zero, size: proposedSize))
    }
}
