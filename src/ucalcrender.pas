unit ucalcrender;

{$mode objfpc}{$H+}

{ Software RGBA canvas for the calculator. Hosts only upload the bytes.
  Layout is derived from the buffer size so a 1× Linux window and a 2×
  retina Mac window share the same hit-testing math. }

interface

uses
  ucalcmodel;

type
  TCalcRole = (crDigit, crOp, crFn, crMem, crEq);

  TCalcBtn = record
    Key: TCalcKey;
    Caption: string[7]; { shortstring so FillChar on the layout record is safe }
    X, Y, W, H: Integer;
    Role: TCalcRole;
  end;

  TCalcLayout = record
    DispX, DispY, DispW, DispH: Integer;
    Buttons: array[0..22] of TCalcBtn;
    Count: Integer;
  end;

  TPixelBuffer = class
  private
    FWidth, FHeight: Integer;
    FData: array of Byte;
  public
    constructor Create(AWidth, AHeight: Integer);
    procedure Resize(AWidth, AHeight: Integer);
    procedure Clear(R, G, B, A: Byte);
    function Ptr: PByte;
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
  end;

function MakeCalcLayout(BufW, BufH: Integer): TCalcLayout;
function HitTest(const Lay: TCalcLayout; PX, PY: Integer): TCalcKey;
procedure RenderCalculator(Buf: TPixelBuffer; Model: TCalcModel;
  Hover, Pressed: TCalcKey);
procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);

implementation

uses
  SysUtils, ubitmapfont;

constructor TPixelBuffer.Create(AWidth, AHeight: Integer);
begin
  inherited Create;
  Resize(AWidth, AHeight);
end;

procedure TPixelBuffer.Resize(AWidth, AHeight: Integer);
begin
  if AWidth < 1 then
    AWidth := 1;
  if AHeight < 1 then
    AHeight := 1;
  FWidth := AWidth;
  FHeight := AHeight;
  SetLength(FData, FWidth * FHeight * 4);
end;

procedure TPixelBuffer.Clear(R, G, B, A: Byte);
var
  I: Integer;
  P: PByte;
begin
  P := @FData[0];
  I := 0;
  while I < Length(FData) do
  begin
    P[I] := R;
    P[I + 1] := G;
    P[I + 2] := B;
    P[I + 3] := A;
    Inc(I, 4);
  end;
end;

function TPixelBuffer.Ptr: PByte;
begin
  Result := @FData[0];
end;

procedure CopyBGRA(Buf: TPixelBuffer; Dest: PByte);
var
  I, N: Integer;
  S, D: PByte;
begin
  S := Buf.Ptr;
  D := Dest;
  N := Buf.Width * Buf.Height;
  for I := 0 to N - 1 do
  begin
    D[0] := S[2]; { B — Windows DIB / HICON want BGRA; the canvas is RGBA }
    D[1] := S[1];
    D[2] := S[0];
    D[3] := S[3];
    Inc(S, 4);
    Inc(D, 4);
  end;
end;

procedure PutPixel(Buf: TPixelBuffer; X, Y: Integer; R, G, B: Byte);
var
  P: PByte;
begin
  if (X < 0) or (Y < 0) or (X >= Buf.Width) or (Y >= Buf.Height) then
    Exit;
  P := Buf.Ptr + (Y * Buf.Width + X) * 4;
  P[0] := R;
  P[1] := G;
  P[2] := B;
  P[3] := 255;
end;

procedure FillRect(Buf: TPixelBuffer; X, Y, W, H: Integer; R, G, B: Byte);
var
  XX, YY, X0, Y0, X1, Y1: Integer;
begin
  X0 := X;
  Y0 := Y;
  if X0 < 0 then
    X0 := 0;
  if Y0 < 0 then
    Y0 := 0;
  X1 := X + W - 1;
  Y1 := Y + H - 1;
  if X1 >= Buf.Width then
    X1 := Buf.Width - 1;
  if Y1 >= Buf.Height then
    Y1 := Buf.Height - 1;
  for YY := Y0 to Y1 do
    for XX := X0 to X1 do
      PutPixel(Buf, XX, YY, R, G, B);
end;

procedure HLine(Buf: TPixelBuffer; X, Y, W: Integer; R, G, B: Byte);
var
  I: Integer;
begin
  for I := 0 to W - 1 do
    PutPixel(Buf, X + I, Y, R, G, B);
end;

procedure VLine(Buf: TPixelBuffer; X, Y, H: Integer; R, G, B: Byte);
var
  I: Integer;
begin
  for I := 0 to H - 1 do
    PutPixel(Buf, X, Y + I, R, G, B);
end;

procedure AddBtn(var Lay: TCalcLayout; Key: TCalcKey; const Caption: string;
  X, Y, W, H: Integer; Role: TCalcRole);
begin
  if Lay.Count > High(Lay.Buttons) then
    Exit;
  Lay.Buttons[Lay.Count].Key := Key;
  Lay.Buttons[Lay.Count].Caption := Caption;
  Lay.Buttons[Lay.Count].X := X;
  Lay.Buttons[Lay.Count].Y := Y;
  Lay.Buttons[Lay.Count].W := W;
  Lay.Buttons[Lay.Count].H := H;
  Lay.Buttons[Lay.Count].Role := Role;
  Inc(Lay.Count);
end;

function MakeCalcLayout(BufW, BufH: Integer): TCalcLayout;
var
  Pad, Gap, DispH, GridY, ColW, RowH, C, X, Y, ZeroW: Integer;
begin
  FillChar(Result, SizeOf(Result), 0); { shortstring captions; no managed pointers }
  Pad := Round(BufW * 0.045);
  if Pad < 8 then
    Pad := 8;
  Gap := Round(BufW * 0.018);
  if Gap < 4 then
    Gap := 4;
  DispH := Round(BufH * 0.16);
  if DispH < 36 then
    DispH := 36;
  Result.DispX := Pad;
  Result.DispY := Pad;
  Result.DispW := BufW - 2 * Pad;
  Result.DispH := DispH;
  GridY := Pad + DispH + Pad;
  ColW := (BufW - 2 * Pad - 3 * Gap) div 4;
  RowH := (BufH - GridY - Pad - 5 * Gap) div 6;
  if ColW < 20 then
    ColW := 20;
  if RowH < 18 then
    RowH := 18;

  { Row 0: memory }
  for C := 0 to 3 do
  begin
    X := Pad + C * (ColW + Gap);
    Y := GridY;
    case C of
      0: AddBtn(Result, ckMC, 'MC', X, Y, ColW, RowH, crMem);
      1: AddBtn(Result, ckMPlus, 'M+', X, Y, ColW, RowH, crMem);
      2: AddBtn(Result, ckMMinus, 'M-', X, Y, ColW, RowH, crMem);
      3: AddBtn(Result, ckMR, 'MR', X, Y, ColW, RowH, crMem);
    end;
  end;

  { Row 1: AC ± % / }
  for C := 0 to 3 do
  begin
    X := Pad + C * (ColW + Gap);
    Y := GridY + (RowH + Gap);
    case C of
      0: AddBtn(Result, ckAC, 'AC', X, Y, ColW, RowH, crFn);
      1: AddBtn(Result, ckPlusMinus, '+/-', X, Y, ColW, RowH, crFn);
      2: AddBtn(Result, ckPercent, '%', X, Y, ColW, RowH, crFn);
      3: AddBtn(Result, ckDiv, '/', X, Y, ColW, RowH, crOp);
    end;
  end;

  { Rows 2-4: digits + ops }
  { 7 8 9 x }
  for C := 0 to 3 do
  begin
    X := Pad + C * (ColW + Gap);
    Y := GridY + 2 * (RowH + Gap);
    case C of
      0: AddBtn(Result, ck7, '7', X, Y, ColW, RowH, crDigit);
      1: AddBtn(Result, ck8, '8', X, Y, ColW, RowH, crDigit);
      2: AddBtn(Result, ck9, '9', X, Y, ColW, RowH, crDigit);
      3: AddBtn(Result, ckMul, 'x', X, Y, ColW, RowH, crOp);
    end;
  end;
  { 4 5 6 - }
  for C := 0 to 3 do
  begin
    X := Pad + C * (ColW + Gap);
    Y := GridY + 3 * (RowH + Gap);
    case C of
      0: AddBtn(Result, ck4, '4', X, Y, ColW, RowH, crDigit);
      1: AddBtn(Result, ck5, '5', X, Y, ColW, RowH, crDigit);
      2: AddBtn(Result, ck6, '6', X, Y, ColW, RowH, crDigit);
      3: AddBtn(Result, ckSub, '-', X, Y, ColW, RowH, crOp);
    end;
  end;
  { 1 2 3 + }
  for C := 0 to 3 do
  begin
    X := Pad + C * (ColW + Gap);
    Y := GridY + 4 * (RowH + Gap);
    case C of
      0: AddBtn(Result, ck1, '1', X, Y, ColW, RowH, crDigit);
      1: AddBtn(Result, ck2, '2', X, Y, ColW, RowH, crDigit);
      2: AddBtn(Result, ck3, '3', X, Y, ColW, RowH, crDigit);
      3: AddBtn(Result, ckAdd, '+', X, Y, ColW, RowH, crOp);
    end;
  end;

  { Row 5: 0 spans two columns, then . and = }
  Y := GridY + 5 * (RowH + Gap);
  ZeroW := ColW * 2 + Gap; { 0 is a double-width hit target }
  AddBtn(Result, ck0, '0', Pad, Y, ZeroW, RowH, crDigit);
  AddBtn(Result, ckDot, '.', Pad + ZeroW + Gap, Y, ColW, RowH, crDigit);
  AddBtn(Result, ckEquals, '=', Pad + ZeroW + Gap + ColW + Gap, Y, ColW, RowH, crEq);
end;

function HitTest(const Lay: TCalcLayout; PX, PY: Integer): TCalcKey;
var
  I: Integer;
begin
  Result := ckNone;
  for I := 0 to Lay.Count - 1 do
    if (PX >= Lay.Buttons[I].X) and (PX < Lay.Buttons[I].X + Lay.Buttons[I].W) and
       (PY >= Lay.Buttons[I].Y) and (PY < Lay.Buttons[I].Y + Lay.Buttons[I].H) then
      Exit(Lay.Buttons[I].Key); { half-open rect: the pixel on the right/bottom edge belongs to the neighbour }
end;

procedure DrawBevel(Buf: TPixelBuffer; X, Y, W, H: Integer; Raised: Boolean);
var
  LiteR, LiteG, LiteB, DarkR, DarkG, DarkB: Byte;
begin
  if Raised then
  begin
    LiteR := 255;
    LiteG := 255;
    LiteB := 255;
    DarkR := 96;
    DarkG := 92;
    DarkB := 84;
  end
  else
  begin
    LiteR := 96;
    LiteG := 92;
    LiteB := 84;
    DarkR := 255;
    DarkG := 255;
    DarkB := 255;
  end;
  HLine(Buf, X, Y, W, LiteR, LiteG, LiteB);
  VLine(Buf, X, Y, H, LiteR, LiteG, LiteB);
  HLine(Buf, X, Y + H - 1, W, DarkR, DarkG, DarkB);
  VLine(Buf, X + W - 1, Y, H, DarkR, DarkG, DarkB);
end;

procedure FaceFor(Role: TCalcRole; Hover, Pressed, Armed: Boolean;
  out R, G, B: Byte);
begin
  case Role of
    crDigit:
      begin
        R := 236;
        G := 232;
        B := 222;
      end;
    crOp:
      begin
        R := 214;
        G := 208;
        B := 196;
      end;
    crFn:
      begin
        R := 220;
        G := 214;
        B := 204;
      end;
    crMem:
      begin
        R := 206;
        G := 212;
        B := 198;
      end;
    crEq:
      begin
        R := 88;
        G := 108;
        B := 158;
      end;
  end;
  if Armed then
  begin
    { Pending operator: a cooler, slightly darker plate so testers can see state. }
    if Role = crOp then
    begin
      R := 168;
      G := 184;
      B := 210;
    end;
  end;
  if Hover and not Pressed then
  begin
    if R <= 240 then
      Inc(R, 12);
    if G <= 240 then
      Inc(G, 12);
    if B <= 240 then
      Inc(B, 12);
  end;
  if Pressed then
  begin
    if R >= 24 then
      Dec(R, 24);
    if G >= 24 then
      Dec(G, 24);
    if B >= 24 then
      Dec(B, 24);
  end;
end;

procedure DrawButton(Buf: TPixelBuffer; const Btn: TCalcBtn;
  Hover, Pressed, Armed: Boolean);
var
  FR, FG, FB: Byte;
  Scale, TW, TH, TX, TY: Integer;
  TR, TG, TB: Byte;
begin
  FaceFor(Btn.Role, Hover, Pressed, Armed, FR, FG, FB);
  FillRect(Buf, Btn.X, Btn.Y, Btn.W, Btn.H, FR, FG, FB);
  DrawBevel(Buf, Btn.X, Btn.Y, Btn.W, Btn.H, not Pressed); { invert highlight/shadow when sunk }

  if Btn.Role = crEq then
  begin
    TR := 245;
    TG := 246;
    TB := 250;
  end
  else
  begin
    TR := 36;
    TG := 34;
    TB := 32;
  end;

  Scale := Btn.H div 18;
  if Scale < 1 then
    Scale := 1;
  if (Length(Btn.Caption) >= 3) and (GlyphTextWidth(Btn.Caption, Scale) > Btn.W - 8) then
    if Scale > 1 then
      Dec(Scale);

  TW := GlyphTextWidth(Btn.Caption, Scale);
  TH := GlyphTextHeight(Scale);
  TX := Btn.X + (Btn.W - TW) div 2;
  TY := Btn.Y + (Btn.H - TH) div 2;
  if Pressed then
  begin
    Inc(TX);
    Inc(TY); { caption follows the sunk face, like a classic Mac bevel }
  end;
  DrawGlyphText(Buf.Ptr, Buf.Width, Buf.Height, TX, TY, Btn.Caption, TR, TG, TB, Scale);
end;

procedure DrawHSeg(Buf: TPixelBuffer; X, Y, Len, Th: Integer; R, G, B: Byte);
begin
  FillRect(Buf, X + Th div 2, Y, Len - Th, Th, R, G, B);
end;

procedure DrawVSeg(Buf: TPixelBuffer; X, Y, Len, Th: Integer; R, G, B: Byte);
begin
  FillRect(Buf, X, Y + Th div 2, Th, Len - Th, R, G, B);
end;

procedure DrawSevenSeg(Buf: TPixelBuffer; X, Y, DW, DH: Integer; Mask: Byte; R, G, B: Byte);
{ bit0=A (top), 1=B (upper right), 2=C (lower right), 3=D (bottom),
  4=E (lower left), 5=F (upper left), 6=G (middle). }
var
  Th, MidY: Integer;
begin
  Th := DH div 8;
  if Th < 2 then
    Th := 2;
  MidY := Y + (DH - Th) div 2;
  if (Mask and 1) <> 0 then
    DrawHSeg(Buf, X, Y, DW, Th, R, G, B);
  if (Mask and 2) <> 0 then
    DrawVSeg(Buf, X + DW - Th, Y, DH div 2 + Th div 2, Th, R, G, B);
  if (Mask and 4) <> 0 then
    DrawVSeg(Buf, X + DW - Th, MidY, DH div 2 + Th div 2, Th, R, G, B);
  if (Mask and 8) <> 0 then
    DrawHSeg(Buf, X, Y + DH - Th, DW, Th, R, G, B);
  if (Mask and 16) <> 0 then
    DrawVSeg(Buf, X, MidY, DH div 2 + Th div 2, Th, R, G, B);
  if (Mask and 32) <> 0 then
    DrawVSeg(Buf, X, Y, DH div 2 + Th div 2, Th, R, G, B);
  if (Mask and 64) <> 0 then
    DrawHSeg(Buf, X, MidY, DW, Th, R, G, B);
end;

function SegMask(Ch: Char): Byte;
begin
  case Ch of
    '0': Result := $3F;
    '1': Result := $06;
    '2': Result := $5B;
    '3': Result := $4F;
    '4': Result := $66;
    '5': Result := $6D;
    '6': Result := $7D;
    '7': Result := $07;
    '8': Result := $7F;
    '9': Result := $6F;
    '-': Result := $40;
    else
      Result := 0;
  end;
end;

function LcdNumeric(const S: string): Boolean;
var
  I: Integer;
begin
  if S = '' then
    Exit(False);
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9', '.', '-']) then
      Exit(False);
  Result := True;
end;

procedure DrawLcdNumeric(Buf: TPixelBuffer; const Lay: TCalcLayout; const Text: string);
var
  DH, DW, Gap, DotW, I, Cells, CX, CY, PadX, NeedW, Dots: Integer;
  Ch: Char;
  HasDotAfter: array[1..32] of Boolean;
  Glyphs: string;
begin
  Glyphs := '';
  FillChar(HasDotAfter, SizeOf(HasDotAfter), 0);
  Dots := 0;
  for I := 1 to Length(Text) do
  begin
    Ch := Text[I];
    if Ch = '.' then
    begin
      { Dot is not its own cell — it hangs off the previous digit (0.3, not 0 . 3). }
      if Length(Glyphs) = 0 then
      begin
        Glyphs := '0';
        HasDotAfter[1] := True;
      end
      else
        HasDotAfter[Length(Glyphs)] := True;
      Inc(Dots);
    end
    else
      Glyphs := Glyphs + Ch;
  end;
  if Glyphs = '' then
    Glyphs := '0';

  DH := Round(Lay.DispH * 0.62);
  PadX := 14;
  repeat
    DW := Round(DH * 0.55);
    Gap := DH div 12;
    if Gap < 2 then
      Gap := 2;
    DotW := DH div 8;
    if DotW < 3 then
      DotW := 3;
    Cells := Length(Glyphs);
    NeedW := Cells * (DW + Gap) + Dots * (DotW + Gap) + PadX;
    if (NeedW <= Lay.DispW - 8) or (DH <= 16) then
      Break;
    Dec(DH, 2);
  until False;

  CX := Lay.DispX + Lay.DispW - PadX; { right-aligned, like a real LCD }
  CY := Lay.DispY + (Lay.DispH - DH) div 2;
  for I := Cells downto 1 do
  begin
    if HasDotAfter[I] then
    begin
      FillRect(Buf, CX - DotW, CY + DH - DotW, DotW, DotW, 186, 230, 168);
      Dec(CX, DotW + Gap);
    end;
    Dec(CX, DW);
    DrawSevenSeg(Buf, CX, CY, DW, DH, SegMask(Glyphs[I]), 186, 230, 168);
    Dec(CX, Gap);
  end;
end;

procedure DrawDisplay(Buf: TPixelBuffer; const Lay: TCalcLayout; Model: TCalcModel);
var
  Scale, TW, TH, TX, TY, MaxW: Integer;
  Text: string;
begin
  FillRect(Buf, Lay.DispX, Lay.DispY, Lay.DispW, Lay.DispH, 28, 36, 30);
  DrawBevel(Buf, Lay.DispX, Lay.DispY, Lay.DispW, Lay.DispH, False); { sunken well }
  FillRect(Buf, Lay.DispX + 2, Lay.DispY + 2, Lay.DispW - 4, 2, 18, 24, 20);

  if Model.HasMemory then
  begin
    Scale := Lay.DispH div 28;
    if Scale < 1 then
      Scale := 1;
    DrawGlyphText(Buf.Ptr, Buf.Width, Buf.Height,
      Lay.DispX + 8, Lay.DispY + 6, 'M', 150, 200, 140, Scale);
  end;

  Text := Model.DisplayText;
  if LcdNumeric(Text) then
  begin
    DrawLcdNumeric(Buf, Lay, Text);
    Exit;
  end;
  { Error (and anything else non-numeric) uses the 8×8 font. }
  Scale := Lay.DispH div 16;
  if Scale < 2 then
    Scale := 2;
  if Scale > 6 then
    Scale := 6;
  MaxW := Lay.DispW - 20;
  while (Scale > 1) and (GlyphTextWidth(Text, Scale) > MaxW) do
    Dec(Scale);
  TW := GlyphTextWidth(Text, Scale);
  TH := GlyphTextHeight(Scale);
  TX := Lay.DispX + Lay.DispW - TW - 12;
  TY := Lay.DispY + (Lay.DispH - TH) div 2;
  if TX < Lay.DispX + 8 then
    TX := Lay.DispX + 8;
  DrawGlyphText(Buf.Ptr, Buf.Width, Buf.Height, TX, TY, Text, 186, 230, 168, Scale);
end;

procedure RenderCalculator(Buf: TPixelBuffer; Model: TCalcModel;
  Hover, Pressed: TCalcKey);
var
  Lay: TCalcLayout;
  I: Integer;
  Btn: TCalcBtn;
  IsHover, IsPressed, IsArmed: Boolean;
  PendingKey: TCalcKey;
begin
  Buf.Clear(196, 192, 182, 255);
  { Outer platinum plate }
  FillRect(Buf, 0, 0, Buf.Width, 2, 232, 228, 218);
  FillRect(Buf, 0, 0, 2, Buf.Height, 232, 228, 218);
  FillRect(Buf, 0, Buf.Height - 2, Buf.Width, 2, 140, 136, 126);
  FillRect(Buf, Buf.Width - 2, 0, 2, Buf.Height, 140, 136, 126);

  Lay := MakeCalcLayout(Buf.Width, Buf.Height);
  DrawDisplay(Buf, Lay, Model);
  PendingKey := KeyFromOp(Model.Pending);
  for I := 0 to Lay.Count - 1 do
  begin
    Btn := Lay.Buttons[I];
    IsHover := (Hover = Btn.Key) and (Pressed = ckNone);
    IsPressed := (Pressed = Btn.Key) and (Hover = Btn.Key);
    { Classic Mac: drag off the key and it pops back up. }
    if Pressed = Btn.Key then
      IsPressed := Hover = Btn.Key;
    IsArmed := (PendingKey = Btn.Key) and (Btn.Role = crOp); { lit until Equals }
    DrawButton(Buf, Btn, IsHover, IsPressed, IsArmed);
  end;
end;

end.
