# Compact panel with anchored graphical controls

Omarchy-inspired 26px panel and Tokyo Night palette, using Ironbar 0.17.1.
All controls live in one compact, centered strip with 16px icons and a short clock.
Panel labels, tooltips and calendar text are English; device and network names
remain unchanged. The locale is scoped to the panel/OSD services, not the session.
Click the clock, Wi-Fi, Bluetooth, volume, CPU or battery icon for its dropdown.
Press Escape, click elsewhere or click the same icon to close it. An open dropdown
keeps the bar visible; otherwise it hides 350ms after leaving the top edge.
Only the edge directly above the centered strip activates it. The invisible
hotspot follows the bar's actual size, including expanding/collapsing the tray.

- Wi-Fi uses the existing NetworkManager through `nmcli`, with rescan, radio,
  connection and disconnection controls. Passwords are written to stdin, never
  command arguments or files. Saved connections may use an empty password field.
- Bluetooth discovers nearby devices while its dropdown is open. Pairing uses
  the existing Blueman graphical agent for PIN/passkey confirmation.
- Wi-Fi and Bluetooth lists grow naturally up to 420px before scrolling, showing
  more rows without widening the dropdowns or stretching short lists.
- Audio uses Ironbar's PulseAudio-compatible mixer with horizontal sliders.
  Server updates do not fight slider dragging or echo back into the mixer.
- CPU and battery cards expose live readings; power management remains TLP.
- The tray opens on click and filters the network/Bluetooth applets already
  represented by dedicated controls. SwayNC retains its notification button.

`home/ironbar-package.nix` builds the pinned source with the existing stability
patch, the Wi-Fi module in `networkmanager.rs`, and version-checked adjustments
in `prepare-source.py`. `ironbar.service` owns the bar and its helper processes.
`panel-status.py` produces the CPU/battery card text.
Dropdown positioning follows the final window allocation when switching modules
or resizing, keeping it centered beneath the clicked icon rather than an edge.
Delayed focus-loss events are scoped to the current opening, so switching or
reopening a popup cannot dismiss it using the previous popup's focus state.

SwayOSD shows a short, bottom-center volume/brightness indicator. `desktop-osd`
observes master-volume events and backlight readings, so keys, the mouse wheel
and the mixer all work without replacing the existing controls. It never sets
volume or brightness, captures pointer input, or takes keyboard focus.
The compact indicator is 220px wide with 20px icons and a 600ms dismissal timer.
Repeated changes reset that timer. Audio events are read immediately after idle
and coalesced at 20ms intervals; backlight changes are sampled every 40ms.
`home/swayosd-package.nix` narrowly patches the pinned 0.2.1 renderer's hard-coded
widget size, spacing and timeout; input/focus handling and controls are unchanged.
All panel/OSD files and session units are owned by Home Manager and applied with
the normal rebuild, not manually installed generation links.

Fuzzel is restored byte-for-byte from generation 62, including
its original palette, border and font. Its Niri shortcuts use `menu-control.sh`.
There is no Omarchy management menu, Walker launcher or terminal-based control UI.

Verify helpers with `PYTHONDONTWRITEBYTECODE=1 python3 test_helpers.py`.
Original Omarchy layout attribution: `OMARCHY-LICENSE`.
