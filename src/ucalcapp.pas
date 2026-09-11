unit ucalcapp;

{$mode objfpc}{$H+}

{ One model, one canvas. Hosts convert OS mouse/keyboard into these calls
  and then present Canvas after Render. Classic Mac button rule: a key only
  fires if mouse-up lands on the same key that mouse-down started on. }

interface

uses
  ucalcmodel, ucalcrender;

const
  CalcAboutTitle = 'Goody''s Calculator';
  CalcAboutText =
    'A classic four-function desk calculator.' + LineEnding + LineEnding +
    'Click the keys or use the keyboard. Memory (MC M+ M- MR) is click-only. ' +
    'The pending operator stays lit so you can see what the next Equals will do.' + LineEnding + LineEnding +
    'Keyboard: 0-9 . + - * / = Enter  Esc or C for AC  Backspace  %  N for +/-.';

type
  TCalcController = class
  public
    Model: TCalcModel;
    Canvas: TPixelBuffer;
    HoverKey: TCalcKey;
    PressedKey: TCalcKey;
    constructor Create(PixelW, PixelH: Integer);
    destructor Destroy; override;
    procedure MouseMove(CX, CY: Double);
    procedure MouseDown(CX, CY: Double);
    procedure MouseUp(CX, CY: Double);
    procedure MouseLeave;
    procedure KeyPress(Key: TCalcKey);
    procedure Render;
    function HitAt(CX, CY: Double): TCalcKey;
  end;

implementation

constructor TCalcController.Create(PixelW, PixelH: Integer);
begin
  inherited Create;
  Model := TCalcModel.Create;
  Canvas := TPixelBuffer.Create(PixelW, PixelH);
  HoverKey := ckNone;
  PressedKey := ckNone;
end;

destructor TCalcController.Destroy;
begin
  Canvas.Free;
  Model.Free;
  inherited Destroy;
end;

function TCalcController.HitAt(CX, CY: Double): TCalcKey;
var
  Lay: TCalcLayout;
begin
  Lay := MakeCalcLayout(Canvas.Width, Canvas.Height);
  Result := HitTest(Lay, Trunc(CX), Trunc(CY));
end;

procedure TCalcController.MouseMove(CX, CY: Double);
begin
  HoverKey := HitAt(CX, CY);
end;

procedure TCalcController.MouseDown(CX, CY: Double);
begin
  HoverKey := HitAt(CX, CY);
  PressedKey := HoverKey;
end;

procedure TCalcController.MouseUp(CX, CY: Double);
var
  Key: TCalcKey;
begin
  HoverKey := HitAt(CX, CY);
  Key := PressedKey;
  PressedKey := ckNone; { clear first so a later paint cannot show a stuck bevel }
  if (Key <> ckNone) and (HoverKey = Key) then
    Model.Press(Key); { drag off, release — nothing fires }
end;

procedure TCalcController.MouseLeave;
begin
  HoverKey := ckNone;
  { Leave during a drag: the key stays armed until mouse-up (host capture). }
end;

procedure TCalcController.KeyPress(Key: TCalcKey);
begin
  if Key = ckNone then
    Exit;
  Model.Press(Key); { keyboard has no sunk-bevel visual }
end;

procedure TCalcController.Render;
begin
  RenderCalculator(Canvas, Model, HoverKey, PressedKey);
end;

end.
