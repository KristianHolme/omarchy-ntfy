import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var ntfy: null
  property var msg: ({})
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property string fontFamily: Style.font.family

  readonly property int priority: Model.clampPriority(msg && msg.priority, 3)
  readonly property var attachment: msg && msg.attachment ? msg.attachment : null
  readonly property bool hasImage: Model.isImageAttachment(attachment)
  readonly property var allActions: Model.cardActions(msg)
  readonly property var shownActions: moreOpen ? allActions : Model.inlineActions(allActions)
  readonly property var extraActions: Model.overflowActions(allActions)
  readonly property var labelTags: Model.textTags(msg && msg.tags)
  readonly property bool clickable: !!(msg && Model.safeClickUrl(msg.click))
  readonly property bool showPrio: priority !== 3
  readonly property color prioColor: {
    if (priority >= 5) return root.urgent
    if (priority >= 4) return Qt.lighter(root.urgent, 1.25)
    if (priority <= 1) return Qt.darker(root.foreground, 2.1)
    if (priority <= 2) return Qt.darker(root.foreground, 1.65)
    return "transparent"
  }
  readonly property int actionColWidth: allActions.length ? Style.space(118) : 0

  property bool moreOpen: false

  implicitHeight: contentRow.implicitHeight + Style.space(16)

  onMsgChanged: moreOpen = false

  HoverHandler {
    id: cardHover
  }

  BorderSurface {
    anchors.fill: parent
    color: cardHover.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
    radius: Style.cornerRadius
  }

  Rectangle {
    width: Style.space(3)
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.topMargin: Style.space(4)
    anchors.bottomMargin: Style.space(4)
    visible: root.showPrio
    radius: width / 2
    color: root.prioColor
  }

  MouseArea {
    id: msgMouse
    z: 0
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: root.clickable ? Qt.LeftButton : Qt.NoButton
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: if (root.ntfy && root.msg) root.ntfy.openClick(root.msg.click)
  }

  Row {
    id: contentRow
    z: 1
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(root.showPrio ? 12 : 10)
    anchors.rightMargin: Style.space(10)
    spacing: Style.space(8)

    Image {
      id: iconImg
      anchors.verticalCenter: parent.verticalCenter
      width: visible ? Style.space(28) : 0
      height: Style.space(28)
      visible: status === Image.Ready
      source: root.msg && root.msg.icon ? root.msg.icon : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: true
    }

    Column {
      id: bodyCol
      width: parent.width - iconImg.width - actionCol.width
        - (iconImg.visible ? parent.spacing : 0)
        - (actionCol.visible ? parent.spacing : 0)
      spacing: Style.space(4)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          text: root.msg && root.msg.topic ? root.msg.topic : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
          width: Math.min(implicitWidth, Math.max(Style.space(48), parent.width * 0.5))
        }

        Text {
          visible: root.clickable
          text: "↗"
          color: Qt.darker(root.foreground, 1.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Item {
          width: Math.max(0, parent.width - parent.children[0].width
            - (parent.children[1].visible ? parent.children[1].width : 0)
            - timeText.implicitWidth - parent.spacing * (parent.children[1].visible ? 3 : 2))
          height: 1
        }

        Text {
          id: timeText
          text: Model.formatWhen(root.msg && root.msg.time)
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: Model.displayTitle(root.msg)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        id: messageText
        width: parent.width
        visible: text !== ""
        text: Model.displayMessage(root.msg)
        color: Qt.darker(root.foreground, 1.15)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.WordWrap
        textFormat: root.msg && root.msg.markdown ? Text.MarkdownText : Text.PlainText
        onLinkActivated: function(link) {
          if (root.ntfy) root.ntfy.openClick(link)
        }
      }

      Item {
        id: imageBox
        width: parent.width
        visible: attImage.status === Image.Ready || attImage.status === Image.Loading || attImage.status === Image.Error
        implicitHeight: attImage.status === Image.Error ? failedAttach.implicitHeight : attImage.height

        Image {
          id: attImage
          width: parent.width
          visible: status !== Image.Error
          height: {
            if (status === Image.Loading) return Style.space(72)
            if (status !== Image.Ready || sourceSize.width <= 0) return 0
            var fitted = width * sourceSize.height / sourceSize.width
            return Math.min(Math.max(fitted, 1), Style.space(168))
          }
          source: root.hasImage && root.attachment ? root.attachment.url : ""
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          cache: true
        }

        Text {
          id: failedAttach
          visible: attImage.status === Image.Error
          width: parent.width
          text: root.attachment && root.attachment.name ? root.attachment.name : "Attachment"
          color: Qt.darker(root.foreground, 1.25)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          anchors.fill: parent
          enabled: !!(root.attachment && root.attachment.url) && attImage.status !== Image.Loading
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.ntfy && root.attachment) root.ntfy.openClick(root.attachment.url)
        }
      }

      Flow {
        width: parent.width
        spacing: Style.space(6)
        visible: root.labelTags.length > 0

        Repeater {
          model: root.labelTags

          Text {
            text: modelData
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }

    Column {
      id: actionCol
      visible: root.allActions.length > 0
      width: root.actionColWidth
      spacing: Style.space(4)

      Repeater {
        model: root.shownActions

        Button {
          width: actionCol.width
          text: modelData.label || ""
          bordered: true
          enabled: Model.actionEnabled(modelData)
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: if (root.ntfy && root.msg) root.ntfy.runAction(root.msg.id, modelData)
        }
      }

      Button {
        width: actionCol.width
        visible: root.extraActions.length > 0 && !root.moreOpen
        text: "More"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.moreOpen = true
      }
    }
  }
}
