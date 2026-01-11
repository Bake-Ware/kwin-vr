# SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

kcmutils_generate_module_data(
    kwinvr_kcm_PART_SRCS
    MODULE_DATA_HEADER kwinvrconfigdata.h
    MODULE_DATA_CLASS_NAME KwinVRConfigData
    SETTINGS_HEADERS kwinvrconfig.h
    SETTINGS_CLASSES KWinVRConfig
    NAMESPACE KWin
)
kconfig_add_kcfg_files(kwinvr_kcm_PART_SRCS GENERATE_MOC ../kwinvrconfig.kcfgc )
kcmutils_add_qml_kcm(kwinvr_kcm SOURCES kwinvrkcm.cpp ${kwinvr_kcm_PART_SRCS})

target_link_libraries(kwinvr_kcm
    PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Quick3D

    KF6::ConfigCore
    KF6::ConfigGui
    KF6::CoreAddons
    KF6::I18n
    KF6::WindowSystem
    KF6::GlobalAccel
    KF6::KCMUtilsQuick
)

install(TARGETS kwinvr_kcm
    DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/kcms/systemsettings
)
