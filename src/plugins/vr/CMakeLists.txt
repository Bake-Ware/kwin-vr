# SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

kcoreaddons_add_plugin(vr INSTALL_NAMESPACE "kwin/plugins")

if (KWIN_BUILD_KCMS)
    add_subdirectory(kcm)
endif()

add_subdirectory(xrtest)

find_package(ECM REQUIRED NO_MODULE)

ecm_qt_declare_logging_category(vr
    HEADER kwinvr_logging.h
    IDENTIFIER KWINVR
    CATEGORY_NAME kwinvr
    DEFAULT_SEVERITY Warning
)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui GuiPrivate
    Quick QuickPrivate
    Quick3D Quick3DPrivate
    Quick3DXr Quick3DXrPrivate)

find_package(KF6 REQUIRED COMPONENTS Config CoreAddons I18n WindowSystem GlobalAccel Notifications)
find_package(KDecoration3 REQUIRED)

set_source_files_properties(qml/Logger.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt6_add_qml_module(vr
    NO_PLUGIN
    URI org.kde.kwin.vr
    QML_FILES
        qml/Main.qml
        qml/VrCursor.qml
        qml/VrInputBindings.qml
        qml/VrRay.qml
        qml/Xray.qml
        qml/XrayHud.qml
        qml/XrayHudItem.qml

        qml/XrItemHacked.qml
        qml/XrScene.qml
        qml/VrKwinCursor.qml
        qml/VrOsdWindows.qml
        qml/KwinWindowThumbnail3D.qml
        qml/VrScreenFrame.qml
        qml/KwinWindowThumbnailXrItem.qml
        qml/KwinWaylandSurface3D.qml
        qml/KwinDecorations3D.qml
        qml/KwinSurfacedWindow3D.qml
        qml/KwinWaylandSubSurface3D.qml
        qml/KwinWaylandSubSurface3DRecursive.qml
        qml/KwinDecorationModel.qml
        qml/KwinDecoratedSurfacedWindow3D.qml
        qml/VRWindow.qml
        qml/RadialMenu.qml
        qml/RadialMenuNode.qml
        qml/KwinInternalWindow3D.qml
        qml/KwinApplicationWindow.qml
        qml/KwinTransientWindow.qml
        qml/KwinTransientWindowRecursive.qml
        qml/VrFocusControl.qml
        qml/VrPicking.qml
        qml/VrHoverState.qml
        qml/VrPointerHandler.qml
        qml/VrWindowManipulation.qml
        qml/VrCursorManager.qml
        qml/VrRayController.qml
        qml/VrPointerConstraint.qml
        qml/VrBarrierConstraint.qml
        qml/VrWindowControls.qml
        qml/KwinPseudoOutputMirror.qml
        qml/Logger.qml
        qml/HeadScrollBindings.qml
        qml/VrMouseBindings.qml
        qml/YuvMaterial.qml
        qml/WindowTextureMaterial.qml

        qml/KwinShadowModel.qml
        qml/VrVignette.qml

    SOURCES
        main.cpp

        kwinvirtualscreenhandle.h kwinvirtualscreenhandle.cpp
        vrheadscroll.h vrheadscroll.cpp
        windowmodelfilter.h windowmodelfilter.cpp
        kwinwaylandsurfacemodel.h kwinwaylandsurfacemodel.cpp
        kwingraphicshelpers.h kwingraphicshelpers.cpp
        kwinwaylandsurface.h kwinwaylandsurface.cpp
        kwinwindowdecoration.h kwinwindowdecoration.cpp
        kwinshadowitem.h kwinshadowitem.cpp
        shadowgeometry.h shadowgeometry.cpp
        curvedwindowgeometry.h curvedwindowgeometry.cpp
        decorationgeometry.h decorationgeometry.cpp
        geometrytypes.h
        zstacker.h zstacker.cpp
        spaceallocator3d.h spaceallocator3d.cpp
        kwinvrbridge.h kwinvrbridge.cpp
        openxrtest.h openxrtest.cpp
        kwinvrinputdevice.h kwinvrinputdevice.cpp
        outputmodel.h outputmodel.cpp
        kwincurrentcursor.h kwincurrentcursor.cpp
        kwinvrhelpers.h kwinvrhelpers.cpp
        kwinvr.h kwinvr.cpp
        kwinvrinputfilter.h kwinvrinputfilter.cpp
        kwinvrshortcuts.h kwinvrshortcuts.cpp

        kwininternalwindow.h kwininternalwindow.cpp
        relativemotionblocker.h relativemotionblocker.cpp
        vrpointeroffset.h vrpointeroffset.cpp
        vrfollowmode.h vrfollowmode.cpp
        kwintoqquick3dinputbridge.h kwintoqquick3dinputbridge.cpp
        textureprovideritem.h textureprovideritem.cpp
        kwinvrconfigwrapper.h
        kwincompat.h

    RESOURCES
        shaders/yuv.vert
        shaders/yuv.frag
        shaders/window_texture.vert
        shaders/window_texture.frag
        shaders/vignette.vert
        shaders/vignette.frag
    )

kconfig_add_kcfg_files(vr GENERATE_MOC kwinvrconfig.kcfgc)

target_compile_definitions(vr PRIVATE
    KDE_INSTALL_FULL_LIBEXECDIR="${KDE_INSTALL_FULL_LIBEXECDIR}"
)

target_link_libraries(vr
    PRIVATE
    kwin
    Qt6::Core
    Qt6::Gui
    Qt6::GuiPrivate
    Qt6::Quick
    Qt6::QuickPrivate
    Qt6::Quick3D
    Qt6::Quick3DPrivate
    Qt6::Quick3DXr
    Qt6::Quick3DXrPrivate

    # KF6::ConfigCore
    KF6::ConfigGui
    KF6::CoreAddons
    KF6::I18n
    KF6::WindowSystem
    KF6::GlobalAccel
    KF6::Notifications

    KDecoration3::KDecoration
)
