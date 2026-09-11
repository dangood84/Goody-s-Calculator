# Execution flow: from `begin` to a drawn key

A step-by-step trace of what happens from `program Calculator` through host initialisation, down to how a click on **2 + 3 =** is calculated and drawn.

Default launch (`make run`) opens the **macOS window**. `make windows` / `make linux` use the same model and renderer; only the present step changes. This trace is **macOS** (`uhostcocoa`) unless a step says otherwise.

One thread does everything after startup:

- **main (Pascal, then Cocoa run loop)** — `HostRun`, `setup`, mouse/key handlers, AppKit drawing

There is no Swing EDT. `NSView.mouseUp` and `NSImage.drawInRect` run on the same thread that called `NSApplication.run`.

---

## Phase A — process entry

**1.** The OS loads `GoodysCalculator.app/Contents/MacOS/GoodysCalculator` (or `./build/GoodysCalculator`). FPC unit initialisation runs (`TCalcModel` is not constructed yet).

**2.** `program Calculator` executes `HostRun`.

```pascal
{ src/calculator.pas }
begin
  HostRun;
end.
```

**3.** `HostRun` (Cocoa):

```pascal
procedure HostRun;
var
  Pool: NSAutoreleasePool;
  App: NSApplication;
begin
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyRegular);
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup;
  App.run;
  Pool.release;
end;
```

Regular policy (and **no** `LSUIElement` in `bundle/Info.plist`) means: **Dock icon**, Cmd-Tab, a real app. `App.run` does not return until Quit.

Windows: `HostRun` registers a window class, `CreateWindowEx`, menu, then `GetMessage`.  
Linux: `gtk_init`, `gtk_window_new`, event box, `gtk_main`.

---

## Phase B — window initialisation (`setup`)

**4.** `TAppDelegate.setup` is idempotent (`if ready then Exit`). `applicationDidFinishLaunching` calls it again after `App.run` has started; the second call is a no-op.

**5.** Pixel scale: `NSScreen.mainScreen.backingScaleFactor` (typically `2`). Controller buffer is in **pixels**, window size in **points** (280×430).

**6.** `controller := TCalcController.Create(pixelW, pixelH)`:

- `TCalcModel.Create` — display `"0"`, no pending op, memory empty
- `Canvas` `TPixelBuffer` allocated (RGBA)
- `HoverKey` / `PressedKey` = `ckNone`

**7.** Application menu targets the delegate: `aboutAction:`, `quitAction:` with **⌘Q**.

**8.** Window: titled, closable, miniaturizable, **not** resizable, centred on `visibleFrame`. Content view is `TCalcView` (unflipped). `applicationShouldTerminateAfterLastWindowClosed` is true, so the close box **quits**.

**9.** First `redraw` **before** `App.run` so the face is not blank for a frame.

```pascal
controller.Render;
frameImage := MakeImage(...);   { copy RGBA into a new NSImage }
window.makeKeyAndOrderFront(nil);
```

**10.** `App.run` starts. Cocoa may also send `applicationDidFinishLaunching` → `setup` (already `ready`).

---

## Phase C — a click (`2`)

**11.** The pointer is over the `2` key. `mouseMoved:` (tracking area) maps the event into canvas space:

```pascal
Pt := convertPoint_fromView(event.locationInWindow, nil);
CX := Pt.x / bounds.width  * canvasW
CY := (bounds.height - Pt.y) / bounds.height * canvasH   { FlipY }
HoverKey := HitTest(layout, Trunc(CX), Trunc(CY))        { ck2 }
redraw                                                   { 2 lightens }
```

**12.** `mouseDown:` — `PressedKey := ck2`. `RenderCalculator` inverts that bevel.

**13.** `mouseUp:` still on `2`:

```pascal
HoverKey := HitTest(...)
Key := PressedKey          { ck2 }
PressedKey := ckNone
if HoverKey = Key then
  Model.Press(ck2)
```

**14.** `TCalcModel.InputDigit(2)`:

```pascal
{ not entering, display was "0" }
FDisplay := '2'
FEntering := True
```

State after the click: **display `"2"`**; pixels have not changed until the draw pass at the end of `mouseUp`.

Windows: `WM_LBUTTONDOWN` / `UP` with client coords scaled by `canvas / client`.  
Linux: `button-press-event` / `button-release-event` on the event box.

---

## Phase D — operator, second operand, Equals

**15.** Click `+`. `InputOp(opAdd)`:

```pascal
FAcc := 2          { no pending yet, so Acc := Display }
FPending := opAdd
FEntering := False
```

The `+` key is drawn **armed** (`KeyFromOp(Pending) = ckAdd`).

**16.** Click `3`. Not entering, so the digit **replaces**: display `"3"`, `FEntering := True`. Acc is still 2, pending is still add.

**17.** Click `=`. `InputEquals`:

```pascal
FLastRhs := 3
FLastOp := opAdd
Apply(opAdd, 2, 3, V)     { V = 5, rounded to 12 sig digits }
FAcc := 5
FDisplay := '5'
FPending := opNone
FCanRepeat := True
```

**18.** `redraw` → `RenderCalculator`:

- platinum plate
- LCD well, right-aligned seven-segment `"5"` in green
- all operator keys un-armed
- `=` back to its resting bevel

**19.** `MakeImage` allocates an `NSBitmapImageRep` with **nil planes** (AppKit owns the bytes), copies `Canvas.Ptr` into `bitmapData`, and wraps that in a new `NSImage`. The previous `frameImage` is released.

**20.** `TCalcView.drawRect` fills platinum and `frameImage.drawInRect`. Cocoa composites that into the window.

---

## The repeating loop

There is no timer. The run loop waits:

```text
NSApplication.run (main thread)
  → mouseDown / mouseUp / keyDown
        HitTest or EventToKey
        Model.Press
        RenderCalculator
        MakeImage copy → setNeedsDisplay → drawRect
  → wait for the next event
```

Quit: menu **Quit Goody's Calculator** → `NSApplication.terminate`. Close box → last window closed → terminate. Process **does not** keep running.

Repeat Equals after step 17: each further `=` does `Apply(opAdd, CurrentValue, 3)` so 5 → 8 → 11.

---

## Keyboard path (same model)

**21.** `keyDown:` maps the event:

| Physical key | `TCalcKey` |
|--------------|------------|
| `2` | `ck2` via `CalcKeyFromChar` |
| keypad `+` | `ckAdd` |
| Return / keypad Enter (`keyCode` 36 / 76) | `ckEquals` |
| Escape (`keyCode` 53) | `ckAC` |
| Delete / Backspace (`keyCode` 51) and forward-delete (`117`) | `ckBackspace` |
| ⌘Q | **not** `keyDown` — the menu item |

`KeyPress` calls `Model.Press` directly (no sunk-bevel press state). Then the same `redraw`.

---

## Windows path (same draw loop)

`WndProc`:

1. `WM_LBUTTONDOWN` → `SetCapture` → `MouseDown`.
2. `WM_MOUSEMOVE` → `MouseMove` (capture keeps this coming outside the client).
3. `WM_LBUTTONUP` → `MouseUp` → `ReleaseCapture`.
4. `WM_CHAR` → `CalcKeyFromChar` (digits, `+ - * / = % c n`, Backspace as `#8`).
5. `WM_KEYDOWN` `VK_ESCAPE` / `VK_DELETE` for keys that do not produce a useful `WM_CHAR`.
6. `Redraw` → `CopyBGRA` → `InvalidateRect` → `WM_PAINT` `StretchDIBits`.

The window is `WS_EX_APPWINDOW`, so it has a **taskbar** button. Close posts `WM_DESTROY` → `PostQuitMessage`.

---

## Linux path (same draw loop)

GTK signals:

1. `button-press-event` / `button-release-event` / `motion-notify-event` on the **event box** (not the `gtk_image`).
2. `key-press-event` on the window (`GDK_Escape`, keypad constants, ASCII `keyval`).
3. `Present` copies RGBA into a `GdkPixbuf` and `gtk_image_set_from_pixbuf`.

Menu **Quit** or the window close box calls `gtk_main_quit`.

---

## One-line map

`begin HostRun` → `setup` (window + first paint) → **event** → **`HitTest` / `EventToKey`** → **`Model.Press`** → **`RenderCalculator` writes RGBA** → **`MakeImage` copies a snapshot** → **`drawRect`**.

Debugger: `HostRun`, `TAppDelegate.setup`, `TCalcView.mouseUp`, `TCalcModel.Press`, `RenderCalculator`, `MakeImage`. The first frame is a paint with display `"0"`; there is no “stamp time only” frame like the Java savers, and no 30 Hz tick like Eyes.

See also `WORKINGS.md` for class responsibilities and the accumulator / percent / memory rules in more detail.
