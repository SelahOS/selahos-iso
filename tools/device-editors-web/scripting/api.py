"""
SelahOS Scripting API
FastAPI endpoints for macro management and execution
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
import asyncio
from .core import (
    Macro, MacroBuilder, MacroLibrary, MacroExecutor, StandardMacros
)

router = APIRouter(prefix="/api/macros", tags=["macros"])

# Global macro library
macro_library = MacroLibrary()
macro_executor = None


def set_executor(executor: MacroExecutor):
    """Set the macro executor instance"""
    global macro_executor
    macro_executor = executor


# Request/Response models
class MacroCreate(BaseModel):
    name: str
    description: str = ""
    steps: List[Dict[str, Any]] = []
    tags: List[str] = []


class MacroUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    tags: Optional[List[str]] = None
    enabled: Optional[bool] = None


class ExecutionRequest(BaseModel):
    macro_id: str


# ============================================================================
# CRUD Operations
# ============================================================================

@router.get("/", response_model=List[Dict])
async def list_macros(tag: Optional[str] = None):
    """List all macros, optionally filtered by tag"""
    macros = macro_library.list_macros(tag=tag)
    return [m.to_dict() for m in macros]


@router.get("/{macro_id}", response_model=Dict)
async def get_macro(macro_id: str):
    """Get macro by ID"""
    macro = macro_library.get_macro(macro_id)
    if not macro:
        raise HTTPException(status_code=404, detail="Macro not found")
    return macro.to_dict()


@router.post("/", response_model=Dict)
async def create_macro(data: MacroCreate):
    """Create new macro"""
    builder = MacroBuilder(data.name, data.description)
    for tag in data.tags:
        builder.add_tag(tag)
    macro = builder.build()
    macro_library.add_macro(macro)
    return macro.to_dict()


@router.put("/{macro_id}", response_model=Dict)
async def update_macro(macro_id: str, data: MacroUpdate):
    """Update macro metadata"""
    macro = macro_library.get_macro(macro_id)
    if not macro:
        raise HTTPException(status_code=404, detail="Macro not found")

    if data.name:
        macro.name = data.name
    if data.description is not None:
        macro.description = data.description
    if data.tags is not None:
        macro.tags = data.tags
    if data.enabled is not None:
        macro.enabled = data.enabled

    return macro.to_dict()


@router.delete("/{macro_id}")
async def delete_macro(macro_id: str):
    """Delete macro"""
    if not macro_library.remove_macro(macro_id):
        raise HTTPException(status_code=404, detail="Macro not found")
    return {"status": "deleted"}


# ============================================================================
# Search & Filter
# ============================================================================

@router.get("/search/{query}", response_model=List[Dict])
async def search_macros(query: str):
    """Search macros by name/description"""
    macros = macro_library.search_macros(query)
    return [m.to_dict() for m in macros]


# ============================================================================
# Execution
# ============================================================================

@router.post("/{macro_id}/execute", response_model=Dict)
async def execute_macro(macro_id: str):
    """Execute macro"""
    if not macro_executor:
        raise HTTPException(status_code=503, detail="Executor not available")

    macro = macro_library.get_macro(macro_id)
    if not macro:
        raise HTTPException(status_code=404, detail="Macro not found")

    try:
        results = await macro_executor.execute(macro)
        return results
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{macro_id}/stop")
async def stop_macro(macro_id: str):
    """Stop macro execution"""
    if macro_executor:
        macro_executor.stop()
    return {"status": "stopped"}


# ============================================================================
# Import/Export
# ============================================================================

@router.get("/{macro_id}/export")
async def export_macro(macro_id: str):
    """Export macro as JSON"""
    exported = macro_library.export_macro(macro_id)
    if not exported:
        raise HTTPException(status_code=404, detail="Macro not found")
    return {"macro": exported}


@router.post("/import")
async def import_macro(data: Dict[str, str]):
    """Import macro from JSON"""
    try:
        macro = macro_library.import_macro(data["macro"])
        return macro.to_dict()
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# ============================================================================
# Library Management
# ============================================================================

@router.post("/library/save")
async def save_library(data: Dict[str, str]):
    """Save library to file"""
    try:
        macro_library.save_to_file(data["filepath"])
        return {"status": "saved"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/library/load")
async def load_library(data: Dict[str, str]):
    """Load library from file"""
    try:
        macro_library.load_from_file(data["filepath"])
        return {"status": "loaded", "count": len(macro_library.list_macros())}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============================================================================
# Templates
# ============================================================================

@router.get("/templates/", response_model=List[str])
async def list_templates():
    """List available macro templates"""
    return [
        "reset_mpk_mini_iv",
        "reset_mpc_studio2",
        "startup_sequence",
        "drum_kit_selection",
        "metronome_click"
    ]


@router.post("/templates/{template_name}", response_model=Dict)
async def create_from_template(template_name: str):
    """Create macro from template"""
    templates = {
        "reset_mpk_mini_iv": StandardMacros.reset_mpk_mini_iv,
        "reset_mpc_studio2": StandardMacros.reset_mpc_studio2,
        "startup_sequence": StandardMacros.startup_sequence,
        "drum_kit_selection": StandardMacros.drum_kit_selection,
        "metronome_click": StandardMacros.metronome_click,
    }

    if template_name not in templates:
        raise HTTPException(status_code=404, detail="Template not found")

    macro = templates[template_name]()
    macro_library.add_macro(macro)
    return macro.to_dict()


@router.get("/stats", response_model=Dict)
async def get_stats():
    """Get library statistics"""
    macros = macro_library.list_macros()
    total_steps = sum(len(m.steps) for m in macros)
    total_duration = sum(m.get_duration_ms() for m in macros)

    return {
        "total_macros": len(macros),
        "total_steps": total_steps,
        "total_duration_ms": total_duration,
        "enabled_macros": len([m for m in macros if m.enabled]),
        "tags": list(set(tag for m in macros for tag in m.tags))
    }
