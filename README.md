# genja-recent.nvim

Recent files with your own rules, ranked by frecency (how often and how
recently). Edits weigh more than views.

## Setup (lazy.nvim)

```lua
{
	'tox2ik/genja-recent.nvim',
	event = 'VeryLazy',
	opts = {
		edit_weight = 2,
		skip_patterns = { '/%.git/' },
		skip_dirs = { vim.uv.os_tmpdir(), vim.fn.stdpath('data') },
	},
	config = function(_, opts) require('genja-recent').setup(opts) end,
}
```

## Options

| Option | Default | Meaning |
|--------|---------|---------|
| `file` | `stdpath('data')/genja-recent.txt` | data file |
| `edit_weight` | `2` | an edit counts this many views |
| `skip_patterns` | `{ '/%.git/' }` | Lua patterns on the lowercase path; not recorded |
| `skip_dirs` | temp dir, `stdpath('data')` | files under these dirs are not recorded |
| `flush_minutes` | `5` | write interval |
| `max_entries` | `2000` | lines kept in the file, best first |

Only buffers with `buftype == ''` and a real path are recorded (no `oil://`,
help, terminals).

## API

- `require('genja-recent').list({ root? })`: existing paths, best first;
  `root` keeps only files under it.
- `.record(buf, 'view'|'edit')`, `.flush()`.
- `require('genja-recent.frecency').score(views, edits, last, now, edit_weight)`.

## Score

`(views + edits * edit_weight) * recency`, recency x4 within an hour, x2
within a day, x0.5 within a week, x0.25 older.

## Data file

One line per file: `path<TAB>views<TAB>edits<TAB>last` (unix time). Plain
text; edit or delete it freely while nvim is closed.
