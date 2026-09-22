//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <bubifm77av40ex_core/bubi_fm77_av40_ex_core_plugin_c_api.h>
#include <bubifm77av40ex_platform/bubi_fm77_av40_ex_platform_plugin.h>
#include <file_selector_windows/file_selector_windows.h>
#include <gamepads_windows/gamepads_windows_plugin_c_api.h>
#include <screen_retriever_windows/screen_retriever_windows_plugin_c_api.h>
#include <window_manager/window_manager_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  BubiFm77Av40ExCorePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BubiFm77Av40ExCorePluginCApi"));
  BubiFm77Av40ExPlatformPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("BubiFm77Av40ExPlatformPlugin"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  GamepadsWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("GamepadsWindowsPluginCApi"));
  ScreenRetrieverWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenRetrieverWindowsPluginCApi"));
  WindowManagerPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WindowManagerPlugin"));
}
