cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "slint_skia")
project(${PROJECT_NAME} LANGUAGES CXX)

cmake_policy(VERSION 3.14...3.25)

# The texture half of SkiaTextureRenderTarget: shows the D3D12 shared texture
# slint-skia-ffi renders into through a flutter::GpuSurfaceTexture.
set(PLUGIN_NAME "slint_skia_plugin")

list(APPEND PLUGIN_SOURCES
  "slint_skia_plugin.cpp"
  "slint_skia_plugin.h"
)

add_library(${PLUGIN_NAME} SHARED
  "include/slint_skia/slint_skia_plugin_c_api.h"
  "slint_skia_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# slint-skia-ffi itself is a native asset of the Dart package, bundled by
# its build hook.
set(slint_skia_bundled_libraries
  ""
  PARENT_SCOPE
)
