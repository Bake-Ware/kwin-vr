# SPDX-FileCopyrightText: 2026 bake
#
# SPDX-License-Identifier: GPL-2.0-or-later

# VR-owned unit tests (see doc/VOCABULARY.md + CONTRIBUTING.md: every behavior
# change needs a test; these are the first layer of the regression armor).

find_package(Qt6 REQUIRED COMPONENTS
    Test
    QuickTest
    Qml
    Gui GuiPrivate
    Network
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

# --- auto-lease/auto-start/auto-stop policy (replug lifecycle) ---
# Pure decision logic, no kwin link: pins the latch re-arm after unplug and
# the lease-backed auto-stop gating that need a physical hotplug to exercise
# end-to-end.
add_executable(testVrAutoLeasePolicy
    testautoleasepolicy.cpp
    ../autoleasepolicy.cpp
)
target_include_directories(testVrAutoLeasePolicy PRIVATE ..)
target_link_libraries(testVrAutoLeasePolicy
    Qt::Test
)
add_test(NAME kwinvr-testAutoLeasePolicy COMMAND testVrAutoLeasePolicy)

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
    Qt6::Network
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

# --- VrFollowMode focus pull (#26 follow-up, VOC-FOCUS-010/020) ---
# Exercises focusOn(): the explicit-camera pan override used by the
# focus-pull behavior, including teardown via destroy/unregister mid-pan.
add_executable(testVrFollowMode
    testvrfollowmode.cpp
    ../vrfollowmode.cpp
    ../kwinvrhelpers.cpp
    ../kwinvirtualscreenhandle.cpp
    ../kwingraphicshelpers.cpp
)
ecm_qt_declare_logging_category(testVrFollowMode
    HEADER kwinvr_logging.h
    IDENTIFIER KWINVR
    CATEGORY_NAME kwinvr
    DEFAULT_SEVERITY Warning
)
# Same epoxy ordering constraint as the plugin (see ../CMakeLists.txt)
target_compile_options(testVrFollowMode PRIVATE -include epoxy/gl.h)
target_link_libraries(testVrFollowMode
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
add_test(NAME kwinvr-testVrFollowMode COMMAND testVrFollowMode)

# --- kcfg defaults + persistence round-trip ---
add_executable(testVrConfig testvrconfig.cpp)
kconfig_add_kcfg_files(testVrConfig GENERATE_MOC ../kwinvrconfig.kcfgc)
target_link_libraries(testVrConfig
    Qt::Test
    KF6::ConfigCore
    KF6::ConfigGui
)
add_test(NAME kwinvr-testConfig COMMAND testVrConfig)

# --- pure QML/JS logic libraries (qmltest over autotests/qml/tst_*.qml) ---
# Covers WindowSnapLogic.js (dock+stack pair classification) and
# HudPlacementLogic.js (HUD cylinder placement + #17 transient lift).
add_executable(testVrQmlLogic testqmllogic.cpp)
target_compile_definitions(testVrQmlLogic
    PRIVATE QUICK_TEST_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml")
target_link_libraries(testVrQmlLogic Qt::QuickTest)
add_test(NAME kwinvr-testQmlLogic
    COMMAND testVrQmlLogic -platform offscreen -input ${CMAKE_CURRENT_SOURCE_DIR}/qml)

# --- flat-mode boot smoke (M2 renderer seam) ---
# Boots real kwin_wayland --virtual with displayMode=Flat, flips vrActive
# over DBus, asserts zero QML load/type errors. Pins the seam against
# runtime-only QML failures (e.g. XrCamera-typed properties in shared scene
# files). Spawns its own private dbus session; ~15-40s.
add_test(NAME kwinvr-testFlatBoot
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flatboot-smoke.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatBoot PROPERTIES TIMEOUT 120)

# --- input-replay harness v0 (M2) ---
# Scripted interaction sequences via the evalInWorkspace test hook, asserting
# scene end-state: look, world-grab, scroll depth, release, reset view, and a
# real Wayland client landing in (and leaving) the workspace.
add_test(NAME kwinvr-testFlatReplay
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flat-replay.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatReplay PROPERTIES TIMEOUT 180)

# --- HUD overlay replay (M3, issue #17) ---
# Real layer-shell dock + xdg-popup land on the HUD; the popup must sit
# strictly closer to the viewer than its dock (transientDepth radial lift).
# SKIPs without the Qt 6 qml runtime or the org.kde.layershell QML module.
add_test(NAME kwinvr-testFlatHudReplay
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flat-hud-replay.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatHudReplay PROPERTIES TIMEOUT 180)

# --- stack-size replay (M3, issue #18) ---
# Two real Wayland clients, one stack-committed onto the other: the stack
# must act as one rigid container — member matches root size at commit and
# keeps matching through later resizes; cascade pose survives allocator
# re-placement. SKIPs without the Qt 6 qml runtime.
add_test(NAME kwinvr-testFlatSnapReplay
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flat-snap-replay.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatSnapReplay PROPERTIES TIMEOUT 180)

# --- auto-float replay (M3, issue #26) ---
# A real Wayland client lands on the VR virtual screen, whose pseudomirror is
# hidden by default: the window must promote itself to vr-floating and get
# allocator placement, and must stay floating when the mirror is re-shown
# (one-way promotion). SKIPs without the Qt 6 qml runtime.
add_test(NAME kwinvr-testFlatFloatReplay
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flat-float-replay.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatFloatReplay PROPERTIES TIMEOUT 180)

# --- focus-pull replay (M3, #26 follow-up) ---
# Real activation edges (new client steals focus, killing it hands focus
# back): activating a far-off vr-floating window pulls it to depth, faces it,
# and pans the world into stop-FOV; deactivation restores its saved pose.
# SKIPs without the Qt 6 qml runtime.
add_test(NAME kwinvr-testFlatFocusReplay
    COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/flat-focus-replay.sh ${CMAKE_BINARY_DIR}/bin)
set_tests_properties(kwinvr-testFlatFocusReplay PROPERTIES TIMEOUT 180)
