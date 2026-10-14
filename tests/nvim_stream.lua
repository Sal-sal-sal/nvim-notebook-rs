local root = assert(vim.env.NOTEBOOK_RS_ROOT)
vim.opt.rtp:append(root)
local stream = require("notebook_rs.output.stream")
local text = require("notebook_rs.output.text")

for _, case in ipairs({
  { "plain\n\ntrailing spaces  \n", "plain\n\ntrailing spaces  \n" },
  { "abcdef\rxy", "xycdef" },
  { "abcdef\rxy\27[K\n", "xy\n" },
  { "abcdef\27[2K\rnew\n", "new\n" },
  { "A\r\nB\n", "A\nB\n" },
  { "abc\bX\n", "abX\n" },
  { "данные\rтест\27[K\n", "тест\n" },
  { "\27[31mred\27[0m\n", "red\n" },
  { "\27[38:2::20:30:40mcolor\27[0m", "color" },
  { "\27]8;;https://example.test\7link\27]8;;\7\n", "link\n" },
  { "a\tb", "a       b" },
  { "incomplete\27[31", "incomplete" },
}) do
  assert(stream.visible(case[1]) == case[2], "stream controls corrupted " .. vim.inspect(case[1]))
  local expected = text.rows({ { output_type = "stream", name = "stderr", text = case[1] } })
  for cut = 0, #case[1] do
    local outputs = {
      { output_type = "stream", name = "stderr", text = { case[1]:sub(1, cut) } },
      { output_type = "stream", name = "stderr", text = { case[1]:sub(cut + 1) } },
    }
    local original = vim.deepcopy(outputs)
    assert(vim.deep_equal(text.rows(outputs), expected), "chunk boundaries changed displayed output")
    assert(vim.deep_equal(outputs, original), "rendering changed raw notebook stream data")
  end
end
local result = { output_type = "execute_result", data = { ["text/plain"] = "result" } }
local image = { output_type = "display_data", data = { ["image/png"] = "aW1hZ2U=" } }
local error = { output_type = "error", ename = "ValueError", evalue = "bad", traceback = { "ValueError: bad" } }
local outputs = {
  { output_type = "stream", name = "stdout", text = "before\n" },
  { output_type = "stream", name = "stderr", text = "warning\n" },
  result,
  { output_type = "stream", name = "stdout", text = "after result\n" },
  image,
  { output_type = "stream", name = "stdout", text = "after image\n" },
  error,
}
local rows = text.rows(outputs, false)
local titles, words = {}, {}
for _, row in ipairs(rows) do
  if row.text:sub(1, #"├─") == "├─" then titles[#titles + 1] = row.text end
  words[#words + 1] = row.text
end
assert(#titles == 6, "different streams, results, media, and errors were merged together")
assert(table.concat(words, "\n"):find("ValueError: bad", 1, true), "traceback was lost")
assert(stream.visible("0%|░░\r50%|█░\r100%|██\n") == "100%|██\n")
print("Stream chunk boundaries, carriage returns, Unicode, ANSI, and output ordering passed")
