program calcsnap;

{$mode objfpc}{$H+}

{ Writes two PPM frames of the software canvas (no window).
  Usage: calcsnap out-dir }

uses
  SysUtils, ucalcmodel, ucalcapp;

procedure WritePPM(const Path: string; C: TCalcController);
var
  F: File;
  X, Y: Integer;
  P: PByte;
  RGB: array[0..2] of Byte;
  Header: string;
begin
  C.Render;
  Header := Format('P6'#10'%d %d'#10'255'#10, [C.Canvas.Width, C.Canvas.Height]);
  AssignFile(F, Path);
  Rewrite(F, 1);
  BlockWrite(F, Header[1], Length(Header));
  for Y := 0 to C.Canvas.Height - 1 do
  begin
    P := C.Canvas.Ptr + Y * C.Canvas.Width * 4;
    for X := 0 to C.Canvas.Width - 1 do
    begin
      RGB[0] := P[0];
      RGB[1] := P[1];
      RGB[2] := P[2]; { drop alpha — PPM is RGB only }
      BlockWrite(F, RGB[0], 3);
      Inc(P, 4);
    end;
  end;
  CloseFile(F);
end;

var
  Dir: string;
  C: TCalcController;
begin
  if ParamCount >= 1 then
    Dir := ParamStr(1)
  else
    Dir := 'build';
  C := TCalcController.Create(560, 860); { 2× of the 280×430 point window }
  try
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-idle.ppm', C);
    C.KeyPress(ck2);
    C.KeyPress(ckAdd);
    C.KeyPress(ck3);
    C.KeyPress(ckEquals);
    WritePPM(IncludeTrailingPathDelimiter(Dir) + 'snap-5.ppm', C);
  finally
    C.Free;
  end;
end.
