import QtQuick
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    Component.onCompleted: root.loading = false

    Rectangle {
        anchors.fill: parent
        color: root.configuration.Color || "black"

        Image {
            anchors.top: parent.top
            anchors.left: parent.left
            fillMode: Image.Pad
            source: root.configuration.Image ? root.configuration.Image : "file:///home/bake/Pictures/omg-i-love-my-nreal-air-glasses-even-more-after-the-new-sbs-v0-doewbo0jo7oa1.webp"
            asynchronous: true
            cache: false
            onStatusChanged: {
                console.log("TopLeft wallpaper status:", status, "source:", source, "size:", sourceSize)
            }
        }
    }
}
