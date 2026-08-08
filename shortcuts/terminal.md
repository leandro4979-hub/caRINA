# Terminal Shortcuts

> Shell line editing, history, and navigation for zsh and bash.
> Last verified: 2026-08-07

## Line editing

| Action | Shortcut | Notes |
| --- | --- | --- |
| Jump to start of line | `⌃A` | Faster than holding `←` |
| Jump to end of line | `⌃E` | |
| Move back one word | `⌥←` | Requires Option as Meta in Terminal |
| Delete to start of line | `⌃U` | zsh deletes whole line; bash deletes to cursor |
| Delete to end of line | `⌃K` | Deleted text is yankable with `⌃Y` |
| Delete previous word | `⌃W` | |
| Swap the last two characters | `⌃T` | Fixes common transposition typos |

## History

| Action | Shortcut | Notes |
| --- | --- | --- |
| Reverse-search history | `⌃R` | Press again to step further back |
| Accept and run search result | `⏎` | `→` accepts without running |
| Previous / next command | `⌃P` / `⌃N` | Equivalent to `↑` / `↓` |
| Cancel the current line | `⌃C` | Line is kept in history |

## Navigation

| Action | Command | Notes |
| --- | --- | --- |
| Return to previous directory | `cd -` | Toggles between two directories |
| Return to home | `cd` | No argument needed |
| Clear the screen | `⌃L` | Preserves scrollback |
| Suspend / resume a process | `⌃Z` / `fg` | `bg` resumes in the background |
