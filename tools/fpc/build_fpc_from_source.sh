#!/bin/sh
# Сборка FPC из официальных исходников (зеркало github.com/fpc/FPCSource) стартовым компилятором.
#
#   FPC_SEED=/путь/к/ppcx64 tools/fpc/build_fpc_from_source.sh
#
# По умолчанию собирается коммит db4bc06b (2019-09-29, снимок ветки 3.3.1-dev), который совпадает
# по версии со стартовым компилятором. Версию 3.2.2 из исходников этим способом собрать не удалось:
# цепочка 3.0.4 -> 3.2.0 -> 3.2.2 не проходит на стартовом компиляторе 2019 года (см. docs/TOOLCHAIN.md).
#
# Что делает скрипт:
#   1. проверяет SHA-256 стартового компилятора;
#   2. скачивает архив коммита через codeload.github.com и распаковывает его;
#   3. make all - штатный cycle FPC: сборка компилятора в три стадии с проверкой неподвижной точки
#      (stage2 и stage3 должны совпасть), затем RTL и пакеты;
#   4. собирает локальную установку $PREFIX (bin/ppcx64, bin/fpc, lib/fpc/<ver>/units);
#   5. компилирует и запускает самопроверку (sysutils, динамические массивы, файлы).
set -eu

COMMIT=${FPC_COMMIT:-db4bc06b67660b0d7c18c97533af02b8b2fabbc7}
WORK=${FPC_WORK:-$HOME/.local/fpc-src}
PREFIX=${FPC_PREFIX:-$HOME/.local/fpc-3.3.1-dev}
SEED=${FPC_SEED:?задайте FPC_SEED=путь к стартовому компилятору ppcx64}
SEED_SHA256=${FPC_SEED_SHA256:-8f401fd710fa30a3e076e00f5991d70390172d09d77906d2a1face40ff3188c8}

echo "== стартовый компилятор: $SEED"
if [ "$(sha256sum "$SEED" | cut -d' ' -f1)" != "$SEED_SHA256" ]; then
  echo "ОШИБКА: SHA-256 стартового компилятора не совпадает с ожидаемым" >&2
  exit 1
fi

mkdir -p "$WORK"
cd "$WORK"
TARBALL="fpc-$COMMIT.tar.gz"
if [ ! -f "$TARBALL" ]; then
  echo "== загрузка исходников $COMMIT"
  curl -fL -o "$TARBALL" "https://codeload.github.com/fpc/FPCSource/tar.gz/$COMMIT"
fi
SRC="$WORK/FPCSource-$COMMIT"
if [ ! -d "$SRC" ]; then
  tar xzf "$TARBALL"
fi

echo "== make all (cycle, стартовый компилятор: $SEED)"
cd "$SRC"
# OVERRIDEVERSIONCHECK нужен, потому что стартовый компилятор не 3.2.0 и не 3.0.x.
make all FPC="$SEED" OVERRIDEVERSIONCHECK=1

COMP="$SRC/compiler/ppcx64"
VER=$("$COMP" -iV)
echo "== собран компилятор версии $VER"

echo "== установка в $PREFIX"
rm -rf "$PREFIX"
mkdir -p "$PREFIX/bin" "$PREFIX/lib/fpc/$VER/units/x86_64-linux"
cp "$COMP" "$PREFIX/bin/ppcx64"
cp "$SRC"/rtl/units/x86_64-linux/* "$PREFIX/lib/fpc/$VER/units/x86_64-linux/"
for D in "$SRC"/packages/*/units/x86_64-linux; do
  if [ -d "$D" ]; then
    cp -n "$D"/* "$PREFIX/lib/fpc/$VER/units/x86_64-linux/" 2>/dev/null || true
  fi
done
printf '%s\n' "-Fu$PREFIX/lib/fpc/$VER/units/x86_64-linux" > "$PREFIX/bin/fpc.cfg"
printf '%s\n' '#!/bin/sh' "exec $PREFIX/bin/ppcx64 @$PREFIX/bin/fpc.cfg \"\$@\"" > "$PREFIX/bin/fpc"
chmod +x "$PREFIX/bin/fpc"

echo "== самопроверка установки"
TMP=$(mktemp -d)
cat > "$TMP/selftest.pas" <<'PASEOF'
program selftest;
{$mode objfpc}{$H+}
uses sysutils;
type
  TVec = record X, Y: Double; end;
  TVecArray = array of TVec;
var
  A: TVecArray;
  I: Integer;
  S: Double;
  F: TextFile;
  Line: string;
begin
  SetLength(A, 1000);
  S := 0;
  for I := 0 to High(A) do
  begin
    A[I].X := I * 0.5;
    A[I].Y := I * 0.25;
    S := S + A[I].X * A[I].Y;
  end;
  if Abs(S - 41604187.5) > 1e-6 then Halt(3);
  Assign(F, ParamStr(1));
  Rewrite(F);
  WriteLn(F, 'selftest line');
  Close(F);
  Assign(F, ParamStr(1));
  Reset(F);
  ReadLn(F, Line);
  Close(F);
  if Line <> 'selftest line' then Halt(4);
  WriteLn('selftest ok, FPC ', {$I %FPCVERSION%});
end.
PASEOF
"$PREFIX/bin/fpc" -Mobjfpc -Sh -FE"$TMP" -o"$TMP/selftest" "$TMP/selftest.pas" > /dev/null
"$TMP/selftest" "$TMP/data.txt"
rm -rf "$TMP"
echo "== готово: $PREFIX/bin/fpc"
