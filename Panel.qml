import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "kristianholme.ntfy"
  ipcTarget: "kristianholme.ntfy"
  manageIpc: false

  property bool settingsOpen: false
  property bool confirmDelete: false
  property string subscribeDraft: ""
  property string sendTitle: ""
  property string sendMessage: ""
  property string sendTags: ""
  property string sendPriority: "3"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var ntfy: {
    var sh = root.bar && root.bar.shell
    if (!sh || typeof sh.serviceFor !== "function") return null
    // Depend on the service map so this rebinds when the singleton appears.
    var services = sh._services
    return sh.serviceFor("kristianholme.ntfy")
  }
  readonly property var feed: ntfy && ntfy.visibleMessages ? ntfy.visibleMessages : []
  readonly property bool canSend: {
    if (!ntfy) return false
    var dest = ntfy.selectedTopic === "all" ? "" : ntfy.selectedTopic
    return ntfy.active && dest !== "" && String(sendMessage).trim() !== "" && !ntfy.publishing
  }

  function bindFocus() {
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() {
    root.controller.show()
    bindFocus()
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    settingsOpen = false
    confirmDelete = false
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function requestClose() {
    if (confirmDelete) {
      confirmDelete = false
      return
    }
    if (settingsOpen) {
      settingsOpen = false
      return
    }
    root.close()
  }

  function addTopic() {
    if (!ntfy) return
    if (ntfy.subscribe(subscribeDraft)) subscribeDraft = ""
  }

  function sendCurrent() {
    if (!ntfy || ntfy.selectedTopic === "all") return
    if (ntfy.publish(ntfy.selectedTopic, sendMessage, sendTitle, sendPriority, sendTags)) {
      sendMessage = ""
    }
  }

  onOpenedChanged: if (opened) {
    settingsOpen = false
    confirmDelete = false
    if (feedFlick) feedFlick.contentY = 0
    bindFocus()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ntfy ? ntfy.barIcon : "󰂚"
    dimmed: !ntfy || !ntfy.active
    slotSize: Style.bar.statusSlot
    tooltipText: ""
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (ntfy) ntfy.setMuted(!ntfy.muted)
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: subscribeField.activeFocus || titleField.activeFocus || tagsField.activeFocus || messageField.activeFocus
      onCloseRequested: root.requestClose()
      onActivateRequested: {
        if (!root.confirmDelete || !ntfy) return
        ntfy.deleteTopic(ntfy.selectedTopic)
        root.confirmDelete = false
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool settingsOpen: root.settingsOpen
          readonly property var ntfyService: ntfy
          readonly property color fg: root.foreground
          readonly property string ff: root.fontFamily
          function openSettings() { root.settingsOpen = true }
          function closeSettings() { root.settingsOpen = false }
          function toggleMute() {
            if (ntfy) ntfy.setMuted(!ntfy.muted)
          }
          function toggleActive() {
            if (ntfy) ntfy.setActive(!ntfy.active)
          }

          PanelHero {
            id: hero
            width: parent.width
            title: root.settingsOpen ? "Settings" : "ntfy.sh"
            meta: root.settingsOpen ? "Notifications" : (ntfy ? ntfy.heroMeta : "Off")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: header.ntfyService && header.ntfyService.active ? 1.0 : 0.5
            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                Text {
                  anchors.centerIn: parent
                  text: header.ntfyService ? header.ntfyService.barIcon : "󰂚"
                  color: header.ntfyService && header.ntfyService.muted ? Qt.darker(header.fg, 1.55) : header.fg
                  font.family: header.ff
                  font.pixelSize: Style.font.display
                }

                MouseArea {
                  id: heroBellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: header.toggleMute()
                }

                PanelToolTip {
                  visible: heroBellMouse.containsMouse
                  text: header.ntfyService && header.ntfyService.muted ? "Unmute system notifications" : "Mute system notifications"
                  fontFamily: header.ff
                }
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  visible: header.settingsOpen
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁍"
                  tooltipText: "Back"
                  foreground: header.fg
                  fontFamily: header.ff
                  fontSize: Style.font.iconLarge
                  onClicked: header.closeSettings()
                }

                PanelActionButton {
                  visible: !header.settingsOpen
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰒓"
                  tooltipText: "Settings"
                  foreground: header.fg
                  fontFamily: header.ff
                  fontSize: Style.font.iconLarge
                  onClicked: header.openSettings()
                }

                ToggleSwitch {
                  anchors.verticalCenter: parent.verticalCenter
                  checked: header.ntfyService && header.ntfyService.active
                  foreground: header.fg
                  onToggled: header.toggleActive()
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: !root.settingsOpen
          foreground: root.foreground
        }

        Column {
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            Dropdown {
              id: topicDropdown
              width: parent.width - topicMuteBtn.implicitWidth - deleteBtn.implicitWidth - parent.spacing * 2
              showLabel: false
              label: ""
              value: ntfy ? ntfy.selectedTopic : "all"
              options: ntfy ? ntfy.topicChoices : [{ value: "all", label: "All" }]
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { if (ntfy) ntfy.setSelectedTopic(value) }
            }

            PanelActionButton {
              id: topicMuteBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: ntfy && ntfy.selectionMuted ? "󰂛" : "󰝟"
              tooltipText: ntfy && ntfy.selectedTopic === "all"
                ? (ntfy.selectionMuted ? "Unmute all topics" : "Mute all topics")
                : (ntfy && ntfy.selectionMuted ? "Unmute topic" : "Mute topic")
              enabled: ntfy && ntfy.topicCount > 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.heading
              onClicked: if (ntfy) ntfy.toggleSelectionMute()
            }

            PanelActionButton {
              id: deleteBtn
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰆴"
              tooltipText: "Delete topic"
              enabled: ntfy && ntfy.selectedTopic !== "all"
              foreground: root.foreground
              hoverColor: root.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.heading
              onClicked: if (enabled) root.confirmDelete = true
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: subscribeField
              width: parent.width - subscribeBtn.implicitWidth - parent.spacing
              placeholderText: "Subscribe to topic"
              text: root.subscribeDraft
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.subscribeDraft = text
              onAccepted: root.addTopic()
            }

            Button {
              id: subscribeBtn
              text: "Add"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.addTopic()
            }
          }

          Text {
            width: parent.width
            visible: ntfy && ntfy.lastError !== ""
            text: ntfy ? ntfy.lastError : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        Column {
          visible: root.settingsOpen
          width: parent.width
          spacing: Style.space(12)

          Dropdown {
            width: parent.width
            label: "Minimum priority"
            value: ntfy ? String(ntfy.minPriority) : "1"
            options: ntfy ? ntfy.minPriorityOptions : []
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { if (ntfy) ntfy.setMinPriority(value) }
          }

          Dropdown {
            width: parent.width
            label: "Delete notifications"
            value: ntfy ? ntfy.deleteAfter : "never"
            options: ntfy ? ntfy.deleteAfterOptions : []
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { if (ntfy) ntfy.setDeleteAfter(value) }
          }
        }

        PanelSeparator {
          visible: !root.settingsOpen
          foreground: root.foreground
        }

        Item {
          visible: !root.settingsOpen
          width: parent.width
          implicitHeight: Style.space(220)

          Flickable {
            id: feedFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: feedColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
              id: feedColumn
              width: feedFlick.width
              spacing: Style.space(8)

              Text {
                width: parent.width
                visible: root.feed.length === 0
                text: ntfy && !ntfy.active ? "ntfy is off." : (ntfy && ntfy.topicCount === 0 ? "No topics yet." : "No messages yet.")
                color: Qt.darker(root.foreground, 1.45)
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: root.feed

                delegate: Item {
                  width: feedColumn.width
                  implicitHeight: msgColumn.implicitHeight + Style.space(10)

                  BorderSurface {
                    anchors.fill: parent
                    color: msgMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                    radius: Style.cornerRadius
                  }

                  Column {
                    id: msgColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(2)

                    Row {
                      width: parent.width
                      spacing: Style.space(8)

                      Text {
                        text: modelData.topic || ""
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        text: modelData.title || ""
                        width: Math.max(0, parent.width - 140)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Item {
                        width: Math.max(0, parent.width - parent.children[0].width - parent.children[1].width - timeText.implicitWidth - parent.spacing * 3)
                        height: 1
                      }

                      Text {
                        id: timeText
                        text: Model.formatWhen(modelData.time)
                        color: Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    Text {
                      width: parent.width
                      text: modelData.message || ""
                      visible: text !== ""
                      color: Qt.darker(root.foreground, 1.15)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WordWrap
                    }

                    Text {
                      width: parent.width
                      visible: modelData.tags && modelData.tags.length
                      text: modelData.tags ? modelData.tags.join("  ") : ""
                      color: Qt.darker(root.foreground, 1.45)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  MouseArea {
                    id: msgMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: modelData.click ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (ntfy && modelData.click) ntfy.openClick(modelData.click)
                  }
                }
              }
            }
          }
        }

        Column {
          visible: !root.settingsOpen
          width: parent.width
          spacing: Style.space(8)

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: titleField
              width: parent.width - priorityDropdown.width - parent.spacing
              placeholderText: "Title"
              text: root.sendTitle
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.sendTitle = text
            }

            Dropdown {
              id: priorityDropdown
              width: Style.space(110)
              showLabel: false
              value: root.sendPriority
              options: ntfy ? ntfy.sendPriorityOptions : []
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { root.sendPriority = value }
            }
          }

          TextField {
            id: tagsField
            width: parent.width
            placeholderText: "Tags (warning, skull)"
            text: root.sendTags
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.sendTags = text
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: messageField
              width: parent.width - sendBtn.implicitWidth - parent.spacing
              placeholderText: ntfy && !ntfy.active
                ? "ntfy is off"
                : (ntfy && ntfy.selectedTopic === "all" ? "Select a topic to send" : "Type a message")
              text: root.sendMessage
              enabled: ntfy && ntfy.active && ntfy.selectedTopic !== "all"
              foreground: root.foreground
              font.family: root.fontFamily
              onTextChanged: root.sendMessage = text
              onAccepted: root.sendCurrent()
            }

            Button {
              id: sendBtn
              text: "Send"
              bordered: true
              enabled: root.canSend
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.sendCurrent()
            }
          }
        }
      }

      ConfirmDialog {
        anchors.fill: parent
        z: 10
        opened: root.confirmDelete
        message: ntfy ? ("Delete topic " + ntfy.selectedTopic + "?") : "Delete topic?"
        confirmText: "Delete"
        foreground: root.foreground
        background: Color.popups.background
        fontFamily: root.fontFamily
        onCanceled: root.confirmDelete = false
        onConfirmed: {
          if (ntfy) ntfy.deleteTopic(ntfy.selectedTopic)
          root.confirmDelete = false
        }
      }
    }
  }
}
