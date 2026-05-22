import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: Screen.width
    height: Screen.height
    color: "#0B0F1A"

    // ── Palette ─────────────────────────────────────────────
    readonly property color clrBg:        "#0B0F1A"
    readonly property color clrPanel:     "#131926"
    readonly property color clrBorder:    "#2A3042"
    readonly property color clrGold:      "#D6A85A"
    readonly property color clrTeal:      "#8EC3B8"
    readonly property color clrText:      "#EDE4D4"
    readonly property color clrSubtext:   "#9A8D7B"
    readonly property color clrDisabled:  "#5A5347"
    readonly property color clrError:     "#B85450"

    // ── SDDM connections ────────────────────────────────────
    property string statusMsg: ""

    Connections {
        target: sddm
        function onLoginFailed()    { statusMsg = "Incorrect username or password."; passField.clear(); passField.forceActiveFocus() }
        function onLoginSucceeded() { statusMsg = "" }
    }

    // ── Ambient background gradient ─────────────────────────
    // Subtle warm vignette so the plain dark doesn't feel cold
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0;  color: "#10141F" }
            GradientStop { position: 0.5;  color: "#0B0F1A" }
            GradientStop { position: 1.0;  color: "#08090E" }
        }
    }

    // ── Wordmark / brand area ───────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.22
        spacing: 6

        Text {
            text: "SelahOS"
            font.pixelSize: 38
            font.letterSpacing: 6
            font.weight: Font.Light
            color: root.clrText
            anchors.horizontalCenter: parent.horizontalCenter
        }
        // thin gold rule under the wordmark
        Rectangle {
            width: 64
            height: 1.5
            color: root.clrGold
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Login card ──────────────────────────────────────────
    Rectangle {
        id: card
        width: 360
        height: cardCol.implicitHeight + 56
        anchors.centerIn: parent
        color: root.clrPanel
        radius: 10
        border.color: root.clrBorder
        border.width: 1.5

        // faint inner top highlight
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#ffffff"
            opacity: 0.04
            radius: parent.radius
        }

        Column {
            id: cardCol
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                topMargin: 28
                leftMargin: 28
                rightMargin: 28
            }
            spacing: 14

            // username
            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: "Username"
                    font.pixelSize: 11
                    font.letterSpacing: 1.5
                    color: root.clrSubtext
                    font.uppercase: true
                }
                Rectangle {
                    width: parent.width
                    height: 38
                    color: root.clrBg
                    radius: 5
                    border.color: userField.activeFocus ? root.clrGold : root.clrBorder
                    border.width: userField.activeFocus ? 1.5 : 1

                    TextInput {
                        id: userField
                        anchors { fill: parent; margins: 10 }
                        verticalAlignment: Text.AlignVCenter
                        color: root.clrText
                        font.pixelSize: 14
                        text: userModel.lastUser
                        selectByMouse: true
                        clip: true
                        KeyNavigation.tab: passField
                        Keys.onReturnPressed: passField.forceActiveFocus()
                    }
                }
            }

            // password
            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: "Password"
                    font.pixelSize: 11
                    font.letterSpacing: 1.5
                    color: root.clrSubtext
                    font.uppercase: true
                }
                Rectangle {
                    width: parent.width
                    height: 38
                    color: root.clrBg
                    radius: 5
                    border.color: passField.activeFocus ? root.clrGold : root.clrBorder
                    border.width: passField.activeFocus ? 1.5 : 1

                    TextInput {
                        id: passField
                        anchors { fill: parent; margins: 10 }
                        verticalAlignment: Text.AlignVCenter
                        color: root.clrText
                        font.pixelSize: 14
                        echoMode: TextInput.Password
                        selectByMouse: true
                        clip: true
                        KeyNavigation.backtab: userField
                        Keys.onReturnPressed: doLogin()
                    }
                }
            }

            // session selector
            Row {
                width: parent.width
                spacing: 8
                Text {
                    text: "Session:"
                    font.pixelSize: 12
                    color: root.clrSubtext
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: parent.width - 68
                    height: 28
                    color: root.clrBg
                    radius: 4
                    border.color: root.clrBorder
                    border.width: 1

                    ComboBox {
                        id: sessionBox
                        anchors.fill: parent
                        model: sessionModel
                        textRole: "name"
                        currentIndex: sessionModel.lastIndex

                        background: Rectangle { color: "transparent" }
                        contentItem: Text {
                            leftPadding: 8
                            text: sessionBox.displayText
                            color: root.clrText
                            font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }
                        delegate: ItemDelegate {
                            width: sessionBox.width
                            contentItem: Text {
                                text: model.name
                                color: root.clrText
                                font.pixelSize: 12
                            }
                            background: Rectangle {
                                color: highlighted ? root.clrGold : root.clrPanel
                            }
                        }
                        popup: Popup {
                            y: sessionBox.height
                            width: sessionBox.width
                            padding: 1
                            background: Rectangle { color: root.clrPanel; border.color: root.clrBorder; radius: 4 }
                            contentItem: ListView {
                                implicitHeight: contentHeight
                                model: sessionBox.delegateModel
                                clip: true
                            }
                        }
                    }
                }
            }

            // status / error message
            Text {
                id: statusText
                width: parent.width
                text: root.statusMsg
                color: root.clrError
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.statusMsg !== ""
            }

            // login button
            Rectangle {
                id: loginBtn
                width: parent.width
                height: 40
                radius: 5
                color: loginMouse.pressed ? "#0D1020"
                     : loginMouse.containsMouse ? "#1E2840" : "#1A2035"
                border.color: loginMouse.containsMouse ? root.clrGold : root.clrBorder
                border.width: 1.5

                Behavior on color { ColorAnimation { duration: 100 } }
                Behavior on border.color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "Sign In"
                    font.pixelSize: 14
                    font.letterSpacing: 1
                    color: root.clrText
                }
                MouseArea {
                    id: loginMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: doLogin()
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    // ── System buttons (power / reboot) ─────────────────────
    Row {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 32
        }
        spacing: 24

        Repeater {
            model: [
                { label: "Suspend",  enabled: sddm.canSuspend,   action: function() { sddm.suspend() } },
                { label: "Restart",  enabled: sddm.canReboot,    action: function() { sddm.reboot()  } },
                { label: "Shut Down",enabled: sddm.canPowerOff,  action: function() { sddm.powerOff()} }
            ]

            delegate: Rectangle {
                width: 90
                height: 28
                radius: 4
                visible: modelData.enabled
                color: sysMouse.pressed ? "#131926"
                     : sysMouse.containsMouse ? "#1A2035" : "transparent"
                border.color: sysMouse.containsMouse ? root.clrBorder : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 80 } }

                Text {
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: 12
                    color: sysMouse.containsMouse ? root.clrSubtext : root.clrDisabled
                }
                MouseArea {
                    id: sysMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: modelData.action()
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    // ── Clock ────────────────────────────────────────────────
    Column {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 28
            rightMargin: 32
        }
        spacing: 2

        Text {
            id: clockTime
            anchors.right: parent.right
            font.pixelSize: 28
            font.weight: Font.Light
            color: root.clrText
        }
        Text {
            anchors.right: parent.right
            font.pixelSize: 12
            color: root.clrSubtext
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: clockTime.text = Qt.formatTime(new Date(), "hh:mm")
        }
    }

    // ── Keyboard focus on load ──────────────────────────────
    Component.onCompleted: {
        if (userField.text === "")
            userField.forceActiveFocus()
        else
            passField.forceActiveFocus()
    }

    function doLogin() {
        if (userField.text === "") {
            root.statusMsg = "Enter your username."
            userField.forceActiveFocus()
            return
        }
        sddm.login(userField.text, passField.text, sessionBox.currentIndex)
    }
}
