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

;;;; Sending

(defun claude-send-tmux--send (pane text)
  "Send TEXT to tmux PANE via load-buffer + paste-buffer."
  (let ((tmpfile (make-temp-file "claude-send-tmux-")))
    (unwind-protect
        (progn
          (with-temp-file tmpfile
            (insert text))
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

(define-derived-mode claude-send-tmux-message-mode text-mode "Claude-Msg"
  "Major mode for composing messages to Claude Code.
\\[claude-send-tmux-message-send] to send, \\[claude-send-tmux-message-cancel] to cancel.")

(defun claude-send-tmux-message-send ()
  "Send the buffer contents to Claude Code and close the buffer."
  (interactive)
  (let ((text (string-trim (buffer-string)))
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

(defun claude-send-tmux--send-key (key-str)
  "Send KEY-STR to the Claude Code pane."
  (let ((pane (nth 0 (claude-send-tmux--ensure-pane))))
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
  (let ((target (claude-send-tmux--ensure-pane))
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
                   '(display-buffer-below-selected (window-height . 10)))
    (claude-send-tmux-message-mode)
    (setq-local claude-send-tmux--target-pane target)
    (setq header-line-format
          (format "%s: send, %s: cancel | %s (%s)"
                  (substitute-command-keys "\\[claude-send-tmux-message-send]")
                  (substitute-command-keys "\\[claude-send-tmux-message-cancel]")
                  (abbreviate-file-name (nth 1 target))
                  (nth 0 target)))
    (when initial
      (insert initial))))

(provide 'claude-send-tmux)
;;; claude-send-tmux.el ends here
