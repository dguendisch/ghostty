# Status Bar

Ghostty supports a per-terminal-tile status bar rendered below the terminal
surface. A user-provided shell script generates the content as styled JSON
segments, which Ghostty renders in a dedicated bar. Each split/tile gets its
own independent status bar.

This feature requires shell integration and is currently macOS-only.

## Quick Start

1. Create a status bar script:

```bash
#!/bin/bash
# ~/.config/ghostty/statusbar.sh

branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null)
echo '[{"text":"'"$USER@$HOST"'","fg":"#89b4fa"},{"text":" '"$PWD"' ","fg":"#cdd6f4"}'"${branch:+,{\"text\":\" $branch \",\"fg\":\"#a6e3a1\",\"bold\":true}}"']'
```

2. Make it executable:

```
chmod +x ~/.config/ghostty/statusbar.sh
```

3. Add to your Ghostty config (`~/.config/ghostty/config`):

```
status-bar-script = ~/.config/ghostty/statusbar.sh
```

4. Open a new terminal. The status bar appears below the terminal surface.

## Configuration Options

### `status-bar-script`

Path to the shell script that generates status bar content. The script runs
in the context of the current shell session (via shell integration), so it
has access to all environment variables, functions, and tools available in
your shell.

The script is invoked automatically:
- Before each prompt (precmd)
- On directory change (chpwd)

The path may be absolute, relative to the config file directory, or prefixed
with `~/` for the home directory. Prefix with `?` to suppress errors if the
file doesn't exist (e.g. `?~/statusbar.sh`).

### `status-bar-font-family`

Font family for the status bar text. Defaults to the system UI font. Unlike
the terminal font, this does not need to be a fixed-width font.

```
status-bar-font-family = SF Pro
```

### `status-bar-background`

Background color for the status bar. Accepts hex (`#RRGGBB` or `RRGGBB`) or
X11 named colors. Defaults to semi-transparent black.

```
status-bar-background = #1e1e2e
```

## Script Output Format

The script must print a JSON array of segment objects to stdout. Each segment
represents a styled piece of text in the status bar.

```json
[
  {"text": " main ", "fg": "#a6e3a1", "bg": "#313244", "bold": true},
  {"text": " ~/dev/project ", "fg": "#cdd6f4"},
  {"text": " 12:34 ", "fg": "#f5c2e7", "align": "right"}
]
```

### Segment Fields

| Field       | Type    | Required | Default  | Description                          |
|-------------|---------|----------|----------|--------------------------------------|
| `text`      | string  | yes      |          | The text to display                  |
| `fg`        | string  | no       | white    | Foreground color (`#RRGGBB` or `RRGGBB`) |
| `bg`        | string  | no       | clear    | Background color (`#RRGGBB` or `RRGGBB`) |
| `bold`      | boolean | no       | false    | Bold text                            |
| `italic`    | boolean | no       | false    | Italic text                          |
| `underline` | boolean | no       | false    | Underlined text                      |
| `align`     | string  | no       | `"left"` | `"left"` or `"right"`               |

Left-aligned segments are grouped on the left, right-aligned segments on the
right, with a spacer in between.

If the JSON is invalid or a segment is missing the required `text` field, it
is silently skipped. Script stderr is redirected to `/dev/null`.

## Shell Integration

The status bar relies on Ghostty's shell integration to run the script at the
right times. Shell integration is enabled automatically when Ghostty launches
your shell. If it isn't active (e.g. when using `zig build run` during
development), add this to your shell config:

**zsh** (`~/.zshrc`):
```zsh
if [[ -n "$GHOSTTY_RESOURCES_DIR" ]]; then
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/zsh/ghostty-integration"
fi
```

**bash** (`~/.bashrc`):
```bash
if [ -n "$GHOSTTY_RESOURCES_DIR" ]; then
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/bash/ghostty.bash"
fi
```

**fish** (`~/.config/fish/config.fish`):
```fish
if set -q GHOSTTY_RESOURCES_DIR
  source "$GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
end
```

## Protocol

The shell integration communicates status bar content to Ghostty via the
OSC 777 escape sequence:

```
ESC ] 777 ; statusbar ; <json> BEL
```

You can test this directly without a script:

```bash
printf '\e]777;statusbar;[{"text":"hello","fg":"#a6e3a1"}]\a'
```

This is useful for verifying the pipeline works independently of the shell
integration and script execution.

## Example Scripts

### Git branch + directory

```bash
#!/bin/bash
branch=$(git -C "$PWD" symbolic-ref --short HEAD 2>/dev/null)
dirty=""
if [ -n "$branch" ]; then
  git -C "$PWD" diff --quiet 2>/dev/null || dirty="*"
fi

segments='[{"text":" '"$PWD"' ","fg":"#cdd6f4"}'
if [ -n "$branch" ]; then
  segments+=',{"text":" '"$branch$dirty"' ","fg":"#a6e3a1","bold":true}'
fi
segments+=']'
echo "$segments"
```

### Clock + virtualenv

```bash
#!/bin/bash
time=$(date +%H:%M)
segments='[{"text":" '"$time"' ","fg":"#f5c2e7","align":"right"}'

if [ -n "$VIRTUAL_ENV" ]; then
  venv=$(basename "$VIRTUAL_ENV")
  segments+=',{"text":" '"$venv"' ","fg":"#fab387"}'
fi

segments+=']'
echo "$segments"
```

## How It Works

1. Ghostty sets the `GHOSTTY_STATUS_BAR_SCRIPT` environment variable to the
   configured script path.
2. The shell integration (zsh/bash/fish) checks for this variable and
   registers a hook that runs at each prompt and on directory changes.
3. The hook executes the script, captures its stdout, and sends the output
   to Ghostty via the `OSC 777;statusbar;<json>` escape sequence.
4. Ghostty's terminal parser receives the OSC sequence, extracts the JSON,
   and passes it to the macOS app runtime.
5. The Swift layer parses the JSON into styled segments and renders them
   in a `StatusBarView` below the terminal surface.
6. The terminal surface automatically resizes to accommodate the status bar,
   reducing the available row count (programs see the correct size via
   `tput lines`).

## Notes

- The script must be executable (`chmod +x`).
- The script runs in a subshell, so it cannot modify the parent shell's state.
- Keep scripts fast - they run at every prompt. Avoid expensive operations
  or use caching where possible.
- The status bar disappears when the segments array is empty.
- Colors must be 6-digit hex (`#RRGGBB` or `RRGGBB`). Short forms like
  `#fff` are not supported.
- This feature is macOS-only. GTK support is not yet implemented.
