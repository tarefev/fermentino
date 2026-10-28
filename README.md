# Fermentino

2D-игра под iPhone, перенос веб-прототипа fermentino.su один в один: Тесей (хост)
собирает гравитацией инертоны, стреляет ими ради отдачи, собирает фермент (хаб + 3 кэпа
по валентным слотам) и доставляет его в поглотитель. Тор-мир, камера на хосте, миникарта.

## Стек

- Swift, SwiftUI (меню и HUD), MetalKit (игровой экран)
- Силы и интегрирование (§2–§3 прототипа) в compute-кернелах: попарная гравитация
  с cutoff, мягкий контакт с липкостью, валентные связи (длина + угол), вязкость,
  чёрная дыра поглотителя; 5 подшагов на кадр, формулы и константы K те же
- Игровая логика (связи, выброс, «свои», нестабильность, победа, HUD) на CPU в `Game.swift`
- Рендер: инстансированные фигуры + линии, сцена собирается на CPU в `SceneBuilder`

## Сборка

Проект описан в `project.yml`, `.xcodeproj` не хранится в git:

```bash
brew install xcodegen
xcodegen generate
open Fermentino.xcodeproj
```

Нужен Metal Toolchain (Xcode 26+ не ставит его по умолчанию):

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Структура

- `Fermentino/Game/GameConstants.swift` — константы K прототипа
- `Fermentino/Game/Rounds.swift` — раунды (элементы, связи, спавн, условие победы), выбор `Rounds.ROUND`
- `Fermentino/Game/Game.swift` — логика раунда (порт функций прототипа)
- `Fermentino/Shaders/ShaderTypes.h` — структуры, общие для Swift и Metal
- `Fermentino/Shaders/Simulation.metal` — computeForces / integrate
- `Fermentino/Shaders/Render.metal` — фигуры и линии
- `Fermentino/Simulation/GPUSimulation.swift` — буферы тел и запуск подшагов
- `Fermentino/Rendering/SceneBuilder.swift` — порт draw(): сцена в экранных точках
- `Fermentino/Rendering/Renderer.swift` — `MTKViewDelegate`, кадр игры + отрисовка
- `Fermentino/Rendering/MetalView.swift` — SwiftUI-обёртка, тап = выстрел
- `Fermentino/App/ContentView.swift` — HUD, интро, победа, подпись зоны (SwiftUI)

## Отличия от прототипа

- Клавиши Q/W, A/S, E/R, L, D, B, Backspace — тапабельные токены в HUD
- На телефоне миникарта в правом нижнем углу (120 pt), чтобы не перекрывать HUD
- Масштаб мира 1:1 в точках экрана: на iPhone видно меньше, чем на мониторе
