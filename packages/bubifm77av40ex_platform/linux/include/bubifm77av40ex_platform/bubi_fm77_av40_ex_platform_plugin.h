#ifndef FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_
#define FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __attribute__((visibility("default")))
#else
#define FLUTTER_PLUGIN_EXPORT
#endif

// Flutterのツールが生成する generated_plugin_registrant.cc から呼ばれる。
// 名前は pubspec.yaml の pluginClass から導かれるため変えない。
FLUTTER_PLUGIN_EXPORT void
bubi_fm77_av40_ex_platform_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

G_END_DECLS

#endif  // FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_
