#include "include/bubifm77av40ex_core/bubi_fm77_av40_ex_core_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "bubi_fm77_av40_ex_core_plugin.h"

void BubiFm77Av40ExCorePluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  bubifm77av40ex_core::BubiFm77Av40ExCorePlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
