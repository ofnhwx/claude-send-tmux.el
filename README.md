# claude-send-tmux

Emacs package that sends messages to a running Claude Code session in a tmux pane. Detects Claude Code panes automatically by matching `pane_current_command` and `pane_current_path` against the current project root.

## Features

- **Auto-detection**: Finds Claude Code panes matching the current project root (resolves symlinks)
- **Message composition**: Opens a dedicated buffer for composing multi-line messages with region support
- **Quick keys**: Send single keys (1, 2, 3, q, Escape) for responding to Claude Code prompts

## Requirements

- Emacs 28.1 or later
- [tmux](https://github.com/tmux/tmux)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) running in a tmux pane

## Installation

### Manual Installation

1. Clone this repository or download `claude-send-tmux.el`
2. Add to your Emacs configuration:

```elisp
(add-to-list 'load-path "/path/to/claude-send-tmux")
(require 'claude-send-tmux)
```

### Using straight.el

```elisp
(straight-use-package
 '(claude-send-tmux :type git :host github :repo "ofnhwx/claude-send-tmux.el"))
```

## Usage

### Compose a message

```
M-x claude-send-tmux-message
```

Opens a buffer to compose a message. If a region is active, it is inserted as a code block with file and line info.

- `C-c C-c` to send
- `C-c C-k` to cancel

### Quick keys

```
M-x claude-send-tmux-send-1       Send "1"
M-x claude-send-tmux-send-2       Send "2"
M-x claude-send-tmux-send-3       Send "3"
M-x claude-send-tmux-send-q       Send "q"
M-x claude-send-tmux-send-escape  Send Escape
```

## Configuration

### tmux executable

```elisp
(setq claude-send-tmux-command "tmux")
```

### Process name for detection

```elisp
(setq claude-send-tmux-process-name "claude")
```

## License

GPL-3.0-or-later

## Author

ofnhwx
