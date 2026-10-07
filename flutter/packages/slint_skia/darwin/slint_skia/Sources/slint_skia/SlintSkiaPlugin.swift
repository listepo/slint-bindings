#if os(iOS)
import Flutter
#else
import FlutterMacOS
#endif
import CoreVideo
import Metal

/// The platform half of `SkiaTextureRenderTarget` on iOS and macOS: owns
/// the textures slint-skia-ffi renders into (`rust/src/platform/metal.rs`).
/// Each is an IOSurface-backed `CVPixelBuffer`, seen by Skia as an
/// `MTLTexture` and by Flutter as a `FlutterTexture`.
public final class SlintSkiaPlugin: NSObject, FlutterPlugin {
  private let registry: FlutterTextureRegistry
  private let device = MTLCreateSystemDefaultDevice()
  private lazy var queue = device?.makeCommandQueue()
  private lazy var cache: CVMetalTextureCache? = {
    guard let device else { return nil }
    var cache: CVMetalTextureCache?
    CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    return cache
  }()
  private var textures: [Int64: SlintSkiaTexture] = [:]

  init(registry: FlutterTextureRegistry) {
    self.registry = registry
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
    let messenger = registrar.messenger()
    let registry = registrar.textures()
    #else
    let messenger = registrar.messenger
    let registry = registrar.textures
    #endif
    let channel = FlutterMethodChannel(name: "slint_skia", binaryMessenger: messenger)
    registrar.addMethodCallDelegate(SlintSkiaPlugin(registry: registry), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    func int(_ key: String) -> Int? { (args[key] as? NSNumber)?.intValue }
    switch call.method {
    case "create":
      let texture = SlintSkiaTexture()
      let id = registry.register(texture)
      textures[id] = texture
      result(NSNumber(value: id))
    case "allocate":
      guard let id = int("textureId"), let texture = textures[Int64(id)],
        let width = int("width"), let height = int("height"), width > 0, height > 0
      else {
        result(Self.error("allocate: unknown texture or bad size"))
        return
      }
      result(allocate(texture, width: width, height: height))
    case "frame":
      if let id = int("textureId") { registry.textureFrameAvailable(Int64(id)) }
      result(nil)
    case "dispose":
      if let id = int("textureId"), textures.removeValue(forKey: Int64(id)) != nil {
        registry.unregisterTexture(Int64(id))
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// A new BGRA8 IOSurface behind `texture`, and the Metal objects Rust
  /// renders into it with, as addresses.
  private func allocate(_ texture: SlintSkiaTexture, width: Int, height: Int) -> Any {
    guard let device, let queue, let cache else {
      return Self.error("no Metal device")
    }
    let attributes: [CFString: Any] = [
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
    ]
    var pixelBuffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
      let pixelBuffer
    else {
      return Self.error("CVPixelBufferCreate failed")
    }
    let usage: [CFString: Any] = [
      kCVMetalTextureUsage: NSNumber(value: MTLTextureUsage([.renderTarget, .shaderRead]).rawValue)
    ]
    var cvTexture: CVMetalTexture?
    guard
      CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pixelBuffer, usage as CFDictionary, .bgra8Unorm,
        width, height, 0, &cvTexture) == kCVReturnSuccess,
      let cvTexture, let metalTexture = CVMetalTextureGetTexture(cvTexture)
    else {
      return Self.error("CVMetalTextureCacheCreateTextureFromImage failed")
    }
    texture.update(pixelBuffer: pixelBuffer, metalTexture: cvTexture)
    return [
      "device": address(device as AnyObject),
      "queue": address(queue as AnyObject),
      "texture": address(metalTexture as AnyObject),
    ]
  }

  private static func error(_ message: String) -> FlutterError {
    FlutterError(code: "slint_skia", message: message, details: nil)
  }
}

/// Skia retains the objects itself (see `slint_skia_instance_attach_metal`).
private func address(_ object: AnyObject) -> Int {
  Int(bitPattern: Unmanaged.passUnretained(object).toOpaque())
}

/// What Flutter's raster thread samples. `update` swaps it from the platform
/// thread, so both sides take the lock.
private final class SlintSkiaTexture: NSObject, FlutterTexture {
  private let lock = NSLock()
  private var pixelBuffer: CVPixelBuffer?
  /// Backs the `MTLTexture` Skia renders into; kept until the next
  /// allocation replaces it.
  private var metalTexture: CVMetalTexture?

  func update(pixelBuffer: CVPixelBuffer, metalTexture: CVMetalTexture) {
    lock.lock()
    defer { lock.unlock() }
    self.pixelBuffer = pixelBuffer
    self.metalTexture = metalTexture
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    return pixelBuffer.map { Unmanaged.passRetained($0) }
  }
}
