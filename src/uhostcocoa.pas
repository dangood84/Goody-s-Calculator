unit uhostcocoa;

{$mode objfpc}{$H+}
{$modeswitch objectivec1}

{ macOS titled window. Regular activation policy so there is a Dock icon.
  Same TCalcController as Windows/Linux; this unit only presents pixels
  and forwards mouse / key events. }

interface

procedure HostRun;

implementation

uses
  SysUtils, CocoaAll, ucalcmodel, ucalcapp;

const
  WinPointsW = 280;
  WinPointsH = 430;

type
  TCalcView = objcclass;
  TCalcWindow = objcclass;

  NSBitmapImageRepCalc = objccategory external (NSBitmapImageRep)
    { FPC truncates the real method name past 127 chars; this category keeps
      a short Pascal identifier and the full ObjC selector. }
    function initRGBA(planes: Pointer; aWidth: NSInteger; aHeight: NSInteger;
      aBits: NSInteger; aSamples: NSInteger; aAlpha: ObjCBOOL;
      aPlanar: ObjCBOOL; aSpace: NSString; aBpr: NSInteger;
      aBpp: NSInteger): id; message 'initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:';
  end;

  TAppDelegate = objcclass(NSObject, NSApplicationDelegateProtocol, NSWindowDelegateProtocol)
  public
    controller: TCalcController;
    window: TCalcWindow;
    view: TCalcView;
    frameImage: NSImage;
    scale: Double;
    ready: ObjCBOOL;
    procedure applicationDidFinishLaunching(notification: NSNotification); message 'applicationDidFinishLaunching:';
    function applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL; message 'applicationShouldTerminateAfterLastWindowClosed:';
    procedure quitAction(sender: id); message 'quitAction:';
    procedure aboutAction(sender: id); message 'aboutAction:';
    procedure redraw; message 'redraw';
    procedure setup; message 'setup';
  end;

  TCalcWindow = objcclass(NSWindow)
  public
    app: TAppDelegate;
    function canBecomeKeyWindow: ObjCBOOL; override;
  end;

  TCalcView = objcclass(NSView)
  public
    app: TAppDelegate;
    procedure drawRect(dirtyRect: NSRect); override;
    function acceptsFirstResponder: ObjCBOOL; override;
    function acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL; override;
    procedure mouseDown(event: NSEvent); override;
    procedure mouseUp(event: NSEvent); override;
    procedure mouseMoved(event: NSEvent); override;
    procedure mouseDragged(event: NSEvent); override;
    procedure mouseExited(event: NSEvent); override;
    procedure keyDown(event: NSEvent); override;
    procedure updateTrackingAreas; override;
  end;

var
  SharedApp: TAppDelegate;

function NSStr(const S: string): NSString;
begin
  Result := NSString.stringWithUTF8String(PChar(S));
end;

function MakeImage(Pixels: PByte; PixelW, PixelH: Integer; PointW, PointH: Double): NSImage;
var
  Rep: NSBitmapImageRep;
  Dest: PByte;
  Bytes: Integer;
begin
  Rep := NSBitmapImageRep(NSBitmapImageRep.alloc.initRGBA(nil, PixelW, PixelH, 8, 4,
    True, False, NSCalibratedRGBColorSpace, PixelW * 4, 32));
  { nil planes: AppKit owns a snapshot. Aliasing Canvas.Ptr would freeze the face
    (same trick as Eyes). }
  Result := NSImage.alloc.initWithSize(NSMakeSize(PointW, PointH));
  if Rep <> nil then
  begin
    Dest := PByte(Rep.bitmapData);
    Bytes := PixelW * PixelH * 4;
    if (Dest <> nil) and (Pixels <> nil) and (Bytes > 0) then
      Move(Pixels^, Dest^, Bytes);
    Result.addRepresentation(Rep);
    Rep.release;
  end;
  Result.setCacheMode(NSImageCacheNever); { recache of one image is not enough }
end;

function ViewToCanvas(View: NSView; Event: NSEvent; BufW, BufH: Integer; out CX, CY: Double): Boolean;
var
  Pt: NSPoint;
  B: NSRect;
begin
  Result := False;
  CX := 0;
  CY := 0;
  if (View = nil) or (Event = nil) then
    Exit;
  Pt := View.convertPoint_fromView(Event.locationInWindow, nil);
  B := View.bounds;
  if (B.size.width < 0.5) or (B.size.height < 0.5) then
    Exit;
  { Unflipped view: Cocoa y-up vs the y-down pixel buffer. }
  CX := Pt.x / B.size.width * BufW;
  CY := (B.size.height - Pt.y) / B.size.height * BufH;
  Result := True;
end;

function EventToKey(Event: NSEvent): TCalcKey;
var
  Code: Word;
  Chars: NSString;
  Ch: unichar;
begin
  Result := ckNone;
  if Event = nil then
    Exit;
  if Event.modifierFlags and NSCommandKeyMask <> 0 then
    Exit; { ⌘Q must stay the menu item, not a calculator key }
  Code := Event.keyCode;
  case Code of
    51, 117:
      Exit(ckBackspace); { 51 = Delete (backspace), 117 = forward delete }
    36, 76:
      Exit(ckEquals); { Return / keypad Enter }
    53:
      Exit(ckAC); { Escape }
  end;
  Chars := Event.charactersIgnoringModifiers;
  if (Chars = nil) or (Chars.length < 1) then
    Exit;
  Ch := Chars.characterAtIndex(0);
  if Ch <= 127 then
    Result := CalcKeyFromChar(Chr(Ch));
end;

procedure TAppDelegate.redraw;
begin
  if controller = nil then
    Exit;
  controller.Render;
  if frameImage <> nil then
    frameImage.release;
  frameImage := MakeImage(controller.Canvas.Ptr, controller.Canvas.Width,
    controller.Canvas.Height, WinPointsW, WinPointsH);
  if view <> nil then
    view.setNeedsDisplay_(True);
end;

procedure SetupMenu(Del: TAppDelegate);
var
  MainMenu, AppMenu: NSMenu;
  AppItem, Item: NSMenuItem;
begin
  MainMenu := NSMenu.alloc.init;
  AppItem := NSMenuItem.alloc.init;
  AppMenu := NSMenu.alloc.initWithTitle(NSStr('Calculator'));
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('About Goody''s Calculator'), objcselector('aboutAction:'), NSStr(''));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppMenu.addItem(NSMenuItem.separatorItem);
  Item := NSMenuItem.alloc.initWithTitle_action_keyEquivalent(
    NSStr('Quit Goody''s Calculator'), objcselector('quitAction:'), NSStr('q'));
  Item.setTarget(Del);
  AppMenu.addItem(Item);
  Item.release;
  AppItem.setSubmenu(AppMenu);
  MainMenu.addItem(AppItem);
  NSApplication.sharedApplication.setMainMenu(MainMenu);
  AppMenu.release;
  AppItem.release;
  MainMenu.release;
end;

procedure TAppDelegate.setup;
var
  PixelScale: Double;
  Style: NSUInteger;
  Rect: NSRect;
  Vis: NSRect;
begin
  if ready then
    Exit;
  ready := True;

  PixelScale := 2;
  if NSScreen.mainScreen <> nil then
    PixelScale := NSScreen.mainScreen.backingScaleFactor;
  if PixelScale < 1 then
    PixelScale := 1;
  scale := PixelScale;

  controller := TCalcController.Create(
    Round(WinPointsW * scale), Round(WinPointsH * scale));

  SetupMenu(self);

  Style := NSTitledWindowMask or NSClosableWindowMask or NSMiniaturizableWindowMask;
  { No NSResizableWindowMask — layout is a fixed 280×430 point face. }
  Rect := NSMakeRect(120, 80, WinPointsW, WinPointsH);
  if NSScreen.mainScreen <> nil then
  begin
    Vis := NSScreen.mainScreen.visibleFrame;
    Rect := NSMakeRect(
      Vis.origin.x + Trunc((Vis.size.width - WinPointsW) / 2),
      Vis.origin.y + Trunc((Vis.size.height - WinPointsH) / 2),
      WinPointsW, WinPointsH);
  end;
  window := TCalcWindow.alloc.initWithContentRect_styleMask_backing_defer(
    Rect, Style, NSBackingStoreBuffered, False);
  window.app := self;
  window.setTitle(NSStr('Goody''s Calculator'));
  window.setReleasedWhenClosed(False);
  { terminateAfterLastWindowClosed is what actually quits; we keep the object. }
  window.setOpaque(True);
  window.setBackgroundColor(NSColor.colorWithCalibratedRed_green_blue_alpha(0.77, 0.75, 0.71, 1.0));
  window.setDelegate(self);

  view := TCalcView.alloc.initWithFrame(NSMakeRect(0, 0, WinPointsW, WinPointsH));
  view.app := self;
  window.setContentView(view);
  window.makeFirstResponder(view); { without this, keyDown never arrives }

  redraw;
  NSApplication.sharedApplication.activateIgnoringOtherApps(True); { come to front on launch }
  window.makeKeyAndOrderFront(nil);
end;

procedure TAppDelegate.applicationDidFinishLaunching(notification: NSNotification);
begin
  setup;
end;

function TAppDelegate.applicationShouldTerminateAfterLastWindowClosed(sender: NSApplication): ObjCBOOL;
begin
  Result := True; { close box quits — a desk calculator, not a menu extra }
end;

procedure TAppDelegate.quitAction(sender: id);
begin
  NSApplication.sharedApplication.terminate(nil);
end;

procedure TAppDelegate.aboutAction(sender: id);
var
  Alert: NSAlert;
begin
  Alert := NSAlert.alloc.init;
  Alert.setMessageText(NSStr(CalcAboutTitle));
  Alert.setInformativeText(NSStr(CalcAboutText));
  Alert.runModal;
  Alert.release;
end;

procedure TCalcView.drawRect(dirtyRect: NSRect);
begin
  NSColor.colorWithCalibratedRed_green_blue_alpha(0.77, 0.75, 0.71, 1.0).set_;
  NSRectFill(self.bounds);
  if (app = nil) or (app.frameImage = nil) then
    Exit;
  app.frameImage.drawInRect_fromRect_operation_fraction(self.bounds, NSZeroRect,
    NSCompositeSourceOver, 1.0); { unflipped view + y-down buffer; isFlipped would invert it }
end;

function TCalcView.acceptsFirstResponder: ObjCBOOL;
begin
  Result := True; { otherwise keyDown never fires }
end;

function TCalcView.acceptsFirstMouse(theEvent: NSEvent): ObjCBOOL;
begin
  Result := True; { click-through from the background, like a desk accessory }
end;

procedure TCalcView.updateTrackingAreas;
var
  Track: NSTrackingArea;
  Areas: NSArray;
  Options: NSTrackingAreaOptions;
  I: Integer;
begin
  Areas := self.trackingAreas;
  if Areas <> nil then
    for I := Integer(Areas.count) - 1 downto 0 do
      self.removeTrackingArea(Areas.objectAtIndex(I));
  inherited updateTrackingAreas;
  Options := NSTrackingMouseMoved or NSTrackingMouseEnteredAndExited or
    NSTrackingActiveInKeyWindow or NSTrackingInVisibleRect or
    NSTrackingEnabledDuringMouseDrag; { hover without a click; keep tracking while dragged }
  Track := NSTrackingArea.alloc.initWithRect_options_owner_userInfo(
    self.bounds, Options, self, nil);
  self.addTrackingArea(Track);
  Track.release;
end;

procedure TCalcView.mouseDown(event: NSEvent);
var
  CX, CY: Double;
begin
  if app = nil then
    Exit;
  self.window.makeFirstResponder(self);
  if ViewToCanvas(self, event, app.controller.Canvas.Width, app.controller.Canvas.Height, CX, CY) then
    app.controller.MouseDown(CX, CY);
  app.redraw;
end;

procedure TCalcView.mouseUp(event: NSEvent);
var
  CX, CY: Double;
begin
  if app = nil then
    Exit;
  if ViewToCanvas(self, event, app.controller.Canvas.Width, app.controller.Canvas.Height, CX, CY) then
    app.controller.MouseUp(CX, CY)
  else
    app.controller.MouseUp(-1, -1); { miss: HoverKey will not match PressedKey }
  app.redraw;
end;

procedure TCalcView.mouseMoved(event: NSEvent);
var
  CX, CY: Double;
begin
  if app = nil then
    Exit;
  if ViewToCanvas(self, event, app.controller.Canvas.Width, app.controller.Canvas.Height, CX, CY) then
    app.controller.MouseMove(CX, CY);
  app.redraw;
end;

procedure TCalcView.mouseDragged(event: NSEvent);
var
  CX, CY: Double;
begin
  if app = nil then
    Exit;
  if ViewToCanvas(self, event, app.controller.Canvas.Width, app.controller.Canvas.Height, CX, CY) then
    app.controller.MouseMove(CX, CY);
  app.redraw;
end;

procedure TCalcView.mouseExited(event: NSEvent);
begin
  if app = nil then
    Exit;
  app.controller.MouseLeave;
  app.redraw;
end;

procedure TCalcView.keyDown(event: NSEvent);
var
  Mapped: TCalcKey;
begin
  if app = nil then
    Exit;
  Mapped := EventToKey(event);
  if Mapped = ckNone then
  begin
    inherited keyDown(event);
    Exit;
  end;
  app.controller.KeyPress(Mapped);
  app.redraw;
end;

function TCalcWindow.canBecomeKeyWindow: ObjCBOOL;
begin
  Result := True;
end;

procedure HostRun;
var
  Pool: NSAutoreleasePool;
  App: NSApplication;
begin
  Pool := NSAutoreleasePool.alloc.init;
  App := NSApplication.sharedApplication;
  App.setActivationPolicy(NSApplicationActivationPolicyRegular); { Dock icon; Eyes was Accessory }
  SharedApp := TAppDelegate.alloc.init;
  App.setDelegate(SharedApp);
  SharedApp.setup; { do not wait for didFinishLaunching; first paint before App.run }
  App.run;
  Pool.release;
end;

end.
