from __future__ import annotations

from PySide6.QtCore import Qt, QTimer
from PySide6.QtGui import QColor
from PySide6.QtWidgets import (
    QHBoxLayout, QHeaderView, QMainWindow, QMessageBox, QPushButton,
    QStatusBar, QTableWidget, QTableWidgetItem, QVBoxLayout, QWidget,
)

import vm_backend
from new_vm_wizard import NewVMWizard
from theme import state_color

COLUMNS = ["Name", "Guest OS", "State"]


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Belvedere — a vantage point over every SelahOS VM")
        self.resize(720, 420)

        central = QWidget()
        self.setCentralWidget(central)
        layout = QVBoxLayout(central)

        self.table = QTableWidget(0, len(COLUMNS))
        self.table.setHorizontalHeaderLabels(COLUMNS)
        self.table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.table.setSelectionBehavior(QTableWidget.SelectRows)
        self.table.setEditTriggers(QTableWidget.NoEditTriggers)
        layout.addWidget(self.table)

        button_row = QHBoxLayout()
        self.start_btn = QPushButton("Start")
        self.stop_btn = QPushButton("Stop")
        self.force_stop_btn = QPushButton("Force Stop")
        self.view_btn = QPushButton("View")
        self.new_btn = QPushButton("New VM…")
        self.refresh_btn = QPushButton("Refresh")
        for b in (self.start_btn, self.stop_btn, self.force_stop_btn, self.view_btn, self.new_btn, self.refresh_btn):
            button_row.addWidget(b)
        layout.addLayout(button_row)

        self.start_btn.clicked.connect(self._on_start)
        self.stop_btn.clicked.connect(self._on_stop)
        self.force_stop_btn.clicked.connect(self._on_force_stop)
        self.view_btn.clicked.connect(self._on_view)
        self.new_btn.clicked.connect(self._on_new_vm)
        self.refresh_btn.clicked.connect(self.refresh)

        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)

        self._vms: list[vm_backend.VMInfo] = []
        self.refresh()

        # Light polling so state changes (a VM finishing boot, etc.) show up
        # without the user needing to click Refresh — not a full event
        # subscription (out of scope for v1), just a periodic re-list.
        self._poll_timer = QTimer(self)
        self._poll_timer.timeout.connect(self.refresh)
        self._poll_timer.start(5000)

    def refresh(self):
        try:
            self._vms = vm_backend.list_vms()
            self.status_bar.clearMessage()
        except Exception as exc:
            self.status_bar.showMessage(f"Failed to list VMs: {exc}")
            return

        self.table.setRowCount(len(self._vms))
        for row, vm in enumerate(self._vms):
            self.table.setItem(row, 0, QTableWidgetItem(vm.name))
            self.table.setItem(row, 1, QTableWidgetItem(vm.os_kind))
            state_item = QTableWidgetItem(vm.state)
            state_item.setForeground(QColor(state_color(vm.state)))
            self.table.setItem(row, 2, state_item)

    def _selected_vm(self) -> vm_backend.VMInfo | None:
        rows = self.table.selectionModel().selectedRows()
        if not rows:
            return None
        return self._vms[rows[0].row()]

    def _on_start(self):
        vm = self._selected_vm()
        if not vm:
            return
        try:
            vm_backend.start_vm(vm.name)
            self.status_bar.showMessage(f"Starting {vm.name}…", 5000)
        except Exception as exc:
            QMessageBox.warning(self, "Start failed", str(exc))
        self.refresh()

    def _on_stop(self):
        vm = self._selected_vm()
        if not vm:
            return
        try:
            vm_backend.stop_vm(vm.name)
            self.status_bar.showMessage(f"Requesting shutdown for {vm.name}… (graceful — may take a while, or do nothing if the guest is unresponsive; use Force Stop if it doesn't come down)", 8000)
        except Exception as exc:
            QMessageBox.warning(self, "Stop failed", str(exc))
        self.refresh()

    def _on_force_stop(self):
        # Graceful shutdown (_on_stop) only sends an ACPI request — confirmed
        # 08-31 that it silently does nothing forever against a guest with no
        # OS/ACPI handling to respond (and can equally hang against a real
        # but wedged guest). This is the escalation path, so it's destructive
        # by design (equivalent to pulling power) — confirm before acting.
        vm = self._selected_vm()
        if not vm:
            return
        reply = QMessageBox.question(
            self, "Force stop?",
            f"Force-stop '{vm.name}'? This is equivalent to pulling the power — "
            f"any unsaved state in the guest will be lost. Use this only if a "
            f"graceful Stop isn't working.",
            QMessageBox.Yes | QMessageBox.No, QMessageBox.No,
        )
        if reply != QMessageBox.Yes:
            return
        try:
            vm_backend.stop_vm(vm.name, force=True)
            self.status_bar.showMessage(f"Force-stopped {vm.name}", 5000)
        except Exception as exc:
            QMessageBox.warning(self, "Force stop failed", str(exc))
        self.refresh()

    def _on_view(self):
        vm = self._selected_vm()
        if not vm:
            return
        try:
            vm_backend.launch_viewer(vm)
        except Exception as exc:
            QMessageBox.warning(self, "View failed", str(exc))

    def _on_new_vm(self):
        wizard = NewVMWizard(self)
        wizard.exec()
        self.refresh()
