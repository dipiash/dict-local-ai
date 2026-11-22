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
}
