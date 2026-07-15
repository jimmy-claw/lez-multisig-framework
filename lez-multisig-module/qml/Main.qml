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
    property int detailTab: 0    // 0=Proposals, 1=Vault

    // ── Multisig state ────────────────────────────────────────────────────────
    property var knownMultisigs: []      // [{createKey, label}]
    property string activeCreateKey: ""
    property var proposals: []           // accumulated for activeCreateKey
    property int _fetchTarget: 0
    property int _fetchNext: 0
    property string _multisigIdl: ""    // lazily loaded from codec.getMultisigIdl()
    property int _busyElapsed: 0

    Timer {
        id: busyTimer
        interval: 1000; repeat: true; running: backend.busy
        onTriggered: _busyElapsed++
        onRunningChanged: if (!running) _busyElapsed = 0
    }

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

    function base58ToHex(s) {
        s = s.replace(/^(Public|Private)\//, "")
        var alpha = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        var bytes = []
        var i
        for (i = 0; i < 32; i++) bytes.push(0)
        for (i = 0; i < s.length; i++) {
            var carry = alpha.indexOf(s[i])
            if (carry < 0) return ""
            for (var j = 31; j >= 0; j--) {
                carry += bytes[j] * 58
                bytes[j] = carry & 0xff
                carry = carry >> 8
            }
        }
        var hex = ""
        for (i = 0; i < 32; i++) {
            var b = bytes[i]
            hex += ((b >> 4) & 0xf).toString(16) + (b & 0xf).toString(16)
        }
        return hex
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

    function describeConfigAction(ca) {
        if (!ca) return ""
        var keys = Object.keys(ca)
        if (keys.length === 0) return JSON.stringify(ca)
        var type = keys[0]
        if (type === "AddMember")        return "Add member: " + shortHex(ca[type]["new_member"] || "")
        if (type === "RemoveMember")     return "Remove member: " + shortHex(ca[type]["member"] || "")
        if (type === "ChangeThreshold")  return "Change threshold to " + ca[type]["new_threshold"]
        return JSON.stringify(ca)
    }

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
        return s["members"].map(function(m) {
            if (typeof m === "string") return m
            return u8ArrayToHex(m)
        })
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    function loadKnownMultisigs() {
        var rawArr = JSON.parse(JSON.stringify(backend.fieldHistory("multisig_create_keys")))
        var raw = (rawArr && rawArr.length > 0) ? rawArr[0] : ""
        var labelsArr = JSON.parse(JSON.stringify(backend.fieldHistory("multisig_labels")))
        var labelsRaw = (labelsArr && labelsArr.length > 0) ? labelsArr[0] : ""
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
            var labelsArr = JSON.parse(JSON.stringify(backend.fieldHistory("multisig_labels")))
            var labelsRaw = (labelsArr && labelsArr.length > 0) ? labelsArr[0] : ""
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
        var labelsArr = JSON.parse(JSON.stringify(backend.fieldHistory("multisig_labels")))
        var labelsRaw = (labelsArr && labelsArr.length > 0) ? labelsArr[0] : ""
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
        detailTab = 0
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
            var fetchIdx = _fetchNext  // PDA index used to fetch = actual on-chain slot
            // Tag the proposal with its PDA index (differs from p["index"] because the
            // on-chain program uses next_proposal_index() which increments before assigning)
            var entry = {}
            var keys = Object.keys(p)
            for (var i = 0; i < keys.length; i++) entry[keys[i]] = p[keys[i]]
            entry["_pda_index"] = fetchIdx
            var arr = proposals.slice()
            arr[fetchIdx] = entry
            proposals = arr
            _fetchNext = fetchIdx + 1
            fetchNextProposal()
        }

        function onOperationSuccess(operation, txHash) {
            toast.show("✓ " + operation + (txHash ? " · " + txHash.slice(0, 12) + "…" : ""), Theme.palette.success)
            // Qt.callLater defers until after m_busy is cleared in C++ (m_busy is still true
            // when this signal fires — it's set to false only after handleFfiResult returns)
            Qt.callLater(function() { if (activeCreateKey) backend.fetchMultisigState(activeCreateKey) })
        }

        function onOperationError(operation, error) {
            toast.show("✗ " + operation + ": " + error, Theme.palette.error)
        }

        function onWalletAccountsChanged() {}
    }

    // ── Reusable account field with history + wallet picker ───────────────────
    component AccountField: Item {
        id: _af
        property alias text: _afField.text
        property alias placeholderText: _afField.placeholderText
        property string historyKey: ""
        property bool showCurrentMembers: false
        Layout.fillWidth: true
        implicitHeight: _afField.implicitHeight

        property var _hist: []
        property var _accts: []
        property var _members: []

        LogosTextField {
            id: _afField
            anchors { left: parent.left; right: _afBtn.left; top: parent.top; bottom: parent.bottom }
            anchors.rightMargin: 4
        }

        Rectangle {
            id: _afBtn
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 6
            color: _afBtnHover.containsMouse ? Theme.palette.backgroundSecondary : Theme.palette.backgroundElevated
            border.color: Theme.palette.border

            Text { anchors.centerIn: parent; text: "▾"; color: Theme.palette.textMuted; font.pixelSize: 14 }

            MouseArea {
                id: _afBtnHover
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: {
                    _af._hist = JSON.parse(JSON.stringify(backend.fieldHistory(_af.historyKey)))
                    _af._accts = JSON.parse(JSON.stringify(backend.walletAccounts))
                    _af._members = _af.showCurrentMembers ? membersHex() : []
                    _afPop.open()
                }
            }

            Popup {
                id: _afPop
                y: _afBtn.height + 2; x: -(_afField.width + 4)
                width: _afField.width + _afBtn.width + 4
                padding: 0
                background: Rectangle { color: Theme.palette.backgroundElevated; border.color: Theme.palette.border; radius: 6 }
                contentItem: Column {
                    width: parent.width; spacing: 0; topPadding: 4; bottomPadding: 4

                    Text { visible: _af._hist.length > 0; text: "RECENT"; color: Theme.palette.textMuted; font.pixelSize: 10; font.bold: true; font.family: Theme.typography.publicSans; leftPadding: 10; topPadding: 2; bottomPadding: 2; width: parent.width }
                    Repeater {
                        model: _af._hist
                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width; height: 34
                            color: _mh.containsMouse ? Theme.palette.backgroundSecondary : "transparent"
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 10; width: parent.width - 10; text: modelData; color: Theme.palette.text; elide: Text.ElideMiddle; font.pixelSize: 12; font.family: Theme.typography.publicSans }
                            MouseArea { id: _mh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { _afField.text = modelData; _afPop.close() } }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.palette.border; visible: _af._hist.length > 0 && (_af._members.length > 0 || _af._accts.length > 0) }

                    Text { visible: _af._members.length > 0; text: "MEMBERS"; color: Theme.palette.textMuted; font.pixelSize: 10; font.bold: true; font.family: Theme.typography.publicSans; leftPadding: 10; topPadding: 2; bottomPadding: 2; width: parent.width }
                    Repeater {
                        model: _af._members
                        delegate: Rectangle {
                            required property string modelData
                            width: parent.width; height: 34
                            color: _mm.containsMouse ? Theme.palette.backgroundSecondary : "transparent"
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 10; width: parent.width - 10; text: modelData; color: Theme.palette.text; elide: Text.ElideMiddle; font.pixelSize: 12; font.family: Theme.typography.publicSans }
                            MouseArea { id: _mm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { _afField.text = modelData; backend.saveHistory(_af.historyKey, modelData); _afPop.close() } }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: Theme.palette.border; visible: (_af._hist.length > 0 || _af._members.length > 0) && _af._accts.length > 0 }

                    Text { visible: _af._accts.length > 0; text: "WALLET"; color: Theme.palette.textMuted; font.pixelSize: 10; font.bold: true; font.family: Theme.typography.publicSans; leftPadding: 10; topPadding: 2; bottomPadding: 2; width: parent.width }
                    Repeater {
                        model: _af._accts
                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width; height: 34
                            color: _mw.containsMouse ? Theme.palette.backgroundSecondary : "transparent"
                            Text { anchors.verticalCenter: parent.verticalCenter; x: 10; width: parent.width - 10; text: modelData.id + (modelData.label ? "  [" + modelData.label + "]" : ""); color: Theme.palette.text; elide: Text.ElideMiddle; font.pixelSize: 12; font.family: Theme.typography.publicSans }
                            MouseArea { id: _mw; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { _afField.text = modelData.id; backend.saveHistory(_af.historyKey, modelData.id); _afPop.close() } }
                        }
                    }

                    Item { visible: _af._hist.length === 0 && _af._accts.length === 0 && _af._members.length === 0; height: 36; width: parent.width
                        Text { anchors.centerIn: parent; text: "No accounts or history yet."; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans } }
                }
            }
        }
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
                RowLayout {
                    visible: backend.busy; spacing: 8
                    Row {
                        spacing: 4
                        Layout.alignment: Qt.AlignVCenter
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
                    Text {
                        visible: _busyElapsed >= 4
                        Layout.alignment: Qt.AlignVCenter
                        text: "Confirming… " + _busyElapsed + "s"
                        color: Theme.palette.textMuted
                        font.pixelSize: 11; font.family: Theme.typography.publicSans
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

                    // Multisig header card — only the threshold row; everything else is in the outer
                    // ColumnLayout so we never depend on implicitHeight of dynamically-visible children.
                    Rectangle {
                        Layout.fillWidth: true
                        height: 56
                        color: Theme.palette.backgroundSecondary
                        border.color: Theme.palette.border

                        RowLayout {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
                            Text {
                                text: Object.keys(backend.multisigState).length > 0
                                      ? (threshold() + " of " + memberCount() + " threshold")
                                      : "Loading…"
                                color: Object.keys(backend.multisigState).length > 0 ? Theme.palette.text : Theme.palette.textMuted
                                font.pixelSize: 15; font.bold: true
                                font.family: Theme.typography.publicSans
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                width: 28; height: 28; implicitHeight: 28; radius: Theme.spacing.radiusSmall
                                color: refArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                Text { anchors.centerIn: parent; text: "↺"; color: Theme.palette.textMuted; font.pixelSize: 16 }
                                MouseArea {
                                    id: refArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: openMultisig(activeCreateKey)
                                }
                            }
                        }
                    }

                    // Create key row
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16; Layout.rightMargin: 16
                        Layout.preferredHeight: 24
                        visible: !!activeCreateKey
                        spacing: 6
                        Text {
                            text: "Key:"
                            color: Theme.palette.textMuted
                            font.pixelSize: 11; font.family: Theme.typography.publicSans
                        }
                        Text {
                            text: shortHex(activeCreateKey)
                            color: Theme.palette.text
                            font.pixelSize: 11; font.family: "monospace"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            width: 44; height: 20; implicitHeight: 20; radius: Theme.spacing.radiusLarge
                            color: pdaCopyArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                            border.color: Theme.palette.border
                            Text {
                                anchors.centerIn: parent
                                text: "Copy"; color: Theme.palette.textMuted
                                font.pixelSize: 10; font.family: Theme.typography.publicSans
                            }
                            MouseArea {
                                id: pdaCopyArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: { clipHelper.copyText(activeCreateKey); toast.show("Copied key") }
                            }
                        }
                    }

                    // Members chips (outside header card — Flow.implicitHeight is 0 until layout, so keeping
                    // it here avoids the header Rectangle sizing itself too small)
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: 16; Layout.rightMargin: 16
                        Layout.topMargin: 6; Layout.bottomMargin: 2
                        spacing: 6
                        visible: membersHex().length > 0
                        Repeater {
                            model: membersHex()
                            Rectangle {
                                property string memberHex: modelData
                                width: chipRow.implicitWidth + 18
                                height: 22; implicitHeight: 22
                                radius: 11
                                color: chipArea.containsMouse
                                    ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.22)
                                    : Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.12)
                                border.color: Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.3)
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: (index + 1)
                                        color: Theme.palette.primary
                                        font.pixelSize: 9; font.bold: true
                                        font.family: Theme.typography.publicSans
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: shortHex(memberHex)
                                        color: Theme.palette.text
                                        font.pixelSize: 10; font.family: "monospace"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                MouseArea {
                                    id: chipArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: { clipHelper.copyText(memberHex); toast.show("Copied member ID") }
                                }
                            }
                        }
                    }

                    // Actions bar (outside header card so height never clips it)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        Layout.leftMargin: 16; Layout.rightMargin: 16
                        // Tab switcher
                        Repeater {
                            model: ["Proposals", "Vault"]
                            Rectangle {
                                width: detailTabLabel.implicitWidth + 16; height: 26; implicitHeight: 26
                                radius: Theme.spacing.radiusLarge
                                color: root.detailTab === index
                                    ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.15)
                                    : "transparent"
                                border.color: root.detailTab === index ? Theme.palette.primary : "transparent"
                                Text {
                                    id: detailTabLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: root.detailTab === index ? Theme.palette.primary : Theme.palette.textMuted
                                    font.pixelSize: 12; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.detailTab = index
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        // Proposals-tab actions
                        Rectangle {
                            visible: root.detailTab === 0
                            width: newPropText.implicitWidth + 16; height: 26; implicitHeight: 26; radius: Theme.spacing.radiusLarge
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
                            model: root.detailTab === 0 ? ["Add Member", "Remove Member", "Change Threshold"] : []
                            Rectangle {
                                width: govText.implicitWidth + 16; height: 26; implicitHeight: 26; radius: Theme.spacing.radiusLarge
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
                                        if (modelData === "Add Member")        addMemberDialog.open()
                                        else if (modelData === "Remove Member")    removeMemberDialog.open()
                                        else if (modelData === "Change Threshold") changeThresholdDialog.open()
                                    }
                                }
                            }
                        }
                    }

                    // ── Vault / PDA manager tab ───────────────────────────────
                    ScrollView {
                        visible: root.detailTab === 1
                        Layout.fillWidth: true; Layout.fillHeight: true; clip: true; contentWidth: availableWidth

                        ColumnLayout {
                            width: parent.parent.width; spacing: 0

                            Item { height: 16; Layout.fillWidth: true }

                            // Multisig state account card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16; Layout.rightMargin: 16
                                radius: Theme.spacing.radiusLarge
                                color: Theme.palette.backgroundSecondary
                                border.color: Theme.palette.border
                                height: vaultStateCol.implicitHeight + 24

                                ColumnLayout {
                                    id: vaultStateCol
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                    spacing: 6

                                    Text {
                                        text: "Multisig state account"
                                        color: Theme.palette.textMuted
                                        font.pixelSize: 11; font.family: Theme.typography.publicSans
                                    }
                                    Text {
                                        text: "Stores the multisig configuration (members, threshold, proposals). Not for funding."
                                        color: Theme.palette.textMuted
                                        font.pixelSize: 11; font.family: Theme.typography.publicSans
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 8
                                        Text {
                                            text: backend.multisigState["multisig_state_id"] || "—"
                                            color: Theme.palette.text
                                            font.pixelSize: 11; font.family: "monospace"
                                            elide: Text.ElideMiddle
                                            Layout.fillWidth: true
                                        }
                                        Rectangle {
                                            width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                            color: stateIdCopyArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                            border.color: Theme.palette.border
                                            Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                            MouseArea {
                                                id: stateIdCopyArea; anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                onClicked: {
                                                    clipHelper.copyText(backend.multisigState["multisig_state_id"] || "")
                                                    toast.show("Copied state account ID")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { height: 16; Layout.fillWidth: true }

                            // ── PDA manager ───────────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16; Layout.rightMargin: 16
                                spacing: 10

                                // section header
                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Vault PDAs"
                                        color: Theme.palette.text
                                        font.pixelSize: 13; font.bold: true; font.family: Theme.typography.publicSans
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "Named accounts this multisig controls as a signer"
                                        color: Theme.palette.textMuted
                                        font.pixelSize: 11; font.family: Theme.typography.publicSans
                                    }
                                }

                                // Default vault (always first)
                                Rectangle {
                                    Layout.fillWidth: true
                                    radius: Theme.spacing.radiusLarge
                                    color: Theme.palette.backgroundSecondary
                                    border.color: Theme.palette.primary
                                    height: defaultVaultCol.implicitHeight + 24

                                    ColumnLayout {
                                        id: defaultVaultCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                        spacing: 6

                                        RowLayout {
                                            spacing: 8
                                            Text {
                                                text: "Default vault"
                                                color: Theme.palette.primary
                                                font.pixelSize: 12; font.bold: true; font.family: Theme.typography.publicSans
                                            }
                                            Rectangle {
                                                width: defaultVaultChip.implicitWidth + 10; height: 18; radius: 9
                                                color: Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.15)
                                                Text { id: defaultVaultChip; anchors.centerIn: parent; text: "Fund this"; color: Theme.palette.primary; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                            }
                                        }
                                        Text {
                                            text: "purpose: (empty string) — general-purpose multisig signer"
                                            color: Theme.palette.textMuted; font.pixelSize: 10; font.family: "monospace"
                                            Layout.fillWidth: true
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: backend.multisigState["vault_id"] || "—"
                                                color: Theme.palette.text; font.pixelSize: 11; font.family: "monospace"
                                                elide: Text.ElideMiddle; Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                                color: defAddrCopy.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                                border.color: Theme.palette.border
                                                Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                MouseArea { id: defAddrCopy; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                    onClicked: { clipHelper.copyText(backend.multisigState["vault_id"] || ""); toast.show("Copied vault address") } }
                                            }
                                        }
                                        // Default vault seed (from FFI)
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            property var _seed: root.activeCreateKey ? backend.computePda(root.activeCreateKey, "") : ({})
                                            Text {
                                                text: "seed:"
                                                color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans
                                            }
                                            Text {
                                                text: parent._seed["seed_hex"] || "—"
                                                color: Theme.palette.textMuted; font.pixelSize: 10; font.family: "monospace"
                                                elide: Text.ElideMiddle; Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                                color: defSeedCopy.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                                border.color: Theme.palette.border
                                                Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                MouseArea { id: defSeedCopy; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                    onClicked: { clipHelper.copyText(parent.parent._seed["seed_hex"] || ""); toast.show("Copied seed hex") } }
                                            }
                                        }
                                    }
                                }

                                // Named vaults (user-derived)
                                Repeater {
                                    id: namedPdaRepeater
                                    model: root.activeCreateKey ? backend.fieldHistory("pdas:" + root.activeCreateKey) : []
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        property var pdaData: { try { return JSON.parse(modelData) } catch(e) { return {} } }
                                        Layout.fillWidth: true
                                        radius: Theme.spacing.radiusLarge
                                        color: Theme.palette.backgroundSecondary
                                        border.color: Theme.palette.border
                                        height: namedPdaCol.implicitHeight + 24

                                        ColumnLayout {
                                            id: namedPdaCol
                                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                            spacing: 6

                                            RowLayout {
                                                spacing: 8
                                                Text {
                                                    text: pdaData["label"] || ("Vault " + (index + 1))
                                                    color: Theme.palette.text
                                                    font.pixelSize: 12; font.bold: true; font.family: Theme.typography.publicSans
                                                }
                                                Item { Layout.fillWidth: true }
                                                Rectangle {
                                                    width: delPdaArea.implicitWidth + 16; height: 20; radius: 10
                                                    color: delPdaArea2.containsMouse ? Qt.rgba(1,0,0,0.12) : "transparent"
                                                    border.color: Theme.palette.border
                                                    Text { id: delPdaArea; anchors.centerIn: parent; text: "Remove"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                    MouseArea {
                                                        id: delPdaArea2; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                        onClicked: {
                                                            var list = backend.fieldHistory("pdas:" + root.activeCreateKey)
                                                            list.splice(index, 1)
                                                            backend.clearHistory("pdas:" + root.activeCreateKey)
                                                            proposeDialog._vaultEpoch++
                                                            // re-add in reverse so prepend preserves order
                                                            for (var ri = list.length - 1; ri >= 0; ri--)
                                                                backend.saveHistory("pdas:" + root.activeCreateKey, list[ri])
                                                            namedPdaRepeater.model = backend.fieldHistory("pdas:" + root.activeCreateKey)
                                                        }
                                                    }
                                                }
                                            }
                                            Text {
                                                text: "purpose: " + (pdaData["purpose"] || "(empty)")
                                                color: Theme.palette.textMuted; font.pixelSize: 10; font.family: "monospace"
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 8
                                                Text {
                                                    text: pdaData["pda"] || "—"
                                                    color: Theme.palette.text; font.pixelSize: 11; font.family: "monospace"
                                                    elide: Text.ElideMiddle; Layout.fillWidth: true
                                                }
                                                Rectangle {
                                                    width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                                    color: namedAddrCopy.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                                    border.color: Theme.palette.border
                                                    Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                    MouseArea { id: namedAddrCopy; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                        onClicked: { clipHelper.copyText(pdaData["pda"] || ""); toast.show("Copied vault address") } }
                                                }
                                            }
                                            RowLayout {
                                                Layout.fillWidth: true; spacing: 8
                                                Text { text: "seed:"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                Text {
                                                    text: pdaData["seed_hex"] || "—"
                                                    color: Theme.palette.textMuted; font.pixelSize: 10; font.family: "monospace"
                                                    elide: Text.ElideMiddle; Layout.fillWidth: true
                                                }
                                                Rectangle {
                                                    width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                                    color: namedSeedCopy.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                                    border.color: Theme.palette.border
                                                    Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                    MouseArea { id: namedSeedCopy; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                        onClicked: { clipHelper.copyText(pdaData["seed_hex"] || ""); toast.show("Copied seed hex") } }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Derive new named vault
                                Rectangle {
                                    Layout.fillWidth: true
                                    radius: Theme.spacing.radiusLarge
                                    color: "transparent"
                                    border.color: Theme.palette.border
                                    border.width: 1
                                    height: deriveCol.implicitHeight + 24

                                    ColumnLayout {
                                        id: deriveCol
                                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                                        spacing: 8

                                        Text {
                                            text: "Derive a named vault"
                                            color: Theme.palette.text; font.pixelSize: 12; font.bold: true; font.family: Theme.typography.publicSans
                                        }
                                        Text {
                                            text: "Each purpose string produces a unique PDA — use the token definition ID, a label, or any differentiator."
                                            color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            TextField {
                                                id: pdaPurposeInput
                                                placeholderText: "Purpose (e.g. token-A holding, 0xabc123…)"
                                                Layout.fillWidth: true
                                                font.pixelSize: 12; font.family: "monospace"
                                                background: Rectangle { radius: Theme.spacing.radiusSmall; color: Theme.palette.background; border.color: Theme.palette.border; border.width: 1 }
                                                color: Theme.palette.text
                                                Keys.onReturnPressed: derivePdaBtn.clicked()
                                            }
                                            Rectangle {
                                                id: derivePdaBtn
                                                signal clicked()
                                                width: deriveBtnLabel.implicitWidth + 24; height: 36; radius: Theme.spacing.radiusSmall
                                                color: deriveBtnArea.containsMouse ? Qt.lighter(Theme.palette.primary, 1.1) : Theme.palette.primary
                                                Text { id: deriveBtnLabel; anchors.centerIn: parent; text: "Derive"; color: "white"; font.pixelSize: 12; font.bold: true; font.family: Theme.typography.publicSans }
                                                MouseArea { id: deriveBtnArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: derivePdaBtn.clicked() }
                                                onClicked: {
                                                    if (!root.activeCreateKey) { toast.show("No active multisig"); return }
                                                    var purpose = pdaPurposeInput.text.trim()
                                                    var result = backend.computePda(root.activeCreateKey, purpose)
                                                    if (result["error"]) { toast.show("Error: " + result["error"]); return }
                                                    var entry = JSON.stringify({
                                                        label: purpose || "vault",
                                                        purpose: purpose,
                                                        pda: result["pda"],
                                                        seed_hex: result["seed_hex"]
                                                    })
                                                    backend.saveHistory("pdas:" + root.activeCreateKey, entry)
                                                    namedPdaRepeater.model = backend.fieldHistory("pdas:" + root.activeCreateKey)
                                                    proposeDialog._vaultEpoch++
                                                    pdaPurposeInput.text = ""
                                                    toast.show("Vault derived: " + result["pda"].slice(0, 14) + "…")
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { height: 16; Layout.fillWidth: true }

                            // PDA seeds from proposals (existing, kept for reference)
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16; Layout.rightMargin: 16
                                spacing: 8
                                visible: {
                                    var seeds = []
                                    for (var i = 0; i < proposals.length; i++) {
                                        var p = proposals[i]
                                        if (p && p["pda_seeds"]) {
                                            var ps = p["pda_seeds"]
                                            for (var j = 0; j < ps.length; j++) {
                                                var s = ps[j]
                                                if (s && seeds.indexOf(s) === -1) seeds.push(s)
                                            }
                                        }
                                    }
                                    return seeds.length > 0
                                }

                                Text {
                                    text: "PDA seeds used in proposals"
                                    color: Theme.palette.textMuted
                                    font.pixelSize: 11; font.family: Theme.typography.publicSans
                                }

                                Repeater {
                                    model: {
                                        var seeds = []
                                        for (var i = 0; i < proposals.length; i++) {
                                            var p = proposals[i]
                                            if (p && p["pda_seeds"]) {
                                                var ps = p["pda_seeds"]
                                                for (var j = 0; j < ps.length; j++) {
                                                    var s = ps[j]
                                                    if (s && seeds.indexOf(s) === -1) seeds.push(s)
                                                }
                                            }
                                        }
                                        return seeds
                                    }
                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        radius: Theme.spacing.radiusSmall
                                        color: Theme.palette.backgroundSecondary
                                        border.color: Theme.palette.border
                                        height: seedRow.implicitHeight + 16

                                        RowLayout {
                                            id: seedRow
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                                            spacing: 8
                                            Text {
                                                text: "Seed"
                                                color: Theme.palette.textMuted
                                                font.pixelSize: 11; font.family: Theme.typography.publicSans
                                            }
                                            Text {
                                                text: modelData
                                                color: Theme.palette.text
                                                font.pixelSize: 10; font.family: "monospace"
                                                elide: Text.ElideMiddle
                                                Layout.fillWidth: true
                                            }
                                            Rectangle {
                                                width: 44; height: 22; radius: Theme.spacing.radiusLarge
                                                color: seedCopyArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                                border.color: Theme.palette.border
                                                Text { anchors.centerIn: parent; text: "Copy"; color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans }
                                                MouseArea {
                                                    id: seedCopyArea; anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                                    onClicked: { clipHelper.copyText(modelData); toast.show("Copied seed") }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            Item { height: 40; Layout.fillWidth: true }
                        }
                    }

                    // Proposals list
                    ScrollView {
                        visible: root.detailTab === 0
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
                                    property bool pExecutable: pStatus === "Active" && pApproved >= pThreshold
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
                                        var externalIdl = storage.fetchIdl(entry["idl_cid"])
                                        if (!externalIdl) {
                                            _decoded = null; _decodeError = "IDL fetch failed for cid: " + entry["idl_cid"].slice(0, 12) + "…"; return
                                        }
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
                                            text: ca ? describeConfigAction(ca)
                                                 : (pdata["target_program_id"]
                                                     ? "Target: " + shortHex(u32ArrayToHex(pdata["target_program_id"]))
                                                     : "")
                                            visible: text !== ""
                                            color: Theme.palette.textMuted
                                            font.pixelSize: 11; font.family: Theme.typography.publicSans
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

                                        // Decode button (only for proposals with instruction data, not config proposals)
                                        Rectangle {
                                            visible: !!pdata["target_instruction_data"] && !pdata["config_action"]
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

                                        // Approval count + who approved
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                text: pApproved + " / " + pThreshold + " approvals" +
                                                      (pRejected > 0 ? "  ·  " + pRejected + " rejected" : "")
                                                color: Theme.palette.textMuted
                                                font.pixelSize: 11; font.family: Theme.typography.publicSans
                                            }
                                            Repeater {
                                                model: pdata["approved"] || []
                                                Rectangle {
                                                    property string approverId: {
                                                        var a = modelData
                                                        if (typeof a === "string") return a
                                                        if (Array.isArray(a)) return u8ArrayToHex(a)
                                                        return JSON.stringify(a)
                                                    }
                                                    width: approverText.implicitWidth + 10
                                                    height: 16; implicitHeight: 16; radius: 8
                                                    color: Qt.rgba(Theme.palette.success.r, Theme.palette.success.g, Theme.palette.success.b, 0.15)
                                                    border.color: Qt.rgba(Theme.palette.success.r, Theme.palette.success.g, Theme.palette.success.b, 0.4)
                                                    Text {
                                                        id: approverText
                                                        anchors.centerIn: parent
                                                        text: shortHex(parent.approverId)
                                                        color: Theme.palette.success
                                                        font.pixelSize: 9; font.family: "monospace"
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: { clipHelper.copyText(parent.approverId); toast.show("Copied approver ID") }
                                                    }
                                                }
                                            }
                                            Item { Layout.fillWidth: true }
                                        }

                                        // Action buttons (Active proposals only)
                                        RowLayout {
                                            visible: pStatus === "Active"
                                            spacing: 8

                                            Repeater {
                                                model: [
                                                    { label: "Approve", col: Theme.palette.success },
                                                    { label: "Reject",  col: Theme.palette.error   }
                                                ]
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
                                                        property int propIdx: pdata["_pda_index"] !== undefined ? parseInt(pdata["_pda_index"]) : (parseInt(pdata["index"]) || index)
                                                        onClicked: {
                                                            accountPicker.action = propAction
                                                            accountPicker.proposalIndex = propIdx
                                                            accountPicker.proposalData = pdata
                                                            accountPicker.open()
                                                        }
                                                    }
                                                }
                                            }

                                            // Execute — always visible, enabled only when threshold met
                                            Rectangle {
                                                width: executeText.implicitWidth + 16; height: 26
                                                radius: Theme.spacing.radiusSmall
                                                color: pExecutable
                                                    ? (executeArea.containsMouse
                                                        ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.25)
                                                        : Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.10))
                                                    : Theme.palette.backgroundElevated
                                                border.color: pExecutable ? Theme.palette.primary : Theme.palette.border
                                                Text {
                                                    id: executeText; anchors.centerIn: parent
                                                    text: "Execute"
                                                    color: pExecutable ? Theme.palette.primary : Theme.palette.textMuted
                                                    font.pixelSize: 12; font.family: Theme.typography.publicSans
                                                }
                                                MouseArea {
                                                    id: executeArea; anchors.fill: parent
                                                    cursorShape: pExecutable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    hoverEnabled: true
                                                    property int propIdx: pdata["_pda_index"] !== undefined ? parseInt(pdata["_pda_index"]) : (parseInt(pdata["index"]) || index)
                                                    onClicked: {
                                                        if (!pExecutable) return
                                                        accountPicker.action = "Execute"
                                                        accountPicker.proposalIndex = propIdx
                                                        accountPicker.proposalData = pdata
                                                        accountPicker.open()
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
                                { label: "Wallet Path",      getter: function(){ return backend.walletPath },    setter: function(v){ backend.setWalletPath(v) },    copyable: false },
                                { label: "Sequencer URL",    getter: function(){ return backend.sequencerUrl },  setter: function(v){ backend.setSequencerUrl(v) },  copyable: false },
                                { label: "Program ID (hex)", getter: function(){ return backend.programIdHex },  setter: function(v){ backend.setProgramIdHex(v) },  copyable: true  }
                            ]
                            ColumnLayout {
                                Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    Text {
                                        text: modelData.label
                                        color: Theme.palette.textMuted
                                        font.pixelSize: Theme.typography.secondaryText
                                        font.family: Theme.typography.publicSans
                                        Layout.fillWidth: true
                                    }
                                    Rectangle {
                                        visible: modelData.copyable
                                        width: 44; height: 20; radius: Theme.spacing.radiusLarge
                                        color: sfCopyArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                        border.color: Theme.palette.border
                                        Text {
                                            anchors.centerIn: parent
                                            text: "Copy"
                                            color: Theme.palette.textMuted
                                            font.pixelSize: 10; font.family: Theme.typography.publicSans
                                        }
                                        MouseArea {
                                            id: sfCopyArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: { clipHelper.copyText(modelData.getter()); toast.show("Copied!") }
                                        }
                                    }
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
                                Rectangle {
                                    width: 44; height: 20; radius: Theme.spacing.radiusLarge
                                    color: accCopyArea.containsMouse ? Theme.palette.backgroundMuted : "transparent"
                                    border.color: Theme.palette.border
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Copy"
                                        color: Theme.palette.textMuted
                                        font.pixelSize: 10; font.family: Theme.typography.publicSans
                                    }
                                    MouseArea {
                                        id: accCopyArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: { clipHelper.copyText(modelData["id"] || ""); toast.show("Copied account ID") }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24
                            height: 1; color: Theme.palette.border
                        }

                        // Create Account
                        Text {
                            text: "Create Account"
                            color: Theme.palette.text
                            font.pixelSize: 14; font.bold: true
                            font.family: Theme.typography.publicSans
                            Layout.leftMargin: 24
                        }

                        RowLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 24; Layout.rightMargin: 24; spacing: 8

                            TextField {
                                id: newAccountLabel
                                Layout.fillWidth: true
                                placeholderText: "Label (optional)"
                                color: Theme.palette.text
                                placeholderTextColor: Theme.palette.textPlaceholder
                                background: Rectangle {
                                    color: Theme.palette.background
                                    border.color: Theme.palette.border
                                    radius: Theme.spacing.radiusSmall
                                }
                                Keys.onReturnPressed: createAccountBtn.clicked()
                            }

                            Rectangle {
                                id: createAccountBtn
                                width: createAccountBtnText.implicitWidth + 20; height: 36
                                radius: Theme.spacing.radiusLarge
                                color: backend.busy ? Theme.palette.backgroundMuted
                                     : createAccountBtnArea.containsMouse ? Theme.palette.primaryHover
                                     : Theme.palette.primary
                                signal clicked()
                                onClicked: {
                                    backend.createAccount(newAccountLabel.text)
                                    newAccountLabel.text = ""
                                }
                                Text {
                                    id: createAccountBtnText; anchors.centerIn: parent
                                    text: backend.busy ? "Creating…" : "Create"
                                    color: Theme.palette.text
                                    font.pixelSize: 13; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: createAccountBtnArea; anchors.fill: parent
                                    cursorShape: backend.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    hoverEnabled: true; enabled: !backend.busy
                                    onClicked: createAccountBtn.clicked()
                                }
                            }
                        }

                        Connections {
                            target: backend
                            function onOperationSuccess(op, result) {
                                if (op === "create_account") toast.show("Account created: " + result.slice(0, 12) + "…")
                            }
                            function onOperationError(op, err) {
                                if (op === "create_account") toast.show("Error: " + err, Theme.palette.error)
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
        contentHeight: watchContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: watchDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: watchContent
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
            spacing: 8
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
        contentHeight: createContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: createDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: createContent
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
            spacing: 8
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
        contentHeight: Math.min(proposeContent.implicitHeight, parent.height - 160)
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        // 0 = raw words mode, 1 = encode-from-IDL mode
        property int proposeMode: 0
        property string _encodeError: ""
        property string _encodePreview: ""  // "N words: [0, 1000, …]"
        property var _spelResults: []
        property string _spelQuery: ""
        property var _parsedInstructions: []
        property string _selectedIx: ""
        property var _argValues: ({})
        property var _accountValues: []   // [{isAuth: bool, seed: string}] indexed by account
        property string _selectedPresetLabel: ""  // tracks last-clicked builtin chip for program ID persistence
        property int _vaultEpoch: 0      // bumped on open + on vault save/remove → vaultList re-evaluates
        onOpened: { _vaultEpoch++; pTargetProgram.text = "" }
        property var _selectedIxObj: {
            var sel = _selectedIx
            var ixs = _parsedInstructions
            if (!sel) return null
            for (var i = 0; i < ixs.length; i++)
                if (ixs[i] && ixs[i].name === sel) return ixs[i]
            return null
        }
        readonly property var _builtinIdls: [
            { label: "AMM", json: '{"version":"0.1.0","name":"amm","instructions":[{"name":"new_definition","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false},{"name":"pool_definition_lp","writable":false,"signer":false,"init":false},{"name":"lp_lock_holding","writable":false,"signer":false,"init":false},{"name":"user_holding_a","writable":false,"signer":false,"init":false},{"name":"user_holding_b","writable":false,"signer":false,"init":false},{"name":"user_holding_lp","writable":false,"signer":false,"init":false}],"args":[{"name":"token_a_amount","type":"u128"},{"name":"token_b_amount","type":"u128"},{"name":"fees","type":"u128"},{"name":"deadline","type":"u64"}]},{"name":"add_liquidity","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false},{"name":"pool_definition_lp","writable":false,"signer":false,"init":false},{"name":"user_holding_a","writable":false,"signer":false,"init":false},{"name":"user_holding_b","writable":false,"signer":false,"init":false},{"name":"user_holding_lp","writable":false,"signer":false,"init":false}],"args":[{"name":"min_amount_liquidity","type":"u128"},{"name":"max_amount_to_add_token_a","type":"u128"},{"name":"max_amount_to_add_token_b","type":"u128"},{"name":"deadline","type":"u64"}]},{"name":"remove_liquidity","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false},{"name":"pool_definition_lp","writable":false,"signer":false,"init":false},{"name":"user_holding_a","writable":false,"signer":false,"init":false},{"name":"user_holding_b","writable":false,"signer":false,"init":false},{"name":"user_holding_lp","writable":false,"signer":false,"init":false}],"args":[{"name":"remove_liquidity_amount","type":"u128"},{"name":"min_amount_to_remove_token_a","type":"u128"},{"name":"min_amount_to_remove_token_b","type":"u128"},{"name":"deadline","type":"u64"}]},{"name":"swap_exact_input","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false},{"name":"user_holding_a","writable":false,"signer":false,"init":false},{"name":"user_holding_b","writable":false,"signer":false,"init":false}],"args":[{"name":"swap_amount_in","type":"u128"},{"name":"min_amount_out","type":"u128"},{"name":"token_definition_id_in","type":"account_id"},{"name":"deadline","type":"u64"}]},{"name":"swap_exact_output","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false},{"name":"user_holding_a","writable":false,"signer":false,"init":false},{"name":"user_holding_b","writable":false,"signer":false,"init":false}],"args":[{"name":"exact_amount_out","type":"u128"},{"name":"max_amount_in","type":"u128"},{"name":"token_definition_id_in","type":"account_id"},{"name":"deadline","type":"u64"}]},{"name":"sync_reserves","accounts":[{"name":"pool","writable":false,"signer":false,"init":false},{"name":"vault_a","writable":false,"signer":false,"init":false},{"name":"vault_b","writable":false,"signer":false,"init":false}],"args":[]}]}' },
            { label: "ATA", json: '{"version":"0.1.0","name":"ata","instructions":[{"name":"create","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"token_definition","writable":false,"signer":false,"init":false},{"name":"ata_account","writable":false,"signer":false,"init":false}],"args":[{"name":"token_program_id","type":"program_id"}]},{"name":"transfer","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"sender_ata","writable":false,"signer":false,"init":false},{"name":"recipient","writable":false,"signer":false,"init":false}],"args":[{"name":"token_program_id","type":"program_id"},{"name":"amount","type":"u128"}]},{"name":"burn","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"holder_ata","writable":false,"signer":false,"init":false},{"name":"token_definition","writable":false,"signer":false,"init":false}],"args":[{"name":"token_program_id","type":"program_id"},{"name":"amount","type":"u128"}]}]}' },
            { label: "Stablecoin", json: '{"version":"0.1.0","name":"stablecoin","instructions":[{"name":"open_position","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"position","writable":false,"signer":false,"init":false},{"name":"vault","writable":false,"signer":false,"init":false},{"name":"user_holding","writable":false,"signer":false,"init":false},{"name":"token_definition","writable":false,"signer":false,"init":false}],"args":[{"name":"collateral_amount","type":"u128"}]},{"name":"withdraw_collateral","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"position","writable":false,"signer":false,"init":false},{"name":"vault","writable":false,"signer":false,"init":false},{"name":"destination","writable":false,"signer":false,"init":false}],"args":[{"name":"amount","type":"u128"}]},{"name":"repay_debt","accounts":[{"name":"owner","writable":false,"signer":false,"init":false},{"name":"position","writable":false,"signer":false,"init":false},{"name":"stablecoin_definition","writable":false,"signer":false,"init":false},{"name":"user_stablecoin_holding","writable":false,"signer":false,"init":false}],"args":[{"name":"amount","type":"u128"}]}]}' },
            { label: "Token", json: '{"name":"token_program","version":"0.1.0","instructions":[{"name":"transfer","accounts":[{"name":"sender_holding","writable":true,"signer":true,"init":false},{"name":"recipient_holding","writable":true,"signer":false,"init":false}],"args":[{"name":"amount_to_transfer","type":"u128"}]},{"name":"new_fungible_definition","accounts":[{"name":"token_definition","writable":true,"signer":false,"init":true},{"name":"token_holding","writable":true,"signer":false,"init":true}],"args":[{"name":"name","type":"string"},{"name":"total_supply","type":"u128"}]},{"name":"new_definition_with_metadata","accounts":[{"name":"token_definition","writable":true,"signer":false,"init":true},{"name":"token_holding","writable":true,"signer":false,"init":true},{"name":"token_metadata","writable":true,"signer":false,"init":true}],"args":[{"name":"new_definition","type":{"defined":"NewTokenDefinition"}},{"name":"metadata","type":{"defined":"NewTokenMetadata"}}]},{"name":"initialize_account","accounts":[{"name":"token_definition","writable":false,"signer":false,"init":false},{"name":"token_holding","writable":true,"signer":false,"init":true}],"args":[]},{"name":"burn","accounts":[{"name":"token_definition","writable":true,"signer":false,"init":false},{"name":"token_holding","writable":true,"signer":true,"init":false}],"args":[{"name":"amount_to_burn","type":"u128"}]},{"name":"mint","accounts":[{"name":"token_definition","writable":true,"signer":true,"init":false},{"name":"token_holding","writable":true,"signer":false,"init":false}],"args":[{"name":"amount_to_mint","type":"u128"}]},{"name":"print_nft","accounts":[{"name":"nft_master_holding","writable":true,"signer":true,"init":false},{"name":"nft_printed_copy","writable":true,"signer":false,"init":true}],"args":[]}]}' },
            { label: "TWAP Oracle", json: '{"version":"0.1.0","name":"twap_oracle","instructions":[{"name":"noop","accounts":[],"args":[]}]}' }
        ]

        function _runEncode() {
            _encodeError = ""
            _encodePreview = ""
            var idlStr = pIdlJson.text.trim()
            var ixName = proposeDialog._selectedIx || pIxName.text.trim()

            if (!idlStr || !ixName) {
                if (!ixName && _parsedInstructions.length > 0)
                    _encodeError = "Select an instruction from the list above"
                else
                    _encodeError = "Fill in IDL and select an instruction"
                return false
            }

            var argsStr
            var ixObj = proposeDialog._selectedIxObj
            if (ixObj !== null) {
                var ixArgs = ixObj.args || []
                if (ixArgs.length === 0) {
                    argsStr = "{}"
                } else {
                    var obj = {}
                    for (var i = 0; i < ixArgs.length; i++) {
                        var n = ixArgs[i].name
                        var v = (_argValues[n] !== undefined) ? _argValues[n] : ""
                        try { obj[n] = JSON.parse(v) } catch(e) { obj[n] = v }
                    }
                    argsStr = JSON.stringify(obj)
                }
            } else {
                argsStr = pArgsJson.text.trim()
                if (!argsStr) {
                    _encodeError = "Fill in the args JSON"
                    return false
                }
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
            implicitHeight: 52
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

        ScrollView {
            width: parent.width
            height: parent.height
            contentWidth: parent.width
            clip: true

            ColumnLayout {
            id: proposeContent
            width: parent.width; spacing: 10

            // ── Fields common to both modes ────────────────────────────────
            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: pProposerId; historyKey: "proposer_id"; placeholderText: "your account ID" }

            Text { text: "Target program ID (hex)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField {
                id: pTargetProgram; Layout.fillWidth: true; placeholderText: "64-char hex"
                onTextChanged: {
                    var t = text.trim()
                    if (proposeDialog._selectedPresetLabel && t.length === 64)
                        backend.saveHistory("program_id:" + proposeDialog._selectedPresetLabel, t)
                }
            }

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
                                anchors { fill: parent; margins: 8 }
                                spacing: 2
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
                                    // Fetch IDL via Logos Storage module
                                    var idlCid = modelData["idl_cid"] || ""
                                    if (idlCid) {
                                        var idlStr = storage.fetchIdl(idlCid)
                                        if (idlStr) {
                                            pIdlJson.text = idlStr
                                            proposeDialog._encodeError = ""
                                        } else {
                                            proposeDialog._encodeError = "IDL fetch failed for cid: " + idlCid.slice(0, 16) + "…"
                                        }
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

                // Known program IDL quick-select
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "Known programs"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                    Flow {
                        Layout.fillWidth: true; spacing: 6
                        Repeater {
                            model: proposeDialog._builtinIdls
                            delegate: Rectangle {
                                height: 26; radius: Theme.spacing.radiusLarge
                                width: builtinChipText.implicitWidth + 14
                                color: builtinChipArea.containsMouse ? Theme.palette.backgroundMuted : Theme.palette.background
                                border.color: Theme.palette.border
                                Text {
                                    id: builtinChipText; anchors.centerIn: parent
                                    text: modelData.label
                                    color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: builtinChipArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        proposeDialog._selectedPresetLabel = modelData.label
                                        pIdlJson.text = modelData.json
                                        var saved = backend.fieldHistory("program_id:" + modelData.label)
                                        pTargetProgram.text = (saved.length > 0 && saved[0]) ? saved[0] : ""
                                    }
                                }
                            }
                        }
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
                    onTextChanged: {
                        proposeDialog._selectedIx = ""
                        proposeDialog._argValues = ({})
                        proposeDialog._accountValues = []
                        var t = text.trim()
                        if (!t) { proposeDialog._parsedInstructions = []; return }
                        try {
                            var idl = JSON.parse(t)
                            var ixs = idl["instructions"] || []
                            proposeDialog._parsedInstructions = ixs.filter(function(ix) { return !!ix["name"] })
                            if (idl["programId"] && !pTargetProgram.text.trim())
                                pTargetProgram.text = idl["programId"]
                        } catch(e) {
                            proposeDialog._parsedInstructions = []
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4

                    RowLayout {
                        Layout.fillWidth: true; spacing: 6
                        Text {
                            text: "Instruction"
                            color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                            Layout.fillWidth: true
                        }
                        Text {
                            visible: proposeDialog._selectedIx !== ""
                            text: proposeDialog._selectedIx
                            color: Theme.palette.primary; font.pixelSize: 11; font.bold: true
                            font.family: Theme.typography.publicSans
                        }
                    }

                    // Instruction chips — shown when IDL parsed successfully
                    Flow {
                        visible: proposeDialog._parsedInstructions.length > 0
                        Layout.fillWidth: true; spacing: 6

                        Repeater {
                            model: proposeDialog._parsedInstructions
                            delegate: Rectangle {
                                property bool isSelected: modelData.name === proposeDialog._selectedIx
                                height: 28; radius: Theme.spacing.radiusLarge
                                width: ixChipText.implicitWidth + 16
                                color: isSelected ? Theme.palette.primary
                                    : (ixChipArea.containsMouse ? Theme.palette.backgroundMuted : Theme.palette.background)
                                border.color: isSelected ? Theme.palette.primary : Theme.palette.border

                                Text {
                                    id: ixChipText; anchors.centerIn: parent
                                    text: modelData.name || ""
                                    color: isSelected ? Theme.palette.text : Theme.palette.textMuted
                                    font.pixelSize: 11; font.family: Theme.typography.publicSans
                                }
                                MouseArea {
                                    id: ixChipArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        proposeDialog._selectedIx = modelData.name
                                        proposeDialog._argValues = ({})
                                        var accts = modelData.accounts || []
                                        // auto-auth signer accounts and pre-fill with default vault seed
                                        var defSeed = root.activeCreateKey
                                            ? (backend.computePda(root.activeCreateKey, "")["seed_hex"] || "")
                                            : ""
                                        proposeDialog._accountValues = accts.map(function(a) {
                                            return {isAuth: !!a.signer, seed: a.signer ? defSeed : ""}
                                        })
                                        pAcctCount.text = String(accts.length)
                                    }
                                }
                            }
                        }
                    }

                    // Fallback text field — shown when no IDL or IDL has no instructions
                    LogosTextField {
                        id: pIxName
                        visible: proposeDialog._parsedInstructions.length === 0
                        Layout.fillWidth: true
                        placeholderText: "e.g. transfer_tokens"
                    }
                }

                // Accounts section — shown when instruction has accounts
                ColumnLayout {
                    visible: proposeDialog._selectedIx !== "" &&
                             proposeDialog._selectedIxObj !== null &&
                             (proposeDialog._selectedIxObj.accounts || []).length > 0
                    Layout.fillWidth: true; spacing: 6

                    Text {
                        text: "Accounts"
                        color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                    }

                    Repeater {
                        model: proposeDialog._selectedIxObj ? (proposeDialog._selectedIxObj.accounts || []) : []
                        delegate: ColumnLayout {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true; spacing: 4

                            property bool _isAuth: {
                                var vals = proposeDialog._accountValues
                                return vals && vals[index] ? vals[index].isAuth : false
                            }

                            // ── Account row header ────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6

                                Text {
                                    text: "[" + index + "] " + (modelData.name || "")
                                    color: Theme.palette.text; font.pixelSize: 11; font.family: Theme.typography.publicSans
                                    Layout.fillWidth: true
                                }

                                // Badges
                                Repeater {
                                    model: [
                                        {label: "signer",   show: !!modelData.signer,   hi: true },
                                        {label: "writable", show: !!modelData.writable, hi: false},
                                        {label: "init",     show: !!modelData.init,     hi: false}
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        visible: modelData.show
                                        height: 16; radius: 8
                                        width: badgeText.implicitWidth + 10
                                        color: modelData.hi
                                            ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.18)
                                            : Theme.palette.backgroundSecondary
                                        border.color: modelData.hi ? Theme.palette.primary : Theme.palette.border
                                        Text {
                                            id: badgeText; anchors.centerIn: parent
                                            text: modelData.label
                                            color: modelData.hi ? Theme.palette.primary : Theme.palette.textMuted
                                            font.pixelSize: 8; font.family: Theme.typography.publicSans
                                        }
                                    }
                                }

                                // Auth toggle (only for signer accounts)
                                Rectangle {
                                    visible: !!modelData.signer
                                    height: 22; radius: Theme.spacing.radiusLarge
                                    width: authToggleText.implicitWidth + 12
                                    color: _isAuth
                                        ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.20)
                                        : Theme.palette.background
                                    border.color: _isAuth ? Theme.palette.primary : Theme.palette.border
                                    Text {
                                        id: authToggleText; anchors.centerIn: parent
                                        text: _isAuth ? "Vault auth" : "External signer"
                                        color: _isAuth ? Theme.palette.primary : Theme.palette.textMuted
                                        font.pixelSize: 9; font.family: Theme.typography.publicSans
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var vals = proposeDialog._accountValues.slice()
                                            if (!vals[index]) return
                                            vals[index] = {isAuth: !vals[index].isAuth, seed: vals[index].seed}
                                            proposeDialog._accountValues = vals
                                        }
                                    }
                                }
                            }

                            // init hint
                            Text {
                                visible: !!modelData.init
                                text: "This account may not exist yet — will be created by the program on execution."
                                color: Theme.palette.textMuted; font.pixelSize: 9; font.family: Theme.typography.publicSans
                                wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }

                            // ── Vault picker (shown when Vault auth is on) ────
                            ColumnLayout {
                                visible: _isAuth
                                Layout.fillWidth: true; spacing: 4
                                // Capture the outer account index as a named property so nested
                                // children don't need fragile parent chains.
                                property int acctIdx: index

                                property var vaultList: {
                                    var _epoch = proposeDialog._vaultEpoch  // reactive dep → re-evals on open + vault change
                                    var list = []
                                    var defRes = root.activeCreateKey
                                        ? backend.computePda(root.activeCreateKey, "") : {}
                                    var defSeed = defRes["seed_hex"] || ""
                                    var defAddr = backend.multisigState["vault_id"] || ""
                                    if (defSeed) list.push({label: "Default vault", pda: defAddr, seed_hex: defSeed})
                                    var stored = root.activeCreateKey
                                        ? backend.fieldHistory("pdas:" + root.activeCreateKey) : []
                                    for (var k = 0; k < stored.length; k++) {
                                        try { list.push(JSON.parse(stored[k])) } catch(e) {}
                                    }
                                    return list
                                }

                                Repeater {
                                    model: parent.vaultList  // parent = vault picker ColumnLayout
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        property int  _ai:  parent.acctIdx
                                        property bool _sel: {
                                            var vals = proposeDialog._accountValues
                                            return vals && vals[_ai]
                                                ? vals[_ai].seed === modelData.seed_hex : false
                                        }
                                        Layout.fillWidth: true
                                        height: vpRow.implicitHeight + 10
                                        radius: Theme.spacing.radiusSmall
                                        color: _sel
                                            ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.12)
                                            : Theme.palette.backgroundSecondary
                                        border.color: _sel ? Theme.palette.primary : Theme.palette.border
                                        border.width: _sel ? 2 : 1

                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                var vals = proposeDialog._accountValues.slice()
                                                if (!vals[parent._ai]) return
                                                vals[parent._ai] = {isAuth: true, seed: parent.modelData.seed_hex}
                                                proposeDialog._accountValues = vals
                                            }
                                        }

                                        RowLayout {
                                            id: vpRow
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                                            spacing: 8

                                            // Radio dot
                                            Rectangle {
                                                width: 16; height: 16; radius: 8
                                                color: "transparent"
                                                border.color: parent.parent._sel ? Theme.palette.primary : Theme.palette.border
                                                border.width: 2
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 8; height: 8; radius: 4
                                                    visible: parent.parent.parent._sel
                                                    color: Theme.palette.primary
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 1
                                                Text {
                                                    text: modelData.label || "Vault"
                                                    color: parent.parent.parent._sel ? Theme.palette.primary : Theme.palette.text
                                                    font.pixelSize: 11; font.bold: parent.parent.parent._sel
                                                    font.family: Theme.typography.publicSans
                                                }
                                                Text {
                                                    text: (modelData.pda || "").slice(0, 24) + "…"
                                                    color: Theme.palette.textMuted; font.pixelSize: 9; font.family: "monospace"
                                                }
                                            }
                                        }
                                    }
                                }

                                // Manual seed override
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 6
                                    // parent = vault picker ColumnLayout (has .acctIdx)
                                    Text { text: "or seed:"; color: Theme.palette.textMuted; font.pixelSize: 9; font.family: Theme.typography.publicSans }
                                    LogosTextField {
                                        Layout.fillWidth: true
                                        placeholderText: "64 hex chars (manual override)"
                                        font.family: "monospace"; font.pixelSize: 10
                                        text: {
                                            var vals = proposeDialog._accountValues
                                            var ai = parent.parent.acctIdx  // RowLayout → vault picker ColumnLayout
                                            return vals && vals[ai] ? vals[ai].seed : ""
                                        }
                                        onTextChanged: {
                                            var ai = parent.parent.acctIdx
                                            var vals = proposeDialog._accountValues.slice()
                                            if (!vals[ai]) return
                                            vals[ai] = {isAuth: vals[ai].isAuth, seed: text}
                                            proposeDialog._accountValues = vals
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Generated args form — shown when an instruction is selected
                ColumnLayout {
                    visible: proposeDialog._selectedIx !== ""
                    Layout.fillWidth: true; spacing: 8

                    Text {
                        visible: proposeDialog._selectedIxObj !== null && (proposeDialog._selectedIxObj.args || []).length === 0
                        text: "No arguments required"
                        color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                    }

                    Repeater {
                        model: proposeDialog._selectedIxObj ? (proposeDialog._selectedIxObj.args || []) : []
                        delegate: ColumnLayout {
                            Layout.fillWidth: true; spacing: 3
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    text: modelData.name || ""
                                    color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: typeof modelData.type === "string" ? modelData.type : JSON.stringify(modelData.type)
                                    color: Theme.palette.textPlaceholder; font.pixelSize: 10; font.family: "monospace"
                                }
                            }
                            LogosTextField {
                                Layout.fillWidth: true
                                placeholderText: typeof modelData.type === "string" ? modelData.type : JSON.stringify(modelData.type)
                                onTextChanged: {
                                    var vals = Object.assign({}, proposeDialog._argValues)
                                    vals[modelData.name] = text
                                    proposeDialog._argValues = vals
                                }
                            }
                        }
                    }
                }

                // Fallback raw args textarea — shown when no instruction is selected
                ColumnLayout {
                    visible: proposeDialog._selectedIx === ""
                    Layout.fillWidth: true; spacing: 4
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
                }

                Text {
                    visible: proposeDialog._encodeError !== ""
                    text: proposeDialog._encodeError
                    color: Theme.palette.error; font.pixelSize: 10; font.family: Theme.typography.publicSans
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            // ── Raw mode only: account count (IDL mode derives it from instruction accounts) ──
            ColumnLayout {
                visible: proposeDialog.proposeMode === 0
                Layout.fillWidth: true; spacing: 4
                Text { text: "Target account count"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
                LogosTextField { id: pAcctCount; Layout.fillWidth: true; placeholderText: "0" }
                Text {
                    visible: (parseInt(pAcctCount.text) || 0) === 0
                    text: "⚠ 0 means no target accounts — correct only for instructions that don't access any accounts (e.g. governance ops)."
                    color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        } // ColumnLayout proposeContent

        } // ScrollView

        footer: RowLayout {
            spacing: 8
            Item { Layout.fillWidth: true }
            LogosButton {
                text: "Cancel"
                onClicked: { proposeDialog.close(); proposeDialog.proposeMode = 0; proposeDialog._selectedIx = ""; proposeDialog._argValues = ({}); proposeDialog._accountValues = []; proposeDialog._selectedPresetLabel = "" }
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
                            var propIdx = String(parseInt(backend.multisigState["transaction_index"]) || 0)
                            var acctVals = proposeDialog._accountValues
                            var pdaSeeds = [], authIdx = []
                            for (var ai = 0; ai < acctVals.length; ai++) {
                                if (acctVals[ai] && acctVals[ai].isAuth) {
                                    authIdx.push(ai)
                                    if (acctVals[ai].seed) pdaSeeds.push(acctVals[ai].seed)
                                }
                            }
                            var acctCount = acctVals.length > 0 ? acctVals.length : (parseInt(pAcctCount.text) || 0)
                            backend.propose(pProposerId.text.trim(), pTargetProgram.text.trim(),
                                            instrWords, acctCount,
                                            pdaSeeds, authIdx, activeCreateKey, propIdx)
                            proposeDialog.close()
                            proposeDialog.proposeMode = 0
                            proposeDialog._encodePreview = ""
                            proposeDialog._selectedIx = ""
                            proposeDialog._argValues = ({})
                            proposeDialog._accountValues = []
                            proposeDialog._selectedPresetLabel = ""
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
        contentHeight: addMemberContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: addMemberDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: addMemberContent
            width: parent.width; spacing: 10

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: amProposerId; historyKey: "proposer_id"; placeholderText: "your account ID" }

            Text { text: "New member account ID (fresh keypair)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: amNewMember; historyKey: "member_id"; placeholderText: "fresh keypair account ID" }

        }

        footer: RowLayout {
            spacing: 8
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
                            var propIdx = String(parseInt(backend.multisigState["transaction_index"]) || 0)
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
        contentHeight: removeMemberContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: removeMemberDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: removeMemberContent
            width: parent.width; spacing: 10

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: rmProposerId; historyKey: "proposer_id"; placeholderText: "your account ID" }

            Text { text: "Member to remove (account ID)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: rmMember; historyKey: "member_id"; showCurrentMembers: true; placeholderText: "account ID to remove" }

        }

        footer: RowLayout {
            spacing: 8
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
                            var propIdx = String(parseInt(backend.multisigState["transaction_index"]) || 0)
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
        contentHeight: changeThresholdContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: changeThresholdDialog.title; color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: changeThresholdContent
            width: parent.width; spacing: 10

            Text {
                text: "Current threshold: " + threshold() + " of " + memberCount()
                color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                visible: Object.keys(backend.multisigState).length > 0
            }

            Text { text: "Proposer account ID"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            AccountField { id: ctProposerId; historyKey: "proposer_id"; placeholderText: "your account ID" }

            Text { text: "New threshold (M)"; color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans }
            LogosTextField { id: ctNewThreshold; Layout.fillWidth: true; placeholderText: "e.g. 3" }

        }

        footer: RowLayout {
            spacing: 8
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
                            var propIdx = String(parseInt(backend.multisigState["transaction_index"]) || 0)
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
        property var proposalData: null
        property var _extAccts: ({})   // slot index → user-typed account ID (non-PDA slots)
        onOpened: { _extAccts = {} }

        // Build the target_accounts array for execute from PDA seeds + user-entered external accounts.
        function buildTargetAccounts() {
            var pd = proposalData
            var count = pd ? (parseInt(pd["target_account_count"]) || 0) : 0
            var seeds = pd ? (pd["pda_seeds"] || []) : []
            var authIdx = pd ? (pd["authorized_indices"] || []) : []
            var result = []
            for (var i = 0; i < count; i++) {
                var pdaPos = -1
                for (var j = 0; j < authIdx.length; j++) {
                    if (parseInt(authIdx[j]) === i) { pdaPos = j; break }
                }
                if (pdaPos >= 0) {
                    var rawSeed = seeds[pdaPos]
                    var seedHex = Array.isArray(rawSeed) ? u8ArrayToHex(rawSeed) : (rawSeed || "")
                    result.push(backend.pdaFromSeed(seedHex))
                } else {
                    result.push(_extAccts[i] || "")
                }
            }
            return result
        }

        modal: true; anchors.centerIn: parent
        width: Math.min(480, parent.width - 48)
        contentHeight: accountPickerContent.implicitHeight
        background: Rectangle { color: Theme.palette.backgroundSecondary; border.color: Theme.palette.border; radius: Theme.spacing.radiusLarge }

        header: Item {
            implicitHeight: 52
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 20 }
                text: accountPicker.action + " Proposal #" + accountPicker.proposalIndex
                color: Theme.palette.text
                font.pixelSize: 15; font.bold: true; font.family: Theme.typography.publicSans
            }
        }

        ColumnLayout {
            id: accountPickerContent
            width: parent.width; spacing: 8

            // ── Target accounts (Execute only) ────────────────────────────
            ColumnLayout {
                visible: accountPicker.action === "Execute" &&
                         accountPicker.proposalData !== null &&
                         (parseInt(accountPicker.proposalData["target_account_count"]) || 0) > 0
                Layout.fillWidth: true; spacing: 4

                Text {
                    text: "Target accounts"
                    color: Theme.palette.textMuted; font.pixelSize: 11; font.family: Theme.typography.publicSans
                }

                Repeater {
                    model: accountPicker.proposalData ? (parseInt(accountPicker.proposalData["target_account_count"]) || 0) : 0
                    delegate: ColumnLayout {
                        Layout.fillWidth: true; spacing: 2
                        property int slotIdx: index
                        property var _seeds: accountPicker.proposalData ? (accountPicker.proposalData["pda_seeds"] || []) : []
                        property var _auth:  accountPicker.proposalData ? (accountPicker.proposalData["authorized_indices"] || []) : []
                        property int pdaPos: {
                            for (var j = 0; j < _auth.length; j++) {
                                if (parseInt(_auth[j]) === slotIdx) return j
                            }
                            return -1
                        }
                        property bool isPda: pdaPos >= 0
                        property string pdaId: {
                            if (!isPda) return ""
                            var s = _seeds[pdaPos]
                            return backend.pdaFromSeed(Array.isArray(s) ? u8ArrayToHex(s) : (s || ""))
                        }

                        Text {
                            text: "Account " + parent.slotIdx + (parent.isPda ? "  (PDA — auto)" : "  (external)")
                            color: Theme.palette.textMuted; font.pixelSize: 10; font.family: Theme.typography.publicSans
                        }
                        Text {
                            visible: parent.isPda
                            Layout.fillWidth: true
                            text: parent.pdaId || "(computing...)"
                            color: Theme.palette.textMuted
                            font.pixelSize: 11; font.family: Theme.typography.publicSans
                            elide: Text.ElideMiddle
                        }
                        LogosTextField {
                            visible: !parent.isPda
                            Layout.fillWidth: true
                            text: accountPicker._extAccts[parent.slotIdx] || ""
                            placeholderText: "account ID"
                            onTextChanged: {
                                var m = Object.assign({}, accountPicker._extAccts)
                                m[parent.slotIdx] = text.trim()
                                accountPicker._extAccts = m
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.palette.border; Layout.topMargin: 4; Layout.bottomMargin: 4 }
            }

            Text {
                text: "Select your account"
                color: Theme.palette.textMuted
                font.pixelSize: 11; font.family: Theme.typography.publicSans
            }

            Repeater {
                model: backend.walletAccounts
                delegate: Rectangle {
                    id: pickerRow
                    property string acctId: modelData["id"] || ""
                    property bool isPreconfigured: (modelData["path"] || "").indexOf("Preconfigured") >= 0
                    property bool isMember: {
                        var mems = membersHex()
                        var myKey = acctId.replace(/^(Public|Private)\//, "")
                        for (var i = 0; i < mems.length; i++) {
                            if (mems[i].replace(/^(Public|Private)\//, "") === myKey) return true
                        }
                        return false
                    }
                    property bool alreadyApproved: {
                        var pd = accountPicker.proposalData
                        if (!pd) return false
                        var appr = pd["approved"] || []
                        var myKey = acctId.replace(/^(Public|Private)\//, "")
                        for (var i = 0; i < appr.length; i++) {
                            var entry = appr[i]
                            var entryKey = typeof entry === "string"
                                ? entry.replace(/^(Public|Private)\//, "")
                                : u8ArrayToHex(entry)
                            if (entryKey === myKey) return true
                        }
                        return false
                    }
                    property bool canAct: {
                        if (isPreconfigured || !isMember) return false
                        if (accountPicker.action === "Approve" && alreadyApproved) return false
                        return true
                    }
                    property string statusLabel: {
                        if (isPreconfigured) return "Cannot sign"
                        if (!isMember)       return "Not a member"
                        if (accountPicker.action === "Approve" && alreadyApproved) return "Already approved"
                        return "Member"
                    }
                    property color statusColor: {
                        if (isPreconfigured || !isMember) return Theme.palette.textMuted
                        if (accountPicker.action === "Approve" && alreadyApproved) return Theme.palette.textMuted
                        return Theme.palette.success
                    }

                    Layout.fillWidth: true; height: 44; radius: Theme.spacing.radiusLarge
                    opacity: canAct ? 1.0 : 0.5
                    color: (pickArea.containsMouse && canAct)
                        ? Qt.rgba(Theme.palette.primary.r, Theme.palette.primary.g, Theme.palette.primary.b, 0.12)
                        : Theme.palette.background
                    border.color: (pickArea.containsMouse && canAct) ? Theme.palette.primary : Theme.palette.border

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
                            font.pixelSize: 11; elide: Text.ElideRight; Layout.preferredWidth: 90
                        }
                        Text {
                            text: pickerRow.statusLabel
                            color: pickerRow.statusColor
                            font.pixelSize: 10; font.family: Theme.typography.publicSans
                        }
                    }

                    MouseArea {
                        id: pickArea; anchors.fill: parent
                        cursorShape: pickerRow.canAct ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                        hoverEnabled: true
                        onClicked: {
                            if (!pickerRow.canAct || backend.busy) return
                            var acctId = modelData["id"] || ""
                            if      (accountPicker.action === "Approve") backend.approve(acctId, accountPicker.proposalIndex, activeCreateKey)
                            else if (accountPicker.action === "Reject")  backend.reject(acctId, accountPicker.proposalIndex, activeCreateKey)
                            else if (accountPicker.action === "Execute") {
                                var tc = accountPicker.proposalData ? (parseInt(accountPicker.proposalData["target_account_count"]) || 0) : 0
                                if (tc > 0)
                                    backend.executeWithAccounts(acctId, accountPicker.proposalIndex, activeCreateKey, accountPicker.buildTargetAccounts())
                                else
                                    backend.execute(acctId, accountPicker.proposalIndex, activeCreateKey)
                            }
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
            spacing: 8
            Item { Layout.fillWidth: true }
            LogosButton { text: "Cancel"; onClicked: accountPicker.close() }
        }
    }
}
