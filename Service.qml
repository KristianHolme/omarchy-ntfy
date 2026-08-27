import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
    id: root

    property var shell: null
    property var manifest: null

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: home + "/.local/state/omarchy"
    readonly property string statePath: stateDir + "/ntfy.json"

    property bool active: true
    property bool muted: false
    property string selectedTopic: "all"
    property int minPriority: 1
    property string deleteAfter: "never"
    property var topics: []
    property var messages: []
    property bool connected: false
    property bool connecting: false
    property string lastError: ""
    property bool publishing: false
    property bool stateLoaded: false

    property var outgoingIds: ({})
    property var notifiedIds: ({})
    property int reconnectMs: 400
    property var httpQueue: []
    property var httpCurrent: null

    readonly property var allTopicNames: Model.topicNames(topics)
    readonly property var topicChoices: Model.topicOptions(topics)
    readonly property var visibleMessages: Model.feedMessages(messages, selectedTopic)
    readonly property bool selectionMuted: Model.selectionMuted(topics, selectedTopic)
    readonly property int topicCount: topics instanceof Array ? topics.length : 0
    readonly property string heroMeta: Model.heroMeta(active, connected, muted, topicCount)
    readonly property var minPriorityOptions: Model.MIN_PRIORITY_OPTIONS
    readonly property var deleteAfterOptions: Model.DELETE_AFTER_OPTIONS
    readonly property var sendPriorityOptions: Model.SEND_PRIORITY_OPTIONS

    function scheduleSave() {
        if (!stateLoaded) return
        saveTimer.restart()
    }

    function flushState() {
        if (!stateLoaded) return
        messages = Model.pruneMessages(messages, deleteAfter, Model.nowSec())
        stateFile.setText(Model.serializeState({
            active: active,
            muted: muted,
            selectedTopic: selectedTopic,
            minPriority: minPriority,
            deleteAfter: deleteAfter,
            topics: topics,
            messages: messages
        }))
    }

    function applyState(raw) {
        if (stateLoaded) return
        var parsed = Model.parseState(raw)
        active = parsed.active
        muted = parsed.muted
        selectedTopic = parsed.selectedTopic
        minPriority = parsed.minPriority
        deleteAfter = parsed.deleteAfter
        topics = parsed.topics
        messages = parsed.messages
        stateLoaded = true
        Qt.callLater(function() {
            if (root.active) {
                pollHistory()
                restartStream()
            } else {
                stopActivity()
            }
        })
    }

    function ingestEvents(events, fromHistory) {
        if (!active) return
        if (!(events instanceof Array) || events.length === 0) return
        var next = messages instanceof Array ? messages.slice() : []
        var changed = false
        for (var i = 0; i < events.length; i++) {
            var ev = events[i]
            if (!ev || typeof ev !== "object") continue
            var kind = String(ev.event || "")
            if (kind === "open" || kind === "keepalive") {
                connected = true
                connecting = false
                lastError = ""
                continue
            }
            if (kind === "message_delete") {
                var before = next.length
                next = Model.removeMessage(next, String(ev.id || ""))
                if (next.length !== before) changed = true
                continue
            }
            var msg = Model.normalizeMessage(ev)
            if (!msg) continue
            var existed = false
            for (var j = 0; j < next.length; j++) {
                if (next[j] && next[j].id === msg.id) {
                    existed = true
                    break
                }
            }
            next = Model.upsertMessage(next, msg)
            changed = true
            if (!fromHistory && !existed) maybeNotify(msg)
        }
        if (changed) {
            messages = Model.pruneMessages(next, deleteAfter, Model.nowSec())
            scheduleSave()
        }
    }

    function maybeNotify(msg) {
        if (!msg || !msg.id) return
        if (outgoingIds[msg.id]) {
            delete outgoingIds[msg.id]
            notifiedIds[msg.id] = true
            return
        }
        if (notifiedIds[msg.id]) return
        notifiedIds[msg.id] = true
        if (!Model.shouldNotify(msg, active, muted, topics, minPriority)) return
        var title = Model.displayTitle(msg) || msg.topic || "ntfy"
        var body = Model.displayMessage(msg)
        var args = [
            "omarchy-notification-send",
            "--app-name", "ntfy",
            "-g", "󰂚",
            "-u", Model.notifyUrgency(msg.priority)
        ]
        var click = Model.safeClickUrl(msg.click)
        if (click) {
            args.push("--exec")
            args.push("xdg-open " + Util.shellQuote(click))
        }
        args.push(title)
        if (body) args.push(body)
        Quickshell.execDetached(args)
    }

    function subscribe(name) {
        var topic = Model.normalizeTopic(name)
        if (!topic) {
            lastError = "Topic names use letters, numbers, _ and - (max 64)."
            return false
        }
        var list = topics instanceof Array ? topics.slice() : []
        var idx = Model.topicIndex(list, topic)
        if (idx) {
            list[idx - 1] = { name: topic, muted: list[idx - 1].muted === true }
        } else {
            list.push({ name: topic, muted: false })
        }
        topics = list
        selectedTopic = topic
        lastError = ""
        scheduleSave()
        if (active) {
            pollHistory([topic])
            restartStream()
        }
        return true
    }

    function deleteTopic(name) {
        var topic = Model.normalizeTopic(name)
        if (!topic) return
        var nextTopics = []
        var list = topics instanceof Array ? topics : []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].name !== topic) nextTopics.push(list[i])
        }
        var nextMessages = []
        var rows = messages instanceof Array ? messages : []
        for (var j = 0; j < rows.length; j++) {
            if (rows[j] && rows[j].topic !== topic) nextMessages.push(rows[j])
        }
        topics = nextTopics
        messages = nextMessages
        if (selectedTopic === topic) selectedTopic = "all"
        scheduleSave()
        if (active) restartStream()
    }

    function setTopicMuted(name, mutedValue) {
        var topic = Model.normalizeTopic(name)
        if (!topic) return
        var list = topics instanceof Array ? topics.slice() : []
        var idx = Model.topicIndex(list, topic)
        if (!idx) return
        list[idx - 1] = { name: topic, muted: mutedValue === true }
        topics = list
        scheduleSave()
    }

    function toggleSelectionMute() {
        if (topicCount === 0) return
        var next = !selectionMuted
        if (selectedTopic === "all") {
            var list = topics instanceof Array ? topics.slice() : []
            for (var i = 0; i < list.length; i++) {
                if (!list[i]) continue
                list[i] = { name: list[i].name, muted: next }
            }
            topics = list
        } else {
            setTopicMuted(selectedTopic, next)
            return
        }
        scheduleSave()
    }

    function setSelectedTopic(value) {
        var next = value === "all" ? "all" : Model.normalizeTopic(value)
        if (!next) next = "all"
        if (next !== "all" && !Model.topicIndex(topics, next)) next = "all"
        selectedTopic = next
        scheduleSave()
    }

    function setActive(value) {
        var next = value === true
        if (active === next) return
        active = next
        lastError = ""
        scheduleSave()
        if (active) {
            pollHistory()
            restartStream()
        } else {
            stopActivity()
        }
    }

    function setMuted(value) {
        muted = value === true
        scheduleSave()
    }

    function setMinPriority(value) {
        minPriority = Model.clampPriority(value, 1)
        scheduleSave()
    }

    function setDeleteAfter(value) {
        deleteAfter = String(value || "never")
        messages = Model.pruneMessages(messages, deleteAfter, Model.nowSec())
        scheduleSave()
    }

    function publish(topic, message, title, priority, tags) {
        if (!active) {
            lastError = "ntfy is off."
            return false
        }
        var dest = Model.normalizeTopic(topic)
        var body = String(message || "")
        if (!dest) {
            lastError = "Select a topic to send."
            return false
        }
        if (!body) {
            lastError = "Message is empty."
            return false
        }
        if (publishProc.running) return false
        var url = Model.publishUrl(dest)
        var cmd = ["curl", "-sS", "-X", "POST"]
        var headline = Model.oneLine(title)
        if (headline) cmd.push("-H", "Title: " + headline)
        cmd.push("-H", "Priority: " + String(Model.clampPriority(priority, 3)))
        var tagLine = Model.oneLine(tags)
        if (tagLine) cmd.push("-H", "Tags: " + tagLine)
        cmd.push("-d", body, url)
        lastError = ""
        publishing = true
        publishProc.command = cmd
        publishProc.running = true
        return true
    }

    function openClick(value) {
        var url = Model.safeClickUrl(value)
        if (!url) return
        Quickshell.execDetached(["xdg-open", url])
    }

    function clearMessage(id) {
        var next = Model.removeMessage(messages, String(id || ""))
        if (next.length === (messages instanceof Array ? messages.length : 0)) return
        messages = next
        scheduleSave()
    }

    function copyText(value) {
        var text = String(value || "")
        if (!text) return false
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "ntfy-copy", text])
        return true
    }

    function runAction(msgId, action) {
        if (!action) return
        var kind = String(action.action || "")
        if (kind === "broadcast") {
            lastError = "Broadcast actions are Android-only."
            return
        }
        if (kind === "view") {
            openClick(action.url)
            if (action.clear) clearMessage(msgId)
            return
        }
        if (kind === "copy") {
            if (!copyText(Model.copyValue(action))) return
            if (action.clear) clearMessage(msgId)
            return
        }
        if (kind === "http") {
            enqueueHttpAction(msgId, action)
            return
        }
    }

    function enqueueHttpAction(msgId, action) {
        var cmd = Model.httpActionCommand(action)
        if (!cmd.length) {
            lastError = "Action URL is missing."
            return
        }
        var job = { msgId: String(msgId || ""), action: action, cmd: cmd }
        if (httpProc.running || httpCurrent) {
            httpQueue = httpQueue.concat([job])
            return
        }
        startHttpAction(job)
    }

    function startHttpAction(job) {
        if (!job || !job.cmd || !job.cmd.length) return
        httpCurrent = job
        lastError = ""
        httpProc.command = job.cmd
        httpProc.running = true
    }

    function finishHttpAction(ok, detail) {
        var job = httpCurrent
        httpCurrent = null
        if (!job) return
        if (!ok) lastError = detail || "Action failed"
        else if (job.action && job.action.clear) clearMessage(job.msgId)
        if (httpQueue.length) {
            var next = httpQueue[0]
            httpQueue = httpQueue.slice(1)
            Qt.callLater(function() { root.startHttpAction(next) })
        }
    }

    function pollHistory(names) {
        if (!active) return
        var list = names instanceof Array && names.length ? names : allTopicNames
        var url = Model.pollUrl(list)
        if (!url || pollProc.running) return
        pollProc.command = ["curl", "-sS", "--max-time", "20", url]
        pollProc.running = true
    }

    function stopActivity() {
        reconnectTimer.stop()
        streamProc.running = false
        pollProc.running = false
        httpQueue = []
        httpCurrent = null
        httpProc.running = false
        if (publishProc.running) {
            publishProc.running = false
            publishing = false
        }
        connected = false
        connecting = false
    }

    function restartStream() {
        reconnectTimer.stop()
        streamProc.running = false
        connected = false
        connecting = false
        reconnectMs = 400
        if (!active || allTopicNames.length === 0) return
        connecting = true
        reconnectTimer.interval = 400
        reconnectTimer.restart()
    }

    function startStream() {
        if (!active) {
            connecting = false
            connected = false
            return
        }
        var url = Model.streamUrl(allTopicNames)
        if (!url) {
            connecting = false
            connected = false
            return
        }
        connecting = true
        streamProc.command = ["curl", "-sN", "--no-buffer", "--max-time", "0", url]
        streamProc.running = true
    }

    Timer {
        id: saveTimer
        interval: 250
        repeat: false
        onTriggered: root.flushState()
    }

    Timer {
        id: reconnectTimer
        interval: 400
        repeat: false
        onTriggered: root.startStream()
    }

    Timer {
        id: pruneTimer
        interval: 60000
        repeat: true
        running: true
        onTriggered: {
            if (!root.stateLoaded) return
            var next = Model.pruneMessages(root.messages, root.deleteAfter, Model.nowSec())
            if (next.length !== root.messages.length) {
                root.messages = next
                root.scheduleSave()
            }
        }
    }

    Process {
        id: mkdirProc
        command: ["mkdir", "-p", root.stateDir]
        running: true
        onExited: Qt.callLater(function() { stateFile.reload() })
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: root.applyState(text())
        onLoadFailed: root.applyState("")
    }

    Process {
        id: streamProc
        stdout: SplitParser {
            onRead: function(line) {
                root.ingestEvents(Model.parseJsonLines(line), false)
            }
        }
        stderr: StdioCollector {
            id: streamErr
            waitForEnd: true
        }
        onExited: function(code) {
            root.connected = false
            root.connecting = false
            if (!root.active || root.allTopicNames.length === 0) return
            if (code !== 0 && streamErr.text) root.lastError = String(streamErr.text).trim()
            root.reconnectMs = Math.min(10000, Math.max(400, root.reconnectMs * 2))
            reconnectTimer.interval = root.reconnectMs
            reconnectTimer.restart()
        }
    }

    Process {
        id: pollProc
        stdout: StdioCollector {
            id: pollOut
            waitForEnd: true
            onStreamFinished: root.ingestEvents(Model.parseJsonLines(text), true)
        }
        stderr: StdioCollector {
            id: pollErr
            waitForEnd: true
        }
        onExited: function(code) {
            if (!root.active) return
            if (code !== 0 && pollErr.text) root.lastError = String(pollErr.text).trim()
        }
    }

    Process {
        id: httpProc
        stdout: StdioCollector {
            id: httpOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: httpErr
            waitForEnd: true
        }
        onExited: function(code) {
            var status = String(httpOut.text || "").trim()
            var ok = code === 0 && /^2\d\d$/.test(status)
            var detail = ""
            if (!ok) {
                if (httpErr.text) detail = String(httpErr.text).trim()
                else if (status) detail = "Action returned HTTP " + status
                else detail = "Action failed"
            }
            root.finishHttpAction(ok, detail)
        }
    }

    Process {
        id: publishProc
        stdout: StdioCollector {
            id: publishOut
            waitForEnd: true
            onStreamFinished: {
                var events = Model.parseJsonLines(text)
                for (var i = 0; i < events.length; i++) {
                    if (events[i] && events[i].id) root.outgoingIds[events[i].id] = true
                }
                root.ingestEvents(events, false)
            }
        }
        stderr: StdioCollector {
            id: publishErr
            waitForEnd: true
        }
        onExited: function(code) {
            root.publishing = false
            if (!root.active) return
            if (code !== 0) root.lastError = String(publishErr.text || "Publish failed").trim()
        }
    }
}
