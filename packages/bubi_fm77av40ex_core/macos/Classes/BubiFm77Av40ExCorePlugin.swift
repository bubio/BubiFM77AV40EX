import FlutterMacOS
import Foundation

/*
 * 映像の受け渡しだけを担うプラグイン。
 *
 * エミュレーターのライフサイクルは Dart 側の FFI が持つ。ここは
 * bfm_session* を受け取り、Texture として登録・解除するだけとする。
 *
 * 破棄の順序は「Texture解放、セッション破棄」である（design.md 5.1）。
 * 逆にすると raster thread が解放済みのセッションを読む。
 */
public class BubiFm77Av40ExCorePlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private var textures: [Int64: BubiVideoTexture] = [:]
  private var timer: Timer?
  private var lastNotified: [Int64: UInt64] = [:]

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "bubi_fm77av40ex/core_video",
                                       binaryMessenger: registrar.messenger)
    let instance = BubiFm77Av40ExCorePlugin(registry: registrar.textures)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "attach":
      guard let address = call.arguments as? Int, address != 0 else {
        result(FlutterError(code: "invalidSession",
                            message: "セッションのアドレスが不正です", details: nil))
        return
      }
      let texture = BubiVideoTexture(sessionAddress: Int64(address))
      // registerTexture は platform thread から呼ぶ決まり（FlutterTexture.h）。
      let id = registry.register(texture)
      textures[id] = texture
      lastNotified[id] = 0
      startTimerIfNeeded()
      result(id)

    case "detach":
      guard let id = call.arguments as? Int else {
        result(FlutterError(code: "invalidTextureId",
                            message: "Texture IDが不正です", details: nil))
        return
      }
      let key = Int64(id)
      registry.unregisterTexture(key)
      textures.removeValue(forKey: key)
      lastNotified.removeValue(forKey: key)
      stopTimerIfIdle()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /*
   * 世代が変わったときだけ通知する（VID-07）。
   * 通知しても copyPixelBuffer が同じ回数呼ばれるとは限らない。
   * エンジンは間引くため、取りこぼす前提で書く。
   */
  private func startTimerIfNeeded() {
    guard timer == nil else { return }
    let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      guard let self = self else { return }
      for (id, texture) in self.textures {
        let generation = texture.publishedGeneration
        if generation != 0 && generation != self.lastNotified[id] {
          self.lastNotified[id] = generation
          self.registry.textureFrameAvailable(id)
        }
      }
    }
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  private func stopTimerIfIdle() {
    guard textures.isEmpty else { return }
    timer?.invalidate()
    timer = nil
  }
}
