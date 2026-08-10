"""
SelahOS Scripting Examples
Basic macro usage examples
"""

from selahos_scripting import MacroBuilder, Macro, MacroLibrary, StandardMacros


def example_simple_macro():
    """Example 1: Simple MIDI sequence"""
    macro = (MacroBuilder("Simple Sequence", "A basic MIDI sequence")
             .note_on("mpk_mini_iv", 60, 100)  # C4
             .delay(250)
             .note_off("mpk_mini_iv", 60)
             .delay(250)
             .note_on("mpk_mini_iv", 62, 100)  # D4
             .delay(250)
             .note_off("mpk_mini_iv", 62)
             .add_tag("learning")
             .build())

    return macro


def example_drum_pattern():
    """Example 2: Drum pattern macro"""
    builder = MacroBuilder(
        "4-Bar Drum Pattern",
        "Simple 4-bar drum pattern on MPC"
    )

    # Kick drum pattern (quarter notes)
    for bar in range(4):
        for beat in range(4):
            builder.note_on("mpc_studio2", 36, 100)  # Kick
            builder.delay(100)
            builder.note_off("mpc_studio2", 36)
            builder.delay(150)

    builder.add_tag("drums")
    builder.add_tag("mpc_studio2")
    return builder.build()


def example_cc_sweep():
    """Example 3: Control change sweep (filter sweep)"""
    builder = MacroBuilder("Filter Sweep", "Sweep filter cutoff")

    for value in range(0, 128, 4):
        builder.cc("mpk_mini_iv", 74, value)  # Filter cutoff CC
        builder.delay(50)

    builder.add_tag("effects")
    builder.add_tag("mpk_mini_iv")
    return builder.build()


def example_initialization():
    """Example 4: Device initialization sequence"""
    builder = MacroBuilder(
        "Initialize Devices",
        "Full initialization of all devices"
    )

    # Initialize each device
    builder.init_device("mpk_mini_iv")
    builder.delay(200)
    builder.init_device("mpc_studio2")
    builder.delay(200)
    builder.init_device("lpd8_mk2")
    builder.delay(200)

    # Reset all controllers
    for device in ["mpk_mini_iv", "mpc_studio2", "lpd8_mk2"]:
        builder.cc(device, 121, 0)  # Reset all controllers
        builder.cc(device, 123, 0)  # All notes off

    builder.add_tag("setup")
    builder.add_tag("system")
    return builder.build()


def example_library_management():
    """Example 5: Managing a macro library"""
    library = MacroLibrary()

    # Add some macros
    macros = [
        example_simple_macro(),
        example_drum_pattern(),
        example_cc_sweep(),
        example_initialization(),
        StandardMacros.reset_mpk_mini_iv(),
        StandardMacros.startup_sequence()
    ]

    for macro in macros:
        library.add_macro(macro)

    print(f"Library contains {len(library.list_macros())} macros")

    # Search macros
    mpc_macros = library.list_macros(tag="mpc_studio2")
    print(f"MPC macros: {len(mpc_macros)}")

    # Save to file
    library.save_to_file("/tmp/selahos_macros.json")
    print("Saved to /tmp/selahos_macros.json")

    # Export single macro
    exported = library.export_macro(example_simple_macro().id)
    print(f"Exported macro:\n{exported}")

    return library


async def example_execution(macro: Macro):
    """Example 6: Executing a macro"""
    from selahos_scripting import MacroExecutor

    async def my_midi_sender(action, device_id, channel, data):
        """Custom MIDI sender"""
        print(f"[{device_id}] {action}: {data}")

    executor = MacroExecutor(midi_sender=my_midi_sender)
    results = await executor.execute(macro)

    print(f"Execution results:")
    print(f"  Status: {results['status']}")
    print(f"  Steps executed: {results['steps_executed']}")
    print(f"  Steps failed: {results['steps_failed']}")
    if results.get('errors'):
        for error in results['errors']:
            print(f"    Step {error['step']}: {error['error']}")

    return results


# Usage guide
if __name__ == "__main__":
    print("SelahOS Scripting Examples\n")

    print("Example 1: Simple Sequence")
    macro1 = example_simple_macro()
    print(f"  Created: {macro1.name}")
    print(f"  Duration: {macro1.get_duration_ms()}ms")

    print("\nExample 2: Drum Pattern")
    macro2 = example_drum_pattern()
    print(f"  Created: {macro2.name}")
    print(f"  Duration: {macro2.get_duration_ms()}ms")

    print("\nExample 3: CC Sweep")
    macro3 = example_cc_sweep()
    print(f"  Created: {macro3.name}")
    print(f"  Duration: {macro3.get_duration_ms()}ms")

    print("\nExample 4: Initialization")
    macro4 = example_initialization()
    print(f"  Created: {macro4.name}")
    print(f"  Duration: {macro4.get_duration_ms()}ms")

    print("\nExample 5: Library Management")
    library = example_library_management()

    print("\nAll examples completed!")
