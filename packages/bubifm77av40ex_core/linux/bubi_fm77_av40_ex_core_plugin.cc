#include "include/bubifm77av40ex_core/bubi_fm77_av40_ex_core_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <map>

#include "bubi_video_texture.h"

/*
 * 映像の受け渡しだけを担うプラグイン（macOSの BubiFm77Av40ExCorePlugin.swift、
 * Windowsの bubi_fm77_av40_ex_core_plugin.cpp と同じ役割）。
 *
 * エミュレーターのライフサイクルは Dart 側の FFI が持つ。ここは
 * bfm_session* を受け取り、Texture として登録・解除するだけとする。
 * 破棄の順序は「Texture解放、セッション破棄」である（design.md 5.1）。
 */

namespace {

// macOSの Timer(timeInterval: 1.0 / 60.0) に当たる。
constexpr guint kFrameTimerIntervalMs = 16;

struct Entry {
  BubiVideoTexture* texture;  // 参照を1つ持つ
  uint64_t last_notified;
};

}  // namespace

struct _BubiFm77Av40ExCorePlugin {
  GObject parent_instance;
  FlTextureRegistrar* textures;  // 参照を1つ持つ
  // GObjectのインスタンスはC++のコンストラクタを走らせないため、
  // C++のコンテナはヒープに置き、init/disposeで構築・破棄する。
  std::map<int64_t, Entry>* entries;
  guint timer_id;
};

G_DECLARE_FINAL_TYPE(BubiFm77Av40ExCorePlugin,
                     bubi_fm77_av40_ex_core_plugin,
                     BUBI,
                     FM77_AV40_EX_CORE_PLUGIN,
                     GObject)

G_DEFINE_TYPE(BubiFm77Av40ExCorePlugin,
              bubi_fm77_av40_ex_core_plugin,
              g_object_get_type())

/*
 * 世代が変わったときだけ通知する（VID-07）。
 * 通知しても copy_pixels が同じ回数呼ばれるとは限らない。
 * エンジンは間引くため、取りこぼす前提で書く。
 */
static gboolean notify_changed_frames(gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_CORE_PLUGIN(user_data);
  for (auto& [id, entry] : *self->entries) {
    const uint64_t generation =
        bubi_video_texture_published_generation(entry.texture);
    if (generation != 0 && generation != entry.last_notified) {
      entry.last_notified = generation;
      fl_texture_registrar_mark_texture_frame_available(
          self->textures, FL_TEXTURE(entry.texture));
    }
  }
  return G_SOURCE_CONTINUE;
}

static void start_timer_if_needed(BubiFm77Av40ExCorePlugin* self) {
  if (self->timer_id != 0) {
    return;
  }
  self->timer_id =
      g_timeout_add(kFrameTimerIntervalMs, notify_changed_frames, self);
}

static void stop_timer_if_idle(BubiFm77Av40ExCorePlugin* self) {
  if (!self->entries->empty() || self->timer_id == 0) {
    return;
  }
  g_source_remove(self->timer_id);
  self->timer_id = 0;
}

static void unregister_entry(BubiFm77Av40ExCorePlugin* self, Entry& entry) {
  // 先にセッションとの縁を切る。detach は複製中なら終わるまで待つため、
  // 戻った時点で raster thread はもうセッションを読まない。Dart は
  // detach の完了を待ってからセッションを破棄する（design.md 5.1）。
  bubi_video_texture_detach(entry.texture);
  fl_texture_registrar_unregister_texture(self->textures,
                                          FL_TEXTURE(entry.texture));
  g_object_unref(entry.texture);
}

static FlMethodResponse* handle_attach(BubiFm77Av40ExCorePlugin* self,
                                       FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_INT ||
      fl_value_get_int(args) == 0) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalidSession", "セッションのアドレスが不正です", nullptr));
  }
  auto* session = reinterpret_cast<bfm_session*>(
      static_cast<intptr_t>(fl_value_get_int(args)));
  BubiVideoTexture* texture = bubi_video_texture_new(session);
  if (!fl_texture_registrar_register_texture(self->textures,
                                             FL_TEXTURE(texture))) {
    bubi_video_texture_detach(texture);
    g_object_unref(texture);
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "textureRegistrationFailed", "Textureを登録できませんでした",
        nullptr));
  }
  const int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
  (*self->entries)[id] = Entry{texture, 0};
  start_timer_if_needed(self);
  g_autoptr(FlValue) result = fl_value_new_int(id);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* handle_detach(BubiFm77Av40ExCorePlugin* self,
                                       FlValue* args) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_INT) {
    return FL_METHOD_RESPONSE(fl_method_error_response_new(
        "invalidTextureId", "Texture IDが不正です", nullptr));
  }
  auto found = self->entries->find(fl_value_get_int(args));
  if (found != self->entries->end()) {
    unregister_entry(self, found->second);
    self->entries->erase(found);
  }
  stop_timer_if_idle(self);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_CORE_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "attach") == 0) {
    response = handle_attach(self, args);
  } else if (g_strcmp0(method, "detach") == 0) {
    response = handle_detach(self, args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void bubi_fm77_av40_ex_core_plugin_dispose(GObject* object) {
  auto* self = BUBI_FM77_AV40_EX_CORE_PLUGIN(object);
  if (self->timer_id != 0) {
    g_source_remove(self->timer_id);
    self->timer_id = 0;
  }
  if (self->entries != nullptr) {
    // Dartがdetachしないまま終了した場合（ウィンドウを閉じた等）。
    // エンジンの停止処理の途中であり、raster threadが最後の描画で
    // まだテクスチャを読む可能性がある。セッションとの縁だけを切り、
    // テクスチャ自体は意図的に解放しない（プロセス終了時の小さな
    // リークと引き換えに解放後使用を防ぐ。Windows版と同じ判断）。
    for (auto& [id, entry] : *self->entries) {
      bubi_video_texture_detach(entry.texture);
    }
    delete self->entries;
    self->entries = nullptr;
  }
  g_clear_object(&self->textures);
  G_OBJECT_CLASS(bubi_fm77_av40_ex_core_plugin_parent_class)->dispose(object);
}

static void bubi_fm77_av40_ex_core_plugin_class_init(
    BubiFm77Av40ExCorePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = bubi_fm77_av40_ex_core_plugin_dispose;
}

static void bubi_fm77_av40_ex_core_plugin_init(BubiFm77Av40ExCorePlugin* self) {
  self->entries = new std::map<int64_t, Entry>();
}

void bubi_fm77_av40_ex_core_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* plugin = BUBI_FM77_AV40_EX_CORE_PLUGIN(
      g_object_new(bubi_fm77_av40_ex_core_plugin_get_type(), nullptr));
  plugin->textures = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "bubifm77av40ex/core_video",
      FL_METHOD_CODEC(codec));
  // チャンネルが破棄されたときにプラグインの参照も落とす。
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
