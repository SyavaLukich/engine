#!/bin/sh
# Сборка, тесты и бенчмарки движка.
#
#   ./build.sh            сборка и запуск тестов (ненулевой код выхода при провале любого теста)
#   ./build.sh bench      то же + запуск бенчмарков
#   ./build.sh examples   сборка примеров и инструментов (без запуска окна)
#
# Переменные окружения:
#   FPC            путь к компилятору (по умолчанию ~/.local/fpc-3.3.1-dev/bin/fpc, иначе fpc из PATH)
#   FPC_CPU_OPTS   цель оптимизации; по умолчанию "-OpCOREAVX2 -CfAVX2" (Haswell и новее).
#                  Для переносимой сборки задайте FPC_CPU_OPTS="" (x86-64 baseline).
#   FPC_EXTRA      дополнительные флаги компилятора
set -eu

ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

if [ -n "${FPC:-}" ]; then
  :
elif [ -x "$HOME/.local/fpc-3.3.1-dev/bin/fpc" ]; then
  FPC="$HOME/.local/fpc-3.3.1-dev/bin/fpc"
else
  FPC=fpc
fi
CPU_OPTS=${FPC_CPU_OPTS-"-OpCOREAVX2 -CfAVX2"}
FLAGS="-Mobjfpc -Sh -O3 -Xs $CPU_OPTS ${FPC_EXTRA:-}"
# все каталоги src/ - пути поиска модулей; подсистемы не зависят друг от друга на уровне модулей
UNITPATHS=$(find src -type d | sed 's/^/-Fu/' | tr '\n' ' ')

build_prog() {
  # $1 - исходник, $2 - каталог вывода, $3 - имя исполняемого файла
  mkdir -p "build/$2"
  echo "== сборка $1 -> build/$2/$3"
  # shellcheck disable=SC2086
  "$FPC" $FLAGS $UNITPATHS -FE"build/$2" -FU"build/$2" -o"build/$2/$3" "$1" > "build/$2/$3.build.log" 2>&1 || {
    cat "build/$2/$3.build.log"
    echo "ОШИБКА сборки: $1" >&2
    exit 1
  }
  if grep -q "Warning:" "build/$2/$3.build.log"; then
    grep "Warning:" "build/$2/$3.build.log" | head -20
  fi
}

MODE=${1:-test}

build_prog tests/TestMain.pas tests test_main
echo "== тесты"
./build/tests/test_main

case "$MODE" in
  bench)
    build_prog bench/BenchMain.pas bench bench_engine
    echo "== бенчмарки"
    ./build/bench/bench_engine
    ;;
  examples)
    for SRC in examples/*.pas tools/*.pas; do
      [ -f "$SRC" ] || continue
      NAME=$(basename "$SRC" .pas)
      build_prog "$SRC" examples "$NAME"
    done
    ;;
  test)
    ;;
  *)
    echo "неизвестный режим: $MODE (test | bench | examples)" >&2
    exit 2
    ;;
esac
echo "== готово"
