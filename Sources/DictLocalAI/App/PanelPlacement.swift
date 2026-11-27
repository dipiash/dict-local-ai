import CoreGraphics

public enum PanelPlacement {
  public static func fitted(_ frame: CGRect, within visible: CGRect) -> CGRect {
    let width = min(frame.width, visible.width)
    let height = min(frame.height, visible.height)
    return CGRect(
      x: min(max(frame.minX, visible.minX), visible.maxX - width),
      y: min(max(frame.minY, visible.minY), visible.maxY - height),
      width: width, height: height)
  }

  /// New frame for a size change: the bottom-left corner stays, so the panel grows upward.
  public static func resized(_ frame: CGRect, to size: CGSize, within visible: CGRect) -> CGRect {
    fitted(CGRect(origin: frame.origin, size: size), within: visible)
  }

  /// Frame for showing the panel: a visible panel keeps its place, a hidden one goes bottom center.
  public static func shown(
    _ frame: CGRect, isVisible: Bool, within visible: CGRect, bottomInset: CGFloat = 24
  ) -> CGRect {
    if isVisible { return fitted(frame, within: visible) }
    let origin = CGPoint(x: visible.midX - frame.width / 2, y: visible.minY + bottomInset)
    return fitted(CGRect(origin: origin, size: frame.size), within: visible)
  }
}
