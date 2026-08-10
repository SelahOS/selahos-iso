"""
SelahOS Scripting System - Macro Engine
Defines macro structure and execution for device automation
"""

import json
import time
from enum import Enum
from typing import List, Dict, Callable, Any, Optional
from dataclasses import dataclass, asdict
import uuid
from datetime import datetime


class ActionType(Enum):
    """Macro action types"""
    NOTE_ON = "note_on"
    NOTE_OFF = "note_off"
    CC = "control_change"
    SYSEX = "sysex"
    PROGRAM_CHANGE = "program_change"
    DELAY = "delay"
    CONDITIONAL = "conditional"
    LOOP = "loop"
    DEVICE_INIT = "device_init"
    CUSTOM = "custom"


@dataclass
class MacroStep:
    """Single step in a macro sequence"""
    action: ActionType
    device_id: Optional[str] = None
    channel: int = 1
    data: Dict[str, Any] = None
    duration_ms: int = 0
    enabled: bool = True

    def to_dict(self) -> dict:
        return {
            'action': self.action.value,
            'device_id': self.device_id,
            'channel': self.channel,
            'data': self.data or {},
            'duration_ms': self.duration_ms,
            'enabled': self.enabled
        }

    @classmethod
    def from_dict(cls, d: dict) -> 'MacroStep':
        return cls(
            action=ActionType(d['action']),
            device_id=d.get('device_id'),
            channel=d.get('channel', 1),
            data=d.get('data', {}),
            duration_ms=d.get('duration_ms', 0),
            enabled=d.get('enabled', True)
        )


@dataclass
class Macro:
    """Complete macro definition"""
    id: str
    name: str
    description: str
    steps: List[MacroStep]
    created_at: str = None
    modified_at: str = None
    tags: List[str] = None
    enabled: bool = True

    def __post_init__(self):
        if not self.id:
            self.id = str(uuid.uuid4())
        if not self.created_at:
            self.created_at = datetime.now().isoformat()
        if not self.modified_at:
            self.modified_at = datetime.now().isoformat()
        if not self.tags:
            self.tags = []

    def add_step(self, step: MacroStep):
        """Add a step to the macro"""
        self.steps.append(step)
        self.modified_at = datetime.now().isoformat()

    def insert_step(self, index: int, step: MacroStep):
        """Insert a step at specific position"""
        self.steps.insert(index, step)
        self.modified_at = datetime.now().isoformat()

    def remove_step(self, index: int):
        """Remove step by index"""
        if 0 <= index < len(self.steps):
            self.steps.pop(index)
            self.modified_at = datetime.now().isoformat()

    def get_duration_ms(self) -> int:
        """Calculate total macro duration"""
        return sum(step.duration_ms for step in self.steps if step.enabled)

    def to_dict(self) -> dict:
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'steps': [step.to_dict() for step in self.steps],
            'created_at': self.created_at,
            'modified_at': self.modified_at,
            'tags': self.tags,
            'enabled': self.enabled
        }

    @classmethod
    def from_dict(cls, d: dict) -> 'Macro':
        steps = [MacroStep.from_dict(s) for s in d.get('steps', [])]
        return cls(
            id=d.get('id'),
            name=d.get('name', 'Untitled'),
            description=d.get('description', ''),
            steps=steps,
            created_at=d.get('created_at'),
            modified_at=d.get('modified_at'),
            tags=d.get('tags', []),
            enabled=d.get('enabled', True)
        )


class MacroExecutor:
    """Executes macros with callbacks for each action"""

    def __init__(self, midi_sender: Callable = None):
        """
        Initialize executor
        midi_sender: async callback(action, device_id, channel, data)
        """
        self.midi_sender = midi_sender or self._default_sender
        self.running = False
        self.paused = False

    async def execute(self, macro: Macro) -> Dict[str, Any]:
        """Execute a macro and return results"""
        if not macro.enabled:
            return {'status': 'skipped', 'reason': 'macro_disabled'}

        self.running = True
        results = {
            'macro_id': macro.id,
            'macro_name': macro.name,
            'start_time': datetime.now().isoformat(),
            'steps_executed': 0,
            'steps_failed': 0,
            'errors': []
        }

        try:
            for i, step in enumerate(macro.steps):
                if not self.running:
                    break
                if not step.enabled:
                    continue

                try:
                    # Delay if specified
                    if step.duration_ms > 0:
                        await self._async_sleep(step.duration_ms / 1000.0)

                    # Execute step
                    await self.midi_sender(
                        step.action.value,
                        step.device_id,
                        step.channel,
                        step.data
                    )
                    results['steps_executed'] += 1

                except Exception as e:
                    results['steps_failed'] += 1
                    results['errors'].append({
                        'step': i,
                        'error': str(e)
                    })

            results['end_time'] = datetime.now().isoformat()
            results['status'] = 'completed'

        except Exception as e:
            results['status'] = 'error'
            results['error'] = str(e)

        finally:
            self.running = False

        return results

    def stop(self):
        """Stop macro execution"""
        self.running = False

    async def _async_sleep(self, seconds: float):
        """Async sleep wrapper"""
        import asyncio
        await asyncio.sleep(seconds)

    async def _default_sender(self, action: str, device_id: str, channel: int, data: dict):
        """Default (no-op) MIDI sender"""
        pass


class MacroLibrary:
    """Manage collection of macros"""

    def __init__(self):
        self.macros: Dict[str, Macro] = {}

    def add_macro(self, macro: Macro):
        """Add macro to library"""
        self.macros[macro.id] = macro

    def remove_macro(self, macro_id: str) -> bool:
        """Remove macro by ID"""
        return self.macros.pop(macro_id, None) is not None

    def get_macro(self, macro_id: str) -> Optional[Macro]:
        """Get macro by ID"""
        return self.macros.get(macro_id)

    def list_macros(self, tag: str = None) -> List[Macro]:
        """List all macros, optionally filtered by tag"""
        if tag:
            return [m for m in self.macros.values() if tag in m.tags]
        return list(self.macros.values())

    def search_macros(self, query: str) -> List[Macro]:
        """Search macros by name/description"""
        q = query.lower()
        return [
            m for m in self.macros.values()
            if q in m.name.lower() or q in m.description.lower()
        ]

    def save_to_file(self, filepath: str):
        """Save library to JSON file"""
        data = {
            'version': '1.0',
            'macros': [m.to_dict() for m in self.macros.values()]
        }
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2)

    def load_from_file(self, filepath: str):
        """Load library from JSON file"""
        with open(filepath, 'r') as f:
            data = json.load(f)
        for macro_data in data.get('macros', []):
            macro = Macro.from_dict(macro_data)
            self.add_macro(macro)

    def export_macro(self, macro_id: str) -> str:
        """Export single macro as JSON"""
        macro = self.get_macro(macro_id)
        if not macro:
            return None
        return json.dumps(macro.to_dict(), indent=2)

    def import_macro(self, json_str: str) -> Macro:
        """Import macro from JSON"""
        data = json.loads(json_str)
        macro = Macro.from_dict(data)
        self.add_macro(macro)
        return macro
