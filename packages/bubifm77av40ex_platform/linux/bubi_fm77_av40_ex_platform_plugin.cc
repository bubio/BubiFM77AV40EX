#include "include/bubifm77av40ex_platform/bubi_fm77_av40_ex_platform_plugin.h"

#include <gtk/gtk.h>

/*
 * ウィンドウの内容領域（Flutterの描画面 FlView）の大きさを直接指定・取得
 * するチャンネル（design.md「x1ウィンドウの大きさの調査」、Windows版
 * bubi_fm77_av40_ex_platform_plugin.cpp と同じチャンネル名・形）。
 *
 * `window_manager`のLinux実装は`gtk_window_get_size`/`gtk_window_resize`で
 * ウィンドウ全体を扱い、内容領域への換算に`getTitleBarHeight`
 * （ヘッダーバーの高さ）を足し引きする。ところがGTKのクライアント側装飾
 * （GNOMEのヘッダーバー）の有無やウィンドウマネージャーによって、
 * ウィンドウの大きさにヘッダーバーが含まれるかどうかが変わるため、
 * x1のゲスト画面が640x447のように縦へずれる（利用者からの報告）。
 * ここでは推測をやめ、FlViewの実際の割当てを内容領域とする。
 *
 * - 取得: FlViewの割当て（GTKの座標はFlutterの論理pxと同じ単位）
 * - 変更: ウィンドウとFlViewの差（ヘッダーバー等）をその場で測って足す
 * - 最小: FlViewのサイズ要求として設定し、GTKにウィンドウの最小サイズを
 *   計算させる（ヘッダーバーや装飾はGTKが加える）
 */

namespace {

constexpr char kMethodChannelName[] = "bubifm77av40ex/platform/window_scale";
constexpr char kEventChannelName[] =
    "bubifm77av40ex/platform/window_scale/changes";

}  // namespace

struct _BubiFm77Av40ExPlatformPlugin {
  GObject parent_instance;
  GtkWidget* view;  // 弱参照。ウィンドウの破棄とともにnullになる
  gulong size_allocate_handler;
  FlEventChannel* changes;  // 参照を1つ持つ
  gboolean listening;
  gint last_width;
  gint last_height;
};

G_DECLARE_FINAL_TYPE(BubiFm77Av40ExPlatformPlugin,
                     bubi_fm77_av40_ex_platform_plugin,
                     BUBI,
                     FM77_AV40_EX_PLATFORM_PLUGIN,
                     GObject)

G_DEFINE_TYPE(BubiFm77Av40ExPlatformPlugin,
              bubi_fm77_av40_ex_platform_plugin,
              g_object_get_type())

static FlValue* encode_size(gint width, gint height) {
  FlValue* value = fl_value_new_list();
  fl_value_append_take(value, fl_value_new_float(width));
  fl_value_append_take(value, fl_value_new_float(height));
  return value;
}

static gboolean read_number(FlValue* map, const gchar* key, double* out) {
  FlValue* value = fl_value_lookup_string(map, key);
  if (value == nullptr) {
    return FALSE;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    *out = fl_value_get_float(value);
    return TRUE;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    *out = static_cast<double>(fl_value_get_int(value));
    return TRUE;
  }
  return FALSE;
}

static void size_allocate_cb(GtkWidget* widget,
                             GdkRectangle* allocation,
                             gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(user_data);
  if (!self->listening || (allocation->width == self->last_width &&
                           allocation->height == self->last_height)) {
    return;
  }
  self->last_width = allocation->width;
  self->last_height = allocation->height;
  g_autoptr(FlValue) event =
      encode_size(allocation->width, allocation->height);
  fl_event_channel_send(self->changes, event, nullptr, nullptr);
}

static FlMethodErrorResponse* listen_cb(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(user_data);
  self->listening = TRUE;
  self->last_width = -1;
  self->last_height = -1;
  return nullptr;
}

static FlMethodErrorResponse* cancel_cb(FlEventChannel* channel,
                                        FlValue* args,
                                        gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(user_data);
  self->listening = FALSE;
  return nullptr;
}

static void set_content_size(BubiFm77Av40ExPlatformPlugin* self,
                             double width,
                             double height) {
  GtkWindow* window = GTK_WINDOW(gtk_widget_get_toplevel(self->view));
  gint window_width = 0;
  gint window_height = 0;
  gtk_window_get_size(window, &window_width, &window_height);
  GtkAllocation allocation;
  gtk_widget_get_allocation(self->view, &allocation);

  // ウィンドウの大きさのうちFlView以外が占める分（ヘッダーバー等）。
  // 装飾の方式で変わるため、計算せず実測する。まだ割り当てられて
  // いなければ（1x1）差は分からないため0とみなす。
  gint extra_width = 0;
  gint extra_height = 0;
  if (allocation.width > 1 && allocation.height > 1) {
    extra_width = MAX(window_width - allocation.width, 0);
    extra_height = MAX(window_height - allocation.height, 0);
  }
  gtk_window_resize(window, static_cast<gint>(width + 0.5) + extra_width,
                    static_cast<gint>(height + 0.5) + extra_height);
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* self = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);

  g_autoptr(FlMethodResponse) response = nullptr;
  if (self->view == nullptr) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "noWindow", "ウィンドウがまだありません", nullptr));
  } else if (g_strcmp0(method, "getContentSize") == 0) {
    GtkAllocation allocation;
    gtk_widget_get_allocation(self->view, &allocation);
    g_autoptr(FlValue) result =
        encode_size(allocation.width, allocation.height);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setContentSize") == 0 ||
             g_strcmp0(method, "setMinimumContentSize") == 0) {
    double width = 0;
    double height = 0;
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP ||
        !read_number(args, "width", &width) ||
        !read_number(args, "height", &height)) {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "invalidSize", "widthとheightが必要です", nullptr));
    } else {
      if (g_strcmp0(method, "setMinimumContentSize") == 0) {
        gtk_widget_set_size_request(self->view,
                                    static_cast<gint>(width + 0.5),
                                    static_cast<gint>(height + 0.5));
      } else {
        set_content_size(self, width, height);
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(method_call, response, nullptr);
}

static void bubi_fm77_av40_ex_platform_plugin_dispose(GObject* object) {
  auto* self = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(object);
  if (self->view != nullptr) {
    g_clear_signal_handler(&self->size_allocate_handler, self->view);
    g_object_remove_weak_pointer(G_OBJECT(self->view),
                                 reinterpret_cast<gpointer*>(&self->view));
    self->view = nullptr;
  }
  g_clear_object(&self->changes);
  G_OBJECT_CLASS(bubi_fm77_av40_ex_platform_plugin_parent_class)
      ->dispose(object);
}

static void bubi_fm77_av40_ex_platform_plugin_class_init(
    BubiFm77Av40ExPlatformPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = bubi_fm77_av40_ex_platform_plugin_dispose;
}

static void bubi_fm77_av40_ex_platform_plugin_init(
    BubiFm77Av40ExPlatformPlugin* self) {}

void bubi_fm77_av40_ex_platform_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  auto* plugin = BUBI_FM77_AV40_EX_PLATFORM_PLUGIN(
      g_object_new(bubi_fm77_av40_ex_platform_plugin_get_type(), nullptr));

  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view != nullptr) {
    plugin->view = GTK_WIDGET(view);
    g_object_add_weak_pointer(G_OBJECT(plugin->view),
                              reinterpret_cast<gpointer*>(&plugin->view));
    plugin->size_allocate_handler =
        g_signal_connect(plugin->view, "size-allocate",
                         G_CALLBACK(size_allocate_cb), plugin);
  }

  FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  plugin->changes = fl_event_channel_new(messenger, kEventChannelName,
                                         FL_METHOD_CODEC(codec));
  fl_event_channel_set_stream_handlers(plugin->changes, listen_cb, cancel_cb,
                                       plugin, nullptr);

  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(messenger, kMethodChannelName,
                            FL_METHOD_CODEC(codec));
  // チャンネルが破棄されたときにプラグインの参照も落とす。
  fl_method_channel_set_method_call_handler(channel, method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);

  g_object_unref(plugin);
}
