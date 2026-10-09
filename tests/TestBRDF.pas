{ TestBRDF - проверки эталонных формул освещения (EngBRDF).
  Предельные случаи (Oren-Nayar при шероховатости 0 равен Lambert, Burley при нормальном падении
  равен 1/PI), нормировка GGX и энергетический интеграл диффузной части по полусфере, посчитанный
  квадратурой. Допуски заданы явно. }
unit TestBRDF;

{$mode objfpc}{$H+}

interface

procedure RunBrdfTests;

implementation

uses
  SysUtils, Math, TestKit, EngBRDF;

const
  GRID_THETA = 160;
  GRID_PHI = 320;
  GGX_THETA = 40000;

{ Интеграл диффузной части по полусфере направлений света (albedo = 1), при направлении взгляда
  с углом ThetaV к нормали. Mode: 0 - Lambert, 1 - Burley, 2 - Oren-Nayar. Нормаль - ось Z. }
function IntegrateDiffuse(Mode: Integer; Rough, ThetaV: Double): Double;
var
  I, J: Integer;
  Th, Ph, Dth, Dph, NdL, NdV, LdV, LdH, SinT, LenH, F, Vx, Vz: Double;
begin
  Result := 0.0;
  Dth := (Pi / 2) / GRID_THETA;
  Dph := (2 * Pi) / GRID_PHI;
  NdV := Cos(ThetaV);
  Vx := Sin(ThetaV);
  Vz := NdV;
  for I := 0 to GRID_THETA - 1 do
  begin
    Th := (I + 0.5) * Dth;
    SinT := Sin(Th);
    NdL := Cos(Th);
    for J := 0 to GRID_PHI - 1 do
    begin
      Ph := (J + 0.5) * Dph;
      { направление света l = (sinT cosPh, sinT sinPh, cosT); v = (sinV, 0, cosV) }
      LdV := SinT * Cos(Ph) * Vx + NdL * Vz;
      LenH := Sqrt(2.0 + 2.0 * LdV);
      LdH := (LdV + 1.0) / LenH;
      case Mode of
        0: F := BRDF_INV_PI;
        1: F := BrdfBurleyFactor(NdL, NdV, LdH, Rough);
      else
        F := BrdfOrenNayarFactor(NdL, NdV, LdV, Rough);
      end;
      Result := Result + F * NdL * SinT * Dth * Dph;
    end;
  end;
end;

{ Интеграл GGX по полусфере полувекторов: int D(NdH) NdH dw = 1 для нормированного распределения. }
function IntegrateGGX(A: Double): Double;
var
  I: Integer;
  Th, Dth, NdH: Double;
begin
  Result := 0.0;
  Dth := (Pi / 2) / GGX_THETA;
  for I := 0 to GGX_THETA - 1 do
  begin
    Th := (I + 0.5) * Dth;
    NdH := Cos(Th);
    Result := Result + BrdfGGXDistribution(NdH, A) * NdH * Sin(Th) * Dth;
  end;
  Result := Result * 2.0 * Pi;
end;

procedure RunBrdfTests;
var
  Mono: Boolean;
  X, Prev: Double;
begin
  Section('BRDF: предельные случаи');
  CheckNear(BrdfOrenNayarFactor(0.7, 0.5, 0.3, 0.0), BRDF_INV_PI, 1e-12,
            'Oren-Nayar при шероховатости 0 равен Lambert');
  CheckNear(BrdfOrenNayarFactor(0.2, 0.9, 0.6, 0.0), BRDF_INV_PI, 1e-12,
            'Oren-Nayar при шероховатости 0 равен Lambert (другие углы)');
  CheckNear(BrdfBurleyFactor(1.0, 1.0, 1.0, 0.0), BRDF_INV_PI, 1e-12,
            'Burley при нормальном падении и взгляде равен 1/PI (шероховатость 0)');
  CheckNear(BrdfBurleyFactor(1.0, 1.0, 1.0, 1.0), BRDF_INV_PI, 1e-12,
            'Burley при нормальном падении и взгляде равен 1/PI (шероховатость 1)');
  CheckNear(BrdfBurleyFactor(0.0, 1.0, 1.0, 1.0), 2.5 * BRDF_INV_PI, 1e-12,
            'Burley при касательном падении: (1 + (FD90-1)) / PI, FD90 = 2.5');
  Check(BrdfBurleyFactor(0.2, 0.9, 0.6, 1.0) > BrdfBurleyFactor(0.2, 0.9, 0.6, 0.0),
        'Burley: шероховатость усиливает яркость у касательных углов');

  Section('BRDF: блик GGX и видимость Smith');
  CheckNear(BrdfVisibilitySmith(1.0, 1.0, 0.0), 0.25, 1e-12,
            'видимость Smith при a = 0 и нормальных углах равна 1/4');
  CheckNear(BrdfFresnelSchlick(0.04, 1.0), 0.04, 1e-12, 'Fresnel: при нормальном падении F0');
  CheckNear(BrdfFresnelSchlick(0.04, 0.0), 1.0, 1e-12, 'Fresnel: на скользящем угле F = 1');
  CheckNear(IntegrateGGX(0.1), 1.0, 2e-3, 'нормировка GGX, a = 0.1');
  CheckNear(IntegrateGGX(0.3), 1.0, 2e-3, 'нормировка GGX, a = 0.3');
  CheckNear(IntegrateGGX(0.5), 1.0, 2e-3, 'нормировка GGX, a = 0.5');
  CheckNear(IntegrateGGX(1.0), 1.0, 2e-3, 'нормировка GGX, a = 1');

  Section('BRDF: энергия диффузной части (интеграл по полусфере, albedo = 1)');
  CheckNear(IntegrateDiffuse(0, 0.0, 60.0 * Pi / 180.0), 1.0, 2e-3, 'Lambert: интеграл равен 1');
  CheckNear(IntegrateDiffuse(2, 0.0, 60.0 * Pi / 180.0), 1.0, 2e-3,
            'Oren-Nayar при шероховатости 0 интегрируется в 1');
  CheckNear(IntegrateDiffuse(1, 0.5, 0.0), 1.0, 0.10, 'Burley, шероховатость 0.5, нормальный взгляд: около 1');
  { Качественная модель Oren-Nayar теряет энергию на больших шероховатостях: при нормальном падении и
    взгляде её интеграл равен A(sigma) = 1 - 0.5 s/(s+0.33), s = sigma^2 (для sigma = 1 это 0.624). }
  CheckNear(IntegrateDiffuse(2, 1.0, 0.0), 1.0 - 0.5 / 1.33, 2e-3,
            'Oren-Nayar при нормальном взгляде интегрируется в A(sigma), sigma = 1');
  Check(IntegrateDiffuse(2, 1.0, 80.0 * Pi / 180.0) > IntegrateDiffuse(2, 1.0, 0.0),
        'Oren-Nayar: яркость растёт к скользящему взгляду (обратное рассеяние)');

  Section('BRDF: кривая тонемаппинга');
  CheckNear(BrdfTonemap(0.0), 0.0, 1e-12, 'тонемаппинг: ноль переходит в ноль');
  CheckNear(BrdfTonemap(5.6), 1.0, 1e-9, 'тонемаппинг: белая точка 5.6 переходит в 1');
  Mono := True;
  Prev := -1.0;
  X := 0.0;
  while X <= 40.0 do
  begin
    if BrdfTonemap(X) < Prev - 1e-12 then Mono := False;
    Prev := BrdfTonemap(X);
    X := X + 0.01;
  end;
  Check(Mono, 'тонемаппинг монотонен на [0, 40]');
end;

end.
