//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <bubifm77av40ex_core/bubi_fm77_av40_ex_core_plugin.h>
#include <bubifm77av40ex_platform/bubi_fm77_av40_ex_platform_plugin.h>
#include <file_selector_linux/file_selector_plugin.h>
#include <gamepads_linux/gamepads_linux_plugin.h>
#include <screen_retriever_linux/screen_retriever_linux_plugin.h>
#include <window_manager/window_manager_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) bubifm77av40ex_core_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "BubiFm77Av40ExCorePlugin");
  bubi_fm77_av40_ex_core_plugin_register_with_registrar(bubifm77av40ex_core_registrar);
  g_autoptr(FlPluginRegistrar) bubifm77av40ex_platform_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "BubiFm77Av40ExPlatformPlugin");
  bubi_fm77_av40_ex_platform_plugin_register_with_registrar(bubifm77av40ex_platform_registrar);
  g_autoptr(FlPluginRegistrar) file_selector_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "FileSelectorPlugin");
  file_selector_plugin_register_with_registrar(file_selector_linux_registrar);
  g_autoptr(FlPluginRegistrar) gamepads_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GamepadsLinuxPlugin");
  gamepads_linux_plugin_register_with_registrar(gamepads_linux_registrar);
  g_autoptr(FlPluginRegistrar) screen_retriever_linux_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "ScreenRetrieverLinuxPlugin");
  screen_retriever_linux_plugin_register_with_registrar(screen_retriever_linux_registrar);
  g_autoptr(FlPluginRegistrar) window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(window_manager_registrar);
}
