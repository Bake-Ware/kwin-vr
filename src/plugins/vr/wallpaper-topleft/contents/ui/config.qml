import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: root

    property alias cfg_Image: imageField.text
    property alias cfg_Color: colorField.text

    Kirigami.FormLayout {
        QQC2.TextField {
            id: imageField
            Kirigami.FormData.label: "Image path:"
            Layout.fillWidth: true
        }
        QQC2.Button {
            text: "Browse..."
            onClicked: fileDialog.open()
        }
        QQC2.TextField {
            id: colorField
            Kirigami.FormData.label: "Background color:"
            text: "black"
        }
    }

    FileDialog {
        id: fileDialog
        title: "Select Wallpaper"
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.bmp *.webp *.svg)"]
        onAccepted: imageField.text = selectedFile
    }
}
