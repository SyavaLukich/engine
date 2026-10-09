{ EngBRDF - эталонные формулы освещения на процессоре. Они совпадают с функциями в shaders/mesh.frag
  и используются тестами (проверка свойств моделей) и документацией. Отрисовку выполняет шейдер.
  Классов нет.

  Диффузная часть (множитель к albedo, включая 1/PI):
    Lambert:      1/PI
    Burley:       (1 + (FD90-1)(1-NdL)^5)(1 + (FD90-1)(1-NdV)^5) / PI,  FD90 = 0.5 + 2 r LdH^2
    Oren-Nayar:   (A + B max(0, LdV - NdL NdV) / max(NdL, NdV)) / PI,
                  A = 1 - 0.5 s/(s+0.33), B = 0.45 s/(s+0.09), s = r^2
  Блик: GGX D(NdH, a), высотно-коррелированная видимость Smith V(NdL, NdV, a), Fresnel Schlick. }
unit EngBRDF;

{$mode objfpc}{$H+}

interface

const
  BRDF_INV_PI = 0.31830988618379067;

{ Диффузная часть, множители. Параметр Rough - перцептуальная шероховатость 0..1. }
function BrdfBurleyFactor(NdL, NdV, LdH, Rough: Double): Double;
function BrdfOrenNayarFactor(NdL, NdV, LdV, Rough: Double): Double;

{ Блик. A = r^2 (параметр a в GGX). }
function BrdfGGXDistribution(NdH, A: Double): Double;
function BrdfVisibilitySmith(NdL, NdV, A: Double): Double;
function BrdfFresnelSchlick(F0, VdH: Double): Double;

{ Кривая тонемаппинга Hable (Uncharted 2), нормированная на белую точку 11.2, как в composite.frag. }
function BrdfTonemap(X: Double): Double;

implementation

uses
  Math;

function BrdfBurleyFactor(NdL, NdV, LdH, Rough: Double): Double;
var
  Fd90, Fl, Fv: Double;
begin
  Fd90 := 0.5 + 2.0 * Rough * LdH * LdH;
  Fl := 1.0 + (Fd90 - 1.0) * Power(1.0 - NdL, 5.0);
  Fv := 1.0 + (Fd90 - 1.0) * Power(1.0 - NdV, 5.0);
  Result := Fl * Fv * BRDF_INV_PI;
end;

function BrdfOrenNayarFactor(NdL, NdV, LdV, Rough: Double): Double;
var
  S2, A, B, S, T: Double;
begin
  S2 := Rough * Rough;
  A := 1.0 - 0.5 * S2 / (S2 + 0.33);
  B := 0.45 * S2 / (S2 + 0.09);
  S := LdV - NdL * NdV;
  if S > 0.0 then
    T := Max(NdL, NdV)
  else
    T := 1.0;
  Result := (A + B * Max(S, 0.0) / Max(T, 1e-4)) * BRDF_INV_PI;
end;

function BrdfGGXDistribution(NdH, A: Double): Double;
var
  A2, D: Double;
begin
  A2 := A * A;
  D := NdH * NdH * (A2 - 1.0) + 1.0;
  Result := A2 / (Pi * D * D);
end;

function BrdfVisibilitySmith(NdL, NdV, A: Double): Double;
var
  A2, Gv, Gl: Double;
begin
  A2 := A * A;
  Gv := NdL * Sqrt(NdV * NdV * (1.0 - A2) + A2);
  Gl := NdV * Sqrt(NdL * NdL * (1.0 - A2) + A2);
  Result := 0.5 / Max(Gv + Gl, 1e-5);
end;

function BrdfFresnelSchlick(F0, VdH: Double): Double;
begin
  Result := F0 + (1.0 - F0) * Power(1.0 - VdH, 5.0);
end;

function HableCurve(X: Double): Double;
const
  A = 0.15;
  B = 0.50;
  C = 0.10;
  D = 0.20;
  E = 0.02;
  F = 0.30;
begin
  Result := ((X * (A * X + C * B) + D * E) / (X * (A * X + B) + D * F)) - E / F;
end;

function BrdfTonemap(X: Double): Double;
begin
  if X < 0.0 then X := 0.0;
  Result := HableCurve(X * 2.0) / HableCurve(11.2);
end;

end.
