import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

// LEZ Multisig — Basecamp UI module.
// Expects a `backend` context property of type LezMultisigBackend.

Rectangle {
    id: root
    width: 960
    height: 640
    color: colBg

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color colBg:       "#0f1117"
    readonly property color colSurface:  "#1a1d27"
    readonly property color colSurface2: "#22263a"
    readonly property color colBorder:   "#2d3148"
    readonly property color colPrimary:  "#7c6ef5"
    readonly property color colSuccess:  "#3ecf8e"
    readonly property color colWarning:  "#f5a623"
    readonly property color colError:    "#e05252"
    readonly property color colText:     "#e8e9f0"
    readonly property color colMuted:    "#6b7280"
    readonly property int   radius:      10

    // ── Toast notification ────────────────────────────────────────────────────
    Rectangle {
        id: toast
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 24 }
        width: toastLabel.implicitWidth + 32; height: 38
        radius: 19
        color: toastSuccess ? root.colSuccess : root.colError
        opacity: 0; z: 100
        property bool toastSuccess: true
        Label { id: toastLabel; anchors.centerIn: parent; color: "#fff"; font.pixelSize: 13 }
        SequentialAnimation {
            id: toastAnim
            NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 180 }
            PauseAnimation  { duration: 3000 }
            NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 350 }
        }
        function show(msg, ok) { toastSuccess = ok; toastLabel.text = msg; toastAnim.restart() }
    }

    Connections {
        target: backend
        function onOperationSuccess(op, txHash) { toast.show("✓ " + op + " — " + txHash.substring(0,14) + "…", true) }
        function onOperationError(op, err)       { toast.show("✗ " + err, false) }
    }

    // ── Setup sheet (shown when program ID is not configured) ─────────────────
    Rectangle {
        anchors.fill: parent
        color: root.colBg
        z: 50
        visible: backend.programIdHex === ""

        ColumnLayout {
            anchors.centerIn: parent
            width: 480
            spacing: 20

            Label {
                text: "LEZ Multisig Setup"
                color: root.colPrimary
                font { pixelSize: 22; bold: true }
                Layout.alignment: Qt.AlignHCenter
            }
            Label {
                text: "Configure your wallet and the deployed multisig program ID to get started."
                color: root.colMuted; font.pixelSize: 13
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            MsTextField {
                id: setupWalletPath
                placeholderText: "Wallet path (default: $NSSA_WALLET_HOME_DIR)"
                text: backend.walletPath
                Layout.fillWidth: true
            }
            MsTextField {
                id: setupProgramId
                placeholderText: "Program ID (64 hex chars)"
                Layout.fillWidth: true
            }
            MsButton {
                text: "Save & Continue"
                accent: true
                enabled: setupProgramId.text.length === 64
                Layout.fillWidth: true
                onClicked: {
                    backend.setWalletPath(setupWalletPath.text.trim())
                    backend.setProgramIdHex(setupProgramId.text.trim())
                }
            }
        }
    }

    // ── Main layout ───────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left sidebar: multisig list ───────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 210
            Layout.fillHeight: true
            color: root.colSurface
            border.color: root.colBorder

            ColumnLayout {
                anchors { fill: parent; margins: 0 }
                spacing: 0

                // Header
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    color: "transparent"
                    border.color: root.colBorder
                    border.width: 0
                    RowLayout {
                        anchors { fill: parent; leftMargin: 14; rightMargin: 10 }
                        Label {
                            text: "Multisigs"
                            color: root.colText
                            font { pixelSize: 14; bold: true }
                            Layout.fillWidth: true
                        }
                        // Settings gear
                        Rectangle {
                            width: 28; height: 28; radius: 6
                            color: settingsGearMa.containsMouse ? root.colSurface2 : "transparent"
                            Label { anchors.centerIn: parent; text: "⚙"; color: root.colMuted; font.pixelSize: 16 }
                            MouseArea {
                                id: settingsGearMa
                                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: settingsPopup.visible = !settingsPopup.visible
                            }
                        }
                    }
                    Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }; height: 1; color: root.colBorder }
                }

                // Multisig list
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: 210
                        spacing: 0

                        Repeater {
                            model: backend.multisigs
                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 58
                                color: modelData.create_key === backend.currentCreateKey
                                       ? root.colPrimary + "28" : "transparent"
                                border.color: modelData.create_key === backend.currentCreateKey
                                              ? root.colPrimary + "66" : "transparent"

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                                    spacing: 8

                                    // Colored dot / initials block
                                    Rectangle {
                                        width: 32; height: 32; radius: 6
                                        color: root.colPrimary + "44"
                                        Label {
                                            anchors.centerIn: parent
                                            text: modelData.threshold + "/" + modelData.member_count
                                            color: root.colPrimary; font { pixelSize: 11; bold: true }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Label {
                                            text: shortKey(modelData.create_key)
                                            color: root.colText; font.pixelSize: 12
                                            elide: Text.ElideRight; Layout.fillWidth: true
                                        }
                                        Label {
                                            text: modelData.member_count + " members · " + modelData.transaction_index + " proposals"
                                            color: root.colMuted; font.pixelSize: 10
                                        }
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.selectMultisig(modelData.create_key)
                                }
                                Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }; height: 1; color: root.colBorder + "88" }
                            }
                        }

                        // Empty state
                        Item {
                            visible: backend.multisigs.length === 0
                            Layout.fillWidth: true; height: 80
                            Label {
                                anchors.centerIn: parent
                                text: "No multisigs yet"
                                color: root.colMuted; font.pixelSize: 12
                            }
                        }
                    }
                }

                // Bottom actions
                Rectangle {
                    Layout.fillWidth: true
                    height: 1; color: root.colBorder
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.margins: 10
                    spacing: 6

                    MsButton {
                        text: "+ Load by key"
                        Layout.fillWidth: true
                        onClicked: loadDialog.visible = true
                    }
                    MsButton {
                        text: "+ Create new"
                        Layout.fillWidth: true
                        onClicked: { mainContent.currentIndex = 2 }
                    }
                }
            }
        }

        // ── Right content area ────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            StackLayout {
                id: mainContent
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: backend.currentCreateKey === "" ? 0 : 1

                // ── 0: Empty state ────────────────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        Label { text: "No multisig selected"; color: root.colMuted; font.pixelSize: 18; Layout.alignment: Qt.AlignHCenter }
                        Label { text: "Load an existing multisig or create a new one."; color: root.colMuted; font.pixelSize: 13; Layout.alignment: Qt.AlignHCenter }
                    }
                }

                // ── 1: Multisig detail ────────────────────────────────────────
                ColumnLayout {
                    spacing: 0

                    // Detail header
                    Rectangle {
                        Layout.fillWidth: true; height: 52
                        color: root.colSurface
                        border.color: root.colBorder
                        RowLayout {
                            anchors { fill: parent; leftMargin: 20; rightMargin: 16 }
                            spacing: 12
                            Label {
                                text: shortKey(backend.currentCreateKey)
                                color: root.colText; font { pixelSize: 15; bold: true }
                            }
                            Rectangle {
                                height: 22; width: thresholdLabel.implicitWidth + 16; radius: 4
                                color: root.colPrimary + "33"; border.color: root.colPrimary + "88"
                                Label { id: thresholdLabel; anchors.centerIn: parent
                                    text: (backend.currentMultisig.threshold || "?") + "-of-" + (backend.currentMultisig.member_count || "?")
                                    color: root.colPrimary; font { pixelSize: 11; bold: true } }
                            }
                            Item { Layout.fillWidth: true }
                            // Refresh button
                            Rectangle {
                                width: 30; height: 30; radius: 6
                                color: refreshMa.containsMouse ? root.colSurface2 : "transparent"
                                border.color: root.colBorder
                                Label { anchors.centerIn: parent; text: "↻"; color: root.colMuted; font.pixelSize: 16 }
                                MouseArea { id: refreshMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: { backend.refreshCurrentMultisig(); backend.refreshProposals() } }
                            }
                            // Remove from list
                            Rectangle {
                                width: 30; height: 30; radius: 6
                                color: removeMa.containsMouse ? root.colError + "22" : "transparent"
                                border.color: root.colBorder
                                Label { anchors.centerIn: parent; text: "✕"; color: root.colMuted; font.pixelSize: 14 }
                                MouseArea { id: removeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.removeLocalMultisig(backend.currentCreateKey) }
                            }
                        }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }; height: 1; color: root.colBorder }
                    }

                    // Tab bar
                    Rectangle {
                        Layout.fillWidth: true; height: 40
                        color: root.colSurface
                        RowLayout {
                            anchors { fill: parent; leftMargin: 12 }; spacing: 4
                            Repeater {
                                model: ["Proposals", "Members", "Config", "New Proposal"]
                                delegate: Rectangle {
                                    height: 32; width: tabLbl.implicitWidth + 20; radius: 6
                                    color: detailTabs.currentIndex === index ? root.colPrimary + "33" : "transparent"
                                    border.color: detailTabs.currentIndex === index ? root.colPrimary + "66" : "transparent"
                                    Label { id: tabLbl; anchors.centerIn: parent; text: modelData
                                        color: detailTabs.currentIndex === index ? root.colPrimary : root.colMuted
                                        font { pixelSize: 13; bold: detailTabs.currentIndex === index } }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: detailTabs.currentIndex = index }
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }; height: 1; color: root.colBorder }
                    }

                    StackLayout {
                        id: detailTabs
                        Layout.fillWidth: true; Layout.fillHeight: true
                        currentIndex: 0

                        // ── Tab 0: Proposals ──────────────────────────────────
                        Item {
                            ColumnLayout {
                                anchors { fill: parent; margins: 16 }; spacing: 10

                                // Filter row
                                RowLayout {
                                    spacing: 6
                                    property int filter: 0
                                    id: filterRow
                                    Repeater {
                                        model: ["All", "Active", "Executed", "Rejected"]
                                        delegate: Rectangle {
                                            height: 26; width: filterLbl.implicitWidth + 16; radius: 5
                                            color: filterRow.filter === index ? root.colPrimary : "transparent"
                                            border.color: filterRow.filter === index ? "transparent" : root.colBorder
                                            Label { id: filterLbl; anchors.centerIn: parent; text: modelData
                                                color: filterRow.filter === index ? "#fff" : root.colMuted; font.pixelSize: 12 }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: filterRow.filter = index }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        text: filteredProposals().length + " proposals"
                                        color: root.colMuted; font.pixelSize: 12
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                                    ColumnLayout {
                                        width: parent.width; spacing: 8

                                        Repeater {
                                            model: filteredProposals()
                                            delegate: Rectangle {
                                                Layout.fillWidth: true
                                                implicitHeight: proposalCol.implicitHeight + 20
                                                radius: root.radius; color: root.colSurface
                                                border.color: statusColor(modelData.status) + "55"

                                                ColumnLayout {
                                                    id: proposalCol
                                                    anchors { fill: parent; margins: 14 }; spacing: 8

                                                    RowLayout {
                                                        spacing: 8
                                                        Label {
                                                            text: "#" + modelData.index + "  " + proposalType(modelData)
                                                            color: root.colText; font { pixelSize: 13; bold: true }
                                                            Layout.fillWidth: true
                                                        }
                                                        // Status badge
                                                        Rectangle {
                                                            height: 20; width: statusLbl.implicitWidth + 12; radius: 4
                                                            color: statusColor(modelData.status) + "33"
                                                            Label { id: statusLbl; anchors.centerIn: parent; text: modelData.status
                                                                color: statusColor(modelData.status); font.pixelSize: 11 }
                                                        }
                                                    }

                                                    // Proposer
                                                    Label {
                                                        text: "Proposer: " + shortKey(modelData.proposer)
                                                        color: root.colMuted; font.pixelSize: 11
                                                    }

                                                    // Voting bar
                                                    ColumnLayout { spacing: 4; Layout.fillWidth: true
                                                        RowLayout {
                                                            Label { text: modelData.approvals + "/" + modelData.threshold + " approvals"
                                                                color: root.colText; font.pixelSize: 11 }
                                                            Item { Layout.fillWidth: true }
                                                            Label {
                                                                visible: modelData.rejections > 0
                                                                text: modelData.rejections + " rejection" + (modelData.rejections > 1 ? "s" : "")
                                                                color: root.colError; font.pixelSize: 11
                                                            }
                                                        }
                                                        Rectangle {
                                                            Layout.fillWidth: true; height: 5; radius: 3
                                                            color: root.colBorder
                                                            Rectangle {
                                                                width: parent.width * Math.min(modelData.approvals / modelData.threshold, 1.0)
                                                                height: parent.height; radius: parent.radius
                                                                color: modelData.approvals >= modelData.threshold ? root.colSuccess : root.colPrimary
                                                                Behavior on width { NumberAnimation { duration: 300 } }
                                                            }
                                                        }
                                                        // Dead proposal warning
                                                        Label {
                                                            visible: isDeadProposal(modelData)
                                                            text: "⚠ Cannot reach threshold"
                                                            color: root.colWarning; font.pixelSize: 11
                                                        }
                                                    }

                                                    // Action buttons (only for Active proposals)
                                                    RowLayout {
                                                        visible: modelData.status === "Active"
                                                        spacing: 8
                                                        MsButton {
                                                            text: "✓ Approve"
                                                            accent: true
                                                            enabled: !backend.busy
                                                            Layout.preferredWidth: 100
                                                            onClicked: backend.approve(modelData.index)
                                                        }
                                                        MsButton {
                                                            text: "✕ Reject"
                                                            destructive: true
                                                            enabled: !backend.busy
                                                            Layout.preferredWidth: 90
                                                            onClicked: backend.reject(modelData.index)
                                                        }
                                                        MsButton {
                                                            text: "⚡ Execute"
                                                            enabled: !backend.busy && modelData.approvals >= modelData.threshold
                                                            Layout.preferredWidth: 90
                                                            onClicked: backend.execute(modelData.index)
                                                        }
                                                        Item { Layout.fillWidth: true }
                                                    }
                                                }
                                            }
                                        }

                                        // Empty state
                                        Item {
                                            visible: backend.proposals.length === 0
                                            Layout.fillWidth: true; height: 80
                                            Label { anchors.centerIn: parent; text: "No proposals yet"; color: root.colMuted; font.pixelSize: 13 }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Tab 1: Members ────────────────────────────────────
                        Item {
                            ColumnLayout {
                                anchors { fill: parent; margins: 16 }; spacing: 12

                                RowLayout {
                                    Label { text: "Members"; color: root.colText; font { pixelSize: 14; bold: true }; Layout.fillWidth: true }
                                    Label {
                                        text: (backend.currentMultisig.member_count || 0) + " / 10"
                                        color: root.colMuted; font.pixelSize: 12
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true; Layout.preferredHeight: 260; clip: true
                                    ColumnLayout {
                                        width: parent.width; spacing: 6
                                        Repeater {
                                            model: backend.currentMultisig.members || []
                                            delegate: Rectangle {
                                                Layout.fillWidth: true; height: 44
                                                radius: 8; color: root.colSurface; border.color: root.colBorder
                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }; spacing: 8
                                                    Label { text: index + 1 + "."; color: root.colMuted; font.pixelSize: 12; Layout.preferredWidth: 20 }
                                                    Label { text: modelData; color: root.colText; font { pixelSize: 12; family: "monospace" }
                                                        elide: Text.ElideMiddle; Layout.fillWidth: true }
                                                    MsButton {
                                                        text: "Remove"; destructive: true; height: 28
                                                        Layout.preferredWidth: 70
                                                        enabled: !backend.busy
                                                        onClicked: backend.proposeRemoveMember(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

                                // Add member form
                                Label { text: "Propose Add Member"; color: root.colText; font { pixelSize: 13; bold: true } }
                                MsTextField { id: newMemberField; placeholderText: "New member public key (hex)"; Layout.fillWidth: true }
                                MsButton {
                                    text: "Propose Add Member"
                                    accent: true; Layout.fillWidth: true
                                    enabled: !backend.busy && newMemberField.text.length > 0
                                    onClicked: { backend.proposeAddMember(newMemberField.text.trim()); newMemberField.text = "" }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        // ── Tab 2: Config ─────────────────────────────────────
                        Item {
                            ColumnLayout {
                                anchors { fill: parent; margins: 16 }; spacing: 16

                                Label { text: "Configuration"; color: root.colText; font { pixelSize: 14; bold: true } }

                                // Current config summary
                                Rectangle {
                                    Layout.fillWidth: true; implicitHeight: configGrid.implicitHeight + 24
                                    radius: root.radius; color: root.colSurface; border.color: root.colBorder
                                    GridLayout {
                                        id: configGrid; anchors { fill: parent; margins: 14 }
                                        columns: 2; columnSpacing: 20; rowSpacing: 8
                                        Label { text: "Threshold";     color: root.colMuted; font.pixelSize: 12 }
                                        Label { text: (backend.currentMultisig.threshold || "—") + " of " + (backend.currentMultisig.member_count || "—") + " members required"
                                            color: root.colText; font.pixelSize: 13 }
                                        Label { text: "Members";       color: root.colMuted; font.pixelSize: 12 }
                                        Label { text: backend.currentMultisig.member_count || "—"; color: root.colText; font.pixelSize: 13 }
                                        Label { text: "Total proposals"; color: root.colMuted; font.pixelSize: 12 }
                                        Label { text: backend.currentMultisig.transaction_index || "0"; color: root.colText; font.pixelSize: 13 }
                                        Label { text: "State account"; color: root.colMuted; font.pixelSize: 12 }
                                        Label { text: backend.currentMultisig.multisig_state_id || "—"
                                            color: root.colText; font { pixelSize: 11; family: "monospace" }
                                            elide: Text.ElideMiddle; Layout.fillWidth: true }
                                    }
                                }

                                Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

                                // Change threshold form
                                Label { text: "Propose Change Threshold"; color: root.colText; font { pixelSize: 13; bold: true } }
                                RowLayout {
                                    spacing: 10
                                    MsTextField {
                                        id: newThresholdField; placeholderText: "New threshold (1 – member count)"
                                        Layout.preferredWidth: 200
                                        inputMethodHints: Qt.ImhDigitsOnly
                                    }
                                    MsButton {
                                        text: "Propose"
                                        accent: true
                                        enabled: !backend.busy && newThresholdField.text.length > 0
                                        onClicked: {
                                            backend.proposeChangeThreshold(parseInt(newThresholdField.text))
                                            newThresholdField.text = ""
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }

                        // ── Tab 3: New Proposal ───────────────────────────────
                        Item {
                            ColumnLayout {
                                anchors { fill: parent; margins: 16 }; spacing: 14

                                Label { text: "New Transaction Proposal"; color: root.colText; font { pixelSize: 14; bold: true } }
                                Label {
                                    text: "Propose execution of an instruction on another LEZ program via this multisig."
                                    color: root.colMuted; font.pixelSize: 12
                                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                                }

                                GridLayout {
                                    columns: 2; columnSpacing: 12; rowSpacing: 10; Layout.fillWidth: true

                                    Label { text: "PDA Seeds (comma-sep hex)"; color: root.colMuted; font.pixelSize: 12 }
                                    MsTextField { id: pdaSeedsField; placeholderText: "0xabcd…, 0xef01…"; Layout.fillWidth: true }

                                    Label { text: "Payload (JSON)"; color: root.colMuted; font.pixelSize: 12
                                        Layout.alignment: Qt.AlignTop }
                                    Rectangle {
                                        Layout.fillWidth: true; height: 120
                                        radius: 8; color: root.colBg; border.color: payloadInput.activeFocus ? root.colPrimary : root.colBorder; border.width: payloadInput.activeFocus ? 2 : 1
                                        ScrollView {
                                            anchors { fill: parent; margins: 8 }; clip: true
                                            TextArea {
                                                id: payloadInput
                                                placeholderText: '{"instruction": "Transfer", "amount": 100}'
                                                color: root.colText; font { pixelSize: 13; family: "monospace" }
                                                background: null
                                                wrapMode: TextArea.Wrap
                                            }
                                        }
                                    }
                                }

                                MsButton {
                                    text: "Submit Proposal"
                                    accent: true
                                    Layout.fillWidth: true
                                    enabled: !backend.busy && payloadInput.text.trim().length > 0
                                    onClicked: {
                                        var seeds = pdaSeedsField.text.trim().length > 0
                                            ? pdaSeedsField.text.split(",").map(function(s) { return s.trim() })
                                            : []
                                        backend.proposeTransaction(payloadInput.text.trim(), seeds)
                                        payloadInput.text = ""
                                        pdaSeedsField.text = ""
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }
                        }
                    }

                    // Busy + status bar
                    Rectangle {
                        Layout.fillWidth: true; height: 32
                        color: root.colSurface; border.color: root.colBorder
                        visible: backend.busy || backend.lastError !== ""
                        RowLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }; spacing: 8
                            BusyIndicator {
                                width: 18; height: 18; running: backend.busy; visible: backend.busy
                                palette.dark: root.colPrimary
                            }
                            Label {
                                text: backend.busy ? "Working…" : "Error: " + backend.lastError
                                color: backend.lastError !== "" ? root.colError : root.colMuted
                                font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── 2: Create multisig form ───────────────────────────────────
                Item {
                    ColumnLayout {
                        anchors { fill: parent; margins: 32 }; spacing: 16
                        Layout.maximumWidth: 520

                        Label { text: "Create New Multisig"; color: root.colText; font { pixelSize: 18; bold: true } }
                        Label { text: "Deploy a new M-of-N multisig on LEZ."; color: root.colMuted; font.pixelSize: 13 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

                        GridLayout {
                            columns: 2; columnSpacing: 12; rowSpacing: 10; Layout.fillWidth: true

                            Label { text: "Create Key (hex32)"; color: root.colMuted; font.pixelSize: 12 }
                            MsTextField { id: createKeyField; placeholderText: "32-byte hex (0x…) — unique ID for this multisig"; Layout.fillWidth: true }

                            Label { text: "Threshold (M)"; color: root.colMuted; font.pixelSize: 12 }
                            MsTextField { id: thresholdField; placeholderText: "e.g. 2"; inputMethodHints: Qt.ImhDigitsOnly; Layout.preferredWidth: 100 }

                            Label { text: "Members (one per line)"; color: root.colMuted; font.pixelSize: 12; Layout.alignment: Qt.AlignTop }
                            Rectangle {
                                Layout.fillWidth: true; height: 100
                                radius: 8; color: root.colBg; border.color: membersInput.activeFocus ? root.colPrimary : root.colBorder; border.width: membersInput.activeFocus ? 2 : 1
                                ScrollView {
                                    anchors { fill: parent; margins: 8 }; clip: true
                                    TextArea {
                                        id: membersInput
                                        placeholderText: "0xpubkey1\n0xpubkey2\n0xpubkey3"
                                        color: root.colText; font { pixelSize: 12; family: "monospace" }
                                        background: null; wrapMode: TextArea.Wrap
                                    }
                                }
                            }
                        }

                        RowLayout {
                            spacing: 10
                            MsButton {
                                text: "Cancel"
                                Layout.preferredWidth: 90
                                onClicked: mainContent.currentIndex = backend.currentCreateKey === "" ? 0 : 1
                            }
                            MsButton {
                                text: "Create Multisig"
                                accent: true; Layout.fillWidth: true
                                enabled: !backend.busy && createKeyField.text.length > 0
                                         && thresholdField.text.length > 0 && membersInput.text.trim().length > 0
                                onClicked: {
                                    var members = membersInput.text.trim().split("\n").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
                                    backend.createMultisig(parseInt(thresholdField.text), members, createKeyField.text.trim())
                                    mainContent.currentIndex = 1
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // ── Load multisig dialog ──────────────────────────────────────────────────
    Rectangle {
        id: loadDialog
        anchors.centerIn: parent
        width: 440; height: 160
        radius: root.radius; color: root.colSurface
        border.color: root.colBorder
        visible: false; z: 40
        layer.enabled: true
        layer.effect: null

        ColumnLayout {
            anchors { fill: parent; margins: 20 }; spacing: 12
            Label { text: "Load Multisig by Create Key"; color: root.colText; font { pixelSize: 14; bold: true } }
            MsTextField { id: loadKeyField; placeholderText: "Create key (32-byte hex, 0x…)"; Layout.fillWidth: true }
            RowLayout {
                spacing: 8
                MsButton { text: "Cancel"; Layout.preferredWidth: 80; onClicked: { loadDialog.visible = false; loadKeyField.text = "" } }
                MsButton {
                    text: "Load"; accent: true; Layout.fillWidth: true
                    enabled: loadKeyField.text.length > 0
                    onClicked: {
                        backend.loadMultisig(loadKeyField.text.trim())
                        backend.selectMultisig(loadKeyField.text.trim())
                        loadKeyField.text = ""
                        loadDialog.visible = false
                    }
                }
            }
        }
    }

    // ── Settings popup ────────────────────────────────────────────────────────
    Rectangle {
        id: settingsPopup
        x: 12; y: 52
        width: 340; implicitHeight: settingsCol.implicitHeight + 24
        radius: root.radius; color: root.colSurface
        border.color: root.colBorder
        visible: false; z: 40

        ColumnLayout {
            id: settingsCol
            anchors { fill: parent; margins: 14 }; spacing: 10
            Label { text: "Settings"; color: root.colText; font { pixelSize: 13; bold: true } }
            Label { text: "Wallet Path"; color: root.colMuted; font.pixelSize: 11 }
            MsTextField { id: settingsWalletPath; text: backend.walletPath; Layout.fillWidth: true }
            Label { text: "Program ID (hex)"; color: root.colMuted; font.pixelSize: 11 }
            MsTextField { id: settingsProgramId; text: backend.programIdHex; Layout.fillWidth: true }
            MsButton {
                text: "Save"; accent: true; Layout.fillWidth: true
                onClicked: {
                    backend.setWalletPath(settingsWalletPath.text.trim())
                    backend.setProgramIdHex(settingsProgramId.text.trim())
                    settingsPopup.visible = false
                }
            }
        }
    }

    // ── Helper functions ──────────────────────────────────────────────────────

    function shortKey(key) {
        if (!key || key.length < 12) return key || "—"
        return key.substring(0, 8) + "…" + key.substring(key.length - 6)
    }

    function statusColor(status) {
        switch (status) {
            case "Active":    return root.colPrimary
            case "Executed":  return root.colSuccess
            case "Rejected":  return root.colError
            case "Cancelled": return root.colMuted
            default:          return root.colMuted
        }
    }

    function proposalType(p) {
        if (p.config_action) {
            if (p.config_action.AddMember)       return "Add Member"
            if (p.config_action.RemoveMember)    return "Remove Member"
            if (p.config_action.ChangeThreshold) return "Change Threshold"
        }
        return "Transaction"
    }

    function isDeadProposal(p) {
        var memberCount = backend.currentMultisig.member_count || 0
        var threshold   = p.threshold || 1
        return p.status === "Active" && p.rejections >= (memberCount - threshold + 1)
    }

    function filteredProposals() {
        var filter = filterRow.filter
        if (filter === 0) return backend.proposals
        var status = ["", "Active", "Executed", "Rejected"][filter]
        return backend.proposals.filter(function(p) { return p.status === status })
    }

    // ── Inline shared components ──────────────────────────────────────────────

    component MsTextField: TextField {
        Layout.fillWidth: true
        color: root.colText
        placeholderTextColor: root.colMuted
        font.pixelSize: 13
        leftPadding: 12; rightPadding: 12
        background: Rectangle {
            radius: 8; color: root.colBg
            border.color: parent.activeFocus ? root.colPrimary : root.colBorder
            border.width: parent.activeFocus ? 2 : 1
        }
    }

    component MsButton: Rectangle {
        id: btn
        property string text: ""
        property bool accent: false
        property bool destructive: false
        property bool enabled: true
        signal clicked
        implicitHeight: 36
        radius: 8
        color: !btn.enabled   ? root.colBorder
             : btn.destructive ? (btnMa.containsMouse ? root.colError : root.colError + "cc")
             : btn.accent      ? (btnMa.containsMouse ? Qt.lighter(root.colPrimary, 1.1) : root.colPrimary)
                              : (btnMa.containsMouse ? root.colSurface2 : root.colSurface)
        border.color: btn.accent || btn.destructive ? "transparent" : root.colBorder
        Behavior on color { ColorAnimation { duration: 80 } }
        Label {
            anchors.centerIn: parent
            text: btn.text
            color: btn.enabled ? "#fff" : root.colMuted
            font { pixelSize: 13; bold: btn.accent }
        }
        MouseArea {
            id: btnMa
            anchors.fill: parent; hoverEnabled: true
            enabled: btn.enabled
            cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (btn.enabled) btn.clicked()
        }
    }
}
