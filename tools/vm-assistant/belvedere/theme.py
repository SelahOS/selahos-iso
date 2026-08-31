"""
Belvedere's visual theme — pulled directly from SelahOS's own established
color scheme (~/SelahOS-Dev/selahos-iso-v3/airootfs/usr/share/color-schemes/
SelahOS.colors), not invented separately, so the app matches the OS instead
of clashing with it as "just another grey Qt app."

The palette's own character — deep midnight-navy with a warm amber/gold
accent — already reads as "a lit cabin window against a dark mountain night"
without any extra design effort; that's the Belvedere brief (a lookout point
over a dark vista, warm light at the vantage point) more or less for free.
"""
from __future__ import annotations

# Straight from SelahOS.colors — do not drift from these without checking
# that file first; keeping Belvedere in lockstep with the OS theme is the
# point.
WINDOW_BG = "rgb(23, 28, 42)"
PANEL_BG = "rgb(29, 35, 51)"
BUTTON_BG = "rgb(42, 48, 66)"
BUTTON_BG_HOVER = "rgb(52, 60, 82)"
TEXT_NORMAL = "rgb(255, 255, 255)"
TEXT_INACTIVE = "rgb(140, 140, 140)"
ACCENT = "rgb(230, 194, 122)"        # DecorationFocus — the "cabin light"
ACCENT_HOVER = "rgb(214, 168, 90)"   # DecorationHover
SELECTION_BG = "rgb(214, 168, 90)"
SELECTION_BG_ALT = "rgb(189, 139, 60)"
SELECTION_FG = "rgb(255, 255, 255)"
LINK_BLUE = "rgb(126, 200, 227)"     # ForegroundLink — glacier/ice accent
POSITIVE = "rgb(129, 178, 154)"      # ForegroundPositive — used for "running"
NEGATIVE = "rgb(224, 122, 95)"       # ForegroundNegative — used for "crashed"
NEUTRAL = "rgb(246, 198, 81)"        # ForegroundNeutral — used for "shut off"

STATE_COLORS = {
    "running": POSITIVE,
    "shut off": TEXT_INACTIVE,
    "paused": NEUTRAL,
    "crashed": NEGATIVE,
    "blocked": NEGATIVE,
    "shutting down": NEUTRAL,
    "suspended": TEXT_INACTIVE,
}

STYLESHEET = f"""
QMainWindow, QDialog {{
    background-color: {WINDOW_BG};
}}

QWidget {{
    color: {TEXT_NORMAL};
    font-size: 13px;
}}

QTableWidget {{
    background-color: {WINDOW_BG};
    alternate-background-color: {PANEL_BG};
    gridline-color: {PANEL_BG};
    border: 1px solid {PANEL_BG};
    selection-background-color: {SELECTION_BG};
    selection-color: {SELECTION_FG};
}}

QHeaderView::section {{
    background-color: {PANEL_BG};
    color: {TEXT_NORMAL};
    padding: 6px;
    border: none;
    border-bottom: 2px solid {ACCENT};
    font-weight: 600;
}}

QTableWidget::item {{
    padding: 4px 8px;
}}

QTableWidget::item:selected {{
    background-color: {SELECTION_BG};
    color: {SELECTION_FG};
}}

QPushButton {{
    background-color: {BUTTON_BG};
    color: {TEXT_NORMAL};
    border: 1px solid {PANEL_BG};
    border-radius: 4px;
    padding: 6px 16px;
}}

QPushButton:hover {{
    background-color: {BUTTON_BG_HOVER};
    border: 1px solid {ACCENT_HOVER};
}}

QPushButton:pressed {{
    background-color: {SELECTION_BG_ALT};
}}

QPushButton:disabled {{
    color: {TEXT_INACTIVE};
    border: 1px solid {PANEL_BG};
}}

QPushButton:default {{
    border: 1px solid {ACCENT};
}}

QStatusBar {{
    background-color: {PANEL_BG};
    color: {TEXT_INACTIVE};
}}

QComboBox, QPlainTextEdit, QLineEdit {{
    background-color: {PANEL_BG};
    color: {TEXT_NORMAL};
    border: 1px solid {BUTTON_BG};
    border-radius: 3px;
    padding: 4px;
}}

QComboBox:hover, QLineEdit:hover {{
    border: 1px solid {ACCENT_HOVER};
}}

QLabel {{
    color: {TEXT_NORMAL};
}}

QScrollBar:vertical {{
    background: {WINDOW_BG};
    width: 12px;
}}
QScrollBar::handle:vertical {{
    background: {BUTTON_BG};
    border-radius: 5px;
    min-height: 24px;
}}
QScrollBar::handle:vertical:hover {{
    background: {ACCENT_HOVER};
}}
"""


def state_color(state: str) -> str:
    return STATE_COLORS.get(state, TEXT_NORMAL)
