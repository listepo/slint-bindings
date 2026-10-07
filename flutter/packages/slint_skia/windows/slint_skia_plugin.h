#ifndef FLUTTER_PLUGIN_SLINT_SKIA_PLUGIN_H_
#define FLUTTER_PLUGIN_SLINT_SKIA_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <vector>

namespace slint_skia {

// One Flutter texture showing the D3D12 shared texture slint-skia-ffi renders
// into (rust/src/platform/d3d.rs). Flutter's ANGLE opens it through its NT
// handle.
class SharedTexture {
 public:
  SharedTexture();
  ~SharedTexture();

  SharedTexture(const SharedTexture&) = delete;
  SharedTexture& operator=(const SharedTexture&) = delete;

  flutter::TextureVariant* variant() { return &variant_; }

  // Shows the texture behind `handle` from the next Flutter frame on. Keeps
  // a duplicate: `handle` stays the caller's.
  bool SetHandle(HANDLE handle, size_t width, size_t height);

 private:
  // Flutter's per-frame callback, on the raster thread.
  const FlutterDesktopGpuSurfaceDescriptor* Descriptor();

  std::mutex mutex_;
  HANDLE handle_ = nullptr;
  size_t width_ = 0;
  size_t height_ = 0;
  // Replaced handles, closed on the next Descriptor() call: by then Flutter
  // has finished opening whatever the previous call returned.
  std::vector<HANDLE> retired_;
  // What Descriptor() returns; raster thread only.
  FlutterDesktopGpuSurfaceDescriptor frame_ = {};
  flutter::TextureVariant variant_;
};

// The `slint_skia` method channel on Windows: create / allocate (Flutter's
// adapter LUID) / setHandle / frame / dispose.
class SlintSkiaPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit SlintSkiaPlugin(flutter::PluginRegistrarWindows* registrar);
  ~SlintSkiaPlugin() override = default;

  SlintSkiaPlugin(const SlintSkiaPlugin&) = delete;
  SlintSkiaPlugin& operator=(const SlintSkiaPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The LUID of the adapter Flutter renders with; 0/0 (the first adapter)
  // when it cannot tell.
  LUID AdapterLuid();

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* textures_;
  std::map<int64_t, std::unique_ptr<SharedTexture>> entries_;
  std::optional<LUID> luid_;
};

}  // namespace slint_skia

#endif  // FLUTTER_PLUGIN_SLINT_SKIA_PLUGIN_H_
