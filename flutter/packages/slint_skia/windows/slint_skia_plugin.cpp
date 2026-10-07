#include "slint_skia_plugin.h"

#include <dxgi.h>
#include <flutter/standard_method_codec.h>

#include <string>
#include <variant>

namespace slint_skia {

namespace {

// Dart ints arrive as int32 or int64 depending on their size.
std::optional<int64_t> IntArg(const flutter::EncodableMap* args,
                              const char* key) {
  if (args == nullptr) return std::nullopt;
  auto it = args->find(flutter::EncodableValue(key));
  if (it == args->end()) return std::nullopt;
  if (const auto* v = std::get_if<int32_t>(&it->second)) return *v;
  if (const auto* v = std::get_if<int64_t>(&it->second)) return *v;
  return std::nullopt;
}

}  // namespace

SharedTexture::SharedTexture()
    : variant_(flutter::GpuSurfaceTexture(
          kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
          [this](size_t, size_t) { return Descriptor(); })) {}

SharedTexture::~SharedTexture() {
  // Only after UnregisterTexture's callback: the raster thread is done.
  for (HANDLE h : retired_) CloseHandle(h);
  if (handle_ != nullptr) CloseHandle(handle_);
}

bool SharedTexture::SetHandle(HANDLE handle, size_t width, size_t height) {
  HANDLE own = nullptr;
  if (!DuplicateHandle(GetCurrentProcess(), handle, GetCurrentProcess(), &own,
                       0, FALSE, DUPLICATE_SAME_ACCESS)) {
    return false;
  }
  std::lock_guard<std::mutex> lock(mutex_);
  if (handle_ != nullptr) retired_.push_back(handle_);
  handle_ = own;
  width_ = width;
  height_ = height;
  return true;
}

const FlutterDesktopGpuSurfaceDescriptor* SharedTexture::Descriptor() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (HANDLE h : retired_) CloseHandle(h);
  retired_.clear();
  if (handle_ == nullptr) return nullptr;
  frame_ = {};
  frame_.struct_size = sizeof(frame_);
  frame_.handle = handle_;
  frame_.width = frame_.visible_width = width_;
  frame_.height = frame_.visible_height = height_;
  frame_.format = kFlutterDesktopPixelFormatBGRA8888;
  return &frame_;
}

void SlintSkiaPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "slint_skia",
          &flutter::StandardMethodCodec::GetInstance());
  auto plugin = std::make_unique<SlintSkiaPlugin>(registrar);
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });
  registrar->AddPlugin(std::move(plugin));
}

SlintSkiaPlugin::SlintSkiaPlugin(flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar), textures_(registrar->texture_registrar()) {}

LUID SlintSkiaPlugin::AdapterLuid() {
  if (!luid_) {
    LUID luid = {};
    flutter::FlutterView* view = registrar_->GetView();
    // ponytail: the adapter reference Flutter hands out is kept, not
    // released: one per plugin, and releasing one it did not add would be
    // worse.
    IDXGIAdapter* adapter = view != nullptr ? view->GetGraphicsAdapter() : nullptr;
    DXGI_ADAPTER_DESC desc;
    if (adapter != nullptr && SUCCEEDED(adapter->GetDesc(&desc))) {
      luid = desc.AdapterLuid;
    }
    luid_ = luid;
  }
  return *luid_;
}

void SlintSkiaPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = call.method_name();
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());

  if (method == "create") {
    auto texture = std::make_unique<SharedTexture>();
    int64_t id = textures_->RegisterTexture(texture->variant());
    if (id < 0) {
      result->Error("slint_skia", "RegisterTexture failed");
      return;
    }
    entries_[id] = std::move(texture);
    result->Success(flutter::EncodableValue(id));
    return;
  }
  if (method != "allocate" && method != "setHandle" && method != "frame" &&
      method != "dispose") {
    result->NotImplemented();
    return;
  }

  std::optional<int64_t> id = IntArg(args, "textureId");
  auto entry = id ? entries_.find(*id) : entries_.end();
  if (entry == entries_.end()) {
    result->Error("slint_skia", method + ": unknown texture");
    return;
  }

  if (method == "allocate") {
    // Rust makes the texture itself, on this adapter (Flutter's, so ANGLE
    // can open it).
    LUID luid = AdapterLuid();
    result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("luidLow"),
         flutter::EncodableValue(static_cast<int64_t>(luid.LowPart))},
        {flutter::EncodableValue("luidHigh"),
         flutter::EncodableValue(static_cast<int32_t>(luid.HighPart))},
    }));
  } else if (method == "setHandle") {
    std::optional<int64_t> handle = IntArg(args, "handle");
    std::optional<int64_t> width = IntArg(args, "width");
    std::optional<int64_t> height = IntArg(args, "height");
    if (!handle || !width || !height || *handle == 0 || *width <= 0 ||
        *height <= 0) {
      result->Error("slint_skia", "setHandle: bad arguments");
      return;
    }
    if (!entry->second->SetHandle(
            reinterpret_cast<HANDLE>(static_cast<intptr_t>(*handle)),
            static_cast<size_t>(*width), static_cast<size_t>(*height))) {
      result->Error("slint_skia", "DuplicateHandle failed");
      return;
    }
    textures_->MarkTextureFrameAvailable(*id);
    result->Success();
  } else if (method == "frame") {
    textures_->MarkTextureFrameAvailable(*id);
    result->Success();
  } else {  // dispose
    SharedTexture* texture = entry->second.release();
    entries_.erase(entry);
    textures_->UnregisterTexture(*id, [texture] { delete texture; });
    result->Success();
  }
}

}  // namespace slint_skia
