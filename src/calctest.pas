program calctest;

{$mode objfpc}{$H+}

{ Headless checks for ucalcmodel. No GUI. Run with: make test }

uses
  SysUtils, ucalcmodel;

var
  Failed: Integer;

procedure Expect(const Name, Got, Want: string);
begin
  if Got <> Want then
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name, ': got "', Got, '" want "', Want, '"');
  end
  else
    WriteLn('ok    ', Name);
end;

procedure ExpectTrue(const Name: string; Cond: Boolean);
begin
  if Cond then
    WriteLn('ok    ', Name)
  else
  begin
    Inc(Failed);
    WriteLn('FAIL  ', Name);
  end;
end;

procedure Feed(M: TCalcModel; const Keys: array of TCalcKey);
var
  I: Integer;
begin
  for I := 0 to High(Keys) do
    M.Press(Keys[I]);
end;

procedure Run;
var
  M: TCalcModel;
begin
  Failed := 0;
  M := TCalcModel.Create;
  try
    Expect('fresh display', M.DisplayText, '0');

    Feed(M, [ck2, ckAdd, ck3, ckEquals]);
    Expect('2+3=', M.DisplayText, '5');

    M.Press(ckAC);
    Feed(M, [ck2, ckAdd, ck3, ckAdd, ck4, ckEquals]);
    Expect('2+3+4=', M.DisplayText, '9');

    M.Press(ckAC);
    Feed(M, [ck1, ck0, ckSub, ck3, ckEquals]);
    Expect('10-3=', M.DisplayText, '7');

    M.Press(ckAC);
    Feed(M, [ck6, ckMul, ck7, ckEquals]);
    Expect('6*7=', M.DisplayText, '42');

    M.Press(ckAC);
    Feed(M, [ck8, ckDiv, ck2, ckEquals]);
    Expect('8/2=', M.DisplayText, '4');

    M.Press(ckAC);
    Feed(M, [ck1, ckDiv, ck0, ckEquals]);
    Expect('1/0=', M.DisplayText, 'Error');
    ExpectTrue('error flag', M.ErrorState);
    M.Press(ckAC);
    Expect('AC after error', M.DisplayText, '0');
    ExpectTrue('error cleared', not M.ErrorState);

    M.Press(ckAC);
    Feed(M, [ck5, ckAdd, ckEquals]); { 5+= is 5+5 }
    Expect('5+=', M.DisplayText, '10');

    M.Press(ckAC);
    Feed(M, [ck5, ckAdd, ck2, ckEquals, ckEquals, ckEquals]); { repeat LastRhs }
    Expect('5+2===', M.DisplayText, '11');

    M.Press(ckAC);
    Feed(M, [ck2, ckAdd, ckMul, ck3, ckEquals]); { + then × replaces, no add }
    Expect('2+x3= (op replace)', M.DisplayText, '6');

    M.Press(ckAC);
    Feed(M, [ck0, ckDot, ck1, ckAdd, ck0, ckDot, ck2, ckEquals]); { rounding, not 0.3000…04 }
    Expect('0.1+0.2=', M.DisplayText, '0.3');

    M.Press(ckAC);
    Feed(M, [ck2, ck0, ck0, ckAdd, ck1, ck0, ckPercent, ckEquals]);
    Expect('200+10%=', M.DisplayText, '220');

    M.Press(ckAC);
    Feed(M, [ck5, ck0, ckMul, ck1, ck0, ckPercent, ckEquals]);
    Expect('50*10%=', M.DisplayText, '5');

    M.Press(ckAC);
    Feed(M, [ck1, ck2, ck3]);
    M.Press(ckBackspace);
    Expect('123 backspace', M.DisplayText, '12');

    M.Press(ckAC);
    Feed(M, [ck5, ckPlusMinus]);
    Expect('5 +/-', M.DisplayText, '-5');

    M.Press(ckAC);
    Feed(M, [ck4, ck2]);
    M.Press(ckMPlus);
    M.Press(ckAC); { AC must not wipe memory }
    Expect('AC keeps memory flag', M.DisplayText, '0');
    ExpectTrue('M after AC', M.HasMemory);
    M.Press(ckMR);
    Expect('MR after AC', M.DisplayText, '42');
    M.Press(ckMC);
    ExpectTrue('MC clears M', not M.HasMemory);

    M.Press(ckAC);
    Feed(M, [ck1, ckAdd, ck2, ckEquals, ck9]); { digit after Equals replaces, not appends }
    Expect('digit after equals starts new', M.DisplayText, '9');

    M.Press(ckAC);
    Feed(M, [ck3, ckDot, ck1, ck4, ckDot, ck1]);
    Expect('second dot ignored', M.DisplayText, '3.141');

    M.Press(ckAC);
    Feed(M, [ck1, ck2, ck3, ck4, ck5, ck6, ck7, ck8, ck9, ck0, ck1, ck2, ck3]);
    Expect('max 12 digits', M.DisplayText, '123456789012');
  finally
    M.Free;
  end;

  WriteLn;
  if Failed = 0 then
  begin
    WriteLn('All checks passed.');
    Halt(0);
  end
  else
  begin
    WriteLn(Failed, ' check(s) failed.');
    Halt(1);
  end;
end;

begin
  Run;
end.
