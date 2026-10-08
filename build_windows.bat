@echo off
rem Сборка, тесты, бенчмарк и демонстрация на Windows (x86_64).
rem
rem   build_windows.bat            сборка и тесты
rem   build_windows.bat bench      то же + бенчмарк
rem   build_windows.bat demo       то же + сборка Demo.exe
rem
rem Переменные окружения:
rem   FPC_EXE     путь к компилятору (по умолчанию fpc из PATH), нужен FPC 3.2.2 или новее с Win64 RTL
rem
rem Для запуска окна рядом с Demo.exe положите glfw3.dll (GLFW 3, x64) и обновите драйвер GPU
rem с поддержкой OpenGL 4.3 core. Проверено только на Linux; см. docs\WINDOWS.md.

setlocal
set "ROOT=%~dp0"
cd /d "%ROOT%"
if errorlevel 1 exit /b 1
if "%FPC_EXE%"=="" set "FPC_EXE=fpc"

set "FLAGS=-Mobjfpc -Sh -O3 -Xs -Twin64 -Px86_64"
set "UNITS=-Fusrc\app -Fusrc\core -Fusrc\engine -Fusrc\render -Fusrc\platform"
set "OUT=build\win64"
if not exist "%OUT%" mkdir "%OUT%"

echo == сборка тестов
"%FPC_EXE%" %FLAGS% %UNITS% -FE"%OUT%" -FU"%OUT%" -o"%OUT%\test_main.exe" tests\TestMain.pas
if errorlevel 1 goto fail
echo == тесты
"%OUT%\test_main.exe"
if errorlevel 1 goto fail

if "%1"=="bench" goto bench
if "%1"=="demo" goto demo
goto done

:bench
echo == сборка бенчмарка
"%FPC_EXE%" %FLAGS% %UNITS% -FE"%OUT%" -FU"%OUT%" -o"%OUT%\bench_engine.exe" bench\BenchMain.pas
if errorlevel 1 goto fail
echo == бенчмарк
"%OUT%\bench_engine.exe"
if errorlevel 1 goto fail
if "%1"=="demo" goto demo
goto done

:demo
echo == сборка Demo.exe
"%FPC_EXE%" %FLAGS% %UNITS% -FE"%OUT%" -FU"%OUT%" -o"%OUT%\Demo.exe" examples\Demo.pas
if errorlevel 1 goto fail
echo Demo.exe собран: %OUT%\Demo.exe (запуск: %OUT%\Demo.exe --frames 120 --shot out\demo.png)
goto done

:fail
echo ОШИБКА сборки или тестов (код %errorlevel%)
exit /b 1

:done
echo == готово
endlocal
