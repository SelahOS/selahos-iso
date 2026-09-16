pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts

Pane {
    id: root
    width: 1280
    height: 720
    padding: 0
    property bool authenticating: false
    property string feedback: ""
    // SDDM injects these context objects; guarded during greeter teardown.
    // qmllint disable unqualified
    property var greeter: sddm
    property var sessions: sessionModel
    property var users: userModel
    property var keyboardState: keyboard
    // qmllint enable unqualified
    font.family: tokens.fontFamily
    font.pixelSize: tokens.bodyPx
    palette.window: tokens.background
    palette.base: tokens.field
    palette.button: tokens.field
    palette.text: tokens.text
    palette.windowText: tokens.text
    palette.buttonText: tokens.text
    palette.highlight: tokens.gold
    palette.highlightedText: tokens.background
    palette.placeholderText: tokens.muted
    Tokens {
        id: tokens
    }

    component SelahComboBox: ComboBox {
        id: combo
        background: Rectangle {
            color: tokens.field
            radius: tokens.radiusField
            border.width: combo.activeFocus ? 2 : 0
            border.color: tokens.goldLight
        }
        indicator: Text {
            x: combo.width - width - 16
            anchors.verticalCenter: parent.verticalCenter
            text: "⌄"
            color: tokens.goldLight
            font.pixelSize: 20
        }
    }

    background: Rectangle {
        color: tokens.background
        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 2
            color: tokens.gold
        }
    }

    function signIn() {
        if (authenticating || !greeter)
            return;
        if (username.text.trim() === "") {
            feedback = qsTr("Enter your username.");
            username.forceActiveFocus();
            return;
        }
        if (session.currentIndex < 0 || session.currentIndex >= session.count) {
            feedback = qsTr("No desktop session is available.");
            return;
        }
        feedback = "";
        authenticating = true;
        greeter.login(username.text.trim(), password.text, session.currentIndex);
        password.text = "";
    }

    ScrollView {
        id: scroll
        anchors.fill: parent
        Flickable {
            id: viewport
            contentWidth: width
            contentHeight: Math.max(height, form.implicitHeight + 64)
            clip: true

            ColumnLayout {
                id: form
                width: Math.min(400, viewport.width - 48)
                x: (viewport.width - width) / 2
                y: Math.max(32, (viewport.height - implicitHeight) / 2)
                spacing: tokens.spaceMd

                Image {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    source: "selah-mark.svg"
                    sourceSize: Qt.size(176, 176)
                    fillMode: Image.PreserveAspectFit
                    Accessible.ignored: true
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("SelahOS")
                    font.pixelSize: tokens.titlePx
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: tokens.spaceLg
                    text: qsTr("Pause. Reflect. Create.")
                    color: tokens.goldLight
                }
                Label {
                    text: qsTr("Username")
                    color: tokens.muted
                }
                TextField {
                    id: username
                    objectName: "username"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    text: root.users ? root.users.lastUser : ""
                    enabled: !root.authenticating
                    Accessible.name: qsTr("Username")
                    selectByMouse: true
                    onAccepted: password.forceActiveFocus()
                    background: Rectangle {
                        color: tokens.field
                        radius: tokens.radiusField
                        border.width: username.activeFocus ? 2 : 0
                        border.color: tokens.goldLight
                    }
                }
                Label {
                    text: qsTr("Password")
                    color: tokens.muted
                }
                TextField {
                    id: password
                    objectName: "password"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    enabled: !root.authenticating
                    echoMode: TextInput.Password
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    Accessible.name: qsTr("Password")
                    onAccepted: root.signIn()
                    background: Rectangle {
                        color: tokens.field
                        radius: tokens.radiusField
                        border.width: password.activeFocus ? 2 : 0
                        border.color: tokens.goldLight
                    }
                }
                Label {
                    Layout.fillWidth: true
                    visible: root.keyboardState ? root.keyboardState.capsLock : false
                    text: qsTr("Caps Lock is on")
                    color: tokens.goldLight
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    objectName: "feedback"
                    visible: text !== ""
                    text: root.feedback
                    color: tokens.error
                    wrapMode: Text.WordWrap
                    Accessible.role: Accessible.AlertMessage
                    Accessible.name: text
                }
                Button {
                    id: login
                    objectName: "login"
                    Layout.fillWidth: true
                    implicitHeight: 46
                    text: root.authenticating ? qsTr("Signing in…") : qsTr("Sign in")
                    enabled: !root.authenticating && session.count > 0
                    onClicked: root.signIn()
                    contentItem: Text {
                        text: login.text
                        font: login.font
                        color: tokens.background
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: login.down ? tokens.goldDark : tokens.goldLight
                        radius: tokens.radiusButton
                        opacity: login.enabled ? 1 : 0.6
                        border.width: login.activeFocus ? 2 : 0
                        border.color: tokens.text
                    }
                }
                Label {
                    text: qsTr("Desktop session")
                    color: tokens.muted
                    Layout.topMargin: tokens.spaceSm
                }
                SelahComboBox {
                    id: session
                    objectName: "session"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    model: root.sessions
                    textRole: "name"
                    enabled: !root.authenticating
                    Accessible.name: qsTr("Desktop session")
                    Component.onCompleted: currentIndex = count > 0 && root.sessions ? Math.max(0, Math.min(root.sessions.lastIndex, count - 1)) : -1
                }
                Label {
                    text: qsTr("Keyboard layout")
                    color: tokens.muted
                }
                SelahComboBox {
                    id: keyboardLayout
                    objectName: "keyboardLayout"
                    Layout.fillWidth: true
                    implicitHeight: 44
                    model: root.keyboardState ? root.keyboardState.layouts : []
                    textRole: "longName"
                    currentIndex: root.keyboardState ? root.keyboardState.currentLayout : -1
                    enabled: !root.authenticating
                    Accessible.name: qsTr("Keyboard layout")
                    onActivated: if (root.keyboardState)
                        root.keyboardState.currentLayout = currentIndex
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: tokens.spaceMd
                    Button {
                        text: qsTr("Restart")
                        implicitHeight: 44
                        enabled: root.greeter && root.greeter.canReboot && !root.authenticating
                        onClicked: {
                            powerDialog.action = "restart";
                            powerDialog.open();
                        }
                    }
                    Button {
                        text: qsTr("Shut down")
                        implicitHeight: 44
                        enabled: root.greeter && root.greeter.canPowerOff && !root.authenticating
                        onClicked: {
                            powerDialog.action = "shutdown";
                            powerDialog.open();
                        }
                    }
                }
            }
        }
    } // Flickable / ScrollView

    Dialog {
        id: powerDialog
        property string action: ""
        anchors.centerIn: parent
        width: Math.min(root.width - 32, 360)
        modal: true
        title: action === "restart" ? qsTr("Restart this computer?") : qsTr("Shut down this computer?")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (action === "restart")
                root.greeter.reboot();
            else
                root.greeter.powerOff();
        }
    }
    Connections {
        target: root.greeter
        function onLoginFailed() {
            root.authenticating = false;
            root.feedback = qsTr("Sign-in failed. Check your username, password and keyboard layout.");
            password.text = "";
            password.forceActiveFocus();
        }
        function onLoginSucceeded() {
            password.text = "";
            root.feedback = "";
        }
    }
    Component.onCompleted: {
        if (username.text === "")
            username.forceActiveFocus();
        else
            password.forceActiveFocus();
    }
}
