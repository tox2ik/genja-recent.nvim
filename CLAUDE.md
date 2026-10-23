# genja-recent.nvim

Recent files with own rules, ranked by frecency. Loaded from disk by the
config's `../../lua/lazyp/new/genja-recent.lua` (`VeryLazy`). The picker is
the config's `lua/genja/recent.lua` on `<C-F1>`. Read README.md.

How this file is kept: one heading per feature, one bullet per decision.
Unmarked bullets were stated by jaro. `(inferred)` marks Claude's reading of the
code or history: confirm or delete. `Hint:` is a working note for Claude.

## Layout

- `lua/genja-recent/init.lua`: setup, recording, data file, `list()`, `flush()`.
- `lua/genja-recent/frecency.lua`: the score, kept apart so genja-startdirs can use it later.

## Decisions (2026-10-23 spec)

- Own plugin in plug-wip, not part of genja-finder; ranking meant to be shared with genja-startdirs.
- Records on `BufWinEnter` (view) and `BufWritePost` (edit); views and edits counted apart.
- Skipped: non-file buftypes, `.git/` (COMMIT_EDITMSG), the temp dir, `nvim-data`; the list is an option.
- Frecency: (views + edits x 2) x recency (x4 < 1 h, x2 < 1 day, x0.5 < 1 week, x0.25 older).
- Picker opens on the current project (git root, else :pwd); `<M-a>` toggles all files.
- Data: `nvim-data/genja-recent.txt`, `path<TAB>views<TAB>edits<TAB>last`; written on `VimLeavePre` and on a timer.
- `<C-F1>` opens it; telescope oldfiles stays on `<leader>jo`.
- Several nvims: each writes its own uses since the last write on top of the file as it is then. (inferred: keeps counts from parallel sessions)
- The plugin must not require `genja.*`; the picker stays in the config. (inferred, as in the other plug-wip plugins)
- genja-startdirs still ranks by plain counts; switching it to frecency.lua needs a last-used time in its usage file. (open)
