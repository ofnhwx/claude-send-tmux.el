;;; claude-send-tmux.el --- Send messages to Claude Code via tmux -*- lexical-binding: t; -*-

;; Author: ofnhwx
;; URL: https://github.com/ofnhwx/nsmacs
;; Package-Requires: ((emacs "28.1"))

;;; Commentary:

;; Send messages to a running Claude Code session in a tmux pane.
;; Detects Claude Code panes automatically by matching `pane_current_command'
;; and `pane_current_path' against the current project root.

;;; Code:

(require 'project)
(require 'transient)

;;;; Customization

(defgroup claude-send-tmux nil
  "Send messages to Claude Code via tmux."
  :group 'tools
  :prefix "claude-send-tmux-")

(defcustom claude-send-tmux-command "tmux"
  "Path to the tmux executable."
  :type 'string)

(defcustom claude-send-tmux-process-name "claude"
  "Process name to detect Claude Code panes."
  :type 'string)

(defcustom claude-send-tmux-preview-lines 20
  "Number of trailing lines captured from the Claude Code pane as preview.
Inserted at the top of the compose buffer as `#'-prefixed comment lines."
  :type 'integer)

(defcustom claude-send-tmux-window-height 0.4
  "Height of the compose buffer window.
Passed to `display-buffer-below-selected' as `window-height'.
Accepts the same values as that parameter (integer lines or float fraction)."
  :type '(choice integer float))

;;;; Pane detection

(defun claude-send-tmux--run-tmux (&rest args)
  "Run tmux with ARGS and return output as string."
  (with-temp-buffer
    (apply #'call-process claude-send-tmux-command nil t nil args)
    (string-trim (buffer-string))))

(defun claude-send-tmux--list-panes ()
  "Return list of tmux panes running Claude Code.
Each element is (PANE-ID PATH) where PANE-ID is
\"session:window.pane\" and PATH is the pane's current directory."
  (let ((output (claude-send-tmux--run-tmux
                 "list-panes" "-a"
                 "-F" "#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_current_path}"))
        result)
    (dolist (line (split-string output "\n" t))
      (let* ((fields (split-string line "\t"))
             (pane-id (nth 0 fields))
             (command (nth 1 fields))
             (path (nth 2 fields)))
        (when (string= command claude-send-tmux-process-name)
          (push (list pane-id path) result))))
    (nreverse result)))

(defun claude-send-tmux--project-root ()
  "Return the current project root directory."
  (when-let ((proj (project-current)))
    (expand-file-name (project-root proj))))

(defun claude-send-tmux--detect-pane ()
  "Detect a Claude Code pane matching the current project root.
Returns (PANE-ID PATH) or nil."
  (let* ((root (claude-send-tmux--project-root))
         (true-root (when root (file-truename root)))
         (panes (claude-send-tmux--list-panes))
         (matching (when true-root
                     (seq-filter (lambda (p)
                                   (string= (file-name-as-directory
                                             (file-truename (nth 1 p)))
                                            (file-name-as-directory true-root)))
                                 panes))))
    (cond
     ((= (length matching) 1)
      (car matching))
     ((> (length matching) 1)
      (claude-send-tmux--select-pane matching))
     ((= (length panes) 1)
      (car panes))
     (panes
      (claude-send-tmux--select-pane panes))
     (t nil))))

(defun claude-send-tmux--select-pane (panes)
  "Let the user select a pane from PANES via `completing-read'.
Returns (PANE-ID PATH)."
  (let* ((candidates (mapcar (lambda (p)
                               (cons (format "%s  %s" (nth 0 p) (nth 1 p))
                                     p))
                             panes))
         (choice (completing-read "Claude Code pane: " candidates nil t)))
    (cdr (assoc choice candidates))))

(defun claude-send-tmux--ensure-pane ()
  "Detect a Claude Code pane, prompting if needed.
With `current-prefix-arg', skip auto-detection and always prompt.
Returns (PANE-ID PATH).  Signals an error if no pane is found."
  (or (if current-prefix-arg
          (let ((panes (claude-send-tmux--list-panes)))
            (cond
             ((null panes) nil)
             ((= (length panes) 1) (car panes))
             (t (claude-send-tmux--select-pane panes))))
        (claude-send-tmux--detect-pane))
      (user-error "No Claude Code pane found in tmux")))

;;;; Pane preview

(defun claude-send-tmux--strip-trailing-empty (lines)
  "Remove trailing empty lines from LINES."
  (nreverse (seq-drop-while #'string-empty-p (nreverse lines))))

(defconst claude-send-tmux--input-box-search-limit 10
  "Maximum number of trailing lines scanned for the input box borders.
Prevents `─' separators deep in the conversation body from being
mistaken for the input box chrome.")

(defun claude-send-tmux--strip-input-box (lines)
  "Remove the trailing Claude Code input box chrome from LINES.
The input box is bounded by two `─' border lines at the bottom of the
pane; everything from the upper border onward is dropped.  Only the
last `claude-send-tmux--input-box-search-limit' lines are scanned, so
`─' sequences appearing earlier in the body are preserved."
  (let ((border-re "\\`[[:space:]]*─\\{3,\\}[[:space:]]*\\'")
        (rev (reverse lines))
        (count 0)
        (scanned 0))
    (while (and rev
                (< count 2)
                (< scanned claude-send-tmux--input-box-search-limit))
      (when (string-match-p border-re (car rev))
        (setq count (1+ count)))
      (setq scanned (1+ scanned))
      (when (< count 2)
        (setq rev (cdr rev))))
    (if (= count 2)
        (reverse (cdr rev))
      lines)))

(defun claude-send-tmux--capture-pane (pane)
  "Return tail of PANE's visible content as `#'-prefixed comment lines.
Strips trailing blank lines and Claude Code's input box chrome before
taking the last `claude-send-tmux-preview-lines' lines."
  (let* ((output (claude-send-tmux--run-tmux "capture-pane" "-p" "-t" pane))
         (lines (split-string output "\n"))
         (lines (claude-send-tmux--strip-trailing-empty lines))
         (lines (claude-send-tmux--strip-input-box lines))
         (lines (claude-send-tmux--strip-trailing-empty lines))
         (tail (last lines claude-send-tmux-preview-lines)))
    (mapconcat (lambda (line)
                 (if (string-empty-p line) "#" (concat "# " line)))
               tail
               "\n")))

;;;; Sending

(defun claude-send-tmux--send (pane text)
  "Send TEXT to tmux PANE via load-buffer + paste-buffer.
Newlines in TEXT are escaped with a leading backslash so Claude Code
treats them as in-input linebreaks rather than submissions."
  (let ((tmpfile (make-temp-file "claude-send-tmux-"))
        (escaped (replace-regexp-in-string "\n" "\\\\\n" text)))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert escaped))
          (claude-send-tmux--run-tmux "load-buffer" tmpfile)
          (claude-send-tmux--run-tmux "paste-buffer" "-t" pane)
          (claude-send-tmux--run-tmux "send-keys" "-t" pane "Enter"))
      (delete-file tmpfile))))

;;;; Message buffer

(defvar-local claude-send-tmux--target-pane nil
  "Target pane for the current message buffer.")

(defvar claude-send-tmux-message-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'claude-send-tmux-message-send)
    (define-key map (kbd "C-c C-k") #'claude-send-tmux-message-cancel)
    map)
  "Keymap for `claude-send-tmux-message-mode'.")

(defvar claude-send-tmux-message-font-lock-keywords
  '(("^#.*$" . font-lock-comment-face))
  "Font-lock keywords for `claude-send-tmux-message-mode'.")

(define-derived-mode claude-send-tmux-message-mode text-mode "Claude-Msg"
  "Major mode for composing messages to Claude Code.
Lines starting with `#' are treated as comments and excluded from the
message sent to Claude Code.
\\[claude-send-tmux-message-send] to send, \\[claude-send-tmux-message-cancel] to cancel."
  (setq font-lock-defaults '(claude-send-tmux-message-font-lock-keywords)))

(defun claude-send-tmux-message-send ()
  "Send the buffer contents to Claude Code and close the buffer.
Lines starting with `#' are stripped before sending."
  (interactive)
  (let* ((lines (split-string (buffer-string) "\n"))
         (body (seq-remove (lambda (line) (string-prefix-p "#" line)) lines))
         (text (string-trim (mapconcat #'identity body "\n")))
         (pane (nth 0 claude-send-tmux--target-pane))
         (path (nth 1 claude-send-tmux--target-pane)))
    (when (string-empty-p text)
      (user-error "Empty message"))
    (quit-window 'kill)
    (claude-send-tmux--send pane text)
    (message "Sent to %s" path)))

(defun claude-send-tmux-message-cancel ()
  "Cancel composing and close the message buffer."
  (interactive)
  (quit-window 'kill)
  (message "Cancelled"))

;;;; Interactive commands

(defvar claude-send-tmux--current-target nil
  "Target pane used by send commands while `claude-send-tmux-send-menu' is active.
When non-nil, suffix commands reuse this instead of running pane detection.")

(defun claude-send-tmux--send-key (key-str)
  "Send KEY-STR to the Claude Code pane."
  (let ((pane (nth 0 (or claude-send-tmux--current-target
                         (claude-send-tmux--ensure-pane)))))
    (claude-send-tmux--run-tmux "send-keys" "-t" pane key-str)
    (message "Sent %s" key-str)))

;;;###autoload
(defun claude-send-tmux-send-1 ()
  "Send \"1\" to the Claude Code pane."
  (interactive)
  (claude-send-tmux--send-key "1"))

;;;###autoload
(defun claude-send-tmux-send-2 ()
  "Send \"2\" to the Claude Code pane."
  (interactive)
  (claude-send-tmux--send-key "2"))

;;;###autoload
(defun claude-send-tmux-send-3 ()
  "Send \"3\" to the Claude Code pane."
  (interactive)
  (claude-send-tmux--send-key "3"))

;;;###autoload
(defun claude-send-tmux-send-escape ()
  "Send Escape to the Claude Code pane."
  (interactive)
  (claude-send-tmux--send-key "Escape"))

;;;###autoload
(defun claude-send-tmux-send-q ()
  "Send \"q\" to the Claude Code pane."
  (interactive)
  (claude-send-tmux--send-key "q"))

;;;###autoload
(defun claude-send-tmux-message ()
  "Open a buffer to compose a message to Claude Code via tmux.
If a region is active, it is inserted as a code block with file and line info.
Use \\[claude-send-tmux-message-send] to send, \\[claude-send-tmux-message-cancel] to cancel."
  (interactive)
  (let* ((target (or claude-send-tmux--current-target
                     (claude-send-tmux--ensure-pane)))
         (preview (claude-send-tmux--capture-pane (nth 0 target)))
         (initial (when (use-region-p)
                    (let* ((start (region-beginning))
                           (end (region-end))
                           (file (or (buffer-file-name) (buffer-name)))
                           (start-line (line-number-at-pos start))
                           (end-line (line-number-at-pos end))
                           (region-text (buffer-substring-no-properties start end)))
                      (concat
                       (format "%s:%d-%d\n" (file-relative-name file) start-line end-line)
                       "```\n"
                       region-text
                       (unless (string-suffix-p "\n" region-text) "\n")
                       "```\n\n")))))
    (deactivate-mark)
    (pop-to-buffer (generate-new-buffer "*claude-send-tmux*")
                   `(display-buffer-below-selected
                     (window-height . ,claude-send-tmux-window-height)))
    (claude-send-tmux-message-mode)
    (setq-local claude-send-tmux--target-pane target)
    (setq header-line-format
          (format "%s: send, %s: cancel | %s (%s)"
                  (substitute-command-keys "\\[claude-send-tmux-message-send]")
                  (substitute-command-keys "\\[claude-send-tmux-message-cancel]")
                  (abbreviate-file-name (nth 1 target))
                  (nth 0 target)))
    (unless (string-empty-p preview)
      (insert preview "\n\n"))
    (when initial
      (insert initial))))

;;;; Transient menu

(defun claude-send-tmux--menu-description ()
  "Description for `claude-send-tmux-send-menu', showing the target pane preview."
  (let* ((target claude-send-tmux--current-target)
         (pane (nth 0 target))
         (path (nth 1 target))
         (preview (claude-send-tmux--capture-pane pane))
         (cleaned (replace-regexp-in-string "^#\\( \\|$\\)" "" preview)))
    (concat
     (propertize (format "%s (%s)" (abbreviate-file-name path) pane)
                 'face 'transient-heading)
     "\n\n"
     (propertize cleaned 'face 'shadow))))

(defun claude-send-tmux--menu-cleanup ()
  "Clear `claude-send-tmux--current-target' when the send menu exits."
  (setq claude-send-tmux--current-target nil)
  (remove-hook 'transient-exit-hook #'claude-send-tmux--menu-cleanup))

;;;###autoload (autoload 'claude-send-tmux-send-menu "claude-send-tmux" nil t)
(transient-define-prefix claude-send-tmux-send-menu ()
  "Send a key or compose a message to the Claude Code pane, with preview."
  [:description claude-send-tmux--menu-description
   ["Choice"
    ("1" "1" claude-send-tmux-send-1)
    ("2" "2" claude-send-tmux-send-2)
    ("3" "3" claude-send-tmux-send-3)]
   ["Control"
    ("e" "Escape" claude-send-tmux-send-escape)
    ("q" "q" claude-send-tmux-send-q)
    ("@" "Compose message" claude-send-tmux-message)]]
  (interactive)
  (setq claude-send-tmux--current-target (claude-send-tmux--ensure-pane))
  (add-hook 'transient-exit-hook #'claude-send-tmux--menu-cleanup)
  (transient-setup 'claude-send-tmux-send-menu))

(provide 'claude-send-tmux)
;;; claude-send-tmux.el ends here
