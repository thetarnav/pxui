// Package pixui is an immediate-mode UI library for pixel-art games in Odin.
//
// Widgets are emitted as function calls each frame. Each call adds a node to a
// global tree (or a fresh tree, since the tree is rebuilt every frame). State
// that must persist across frames (animation values, slider/checkbox state,
// scroll offsets) is stored in a hash table keyed by a stable widget id.
//
// Coordinates are in *UI pixels* — the library does not know about screen
// resolution. A single `Context.pixel_scale` (set in `begin_frame`) scales all
// draw calls at emit time.
//
// Rendering is backend-agnostic. The `Backend` struct in `backend.odin` is a
// bag of proc pointers; the example wires it to karl2d.
package pixui

// Re-export the public surface so callers can `import px "pixui"` and reach
// everything via `px.*`. Mirrors the package's "everything at the root" layout.
