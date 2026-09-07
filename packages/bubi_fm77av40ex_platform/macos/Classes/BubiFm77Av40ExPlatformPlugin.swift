import Cocoa
import FlutterMacOS

/// 利用者が選んだ位置への永続アクセス権（security-scoped bookmark）を扱う。
///
/// Flutter公式パッケージが覆わない範囲だけをここへ置く。ダイアログ表示は
/// `file_selector` が行い、このプラグインは受け取ったパスをブックマークへ
/// 変換し、次回起動でパスへ戻す責務に限る（design.md 9、11.2）。
///
/// App Sandboxを有効にしていない現状でもブックマークは作成・解決できる。
/// 署名・公証とサンドボックス化（M2 WP7）の後も同じ経路で動くよう、
/// 最初からブックマークを正本として保存する。
public class BubiFm77Av40ExPlatformPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "bubi_fm77av40ex/platform",
      binaryMessenger: registrar.messenger)
    let instance = BubiFm77Av40ExPlatformPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let fullScreenEvents = FlutterEventChannel(
      name: "bubi_fm77av40ex/platform/fullscreen",
      binaryMessenger: registrar.messenger)
    fullScreenEvents.setStreamHandler(instance.fullScreenStreamHandler)
  }

  /// アクセスを開始したURL。解放するまで保持する。
  private var activeScopes: [String: URL] = [:]

  /// フルスクリーン状態変化（VID-03）の配信元。
  private let fullScreenStreamHandler = FullScreenStreamHandler()

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createBookmark":
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(argumentError())
        return
      }
      result(createBookmark(path: path, result: result))

    case "resolveBookmark":
      guard let arguments = call.arguments as? [String: Any],
        let token = arguments["token"] as? String
      else {
        result(argumentError())
        return
      }
      resolveBookmark(token: token, result: result)

    case "startAccess":
      guard let arguments = call.arguments as? [String: Any],
        let token = arguments["token"] as? String
      else {
        result(argumentError())
        return
      }
      startAccess(token: token, result: result)

    case "revealInFileManager":
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String
      else {
        result(argumentError())
        return
      }
      // 利用者がROMを置くフォルダーをFinderで開く。
      // 選択状態で開くので、フォルダーの中身がそのまま見える。
      NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
      result(nil)

    case "stopAccess":
      guard let arguments = call.arguments as? [String: Any],
        let token = arguments["token"] as? String
      else {
        result(argumentError())
        return
      }
      stopAccess(token: token)
      result(nil)

    case "isFullScreen":
      result(mainWindow()?.styleMask.contains(.fullScreen) ?? false)

    case "setFullScreen":
      guard let arguments = call.arguments as? [String: Any],
        let value = arguments["value"] as? Bool
      else {
        result(argumentError())
        return
      }
      setFullScreen(value)
      result(nil)

    case "picturesDirectoryPath":
      let paths = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)
      guard let path = paths.first?.path else {
        result(
          FlutterError(
            code: "notFound", message: "Pictures directory is not available.", details: nil))
        return
      }
      result(path)

    case "musicDirectoryPath":
      let musicPaths = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)
      guard let musicPath = musicPaths.first?.path else {
        result(
          FlutterError(
            code: "notFound", message: "Music directory is not available.", details: nil))
        return
      }
      result(musicPath)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// アプリの唯一のウィンドウ。フルスクリーン制御の対象にする。
  private func mainWindow() -> NSWindow? {
    NSApplication.shared.windows.first
  }

  /// 現状と異なる場合だけ切り替える。実際の状態反映は
  /// `NSWindow`の通知（[FullScreenStreamHandler]）を経由して届く。
  private func setFullScreen(_ value: Bool) {
    guard let window = mainWindow() else {
      return
    }
    let isFullScreen = window.styleMask.contains(.fullScreen)
    if isFullScreen == value {
      return
    }
    window.toggleFullScreen(nil)
  }

  private func argumentError() -> FlutterError {
    FlutterError(
      code: "invalidArgument", message: "Required arguments are missing.", details: nil)
  }

  /// パスからブックマークを作り、Base64の文字列で返す。
  private func createBookmark(path: String, result: @escaping FlutterResult) -> Any? {
    let url = URL(fileURLWithPath: path)
    do {
      let data = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil)
      return data.base64EncodedString()
    } catch {
      return FlutterError(
        code: "bookmarkFailed", message: error.localizedDescription, details: path)
    }
  }

  /// ブックマークをパスへ戻す。失効していればnilを返す。
  ///
  /// 解決結果が stale な場合も、その回のパスは有効なので返す。
  /// 呼び出し側が作り直すかどうかを決められるよう、staleを併せて返す。
  private func resolveBookmark(token: String, result: @escaping FlutterResult) {
    guard let data = Data(base64Encoded: token) else {
      result(nil)
      return
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      result(["path": url.path, "stale": stale])
    } catch {
      // 参照先が消えた、権限が失われたなど。呼び出し側は選び直しを促す。
      result(nil)
    }
  }

  private func startAccess(token: String, result: @escaping FlutterResult) {
    guard let data = Data(base64Encoded: token) else {
      result(nil)
      return
    }
    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale)
      // サンドボックス外では false を返すが、その場合もパスは使える。
      // 開始できたかどうかで停止の要否が変わるため、記録しておく。
      if url.startAccessingSecurityScopedResource() {
        activeScopes[token] = url
      }
      result(url.path)
    } catch {
      result(nil)
    }
  }

  private func stopAccess(token: String) {
    guard let url = activeScopes.removeValue(forKey: token) else {
      return
    }
    url.stopAccessingSecurityScopedResource()
  }
}

/// フルスクリーンの出入り（VID-03）をDartへ配信する。
///
/// 緑ボタンや標準ショートカットなどOS操作による変化も同じ通知経路
/// （`NSWindow.didEnterFullScreenNotification`/
/// `didExitFullScreenNotification`）で拾えるため、Dartからのコマンドが
/// 介さない変化も取りこぼさない。
private class FullScreenStreamHandler: NSObject, FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    self.eventSink = events
    guard let window = NSApplication.shared.windows.first else {
      return nil
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(didEnterFullScreen), name: NSWindow.didEnterFullScreenNotification,
      object: window)
    NotificationCenter.default.addObserver(
      self, selector: #selector(didExitFullScreen), name: NSWindow.didExitFullScreenNotification,
      object: window)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    eventSink = nil
    return nil
  }

  private var eventSink: FlutterEventSink?

  @objc private func didEnterFullScreen() {
    eventSink?(true)
  }

  @objc private func didExitFullScreen() {
    eventSink?(false)
  }
}
