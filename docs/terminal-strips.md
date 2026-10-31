# Terminal strips (core contract)

Drawings retain schema version 1. New drawings contain `terminalStrips: []`; old drawings without the field remain valid. A strip is `{id, bmk, label?}`. Each physical terminal remains its own device (`type: terminal`, exactly one existing port) and may have `terminalStripId` referencing a strip. Its port `label` is the mark (`1`, `N`, `PE`, `+`, `-`, or another nonblank 1–3 Unicode-scalar-character mark); port `id` stays `1`. Marks are unique **within** a strip (exact comparison). A legacy terminal without `terminalStripId` retains its prior BMK/port-label display.

Public functions exported by `package:ecad_core/ecad_core.dart`:

- `createTerminalStrip(d, bmk, {label}) -> Json` adds and returns the strip. `renameTerminalStrip(d, stripId, bmk)` changes its visible BMK. BMKs are nonblank, at most 80 characters, and case-insensitively unique across strips, devices and cables.
- `assignTerminalToStrip(d, deviceId, stripId, mark)` changes only the terminal's strip reference and port label. `setTerminalMark(d, deviceId, mark)` changes the mark of an already assigned terminal. Both reject duplicate marks, invalid marks, and invalid devices; validation also enforces these constraints on loaded documents. Functions mutate the passed drawing and throw `FormatException` on invalid input.
- `deleteTerminalStrip(d, stripId)` refuses an occupied strip. To unassign a terminal, remove its `terminalStripId` (keeping its current label) before deleting the empty strip; the device and wires remain.
- `terminalDisplayBmk(d, device)` returns the strip BMK for assigned devices, the own device BMK otherwise. Use `${terminalDisplayBmk(d, device)}:${(device['terminals'] as List).first['label']}` for the visible terminal name. `endpointName(d, portRef(instanceId, '1'))` already produces it.

The device's internal `bmk` remains unique and never becomes the strip BMK. Never replace the device ID, instance ID, port ID or wire `terminalId` with a display string: `endpointKey` continues using physical device/port identities, so distinct terminals on a strip cannot short electrically. `documentData(project)['terminals']` has one row per device/port with stable `id: '<deviceId>:<portId>'`, visible `bmk` and `terminal`, plus `deviceId` and optional `terminalStripId`. Connection endpoint labels also use the visible strip BMK and mark.

**Macro integration:** `extractMacroRegion` copies strips referenced by selected terminal devices. `insertMacro` allocates fresh strip IDs, resolves colliding BMKs, and remaps each copied terminal's `terminalStripId`; covered by `macros_calculations_test.dart`. Pinned symbol definitions need no change: the terminal port identity remains `1`.
