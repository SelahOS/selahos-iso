"""
SelahOS Device Bridge Scripting System
Complete macro and automation framework
"""

from .macro import (
    Macro,
    MacroStep,
    MacroExecutor,
    MacroLibrary,
    ActionType
)
from .builder import MacroBuilder, StandardMacros

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
