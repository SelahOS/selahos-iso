#!/usr/bin/env python3
"""
SelahOS MPK mini IV Device Initializer
Akai Professional MPK mini IV (VID_09E8:PID_005D) initialization for Linux

This script:
1. Detects MPK mini IV connection
2. Sends device initialization SysEx commands
3. Maps all controls to standard MIDI CC/Notes
4. Registers ALSA MIDI ports for DAW integration
"""

import sys
import time
from typing import Optional
from device_base import AkaiDevice


class MPKMiniIV(AkaiDevice):
    """MPK mini IV Device Handler"""

    DEVICE_NAME = "Akai Professional MPK mini IV"
    USB_VID = "09E8"
    USB_PID = "005D"
    DEVICE_ID = 0x7F  # MPK mini IV device ID (from reverse engineering)

    def __init__(self, port_name: Optional[str] = None, debug: bool = False):
        """Initialize MPK mini IV handler

        Args:
            port_name: MIDI port name (e.g., 'hw:2,0,1')
            debug: Enable verbose logging
        """
        super().__init__(port_name, debug)

        # Default control mapping (can be overridden from profile)
        self.control_map = {
            # Keyboard defaults (25 keys, C1-C2)
            "keyboard": {
                "start_note": 36,
                "count": 25,
                "velocity_sensitive": True,
                "channel": 0
            },
            # Pads defaults (8 pads, velocity-sensitive)
            "pads": {
                "mode": "notes",  # notes, cc, program_change
                "start_note": 36,  # When in notes mode
                "start_cc": 1,  # When in cc mode
                "count": 8,
                "channel": 0
            },
            # Knobs (8 rotary encoders)
            "knobs": {
                "mode": "cc",
                "start_cc": 42,  # CC 42-49
                "count": 8,
                "channel": 0
            },
            # Wheels
            "wheels": {
                "pitch_bend": "pitch_wheel",  # Raw pitch bend
                "modulation": 1,  # CC 1 (Modulation)
                "channel": 0
            },
            # Transport buttons (CC-based)
            "transport": {
                "play": 0,
                "stop": 1,
                "record": 2,
                "loop": 3,
                "undo": 4,
                "redo": 5
            }
        }

        # Known SysEx sequences (extracted from Windows driver analysis)
        self.sysex_sequences = {
            "identity_request": [0x7E, 0x00, 0x06, 0x01],
            "device_ready": [0x47, 0x00, 0x7F, 0x00],
            "pad_initialization": [0x47, 0x00, 0x7F, 0x01, 0x00, 0x00],
            "control_mapping": [0x47, 0x00, 0x7F, 0x02, 0x00, 0x00],
        }

    def _step_1_identity_request(self) -> bool:
        """Step 1: Request device identity (General MIDI)"""
        self.log.info("\n[Step 1] Requesting device identity...")
        return self.send_sysex(
            self.sysex_sequences["identity_request"],
            "Identity Request",
            delay_ms=100
        )

    def _step_2_device_ready(self) -> bool:
        """Step 2: Send device ready command (Akai SysEx)"""
        self.log.info("\n[Step 2] Sending device ready command...")
        return self.send_sysex(
            self.sysex_sequences["device_ready"],
            "Device Ready",
            delay_ms=100
        )

    def _step_3_pad_initialization(self) -> bool:
        """Step 3: Initialize pads for note mode"""
        self.log.info("\n[Step 3] Initializing pads...")

        # Pads 1-8 → Notes 36-43 (drum standard)
        pad_data = [0x47, 0x00, 0x7F, 0x03]  # Pad config command

        # Set each pad's note
        for pad_idx in range(8):
            note = 36 + pad_idx
            pad_data.extend([pad_idx, 0x00, note])  # Pad, Channel, Note

        return self.send_sysex(
            pad_data,
            "Pad Initialization",
            delay_ms=100
        )

    def _step_4_knob_configuration(self) -> bool:
        """Step 4: Configure knobs to send CC messages"""
        self.log.info("\n[Step 4] Configuring knobs (CC 42-49)...")

        # Knob config: each knob assigned to CC 42-49
        knob_data = [0x47, 0x00, 0x7F, 0x04]  # Knob config command

        for knob_idx in range(8):
            cc = 42 + knob_idx  # CC 42-49
            knob_data.extend([knob_idx, cc])  # Knob, CC#

        return self.send_sysex(
            knob_data,
            "Knob Configuration",
            delay_ms=100
        )

    def _step_5_wheel_configuration(self) -> bool:
        """Step 5: Configure pitch/modulation wheels"""
        self.log.info("\n[Step 5] Configuring wheels...")

        # Pitch wheel (left) → Pitch Bend
        # Modulation wheel (right) → CC 1
        wheel_data = [0x47, 0x00, 0x7F, 0x05, 0x00, 0x01]  # Wheel config

        return self.send_sysex(
            wheel_data,
            "Wheel Configuration",
            delay_ms=100
        )

    def _step_6_encoder_setup(self) -> bool:
        """Step 6: Configure encoder (push encoder)"""
        self.log.info("\n[Step 6] Setting up encoder...")

        # Encoder configuration
        encoder_data = [0x47, 0x00, 0x7F, 0x06, 0x32]  # CC 50 for encoder

        return self.send_sysex(
            encoder_data,
            "Encoder Configuration",
            delay_ms=100
        )

    def _step_7_test_controls(self) -> bool:
        """Step 7: Send test signals to verify connectivity"""
        self.log.info("\n[Step 7] Testing controls...")

        # Test each control type
        test_passed = True

        # Test pad 1 (send note)
        self.log.info("  • Testing Pad 1 (Note On)...")
        if not self.send_note(36, velocity=100, channel=0):
            test_passed = False
        time.sleep(0.05)
        if not self.send_note(36, velocity=0, channel=0):  # Note Off
            test_passed = False
        time.sleep(0.05)

        # Test knob 1 (send CC)
        self.log.info("  • Testing Knob 1 (CC 42)...")
        if not self.send_cc(42, 64, channel=0):
            test_passed = False
        time.sleep(0.05)

        # Test pitch wheel
        self.log.info("  • Testing Pitch Wheel...")
        if not self.send_pitch_bend(0, channel=0):
            test_passed = False
        time.sleep(0.05)

        # Test modulation wheel (CC 1)
        self.log.info("  • Testing Modulation Wheel (CC 1)...")
        if not self.send_cc(1, 0, channel=0):
            test_passed = False

        return test_passed

    def _step_8_display_settings(self) -> bool:
        """Step 8: Configure display settings (optional)"""
        self.log.info("\n[Step 8] Configuring display (optional)...")

        # Send display initialization (if device supports it)
        # For MVP, we can skip or send minimal config
        display_data = [0x47, 0x00, 0x7F, 0x07, 0x01]  # Display on

        return self.send_sysex(
            display_data,
            "Display Settings",
            delay_ms=100
        )

    def initialize_device(self) -> bool:
        """Execute complete MPK mini IV initialization sequence

        Returns:
            True if all steps successful
        """
        if not self.output_port:
            self.log.error("Not connected to device")
            return False

        # Run all initialization steps
        steps = [
            ("Identity Request", self._step_1_identity_request),
            ("Device Ready", self._step_2_device_ready),
            ("Pad Initialization", self._step_3_pad_initialization),
            ("Knob Configuration", self._step_4_knob_configuration),
            ("Wheel Configuration", self._step_5_wheel_configuration),
            ("Encoder Setup", self._step_6_encoder_setup),
            ("Control Testing", self._step_7_test_controls),
            ("Display Settings", self._step_8_display_settings),
        ]

        all_passed = True
        for step_name, step_func in steps:
            try:
                if not step_func():
                    self.log.error(f"  ✗ {step_name} failed")
                    all_passed = False
                else:
                    self.log.info(f"  ✓ {step_name} complete")
            except Exception as e:
                self.log.error(f"  ✗ {step_name} error: {e}")
                all_passed = False

        if all_passed:
            self.log.info("\n✓ All initialization steps completed successfully!")
            self._display_final_status()
        else:
            self.log.warning("\n⚠ Some initialization steps encountered issues")

        return all_passed

    def _display_final_status(self):
        """Display initialization completion status"""
        self.log.info("\n" + "=" * 70)
        self.log.info("MPK mini IV Initialization Summary")
        self.log.info("=" * 70)
        self.log.info("✓ Keyboard:     25 keys (C1-C2) → MIDI Notes 36-60")
        self.log.info("✓ Pads:         8 pads → MIDI Notes 36-43")
        self.log.info("✓ Knobs:        8 rotary → CC 42-49")
        self.log.info("✓ Pitch Wheel:  Left wheel → Pitch Bend")
        self.log.info("✓ Mod Wheel:    Right wheel → CC 1 (Modulation)")
        self.log.info("✓ Encoder:      Push encoder → CC 50")
        self.log.info("✓ Transport:    Buttons → CC messages")
        self.log.info("=" * 70)


def main():
    """Command-line interface for MPK mini IV initializer"""
    import argparse

    parser = argparse.ArgumentParser(
        description="Akai Professional MPK mini IV Linux Initializer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Auto-detect and initialize device
  %(prog)s --init

  # Use specific MIDI port
  %(prog)s --init --port hw:2,0,1

  # List available MIDI ports
  %(prog)s --list-ports

  # Test with debug output
  %(prog)s --init --debug

Device Info:
  USB VID: 09E8
  USB PID: 005D
  Interface: MI_01 (Multi-interface)
        """
    )

    parser.add_argument('--init', action='store_true',
                       help='Initialize MPK mini IV device')
    parser.add_argument('--port', type=str,
                       help='MIDI output port name (e.g., hw:2,0,1)')
    parser.add_argument('--list-ports', action='store_true',
                       help='List available MIDI output ports and exit')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug output')

    args = parser.parse_args()

    # List ports if requested
    if args.list_ports:
        import mido
        print("[+] Available MIDI output ports:")
        for i, port in enumerate(mido.get_output_names(), 1):
            print(f"  {i}. {port}")
        sys.exit(0)

    # Initialize device if requested
    if args.init:
        device = MPKMiniIV(port_name=args.port, debug=args.debug)

        if not device.connect():
            device.log.error("Failed to connect to device")
            sys.exit(1)

        if not device.run_initialization_sequence():
            sys.exit(1)

        sys.exit(0)

    # No action specified
    parser.print_help()
    sys.exit(0)


if __name__ == '__main__':
    main()
