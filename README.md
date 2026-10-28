# Fermentino

2D-игра под iPhone: много тел, попарная псевдогравитация и столкновения.
Вся симуляция и рендер на GPU через Metal.

## Стек

- Swift, SwiftUI (меню и HUD), MetalKit (игровой экран)
- Симуляция в compute-кернелах: гравитация «каждый с каждым» с тайлингом,
  position-based столкновения через хэш-сетку, Verlet-интеграция
- Один instanced draw call на все тела

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

- `Fermentino/Shaders/ShaderTypes.h` — структуры, общие для Swift и Metal
- `Fermentino/Shaders/Simulation.metal` — кернелы симуляции
- `Fermentino/Shaders/Render.metal` — рендер кругов
- `Fermentino/Simulation/Simulation.swift` — буферы и кодирование кадра
- `Fermentino/Rendering/Renderer.swift` — `MTKViewDelegate`
- `Fermentino/Rendering/MetalView.swift` — SwiftUI-обёртка и касания
