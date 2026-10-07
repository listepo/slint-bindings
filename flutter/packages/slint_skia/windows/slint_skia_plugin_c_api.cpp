#include "include/slint_skia/slint_skia_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "slint_skia_plugin.h"

void SlintSkiaPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  slint_skia::SlintSkiaPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
