import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root
    width: 1920; height: 1080
    color: "#171C2A"

    // Cosmic background gradient
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0D1020" }
            GradientStop { position: 0.5; color: "#171C2A" }
            GradientStop { position: 1.0; color: "#0D1020" }
        }
    }

    // Subtle gold glow at top
    Rectangle {
        width: 600; height: 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 0
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: "#E6C27A" }
            GradientStop { position: 1.0; color: "transparent" }
        }
        opacity: 0.6
    }

    // Clock (top-right)
    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 40
        spacing: 4

        Text {
            id: timeLabel
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: "Inter"
            font.pixelSize: 48
            font.weight: Font.Light
            color: "#FFFFFF"
            opacity: 0.9

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: timeLabel.text = Qt.formatTime(new Date(), "hh:mm")
            }
            Component.onCompleted: text = Qt.formatTime(new Date(), "hh:mm")
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            font.family: "Inter"
            font.pixelSize: 16
            color: "#FFFFFF"
            opacity: 0.45
            text: Qt.formatDate(new Date(), "dddd, MMMM d")
        }
    }

    // Center login card
    Rectangle {
        id: loginCard
        width: 420
        height: loginColumn.implicitHeight + 80
        anchors.centerIn: parent
        color: "transparent"

        ColumnLayout {
            id: loginColumn
            anchors.centerIn: parent
            width: 360
            spacing: 0

            // Logo glyph
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "◈"
                font.family: "Inter"
                font.pixelSize: 64
                font.weight: Font.Thin
                color: "#D6A85A"
            }

            // SelahOS name
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 8
                text: "SelahOS™"
                font.family: "Inter"
                font.pixelSize: 24
                font.weight: Font.Light
                color: "#FFFFFF"
                opacity: 0.95
            }

            // Tagline
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                text: "Pause. Reflect. Create."
                font.family: "Inter"
                font.pixelSize: 13
                color: "#D6A85A"
                opacity: 0.8
                font.italic: true
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 28
                Layout.bottomMargin: 28
                height: 1
                color: "#E6C27A"
                opacity: 0.15
            }

            // Username field
            TextField {
                id: usernameField
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                placeholderText: "Username"
                font.family: "Inter"
                font.pixelSize: 14
                color: "#FFFFFF"
                background: Rectangle {
                    color: "#2A3042"
                    radius: 10
                    border.color: usernameField.activeFocus ? "#D6A85A" : "#E6C27A22"
                    border.width: 1
                }
                leftPadding: 16
                text: userModel.lastUser
            }

            Item { Layout.preferredHeight: 12 }

            // Password field
            TextField {
                id: passwordField
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                placeholderText: "Password"
                echoMode: TextInput.Password
                font.family: "Inter"
                font.pixelSize: 14
                color: "#FFFFFF"
                background: Rectangle {
                    color: "#2A3042"
                    radius: 10
                    border.color: passwordField.activeFocus ? "#D6A85A" : "#E6C27A22"
                    border.width: 1
                }
                leftPadding: 16
                onAccepted: signIn()
            }

            Item { Layout.preferredHeight: 20 }

            // Sign in button
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 12

                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#E6C27A" }
                    GradientStop { position: 0.5; color: "#D6A85A" }
                    GradientStop { position: 1.0; color: "#BD8B3C" }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Sign In"
                    font.family: "Inter"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#171C2A"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: signIn()
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // Error message
            Text {
                id: errorMsg
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 12
                visible: false
                text: ""
                font.family: "Inter"
                font.pixelSize: 13
                color: "#E07A5F"
            }
        }
    }

    // Session selector (bottom-left)
    ComboBox {
        id: sessionSelect
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 40
        width: 200; height: 36
        model: sessionModel
        textRole: "name"
        font.family: "Inter"
        font.pixelSize: 13
        background: Rectangle {
            color: "#2A3042"
            radius: 8
            border.color: "#E6C27A22"
        }
        contentItem: Text {
            leftPadding: 12
            text: sessionSelect.displayText
            color: "#FFFFFF"
            opacity: 0.7
            font: sessionSelect.font
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Bottom copyright
    Text {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 20
        text: "© 2026 Selah Technologies LLC  ·  selahos.io"
        font.family: "Inter"
        font.pixelSize: 12
        color: "#FFFFFF"
        opacity: 0.2
    }

    function signIn() {
        if (usernameField.text === "") {
            errorMsg.text = "Please enter a username."
            errorMsg.visible = true
            return
        }
        errorMsg.visible = false
        sddm.login(usernameField.text, passwordField.text, sessionSelect.currentIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            errorMsg.text = "Incorrect username or password."
            errorMsg.visible = true
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (usernameField.text !== "")
            passwordField.forceActiveFocus()
        else
            usernameField.forceActiveFocus()
    }
}
