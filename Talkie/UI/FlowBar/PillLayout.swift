import Foundation

/// Pure positioning math for the Flow Bar panel.
///
/// Bug 2026-06-11: reposition() read `panel.frame.size`, which is zero at panel
/// creation and transiently zero/stale while refreshStyle() swaps the hosting
/// view's rootView — topCenter/bottomCenter landed off-center by exactly
/// width/2. The panel size is therefore a constant here, never read back from
/// AppKit.
enum PillLayout {
    /// The pill's fixed panel size; FlowBarView pins its body to the same box.
    static let panelSize = CGSize(width: 260, height: 56)
    static let margin: CGFloat = 12

    static func origin(position: String, panelSize: CGSize = panelSize,
                       screenFrame: CGRect, margin: CGFloat = margin) -> CGPoint {
        switch position {
        case "bottomLeft":
            CGPoint(x: screenFrame.minX + margin, y: screenFrame.minY + margin)
        case "bottomRight":
            CGPoint(x: screenFrame.maxX - panelSize.width - margin, y: screenFrame.minY + margin)
        case "topCenter":
            CGPoint(x: screenFrame.midX - panelSize.width / 2,
                    y: screenFrame.maxY - panelSize.height - margin)
        default: // bottomCenter
            CGPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.minY + margin)
        }
    }
}
