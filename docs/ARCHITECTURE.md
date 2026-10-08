# Архитектура движка

## Принципы

- Язык: FreePascal, режим `objfpc`. Классов и объектов в проекте нет: данные описаны записями (`record`), поведение - процедурами и функциями с явными параметрами.
- Исключения не используются. Ошибки печатаются в stderr (`WriteLn(ErrOutput, ...)`), программа завершается через `Halt(код)`.
- Подсистемы связаны только данными и параметрами. Глобального состояния между модулями нет, кроме загрузчиков GL и GLFW, которые по природе глобальны (указатели на функции).
- Ориентиры: Quake 3 (разделение на слои платформы, рендера и движка; данные отдельно от кода) и проекты Pangea Software (простой процедурный Паскаль, юниты как модули). Графика ориентирована на идеи Fox Engine (физически основанный материал, тени, тонемаппинг), но реализована в упрощённом виде. Это не клон Fox Engine.

## Слои и зависимости

Модуль зависит только от модулей своего слоя или слоёв ниже. Слои перечислены снизу вверх.

| Слой | Каталог | Модули | Зависимости |
|---|---|---|---|
| 1. Ядро | `src/core` | `EngPNG` | нет |
| 2. Математика, физика, анимация | `src/engine` | `EngMath`, `EngMat4`, `EngConvex`, `EngPhysics`, `EngAnim`, `EngHumanoid`, `EngRagdoll` | `EngConvex` - от `EngMath`; `EngPhysics` - от `EngConvex`; `EngHumanoid` - от `EngAnim`; `EngRagdoll` - от физики, анимации и гуманоида |
| 3. Платформа | `src/platform` | `GLBind`, `GLFWBind`, `GLFixedBind`, `OSMesaBind`, `EngScreenshot` | `GLFWBind`, `OSMesaBind` - `dynlibs`; `EngScreenshot` - `EngPNG`, `GLBind` |
| 4. Рендеринг | `src/render` | `EngMesh`, `EngScene`, `EngRender`, `EngFixedGL` | `EngScene` - `EngMath`, `EngMat4`; `EngRender` - `EngScene`, `EngMesh`, `GLBind`; `EngFixedGL` - `EngScene`, `EngMesh`, `GLFixedBind`, `OSMesaBind` |
| 6. Приложение | `src/app` | `EngDemo` | все слои |
| Точки входа | `examples/`, `tools/`, `tests/`, `bench/`, `lazarus/` | программы | любые слои |

Физика не знает о рендеринге и GL. Рендерер получает от приложения только массив `TRenderItem` (индекс меша, матрица модели, материал). Связь «физика -> рендер» выполняет `src/app/EngDemo.pas` (процедура `FillItems`).

## Поток данных кадра

1. `RagdollAdvance(W, R, dt, substeps)`: обновляется клип анимации (`PlayerUpdate`, `PlayerEvaluate`, `PoseGlobal`); затем на каждом подшаге вызываются `RagdollControl` (поведения: баланс, упор, дотягивание) и `PhysStep`.
2. Приложение заполняет `TRenderItem` из позиций тел (`Mat4FromRT`) и вызывает `RenderFrame`.
3. `RenderFrame`: проход теней (карта глубины из направленного света), основной проход (GGX, PCF 3x3, ACES, гамма 2.2). Пол рисуется шахматкой через `uChecker`.
4. `ScreenshotSave` (`src/platform/EngScreenshot.pas`) читает задний буфер до `SwapBuffers` и записывает PNG.

## Графика

Реализовано в шейдерах `shaders/mesh.vert`, `mesh.frag`, `shadow.vert`, `shadow.frag` (GLSL 4.30 core):

- физически основанный материал: металличность, шероховатость, распределение GGX;
- карта теней направленного света с фильтрацией PCF 3x3;
- тонемаппинг ACES и гамма-коррекция 2.2;
- шахматный пол.

Не реализовано: глобальное освещение, постобработка, SSAO, каскадные тени.

Статус проверки: шейдеры компилируются `glslangValidator` (GLSL 430 core, код 0; отрицательный контроль с ошибкой даёт код 2). Шейдерный путь GL 4.3 на GPU не запускался: на стенде нет GPU. Он запускался на программном OpenGL Mesa 21.0.3 (softpipe) с переопределением версии (`MESA_GL_VERSION_OVERRIDE=4.3`): кадр `Demo --offscreen` получен. Снимки поз (`out/pose_*.png`) получены через OpenGL 2.x в osmesa-main (фиксированный конвейер, без шейдеров, теней и GGX; `src/render/EngFixedGL.pas`). Прежний CPU-растеризатор `EngSoftRaster` удалён; он остаётся в истории git (коммит cb3eef0).

Снимок окна (`EngScreenshot`) следует методу из статьи lencerf: `glfwGetFramebufferSize`, `GL_PACK_ALIGNMENT = 1`, `glReadPixels`, переворот строк при записи. Отличие: читается задний буфер до `SwapBuffers`, а не передний.

## Тесты и инструменты

- `tests/TestMain.pas` - набор проверок; модули `TestKit` (проверки), `TestPhysics`, `TestRagdoll` (анимация и рэгдолл), `TestPNG`, `TestRender` (матрицы, меши, шахматный пол через OpenGL 2.x в OSMesa; без osmesa-main этот тест пропускается).
- `bench/BenchMain.pas` - бенчмарк: столкновения, физика, рэгдолл, анимация, PNG. См. `docs/BENCHMARK.md`.
- `tools/PoseSnapshot.pas` - снимки поз рэгдолла через OpenGL 2.x в OSMesa (`out/pose_*.png`); библиотека задаётся `--osmesa` или `ENGINE_OSMESA`, см. `docs/OSMESA.md`.
- `examples/Demo.pas` и `lazarus/EngineDemo.lpr` - запуск окна; общий код в `src/app/EngDemo.pas`.
