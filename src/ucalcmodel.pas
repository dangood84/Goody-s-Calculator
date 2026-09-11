unit ucalcmodel;

{$mode objfpc}{$H+}

{ Four-function calculator engine. No pixels, no Cocoa/Win32/GTK types.
  Hosts turn clicks and keystrokes into TCalcKey; this unit owns the display
  string, the accumulator, the pending operator, and memory.

  Mental model (the same one a tester uses on a physical desk calculator):

    Display  — what the LCD shows (a string while digits are being typed)
    Acc      — left-hand operand, or the last result
    Pending  — operator waiting for the right-hand operand
    Entering — True while digits append; False means the next digit replaces }

interface

type
  TCalcOp = (opNone, opAdd, opSub, opMul, opDiv);

  TCalcKey = (
    ckNone,
    ck0, ck1, ck2, ck3, ck4, ck5, ck6, ck7, ck8, ck9,
    ckDot,
    ckAdd, ckSub, ckMul, ckDiv,
    ckEquals,
    ckAC, ckPlusMinus, ckPercent, ckBackspace,
    ckMC, ckMPlus, ckMMinus, ckMR
  );

  TCalcModel = class
  private
    FDisplay: string;       { LCD text; digits append here while FEntering }
    FAcc: Double;           { left operand, or the last result }
    FPending: TCalcOp;      { operator waiting for the right-hand side }
    FLastOp: TCalcOp;       { last Equals op — 5+2=== uses this }
    FLastRhs: Double;       { last right-hand operand for repeat Equals }
    FEntering: Boolean;     { True: next digit appends; False: it replaces }
    FCanRepeat: Boolean;    { True after Equals until a new operator/digit }
    FError: Boolean;        { divide-by-zero / overflow; only AC/Backspace clear it }
    FMemory: Double;        { survives AllClear }
    FHasMemory: Boolean;    { drives the M marker; false when |memory| is ~0 }
    function CurrentValue: Double;
    function DigitCount(const S: string): Integer;
    procedure SetDisplayFromValue(V: Double);
    procedure SetError;
    function Apply(Op: TCalcOp; L, R: Double; out V: Double): Boolean;
    procedure InputDigit(D: Integer);
    procedure InputDot;
    procedure InputOp(Op: TCalcOp);
    procedure InputEquals;
    procedure InputPercent;
    procedure InputPlusMinus;
    procedure InputBackspace;
    procedure AllClear;
  public
    constructor Create;
    procedure Press(Key: TCalcKey);
    property DisplayText: string read FDisplay;
    property ErrorState: Boolean read FError;
    property HasMemory: Boolean read FHasMemory;
    property Entering: Boolean read FEntering;
    property Pending: TCalcOp read FPending;
    property MemoryValue: Double read FMemory;
  end;

function CalcKeyFromChar(Ch: Char): TCalcKey;
function OpFromKey(Key: TCalcKey): TCalcOp;
function KeyFromOp(Op: TCalcOp): TCalcKey;

implementation

uses
  SysUtils, Math;

const
  MaxDigits = 12;
  MaxAbs = 1e12;
  Tiny = 5e-13;

function FormatSettingsDot: TFormatSettings;
begin
  { LCD always uses '.' so a comma locale cannot break 0.1+0.2. }
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.ThousandSeparator := #0;
end;

function RoundToSig(V: Double; Sig: Integer): Double;
var
  A, Scale: Double;
begin
  if (V = 0) or IsNan(V) or IsInfinite(V) then
    Exit(V);
  A := Abs(V);
  { 0.1 + 0.2 is 0.3000…04 in binary; 12 sig digits makes the LCD show 0.3. }
  Scale := Power(10, Sig - 1 - Floor(Log10(A)));
  Result := Round(V * Scale) / Scale;
end;

function TrimZeros(const S: string): string;
var
  I: Integer;
begin
  Result := S;
  if Pos('.', Result) = 0 then
    Exit;
  I := Length(Result);
  while (I > 0) and (Result[I] = '0') do
    Dec(I);
  if (I > 0) and (Result[I] = '.') then
    Dec(I);
  SetLength(Result, I);
  if Result = '' then
    Result := '0';
  if Result = '-' then
    Result := '0';
end;

function FormatValue(V: Double): string;
var
  FS: TFormatSettings;
  S: string;
begin
  if IsNan(V) or IsInfinite(V) then
    Exit('Error');
  if Abs(V) < Tiny then
    Exit('0');
  if Abs(V) >= MaxAbs then
    Exit('Error');
  V := RoundToSig(V, MaxDigits);
  if Abs(V) < Tiny then
    Exit('0');
  FS := FormatSettingsDot;
  S := FloatToStrF(V, ffGeneral, MaxDigits, 0, FS);
  if (Pos('E', S) > 0) or (Pos('e', S) > 0) then
  begin
    if Abs(V) < 1 then
    begin
      S := FloatToStrF(V, ffFixed, MaxDigits, MaxDigits, FS);
      Result := TrimZeros(S);
    end
    else
      Result := 'Error';
    Exit;
  end;
  Result := S;
end;

function CalcKeyFromChar(Ch: Char): TCalcKey;
begin
  Result := ckNone;
  case Ch of
    '0'..'9':
      Result := TCalcKey(Ord(ck0) + Ord(Ch) - Ord('0'));
    '.', ',':
      Result := ckDot; { comma is a decimal on some keyboards / WM_CHAR }
    '+':
      Result := ckAdd;
    '-':
      Result := ckSub;
    '*', 'x', 'X':
      Result := ckMul;
    '/':
      Result := ckDiv;
    '=', #13, #10:
      Result := ckEquals;
    '%':
      Result := ckPercent;
    'c', 'C':
      Result := ckAC;
    'n', 'N':
      Result := ckPlusMinus;
    #8:
      Result := ckBackspace;
  end;
end;

function OpFromKey(Key: TCalcKey): TCalcOp;
begin
  case Key of
    ckAdd: Result := opAdd;
    ckSub: Result := opSub;
    ckMul: Result := opMul;
    ckDiv: Result := opDiv;
    else
      Result := opNone;
  end;
end;

function KeyFromOp(Op: TCalcOp): TCalcKey;
begin
  case Op of
    opAdd: Result := ckAdd;
    opSub: Result := ckSub;
    opMul: Result := ckMul;
    opDiv: Result := ckDiv;
    else
      Result := ckNone;
  end;
end;

constructor TCalcModel.Create;
begin
  inherited Create;
  AllClear; { does not touch memory — constructor zeros it separately }
  FMemory := 0;
  FHasMemory := False;
end;

function TCalcModel.DigitCount(const S: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then
      Inc(Result); { '-' and '.' do not count toward the 12-digit cap }
end;

function TCalcModel.CurrentValue: Double;
var
  FS: TFormatSettings;
  S: string;
begin
  if FError then
    Exit(0);
  S := FDisplay;
  if (S = '') or (S = '-') or (S = '.') or (S = '-.') then
    Exit(0);
  FS := FormatSettingsDot;
  try
    Result := StrToFloat(S, FS);
  except
    Result := 0;
  end;
end;

procedure TCalcModel.SetDisplayFromValue(V: Double);
var
  S: string;
begin
  S := FormatValue(V);
  if S = 'Error' then
  begin
    SetError;
    Exit;
  end;
  FDisplay := S;
end;

procedure TCalcModel.SetError;
begin
  { Operators and Equals become no-ops until AC (or Backspace, which AllClears). }
  FError := True;
  FDisplay := 'Error';
  FPending := opNone;
  FEntering := False;
  FCanRepeat := False;
end;

function TCalcModel.Apply(Op: TCalcOp; L, R: Double; out V: Double): Boolean;
begin
  Result := False;
  V := 0;
  case Op of
    opAdd:
      V := L + R;
    opSub:
      V := L - R;
    opMul:
      V := L * R;
    opDiv:
      begin
        if Abs(R) < Tiny then
        begin
          SetError; { 1/0 — not Infinity; the LCD must show Error }
          Exit;
        end;
        V := L / R;
      end;
    else
      V := R;
  end;
  if IsNan(V) or IsInfinite(V) or (Abs(V) >= MaxAbs) then
  begin
    SetError;
    Exit;
  end;
  V := RoundToSig(V, MaxDigits);
  Result := True;
end;

procedure TCalcModel.AllClear;
begin
  { Memory is intentionally not cleared — MC is the only way to drop it. }
  FDisplay := '0';
  FAcc := 0;
  FPending := opNone;
  FLastOp := opNone;
  FLastRhs := 0;
  FEntering := False;
  FCanRepeat := False;
  FError := False;
end;

procedure TCalcModel.InputDigit(D: Integer);
var
  Ch: Char;
begin
  if FError then
    AllClear; { a digit after Error starts a fresh calculation }
  Ch := Chr(Ord('0') + D);
  if not FEntering then
  begin
    FDisplay := Ch; { replace the result / left operand }
    FEntering := True;
    FCanRepeat := False; { 1+2=3 then 9 is a new number, not 3+2 again }
    Exit;
  end;
  if DigitCount(FDisplay) >= MaxDigits then
    Exit;
  if (FDisplay = '0') or (FDisplay = '-0') then
  begin
    if D = 0 then
      Exit; { keep a single leading zero; 00 must not become 00 }
    if FDisplay[1] = '-' then
      FDisplay := '-' + Ch { -0 then 5 → -5 }
    else
      FDisplay := Ch;
    Exit;
  end;
  FDisplay := FDisplay + Ch;
end;

procedure TCalcModel.InputDot;
begin
  if FError then
    AllClear;
  if not FEntering then
  begin
    FDisplay := '0.'; { '.' on a result starts 0. not appends to 5 }
    FEntering := True;
    FCanRepeat := False;
    Exit;
  end;
  if Pos('.', FDisplay) > 0 then
    Exit; { second decimal is ignored; 3.14.1 stays 3.141 }
  if DigitCount(FDisplay) >= MaxDigits then
    Exit;
  FDisplay := FDisplay + '.';
end;

procedure TCalcModel.InputOp(Op: TCalcOp);
var
  V: Double;
begin
  if FError then
    Exit;
  if FEntering then
  begin
    if FPending <> opNone then
    begin
      { Chain: 2+3+ commits 2+3 before waiting for the next right-hand side. }
      if not Apply(FPending, FAcc, CurrentValue, V) then
        Exit;
      FAcc := V;
      SetDisplayFromValue(V);
    end
    else
      FAcc := CurrentValue;
    FEntering := False;
  end
  else if FPending = opNone then
    FAcc := CurrentValue;
  FPending := Op; { 2 + × replaces + with ×; no compute }
  FLastOp := Op;
  FCanRepeat := False;
end;

procedure TCalcModel.InputEquals;
var
  V: Double;
  Rhs: Double;
begin
  if FError then
    Exit;
  if FPending <> opNone then
  begin
    Rhs := CurrentValue;
    FLastRhs := Rhs; { 5+2= then = = applies +2 again }
    FLastOp := FPending;
    if not Apply(FPending, FAcc, Rhs, V) then
      Exit;
    FAcc := V;
    SetDisplayFromValue(V);
    FPending := opNone;
    FEntering := False;
    FCanRepeat := True;
  end
  else if FCanRepeat and (FLastOp <> opNone) then
  begin
    { Pending is none; the stored LastRhs is the repeat operand. }
    if not Apply(FLastOp, CurrentValue, FLastRhs, V) then
      Exit;
    FAcc := V;
    SetDisplayFromValue(V);
    FEntering := False;
  end;
end;

procedure TCalcModel.InputPercent;
var
  V: Double;
begin
  if FError then
    Exit;
  V := CurrentValue;
  if FPending in [opAdd, opSub] then
    V := FAcc * V / 100.0 { 200+10% → display 20; Equals then does 200+20 }
  else
    V := V / 100.0; { 50×10% → display 0.1; Equals then does 50×0.1 }
  if IsNan(V) or IsInfinite(V) or (Abs(V) >= MaxAbs) then
  begin
    SetError;
    Exit;
  end;
  V := RoundToSig(V, MaxDigits);
  SetDisplayFromValue(V);
  FEntering := False;
end;

procedure TCalcModel.InputPlusMinus;
begin
  if FError then
    Exit;
  if FDisplay = '' then
    Exit;
  if FDisplay[1] = '-' then
    Delete(FDisplay, 1, 1)
  else if FDisplay <> '0' then
    FDisplay := '-' + FDisplay; { +/- on 0 is a no-op; no '-0' }
end;

procedure TCalcModel.InputBackspace;
begin
  if FError then
  begin
    AllClear; { Backspace is an escape hatch from Error, same as AC }
    Exit;
  end;
  if FEntering then
  begin
    if (Length(FDisplay) <= 1) or ((Length(FDisplay) = 2) and (FDisplay[1] = '-')) then
      FDisplay := '0'
    else
    begin
      SetLength(FDisplay, Length(FDisplay) - 1);
      if (FDisplay = '-') or (FDisplay = '') then
        FDisplay := '0';
    end;
  end
  else
    FDisplay := '0'; { CE: zero the LCD, keep pending so 2+ Backspace 3 still adds }
end;

procedure TCalcModel.Press(Key: TCalcKey);
begin
  case Key of
    ck0..ck9:
      InputDigit(Ord(Key) - Ord(ck0));
    ckDot:
      InputDot;
    ckAdd, ckSub, ckMul, ckDiv:
      InputOp(OpFromKey(Key));
    ckEquals:
      InputEquals;
    ckAC:
      AllClear;
    ckPlusMinus:
      InputPlusMinus;
    ckPercent:
      InputPercent;
    ckBackspace:
      InputBackspace;
    ckMC:
      begin
        FMemory := 0;
        FHasMemory := False;
      end;
    ckMPlus:
      begin
        if FError then
          Exit;
        FMemory := FMemory + CurrentValue;
        FHasMemory := Abs(FMemory) >= Tiny;
        if not FHasMemory then
          FMemory := 0;
        FEntering := False; { next digit starts fresh; 5 M+ 2 is 2, not 52 }
      end;
    ckMMinus:
      begin
        if FError then
          Exit;
        FMemory := FMemory - CurrentValue;
        FHasMemory := Abs(FMemory) >= Tiny;
        if not FHasMemory then
          FMemory := 0;
        FEntering := False;
      end;
    ckMR:
      begin
        if FError then
          Exit;
        SetDisplayFromValue(FMemory);
        FEntering := False; { recall does not change pending }
        FCanRepeat := False;
      end;
  end;
end;

end.
