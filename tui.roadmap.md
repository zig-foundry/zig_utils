# zig_utils.tui Roadmap

**Goal**: Reach full ncurses feature parity, then go beyond it... safer, more powerful, and aligned with Zig’s philosophy.

Reference: ncurses (X/Open Curses + extensions), with modern terminal protocols (truecolor, synchronized output, Kitty keyboard, SGR mouse) as first-class citizens.

---

## Current State Audit (Phase 0 — Done)

### What Exists

| Area | Status | Notes |
|------|--------|-------|
| Terminal raw mode + alternate screen | Done | `enterRawMode` / `leaveRawMode`, `?1049h/l` |
| SIGWINCH resize | Done | Atomic flag + `handleResize` |
| Double buffering | Done | Virtual + physical screens, minimal ANSI |
| Synchronized output | Done | `?2026h/l` |
| Color pairs | Done | 1–255, slot 0 = default |
| Attributes | Partial | bold, dim, italic, underline, reverse |
| Windows | Basic | Absolute position, own cell buffer |
| Input | Basic | Blocking / timed / nodelay, arrows, Ctrl, UTF-8 codepoints, resize |
| Drawing | Basic | `addChar`/`addStr`/`print`, `box()`, `erase`/`clear` |
| Refresh | Done | `noutrefresh` + `doupdate` / `refresh` |
| Cursor control | Basic | Visibility only |

### Gaps vs ncurses

- No pads
- No panels (z-order / overlapping)
- No subwindows / derived windows
- No scrolling (`scrollok`, `wscrl`)
- No background character (`bkgd` / `bkgdset`)
- No mouse
- Incomplete keypad / function keys
- No forms / menus / soft labels
- Limited ACS / line-drawing
- No insert/delete line/char
- No overlay / copywin
- Minimal attribute set (missing blink, standout, invisible, protect)
- No capability query / terminfo abstraction
- Global termios + signal state (acceptable for panic safety, but should be minimized)

### Strengths to Keep

- Explicit allocators
- Error returns (no silent `ERR`)
- Panic-safe `endwin()`
- Truecolor + ANSI already in `Color`
- Diff-based renderer (already better than naive full redraw)

---

## Design Philosophy (Zig’s Way)

1. **Safety first**: No UB, no hidden globals where avoidable, all resources explicit, `defer` friendly.
2. **Allocator-aware**: Every allocation takes an allocator. No hidden heaps.
3. **Error-driven**: Functions that can fail return `error` unions. No `ERR`/`OK` integer codes.
4. **Comptime where it helps**: Color pair IDs, attribute bitmasks, format strings, static key tables.
5. **Modern terminals first**: Truecolor, synchronized output, Kitty keyboard protocol, SGR mouse are defaults. Fallbacks exist but are secondary.
6. **Explicit over magic**: No automatic “magic cookie” handling, no hidden insert/delete optimization unless the user opts in.
7. **Layered API**:
   - Core (windows, cells, renderer, input) — low-level, ncurses-like.
   - Higher-level (panels, pads, forms, menus, widgets): built on top, optional.
8. **No C compatibility tax**: We do not aim for a drop-in `ncurses.h` replacement. We take the good ideas and express them cleanly in Zig.

---

## Phased Roadmap

### Phase 1 — Solidify Core (Current → Production-Ready Base)

**Goal**: Make the existing foundation complete and robust.

- [X] Full attribute set (`blink`, `standout`, `invisible`, `protect`, `altcharset`)
- [X] Background character + attribute (`bkgdset` / `bkgd` equivalent)
- [X] Proper ACS / line-drawing constants (or Unicode box drawing as primary)
- [ ] Better border API (`border` with custom corners/sides)
- [ ] Window methods: `getyx`, `getbegyx`, `getmaxyx`, `inch` / `mvinch`
- [ ] `wtouch` / change tracking improvements
- [ ] Cursor positioning on terminal (`move` that actually moves the physical cursor when needed)
- [ ] `beep` / `flash`
- [ ] Input: complete keypad (F1–F12, keypad keys, modifiers)
- [ ] Input: better Escape vs sequence discrimination
- [ ] Remove remaining silent failures; make all drawing errors explicit where relevant
- [ ] Documentation + more examples

### Phase 2 — Windows, Subwindows, Scrolling

**Goal**: Full window model.

- [ ] Subwindows (`subwin`, `derwin`)
- [ ] Parent/child relationships + clipping correctness
- [ ] `scrollok`, `wscrl`, `scroll`
- [ ] Insert / delete line (`insdelln`, `insdelch`)
- [ ] Overlay / overwrite (`overlay`, `overwrite`, `copywin`)
- [ ] Window move (`mvwin`) with proper invalidation
- [ ] Better resize behavior (preserve content where sensible)

### Phase 3 — Pads

**Goal**: Virtual windows larger than the screen.

- [ ] `Pad` type (or `Window` with unbounded virtual size)
- [ ] Viewport model (`prefresh` / `pnoutrefresh` style)
- [ ] Subpads
- [ ] Efficient partial updates

### Phase 4 — Panels (Z-Order & Overlapping)

**Goal**: Proper stacking.

- [ ] Panel layer on top of windows
- [ ] `new_panel`, `top_panel`, `bottom_panel`, `hide_panel`, `show_panel`
- [ ] Automatic redraw order
- [ ] User pointer / panel data

### Phase 5 — Input Completeness

**Goal**: Production-grade input.

- [ ] Mouse support (SGR 1006 + classic)
- [ ] Full Kitty keyboard protocol (where available)
- [ ] Modifier keys (Shift, Ctrl, Alt, Meta) on all keys
- [ ] `keypad` mode as an explicit flag
- [ ] Input queue / ungetch equivalent
- [ ] Half-delay / timed input refinements

### Phase 6 — Color System Polish

**Goal**: Best-in-class color.

- [ ] `use_default_colors` equivalent
- [ ] `init_color` / palette redefinition (where supported)
- [ ] Color capability query (truecolor, 256, 16, monochrome)
- [ ] Automatic degradation path (optional)
- [ ] Pair allocation helpers (beyond fixed 256)

### Phase 7 — Higher-Level Components (Optional Layer)

**Goal**: Menus, forms, soft labels — the parts that make ncurses usable for real apps.

These should be optional modules, not forced into the core.

- [ ] Soft labels
- [ ] Menu system (items, multi-column, scrolling, mouse)
- [ ] Form system (fields, validation, drivers)
- [ ] Basic widgets (list, table, progress, dialog) — modern extras

### Phase 8 — Extras Beyond ncurses

**Goal**: Things ncurses never had, or had poorly.

- [ ] First-class truecolor + RGB everywhere
- [ ] Synchronized output as default (already started)
- [ ] Kitty graphics / image protocol (optional)
- [ ] Better Unicode: grapheme-aware width, wide characters
- [ ] Damage tracking / dirty regions (more efficient than full cell compare)
- [ ] Multiple independent screens
- [ ] Async-friendly design (no hidden blocking where avoidable)
- [ ] Theme system / style sheets for widgets
- [ ] Clipboard integration (where possible)
- [ ] High-level immediate-mode or retained-mode UI helpers (user choice)

---

## Feature Parity Matrix

| Feature | ncurses | Current | Target |
|---------|---------|---------|--------|
| Windows | Yes | Basic | Full |
| Subwindows | Yes | No | Yes |
| Pads | Yes | No | Yes |
| Panels | Yes | No | Yes |
| Color pairs | Yes | Yes | Yes + truecolor |
| Attributes | Full | Partial | Full |
| Mouse | Yes | No | Yes |
| Forms / Menus | Yes | No | Optional layer |
| Double buffering | Yes | Yes | Better |
| Terminfo | Yes | No | Capability query |
| Unicode | Wide API | Basic u21 | Grapheme-aware |
| Safety | C | Better | Best |

---

## Implementation Priorities (Recommended Order)

1. Finish Phase 1 (core completeness)
2. Phase 2 (subwindows + scrolling) — unlocks real applications
3. Phase 5 (input + mouse) — usability
4. Phase 3 + 4 (pads + panels) — advanced windowing
5. Phase 6 (color polish)
6. Phase 7 (higher-level) as demand appears
7. Phase 8 (extras) continuously

---

## Notes for Implementation

- Keep the virtual/physical diff renderer. It is already one of the strongest parts.
- Prefer Unicode box-drawing characters over ACS for modern terminals. Offer ACS as a fallback mode.
- Minimize global state. The current termios + SIGWINCH globals exist for panic safety — document them clearly and isolate them.
- All public APIs should be allocator-explicit and error-returning.
- Write tests for the cell model, input parser, and renderer diffing early.
- Examples should grow with each phase (menu demo, form demo, pad demo, mouse demo).

---

## Success Criteria

- Can write a full-screen application with overlapping windows, scrolling text, mouse, and truecolor without leaving the library.
- The API feels like Zig, not like a C port.
- Panic-safe cleanup remains intact.
- Performance is equal or better than ncurses on modern terminals (diff + synchronized output already helps).

This roadmap is living. Update it as phases complete.

