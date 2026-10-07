cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "slint_skia")
project(${PROJECT_NAME} LANGUAGES CXX)

# The texture half of SkiaTextureRenderTarget: an FlPixelBufferTexture fed
# with the frames slint-skia-ffi renders offscreen and reads back.
set(PLUGIN_NAME "slint_skia_plugin")

list(APPEND PLUGIN_SOURCES
  "slint_skia_plugin.cc"
)

add_library(${PLUGIN_NAME} SHARED
  ${PLUGIN_SOURCES}
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# slint-skia-ffi itself is a native asset of the Dart package, bundled by
# its build hook; it loads libEGL at runtime.
set(slint_skia_bundled_libraries
  ""
  PARENT_SCOPE
)
