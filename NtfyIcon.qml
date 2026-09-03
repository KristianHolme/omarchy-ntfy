import QtQuick
import qs.Commons

// Generic message bubble from the theme icon font (not the ntfy.sh trademark).
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Text {
    anchors.centerIn: parent
    text: "󰍡"
    font.family: Style.font.family
    font.pixelSize: root.iconSize
    color: root.color
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}
