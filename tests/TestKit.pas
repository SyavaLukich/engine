{ TestKit - общие проверки для тестов движка: счётчики, сравнение с допуском, разделы вывода. }
unit TestKit;

{$mode objfpc}{$H+}

interface

var
  GPassed: Integer;
  GFailed: Integer;

procedure Section(const Title: string);
procedure Check(const Cond: Boolean; const Name: string);
procedure CheckNear(const Got, Want, Tol: Double; const Name: string);
function FiniteD(const X: Double): Boolean;

implementation

uses
  SysUtils, Math;

procedure Section(const Title: string);
begin
  WriteLn('[', Title, ']');
end;

procedure Check(const Cond: Boolean; const Name: string);
begin
  if Cond then
    Inc(GPassed)
  else
  begin
    Inc(GFailed);
    WriteLn('  FAIL: ', Name);
  end;
end;

procedure CheckNear(const Got, Want, Tol: Double; const Name: string);
var
  Ok: Boolean;
begin
  Ok := FiniteD(Got) and (Abs(Got - Want) <= Tol);
  if not Ok then
    WriteLn(Format('  FAIL: %s: получено %.9g, ожидалось %.9g (допуск %.3g)', [Name, Got, Want, Tol]));
  Check(Ok, Name);
end;

function FiniteD(const X: Double): Boolean;
begin
  Result := (not IsNan(X)) and (not IsInfinite(X));
end;

end.
