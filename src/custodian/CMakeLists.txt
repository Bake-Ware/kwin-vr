# SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

find_package(Qt6 REQUIRED COMPONENTS Core DBus)
find_package(PkgConfig REQUIRED)
pkg_check_modules(Udev REQUIRED IMPORTED_TARGET libudev)

find_package(ECM REQUIRED NO_MODULE)
ecm_qt_declare_logging_category(custodian_logging_SRCS
    HEADER custodian_logging.h
    IDENTIFIER KWINVRCUSTODIAN
    CATEGORY_NAME kwinvr.custodian
    DEFAULT_SEVERITY Info
)

add_executable(kwin-vr-custodian
    main.cpp
    custodian.h custodian.cpp
    custodianprofile.h custodianprofile.cpp
    udevmonitor.h udevmonitor.cpp
    hidinit.h hidinit.cpp
    ${custodian_logging_SRCS}
)

target_link_libraries(kwin-vr-custodian
    PRIVATE
    Qt6::Core
    Qt6::DBus
    PkgConfig::Udev
)

install(TARGETS kwin-vr-custodian DESTINATION ${KDE_INSTALL_LIBEXECDIR})
