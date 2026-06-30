"""
SelahOS Scripting - Macro Builder
Fluent API for creating macros programmatically
"""

from typing import Optional, List
from .macro import Macro, MacroStep, ActionType


class MacroBuilder:
    """Fluent builder for creating macros"""

    def __init__(self, name: str, description: str = ""):
        self.macro = Macro(
            id="",
            name=name,
            description=description,
            steps=[],
            tags=[]
        )

    def note_on(self, device_id: str, note: int, velocity: int = 100, channel: int = 1) -> 'MacroBuilder':
        """Add note on event"""
        step = MacroStep(
            action=ActionType.NOTE_ON,
            device_id=device_id,
            channel=channel,
            data={'note': note, 'velocity': velocity}
        )
        self.macro.add_step(step)
        return self

    def note_off(self, device_id: str, note: int, channel: int = 1) -> 'MacroBuilder':
        """Add note off event"""
        step = MacroStep(
            action=ActionType.NOTE_OFF,
            device_id=device_id,
            channel=channel,
            data={'note': note}
        )
        self.macro.add_step(step)
        return self

    def cc(self, device_id: str, cc: int, value: int, channel: int = 1) -> 'MacroBuilder':
        """Add control change event"""
        step = MacroStep(
            action=ActionType.CC,
            device_id=device_id,
            channel=channel,
            data={'cc': cc, 'value': value}
        )
        self.macro.add_step(step)
        return self

    def sysex(self, device_id: str, data: List[int], channel: int = 1) -> 'MacroBuilder':
        """Add system exclusive event"""
        step = MacroStep(
            action=ActionType.SYSEX,
            device_id=device_id,
            channel=channel,
            data={'bytes': data}
        )
        self.macro.add_step(step)
        return self

    def program_change(self, device_id: str, program: int, channel: int = 1) -> 'MacroBuilder':
        """Add program change event"""
        step = MacroStep(
            action=ActionType.PROGRAM_CHANGE,
            device_id=device_id,
            channel=channel,
            data={'program': program}
        )
        self.macro.add_step(step)
        return self

    def delay(self, milliseconds: int) -> 'MacroBuilder':
        """Add delay step"""
        step = MacroStep(
            action=ActionType.DELAY,
            duration_ms=milliseconds,
            data={'delay_ms': milliseconds}
        )
        self.macro.add_step(step)
        return self

    def delay_seconds(self, seconds: float) -> 'MacroBuilder':
        """Add delay in seconds"""
        return self.delay(int(seconds * 1000))

    def init_device(self, device_id: str) -> 'MacroBuilder':
        """Add device initialization"""
        step = MacroStep(
            action=ActionType.DEVICE_INIT,
            device_id=device_id,
            data={'device_id': device_id}
        )
        self.macro.add_step(step)
        return self

    def set_name(self, name: str) -> 'MacroBuilder':
        """Set macro name"""
        self.macro.name = name
        return self

    def set_description(self, description: str) -> 'MacroBuilder':
        """Set macro description"""
        self.macro.description = description
        return self

    def add_tag(self, tag: str) -> 'MacroBuilder':
        """Add tag to macro"""
        if tag not in self.macro.tags:
            self.macro.tags.append(tag)
        return self

    def add_tags(self, tags: List[str]) -> 'MacroBuilder':
        """Add multiple tags"""
        for tag in tags:
            self.add_tag(tag)
        return self

    def enable(self) -> 'MacroBuilder':
        """Enable macro"""
        self.macro.enabled = True
        return self

    def disable(self) -> 'MacroBuilder':
        """Disable macro"""
        self.macro.enabled = False
        return self

    def build(self) -> Macro:
        """Build and return the macro"""
        return self.macro


# Pre-built macro templates for common tasks

class StandardMacros:
    """Library of standard macro templates"""

    @staticmethod
    def reset_mpk_mini_iv() -> Macro:
        """Reset MPK mini IV to default state"""
        return (MacroBuilder("Reset MPK mini IV", "Reset controller to defaults")
                .init_device("mpk_mini_iv")
                .delay(100)
                .cc("mpk_mini_iv", 123, 0)  # All notes off
                .cc("mpk_mini_iv", 121, 0)  # Reset all controllers
                .delay(50)
                .add_tag("setup")
                .add_tag("mpk_mini_iv")
                .build())

    @staticmethod
    def reset_mpc_studio2() -> Macro:
        """Reset MPC Studio 2"""
        return (MacroBuilder("Reset MPC Studio 2", "Reset MPC to defaults")
                .init_device("mpc_studio2")
                .delay(100)
                .cc("mpc_studio2", 123, 0)
                .delay(50)
                .add_tag("setup")
                .add_tag("mpc_studio2")
                .build())

    @staticmethod
    def startup_sequence() -> Macro:
        """Full startup sequence for all devices"""
        builder = MacroBuilder(
            "Full Startup Sequence",
            "Initialize all controllers and set up MIDI routing"
        )
        builder.init_device("mpk_mini_iv")
        builder.delay(100)
        builder.init_device("mpc_studio2")
        builder.delay(100)
        builder.cc("mpk_mini_iv", 121, 0)
        builder.cc("mpc_studio2", 121, 0)
        builder.delay(200)
        builder.add_tag("setup")
        builder.add_tag("system")
        return builder.build()

    @staticmethod
    def drum_kit_selection() -> Macro:
        """Select drum kit on MPC"""
        return (MacroBuilder("Select Drum Kit", "Switch to drum kit on MPC")
                .cc("mpc_studio2", 0, 0)  # Bank select LSB
                .delay(10)
                .program_change("mpc_studio2", 0)  # Program 1
                .delay(100)
                .add_tag("workflow")
                .add_tag("mpc_studio2")
                .build())

    @staticmethod
    def metronome_click() -> Macro:
        """Metronome click sequence"""
        builder = MacroBuilder("Metronome Click", "Click sound pattern")
        for i in range(4):
            builder.note_on("mpk_mini_iv", 36 + i, 90)  # Kick notes
            builder.delay(250)
            builder.note_off("mpk_mini_iv", 36 + i)
            builder.delay(250)
        builder.add_tag("utility")
        return builder.build()
