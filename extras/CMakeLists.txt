# SPDX-FileCopyrightText: 2026 Stanislav Aleksandrov <lightofmysoul@gmail.com>
#
# SPDX-License-Identifier: GPL-2.0-or-later

# ── VR profiles ───────────────────────────────────────────────────────────────
# Install bundled profiles to /etc/vr-profiles.d/. These are the defaults
# shipped with the package; admins can add site-specific profiles alongside them.

file(GLOB VR_PROFILES "vr-profiles.d/*.conf")
install(FILES ${VR_PROFILES}
    DESTINATION "/etc/vr-profiles.d"
    COMPONENT kwin-vr-extras
)

# ── udev rules ────────────────────────────────────────────────────────────────
# Install to /usr/lib/udev/rules.d/ (the package-managed location).
# /etc/udev/rules.d/ is for local admin overrides and is not managed here.

file(GLOB VR_UDEV_RULES "udev/rules.d/*.rules")
install(FILES ${VR_UDEV_RULES}
    DESTINATION "/usr/lib/udev/rules.d"
    COMPONENT kwin-vr-extras
)

# ── systemd user units ────────────────────────────────────────────────────────
# The custodian service unit is a template (.in) that needs the libexec path
# substituted at build time. All others are installed verbatim.

find_package(ECM REQUIRED NO_MODULE)
include(KDEInstallDirs)

# Resolve KDE_INSTALL_FULL_LIBEXECDIR (needed for service ExecStart path).
# KDEInstallDirs sets KDE_INSTALL_FULL_LIBEXECDIR when included.
configure_file(
    systemd/user/kwin-vr-custodian.service.in
    "${CMAKE_CURRENT_BINARY_DIR}/kwin-vr-custodian.service"
    @ONLY
)

# Determine systemd user unit install directory.
# ECM provides KDE_INSTALL_SYSTEMDUSERUNITDIR; fall back if empty.
if(NOT KDE_INSTALL_SYSTEMDUSERUNITDIR)
    set(KDE_INSTALL_SYSTEMDUSERUNITDIR "lib/systemd/user")
endif()

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/kwin-vr-custodian.service"
    DESTINATION "${KDE_INSTALL_SYSTEMDUSERUNITDIR}"
    COMPONENT kwin-vr-extras
)

install(FILES
        systemd/user/monado.service
    DESTINATION "${KDE_INSTALL_SYSTEMDUSERUNITDIR}"
    COMPONENT kwin-vr-extras
)
