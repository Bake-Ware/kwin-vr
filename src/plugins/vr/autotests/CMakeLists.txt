# SPDX-FileCopyrightText: 2026 bake
#
# SPDX-License-Identifier: GPL-2.0-or-later

# VR-owned unit tests (see doc/VOCABULARY.md + CONTRIBUTING.md: every behavior
# change needs a test; these are the first layer of the regression armor).

find_package(Qt6 REQUIRED COMPONENTS
    Test
    Qml
    Gui GuiPrivate
    Quick QuickPrivate
    Quick3D Quick3DPrivate
    Quick3DXr Quick3DXrPrivate)
find_package(KF6 REQUIRED COMPONENTS Config)
find_package(KDecoration3 REQUIRED)

# --- pure 3D placement logic, no kwin link needed ---
add_executable(testVrSpaceAllocator3D
    testspaceallocator3d.cpp
    ../spaceallocator3d.cpp
)
target_link_libraries(testVrSpaceAllocator3D
    Qt::Test
    Qt6::Qml
    Qt6::Quick3D
    Qt6::Quick3DPrivate
)
add_test(NAME kwinvr-testSpaceAllocator3D COMMAND testVrSpaceAllocator3D)

# --- helper math + key bindings (compiles the real kwinvrhelpers.cpp) ---
add_executable(testVrHelpers
    testvrhelpers.cpp
    ../kwinvrhelpers.cpp
    ../kwinvirtualscreenhandle.cpp
    ../kwingraphicshelpers.cpp
)
ecm_qt_declare_logging_category(testVrHelpers
    HEADER kwinvr_logging.h
    IDENTIFIER KWINVR
    CATEGORY_NAME kwinvr
    DEFAULT_SEVERITY Warning
)
# Same epoxy ordering constraint as the plugin (see ../CMakeLists.txt)
target_compile_options(testVrHelpers PRIVATE -include epoxy/gl.h)
target_link_libraries(testVrHelpers
    kwin
    Qt::Test
    Qt6::GuiPrivate
    Qt6::Quick
    Qt6::QuickPrivate
    Qt6::Quick3D
    Qt6::Quick3DPrivate
    Qt6::Quick3DXr
    Qt6::Quick3DXrPrivate
    KF6::ConfigGui
    KF6::WindowSystem
    KDecoration3::KDecoration
)
add_test(NAME kwinvr-testHelpers COMMAND testVrHelpers)

# --- kcfg defaults + persistence round-trip ---
add_executable(testVrConfig testvrconfig.cpp)
kconfig_add_kcfg_files(testVrConfig GENERATE_MOC ../kwinvrconfig.kcfgc)
target_link_libraries(testVrConfig
    Qt::Test
    KF6::ConfigCore
    KF6::ConfigGui
)
add_test(NAME kwinvr-testConfig COMMAND testVrConfig)

# --- flat-mode boot smoke (M2 renderer seam) ---
# Boots real kwin_wayland --virtual with displayMode=Flat, flips vrActive
# over DBus, asserts zero QML load/type errors. Pins the seam against
# runtime-only QML failures (e.g. XrCamera-typed properties in shared scene
# files). Spawns its own private dbus session; ~15-40s.
add_test(NAME kwinvr-testFlatBoot
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flatboot-smoke.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatBoot PROPERTIES TIMEOUT 120)
