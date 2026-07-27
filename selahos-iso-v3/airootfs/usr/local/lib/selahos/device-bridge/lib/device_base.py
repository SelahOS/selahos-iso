#!/usr/bin/env python3
"""
SelahOS Device Bridge - Base Class
Abstract base class for Akai Professional device initialization
Extends your existing MPC Studio 2 pattern
"""

import sys
import time
import json
import logging
from abc import ABC, abstractmethod
from typing import Optional, Dict, List, Tuple
from pathlib import Path

try:
    import mido
except ImportError:
    print("[-] python-mido not installed. Install with: pip install --break-system-packages python-mido")
    sys.exit(1)


class DeviceLogger:
    """Unified logging for device operations"""

    def __init__(self, device_name: str, debug: bool = False):
        self.device_name = device_name
        self.debug = debug
        self.log_level = logging.DEBUG if debug else logging.INFO
        self._setup_logger()

    def _setup_logger(self):
        """Configure Python logging"""
        logging.basicConfig(
            level=self.log_level,
            format=f'[%(asctime)s] [{self.device_name}] [%(levelname)s] %(message)s',
            datefmt='%H:%M:%S'
        )
        self.logger = logging.getLogger(self.device_name)

    def debug(self, msg: str):
        if self.debug:
            self.logger.debug(msg)

    def info(self, msg: str):
        self.logger.info(msg)

    def warning(self, msg: str):
        self.logger.warning(msg)

    def error(self, msg: str):
        self.logger.error(msg)


class SysExBuilder:
    """Construct MIDI SysEx messages"""

    # Standard manufacturer IDs
    AKAI_SYSEX_ID = 0x47
    UNIVERSAL_NON_REALTIME = 0x7E
    UNIVERSAL_REALTIME = 0x7F

    @staticmethod
    def identity_request() -> List[int]:
        """Build General MIDI Identity Request (standard)"""
        return [0x7E, 0x00, 0x06, 0x01]

    @staticmethod
    def akai_sysex(device_id: int, command: int, data: List[int] = None) -> List[int]:
        """Build Akai-specific SysEx message

        Format: F0 47 <channel> <device_id> <command> [data...] F7
        """
        msg = [0x47, 0x00, device_id, command]
        if data:
            msg.extend(data)
        return msg

    @staticmethod
    def add_sysex_wrapper(data: List[int]) -> bytes:
        """Wrap raw SysEx bytes with F0/F7"""
        return bytes([0xF0] + data + [0xF7])


class AkaiDevice(ABC):
    """Base class for Akai Professional MIDI devices"""

    # Override in subclass
    DEVICE_NAME: str = "Akai Device"
    USB_VID: str = "09E8"
    USB_PID: str = "XXXX"
    DEVICE_ID: int = 0x00  # Akai internal device ID

    # Standard Akai SysEx ID
    AKAI_MFR_ID: int = 0x47

    def __init__(self, port_name: Optional[str] = None, debug: bool = False):
        """Initialize device handler

        Args:
            port_name: MIDI output port name (e.g., 'hw:2,0,1')
            debug: Enable verbose logging
        """
        self.port_name = port_name
        self.debug = debug
        self.log = DeviceLogger(self.DEVICE_NAME, debug)
        self.output_port: Optional[mido.ports.BaseOutput] = None
        self.input_port: Optional[mido.ports.BaseInput] = None
        self.sysex = SysExBuilder()
        self.profile: Dict = {}
        self._load_profile()

    def _load_profile(self):
        """Load device control mapping from JSON profile"""
        profile_path = Path(__file__).parent / "profiles" / f"{self.DEVICE_NAME.lower().replace(' ', '_')}.json"

        if profile_path.exists():
            try:
                with open(profile_path, 'r') as f:
                    self.profile = json.load(f)
                self.log.debug(f"Loaded profile from {profile_path}")
            except Exception as e:
                self.log.warning(f"Failed to load profile: {e}")
        else:
            self.log.debug(f"No profile file found at {profile_path}")

    def find_device_port(self) -> Optional[str]:
        """Auto-detect device MIDI port

        Returns:
            Port name if found, None otherwise
        """
        self.log.info(f"Scanning for {self.DEVICE_NAME} MIDI ports...")

        # First, try exact device name match
        for port_name in mido.get_output_names():
            if self.DEVICE_NAME.lower() in port_name.lower():
                self.log.info(f"Found device port: {port_name}")
                return port_name

        # Fallback: look for Akai with USB VID
        for port_name in mido.get_output_names():
            if 'Akai' in port_name or self.USB_VID.lower() in port_name.lower():
                self.log.info(f"Found Akai device port: {port_name}")
                return port_name

        self.log.warning(f"No {self.DEVICE_NAME} port found")
        return None

    def connect(self, port_name: Optional[str] = None) -> bool:
        """Connect to device MIDI port

        Args:
            port_name: Specific port to use (or auto-detect)

        Returns:
            True if connection successful
        """
        target_port = port_name or self.port_name or self.find_device_port()

        if not target_port:
            self.log.error("Cannot connect: no port specified and auto-detect failed")
            return False

        try:
            self.output_port = mido.open_output(target_port)
            self.log.info(f"Connected to output port: {target_port}")

            # Try to open input port for feedback
            try:
                self.input_port = mido.open_input(target_port)
            except:
                self.log.debug("Could not open input port (not critical)")

            return True
        except Exception as e:
            self.log.error(f"Failed to connect to {target_port}: {e}")
            return False

    def send_sysex(self, data: List[int], label: str = "SysEx", delay_ms: float = 50) -> bool:
        """Send SysEx message

        Args:
            data: SysEx bytes (include 47 manufacturer ID)
            label: Description for logging
            delay_ms: Delay after sending

        Returns:
            True if sent successfully
        """
        if not self.output_port:
            self.log.error("Not connected to device")
            return False

        try:
            msg = mido.Message('sysex', data=data)
            self.output_port.send(msg)
            hex_preview = ' '.join(f'{b:02X}' for b in data[:16])
            if len(data) > 16:
                hex_preview += '...'
            self.log.debug(f"Sent {label}: {hex_preview}")
            time.sleep(delay_ms / 1000.0)
            return True
        except Exception as e:
            self.log.error(f"Failed to send SysEx: {e}")
            return False

    def send_cc(self, cc: int, value: int, channel: int = 0) -> bool:
        """Send Control Change message

        Args:
            cc: CC number (0-127)
            value: CC value (0-127)
            channel: MIDI channel (0-15)

        Returns:
            True if sent successfully
        """
        if not self.output_port:
            self.log.error("Not connected to device")
            return False

        try:
            msg = mido.Message('control_change', control=cc, value=value, channel=channel)
            self.output_port.send(msg)
            self.log.debug(f"Sent CC {cc} = {value} on channel {channel}")
            return True
        except Exception as e:
            self.log.error(f"Failed to send CC: {e}")
            return False

    def send_note(self, note: int, velocity: int = 127, channel: int = 0, is_on: bool = True) -> bool:
        """Send Note On/Off message

        Args:
            note: MIDI note number (0-127)
            velocity: Note velocity (0-127, 0=off for Note On)
            channel: MIDI channel (0-15)
            is_on: True for Note On, False for Note Off

        Returns:
            True if sent successfully
        """
        if not self.output_port:
            self.log.error("Not connected to device")
            return False

        try:
            msg_type = 'note_on' if is_on else 'note_off'
            msg = mido.Message(msg_type, note=note, velocity=velocity, channel=channel)
            self.output_port.send(msg)
            action = "Note On" if is_on else "Note Off"
            self.log.debug(f"Sent {action}: note={note}, velocity={velocity}, channel={channel}")
            return True
        except Exception as e:
            self.log.error(f"Failed to send note: {e}")
            return False

    def send_pitch_bend(self, value: int = 0, channel: int = 0) -> bool:
        """Send Pitch Bend message

        Args:
            value: Pitch bend value (-8192 to +8191, 0 = center)
            channel: MIDI channel (0-15)

        Returns:
            True if sent successfully
        """
        if not self.output_port:
            self.log.error("Not connected to device")
            return False

        try:
            msg = mido.Message('pitchwheel', pitch=value, channel=channel)
            self.output_port.send(msg)
            self.log.debug(f"Sent Pitch Bend: {value} on channel {channel}")
            return True
        except Exception as e:
            self.log.error(f"Failed to send pitch bend: {e}")
            return False

    @abstractmethod
    def initialize_device(self) -> bool:
        """Perform full device initialization

        Must be implemented by subclass

        Returns:
            True if initialization successful
        """
        pass

    def disconnect(self):
        """Cleanly disconnect from device"""
        if self.output_port:
            try:
                self.output_port.close()
                self.log.info("Disconnected from output port")
            except:
                pass

        if self.input_port:
            try:
                self.input_port.close()
                self.log.info("Disconnected from input port")
            except:
                pass

    def run_initialization_sequence(self) -> bool:
        """Complete initialization workflow

        Returns:
            True if fully successful
        """
        try:
            self.log.info("=" * 70)
            self.log.info(f"Starting {self.DEVICE_NAME} Initialization")
            self.log.info("=" * 70)

            if not self.initialize_device():
                self.log.error("Device initialization failed")
                return False

            self.log.info("=" * 70)
            self.log.info("Initialization complete")
            self.log.info("=" * 70)
            return True

        except Exception as e:
            self.log.error(f"Initialization sequence error: {e}")
            return False

        finally:
            self.disconnect()


class MockDevice(AkaiDevice):
    """Mock device for testing without hardware"""

    DEVICE_NAME = "Mock Akai Device"
    USB_VID = "09E8"
    USB_PID = "MOCK"

    def find_device_port(self) -> Optional[str]:
        """Return mock port name"""
        return "virtual_mock_device"

    def connect(self, port_name: Optional[str] = None) -> bool:
        """Mock connection (doesn't actually open port)"""
        self.log.info(f"Mock connected to port: {port_name or 'mock'}")
        return True

    def initialize_device(self) -> bool:
        """Mock initialization"""
        self.log.info("Mock device initialization sequence complete")
        return True
