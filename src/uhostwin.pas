unit uhostwin;

{$mode objfpc}{$H+}

{ Windows titled window on the taskbar. Same TCalcController as macOS;
  this unit only presents pixels (BGRA StretchDIBits) and forwards input. }

interface

procedure HostRun;

implementation

{$IFDEF WINDOWS}

uses
  Windows, Messages, SysUtils, ucalcmodel, ucalcrender, ucalcapp;

const
  AppName = 'GoodysCalculatorWnd';
  CmdAbout = 1001;
  CmdQuit = 1002;
  WinW = 280;
  WinH = 430;
  BufScale = 2;

var
  Controller: TCalcController;
  MainWnd: HWND;
  Bgra: array of Byte;
  TrackingLeave: Boolean;

function ClientToCanvas(Wnd: HWND; X, Y: Integer; out CX, CY: Double): Boolean;
var
  R: TRect;
  CW, CH: Integer;
begin
  Result := False;
  CX := 0;
  CY := 0;
  if not GetClientRect(Wnd, R) then
    Exit;
  CW := R.Right - R.Left;
  CH := R.Bottom - R.Top;
  if (CW < 1) or (CH < 1) then
    Exit;
  CX := X * Controller.Canvas.Width / CW;
  CY := Y * Controller.Canvas.Height / CH;
  Result := True;
end;

procedure Redraw(Wnd: HWND);
begin
  Controller.Render;
  SetLength(Bgra, Controller.Canvas.Width * Controller.Canvas.Height * 4);
  CopyBGRA(Controller.Canvas, @Bgra[0]);
  InvalidateRect(Wnd, nil, False); { erase=False avoids a grey flash between paints }
end;

procedure PaintCalc(Wnd: HWND);
var
  PS: PAINTSTRUCT;
  DC: HDC;
  Info: BITMAPINFO;
  R: TRect;
begin
  DC := BeginPaint(Wnd, @PS);
  GetClientRect(Wnd, @R);
  if Length(Bgra) = Controller.Canvas.Width * Controller.Canvas.Height * 4 then
  begin
    FillChar(Info, SizeOf(Info), 0);
    Info.bmiHeader.biSize := SizeOf(BITMAPINFOHEADER);
    Info.bmiHeader.biWidth := Controller.Canvas.Width;
    Info.bmiHeader.biHeight := -Controller.Canvas.Height; { negative = top-down DIB, matches y-down canvas }
    Info.bmiHeader.biPlanes := 1;
    Info.bmiHeader.biBitCount := 32;
    Info.bmiHeader.biCompression := BI_RGB;
    StretchDIBits(DC, 0, 0, R.Right - R.Left, R.Bottom - R.Top,
      0, 0, Controller.Canvas.Width, Controller.Canvas.Height,
      @Bgra[0], Info, DIB_RGB_COLORS, SRCCOPY);
  end;
  EndPaint(Wnd, @PS);
end;

procedure ShowAbout(Wnd: HWND);
begin
  MessageBox(Wnd, PChar(CalcAboutText), CalcAboutTitle, MB_OK or MB_ICONINFORMATION);
end;

procedure EnsureMouseLeaveTrack(Wnd: HWND);
var
  Tme: TTrackMouseEvent;
begin
  if TrackingLeave then
    Exit;
  FillChar(Tme, SizeOf(Tme), 0);
  Tme.cbSize := SizeOf(Tme);
  Tme.dwFlags := TME_LEAVE;
  Tme.hwndTrack := Wnd;
  TrackMouseEvent(Tme);
  TrackingLeave := True;
end;

function WndProc(Wnd: HWND; Msg: UINT; WParam: WPARAM; LParam: LPARAM): LRESULT; stdcall;
var
  CX, CY: Double;
  Key: TCalcKey;
  Ch: Char;
  X, Y: Integer;
begin
  Result := 0;
  case Msg of
    WM_CREATE:
      Redraw(Wnd);
    WM_PAINT:
      PaintCalc(Wnd);
    WM_LBUTTONDOWN:
      begin
        SetCapture(Wnd); { release outside the client must still reach MouseUp }
        SetFocus(Wnd);
        X := SmallInt(LOWORD(LParam)); { signed: captured drags can report negative coords }
        Y := SmallInt(HIWORD(LParam));
        if ClientToCanvas(Wnd, X, Y, CX, CY) then
          Controller.MouseDown(CX, CY);
        Redraw(Wnd);
      end;
    WM_MOUSEMOVE:
      begin
        EnsureMouseLeaveTrack(Wnd);
        X := SmallInt(LOWORD(LParam));
        Y := SmallInt(HIWORD(LParam));
        if ClientToCanvas(Wnd, X, Y, CX, CY) then
          Controller.MouseMove(CX, CY);
        Redraw(Wnd);
      end;
    WM_LBUTTONUP:
      begin
        X := SmallInt(LOWORD(LParam));
        Y := SmallInt(HIWORD(LParam));
        if ClientToCanvas(Wnd, X, Y, CX, CY) then
          Controller.MouseUp(CX, CY)
        else
          Controller.MouseUp(-1, -1);
        if GetCapture = Wnd then
          ReleaseCapture;
        Redraw(Wnd);
      end;
    WM_MOUSELEAVE:
      begin
        TrackingLeave := False;
        Controller.MouseLeave;
        Redraw(Wnd);
      end;
    WM_CAPTURECHANGED:
      if Controller.PressedKey <> ckNone then
      begin
        Controller.PressedKey := ckNone; { lost capture: cancel, do not fire the key }
        Redraw(Wnd);
      end;
    WM_CHAR:
      begin
        { Digits, + - * / = % c n, and Backspace as #8 after TranslateMessage. }
        Ch := Chr(Byte(WParam));
        Key := CalcKeyFromChar(Ch);
        if Key <> ckNone then
        begin
          Controller.KeyPress(Key);
          Redraw(Wnd);
        end;
      end;
    WM_KEYDOWN:
      begin
        Key := ckNone;
        case WParam of
          VK_ESCAPE:
            Key := ckAC; { Escape does not produce a useful WM_CHAR }
          VK_DELETE:
            Key := ckBackspace;
        end;
        if Key <> ckNone then
        begin
          Controller.KeyPress(Key);
          Redraw(Wnd);
        end;
      end;
    WM_COMMAND:
      case LOWORD(WParam) of
        CmdAbout:
          ShowAbout(Wnd);
        CmdQuit:
          PostQuitMessage(0);
      end;
    WM_DESTROY:
      PostQuitMessage(0);
    else
      Result := DefWindowProc(Wnd, Msg, WParam, LParam);
  end;
end;

function BuildMenu: HMENU;
var
  Bar, CalcMenu: HMENU;
begin
  Bar := CreateMenu;
  CalcMenu := CreatePopupMenu;
  AppendMenu(CalcMenu, MF_STRING, CmdAbout, '&About Goody''s Calculator...');
  AppendMenu(CalcMenu, MF_SEPARATOR, 0, nil);
  AppendMenu(CalcMenu, MF_STRING, CmdQuit, 'E&xit');
  AppendMenu(Bar, MF_POPUP, CalcMenu, '&Calculator');
  Result := Bar;
end;

procedure HostRun;
var
  WC: WNDCLASS;
  Msg: TMsg;
  Wr: TRect;
  Style: DWORD;
begin
  Controller := TCalcController.Create(WinW * BufScale, WinH * BufScale); { 2× buffer, StretchDIBits to 280×430 }

  FillChar(WC, SizeOf(WC), 0);
  WC.lpfnWndProc := @WndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := GetStockObject(LTGRAY_BRUSH);
  WC.lpszClassName := AppName;
  RegisterClass(WC);

  Style := WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX;
  Wr.Left := 0;
  Wr.Top := 0;
  Wr.Right := WinW;
  Wr.Bottom := WinH;
  AdjustWindowRect(Wr, Style, True); { True = has a menu; client stays 280×430 }

  MainWnd := CreateWindowEx(WS_EX_APPWINDOW, AppName, 'Goody''s Calculator',
    { APPWINDOW = taskbar button; TOOLWINDOW would hide it. }
    Style,
    CW_USEDEFAULT, CW_USEDEFAULT, Wr.Right - Wr.Left, Wr.Bottom - Wr.Top,
    0, BuildMenu, HInstance, nil);

  ShowWindow(MainWnd, SW_SHOW);
  UpdateWindow(MainWnd);

  while GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg); { turns VK_RETURN / keypad into WM_CHAR }
    DispatchMessage(Msg);
  end;
  Controller.Free;
end;

{$ELSE}

procedure HostRun;
begin
end;

{$ENDIF}

end.
