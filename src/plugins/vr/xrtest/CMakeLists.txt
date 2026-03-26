# SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

qt6_add_executable(kwinvr-xrtest)

find_package(ECM REQUIRED NO_MODULE)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Quick
    Quick3D
    Quick3DXr)

qt6_add_qml_module(kwinvr-xrtest
    URI xrtest
    RESOURCE_PREFIX /
    NO_PLUGIN
    QML_FILES
        XrTest.qml
        KdeKubes.qml
    SOURCES
        main.cpp
        xrtestresult.h xrtestresult.cpp
)

target_link_libraries(kwinvr-xrtest PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Quick3D
    Qt6::Quick3DXr
    KF6::ConfigCore
)

install(TARGETS kwinvr-xrtest
    DESTINATION ${KDE_INSTALL_LIBEXECDIR}
)
