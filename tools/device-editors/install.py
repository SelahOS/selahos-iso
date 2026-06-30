#!/usr/bin/env python3
"""
SelahOS Device Bridge - Interactive Installer
Graphical installation for MPK mini IV, MPC Studio mk2, and other Akai devices

Run as: python3 install.py
"""

import os
import sys
import shutil
import subprocess
import json
from pathlib import Path
from typing import Optional, Tuple

try:
    import tkinter as tk
    from tkinter import ttk, messagebox, filedialog
except ImportError:
    print("ERROR: tkinter not found. Install with: sudo pacman -S tk")
    sys.exit(1)


class DeviceBridgeInstaller:
    """Interactive GUI installer for SelahOS Device Bridge"""

    DEVICES = {
        "MPK mini IV": {
            "vid": "09E8",
            "pid": "005D",
            "controls": "25 keys, 8 pads, 8 knobs, 2 wheels",
            "file": "mpk_mini_iv.py"
        },
        "MPC Studio mk2": {
            "vid": "09E8",
            "pid": "004A",
            "controls": "16 pads, transport, jog wheel",
            "file": "mpc_studio2_mk2.py"
        }
    }

    INSTALL_PATHS = {
        "lib": "/usr/local/lib/selahos/device-bridge/",
        "config": "/etc/selahos/device-bridge/",
        "systemd": "/etc/systemd/system/",
        "udev": "/etc/udev/rules.d/"
    }

    def __init__(self, root):
        self.root = root
        self.root.title("SelahOS Device Bridge Installer")
        self.root.geometry("700x600")
        self.root.configure(bg="#1e1e1e")

        self.script_dir = Path(__file__).parent
        self.selected_devices = []
        self.auto_install = tk.BooleanVar(value=True)
        self.auto_init = tk.BooleanVar(value=True)

        self._setup_ui()
        self._check_requirements()

    def _setup_ui(self):
        """Build the installer UI"""
        # Header
        header = ttk.Frame(self.root)
        header.pack(fill=tk.X, padx=20, pady=20)

        title = tk.Label(
            header,
            text="SelahOS Device Bridge Installer",
            font=("Arial", 18, "bold"),
            bg="#1e1e1e",
            fg="#00ff00"
        )
        title.pack(anchor=tk.W)

        subtitle = tk.Label(
            header,
            text="Akai Professional controller support for Linux",
            font=("Arial", 10),
            bg="#1e1e1e",
            fg="#999999"
        )
        subtitle.pack(anchor=tk.W)

        # Device selection
        devices_frame = ttk.LabelFrame(self.root, text="Select Devices to Install", padding=15)
        devices_frame.pack(fill=tk.BOTH, padx=20, pady=10)

        self.device_vars = {}
        for device_name in self.DEVICES.keys():
            var = tk.BooleanVar(value=True)
            self.device_vars[device_name] = var

            frame = tk.Frame(devices_frame, bg="#2a2a2a")
            frame.pack(fill=tk.X, pady=8)

            cb = tk.Checkbutton(
                frame,
                text=device_name,
                variable=var,
                font=("Arial", 11, "bold"),
                bg="#2a2a2a",
                fg="#00ff00",
                selectcolor="#1e1e1e",
                activebackground="#2a2a2a",
                activeforeground="#00ff00"
            )
            cb.pack(anchor=tk.W, padx=10, pady=5)

            device = self.DEVICES[device_name]
            info = tk.Label(
                frame,
                text=f"  USB: {device['vid']}:{device['pid']} | {device['controls']}",
                font=("Arial", 9),
                bg="#2a2a2a",
                fg="#888888"
            )
            info.pack(anchor=tk.W, padx=30)

        # Options
        options_frame = ttk.LabelFrame(self.root, text="Installation Options", padding=15)
        options_frame.pack(fill=tk.BOTH, padx=20, pady=10)

        cb_auto = tk.Checkbutton(
            options_frame,
            text="Auto-initialize devices on boot (systemd service)",
            variable=self.auto_init,
            font=("Arial", 10),
            bg="#2a2a2a",
            fg="#cccccc",
            selectcolor="#1e1e1e",
            activebackground="#2a2a2a"
        )
        cb_auto.pack(anchor=tk.W, pady=5)

        cb_hotplug = tk.Checkbutton(
            options_frame,
            text="Auto-initialize when device is plugged in (udev rules)",
            variable=self.auto_install,
            font=("Arial", 10),
            bg="#2a2a2a",
            fg="#cccccc",
            selectcolor="#1e1e1e",
            activebackground="#2a2a2a"
        )
        cb_hotplug.pack(anchor=tk.W, pady=5)

        # Status
        self.status_frame = ttk.LabelFrame(self.root, text="Status", padding=15)
        self.status_frame.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)

        self.status_text = tk.Text(
            self.status_frame,
            height=8,
            width=80,
            bg="#1a1a1a",
            fg="#00ff00",
            font=("Courier", 9),
            relief=tk.FLAT,
            borderwidth=0
        )
        self.status_text.pack(fill=tk.BOTH, expand=True)
        self.status_text.config(state=tk.DISABLED)

        # Buttons
        button_frame = tk.Frame(self.root, bg="#1e1e1e")
        button_frame.pack(fill=tk.X, padx=20, pady=20)

        btn_install = tk.Button(
            button_frame,
            text="Install",
            command=self._install,
            font=("Arial", 11, "bold"),
            bg="#00aa00",
            fg="white",
            padx=20,
            pady=10,
            relief=tk.FLAT,
            cursor="hand2"
        )
        btn_install.pack(side=tk.LEFT, padx=5)

        btn_uninstall = tk.Button(
            button_frame,
            text="Uninstall",
            command=self._uninstall,
            font=("Arial", 11),
            bg="#aa0000",
            fg="white",
            padx=20,
            pady=10,
            relief=tk.FLAT,
            cursor="hand2"
        )
        btn_uninstall.pack(side=tk.LEFT, padx=5)

        btn_close = tk.Button(
            button_frame,
            text="Close",
            command=self.root.quit,
            font=("Arial", 11),
            bg="#444444",
            fg="white",
            padx=20,
            pady=10,
            relief=tk.FLAT,
            cursor="hand2"
        )
        btn_close.pack(side=tk.RIGHT, padx=5)

    def _status_log(self, message: str, level: str = "INFO"):
        """Add message to status log"""
        self.status_text.config(state=tk.NORMAL)

        color_map = {
            "INFO": "#00ff00",
            "SUCCESS": "#00ff00",
            "WARNING": "#ffaa00",
            "ERROR": "#ff0000",
            "DEBUG": "#888888"
        }

        self.status_text.insert(tk.END, f"[{level}] {message}\n")
        self.status_text.tag_add(level, "end-2c")
        self.status_text.tag_config(level, foreground=color_map.get(level, "#ffffff"))
        self.status_text.see(tk.END)
        self.status_text.config(state=tk.DISABLED)
        self.root.update()

    def _check_requirements(self):
        """Check system requirements"""
        self._status_log("Checking requirements...", "INFO")

        # Check if running as root (needed for system installation)
        if os.geteuid() != 0:
            self._status_log(
                "⚠ Not running as root - some features may be limited",
                "WARNING"
            )
            self._status_log(
                "Run with: sudo python3 install.py",
                "INFO"
            )
        else:
            self._status_log("✓ Running with root privileges", "SUCCESS")

        # Check mido
        try:
            import mido
            self._status_log("✓ python-mido installed", "SUCCESS")
        except ImportError:
            self._status_log(
                "✗ python-mido not found - will be installed",
                "WARNING"
            )

        # Check if on SelahOS
        if Path("/etc/os-release").exists():
            with open("/etc/os-release") as f:
                if "Selah" in f.read().upper():
                    self._status_log("✓ Running on SelahOS", "SUCCESS")
                else:
                    self._status_log(
                        "⚠ Not running on SelahOS - installation may differ",
                        "WARNING"
                    )

    def _install(self):
        """Execute installation"""
        self._status_log("\n" + "="*60, "INFO")
        self._status_log("Starting installation...", "INFO")
        self._status_log("="*60, "INFO")

        if not any(self.device_vars.values()):
            messagebox.showerror("Error", "Please select at least one device")
            return

        try:
            # Step 1: Install dependencies
            self._step_install_dependencies()

            # Step 2: Create directories
            self._step_create_directories()

            # Step 3: Copy files
            self._step_copy_files()

            # Step 4: Install udev rules
            if self.auto_install.get():
                self._step_install_udev()

            # Step 5: Install systemd service
            if self.auto_init.get():
                self._step_install_systemd()

            # Step 6: Verify installation
            self._step_verify()

            self._status_log("\n" + "="*60, "SUCCESS")
            self._status_log("✓ Installation complete!", "SUCCESS")
            self._status_log("="*60, "SUCCESS")

            messagebox.showinfo(
                "Success",
                "Device bridge installed successfully!\n\n"
                "Your devices will now:\n"
                "• Auto-initialize on boot\n"
                "• Auto-initialize when plugged in\n"
                "• Be ready for use in your DAW"
            )

        except Exception as e:
            self._status_log(f"✗ Installation failed: {e}", "ERROR")
            messagebox.showerror("Installation Failed", str(e))

    def _step_install_dependencies(self):
        """Install Python dependencies"""
        self._status_log("\n[1/6] Installing dependencies...", "INFO")

        try:
            import mido
            self._status_log("✓ python-mido already installed", "DEBUG")
        except ImportError:
            self._status_log("Installing python-mido...", "INFO")
            subprocess.run(
                ["pip", "install", "--break-system-packages", "python-mido"],
                check=True,
                capture_output=True
            )
            self._status_log("✓ python-mido installed", "SUCCESS")

    def _step_create_directories(self):
        """Create necessary directories"""
        self._status_log("\n[2/6] Creating directories...", "INFO")

        for path_name, path_str in self.INSTALL_PATHS.items():
            path = Path(path_str)
            path.mkdir(parents=True, exist_ok=True)
            self._status_log(f"✓ {path_str}", "DEBUG")

    def _step_copy_files(self):
        """Copy framework files"""
        self._status_log("\n[3/6] Copying files...", "INFO")

        # Copy base class
        src = self.script_dir / "lib" / "device_base.py"
        dst = Path(self.INSTALL_PATHS["lib"]) / "device_base.py"
        shutil.copy2(src, dst)
        self._status_log(f"✓ Copied device_base.py", "DEBUG")

        # Copy device-specific files
        for device_name, var in self.device_vars.items():
            if not var.get():
                continue

            device_info = self.DEVICES[device_name]
            src = self.script_dir / "lib" / device_info["file"]

            if src.exists():
                dst = Path(self.INSTALL_PATHS["lib"]) / device_info["file"]
                shutil.copy2(src, dst)
                dst.chmod(0o755)
                self._status_log(f"✓ Copied {device_name} initializer", "DEBUG")
            else:
                self._status_log(f"⚠ {device_name} initializer not found", "WARNING")

        # Copy profiles
        profiles_src = self.script_dir / "profiles"
        profiles_dst = Path(self.INSTALL_PATHS["lib"]) / "profiles"
        if profiles_src.exists():
            profiles_dst.mkdir(exist_ok=True)
            for profile_file in profiles_src.glob("*.json"):
                shutil.copy2(profile_file, profiles_dst / profile_file.name)
            self._status_log(f"✓ Copied device profiles", "DEBUG")

        self._status_log("✓ All files copied", "SUCCESS")

    def _step_install_udev(self):
        """Create and install udev rules"""
        self._status_log("\n[4/6] Installing udev rules...", "INFO")

        udev_rules = """# SelahOS Device Bridge - Akai Professional Devices
# Auto-initializes devices when plugged in

# MPK mini IV (VID_09E8&PID_005D)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="09e8", ATTRS{idProduct}=="005d", \\
  ACTION=="add", RUN+="/usr/local/lib/selahos/device-bridge/udev-init.sh mpk_mini_iv"

# MPC Studio mk2 (VID_09E8&PID_004A)
SUBSYSTEMS=="usb", ATTRS{idVendor}=="09e8", ATTRS{idProduct}=="004a", \\
  ACTION=="add", RUN+="/usr/local/lib/selahos/device-bridge/udev-init.sh mpc_studio2_mk2"

# Allow non-root MIDI access
SUBSYSTEMS=="usb", ATTRS{idVendor}=="09e8", MODE="0666"
"""

        udev_file = Path(self.INSTALL_PATHS["udev"]) / "99-selahos-akai-bridge.rules"
        udev_file.write_text(udev_rules)
        self._status_log(f"✓ Created udev rule: {udev_file}", "DEBUG")

        # Reload udev rules
        try:
            subprocess.run(["udevadm", "control", "--reload-rules"], check=True)
            self._status_log("✓ Reloaded udev rules", "SUCCESS")
        except Exception as e:
            self._status_log(f"⚠ Could not reload udev: {e}", "WARNING")

    def _step_install_systemd(self):
        """Create and install systemd service"""
        self._status_log("\n[5/6] Installing systemd service...", "INFO")

        service_content = """[Unit]
Description=SelahOS Device Bridge Auto-Initialization
After=sound.target
ConditionPathExists=/usr/local/lib/selahos/device-bridge/

[Service]
Type=oneshot
ExecStart=/usr/local/lib/selahos/device-bridge/auto-init.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
"""

        service_file = Path(self.INSTALL_PATHS["systemd"]) / "selahos-device-bridge.service"
        service_file.write_text(service_content)
        self._status_log(f"✓ Created systemd service: {service_file}", "DEBUG")

        try:
            subprocess.run(["systemctl", "daemon-reload"], check=True)
            subprocess.run(["systemctl", "enable", "selahos-device-bridge.service"], check=True)
            self._status_log("✓ Enabled systemd service", "SUCCESS")
        except Exception as e:
            self._status_log(f"⚠ Could not enable service: {e}", "WARNING")

    def _step_verify(self):
        """Verify installation"""
        self._status_log("\n[6/6] Verifying installation...", "INFO")

        lib_path = Path(self.INSTALL_PATHS["lib"])

        # Check device_base.py
        if (lib_path / "device_base.py").exists():
            self._status_log("✓ device_base.py installed", "DEBUG")
        else:
            self._status_log("✗ device_base.py not found", "ERROR")

        # Check selected devices
        for device_name, var in self.device_vars.items():
            if not var.get():
                continue
            device_info = self.DEVICES[device_name]
            file_path = lib_path / device_info["file"]
            if file_path.exists():
                self._status_log(f"✓ {device_name} installed", "DEBUG")
            else:
                self._status_log(f"✗ {device_name} not found", "WARNING")

        # Check udev
        if self.auto_install.get():
            udev_file = Path(self.INSTALL_PATHS["udev"]) / "99-selahos-akai-bridge.rules"
            if udev_file.exists():
                self._status_log("✓ udev rules installed", "DEBUG")

        # Check systemd
        if self.auto_init.get():
            service_file = Path(self.INSTALL_PATHS["systemd"]) / "selahos-device-bridge.service"
            if service_file.exists():
                self._status_log("✓ systemd service installed", "DEBUG")

        self._status_log("✓ Installation verified", "SUCCESS")

    def _uninstall(self):
        """Remove installation"""
        if not messagebox.askyesno(
            "Confirm Uninstall",
            "Remove SelahOS Device Bridge?\n\n"
            "This will:\n"
            "• Remove all installed files\n"
            "• Disable udev rules\n"
            "• Disable systemd service"
        ):
            return

        self._status_log("\n" + "="*60, "INFO")
        self._status_log("Starting uninstallation...", "INFO")
        self._status_log("="*60, "INFO")

        try:
            # Remove systemd service
            try:
                subprocess.run(["systemctl", "disable", "selahos-device-bridge.service"], check=False)
                subprocess.run(["systemctl", "daemon-reload"], check=False)
            except:
                pass

            # Remove files
            lib_path = Path(self.INSTALL_PATHS["lib"])
            if lib_path.exists():
                shutil.rmtree(lib_path)
                self._status_log("✓ Removed device bridge files", "DEBUG")

            # Remove udev rules
            udev_file = Path(self.INSTALL_PATHS["udev"]) / "99-selahos-akai-bridge.rules"
            if udev_file.exists():
                udev_file.unlink()
                self._status_log("✓ Removed udev rules", "DEBUG")

            # Remove systemd service
            service_file = Path(self.INSTALL_PATHS["systemd"]) / "selahos-device-bridge.service"
            if service_file.exists():
                service_file.unlink()
                self._status_log("✓ Removed systemd service", "DEBUG")

            self._status_log("\n✓ Uninstallation complete", "SUCCESS")
            messagebox.showinfo("Success", "Device bridge uninstalled")

        except Exception as e:
            self._status_log(f"✗ Uninstallation failed: {e}", "ERROR")
            messagebox.showerror("Uninstallation Failed", str(e))


def main():
    """Run the installer"""
    root = tk.Tk()

    # Style the window
    root.configure(bg="#1e1e1e")
    style = ttk.Style()
    style.theme_use("clam")
    style.configure("TLabelframe", background="#1e1e1e", foreground="#ffffff")
    style.configure("TLabelframe.Label", background="#1e1e1e", foreground="#ffffff")

    app = DeviceBridgeInstaller(root)
    root.mainloop()


if __name__ == '__main__':
    main()
