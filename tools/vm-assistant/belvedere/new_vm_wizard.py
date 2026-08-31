"""New VM wizard — picks guest OS + version, runs the capability-check gate,
then streams the underlying script's output. No install logic lives here;
it all just calls vm_backend, which calls the same scripts the CLI uses."""
from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, QThread, Signal
from PySide6.QtWidgets import (
    QComboBox, QDialog, QDialogButtonBox, QFormLayout, QLabel,
    QPlainTextEdit, QPushButton, QVBoxLayout,
)

import vm_backend

MACOS_VERSIONS_CONF = vm_backend.SCRIPT_DIR / "macos-versions.conf"


def _macos_versions() -> list[str]:
    versions = []
    for line in MACOS_VERSIONS_CONF.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        versions.append(line.split(":")[0])
    return versions


class _BuildThread(QThread):
    output_line = Signal(str)
    finished_ok = Signal(bool)

    def __init__(self, kind: str, version: str):
        super().__init__()
        self.kind = kind
        self.version = version

    def run(self):
        try:
            proc = vm_backend.build_vm(self.kind, self.version, self.output_line.emit)
            for line in proc.stdout:
                self.output_line.emit(line.rstrip("\n"))
            proc.wait()
            self.finished_ok.emit(proc.returncode == 0)
        except Exception as exc:  # surface, don't swallow
            self.output_line.emit(f"ERROR: {exc}")
            self.finished_ok.emit(False)


class NewVMWizard(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("New VM")
        self.resize(520, 420)
        self._thread: _BuildThread | None = None

        layout = QVBoxLayout(self)

        form = QFormLayout()
        self.os_combo = QComboBox()
        self.os_combo.addItems(["macos", "windows"])
        self.os_combo.currentTextChanged.connect(self._on_os_changed)
        form.addRow("Guest OS:", self.os_combo)

        self.version_combo = QComboBox()
        form.addRow("Version:", self.version_combo)
        layout.addLayout(form)

        self.capability_label = QLabel("")
        self.capability_label.setWordWrap(True)
        layout.addWidget(self.capability_label)

        self.output_view = QPlainTextEdit()
        self.output_view.setReadOnly(True)
        self.output_view.setPlaceholderText("Build output will appear here…")
        layout.addWidget(self.output_view, stretch=1)

        self.start_button = QPushButton("Check && Build")
        self.start_button.clicked.connect(self._start_build)
        layout.addWidget(self.start_button)

        buttons = QDialogButtonBox(QDialogButtonBox.Close)
        buttons.rejected.connect(self.reject)
        buttons.accepted.connect(self.accept)
        layout.addWidget(buttons)

        self._on_os_changed(self.os_combo.currentText())

    def _on_os_changed(self, kind: str):
        self.version_combo.clear()
        if kind == "macos":
            self.version_combo.addItems(_macos_versions())
            self.version_combo.setEnabled(True)
        else:
            self.version_combo.addItem("10 (Windows 11 not available here — see CLI --version flag)")
            self.version_combo.setEnabled(False)

    def _start_build(self):
        kind = self.os_combo.currentText()
        version = self.version_combo.currentText().split()[0] if kind == "macos" else "10"

        # Same Phase-0 gate the CLI scripts run, surfaced in the UI instead
        # of a terminal exit code — per the plan's v1 feature scope.
        memory_mb = 4096
        required_flag = "avx2" if kind == "macos" and version in ("sonoma", "sequoia", "tahoe") else ""
        ok, message = vm_backend.run_capability_check(memory_mb, required_flag)
        self.capability_label.setText(message.strip())
        self.capability_label.setStyleSheet("color: #a33;" if not ok else "color: #2a2;")
        if not ok:
            return

        self.start_button.setEnabled(False)
        self.output_view.clear()
        self._thread = _BuildThread(kind, version)
        self._thread.output_line.connect(self.output_view.appendPlainText)
        self._thread.finished_ok.connect(self._on_build_finished)
        self._thread.start()

    def _on_build_finished(self, ok: bool):
        self.start_button.setEnabled(True)
        self.output_view.appendPlainText(
            "\n=== Build finished successfully ===" if ok else "\n=== Build FAILED — see output above ==="
        )
