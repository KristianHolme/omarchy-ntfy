.pragma library

var TOPIC_RE = /^[-_A-Za-z0-9]{1,64}$/
var MESSAGE_CAP = 200
var SERVER = "https://ntfy.sh"

var MIN_PRIORITY_OPTIONS = [
    { value: "1", label: "Any priority" },
    { value: "2", label: "Low priority and higher" },
    { value: "3", label: "Default priority and higher" },
    { value: "4", label: "High priority and higher" },
    { value: "5", label: "Only max priority" }
]

var DELETE_AFTER_OPTIONS = [
    { value: "never", label: "Never" },
    { value: "3h", label: "After three hours" },
    { value: "1d", label: "After one day" },
    { value: "1w", label: "After one week" },
    { value: "1m", label: "After one month" }
]

var SEND_PRIORITY_OPTIONS = [
    { value: "1", label: "Min" },
    { value: "2", label: "Low" },
    { value: "3", label: "Default" },
    { value: "4", label: "High" },
    { value: "5", label: "Max" }
]

function isValidTopic(name) {
    return TOPIC_RE.test(String(name || ""))
}

function normalizeTopic(name) {
    var value = String(name || "").trim()
    return isValidTopic(value) ? value : ""
}

function clampPriority(value, fallback) {
    var n = parseInt(String(value === undefined || value === null ? fallback : value), 10)
    if (!isFinite(n)) n = fallback
    if (n < 1) n = 1
    if (n > 5) n = 5
    return n
}

function deleteAfterSeconds(key) {
    switch (String(key || "never")) {
    case "3h":
        return 3 * 3600
    case "1d":
        return 86400
    case "1w":
        return 7 * 86400
    case "1m":
        return 30 * 86400
    default:
        return 0
    }
}

function nowSec() {
    return Math.floor(Date.now() / 1000)
}

function emptyState() {
    return {
        version: 1,
        active: true,
        muted: false,
        selectedTopic: "all",
        minPriority: 1,
        deleteAfter: "never",
        topics: [],
        messages: []
    }
}

function parseState(raw) {
    var state = emptyState()
    var text = String(raw || "").trim()
    if (!text) return state

    var parsed
    try {
        parsed = JSON.parse(text)
    } catch (e) {
        return state
    }
    if (!parsed || typeof parsed !== "object") return state

    state.active = parsed.active !== false
    state.muted = parsed.muted === true
    state.selectedTopic = parsed.selectedTopic === "all" || isValidTopic(parsed.selectedTopic)
        ? String(parsed.selectedTopic)
        : "all"
    state.minPriority = clampPriority(parsed.minPriority, 1)
    var deleteAfter = String(parsed.deleteAfter || "never")
    state.deleteAfter = deleteAfterSeconds(deleteAfter) > 0 || deleteAfter === "never" ? deleteAfter : "never"

    var topics = []
    var seen = {}
    var list = parsed.topics instanceof Array ? parsed.topics : []
    for (var i = 0; i < list.length; i++) {
        var item = list[i]
        var name = normalizeTopic(item && typeof item === "object" ? item.name : item)
        if (!name || seen[name]) continue
        seen[name] = true
        topics.push({
            name: name,
            muted: item && typeof item === "object"
                ? (item.muted === true || item.enabled === false)
                : false
        })
    }
    state.topics = topics

    var messages = []
    var ids = {}
    var rows = parsed.messages instanceof Array ? parsed.messages : []
    for (var j = 0; j < rows.length; j++) {
        var msg = normalizeMessage(rows[j])
        if (!msg || ids[msg.id]) continue
        ids[msg.id] = true
        messages.push(msg)
    }
    state.messages = pruneMessages(messages, state.deleteAfter, nowSec())
    if (state.selectedTopic !== "all" && !topicIndex(state.topics, state.selectedTopic))
        state.selectedTopic = "all"
    return state
}

function serializeState(state) {
    return JSON.stringify({
        version: 1,
        active: !(state && state.active === false),
        muted: !!(state && state.muted),
        selectedTopic: state && state.selectedTopic ? String(state.selectedTopic) : "all",
        minPriority: clampPriority(state && state.minPriority, 1),
        deleteAfter: state && state.deleteAfter ? String(state.deleteAfter) : "never",
        topics: (state && state.topics instanceof Array) ? state.topics : [],
        messages: (state && state.messages instanceof Array) ? state.messages : []
    }, null, 2) + "\n"
}

function topicIndex(topics, name) {
    var list = topics instanceof Array ? topics : []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === name) return i + 1
    }
    return 0
}

function topicNames(topics) {
    var list = topics instanceof Array ? topics : []
    var names = []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name) names.push(list[i].name)
    }
    return names
}

function topicMuted(topics, name) {
    var list = topics instanceof Array ? topics : []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].name === name) return list[i].muted === true
    }
    return false
}

function topicOptions(topics) {
    var options = [{ value: "all", label: "All" }]
    var list = topics instanceof Array ? topics : []
    for (var i = 0; i < list.length; i++) {
        if (!list[i] || !list[i].name) continue
        var mark = list[i].muted === true ? " (muted)" : ""
        options.push({ value: list[i].name, label: list[i].name + mark })
    }
    return options
}

function selectionMuted(topics, selectedTopic) {
    var list = topics instanceof Array ? topics : []
    if (list.length === 0) return false
    if (selectedTopic === "all") {
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].muted !== true) return false
        }
        return true
    }
    return topicMuted(topics, selectedTopic)
}

function normalizeMessage(raw) {
    if (!raw || typeof raw !== "object") return null
    var event = String(raw.event || "message")
    if (event !== "message") return null
    var id = String(raw.id || "")
    if (!id) return null
    var tags = []
    if (raw.tags instanceof Array) {
        for (var i = 0; i < raw.tags.length; i++) tags.push(String(raw.tags[i]))
    } else if (typeof raw.tags === "string" && raw.tags) {
        tags = raw.tags.split(",").map(function(t) { return t.trim() }).filter(function(t) { return t !== "" })
    }
    return {
        id: id,
        time: parseInt(raw.time, 10) || nowSec(),
        topic: String(raw.topic || ""),
        title: String(raw.title || ""),
        message: String(raw.message || ""),
        priority: clampPriority(raw.priority, 3),
        tags: tags,
        click: String(raw.click || "")
    }
}

function parseJsonLines(raw) {
    var lines = String(raw || "").split("\n")
    var events = []
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim()
        if (!line) continue
        try {
            events.push(JSON.parse(line))
        } catch (e) {
        }
    }
    return events
}

function upsertMessage(messages, msg) {
    var list = messages instanceof Array ? messages.slice() : []
    if (!msg) return list
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id === msg.id) {
            list[i] = msg
            return list
        }
    }
    list.push(msg)
    return list
}

function removeMessage(messages, id) {
    var list = messages instanceof Array ? messages : []
    var next = []
    for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].id !== id) next.push(list[i])
    }
    return next
}

function pruneMessages(messages, deleteAfter, now) {
    var list = messages instanceof Array ? messages.slice() : []
    var maxAge = deleteAfterSeconds(deleteAfter)
    if (maxAge > 0) {
        var kept = []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && (now - (list[i].time || 0)) <= maxAge) kept.push(list[i])
        }
        list = kept
    }
    list.sort(function(a, b) { return (a.time || 0) - (b.time || 0) })
    if (list.length > MESSAGE_CAP) list = list.slice(list.length - MESSAGE_CAP)
    return list
}

function feedMessages(messages, selectedTopic) {
    var list = messages instanceof Array ? messages.slice() : []
    if (selectedTopic && selectedTopic !== "all") {
        var filtered = []
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].topic === selectedTopic) filtered.push(list[i])
        }
        list = filtered
    }
    list.sort(function(a, b) { return (b.time || 0) - (a.time || 0) })
    return list
}

function shouldNotify(msg, active, globalMuted, topics, minPriority) {
    if (!msg || !active || globalMuted) return false
    if (topicMuted(topics, msg.topic)) return false
    return clampPriority(msg.priority, 3) >= clampPriority(minPriority, 1)
}

function notifyUrgency(priority) {
    var n = clampPriority(priority, 3)
    if (n >= 4) return "critical"
    if (n <= 2) return "low"
    return "normal"
}

function safeClickUrl(value) {
    var url = String(value || "").trim()
    if (url.indexOf("https://") === 0 || url.indexOf("http://") === 0) return url
    return ""
}

function oneLine(value) {
    return String(value || "").replace(/[\r\n]+/g, " ").trim()
}

function formatTime(unix) {
    var n = parseInt(unix, 10)
    if (!isFinite(n) || n <= 0) return ""
    var d = new Date(n * 1000)
    var hh = d.getHours()
    var mm = d.getMinutes()
    var pad = function(v) { return v < 10 ? "0" + v : String(v) }
    return pad(hh) + ":" + pad(mm)
}

function formatWhen(unix) {
    var n = parseInt(unix, 10)
    if (!isFinite(n) || n <= 0) return ""
    var d = new Date(n * 1000)
    var now = new Date()
    var sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate()
    return sameDay ? formatTime(unix) : (d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate() + " " + formatTime(unix))
}

function tagsLabel(tags) {
    if (!(tags instanceof Array) || tags.length === 0) return ""
    return tags.join("  ")
}

function streamUrl(topicList) {
    if (!(topicList instanceof Array) || topicList.length === 0) return ""
    return SERVER + "/" + topicList.join(",") + "/json"
}

function pollUrl(topicList) {
    var url = streamUrl(topicList)
    return url ? (url + "?poll=1") : ""
}

function publishUrl(topic) {
    var name = normalizeTopic(topic)
    return name ? (SERVER + "/" + name) : ""
}

function heroMeta(active, connected, muted, topicCount) {
    if (!active) return "Off"
    if (muted) return "Muted"
    if (topicCount === 0) return "Subscribe to a topic"
    if (!connected) return "Connecting"
    return topicCount === 1 ? "1 topic" : (topicCount + " topics")
}
