# Графики под ячейками

Графики Matplotlib отображаются под ячейкой как изображения PNG или JPEG.
Это работает после выполнения и при открытии сохранённого `.ipynb`.
Текстовые результаты остаются доступны для поиска и выделения при `cells_output_interacteable = true`.

## Настройка Kitty

Для показа внутри Neovim нужны терминал с поддержкой изображений, [image.nvim](https://github.com/3rd/image.nvim) и ImageMagick.
На macOS установи ImageMagick командой `brew install imagemagick`.
Добавь в конфигурацию `lazy.nvim`:

```lua
return {
  {
    "3rd/image.nvim",
    opts = {
      backend = "kitty",
      processor = "magick_cli",
    },
  },
  {
    "Sal-sal-sal/nvim-notebook-rs",
    build = "cargo build --release --locked",
    opts = {
      cells_output_interacteable = true,
      image_output = true,
      image_max_height = 20,
    },
    config = function(_, opts)
      require("notebook_rs").setup(opts)
    end,
  },
}
```

Расширение задаёт размер графика в терминальных ячейках Kitty и обрезает его по границам окна, включая экраны Retina.
Если `image.nvim` уже настроен, добавь эти параметры в существующую запись.
Запусти новый Neovim в Kitty после изменения конфигурации.
Для других терминалов настрой поддерживаемый ими backend в `image.nvim`.

## Как выполнить

Открой notebook, поставь курсор в ячейку и выполни `:NotebookRun` или `<leader>rc`.

```python
import torch
import matplotlib.pyplot as plt

def tnp(x: torch.Tensor):
    return x.detach().cpu().numpy()

res = torch.arange(200).reshape(20, 10)
plt.figure()
plt.plot(tnp(res))
plt.grid(True)
plt.show()
```

`.cpu()` позволяет преобразовать в NumPy также тензор с GPU.
В локальном backend расширение собирает открытые изменившиеся фигуры Matplotlib даже без `plt.show()`, включая `s = plt.plot(...)`.
В Colab используй `plt.show()` для явного вывода фигуры в результат ячейки.
Само выражение `s` возвращает список объектов `Line2D`; оно не создаёт новый график.
Для отдельных графиков в следующих ячейках вызывай `plt.figure()` перед рисованием.

## Размер и открытие отдельно

`image_max_height = 20` резервирует до 20 строк на каждую картинку.
Увеличь значение для более крупного графика.
`image_output = false` отключает показ картинок внутри редактора.
Изображения сохраняются в `.ipynb` при `:write` при любом режиме отображения.

`:NotebookOpenChart` открывает первую картинку текущей ячейки в системном просмотрщике.
`:NotebookOpenChart 2` открывает вторую картинку той же ячейки.
Команда работает и без `image.nvim`, и для результатов из сохранённого notebook.

## Если виден только текст

Если появляется `[<matplotlib.lines.Line2D ...>]`, это текстовое представление результата `plt.plot`.
Сам график должен находиться ниже этого текста.
Если видна строка `Image output saved in notebook`, выполни `:NotebookOpenChart` и проверь настройку `image.nvim`, Kitty и наличие `magick` в `PATH`.
Если картинки нет и команда сообщает `No chart`, выполни ячейку с `plt.show()` и проверь, что выполнение завершилось без ошибки.
`nootbook_result = "window"` и `"hidden"` не показывают графики под ячейками; для этого выбери `"nootbook"`.
