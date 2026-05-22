// Hand-written multisig UI — Phase 2. Regenerate backend with 'make generate-module'.
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Theme 1.0
import Logos.Controls 1.0

Item {
    id: root

    // ── Navigation ────────────────────────────────────────────────────────────
    // 0 = dashboard, 1 = detail, 2 = settings
    property int page: 0

    // ── Multisig state ────────────────────────────────────────────────────────
    property var knownMultisigs: []      // [{createKey, label}]
    property string activeCreateKey: ""
    property var proposals: []           // accumulated for activeCreateKey
    property int _fetchTarget: 0
    property int _fetchNext: 0
    property string _multisigIdl: ""    // lazily loaded from codec.getMultisigIdl()
    property string _storageUrl: ""     // Logos Storage URL (Codex) — for IDL fetching via spelbook

    // ── Helpers ───────────────────────────────────────────────────────────────
    function u8ArrayToHex(arr) {
        if (!arr || !arr.length) return ""
        var s = ""
        for (var i = 0; i < arr.length; i++) {
            var b = arr[i] & 0xff
            s += (b < 16 ? "0" : "") + b.toString(16)
        }
        return s
    }

    function u32ArrayToHex(arr) {
        if (!arr || !arr.length) return ""
        var s = ""
        for (var i = 0; i < arr.length; i++) {
            var v = arr[i] >>> 0
            var hex = v.toString(16)
            while (hex.length < 8) hex = "0" + hex
            s += hex
        }
        return s
    }

    function shortHex(hex) {
        if (!hex || hex.length <= 16) return hex || ""
        return hex.slice(0, 8) + "…" + hex.slice(-8)
    }

    function proposalStatus(p) {
        var s = p["status"]
        if (!s) return "Unknown"
        if (typeof s === "string") return s
        if (typeof s === "object") return Object.keys(s)[0] || "Unknown"
        return String(s)
    }

    function statusColor(status) {
        if (status === "Executed") return Theme.palette.success
        if (status === "Rejected") return Theme.palette.error
        return Theme.palette.primary
    }

    function approvalCount(p) { return p["approved"] ? p["approved"].length : 0 }
    function rejectCount(p)   { return p["rejected"] ? p["rejected"].length : 0 }

    function threshold() {
        var s = backend.multisigState
        return s ? (s["threshold"] || 0) : 0
    }

    function memberCount() {
        var s = backend.multisigState
        return s ? (s["member_count"] || 0) : 0
    }

    function membersHex() {
        var s = backend.multisigState
        if (!s || !s["members"]) return []
        return s["members"].map(function(m) { return u8ArrayToHex(m) })
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    function loadKnownMultisigs() {
        var raw = backend.fieldHistory("multisig_create_keys")
        var labelsRaw = backend.fieldHistory("multisig_labels")
        var labels = {}
        try { if (labelsRaw) labels = JSON.parse(labelsRaw) } catch(e) {}
        var keys = raw ? raw.split(",").filter(function(k) { return k.length > 0 }) : []
        knownMultisigs = keys.map(function(k) { return { createKey: k, label: labels[k] || "" } })
    }

    function saveMultisig(createKey, label) {
        var existing = knownMultisigs.map(function(m) { return m.createKey })
        if (existing.indexOf(createKey) < 0) {
            backend.saveHistory("multisig_create_keys", existing.concat([createKey]).join(","))
        }
        if (label) {
            var labelsRaw = backend.fieldHistory("multisig_labels")
            var labels = {}
            try { if (labelsRaw) labels = JSON.parse(labelsRaw) } catch(e) {}
            labels[createKey] = label
            backend.saveHistory("multisig_labels", JSON.stringify(labels))
        }
        loadKnownMultisigs()
    }

    function removeMultisig(createKey) {
        var keys = knownMultisigs.map(function(m) { return m.createKey })
                                 .filter(function(k) { return k !== createKey })
        backend.saveHistory("multisig_create_keys", keys.join(","))
        var labelsRaw = backend.fieldHistory("multisig_labels")
        var labels = {}
        try { if (labelsRaw) labels = JSON.parse(labelsRaw) } catch(e) {}
        delete labels[createKey]
        backend.saveHistory("multisig_labels", JSON.stringify(labels))
        loadKnownMultisigs()
    }

    // ── Sequential proposal fetch ─────────────────────────────────────────────
    function openMultisig(createKey) {
        activeCreateKey = createKey
        proposals = []
        _fetchNext = 0
        _fetchTarget = 0
        page = 1
        backend.fetchMultisigState(createKey)
    }

    function fetchNextProposal() {
        if (_fetchNext < _fetchTarget)
            backend.fetchProposal(activeCreateKey, _fetchNext)
    }

    // ── Init ──────────────────────────────────────────────────────────────────
    Component.onCompleted: {
        loadKnownMultisigs()
        backend.listAccounts()
        _multisigIdl = codec.getMultisigIdl()
        var rawStorageUrl = backend.fieldHistory("storage_url")
        if (rawStorageUrl) _storageUrl = rawStorageUrl
    }

    // ── Backend connections ───────────────────────────────────────────────────
    Connections {
        target: backend

        function onMultisigStateChanged() {
            var s = backend.multisigState
            if (!s || Object.keys(s).length === 0) return
            _fetchTarget = parseInt(s["transaction_index"]) || 0
            _fetchNext = 0
            proposals = []
            fetchNextProposal()
        }

        function onProposalChanged() {
            var p = backend.proposal
            if (!p || Object.keys(p).length === 0) return
            var idx = parseInt(p["index"]) || _fetchNext
            var arr = proposals.slice()
            arr[idx] = p
            proposals = arr
            _fetchNext = idx + 1
            fetchNextProposal()
        }

        function onOperationSuccess(operation, txHash) {
            toast.show("✓ " + operation + (txHash ? " · " + txHash.slice(0, 12) + "…" : ""), Theme.palette.success)
            if (activeCreateKey) backend.fetchMultisigState(activeCreateKey)
        }

        function onOperationError(operation, error) {
            toast.show("✗ " + operation + ": " + error, Theme.palette.error)
        }

        function onWalletAccountsChanged() {}
    }

    // ── Root background ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Theme.palette.background

        // ── Top bar ───────────────────────────────────────────────────────────
        Rectangle {
            id: topBar
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 52
            color: Theme.palette.backgroundElevated
            border.color: Theme.palette.border
            border.width: 0

            RowLayout {
                anchors { fill: parent; leftMargin: 16; rightMargin: 12 }
                spacing: 8

                // Back button (detail view only)
                Item {
                    width: 32; height: 32
                    visible: root.page === 1
                    Rectangle {
                        anchors.fill: parent; radius: Theme.spacing.radiusSmall
                        color: backArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: "←"; color: Theme.palette.text; font.pixelSize: 18
                    }
                    MouseArea {
                        id: backArea
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { root.page = 0; activeCreateKey = "" }
                    }
                }

                Text {
                    text: root.page === 0 ? "Multisig" :
                          root.page === 1 ? (function() {
                              var entry = knownMultisigs.filter(function(m){ return m.createKey === activeCreateKey })[0]
                              return entry && entry.label ? entry.label : shortHex(activeCreateKey)
                          })() :
                          "Settings"
                    color: Theme.palette.text
                    font.pixelSize: 15; font.bold: true
                    font.family: Theme.typography.publicSans
                    Layout.fillWidth: true
                }

                // Busy indicator
                Row {
                    visible: backend.busy; spacing: 4
                    Repeater {
                        model: 3
                        Rectangle {
                            width: 5; height: 5; radius: 2.5
                            color: Theme.palette.primary
                            SequentialAnimation on opacity {
                                running: backend.busy; loops: Animation.Infinite
                                PauseAnimation  { duration: index * 180 }
                                NumberAnimation { to: 1.0; duration: 180 }
                                NumberAnimation { to: 0.2; duration: 180 }
                                PauseAnimation  { duration: (2 - index) * 180 }
                            }
                        }
                    }
                }

                // Nav tab buttons
                Repeater {
                    model: [{ label: "Dashboard", pg: 0 }, { label: "Settings", pg: 2 }]
                    Rectangle {
                        width: navLabel.implicitWidth + 20; height: 30
                        radius: Theme.spacing.radiusLarge
                        color: root.page === modelData.pg
                            ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.18)
                            : "transparent"
                        border.color: root.page === modelData.pg ? Theme.palette.primary : "transparent"
                        Text {
                            id: navLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.page === modelData.pg ? Theme.palette.primary : Theme.palette.textMuted
                            font.pixelSize: 13
                            font.family: Theme.typography.publicSans
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = modelData.pg
                        }
                    }
                }
            }
        }

        // ── Pages ─────────────────────────────────────────────────────────────
        StackLayout {
            anchors { left: parent.left; right: parent.right; top: topBar.bottom; bottom: parent.bottom }
            currentIndex: root.page

            // ── Page 0: Dashboard ─────────────────────────────────────────────
            Item {
                ScrollView {
                    anchors.fill: parent; clip: true; contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.parent.width; spacing: 12

                        Item { height: 20; Layout.fillWidth: true }

                        RowLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24

                            Text {
                                text: "Your Multisigs"
                                color: Theme.palette.text
                                font.pixelSize: 20; font.bold: true
                                font.family: Theme.typography.publicSans
                                Layout.fillWidth: true
                            }

                            // Watch button
                            Rectangle {
                                width: watchBtnText.implicitWidth + 20; height: 32
                                radius: Theme.spacing.radiusLarge
                                color: watchBtnArea.containsMouse
                                    ? Theme.palette.backgroundMuted : "transparent"
                                border.color: Theme.palette.border
                                Text {
                                    id: watchBtnText; anchors.centerIn: parent
                                    text: "Watch"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: watchBtnArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: watchDialog.open()
                                }
                            }

                            // Create button
                            Rectangle {
                                width: createBtnText.implicitWidth + 20; height: 32
                                radius: Theme.spacing.radiusLarge
                                color: createBtnArea.containsMouse
                                    ? Theme.palette.primaryHover : Theme.palette.primary
                                Text {
                                    id: createBtnText; anchors.centerIn: parent
                                    text: "+ Create"
                                    color: Theme.palette.text
                                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: createBtnArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: createDialog.open()
                                }
                            }
                        }

                        // Empty state
                        Item {
                            visible: knownMultisigs.length === 0
                            Layout.fillWidth: true; height: 120
                            Column {
                                anchors.centerIn: parent; spacing: 8
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "No multisigs yet"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 15; font.family: Theme.typography.publicSans
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Create a new one or watch an existing create key"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 12; font.family: Theme.typography.publicSans
                                }
                            }
                        }

                        // Multisig cards
                        Repeater {
                            model: knownMultisigs
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.leftMargin: 24; Layout.rightMargin: 24
                                height: 72; radius: Theme.spacing.radiusLarge
                                color: cardArea.containsMouse
                                    ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.08)
                                    : Theme.palette.backgroundSecondary
                                border.color: cardArea.containsMouse
                                    ? Theme.palette.primary : Theme.palette.border

                                RowLayout {
                                    anchors { fill: parent; margins: 16 }
                                    Column {
                                        Layout.fillWidth: true; spacing: 4
                                        Text {
                                            text: modelData.label || shortHex(modelData.createKey)
                                            color: Theme.palette.text
                                            font.pixelSize: 14; font.bold: !!modelData.label
                                            font.family: Theme.typography.publicSans
                                        }
                                        Text {
                                            visible: !!modelData.label
                                            text: shortHex(modelData.createKey)
                                            color: Theme.palette.textMuted
                                            font.pixelSize: 11; font.family: Theme.typography.publicSans
                                        }
                                    }
                                    Text { text: "→"; color: Theme.palette.primary; font.pixelSize: 18 }
                                }

                                MouseArea {
                                    id: cardArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: openMultisig(modelData.createKey)
                                }

                                // Remove button
                                Rectangle {
                                    anchors { right: parent.right; top: parent.top; margins: 6 }
                                    width: 22; height: 22; radius: 11
                                    color: removeArea.containsMouse
                                        ? Qt.rgba(Theme.palette.error.r, Theme.palette.error.g, Theme.palette.error.b, 0.25)
                                        : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"; color: Theme.palette.textMuted; font.pixelSize: 13
                                    }
                                    MouseArea {
                                        id: removeArea; anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: removeMultisig(modelData.createKey)
                                    }
                                }
                            }
                        }

                        Item { height: 40; Layout.fillWidth: true }
                    }
                }
            }

            // ── Page 1: Detail ────────────────────────────────────────────────
            Item {
                ColumnLayout {
                    anchors.fill: parent; spacing: 0

                    // Multisig header card
                    Rectangle {
                        Layout.fillWidth: true
                        height: headerCol.implicitHeight + 24
                        color: Theme.palette.backgroundSecondary
                        border.color: Theme.palette.border

                        ColumnLayout {
                            id: headerCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: threshold() + " of " + memberCount() + " threshold"
                                    color: Theme.palette.text
                                    font.pixelSize: 15; font.bold: true
                                    font.family: Theme.typography.publicSans
                                    Layout.fillWidth: true
                                    visible: Object.keys(backend.multisigState).length > 0
                                }
                                Text {
                                    visible: Object.keys(backend.multisigState).length === 0
                                    text: "Loading…"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 14; font.family: Theme.typography.publicSans
                                    Layout.fillWidth: true
                                }
                                Rectangle {
                                    width: 28; height: 28; radius: Theme.spacing.radiusSmall
                                    color: refArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                    Text { anchors.centerIn: parent; text: "↺"; color: Theme.palette.textMuted; font.pixelSize: 16 }
                                    MouseArea {
                                        id: refArea; anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: openMultisig(activeCreateKey)
                                    }
                                }
                            }

                            // Members chips
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: membersHex()
                                    Rectangle {
                                        height: 22; width: memberChip.implicitWidth + 16; radius: 11
                                        color: Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.12)
                                        border.color: Theme.palette.primary
                                        Text {
                                            id: memberChip; anchors.centerIn: parent
                                            text: shortHex(modelData)
                                            color: Theme.palette.primary
                                            font.pixelSize: 11; font.family: Theme.typography.publicSans
                                        }
                                    }
                                }
                            }

                            // Actions row
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: proposals.filter(function(p){ return p && proposalStatus(p) === "Pending" }).length + " pending  ·  " +
                                          (parseInt(backend.multisigState["transaction_index"]) || 0) + " total"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.family: Theme.typography.publicSans
                                    Layout.fillWidth: true
                                }
                                Rectangle {
                                    width: newPropText.implicitWidth + 16; height: 26; radius: Theme.spacing.radiusLarge
                                    color: newPropArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                                    Text {
                                        id: newPropText; anchors.centerIn: parent
                                        text: "New Proposal"; color: Theme.palette.text
                                        font.pixelSize: 12; font.family: Theme.typography.publicSans
                                    }
                                    MouseArea {
                                        id: newPropArea; anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: proposeDialog.open()
                                    }
                                }
                                Repeater {
                                    model: ["Add Member", "Remove Member", "Change Threshold"]
                                    Rectangle {
                                        width: govText.implicitWidth + 16; height: 26; radius: Theme.spacing.radiusLarge
                                        color: govArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                        border.color: Theme.palette.border
                                        Text {
                                            id: govText; anchors.centerIn: parent
                                            text: modelData; color: Theme.palette.textMuted
                                            font.pixelSize: 12; font.family: Theme.typography.publicSans
                                        }
                                        MouseArea {
                                            id: govArea; anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: {
                                                if (modelData === "Add Member")       addMemberDialog.open()
                                                else if (modelData === "Remove Member")   removeMemberDialog.open()
                                                else if (modelData === "Change Threshold") changeThresholdDialog.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Proposals list
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth

                        ColumnLayout {
                            width: parent.parent.width; spacing: 10

                            Item { height: 12; Layout.fillWidth: true }

                            Text {
                                visible: proposals.length === 0 && !backend.busy
                                text: "No proposals yet."
                                color: Theme.palette.textMuted
                                font.pixelSize: 13; font.family: Theme.typography.publicSans
                                Layout.leftMargin: 24
                            }

                            Repeater {
                                model: proposals
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 16; Layout.rightMargin: 16
                                    radius: Theme.spacing.radiusLarge
                                    color: Theme.palette.backgroundSecondary
                                    border.color: Theme.palette.border
                                    height: proposalCardCol.implicitHeight + 20
                                    visible: !!modelData

                                    property var pdata: modelData || {}
                                    property string pStatus: proposalStatus(pdata)
                                    property int pApproved: approvalCount(pdata)
                                    property int pRejected: rejectCount(pdata)
                                    property int pThreshold: threshold()
                                    property bool pExecutable: pStatus === "Pending" && pApproved >= pThreshold
                                    property var _decoded: null
                                    property string _decodeError: ""

                                    function tryDecode() {
                                        var instrData = pdata["target_instruction_data"]
                                        if (!instrData) { _decodeError = "no instruction data"; return }
                                        var words = Array.isArray(instrData) ? instrData : [instrData]
                                        var wordsJson = JSON.stringify(words.map(function(w){ return (parseInt(w) >>> 0) }))

                                        // Try multisig IDL first
                                        var idl = _multisigIdl
                                        var resultStr = codec.decodeInstruction(idl, wordsJson)
                                        var result = JSON.parse(resultStr)
                                        if (result.success) { _decoded = result.result; _decodeError = ""; return }

                                        // Fallback: look up target program in spelbook cache
                                        if (!spelbook.isAvailable()) {
                                            _decoded = null; _decodeError = result.error || "decode failed"
                                            return
                                        }
                                        var targetHex = u32ArrayToHex(pdata["target_program_id"] || [])
                                        if (!targetHex) { _decoded = null; _decodeError = result.error || "decode failed"; return }

                                        var searchStr = spelbook.searchPrograms("")
                                        var searchRes = JSON.parse(searchStr)
                                        if (!searchRes.success) {
                                            _decoded = null; _decodeError = result.error || "decode failed"; return
                                        }
                                        var entry = null
                                        for (var i = 0; i < searchRes.programs.length; i++) {
                                            if ((searchRes.programs[i]["program_id"] || "").toLowerCase() === targetHex.toLowerCase()) {
                                                entry = searchRes.programs[i]; break
                                            }
                                        }
                                        if (!entry || !entry["idl_cid"]) {
                                            _decoded = null
                                            _decodeError = (result.error || "decode failed") + " · program not in spelbook cache"
                                            return
                                        }
                                        if (!_storageUrl) {
                                            _decoded = null
                                            _decodeError = "program in spelbook (idl_cid: " + entry["idl_cid"].slice(0, 12) + "…) — set Storage URL in Settings to fetch IDL"
                                            return
                                        }
                                        var idlFetchStr = spelbook.fetchIdl(_storageUrl, entry["idl_cid"])
                                        var idlFetch = JSON.parse(idlFetchStr)
                                        if (!idlFetch.success) {
                                            _decoded = null; _decodeError = "IDL fetch failed: " + (idlFetch.error || "unknown"); return
                                        }
                                        var externalIdl = JSON.stringify(idlFetch.idl)
                                        var resultStr2 = codec.decodeInstruction(externalIdl, wordsJson)
                                        var result2 = JSON.parse(resultStr2)
                                        if (result2.success) { _decoded = result2.result; _decodeError = "" }
                                        else { _decoded = null; _decodeError = result2.error || "decode failed (spelbook IDL)" }
                                    }

                                    ColumnLayout {
                                        id: proposalCardCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                                        spacing: 8

                                        // Header row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Proposal #" + (pdata["index"] !== undefined ? pdata["index"] : index)
                                                color: Theme.palette.text
                                                font.pixelSize: 13; font.bold: true
                                                font.family: Theme.typography.publicSans
                                                Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                width: statusChip.implicitWidth + 12; height: 20; radius: 10
                                                color: Qt.rgba(0,0,0,0.3)
                                                border.color: statusColor(pStatus)
                                                Text {
                                                    id: statusChip; anchors.centerIn: parent
                                                    text: pStatus
                                                    color: statusColor(pStatus)
                                                    font.pixelSize: 11; font.family: Theme.typography.publicSans
                                                }
                                            }
                                        }

                                        // Config action or target program
                                        Text {
                                            property var ca: pdata["config_action"]
                                            text: ca ? JSON.stringify(ca)
                                                 : (pdata["target_program_id"]
                                                     ? "Target: " + shortHex(u32ArrayToHex(pdata["target_program_id"]))
                                                     : "")
                                            visible: text !== ""
                                            color: Theme.palette.textMuted
                                            font.pixelSize: 11; font.family: "monospace"
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }

                                        // Decoded instruction (shown after clicking Decode)
                                        Rectangle {
                                            visible: _decoded !== null || _decodeError !== ""
                                            Layout.fillWidth: true
                                            height: decodedCol.implicitHeight + 10
                                            radius: Theme.spacing.radiusSmall
                                            color: _decodeError !== ""
                                                ? Qt.rgba(Theme.palette.error.r, Theme.palette.error.g, Theme.palette.error.b, 0.08)
                                                : Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.06)
                                            border.color: _decodeError !== "" ? Theme.palette.error : Theme.palette.border

                                            ColumnLayout {
                                                id: decodedCol
                                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                                spacing: 4

                                                Text {
                                                    visible: _decodeError !== ""
                                                    text: "Decode error: " + _decodeError
                                                    color: Theme.palette.error
                                                    font.pixelSize: 10; font.family: "monospace"
                                                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                                                }
                                                Text {
                                                    visible: _decoded !== null
                                                    text: _decoded ? ("ix: " + _decoded["instruction"]) : ""
                                                    color: Theme.palette.primary
                                                    font.pixelSize: 11; font.bold: true
                                                    font.family: Theme.typography.publicSans
                                                }
                                                Text {
                                                    visible: _decoded !== null && _decoded["args"] !== undefined
                                                    text: _decoded ? JSON.stringify(_decoded["args"], null, 2) : ""
                                                    color: Theme.palette.text
                                                    font.pixelSize: 10; font.family: "monospace"
                                                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }

                                        // Decode button (only for proposals with instruction data)
                                        Rectangle {
                                            visible: !!pdata["target_instruction_data"]
                                            width: decodeText.implicitWidth + 14; height: 22
                                            radius: Theme.spacing.radiusSmall
                                            color: decodeArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                            border.color: Theme.palette.border
                                            Text {
                                                id: decodeText; anchors.centerIn: parent
                                                text: _decoded ? "Re-decode" : "Decode"
                                                color: Theme.palette.textMuted
                                                font.pixelSize: 10; font.family: Theme.typography.publicSans
                                            }
                                            MouseArea {
                                                id: decodeArea; anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                onClicked: tryDecode()
                                            }
                                        }

                                        // Approval progress bar
                                        Item {
                                            Layout.fillWidth: true; height: 6
                                            Rectangle {
                                                anchors.fill: parent; radius: 3
                                                color: Theme.palette.backgroundInset
                                            }
                                            Rectangle {
                                                width: pThreshold > 0
                                                    ? Math.min(1, pApproved / pThreshold) * parent.width : 0
                                                height: parent.height; radius: 3
                                                color: pExecutable ? Theme.palette.success : Theme.palette.primary
                                            }
                                        }

                                        // Approval count
                                        Text {
                                            text: pApproved + " / " + pThreshold + " approvals" +
                                                  (pRejected > 0 ? "  ·  " + pRejected + " rejected" : "")
                                            color: Theme.palette.textMuted
                                            font.pixelSize: 11; font.family: Theme.typography.publicSans
                                        }

                                        // Action buttons (Pending proposals only)
                                        RowLayout {
                                            visible: pStatus === "Pending"
                                            spacing: 8

                                            Repeater {
                                                model: pExecutable
                                                    ? [{ label: "Approve", col: Theme.palette.success },
                                                       { label: "Reject",  col: Theme.palette.error   },
                                                       { label: "Execute", col: Theme.palette.primary  }]
                                                    : [{ label: "Approve", col: Theme.palette.success  },
                                                       { label: "Reject",  col: Theme.palette.error    }]
                                                Rectangle {
                                                    width: actionText.implicitWidth + 16; height: 26
                                                    radius: Theme.spacing.radiusSmall
                                                    color: actionArea.containsMouse
                                                        ? Qt.rgba(modelData.col.r, modelData.col.g, modelData.col.b, 0.25)
                                                        : Qt.rgba(modelData.col.r, modelData.col.g, modelData.col.b, 0.10)
                                                    border.color: modelData.col
                                                    Text {
                                                        id: actionText; anchors.centerIn: parent
                                                        text: modelData.label
                                                        color: modelData.col
                                                        font.pixelSize: 12; font.family: Theme.typography.publicSans
                                                    }
                                                    MouseArea {
                                                        id: actionArea; anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                        property string propAction: modelData.label
                                                        property int propIdx: parseInt(pdata["index"]) || index
                                                        onClicked: {
                                                            accountPicker.action = propAction
                                                            accountPicker.proposalIndex = propIdx
                                                            accountPicker.open()
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { height: 40; Layout.fillWidth: true }
                        }
                    }
                }
            }

            // ── Page 2: Settings ──────────────────────────────────────────────
            Item {
                Rectangle { anchors.fill: parent; color: Theme.palette.backgroundSecondary }
                ScrollView {
                    anchors.fill: parent; clip: true; contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.parent.width; spacing: 12

                        Item { height: 20; Layout.fillWidth: true }

                        Text {
                            text: "Settings"
                            color: Theme.palette.text
                            font.pixelSize: 20; font.bold: true
                            font.family: Theme.typography.publicSans
                            Layout.leftMargin: 24
                        }

                        // Settings fields (using plain TextField + Theme styling for onEditingFinished support)
                        Repeater {
                            model: [
                                { label: "Wallet Path",      getter: function(){ return backend.walletPath },    setter: function(v){ backend.setWalletPath(v) } },
                                { label: "Sequencer URL",    getter: function(){ return backend.sequencerUrl },  setter: function(v){ backend.setSequencerUrl(v) } },
                                { label: "Program ID (hex)", getter: function(){ return backend.programIdHex }, setter: function(v){ backend.setProgramIdHex(v) } },
                                { label: "Storage URL (Codex)", getter: function(){ return root._storageUrl },
                                  setter: function(v){ root._storageUrl = v; backend.saveHistory("storage_url", v) } }
                            ]
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 4
                                Text {
                                    text: modelData.label
                                    color: Theme.palette.textMuted
                                    font.pixelSize: Theme.typography.secondaryText
                                    font.family: Theme.typography.publicSans
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    text: modelData.getter()
                                    onEditingFinished: modelData.setter(text)
                                    color: Theme.palette.text
                                    placeholderTextColor: Theme.palette.textPlaceholder
                                    background: Rectangle {
                                        color: Theme.palette.background
                                        border.color: Theme.palette.border
                                        radius: Theme.spacing.radiusSmall
                                    }
                                }
                            }
                        }

                        // Connection test
                        RowLayout {
                            Layout.leftMargin: 24; Layout.rightMargin: 24

                            Rectangle {
                                width: connText.implicitWidth + 20; height: 32; radius: Theme.spacing.radiusLarge
                                color: connArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                                Text {
                                    id: connText; anchors.centerIn: parent
                                    text: "Test Connection"
                                    color: Theme.palette.text
                                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: connArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: backend.checkConnection()
                                }
                            }
                            Text {
                                text: backend.connectionStatus || ""
                                color: backend.connectionStatus.startsWith("✓") ? Theme.palette.success
                                     : backend.connectionStatus.startsWith("✗") ? Theme.palette.error
                                     : Theme.palette.textMuted
                                font.pixelSize: 12; font.family: Theme.typography.publicSans
                                Layout.fillWidth: true; wrapMode: Text.WordWrap
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                            height: 1; color: Theme.palette.border
                        }

                        // Accounts
                        RowLayout {
                            Layout.leftMargin: 24; Layout.rightMargin: 24
                            Text {
                                text: "Wallet Accounts"
                                color: Theme.palette.text
                                font.pixelSize: 14; font.bold: true
                                font.family: Theme.typography.publicSans
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                width: refAccText.implicitWidth + 16; height: 28; radius: Theme.spacing.radiusLarge
                                color: refAccArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                border.color: Theme.palette.border
                                Text {
                                    id: refAccText; anchors.centerIn: parent
                                    text: "↺ Refresh"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 12; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: refAccArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: backend.listAccounts()
                                }
                            }
                        }

                        Repeater {
                            model: backend.walletAccounts
                            delegate: RowLayout {
                                Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 8
                                Rectangle {
                                    property string st: modelData["status"] || "unknown"
                                    width: 48; height: 20; radius: 10
                                    color: st === "owned"
                                        ? Qt.rgba(Theme.palette.success.r, Theme.palette.success.g, Theme.palette.success.b, 0.15)
                                        : Qt.rgba(0.4,0.4,0.4,0.15)
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.st === "owned" ? "owned"
                                            : parent.st === "uninitialized" ? "free" : "other"
                                        color: parent.st === "owned" ? Theme.palette.success : Theme.palette.textMuted
                                        font.pixelSize: 10; font.family: Theme.typography.publicSans
                                    }
                                }
                                Text {
                                    text: modelData["label"] || ""
                                    visible: !!modelData["label"]
                                    color: Theme.palette.primary
                                    font.pixelSize: 11; font.family: Theme.typography.publicSans
                                    Layout.preferredWidth: 70; elide: Text.ElideRight
                                }
                                Text {
                                    text: shortHex(modelData["id"] || "")
                                    color: Theme.palette.text
                                    font.pixelSize: 12; font.family: "monospace"
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        Item { height: 40; Layout.fillWidth: true }
                    }
                }
            }
        }

        // ── Toast ─────────────────────────────────────────────────────────────
        Rectangle {
            id: toast
            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 24 }
            width: Math.min(toastText.implicitWidth + 48, parent.width - 80); height: 44
            radius: Theme.spacing.radiusXlarge
            color: Theme.palette.backgroundSecondary
            opacity: 0; visible: opacity > 0

            function show(msg, col) {
                toastText.text = msg; toast.color = col || Theme.palette.backgroundSecondary
                opacity = 1; toastTimer.restart()
            }

            Text {
                id: toastText; anchors { fill: parent; margins: 12 }
                color: Theme.palette.text
                font.pixelSize: 13; font.family: Theme.typography.publicSans
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
            }
            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { toastTimer.stop(); toast.opacity = 0 }
            }
            Behavior on opacity { NumberAnimation { duration: 300 } }
            Timer { id: toastTimer; interval: 4000; onTriggered: toast.opacity = 0 }
        }
    }

    // ── Clip helper ───────────────────────────────────────────────────────────
    TextEdit {
        id: clipHelper; width: 0; height: 0; opacity: 0
        function copyText(t) { clipHelper.text = t; selectAll(); copy() }
    }

    // ── Watch dialog ──────────────────────────────────────────────────────────
    Dialog {
        id: watchDialog
        title: "Watch Multisig"
        modal: true; anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: watchDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 12

            Text { text: "Create key (unique seed)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: watchKey; Layout.fillWidth: true
                placeholderText: "e.g. my-multisig-2024"
            }
            Text { text: "Label (optional)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: watchLabel; Layout.fillWidth: true
                placeholderText: "e.g. Team Treasury"
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Cancel"
                onClicked: watchDialog.close()
            }
            Rectangle {
                width: watchOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: watchOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: watchKey.text.length > 0 ? 1.0 : 0.5
                Text {
                    id: watchOkText; anchors.centerIn: parent
                    text: "Watch"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: watchOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (watchKey.text.length > 0) {
                            saveMultisig(watchKey.text.trim(), watchLabel.text.trim())
                            watchDialog.close()
                            watchKey.text = ""; watchLabel.text = ""
                        }
                    }
                }
            }
        }
    }

    // ── Create multisig dialog ────────────────────────────────────────────────
    Dialog {
        id: createDialog
        title: "Create Multisig"
        modal: true; anchors.centerIn: parent
        width: Math.min(480, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: createDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 10

            Text { text: "Create key (unique seed)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: cCreateKey; Layout.fillWidth: true; placeholderText: "e.g. my-multisig" }

            Text { text: "Label (optional)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: cLabel; Layout.fillWidth: true; placeholderText: "e.g. Team Treasury" }

            Text { text: "Threshold (M)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: cThreshold; Layout.fillWidth: true; placeholderText: "2" }

            Text { text: "Member account IDs (one per line)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            TextArea {
                id: cMembers; Layout.fillWidth: true; implicitHeight: 80
                placeholderText: "account_id_hex\naccount_id_hex\n…"
                color: Theme.palette.text
                placeholderTextColor: Theme.palette.textPlaceholder
                wrapMode: TextArea.Wrap
                background: Rectangle {
                    color: Theme.palette.backgroundSecondary
                    border.color: Theme.palette.border
                    radius: Theme.spacing.radiusSmall
                }
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Cancel"
                onClicked: createDialog.close()
            }
            Rectangle {
                width: createOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: createOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: backend.busy ? 0.5 : 1.0
                Text {
                    id: createOkText; anchors.centerIn: parent
                    text: "Create"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: createOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (!backend.busy && cCreateKey.text.length > 0) {
                            var members = cMembers.text.split("\n")
                                .map(function(s){ return s.trim() })
                                .filter(function(s){ return s.length > 0 })
                            backend.createMultisig(cCreateKey.text.trim(), parseInt(cThreshold.text) || 2, members)
                            saveMultisig(cCreateKey.text.trim(), cLabel.text.trim())
                            createDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Propose dialog ────────────────────────────────────────────────────────
    Dialog {
        id: proposeDialog
        title: "New Proposal"
        modal: true; anchors.centerIn: parent
        width: Math.min(540, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        // 0 = raw words mode, 1 = encode-from-IDL mode
        property int proposeMode: 0
        property string _encodeError: ""
        property string _encodePreview: ""  // "N words: [0, 1000, …]"
        property var _spelResults: []
        property string _spelQuery: ""

        function _runEncode() {
            _encodeError = ""
            _encodePreview = ""
            var idlStr = pIdlJson.text.trim()
            var ixName = pIxName.text.trim()
            var argsStr = pArgsJson.text.trim()
            if (!idlStr || !ixName || !argsStr) {
                _encodeError = "Fill in IDL, instruction name, and args JSON"
                return false
            }
            var resultStr = codec.encodeInstruction(idlStr, ixName, argsStr)
            var result = JSON.parse(resultStr)
            if (!result.success) {
                _encodeError = result.error || "encode failed"
                return false
            }
            var words = result.result.words
            pInstrData.text = words.join("\n")
            _encodePreview = words.length + " words · " + result.result.hex.slice(0, 18) + "…"
            proposeMode = 0  // switch back to raw view to confirm
            return true
        }

        header: Item {
            height: 52
            RowLayout {
                anchors { fill: parent; leftMargin: 20; rightMargin: 16 }
                Text {
                    text: "New Proposal"
                    color: Theme.palette.text
                    font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
                    Layout.fillWidth: true
                }
                // Mode toggle
                Rectangle {
                    width: modeToggleText.implicitWidth + 16; height: 28; radius: Theme.spacing.radiusLarge
                    color: modeToggleArea.containsMouse ? Theme.palette.backgroundMuted : Theme.palette.background
                    border.color: proposeDialog.proposeMode === 1 ? Theme.palette.primary : Theme.palette.border
                    Text {
                        id: modeToggleText; anchors.centerIn: parent
                        text: proposeDialog.proposeMode === 0 ? "Encode from IDL…" : "← Raw words"
                        color: proposeDialog.proposeMode === 1 ? Theme.palette.primary : Theme.palette.textMuted
                        font.pixelSize: 11; font.family: Theme.typography.publicSans
                    }
                    MouseArea {
                        id: modeToggleArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: {
                            proposeDialog.proposeMode = proposeDialog.proposeMode === 0 ? 1 : 0
                            proposeDialog._encodeError = ""
                            proposeDialog._encodePreview = ""
                        }
                    }
                }
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 10

            // ── Fields common to both modes ────────────────────────────────
            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: pProposerId; Layout.fillWidth: true; placeholderText: "your account ID" }

            Text { text: "Target program ID (hex)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: pTargetProgram; Layout.fillWidth: true; placeholderText: "64-char hex" }

            // ── Raw words mode ─────────────────────────────────────────────
            ColumnLayout {
                visible: proposeDialog.proposeMode === 0
                Layout.fillWidth: true; spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Instruction data (u32 words, one per line)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans; Layout.fillWidth: true }
                    Text {
                        visible: proposeDialog._encodePreview !== ""
                        text: "✓ " + proposeDialog._encodePreview
                        color: Theme.palette.success; font.pixelSize: 10; font.family: Theme.typography.publicSans
                    }
                }
                TextArea {
                    id: pInstrData; Layout.fillWidth: true; implicitHeight: 72
                    placeholderText: "0\n1000\n0\n…  (or use Encode from IDL →)"
                    color: Theme.palette.text
                    placeholderTextColor: Theme.palette.textPlaceholder
                    wrapMode: TextArea.Wrap
                    background: Rectangle {
                        color: Theme.palette.backgroundSecondary
                        border.color: Theme.palette.border
                        radius: Theme.spacing.radiusSmall
                    }
                }
            }

            // ── Encode-from-IDL mode ───────────────────────────────────────
            ColumnLayout {
                visible: proposeDialog.proposeMode === 1
                Layout.fillWidth: true; spacing: 6

                // Spelbook search (only when spelbook is linked)
                ColumnLayout {
                    visible: spelbook.isAvailable()
                    Layout.fillWidth: true; spacing: 4

                    Text { text: "Search spelbook registry"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        LogosTextField {
                            id: pSpelQuery; Layout.fillWidth: true
                            placeholderText: "program name or leave blank for all"
                            onTextChanged: proposeDialog._spelQuery = text
                        }
                        Rectangle {
                            width: spelSearchText.implicitWidth + 16; height: 36
                            radius: Theme.spacing.radiusLarge
                            color: spelSearchArea.containsMouse ? Theme.palette.backgroundMuted : Theme.palette.background
                            border.color: Theme.palette.border
                            Text {
                                id: spelSearchText; anchors.centerIn: parent
                                text: "Search"; color: Theme.palette.textMuted
                                font.pixelSize: 11; font.family: Theme.typography.publicSans
                            }
                            MouseArea {
                                id: spelSearchArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: {
                                    var resStr = spelbook.searchPrograms(proposeDialog._spelQuery)
                                    var res = JSON.parse(resStr)
                                    proposeDialog._spelResults = res.success ? res.programs : []
                                }
                            }
                        }
                    }

                    // Search results
                    Repeater {
                        model: proposeDialog._spelResults
                        Rectangle {
                            Layout.fillWidth: true; height: 44; radius: Theme.spacing.radiusSmall
                            color: spelResultArea.containsMouse
                                ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.10)
                                : Theme.palette.background
                            border.color: spelResultArea.containsMouse ? Theme.palette.primary : Theme.palette.border

                            ColumnLayout {
                                anchors { fill: parent; margins: 8 }; spacing: 2
                                Text {
                                    text: (modelData["name"] || "Unknown") + (modelData["version"] ? "  v" + modelData["version"] : "")
                                    color: Theme.palette.text; font.pixelSize: 12; font.bold: true
                                    font.family: Theme.typography.publicSans
                                    elide: Text.ElideRight; Layout.fillWidth: true
                                }
                                Text {
                                    text: shortHex(modelData["program_id"] || "") +
                                          (modelData["idl_cid"] ? "  · IDL available" : "  · no IDL")
                                    color: Theme.palette.textMuted; font.pixelSize: 10
                                    font.family: "monospace"; elide: Text.ElideRight; Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: spelResultArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: {
                                    // Populate target program field
                                    pTargetProgram.text = modelData["program_id"] || ""
                                    // Fetch IDL if cid + storage URL available
                                    var idlCid = modelData["idl_cid"] || ""
                                    if (idlCid && _storageUrl) {
                                        var idlStr = spelbook.fetchIdl(_storageUrl, idlCid)
                                        var idlRes = JSON.parse(idlStr)
                                        if (idlRes.success) {
                                            pIdlJson.text = JSON.stringify(idlRes.idl)
                                            proposeDialog._encodeError = ""
                                        } else {
                                            proposeDialog._encodeError = "IDL fetch failed: " + (idlRes.error || "unknown")
                                        }
                                    } else if (idlCid && !_storageUrl) {
                                        proposeDialog._encodeError = "IDL cid: " + idlCid.slice(0, 16) + "… — set Storage URL in Settings to fetch"
                                    }
                                    proposeDialog._spelResults = []
                                    pSpelQuery.text = ""
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: proposeDialog._spelResults.length === 0 && pSpelQuery.text.length > 0
                        Layout.fillWidth: true; height: 1; color: Theme.palette.border
                    }
                }

                Text { text: "Program IDL (paste JSON)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                TextArea {
                    id: pIdlJson; Layout.fillWidth: true; implicitHeight: 80
                    placeholderText: '{"name":"token","instructions":[…]}'
                    color: Theme.palette.text; font.pixelSize: 11; font.family: "monospace"
                    placeholderTextColor: Theme.palette.textPlaceholder
                    wrapMode: TextArea.WrapAtWordBoundaryOrAnywhere
                    background: Rectangle {
                        color: Theme.palette.backgroundSecondary
                        border.color: Theme.palette.border; radius: Theme.spacing.radiusSmall
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: "Instruction name"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                        LogosTextField { id: pIxName; Layout.fillWidth: true; placeholderText: "e.g. transfer_tokens" }
                    }
                }

                Text { text: "Args (JSON object)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                TextArea {
                    id: pArgsJson; Layout.fillWidth: true; implicitHeight: 60
                    placeholderText: '{"amount": 1000, "recipient": "0x01020304…"}'
                    color: Theme.palette.text; font.pixelSize: 11; font.family: "monospace"
                    placeholderTextColor: Theme.palette.textPlaceholder
                    wrapMode: TextArea.WrapAtWordBoundaryOrAnywhere
                    background: Rectangle {
                        color: Theme.palette.backgroundSecondary
                        border.color: Theme.palette.border; radius: Theme.spacing.radiusSmall
                    }
                }

                // Error + Encode button row
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        visible: proposeDialog._encodeError !== ""
                        text: proposeDialog._encodeError
                        color: Theme.palette.error; font.pixelSize: 10; font.family: Theme.typography.publicSans
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Item { Layout.fillWidth: true; visible: proposeDialog._encodeError === "" }
                    Rectangle {
                        width: encodeText.implicitWidth + 20; height: 32; radius: Theme.spacing.radiusXlarge
                        color: encodeArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                        Text {
                            id: encodeText; anchors.centerIn: parent
                            text: "Encode →"; color: Theme.palette.text
                            font.pixelSize: 12; font.family: Theme.typography.publicSans
                        }
                        MouseArea {
                            id: encodeArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: proposeDialog._runEncode()
                        }
                    }
                }
            }

            // ── Common: account count + proposal index ─────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "Target account count"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                    LogosTextField { id: pAcctCount; Layout.fillWidth: true; placeholderText: "0" }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "Proposal index"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                    LogosTextField {
                        id: pPropIdx; Layout.fillWidth: true
                        placeholderText: String(parseInt(backend.multisigState["transaction_index"]) || 0)
                    }
                }
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Cancel"
                onClicked: { proposeDialog.close(); proposeDialog.proposeMode = 0 }
            }
            // In encode mode, show Encode button only; in raw mode, show Propose
            Rectangle {
                visible: proposeDialog.proposeMode === 1
                width: encodeFooterText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: encodeFooterArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                Text {
                    id: encodeFooterText; anchors.centerIn: parent
                    text: "Encode"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: encodeFooterArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: proposeDialog._runEncode()
                }
            }
            Rectangle {
                visible: proposeDialog.proposeMode === 0
                width: propOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: propOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: backend.busy ? 0.5 : 1.0
                Text {
                    id: propOkText; anchors.centerIn: parent
                    text: "Propose"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: propOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (!backend.busy && proposeDialog.proposeMode === 0) {
                            var instrWords = pInstrData.text.split("\n")
                                .map(function(s){ return s.trim() })
                                .filter(function(s){ return s.length > 0 })
                            var propIdx = pPropIdx.text.length > 0
                                ? pPropIdx.text
                                : String(parseInt(backend.multisigState["transaction_index"]) || 0)
                            backend.propose(pProposerId.text.trim(), pTargetProgram.text.trim(),
                                            instrWords, parseInt(pAcctCount.text) || 0,
                                            [], [], activeCreateKey, propIdx)
                            proposeDialog.close()
                            proposeDialog.proposeMode = 0
                            proposeDialog._encodePreview = ""
                        }
                    }
                }
            }
        }
    }

    // ── Add member dialog ─────────────────────────────────────────────────────
    Dialog {
        id: addMemberDialog
        title: "Propose Add Member"
        modal: true; anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: addMemberDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 10

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: amProposerId; Layout.fillWidth: true; placeholderText: "your account ID" }

            Text { text: "New member account ID (fresh keypair)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: amNewMember; Layout.fillWidth: true; placeholderText: "fresh keypair account ID" }

            Text { text: "Proposal index"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: amPropIdx; Layout.fillWidth: true
                placeholderText: String(parseInt(backend.multisigState["transaction_index"]) || 0)
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton { text: "Cancel"; onClicked: addMemberDialog.close() }
            Rectangle {
                width: amOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: amOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: backend.busy ? 0.5 : 1.0
                Text {
                    id: amOkText; anchors.centerIn: parent
                    text: "Propose"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: amOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (!backend.busy) {
                            var propIdx = amPropIdx.text.length > 0
                                ? amPropIdx.text
                                : String(parseInt(backend.multisigState["transaction_index"]) || 0)
                            backend.proposeAddMember(amProposerId.text.trim(), amNewMember.text.trim(),
                                                     activeCreateKey, propIdx)
                            addMemberDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Remove member dialog ──────────────────────────────────────────────────
    Dialog {
        id: removeMemberDialog
        title: "Propose Remove Member"
        modal: true; anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: removeMemberDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 10

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: rmProposerId; Layout.fillWidth: true; placeholderText: "your account ID" }

            Text { text: "Member to remove (account ID)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: rmMember; Layout.fillWidth: true; placeholderText: "account ID to remove" }

            Text { text: "Proposal index"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: rmPropIdx; Layout.fillWidth: true
                placeholderText: String(parseInt(backend.multisigState["transaction_index"]) || 0)
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton { text: "Cancel"; onClicked: removeMemberDialog.close() }
            Rectangle {
                width: rmOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: rmOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: backend.busy ? 0.5 : 1.0
                Text {
                    id: rmOkText; anchors.centerIn: parent
                    text: "Propose"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: rmOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (!backend.busy) {
                            var propIdx = rmPropIdx.text.length > 0
                                ? rmPropIdx.text
                                : String(parseInt(backend.multisigState["transaction_index"]) || 0)
                            backend.proposeRemoveMember(rmProposerId.text.trim(), rmMember.text.trim(),
                                                        activeCreateKey, propIdx)
                            removeMemberDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Change threshold dialog ───────────────────────────────────────────────
    Dialog {
        id: changeThresholdDialog
        title: "Propose Change Threshold"
        modal: true; anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: changeThresholdDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 10

            Text {
                text: "Current threshold: " + threshold() + " of " + memberCount()
                color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                visible: Object.keys(backend.multisigState).length > 0
            }

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: ctProposerId; Layout.fillWidth: true; placeholderText: "your account ID" }

            Text { text: "New threshold (M)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: ctNewThreshold; Layout.fillWidth: true; placeholderText: "e.g. 3" }

            Text { text: "Proposal index"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: ctPropIdx; Layout.fillWidth: true
                placeholderText: String(parseInt(backend.multisigState["transaction_index"]) || 0)
            }
        }

        footer: RowLayout {
            spacing: 8; Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton { text: "Cancel"; onClicked: changeThresholdDialog.close() }
            Rectangle {
                width: ctOkText.implicitWidth + 24; height: 40; radius: Theme.spacing.radiusXlarge
                color: ctOkArea.containsMouse ? Theme.palette.primaryHover : Theme.palette.primary
                opacity: backend.busy ? 0.5 : 1.0
                Text {
                    id: ctOkText; anchors.centerIn: parent
                    text: "Propose"; color: Theme.palette.text
                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                }
                MouseArea {
                    id: ctOkArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        if (!backend.busy && ctNewThreshold.text.length > 0) {
                            var propIdx = ctPropIdx.text.length > 0
                                ? ctPropIdx.text
                                : String(parseInt(backend.multisigState["transaction_index"]) || 0)
                            backend.proposeChangeThreshold(ctProposerId.text.trim(),
                                                           parseInt(ctNewThreshold.text),
                                                           activeCreateKey, propIdx)
                            changeThresholdDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ── Account picker (approve / reject / execute) ────────────────────────────
    Dialog {
        id: accountPicker
        property string action: ""
        property int proposalIndex: 0
        modal: true; anchors.centerIn: parent
        width: Math.min(420, parent.width - 48)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            height: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: accountPicker.action + " Proposal #" + accountPicker.proposalIndex
                color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            width: parent.width; spacing: 8

            Text {
                text: "Select your account"
                color: Theme.palette.textMuted
                font.pixelSize: 11; font.family: Theme.typography.publicSans
            }

            Repeater {
                model: backend.walletAccounts
                delegate: Rectangle {
                    Layout.fillWidth: true; height: 44; radius: Theme.spacing.radiusLarge
                    color: pickArea.containsMouse
                        ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.12)
                        : Theme.palette.background
                    border.color: pickArea.containsMouse ? Theme.palette.primary : Theme.palette.border

                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        Text {
                            text: modelData["label"] || shortHex(modelData["id"] || "")
                            color: Theme.palette.text
                            font.pixelSize: 12; font.family: Theme.typography.publicSans
                            Layout.fillWidth: true; elide: Text.ElideRight
                        }
                        Text {
                            visible: !!modelData["label"]
                            text: shortHex(modelData["id"] || "")
                            color: Theme.palette.textMuted
                            font.pixelSize: 11; elide: Text.ElideRight; Layout.preferredWidth: 120
                        }
                    }

                    MouseArea {
                        id: pickArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: {
                            var acctId = modelData["id"] || ""
                            if      (accountPicker.action === "Approve") backend.approve(acctId, accountPicker.proposalIndex, activeCreateKey)
                            else if (accountPicker.action === "Reject")  backend.reject(acctId, accountPicker.proposalIndex, activeCreateKey)
                            else if (accountPicker.action === "Execute") backend.execute(acctId, accountPicker.proposalIndex, activeCreateKey)
                            accountPicker.close()
                        }
                    }
                }
            }

            Text {
                visible: backend.walletAccounts.length === 0
                text: "No accounts — go to Settings and refresh."
                color: Theme.palette.textMuted
                font.pixelSize: 12; font.family: Theme.typography.publicSans
            }
        }

        footer: RowLayout {
            Layout.rightMargin: 16; Layout.bottomMargin: 12
            Item { Layout.fillWidth: true }
            LogosButton { text: "Cancel"; onClicked: accountPicker.close() }
        }
    }
}
