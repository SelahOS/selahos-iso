"""
SelahOS Device Scripting System
Macro engine and automation framework
"""

from .core import (
    Macro,
    MacroStep,
    MacroExecutor,
    MacroLibrary,
    MacroBuilder,
    StandardMacros,
    ActionType
)

__all__ = [
    'Macro',
    'MacroStep',
    'MacroExecutor',
    'MacroLibrary',
    'MacroBuilder',
    'StandardMacros',
    'ActionType'
]

__version__ = '1.0.0'
