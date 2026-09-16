#!/usr/bin/env python3
"""Load actual login QML with fake SDDM objects; never authenticate or power off."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import sys
from pathlib import Path
from PyQt6.QtCore import (QObject, QAbstractListModel, QModelIndex, Qt, QUrl,
                         pyqtSignal, pyqtSlot, pyqtProperty, QMetaObject)
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickView
from PyQt6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
app = QGuiApplication([])

class Sessions(QAbstractListModel):
    countChanged = pyqtSignal()
    def __init__(self):
        super().__init__()
        self.names = ["Plasma (Wayland)", "Plasma (X11)"]
    def rowCount(self, parent=QModelIndex()): return 0 if parent.isValid() else len(self.names)
    def roleNames(self): return {257: b"name"}
    def data(self, index, role):
        return self.names[index.row()] if index.isValid() and role == 257 else None
    @pyqtProperty(int, constant=True)
    def lastIndex(self): return 1
    @pyqtProperty(int, notify=countChanged)
    def count(self): return len(self.names)
    def clear(self):
        self.beginResetModel(); self.names=[]; self.endResetModel(); self.countChanged.emit()

class Users(QObject):
    @pyqtProperty(str, constant=True)
    def lastUser(self): return "creator"

class Keyboard(QObject):
    changed = pyqtSignal()
    def __init__(self):
        super().__init__(); self._layout=0
    @pyqtProperty(bool, constant=True)
    def capsLock(self): return False
    @pyqtProperty("QVariantList", constant=True)
    def layouts(self):
        return [{"shortName":"us","longName":"English (US)"}, {"shortName":"gb","longName":"English (UK)"}]
    @pyqtProperty(int, notify=changed)
    def currentLayout(self): return self._layout
    @currentLayout.setter
    def currentLayout(self, value): self._layout=value; self.changed.emit()

class Greeter(QObject):
    loginFailed = pyqtSignal()
    loginSucceeded = pyqtSignal()
    def __init__(self): super().__init__(); self.calls=[]
    @pyqtProperty(bool, constant=True)
    def canReboot(self): return True
    @pyqtProperty(bool, constant=True)
    def canPowerOff(self): return True
    @pyqtSlot(str, str, int)
    def login(self, user, password, session): self.calls.append((user,password,session))
    @pyqtSlot()
    def reboot(self): raise AssertionError("No power action expected")
    @pyqtSlot()
    def powerOff(self): raise AssertionError("No power action expected")

greeter, sessions, users, keyboard = Greeter(), Sessions(), Users(), Keyboard()
view = QQuickView()
view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
for name, obj in [("sddm",greeter),("sessionModel",sessions),("userModel",users),("keyboard",keyboard)]:
    view.rootContext().setContextProperty(name,obj)
view.setSource(QUrl.fromLocalFile(str(ROOT/"login/selah-sddm/Main.qml")))
if view.status() == QQuickView.Status.Error:
    raise SystemExit("\n".join(e.toString() for e in view.errors()))
view.resize(1280,900); view.show(); QTest.qWait(100)
root = view.rootObject()
def item(name):
    result = root.findChild(QObject,name)
    assert result is not None, name
    return result
username, password, session = item("username"),item("password"),item("session")
assert session.property("currentIndex") == 1
if "--capture" in sys.argv:
    out=ROOT/".build/login-preview.png"; out.parent.mkdir(exist_ok=True)
    assert view.grabWindow().save(str(out))

username.setProperty("text","")
QMetaObject.invokeMethod(root,"signIn")
assert not greeter.calls and root.property("feedback")
username.setProperty("text","creator")
QMetaObject.invokeMethod(username,"forceActiveFocus")
QTest.keyClick(view, Qt.Key.Key_Return)
assert password.property("activeFocus")
password.setProperty("text","dummy-test-value")
QTest.keyClick(view, Qt.Key.Key_Return)
assert greeter.calls == [("creator","dummy-test-value",1)]
assert password.property("text") == ""
QMetaObject.invokeMethod(root,"signIn")
assert len(greeter.calls) == 1, "Duplicate submission"
greeter.loginFailed.emit(); QTest.qWait(20)
assert not root.property("authenticating") and root.property("feedback")
assert password.property("activeFocus")
session.setProperty("currentIndex",0)
password.setProperty("text","another-test-value")
QMetaObject.invokeMethod(root,"signIn")
assert greeter.calls[-1][2] == 0
greeter.loginSucceeded.emit()
assert password.property("text") == "" and root.property("feedback") == ""
greeter.loginFailed.emit()
sessions.clear(); QTest.qWait(20)
previous=len(greeter.calls)
QMetaObject.invokeMethod(root,"signIn")
assert len(greeter.calls) == previous and "session" in root.property("feedback")
assert not item("login").property("enabled")
for w,h in [(800,600),(640,480),(1920,1080)]:
    view.resize(w,h); QTest.qWait(20)
    assert root.width() == w and root.height() == h
print("PASS: QML load, remembered session, keyboard Enter, empty user, failed/successful auth, duplicate guard, empty sessions, resize.")
view.close()
