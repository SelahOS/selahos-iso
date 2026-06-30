# SelahOS Device Scripting System

Complete macro and automation framework for SelahOS device control. Create, manage, and execute MIDI sequences and device automation routines.

## Features

✓ **Macro Engine** - Execute complex MIDI sequences
✓ **Fluent Builder API** - Easy-to-use Python API for creating macros
✓ **Macro Library** - Manage collections of macros with tagging/search
✓ **Standard Templates** - Pre-built macros for common tasks
✓ **REST API** - Full HTTP API for macro management
✓ **Import/Export** - Share macros as JSON files
✓ **Async Execution** - Non-blocking macro playback
✓ **Error Handling** - Robust error tracking and reporting

## Quick Start

### Creating a Simple Macro

```python
from selahos_scripting import MacroBuilder

macro = (MacroBuilder("My First Macro", "A simple test sequence")
    .note_on("mpk_mini_iv", 60, 100)   # C4, velocity 100
    .delay(250)
    .note_off("mpk_mini_iv", 60)
    .delay(250)
    .note_on("mpk_mini_iv", 62, 100)   # D4
    .delay(250)
    .note_off("mpk_mini_iv", 62)
    .add_tag("learning")
    .build())
```

### Managing Macros

```python
from selahos_scripting import MacroLibrary

# Create library
library = MacroLibrary()

# Add macro
library.add_macro(macro)

# Search
results = library.search_macros("drum")

# Filter by tag
drums = library.list_macros(tag="drums")

# Save to file
library.save_to_file("my_macros.json")

# Load from file
library.load_from_file("my_macros.json")
```

### Executing Macros

```python
from selahos_scripting import MacroExecutor
import asyncio

async def play_macro(macro):
    async def my_sender(action, device_id, channel, data):
        # Your MIDI sending implementation
        print(f"[{device_id}] {action}: {data}")
    
    executor = MacroExecutor(midi_sender=my_sender)
    results = await executor.execute(macro)
    
    print(f"Status: {results['status']}")
    print(f"Steps executed: {results['steps_executed']}")
    print(f"Errors: {results['steps_failed']}")

asyncio.run(play_macro(macro))
```

## Action Types

- **NOTE_ON** - Start a note: `note_on(device, note, velocity)`
- **NOTE_OFF** - Stop a note: `note_off(device, note)`
- **CC** - Control change: `cc(device, cc_number, value)`
- **SYSEX** - System exclusive: `sysex(device, [bytes])`
- **PROGRAM_CHANGE** - Program: `program_change(device, program)`
- **DELAY** - Wait: `delay(milliseconds)` or `delay_seconds(seconds)`
- **DEVICE_INIT** - Initialize device: `init_device(device_id)`

## Builder API Reference

### Note Methods
```python
.note_on(device_id, note, velocity=100, channel=1)
.note_off(device_id, note, channel=1)
```

### Control Methods
```python
.cc(device_id, cc_number, value, channel=1)
.program_change(device_id, program, channel=1)
.sysex(device_id, bytes, channel=1)
```

### Timing
```python
.delay(milliseconds)
.delay_seconds(seconds)
```

### Device
```python
.init_device(device_id)
```

### Metadata
```python
.set_name(name)
.set_description(description)
.add_tag(tag)
.add_tags([tags])
.enable()
.disable()
```

### Build
```python
.build()  # Returns completed Macro
```

## Standard Macros

Pre-built templates available via `StandardMacros`:

```python
from selahos_scripting import StandardMacros

# Device setup
StandardMacros.reset_mpk_mini_iv()
StandardMacros.reset_mpc_studio2()

# System
StandardMacros.startup_sequence()  # Initialize all devices

# Workflows
StandardMacros.drum_kit_selection()
StandardMacros.metronome_click()
```

## REST API Endpoints

### Macro CRUD
- `GET /api/macros` - List all macros
- `GET /api/macros/{id}` - Get macro
- `POST /api/macros` - Create macro
- `PUT /api/macros/{id}` - Update macro
- `DELETE /api/macros/{id}` - Delete macro

### Search & Filter
- `GET /api/macros/search/{query}` - Search by name/description
- `GET /api/macros?tag=drums` - Filter by tag

### Execution
- `POST /api/macros/{id}/execute` - Execute macro
- `POST /api/macros/{id}/stop` - Stop execution

### Import/Export
- `GET /api/macros/{id}/export` - Export as JSON
- `POST /api/macros/import` - Import from JSON

### Library
- `POST /api/macros/library/save` - Save to file
- `POST /api/macros/library/load` - Load from file

### Templates
- `GET /api/macros/templates/` - List templates
- `POST /api/macros/templates/{name}` - Create from template

### Stats
- `GET /api/macros/stats` - Library statistics

## File Format

Macros are stored as JSON:

```json
{
  "id": "uuid",
  "name": "Macro Name",
  "description": "Description",
  "created_at": "2026-06-30T10:00:00",
  "modified_at": "2026-06-30T10:00:00",
  "enabled": true,
  "tags": ["tag1", "tag2"],
  "steps": [
    {
      "action": "note_on",
      "device_id": "mpk_mini_iv",
      "channel": 1,
      "data": {"note": 60, "velocity": 100},
      "duration_ms": 0,
      "enabled": true
    },
    {
      "action": "delay",
      "device_id": null,
      "channel": 1,
      "data": {"delay_ms": 250},
      "duration_ms": 250,
      "enabled": true
    }
  ]
}
```

## Examples

### Drum Pattern
```python
builder = MacroBuilder("Drum Loop", "4-bar kick pattern")
for bar in range(4):
    for beat in range(4):
        builder.note_on("mpc_studio2", 36, 100)
        builder.delay(100)
        builder.note_off("mpc_studio2", 36)
        builder.delay(150)
macro = builder.build()
```

### Filter Sweep
```python
builder = MacroBuilder("Filter Sweep", "Sweep low-pass filter")
for value in range(0, 128, 4):
    builder.cc("mpk_mini_iv", 74, value)  # Cutoff CC
    builder.delay(50)
macro = builder.build()
```

### Initialization Sequence
```python
builder = MacroBuilder("Init All", "Setup all devices")
builder.init_device("mpk_mini_iv")
builder.delay(200)
builder.init_device("mpc_studio2")
builder.delay(200)
for device in ["mpk_mini_iv", "mpc_studio2"]:
    builder.cc(device, 121, 0)  # Reset controllers
    builder.cc(device, 123, 0)  # All notes off
macro = builder.build()
```

## Performance

- **Async execution** - Non-blocking playback via asyncio
- **Lazy loading** - Macros loaded on-demand
- **Efficient storage** - JSON format, easy to compress
- **Error recovery** - Continues on individual step failures
- **Memory efficient** - Streams MIDI output, doesn't buffer

## Advanced Usage

### Custom MIDI Sender
```python
async def send_to_hardware(action, device_id, channel, data):
    """Send MIDI to actual hardware"""
    # Connect to your MIDI device
    # Parse action type and data
    # Send appropriate MIDI message

executor = MacroExecutor(midi_sender=send_to_hardware)
```

### Chaining Macros
```python
async def play_sequence():
    executor = MacroExecutor(midi_sender=send_midi)
    
    for macro in [setup, intro, verse, chorus]:
        results = await executor.execute(macro)
        if results['status'] != 'completed':
            break
```

### Error Handling
```python
results = await executor.execute(macro)

if results['steps_failed'] > 0:
    for error in results['errors']:
        print(f"Step {error['step']}: {error['error']}")
```

## Limitations & Notes

- Maximum macro size: limited by available memory
- MIDI timing: subject to OS scheduler jitter
- WebSocket latency: accounts for network delays
- Concurrent execution: not thread-safe by default

## Future Enhancements

- [ ] Conditional logic (if/then/else)
- [ ] Looping constructs
- [ ] Variables and expressions
- [ ] Macro chaining/dependencies
- [ ] Visual macro editor
- [ ] Scheduled execution
- [ ] MIDI learning/capture
- [ ] Macro versioning

## License

Part of SelahOS - Audio production platform for Linux
