# claude-send-tmux

tmux ペインで動作中の Claude Code セッションにメッセージを送る Emacs パッケージ。`pane_current_command` と `pane_current_path` を使って、現在のプロジェクトに対応する Claude Code ペインを自動検出します。

## 機能

- **自動検出**: 現在のプロジェクトルートに一致する Claude Code ペインを自動検出（シンボリックリンクを解決）
- **メッセージ作成**: 複数行メッセージを作成する専用バッファ。リージョン選択時はコードブロックとして挿入
- **クイックキー**: Claude Code のプロンプトに対して単一キー（1, 2, 3, q, Escape）を即座に送信

## 必要環境

- Emacs 28.1 以降
- [tmux](https://github.com/tmux/tmux)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) が tmux ペインで実行中であること

## インストール

### 手動インストール

1. このリポジトリをクローンまたは `claude-send-tmux.el` をダウンロード
2. Emacs 設定に以下を追加：

```elisp
(add-to-list 'load-path "/path/to/claude-send-tmux")
(require 'claude-send-tmux)
```

### straight.el を使用

```elisp
(straight-use-package
 '(claude-send-tmux :type git :host github :repo "ofnhwx/claude-send-tmux.el"))
```

## 使い方

### メッセージを作成して送信

```
M-x claude-send-tmux-message
```

メッセージ作成用のバッファが開きます。リージョンが選択されている場合、ファイル名と行番号付きのコードブロックとして挿入されます。

- `C-c C-c` で送信
- `C-c C-k` でキャンセル

### クイックキー

```
M-x claude-send-tmux-send-1       "1" を送信
M-x claude-send-tmux-send-2       "2" を送信
M-x claude-send-tmux-send-3       "3" を送信
M-x claude-send-tmux-send-q       "q" を送信
M-x claude-send-tmux-send-escape  Escape を送信
```

## カスタマイズ

### tmux 実行ファイル

```elisp
(setq claude-send-tmux-command "tmux")
```

### 検出するプロセス名

```elisp
(setq claude-send-tmux-process-name "claude")
```

## ライセンス

GPL-3.0-or-later

## 作者

ofnhwx
