# Maintainer: bake
pkgname=kwin
pkgver=6.6.3
pkgrel=1
pkgdesc='KDE Window Manager with VR support (custom build)'
arch=(x86_64 aarch64)
license=(LGPL-2.0-or-later)
url='https://kde.org/plasma-desktop/'

depends=(
  aurorae breeze gcc-libs glibc iio-sensor-proxy plasma-activities kauth kcmutils
  kcolorscheme kconfig kcoreaddons kcrash kdbusaddons kdeclarative kdecoration
  kglobalaccel kglobalacceld kguiaddons ki18n kidletime kirigami kitemmodels
  knewstuff knighttime knotifications kpackage kquickcharts kscreenlocker kservice
  ksvg kwayland kwidgetsaddons kwindowsystem kxmlgui lcms2 libcanberra
  libdisplay-info libdrm libei libepoxy libevdev libinput libpipewire
  libqaccessibilityclient-qt6 libxcb libxcvt libxkbcommon mesa milou
  pipewire-session-manager libplasma qt6-5compat qt6-base qt6-declarative qt6-svg
  qt6-tools systemd-libs wayland xcb-util-keysyms xcb-util-wm
  # VR extras
  qt6-quick3d openxr
)

makedepends=(
  extra-cmake-modules kdoctools krunner plasma-wayland-protocols python
  wayland-protocols xorg-xwayland
)

optdepends=('plasma-keyboard: virtual keyboard')

provides=(kwin=$pkgver)
conflicts=(kwin)

# Build from the local source tree — no download needed
source=()
sha256sums=()

build() {
  cmake -B build -S "$startdir" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBEXECDIR=lib \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DBUILD_TESTING=OFF \
    -DKWIN_BUILD_VR=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_KF6DocTools=TRUE
  cmake --build build -j$(nproc)
}

package() {
  DESTDIR="$pkgdir" cmake --install build
  # KWin wayland needs CAP_SYS_NICE for realtime scheduling
  setcap CAP_SYS_NICE=+ep "$pkgdir/usr/bin/kwin_wayland"
}
