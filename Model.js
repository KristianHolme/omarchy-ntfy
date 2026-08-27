.pragma library
.import "Emojis.js" as Emojis

var TOPIC_RE = /^[-_A-Za-z0-9]{1,64}$/
var MESSAGE_CAP = 200
var SERVER = "https://ntfy.sh"
var INLINE_ACTION_LIMIT = 6
var IMAGE_NAME_RE = /\.(jpe?g|png|gif|webp|bmp|svg)(\?|#|$)/i

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
        click: String(raw.click || ""),
        icon: safeClickUrl(raw.icon),
        markdown: raw.markdown === true || String(raw.content_type || "").toLowerCase() === "text/markdown",
        attachment: normalizeAttachment(raw.attachment),
        actions: normalizeActions(raw.actions)
    }
}

function normalizeAttachment(raw) {
    if (!raw || typeof raw !== "object") return null
    var url = safeClickUrl(raw.url)
    if (!url) return null
    return {
        name: String(raw.name || ""),
        url: url,
        type: String(raw.type || ""),
        size: parseInt(raw.size, 10) || 0,
        expires: parseInt(raw.expires, 10) || 0
    }
}

function normalizeActions(raw) {
    var list = []
    var rows = raw instanceof Array ? raw : []
    for (var i = 0; i < rows.length; i++) {
        var action = normalizeAction(rows[i])
        if (action) list.push(action)
    }
    return list
}

function normalizeAction(raw) {
    if (!raw || typeof raw !== "object") return null
    var kind = String(raw.action || "").toLowerCase()
    if (kind !== "view" && kind !== "http" && kind !== "copy" && kind !== "broadcast") return null
    var label = String(raw.label || "").trim()
    if (!label) return null
    var url = String(raw.url || "")
    var value = String(raw.value !== undefined && raw.value !== null ? raw.value : url)
    if (kind === "view" && !safeClickUrl(url)) return null
    if (kind === "http" && !safeClickUrl(url)) return null
    if (kind === "copy" && !value) return null
    var method = String(raw.method || "POST").toUpperCase()
    if (!method) method = "POST"
    var headers = {}
    if (raw.headers && typeof raw.headers === "object") {
        for (var key in raw.headers) {
            headers[String(key)] = String(raw.headers[key])
        }
    }
    return {
        id: String(raw.id || ""),
        action: kind,
        label: label,
        url: url,
        value: value,
        clear: raw.clear === true,
        method: method,
        body: raw.body !== undefined && raw.body !== null ? String(raw.body) : "",
        headers: headers,
        intent: String(raw.intent || "")
    }
}

function isImageAttachment(att) {
    if (!att || !att.url) return false
    var type = String(att.type || "").toLowerCase()
    if (type.indexOf("image/") === 0) return true
    if (IMAGE_NAME_RE.test(String(att.name || ""))) return true
    return IMAGE_NAME_RE.test(String(att.url || ""))
}

function emojiForTag(tag) {
    return Emojis.lookup(tag)
}

function emojiPrefix(tags) {
    var list = tags instanceof Array ? tags : []
    var parts = []
    for (var i = 0; i < list.length; i++) {
        var emoji = emojiForTag(list[i])
        if (emoji) parts.push(emoji)
    }
    return parts.join("")
}

function textTags(tags) {
    var list = tags instanceof Array ? tags : []
    var parts = []
    for (var i = 0; i < list.length; i++) {
        if (!emojiForTag(list[i])) parts.push(String(list[i]))
    }
    return parts
}

function displayTitle(msg) {
    var prefix = emojiPrefix(msg && msg.tags)
    var title = msg && msg.title ? String(msg.title) : ""
    if (prefix && title) return prefix + " " + title
    return title
}

function displayMessage(msg) {
    var body = msg && msg.message ? String(msg.message) : ""
    var title = msg && msg.title ? String(msg.title) : ""
    if (title) return body
    var prefix = emojiPrefix(msg && msg.tags)
    if (prefix && body) return prefix + " " + body
    if (prefix) return prefix
    return body
}

function attachmentExpired(att) {
    if (!att || !att.expires) return false
    return att.expires < nowSec()
}

function syntheticCopyAction(label, value) {
    return {
        id: "",
        action: "copy",
        label: label,
        url: "",
        value: value,
        clear: false,
        method: "GET",
        body: "",
        headers: {},
        intent: ""
    }
}

function syntheticViewAction(label, url) {
    return {
        id: "",
        action: "view",
        label: label,
        url: url,
        value: url,
        clear: false,
        method: "GET",
        body: "",
        headers: {},
        intent: ""
    }
}

function cardActions(msg) {
    var actions = []
    var att = msg && msg.attachment
    if (att && att.url && !attachmentExpired(att)) {
        actions.push(syntheticCopyAction("Copy URL", att.url))
        actions.push(syntheticViewAction("Open attachment", att.url))
    }
    var click = safeClickUrl(msg && msg.click)
    if (click) {
        actions.push(syntheticCopyAction("Copy link", click))
        actions.push(syntheticViewAction("Open link", click))
    }
    var rows = msg && msg.actions instanceof Array ? msg.actions : []
    for (var i = 0; i < rows.length; i++) {
        if (rows[i]) actions.push(rows[i])
    }
    return actions
}

function inlineActions(actions) {
    var list = actions instanceof Array ? actions : []
    if (list.length <= INLINE_ACTION_LIMIT) return list
    return list.slice(0, INLINE_ACTION_LIMIT)
}

function overflowActions(actions) {
    var list = actions instanceof Array ? actions : []
    if (list.length <= INLINE_ACTION_LIMIT) return []
    return list.slice(INLINE_ACTION_LIMIT)
}

function actionEnabled(action) {
    if (!action) return false
    return action.action !== "broadcast"
}

function copyValue(action) {
    if (!action) return ""
    return String(action.value || action.url || "")
}

function httpActionCommand(action) {
    var url = safeClickUrl(action && action.url)
    if (!url) return []
    var method = String(action.method || "POST").toUpperCase()
    if (!method) method = "POST"
    var cmd = ["curl", "-sS", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "20", "-X", method]
    var headers = action && action.headers && typeof action.headers === "object" ? action.headers : {}
    for (var key in headers) {
        cmd.push("-H", String(key) + ": " + String(headers[key]))
    }
    if (action && action.body) cmd.push("--data-binary", String(action.body))
    cmd.push(url)
    return cmd
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
    var prefix = emojiPrefix(tags)
    var rest = textTags(tags)
    var bits = []
    if (prefix) bits.push(prefix)
    if (rest.length) bits.push(rest.join("  "))
    return bits.join("  ")
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
