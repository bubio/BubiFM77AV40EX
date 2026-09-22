#ifndef FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_
#define FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_

// The file name and the function name are derived by the Flutter tool from
// `pluginClass` in pubspec.yaml (`window_manager_plugin.h`と同じ形).
// Keep them ASCII-only; this header is included by the app runner
// (generated_plugin_registrant.cc), which is compiled with the locale code
// page and /WX.

#include <flutter_plugin_registrar.h>

#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FLUTTER_PLUGIN_EXPORT void BubiFm77Av40ExPlatformPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_BUBI_FM77_AV40_EX_PLATFORM_PLUGIN_H_
