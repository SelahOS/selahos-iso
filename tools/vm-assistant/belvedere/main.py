#!/usr/bin/env python3
"""Belvedere — SelahOS VM Manager. Entry point."""
import sys

from PySide6.QtWidgets import QApplication

from main_window import MainWindow
from theme import STYLESHEET


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Belvedere")
    app.setStyleSheet(STYLESHEET)
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
