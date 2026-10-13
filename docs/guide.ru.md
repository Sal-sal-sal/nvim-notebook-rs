# Как пользоваться nvim-notebook-rs

Расширение открывает `.ipynb` прямо в Neovim: редактируешь ячейки, запускаешь Python и видишь результат рядом с кодом.
Код можно выполнять на своём компьютере или в выбранной сессии Google Colab.

## Где менять настройки

Настройки передаются в `require("notebook_rs").setup({ ... })`.
Если используешь `lazy.nvim`, помести этот вызов в `config` своего файла плагина.
На этом компьютере файл находится в `/Users/saladin/.config/nvim/lua/plugins/notebook_rs.lua`.
Сам код расширения находится в `/Users/saladin/projects/nvim-notebook-rs`.

Пример конфигурации:

```lua
{
  "Sal-sal-sal/nvim-notebook-rs",
  build = "cargo build --release --locked",
  config = function()
    require("notebook_rs").setup({
      cells_output_interacteable = true,
      nootbook_result = "nootbook",
      nootbook_hidden_id_line = true,
      distance_between_cells = 2,
    })
  end,
}
```

При работе с локальными исходниками замени строку репозитория на `dir = "/Users/saladin/projects/nvim-notebook-rs"`.
После обновления кода расширения или изменения конфигурационного файла перезапусти Neovim, чтобы загрузились все новые обработчики.
Если обновились Rust-исходники worker, сначала выполни `cargo build --release --locked` в каталоге расширения.
При установке через `dir` сборку можно выполнить этой командой вручную или через `:Lazy build nvim-notebook-rs`; изменения только в Lua не требуют пересборки worker.

## Первый запуск

1. Открой существующий файл через `:edit experiment.ipynb` или создай новый через `:NotebookNew experiment.ipynb`.
2. Напиши Python-код внутри code-ячейки.
3. Поставь курсор в эту ячейку и выполни `:NotebookRun`.
4. Прочитай результат под ячейкой.
5. Выполни `:write`, чтобы сохранить код и результат в `.ipynb`.

Например, ячейка с `print("hello")` покажет `hello` в секции OUTPUT.
`:NotebookRunAll` запускает все code-ячейки по порядку и останавливается на первой ошибке.
Переменные локального Python сохраняются между запусками ячеек одного notebook.
`:NotebookRestart` очищает этот локальный Python-процесс.

## Как двигаться по output

Включи `cells_output_interacteable = true` вместе с `nootbook_result = "nootbook"`.
Текстовый результат, значения выражений и traceback станут обычными строками под своей ячейкой.
Курсор не перепрыгивает весь результат при движении вниз.

| Действие | Клавиши |
| --- | --- |
| На строку вниз / вверх | `j` / `k` |
| Перейти внутри строки | `h` / `l`, `w` / `b` |
| На страницу вниз / вверх | `Ctrl-f` / `Ctrl-b` |
| Прокрутить на полстраницы | `Ctrl-d` / `Ctrl-u` |
| Найти текст результата | `/нужный текст`, затем `n` / `N` |
| Выделить строки | `V`, затем `j` / `k` |
| Скопировать строку / выделение | `yy` / `y` |
| Перейти к следующей / предыдущей ячейке | `:NotebookCellNext` / `:NotebookCellPrev` |

Копирование выделения, состоящего только из output, убирает служебные префиксы.
Результат доступен для чтения, поиска и копирования; редактируй код исходной ячейки, чтобы изменить результат.
Попытка изменить только строки output восстанавливает их исходный текст.
Если запустить `:NotebookRun` с курсором в output, выполнится его исходная code-ячейка.
Команды вставки, удаления и перемещения ячейки из output тоже относятся к его исходной ячейке.

При `cells_output_interacteable = false` вывод снова рисуется виртуальными строками.
Это значение используется по умолчанию.
Изображения и HTML остаются визуальными блоками или ссылками, а не строками для курсора.
`:NotebookOpenArtifact` открывает последний полученный файл изображения или HTML.
При `nootbook_result = "window"` результат показывается в отдельном нижнем окне.
При `nootbook_result = "hidden"` результат не показывается, но его можно сохранить через `:write`.

## Графики Matplotlib

Графики `plt` сохраняются как изображения.
После выполнения ячейки открой последний график командой `:NotebookOpenArtifact`.
Настройка `cells_output_interacteable` управляет движением по тексту и не меняет работу изображений.

```python
import tensorflow as tf
import matplotlib.pyplot as plt

g = tf.random.Generator.from_seed(1243)
plt.imshow(g.normal((10, 10)).numpy())
plt.show()
```

Для `imshow` подходят формы `(M, N)`, `(M, N, 3)` и `(M, N, 4)`.
Выражение `g.normal((10, 10))[np.newaxis]` создаёт форму `(1, 10, 10)` и вызывает ошибку Matplotlib.
Убери `np.newaxis`, если хочешь показать обычную матрицу 10 на 10.
Подробнее: [документация imshow](https://matplotlib.org/stable/api/_as_gen/matplotlib.pyplot.imshow.html).

Ошибка `Invalid symbol 10` относится к чтению изображения расширением, а не к форме массива.
Обнови исходники расширения и пересобери Rust worker, чтобы получить исправление обработки переносов строк в base64.

## Ячейки и горячие клавиши

`<leader>` обозначает твой `mapleader`.
Если leader установлен в пробел, `<leader>rr` означает пробел, затем `r`, затем ещё `r`.
Все перечисленные сочетания работают только в notebook-буфере.

| Что сделать | Команда | Сочетание |
| --- | --- | --- |
| Запустить текущую code-ячейку | `:NotebookRun` | `<leader>rr` или `<leader>rc` |
| Запустить все code-ячейки | `:NotebookRunAll` | `<leader>ra` |
| Следующая / предыдущая ячейка | `:NotebookCellNext` / `:NotebookCellPrev` | `<leader>jc` / `<leader>kc` |
| Перейти к ячейке 3 | `:NotebookCellGoto 3` | `<leader>3b` |
| Добавить code-ячейку сверху / снизу | `:NotebookCellNewAbove` / `:NotebookCellNewBelow` | `<leader>cca` / `<leader>ccb` |
| Удалить ячейку | `:NotebookCellDelete` | `<leader>ccx` |
| Переместить ячейку | `:NotebookCellMove up` или `down` | Через команду |
| Открыть меню ячеек и Colab | Через сочетание | `<leader>cc` |

Для Markdown используй `:NotebookCellNewBelow markdown`, для обычного текста - `:NotebookCellNewBelow raw`.
Строка `# %% [code] id=...` обозначает начало ячейки.
Её можно показывать или скрывать настройкой `nootbook_hidden_id_line`, но удалять или портить её не нужно.

## Все настройки отображения

| Настройка | По умолчанию | Что меняет |
| --- | --- | --- |
| `cells_output_interacteable` | `false` | Разрешает курсору двигаться по текстовому inline output |
| `nootbook_result` | `"nootbook"` | `"nootbook"`: под ячейкой; `"window"`: нижнее окно; `"hidden"`: скрыть |
| `nootbook_hidden_id_line` | `true` | Скрывает служебные строки с типом и id ячейки |
| `distance_between_cells` | `2` | Добавляет визуальное расстояние между ячейками |
| `python_lsp.enabled` | `true` | Подключает Python language server для подсказок |
| `python_lsp.server` | `"pyright"` | Выбирает имя Python language server |
| `python_lsp.cmd` | Не задано | Задаёт команду запуска language server |
| `python_lsp.python_path` | Не задано | Выбирает Python-окружение, библиотеки которого видит language server |

Сохрани точное написание `cells_output_interacteable` и `nootbook`: это имена текущих параметров.
Чтобы изменить режим в уже открытых notebook-буферах, можно вызвать `:lua require("notebook_rs").setup({ cells_output_interacteable = false })`.
Это подходит для смены настройки в текущей версии расширения; после обновления самих исходников нужен новый сеанс Neovim.

## Локальный Python или Colab

Локальный запуск использует `python3` или интерпретатор из переменной `NVIM_NOTEBOOK_PYTHON`.
Для выбора Colab установи официальный Colab CLI и пройди вход через `:NotebookColabLogin`.

```vim
:NotebookColabConnect training
:NotebookBackend colab
:NotebookRun
```

Если сессии ещё нет, используй `:NotebookColabNew training T4`.
Расширение предложит выбрать существующую именованную сессию или создать новую.
Успешное подключение переключает исходный notebook на Colab.
`:NotebookBackend local` возвращает этот notebook к локальному Python.
Строка статуса `run: local` или `run: colab` показывает, где действительно выполняется код.
`:NotebookColabStop` останавливает выбранную удалённую сессию.

Окружение для подсказок `python_lsp.python_path` выбирается отдельно от окружения выполнения.
Установка Torch в окружение подсказок сама по себе не устанавливает Torch в выбранную Colab-сессию или локальный runtime.
Подробнее о подсказках: `:help notebook-rs-completion`.

## Что сохраняется в файле

`:write` сохраняет Python-код, Markdown, metadata и структурированные результаты в исходный `.ipynb`.
Служебные строки интерактивного output не становятся исходным кодом.
Изменение code-ячейки очищает только её устаревший output.
Output, включая изображения, у неизменённых соседних ячеек сохраняется.
Изображение изменённой code-ячейки очищается вместе с её остальным устаревшим output.
Файл, изменившийся на диске после открытия, нужно переоткрыть перед сохранением.

## Где искать помощь

| Задача | Где посмотреть |
| --- | --- |
| Проверить установку | `:checkhealth notebook_rs` |
| Общая справка внутри Neovim | `:help nvim-notebook-rs` |
| Настройки output | `:help notebook-rs-output` |
| Все команды и сочетания | `:help notebook-rs-commands`, `:help notebook-rs-keys` |
| Python-подсказки | `:help notebook-rs-completion` |
| Ошибки открытия, сохранения, Colab и TLS | [Устранение проблем](troubleshooting.md) |
| Внутреннее устройство расширения | [Архитектура](architecture.md) |
| Установка готового worker и выпуск версии | [Релизы](releases.md) |

Для воспроизводимого отчёта об ошибке укажи Neovim, выбранный backend, настройки output и короткую ячейку, на которой возникает проблема.
