# How Goody's Calculator works

This note is for an automation tester who wants to see how a small Free Pascal desktop app is structured: where it starts, who owns state, who paints pixels, and how a click becomes `2 + 3 = 5`.

You do not need to be a Cocoa, Win32, or GTK expert. The same ideas show up in many GUI apps: an entry point, a model, a view, and an event loop that turns input into state then redraws.

There is **no Swing**, **no Lazarus**, and **no HTML**. Each key is a rectangle in a layout. A click that lands inside a rectangle becomes a `TCalcKey`. The model mutates a display string and two numbers. The renderer turns that into an RGBA buffer. The host only uploads the buffer.

This is **event-driven**, not a 30 FPS animation loop like Eyes. Nothing moves until a mouse or keyboard event arrives. That is the whole difference from the screensavers.

## Mental model

```
calculator.pas begin
  → HostRun                    # uhostcocoa / uhostwin / uhostgtk
      → create TCalcController (model + one pixel buffer)
      → create titled window
      → native run loop
           → mouse down / up / move  or  key
           → Controller hit-test / Model.Press
           → RenderCalculator (RGBA pixels)
           → host shows the buffer in the window
```

| Layer | Unit | Tester-friendly analogy |
|-------|------|-------------------------|
| Entry / routing | `calculator.pas` | Test runner that picks the OS host at compile time |
| State | `ucalcmodel` | Fixture: display string, accumulator, pending op, memory |
| Composer | `ucalcapp` | Holds one model and one canvas; classic press/release rule |
| View | `ucalcrender` | The thing that actually paints the LCD and bevel keys |
| Window shell | `uhostcocoa` / `uhostwin` / `uhostgtk` | Native window + “about / quit” |

The hosts are **event-driven**. Almost everything after `HostRun` runs on the GUI thread (Cocoa run loop, Windows message loop, GTK main loop). Clicks, keys, and drawing all happen there. That is why there is no `NSTimer` / `SetTimer` / `g_timeout_add` for the face itself.

---

## 1. Entry point and execution lifecycle

### Where `main` lives

The process entry point is the Pascal `program Calculator` in `src/calculator.pas`. It has no logic of its own. `{$IFDEF}` chooses one host unit; `begin HostRun; end.`

```pascal
uses
  {$IFDEF DARWIN}
  uhostcocoa
  {$ELSE}
    {$IFDEF WINDOWS}
    uhostwin
    {$ELSE}
    uhostgtk
    {$ENDIF}
  {$ENDIF};

begin
  HostRun;
end.
```

Only one `HostRun` is linked. The other two host units are not compiled on that OS.

### Lifecycle, step by step (macOS — the reference host)

1. **The OS** starts `GoodysCalculator.app/Contents/MacOS/GoodysCalculator`.
2. **`HostRun`** creates an `NSAutoreleasePool`, gets `NSApplication.sharedApplication`, and sets **`NSApplicationActivationPolicyRegular`** so there **is** a Dock icon (Eyes was an accessory; this is a real app).
3. **`TAppDelegate.alloc.init`** becomes the application (and window) delegate.
4. **`setup`** (idempotent via `ready`):
   - reads `backingScaleFactor` (usually 2 on retina)
   - `TCalcController.Create` with `280×430` points scaled to pixels
   - builds the application menu (About / Quit ⌘Q)
   - creates a non-resizable titled `NSWindow` centred on `visibleFrame`
   - content view is `TCalcView` (unflipped, so the y-down buffer is not drawn upside down)
   - first `redraw` so the window is not blank
5. **`App.run`** enters the Cocoa run loop. The process stays alive until **Quit** or the last window closes (`applicationShouldTerminateAfterLastWindowClosed`).

### One user journey

**Click `2` `+` `3` `=`:**

```
mouseDown on the 2 key  → PressedKey := ck2  (button sinks)
mouseUp still on 2      → Model.Press(ck2)   (display "2")
mouseDown/up on +       → pending opAdd, + stays lit
mouseDown/up on 3       → display "3"
mouseDown/up on =       → display "5", pending cleared
```

Windows and Linux follow the same composer: one `TCalcController`, mouse down/up, `Model.Press`, `RenderCalculator`.

### Why testers care

- **Compile-time host is the feature flag.** Automating “Mac window” vs “Windows window” is `make` vs `make windows`, not a CLI switch.
- **There is no preferences file.** Digit limits and percent rules are constants in `ucalcmodel` (`MaxDigits = 12`). A test that wants overflow should type 12 digits, not edit a config.
- **Exit is process-level** (`terminate` / `PostQuitMessage` / `gtk_main_quit`). Closing the window **quits**, unlike Eyes where close hid the desktop pair and left the extra running.
- **The painted keys are the real hit targets.** If a click misses a bevel, `HitTest` returns `ckNone` and the model does not change. You are not testing a native `NSButton`.
- **`make test`** exercises the engine without a GUI. Use that for register math; use the window for hit-testing, hover, and keyboard mapping.

---

## 2. Main units and responsibilities

This is a **separation of UI vs state**, not a full MVC framework. There is no database and no service layer.

### `calculator.pas` — composition root

- Picks the host with `{$IFDEF}`
- Calls `HostRun`
- Does **not** draw keys or store the accumulator

### `ucalcmodel` — state management

Holds *behaviour*, not pixels:

- `FDisplay` — the LCD string (digits append here while `FEntering`)
- `FAcc` — left operand / last result
- `FPending` — operator waiting for the right-hand side
- `FLastOp` / `FLastRhs` — so repeated Equals works
- `FMemory` / `FHasMemory`
- `FError`

**`Press(Key)`** is the only mutator. Hosts never poke `FDisplay` themselves.

This unit is the closest thing to a **model**. It has no Cocoa/Win32/GTK types. That is why `calctest.pas` can import it alone.

### `ucalcrender` — software canvas

- `TPixelBuffer`: a packed RGBA byte array (`Width × Height × 4`)
- `MakeCalcLayout`: padding, LCD well, 4×6 key grid (`0` spans two columns)
- `HitTest`: point-in-rect against that layout
- `RenderCalculator`: platinum plate, sunken LCD (seven-segment digits; **Error** is 8×8 glyphs), raised bevel keys
- Pending operator is drawn **armed** (cooler plate) so the next Equals is visible
- Hover lightens a key; a true press inverts the bevel and nudges the caption 1 px

It does **not** know about mouse buttons. It only paints `DisplayText`, `HasMemory`, `Pending`, plus the hover/pressed keys the controller passes in.

### `ucalcapp` — one controller, one buffer

- Owns `TCalcModel` and `Canvas`
- `MouseDown` records `PressedKey`
- `MouseUp` calls `Model.Press` **only if** the pointer is still on that same key
- `KeyPress` goes straight to the model (no press visual)
- `Render` → `RenderCalculator`

Classic Macintosh buttons work this way: press, drag off, release — nothing fires. That is the rule a Playwright tester would write as “mousedown on 7, mouseup on 8 → display unchanged.”

### `uhostcocoa` — macOS shell

- Regular `NSWindow`, Dock icon, application menu
- `NSView` mouseDown / mouseUp / mouseDragged / mouseMoved / keyDown
- Each redraw **copies** the RGBA canvas into a new `NSImage` (AppKit-owned bitmap), same snapshot trick as Eyes
- `FlipY` when converting view coords into the y-down buffer

### `uhostwin` — Windows shell

- Overlapped window (`WS_EX_APPWINDOW`) so it **appears on the taskbar**
- `WM_LBUTTONDOWN` / `UP` / `MOUSEMOVE`, `SetCapture` so release outside the client still cancels
- `WM_CHAR` for digits and operators; `VK_ESCAPE` / `VK_DELETE` on `WM_KEYDOWN`
- `CopyBGRA` + `StretchDIBits` (Windows DIBs are BGRA, top-down via negative `biHeight`)

### `uhostgtk` — Linux shell

- `gtk_window` + menubar + `gtk_event_box` (a bare `gtk_image` does not receive clicks)
- `button-press` / `release` / `motion` / `key-press`
- Copy RGBA into a `GdkPixbuf`, `gtk_image_set_from_pixbuf`

### What is *not* a unit

There is no `JButton`, no CSS, no accessibility tree of keys. The “objects” on screen are rectangles in `TCalcLayout`. The LCD *value* is a string (`DisplayText`); numeric strings are painted as seven-segment bars, and `Error` is painted with the 8×8 font.

---

## 3. How input becomes a redraw

This is **not** a game loop (`while running do begin Update; Render; end`).

It is a **GUI event loop** on the UI thread:

```
native event (click / key)
    → Controller (hit-test or map char → TCalcKey)
        → Model.Press              // registers, display string
            → RenderCalculator     // pixels
                → host presents    // setNeedsDisplay / StretchDIBits / set_from_pixbuf
```

### When it starts and stops

| Hook | Meaning |
|------|--------|
| `setup` / `WM_CREATE` / `HostRun` | Window exists; first `Render` |
| mouse / key handlers | One interaction |
| Quit menu / close box / `gtk_main_quit` | Process ends |

There is no timer. Hover highlighting is just another `mouseMoved` → `Render`.

### Update vs draw (important split)

| Procedure | Mutates | Draws |
|-----------|---------|-------|
| `TCalcModel.Press` | display, acc, pending, memory, error | no |
| `TCalcController.MouseDown/Up` | hover / pressed key; maybe `Press` | no |
| `RenderCalculator` | pixel buffer only | yes |
| host `setNeedsDisplay` / `InvalidateRect` | nothing in the model | presents |

A tester debugging “2 + 3 stayed 3” should breakpoint `Press` / `InputEquals`. A tester debugging “the window is blank” should breakpoint `RenderCalculator` / `MakeImage`. A tester debugging “clicks do nothing” should breakpoint `HitTest` / `ViewToCanvas` (especially the Cocoa Y flip). A tester debugging “the key fired when I released off it” should breakpoint `MouseUp` and watch `HoverKey = PressedKey`.

### Why not `Thread.sleep` in a loop?

A blocking loop on the GUI thread would freeze the menu and paints. A calculator has no frames to produce while idle. The run loop is the platform-native “wait for the next click.”

---

## 4. Register math on each key

Two kinds of state matter:

- **Entering** — digits append to `FDisplay`. The next operator commits that string as a number.
- **Not entering** — the LCD is showing a result (or the left operand). The next digit **replaces** it.

### Layout (`MakeCalcLayout`)

```text
Pad     = 4.5% of canvas width
Gap     = 1.8% of canvas width
DispH   = 16% of canvas height
ColW    = remaining width / 4
RowH    = remaining height / 6
0       = two columns wide
```

The same formula sizes a 280×430 Linux window and a 560×860 retina buffer. Hit-testing uses canvas pixels, not points.

### Digit entry

```text
if Error:           AllClear first
if not Entering:    Display := that digit; Entering := true
else if 12 digits:  ignore
else if Display is 0 / -0 and digit ≠ 0:
                    replace the zero
else:               append
```

A second decimal point is ignored. `0.` then `0` becomes `0.0` because `Display` is no longer exactly `'0'`.

### Operators

```text
if Entering and Pending exists:   Acc := Acc Pending Display   (chain)
else if no Pending:               Acc := Display
Pending := this operator
Entering := false
```

If you are **not** entering (you just pressed `+`, then change to `×`), only `Pending` changes. That is operator replacement.

### Equals

```text
if Pending:
    LastRhs := Display
    LastOp  := Pending
    Acc := Acc Pending Display
    Pending := none
    CanRepeat := true
else if CanRepeat:
    Acc := Display LastOp LastRhs     # 5+2=7=9=11
```

`5` `+` `=` is `5 + 5` because the display is still 5 when Equals runs.

### Percent

```text
if Pending is + or -:   Display := Acc * Display / 100
else:                   Display := Display / 100
Entering := false
```

Then Equals (or another operator) uses that as the right-hand side: `200 + 10% =` → 220. `50 × 10% =` → 5.

### Sign, backspace, AC, memory

| Key | Effect |
|-----|--------|
| `+/-` | Toggle a leading `-` on the display string (not a multiply by −1 of Acc). No-op on `0` |
| Backspace while entering | Drop last character; empty → `0` |
| Backspace while not entering | Display `0`, pending kept |
| **AC** | Display, Acc, pending, repeat — **not** memory |
| **M+** / **M-** | Memory ± display; `Entering := false`; **M** marker if memory ≠ 0 |
| **MR** | Display := memory; does not change pending |
| **MC** | Memory := 0 |

### Error

Divide by zero, or `|result| ≥ 1e12`, sets `Display = 'Error'`. Further operators are ignored until **AC** (or Backspace, which also All Clears from error).

Binary floating point is rounded to 12 significant digits before it hits the LCD, so `0.1 + 0.2` shows `0.3` rather than `0.30000000000000004`.

### Who updates what

| Value | Updated when | Role |
|-------|----------------|------|
| `FDisplay` | digit / dot / ± / compute / MR | LCD text |
| `FAcc`, `FPending` | operator / equals / AC | next compute |
| `FLastOp`, `FLastRhs` | equals | repeat equals |
| `FMemory` | M+ M- MC | survives AC |
| pixel buffer | every `Render` | thrown away next event |
| window image | after `Render` | what the user sees |

Idle tests do not apply. Leave the mouse still and **nothing** ticks. You are testing an event machine, not a screensaver.

---

## Quick map of files

```
src/
  calculator.pas    # program, {$IFDEF} host
  ucalcmodel.pas    # Press + registers
  ucalcrender.pas   # RGBA bevels, seven-segment LCD, HitTest
  ucalcapp.pas      # controller, press/release rule
  ubitmapfont.pas   # 8×8 captions
  uhostcocoa.pas    # NSWindow, mouse, keyDown
  uhostwin.pas      # HWND, WM_*, StretchDIBits
  uhostgtk.pas      # GtkWindow, event box, pixbuf
  calctest.pas      # make test
  calcsnap.pas      # make snap (PPM of the canvas, no window)
bundle/Info.plist   # NSHighResolutionCapable, Dock app
```

If you are tracing in a debugger, put breakpoints on `HostRun`, `TCalcController.MouseUp`, `TCalcModel.Press`, and `RenderCalculator`. You will see: **event → optional Press → paint RGBA → host presents**.
