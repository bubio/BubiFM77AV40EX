import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // xib既定のフレームのまま一瞬表示されるのを避けるため、ここでは
    // 出さない。Dart側（WindowScaleController.applyInitialMultiplierIfNeeded）
    // がゲスト画面に合わせてリサイズした直後に`window_manager`経由で
    // 明示的に表示する（design.md「Window x1/x2/…の実装方式」）。
    self.orderOut(nil)
  }
}
