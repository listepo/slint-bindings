#include "include/slint_skia/slint_skia_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <cstring>

// A texture showing the frames slint-skia-ffi rendered offscreen and read
// back (rust/src/platform/gl.rs). Dart hands each frame over on the
// platform thread; the raster thread uploads the newest one.
G_DECLARE_FINAL_TYPE(SlintSkiaTexture, slint_skia_texture, SLINT_SKIA, TEXTURE,
                     FlPixelBufferTexture)

struct _SlintSkiaTexture {
  FlPixelBufferTexture parent_instance;
  GMutex mutex;
  // The newest frame (RGBA8888 premultiplied) and its size; under `mutex`.
  GBytes* latest;
  uint32_t width;
  uint32_t height;
  // What the raster thread last uploaded from; raster thread only.
  GBytes* in_use;
};

G_DEFINE_TYPE(SlintSkiaTexture, slint_skia_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean slint_skia_texture_copy_pixels(FlPixelBufferTexture* texture,
                                               const uint8_t** buffer,
                                               uint32_t* width,
                                               uint32_t* height,
                                               GError** error) {
  SlintSkiaTexture* self = SLINT_SKIA_TEXTURE(texture);
  g_mutex_lock(&self->mutex);
  GBytes* latest = self->latest != nullptr ? g_bytes_ref(self->latest) : nullptr;
  *width = self->width;
  *height = self->height;
  g_mutex_unlock(&self->mutex);
  if (latest == nullptr) {
    g_set_error_literal(error, g_quark_from_static_string("slint_skia"), 0,
                        "no frame rendered yet");
    return FALSE;
  }
  g_clear_pointer(&self->in_use, g_bytes_unref);
  self->in_use = latest;
  *buffer = static_cast<const uint8_t*>(g_bytes_get_data(latest, nullptr));
  return TRUE;
}

// Takes over the reference to `frame`.
static void slint_skia_texture_set_frame(SlintSkiaTexture* self, GBytes* frame,
                                         uint32_t width, uint32_t height) {
  g_mutex_lock(&self->mutex);
  g_clear_pointer(&self->latest, g_bytes_unref);
  self->latest = frame;
  self->width = width;
  self->height = height;
  g_mutex_unlock(&self->mutex);
}

static void slint_skia_texture_finalize(GObject* object) {
  SlintSkiaTexture* self = SLINT_SKIA_TEXTURE(object);
  g_clear_pointer(&self->latest, g_bytes_unref);
  g_clear_pointer(&self->in_use, g_bytes_unref);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(slint_skia_texture_parent_class)->finalize(object);
}

static void slint_skia_texture_class_init(SlintSkiaTextureClass* klass) {
  G_OBJECT_CLASS(klass)->finalize = slint_skia_texture_finalize;
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels =
      slint_skia_texture_copy_pixels;
}

static void slint_skia_texture_init(SlintSkiaTexture* self) {
  g_mutex_init(&self->mutex);
}

// The `slint_skia` method channel on Linux: create / frame / dispose.
G_DECLARE_FINAL_TYPE(SlintSkiaPlugin, slint_skia_plugin, SLINT_SKIA, PLUGIN,
                     GObject)

struct _SlintSkiaPlugin {
  GObject parent_instance;
  FlTextureRegistrar* registrar;
  // Texture id (gint64*) → SlintSkiaTexture.
  GHashTable* textures;
};

G_DEFINE_TYPE(SlintSkiaPlugin, slint_skia_plugin, g_object_get_type())

// Dart ints arrive as FL_VALUE_TYPE_INT whatever their size.
static gboolean int_arg(FlValue* args, const char* key, int64_t* out) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return FALSE;
  }
  *out = fl_value_get_int(value);
  return TRUE;
}

static FlMethodResponse* error_response(const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new("slint_skia", message, nullptr));
}

static FlMethodResponse* handle_call(SlintSkiaPlugin* self,
                                     FlMethodCall* call) {
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (strcmp(method, "create") == 0) {
    SlintSkiaTexture* texture = SLINT_SKIA_TEXTURE(
        g_object_new(slint_skia_texture_get_type(), nullptr));
    if (!fl_texture_registrar_register_texture(self->registrar,
                                               FL_TEXTURE(texture))) {
      g_object_unref(texture);
      return error_response("registering the texture failed");
    }
    int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
    gint64* key = g_new(gint64, 1);
    *key = id;
    g_hash_table_insert(self->textures, key, texture);
    g_autoptr(FlValue) result = fl_value_new_int(id);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  }

  const gboolean frame = strcmp(method, "frame") == 0;
  if (!frame && strcmp(method, "dispose") != 0) {
    return FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  int64_t id = 0;
  SlintSkiaTexture* texture =
      int_arg(args, "textureId", &id)
          ? static_cast<SlintSkiaTexture*>(
                g_hash_table_lookup(self->textures, &id))
          : nullptr;
  if (texture == nullptr) return error_response("unknown texture");

  if (!frame) {
    fl_texture_registrar_unregister_texture(self->registrar,
                                            FL_TEXTURE(texture));
    g_hash_table_remove(self->textures, &id);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  int64_t pixels = 0, length = 0, width = 0, height = 0;
  if (!int_arg(args, "pixels", &pixels) || !int_arg(args, "length", &length) ||
      !int_arg(args, "width", &width) || !int_arg(args, "height", &height) ||
      pixels == 0 || width <= 0 || height <= 0 ||
      length != width * height * 4) {
    return error_response("frame: bad arguments");
  }
  // Borrowed from slint-skia-ffi until Dart's next render, which waits for
  // this reply: copy it now. ponytail: one CPU copy per frame on top of the
  // GPU read-back; a GL texture shared with Flutter's context would drop both.
  GBytes* bytes = g_bytes_new(
      reinterpret_cast<const void*>(static_cast<intptr_t>(pixels)),
      static_cast<gsize>(length));
  slint_skia_texture_set_frame(texture, bytes, static_cast<uint32_t>(width),
                               static_cast<uint32_t>(height));
  fl_texture_registrar_mark_texture_frame_available(self->registrar,
                                                    FL_TEXTURE(texture));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  g_autoptr(FlMethodResponse) response =
      handle_call(SLINT_SKIA_PLUGIN(user_data), call);
  fl_method_call_respond(call, response, nullptr);
}

static void slint_skia_plugin_dispose(GObject* object) {
  SlintSkiaPlugin* self = SLINT_SKIA_PLUGIN(object);
  g_clear_pointer(&self->textures, g_hash_table_unref);
  g_clear_object(&self->registrar);
  G_OBJECT_CLASS(slint_skia_plugin_parent_class)->dispose(object);
}

static void slint_skia_plugin_class_init(SlintSkiaPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = slint_skia_plugin_dispose;
}

static void slint_skia_plugin_init(SlintSkiaPlugin* self) {
  self->textures =
      g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free, g_object_unref);
}

void slint_skia_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  SlintSkiaPlugin* plugin = SLINT_SKIA_PLUGIN(
      g_object_new(slint_skia_plugin_get_type(), nullptr));
  plugin->registrar = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "slint_skia", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
