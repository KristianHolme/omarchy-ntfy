import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "kristianholme.ntfy"
  ipcTarget: "kristianholme.ntfy"
  manageIpc: false

  property bool settingsOpen: false
  property bool sendOpen: false
  property bool confirmDelete: false
  property string subscribeDraft: ""
  property string sendTitle: ""
  property string sendMessage: ""
  property string sendTags: ""
  property string sendPriority: "3"

  readonly property bool mainView: !settingsOpen && !sendOpen
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
  readonly property color iconColor: {
    if (!ntfy || !ntfy.active)
      return root.urgent
    if (ntfy.muted)
      return Color.muted
    return root.foreground
  }
  readonly property bool canSend: {
    if (!ntfy) return false
    var dest = ntfy.selectedTopic === "all" ? "" : ntfy.selectedTopic
    return ntfy.active && dest !== "" && String(sendMessage).trim() !== "" && !ntfy.publishing
  }
  readonly property string sendTopicValue: {
    if (!ntfy || ntfy.topicCount === 0) return ""
    if (ntfy.selectedTopic !== "all") return ntfy.selectedTopic
    return ntfy.allTopicNames.length ? ntfy.allTopicNames[0] : ""
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
    sendOpen = false
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
    if (sendOpen) {
      sendOpen = false
      return
    }
    root.close()
  }

  function addTopic() {
    if (!ntfy) return
    if (ntfy.subscribe(subscribeDraft)) subscribeDraft = ""
  }

  function openSend() {
    settingsOpen = false
    if (ntfy && ntfy.selectedTopic === "all" && ntfy.topicCount > 0)
      ntfy.setSelectedTopic(ntfy.allTopicNames[0])
    sendOpen = true
    Qt.callLater(function() {
      if (root.sendOpen && messageField) messageField.forceActiveFocus()
    })
  }

  function sendCurrent() {
    if (!ntfy || ntfy.selectedTopic === "all") return
    if (ntfy.publish(ntfy.selectedTopic, sendMessage, sendTitle, sendPriority, sendTags)) {
      sendMessage = ""
      sendOpen = false
      bindFocus()
    }
  }

  onOpenedChanged: if (opened) {
    settingsOpen = false
    sendOpen = false
    confirmDelete = false
    if (feedList) feedList.contentY = 0
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
    slotSize: Style.bar.statusSlot
    tooltipText: ""
    iconComponent: Component {
      Item {
        NtfyIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          color: root.iconColor
        }
      }
    }
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
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(880))

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
      onMoveRequested: function(dx, dy) {
        if (!root.mainView) return
        feedList.flick(0, dy > 0 ? -900 : 900)
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(12)

        Item {
          id: header
          width: parent.width
          implicitHeight: hero.implicitHeight
          readonly property bool settingsOpen: root.settingsOpen
          readonly property bool sendOpen: root.sendOpen
          readonly property var ntfyService: ntfy
          readonly property color fg: root.foreground
          readonly property string ff: root.fontFamily
          function openSettings() {
            root.sendOpen = false
            root.settingsOpen = true
          }
          function closeSettings() { root.settingsOpen = false }
          function openSend() { root.openSend() }
          function closeSend() { root.sendOpen = false }
          function toggleMute() {
            if (ntfy) ntfy.setMuted(!ntfy.muted)
          }
          function toggleActive() {
            if (ntfy) ntfy.setActive(!ntfy.active)
          }

          PanelHero {
            id: hero
            width: parent.width
            title: root.settingsOpen ? "Settings"
              : root.sendOpen ? "Send"
              : "ntfy.sh"
            meta: root.settingsOpen ? "Notifications"
              : root.sendOpen ? (ntfy && ntfy.selectedTopic !== "all" ? ntfy.selectedTopic : "Select a topic")
              : (ntfy ? ntfy.heroMeta : "Off")
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                width: Style.font.display
                height: Style.font.display

                NtfyIcon {
                  anchors.centerIn: parent
                  iconSize: Style.font.display
                  color: root.iconColor
                }

                MouseArea {
                  id: heroIconMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: header.toggleMute()
                }

                PanelToolTip {
                  visible: heroIconMouse.containsMouse
                  text: header.ntfyService && header.ntfyService.muted ? "Unmute system notifications" : "Mute system notifications"
                  fontFamily: header.ff
                }
              }
            }

            trailingControl: Component {
              Row {
                spacing: Style.space(4)

                PanelActionButton {
                  visible: header.settingsOpen || header.sendOpen
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰁍"
                  tooltipText: "Back"
                  foreground: header.fg
                  fontFamily: header.ff
                  fontSize: Style.font.iconLarge
                  onClicked: header.settingsOpen ? header.closeSettings() : header.closeSend()
                }

                PanelActionButton {
                  visible: root.mainView
                  anchors.verticalCenter: parent.verticalCenter
                  iconText: "󰒊"
                  tooltipText: "Send message"
                  enabled: ntfy && ntfy.active && ntfy.topicCount > 0
                  foreground: header.fg
                  fontFamily: header.ff
                  fontSize: Style.font.iconLarge
                  onClicked: header.openSend()
                }

                PanelActionButton {
                  visible: root.mainView
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
          id: mainSep1
          visible: root.mainView
          foreground: root.foreground
        }

        Column {
          id: mainControls
          visible: root.mainView
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

        Column {
          id: sendPane
          visible: root.sendOpen
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            visible: !ntfy || !ntfy.active
            text: "Turn ntfy on to send messages."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: ntfy && ntfy.active && ntfy.topicCount === 0
            text: "Subscribe to a topic first."
            color: Qt.darker(root.foreground, 1.45)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Dropdown {
            width: parent.width
            visible: ntfy && ntfy.active && ntfy.topicCount > 0
            showLabel: false
            label: ""
            value: root.sendTopicValue
            options: ntfy ? ntfy.sendTopicChoices : []
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { if (ntfy) ntfy.setSelectedTopic(value) }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)

            TextField {
              id: titleField
              width: parent.width - priorityDropdown.width - parent.spacing
              placeholderText: "Title"
              text: root.sendTitle
              enabled: ntfy && ntfy.active && ntfy.selectedTopic !== "all"
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
            enabled: ntfy && ntfy.active && ntfy.selectedTopic !== "all"
            foreground: root.foreground
            font.family: root.fontFamily
            onTextChanged: root.sendTags = text
          }

          TextField {
            id: messageField
            width: parent.width
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

          Row {
            width: parent.width
            spacing: Style.space(8)

            Item { width: parent.width - sendBtn.implicitWidth - parent.spacing; height: 1 }

            Button {
              id: sendBtn
              text: ntfy && ntfy.publishing ? "Sending…" : "Send"
              bordered: true
              enabled: root.canSend
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.sendCurrent()
            }
          }
        }

        PanelSeparator {
          id: mainSep2
          visible: root.mainView
          foreground: root.foreground
        }

        Text {
          id: emptyFeed
          visible: root.mainView && root.feed.length === 0
          width: parent.width
          text: ntfy && !ntfy.active ? "ntfy is off." : (ntfy && ntfy.topicCount === 0 ? "No topics yet." : "No messages yet.")
          color: Qt.darker(root.foreground, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: feedList
          visible: root.mainView && root.feed.length > 0
          width: parent.width
          readonly property int cap: {
            var chrome = hero.implicitHeight
              + (mainSep1.visible ? mainSep1.implicitHeight : 0)
              + (mainControls.visible ? mainControls.implicitHeight : 0)
              + (mainSep2.visible ? mainSep2.implicitHeight : 0)
              + (feedFooter.visible ? feedFooter.implicitHeight : 0)
              + (emptyFeed.visible ? emptyFeed.implicitHeight : 0)
            var gaps = column.spacing * (
              (mainSep1.visible ? 1 : 0)
              + (mainControls.visible ? 1 : 0)
              + (mainSep2.visible ? 1 : 0)
              + (emptyFeed.visible ? 1 : 0)
              + (feedFooter.visible ? 1 : 0)
            )
            return Math.max(Style.space(280),
              panel.availableCardHeight - panel.verticalContentInset - chrome - gaps)
          }
          height: Math.min(contentHeight, cap)
          clip: true
          model: root.feed
          spacing: Style.space(10)
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: NotificationCard {
            required property var modelData
            width: feedList.width
            ntfy: root.ntfy
            msg: modelData
            foreground: root.foreground
            urgent: root.urgent
            fontFamily: root.fontFamily
          }
        }

        Text {
          id: feedFooter
          visible: root.mainView && root.feed.length > 0
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(2)
          text: root.feed.length === 1
            ? "1 message"
            : root.feed.length + " messages"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.foreground
          opacity: 0.4
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
