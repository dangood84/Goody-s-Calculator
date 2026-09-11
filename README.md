# Goody's Calculator

A classic Macintosh-inspired **four-function desk calculator**: LCD-style display, platinum bevel keys, memory, and a keyboard that matches the buttons.

Written in **Free Pascal**. Lazarus and Delphi are not required — `fpc` plus the platform GUI libraries already on the machine are enough. There is no JVM and no widget toolkit theme to fight. The whole face is a software RGBA canvas; each host only uploads those bytes into a native window.

Pascal is a better fit here than Java for the same reason it was for Eyes: one compile-time host (`{$IFDEF}`) gives a small native binary on macOS, Windows, and Linux, with mouse and key events coming from Cocoa / Win32 / GTK instead of a Swing EDT.

The calculator:

- adds, subtracts, multiplies, and divides
- chains operators (`2 + 3 + 4 = 9`) and repeats Equals (`5 + 2 = = =` → 11)
- replaces a pending operator if you change your mind (`2 + × 3 = 6`)
- does percent the four-function way (`200 + 10% = 220`, `50 × 10% = 5`)
- keeps **memory** across All Clear (`M+` / `MR` / `M-` / `MC`)
- shows **Error** on divide-by-zero or overflow (`|result| ≥ 1e12`); **AC** or Backspace recovers
- lights the pending operator so you can see what the next Equals will do

How the pieces fit together (same style as Eyes, Moiré, and the Java savers): `WORKINGS.md` for responsibilities and the register math, `EXECUTION_FLOW.md` for a click-by-click trace.

## Requirements

- **Free Pascal** 3.2+ (`fpc` on your `PATH`)

macOS (Homebrew):

```bash
brew install fpc
```

Debian / Raspberry Pi OS:

```bash
sudo apt install fpc libgtk2.0-dev
```

Windows: a native Free Pascal install (the `Windows` unit ships with FPC).

## Run

From the project root:

```bash
make
make run
```

That compiles to `build/` and opens `GoodysCalculator.app` on macOS. The window is a real app with a Dock icon (unlike Eyes, which lived in the menu bar).

Or with Make on other OSes:

```bash
make linux      # Linux / Raspberry Pi OS window
make windows    # GoodysCalculator.exe
make test       # headless engine checks (no GUI)
make snap       # two PPM frames of the canvas (idle, and after 2+3=)
make clean      # remove build/
```

Manual compile on macOS (Make still has to wrap the binary in the `.app` bundle):

```bash
fpc -Mobjfpc -Scgi -O2 -Fusrc -FUbuild -FEbuild -obuild/GoodysCalculator src/calculator.pas
make app
open build/GoodysCalculator.app
```

## Using it

1. Click digits, or type them. The LCD updates immediately.
2. Click an operator. That key stays lit until Equals (or until you pick a different operator).
3. Click **=** or press Enter. Repeat Equals to apply the last right-hand operand again.
4. **AC** (or Esc / `C`) clears the display and the pending operator. Memory survives AC.
5. **+/-** (or `N`) flips the sign. **%** scales the current value (see WORKINGS.md).
6. Memory: **M+** adds the display, **M-** subtracts, **MR** recalls, **MC** clears. An **M** appears in the LCD well while memory is non-zero.

## Keyboard

| Key | Action |
|-----|--------|
| `0`–`9` `.` | Digits and decimal (second dot is ignored) |
| `+` `-` `*` `/` | Operators (`x` also multiplies) |
| `Enter` `=` | Equals |
| `Esc` `C` | All Clear |
| `Backspace` | Delete last digit, or zero the display if not entering |
| `%` | Percent |
| `N` | Change sign |

The numeric keypad maps the same way. Memory keys are click-only.

## Where it appears

| OS | Presence |
|----|----------|
| **macOS** | Titled window, Dock icon, **About** / **Quit** in the application menu. |
| **Windows** | Titled window on the taskbar, **Calculator** menu (About / Exit). |
| **Linux** | GTK 2 window (Raspberry Pi OS friendly), **Calculator** menu. |

Closing the window **quits** the process. This is a desk calculator, not a menu extra.

## Project layout

```
src/
  calculator.pas    # program; picks the host with {$IFDEF}
  ucalcmodel.pas    # registers, pending op, memory, Error
  ucalcrender.pas   # software RGBA canvas (seven-segment LCD + bevel keys)
  ucalcapp.pas      # TCalcController: hit-test, press/release
  ubitmapfont.pas   # 8×8 glyphs for button captions and the Error LCD
  uhostcocoa.pas    # macOS NSWindow
  uhostwin.pas      # Windows HWND
  uhostgtk.pas      # Linux GtkWindow
  calctest.pas      # headless engine checks
  calcsnap.pas      # paints two PPM frames without a window
bundle/
  Info.plist        # retina-capable app bundle
Makefile
```
