# OSMesa: OpenGL без окна и без GPU

В проекте две OSMesa-библиотеки, у каждой своя задача.

| Библиотека | Версия OpenGL | Где используется | Статус |
|---|---|---|---|
| osmesa-main (форк Mesa 7.0.4, `libosmesa.so`) | OpenGL 2.0, фиксированный конвейер | `tools/PoseSnapshot.pas`, тест пола в `tests/TestRender.pas` | собрана; снимки поз и тесты проверены |
| Mesa 21.0.3, softpipe (`libOSMesa.so.8`) | OpenGL 4.3 core через переопределение версии | `examples/Demo.pas --offscreen` (шейдеры GL 4.3, тени) | собрана; кадр рендерера GL 4.3 получен |

Ни одна из них не заменяет GPU. Это программная растеризация Mesa, результаты проверяются визуально и тестами.

## osmesa-main: сборка

Архив `osmesa-main.zip` лежит в корне ветки `arena/721eac7b-engine`. Распакуйте его и выполните:

```sh
cmake -S osmesa-main -B osmesa-build -G Ninja -DCMAKE_BUILD_TYPE=Release -DOSMESA_BUILD_EXAMPLES=OFF
cmake --build osmesa-build
```

Результат: `osmesa-build/src/libosmesa.so`. Сборка под Windows (`osmesa.dll`) не проверена.

Запуск:

```sh
ENGINE_OSMESA=/путь/libosmesa.so ./build.sh                       # тесты, включая проверку пола через OpenGL 2.x
./build/examples/PoseSnapshot --osmesa /путь/libosmesa.so out     # снимки поз -> out/pose_*.png
```

Без библиотеки тест пола пропускается (111 проверок вместо 114), а `PoseSnapshot` завершается с кодом 2 и объяснением.

## Mesa 21 (OpenGL 4.3 через softpipe)

Mesa 21.0.3 берётся из `AOF-Dev/mesa-swdroid` (ветка `swdroid-21.0`). Сборка meson:

```sh
meson setup build-osmesa mesa-src -Dgallium-drivers=swrast -Ddri-drivers=[] -Dosmesa=true \
  -Dosmesa-bits=8 -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dvulkan-drivers= -Dllvm=disabled \
  -Dshared-glapi=enabled -Dopengl=true -Dbuild-tests=false
ninja -C build-osmesa src/gallium/targets/osmesa/libOSMesa.so.8.0.0
```

Нужны zlib, expat, bison, flex и GNU m4. В нашем стенде m4 не было, поэтому использовалась сборка m4 1.4.20 под WASIX, запущенная через Node.js.

Запуск кадра GL 4.3:

```sh
MESA_GL_VERSION_OVERRIDE=4.3 MESA_GLSL_VERSION_OVERRIDE=430 \
  ./build/examples/Demo --offscreen --osmesa /путь/libOSMesa.so.8 --frames 120 --shot out/demo_osmesa.png
```

Переменные задаются вручную: softpipe отдаёт OpenGL 4.0, а 4.3 получается переопределением. Программа их сама не ставит, чтобы не писать платформенный код для окружения процесса.

## Что проверено

- `./build.sh` с osmesa-main: 114 из 114. Без библиотеки: 111, тест пола пропущен, код 0.
- Мутации теста пола: без выравнивания распаковки текстуры тест падает (отношения каналов), без переворота строк падают все 68 252 клетки. Оба исходника восстановлены побайтно.
- Снимки `pose_standing`, `pose_push`, `pose_fallen`, `pose_reach` просмотрены: пол ровный, клетки 1 м, фигура стоит, падает и тянется правильно.
- `Demo --offscreen` с Mesa 21: кадр записан, код 0.

## Ограничения

- osmesa-main поддерживает только OpenGL 2.0 и не запускает шейдерный путь `EngRender`. Поэтому снимки поз рисуются фиксированным конвейером: без теней и GGX.
- softpipe медленный: кадр 1280×720 занимает около 1,5 с.
- GL 4.3 в Mesa 21 заявлен переопределением версии. Это не возможности настоящего драйвера, поэтому проверка на GPU по-прежнему нужна.
