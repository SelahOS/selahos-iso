"""
SelahOS Device Bridge Web Interface - FastAPI Backend
Run with: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import json
import asyncio
from typing import List, Dict
from pathlib import Path
from datetime import datetime

import mido

# Initialize FastAPI app
app = FastAPI(
    title="SelahOS Device Bridge",
    description="Web interface for Akai Professional device control",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Store connected WebSocket clients
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass

manager = ConnectionManager()

# ============================================================================
# REST API ENDPOINTS
# ============================================================================

@app.get("/api/devices")
async def get_devices():
    """List connected Akai devices"""
    devices = [
        {
            "id": "mpk_mini_iv",
            "name": "MPK mini IV",
            "usb_vid": "09E8",
            "usb_pid": "005D",
            "connected": check_device("09E8:005D"),
            "controls": "25 keys, 8 pads, 8 knobs, 2 wheels"
        },
        {
            "id": "mpc_studio2",
            "name": "MPC Studio mk2",
            "usb_vid": "09E8",
            "usb_pid": "004A",
            "connected": check_device("09E8:004A"),
            "controls": "16 pads, transport, jog wheel"
        },
        {
            "id": "lpd8_mk2",
            "name": "LPD8 mk2",
            "usb_vid": "09E8",
            "usb_pid": "0001",
            "connected": check_device("09E8:0001"),
            "controls": "8 pads, 8 knobs"
        },
        {
            "id": "mpk261",
            "name": "MPK261",
            "usb_vid": "09E8",
            "usb_pid": "0002",
            "connected": check_device("09E8:0002"),
            "controls": "61 keys, 16 pads"
        }
    ]
    return {"devices": devices}

@app.get("/api/midi/ports")
async def get_midi_ports():
    """List available MIDI ports"""
    return {
        "input_ports": mido.get_input_names(),
        "output_ports": mido.get_output_names()
    }

@app.post("/api/devices/{device_id}/init")
async def initialize_device(device_id: str):
    """Initialize a device"""
    # Placeholder: actual initialization would call device bridge
    return {
        "status": "initialized",
        "device_id": device_id,
        "message": f"{device_id} initialized successfully"
    }

@app.get("/api/presets")
async def list_presets():
    """List saved device presets"""
    return {
        "presets": [
            {"id": 1, "name": "Live Session", "device": "mpk_mini_iv"},
            {"id": 2, "name": "Studio Setup", "device": "mpc_studio2"}
        ]
    }

@app.post("/api/presets")
async def save_preset(preset_data: dict):
    """Save a preset"""
    return {
        "status": "saved",
        "preset_id": 3,
        "name": preset_data.get("name", "Untitled")
    }

# ============================================================================
# WEBSOCKET ENDPOINTS
# ============================================================================

@app.websocket("/ws/monitoring")
async def websocket_monitoring(websocket: WebSocket):
    """WebSocket for real-time device monitoring"""
    await manager.connect(websocket)
    try:
        while True:
            # Broadcast device status every second
            await asyncio.sleep(1)

            status = {
                "type": "device_status",
                "timestamp": datetime.now().isoformat(),
                "devices": await get_devices()
            }

            await manager.broadcast(status)

    except WebSocketDisconnect:
        manager.disconnect(websocket)

# ============================================================================
# HEALTH CHECK
# ============================================================================

@app.get("/health")
async def health():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "service": "selahos-device-bridge-web",
        "version": "1.0.0"
    }

# ============================================================================
# SERVE FRONTEND
# ============================================================================

@app.get("/")
async def root():
    """Serve frontend"""
    frontend_path = Path(__file__).parent.parent / "frontend" / "dist" / "index.html"
    if frontend_path.exists():
        return FileResponse(frontend_path)
    return {"message": "SelahOS Device Bridge API - Frontend not built yet"}

# Mount static files if they exist
frontend_dist = Path(__file__).parent.parent / "frontend" / "dist"
if frontend_dist.exists():
    app.mount("/static", StaticFiles(directory=str(frontend_dist)), name="static")

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

def check_device(vid_pid: str) -> bool:
    """Check if device is connected via USB"""
    try:
        import subprocess
        result = subprocess.run(
            ["lsusb"],
            capture_output=True,
            text=True,
            check=True
        )
        return vid_pid.lower() in result.stdout.lower()
    except:
        return False

# ============================================================================
# STARTUP/SHUTDOWN
# ============================================================================

@app.on_event("startup")
async def startup_event():
    print("╔════════════════════════════════════════════════════════════╗")
    print("║      SelahOS Device Bridge Web Interface Started           ║")
    print("╚════════════════════════════════════════════════════════════╝")
    print("")
    print("API Documentation: http://localhost:8000/docs")
    print("Dashboard:         http://localhost:8000/")
    print("")

@app.on_event("shutdown")
async def shutdown_event():
    print("\nSelahOS Device Bridge Web Interface stopped")

# ============================================================================

if __name__ == "__main__":
    import uvicorn
    from datetime import datetime
    uvicorn.run(app, host="0.0.0.0", port=8000)
