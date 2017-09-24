;;; presage-predictor.el --- PRESAGE PREDICTOR completion for the emacs editor

;; Copyright (C) 2009 Tastu Teche

;; Author: Tastu Teche <tastuteche@yahoo.com>

;; This program is free software: you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of the
;; License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see
;; `http://www.gnu.org/licenses/'.

;;; Commentary:
;;
;; This file defines dynamic completion backend for company-mode
;; that are based on presage predictor.
;;
;; Presage predictor for emacs:
;; - is configurable through programmable presage predictor
;;
;; When the first completion is requested in company mode
;; , presage-predictor.el starts a separate presage
;; process.  presage-predictor.el then uses this process to do the actual
;; completion and includes it into Emacs completion suggestions.
;;
;; INSTALLATION
;;
;; 1. copy presage-predictor.el into a directory that's on Emacs load-path
;; 2. add this into your .emacs file:
;;   (autoload 'company-presage-backend \"presage-predictor\"
;;     \"PRESAGE PREDICTOR completion backend\")
;; (add-to-list 'company-backends 'company-presage-backend)
;;
;;   or simpler, but forces you to load this file at startup:
;;
;;   (require 'presage-predictor)
;;   (presage-predictor-setup)
;;
;; 3. reload your .emacs (M-x `eval-buffer') or restart
;;
;; Once this is done, type as usual to do dynamic completion from
;; company mode. Note that the first completion is slow, as emacs
;; launches a new presage process.
;;
;; You'll get better results if you use language models based on a "good" training corpus of text.
;; text2ngram tool generates n-gram language models from a given training text corpora.
;; https://sourceforge.net/p/presage/presage/ci/master/tree/FAQ

;; Right after your language model trained, and whenever you
;; make changes to your /etc/presage.xml, call `presage-predictor-reset' to make
;; sure presage predictor takes your new settings into account.
;;
;;
;; CAVEATS
;;
;; Using a separate process for doing the completion has several
;; important disadvantages:
;; - presage predictor is slower than standard emacs completion
;; - the first completion can take a long time, since a new presage process
;;   needs to be started and initialized
;;
;; COMPATIBILITY
;;
;; presage-predictor.el is known to work on Emacs 22 and later under
;; Linux.
;;

;;; History:
;;
;; Full history is available on
;; https://github.com/tastuteche/emacs-presage-predictor


;;; Code:
(require 'cl-lib)
(require 'company)
;;; ---------- Customization
(defgroup presage-predictor nil
  "PRESAGE configurable completion "
  :group 'presage-predictor
  :prefix "presage-predictor-")


(defcustom presage-predictor-prog "/usr/bin/presage_demo_text"
  "Name or path of the PRESAGE PREDICTOR executable to run for predictive text entry.
This should be either an absolute path to the PRESAGE PREDICTOR executable or
the name of the presage predictor command if it is on Emacs's PATH."
  :type '(file :must-match t)
  :group 'presage-predictor)

(defcustom presage-predictor-args '("-s 10")
  "Args passed to the PRESAGE executable."
  :type '(repeat (string :tag "Argument"))
  :group 'presage-predictor)

(defcustom presage-predictor-process-timeout 2.5
  "Number of seconds to wait for an answer from presage.
If presage takes longer than that to answer, the answer will be
ignored."
  :type '(float)
  :group 'presage-predictor)

(defcustom presage-predictor-message-delay 0.4
  "Time to wait before displaying a message while waiting for results.

If completion takes longer than that time, a message is displayed
on the minibuffer to make it clear what's happening. Set to nil
to never display any such message. 0 to always display it.")

(defcustom presage-predictor-initial-timeout 30
  "Timeout value to apply when talking to presage for the first time.
The first thing presage is supposed to do is process /etc/presage.xml,
which typically takes a long time."
  :type '(float)
  :group 'presage-predictor)


;;; ---------- Internal variables and constants

(defvar presage-predictor-process nil
  "Presage process object.")

;;; ---------- Functions: completion
;;;###autoload
(defun company-presage-backend (command &optional arg &rest ignored)
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-presage-backend))
    (prefix (and (eq major-mode 'fundamental-mode)
                 (company-grab-symbol)))
    (candidates (presage-predictor-comm arg))
    (meta (format "This value is named %s" arg))))
;;;###autoload
(defun presage-predictor-setup ()
  "Register presage predictor for the company mode.

This function adds `company-presage-backend' to the completion
backend list of company mode, `company-backends'.

This function is convenient, but it might not be the best way of enabling
presage predictor in your .emacs file because it forces you to load the module
before it is needed.  For an autoload version, add:

  (autoload 'company-presage-backend \"presage-predictor\"
    \"PRESAGE PREDICTOR completion backend\")
  (add-to-list 'company-backends 'company-presage-backend)"
  (add-to-list 'company-backends 'company-presage-backend)
  )

;;; ---------- Functions: getting candidates from presage

(defun presage-predictor-comm (word-prefix)
  "Set WORD-PREFIX, return the result.
This function starts a separate presage process if necessary, sets
up the completion environment (word-prefix) and calls presage.
The result is a list of candidates, which might be empty."
  ;; start process now, to make sure inferior process running.
  (let ((process (presage-predictor-require-process))
        (candidates)
        (completion-status))
    (setq completion-status (presage-predictor-send (concat " " word-prefix)))
    (setq candidates
          (when (eq 0 completion-status)
            (presage-predictor-extract-candidates)))
    (if (not candidates)
        nil
      candidates)))

(defun presage-predictor-extract-candidates ()
  "Extract the completion candidates from the process buff.
This function takes the content of the completion process buffer,
splits it by newlines."
  (let ((candidates) (result (list)))
    (setq candidates (with-current-buffer (presage-predictor-buffer)
                       (split-string (buffer-string) "\n" t)))
    candidates
    ))


;;; ---------- Functions: presage subprocess
(defun presage-predictor-require-process ()
  "Return the presage predictor process or start it.

If a presage predictor process is already running, return it.

Otherwise, create a presage predictor process and return the
result.  This can take a long time, since presage needs to start completely
before this function returns to be sure everything has been
initialized correctly.

The process uses `presage-predictor-prog' to figure out the path to
presage on the current system."
  (if (presage-predictor-is-running)
      presage-predictor-process
    ;; start process
    (let ((process) (process-connection-type nil) )
      (unwind-protect
	  (progn
	    (setq process
		  (apply 'start-process
                         (append
                          `("*presage-predictor*"
                            ,(generate-new-buffer-name " presage-predictor")
                            ,presage-predictor-prog )
                          presage-predictor-args)))
	    (set-process-query-on-exit-flag process nil)
            
	    (presage-predictor-send "" process presage-predictor-initial-timeout)
	    (setq presage-predictor-process process)
	    (setq process nil)
	    presage-predictor-process)
	;; finally
	(progn
	  (when process
	    (condition-case err
		(presage-predictor-kill process)
	      (error nil))))))))

;;;###autoload
(defun presage-predictor-reset ()
  "Force the next predictive text entry to start with a fresh PRESAGE process.
This function kills any existing PRESAGE PREDICTOR completion process.  This way, the
next time PRESAGE PREDICTOR completion is requested, a new process will be created with
the latest configuration.

Call this method if you have updated your /etc/presage.xml or any presage language models
and would like presage predictor in Emacs to take these changes into account."
  (interactive)
  (presage-predictor-kill presage-predictor-process)
  (setq presage-predictor-process nil))

(defun presage-predictor-kill (process)
  "Kill PROCESS and its buffer."
  (when process
    (when (eq 'run (process-status process))
      (kill-process process))
    (let ((buffer (process-buffer process)))
      (when (buffer-live-p buffer)
	(kill-buffer buffer)))))

(defun presage-predictor-buffer ()
  "Return the buffer of the PRESAGE process, create the PRESAGE process if necessary."
  (process-buffer (presage-predictor-require-process)))

(defun presage-predictor-is-running ()
  "Check whether the presage predictor process is running."
  (and presage-predictor-process (eq 'run (process-status presage-predictor-process))))

(defun presage-predictor-send (word-prefix &optional process timeout)
  "Send a WORD-PREFIX to the presage predictor process.

word-prefix should be a prefix of a word, without the final newline.

PROCESS should be the presage process, if nil this function calls
`presage-predictor-require-process' which might start a new process.

TIMEOUT is the timeout value for this operation, if nil the value of
`presage-predictor-process-timeout' is used.

Once predicting text entry with this word-prefix has run without errors, you will find the result
of prediction of the word-prefix in the presage predictor process buffer.

Return the status code of entry prediction of the word-prefix, as a number."
  (let ((process (or process (presage-predictor-require-process)))
        (timeout (or timeout presage-predictor-process-timeout)))
    (with-current-buffer (process-buffer process)
      (erase-buffer)
      (set-process-query-on-exit-flag process nil)
      (process-send-string process (concat word-prefix "\n"))
      (while (not (progn (goto-char 1) (search-forward ">" nil t)))
        (unless (accept-process-output process timeout)
          (error "Timeout while waiting for an answer from presage-predictor process")))
      (let* ((prompt-position (point))
             (context-position (progn (search-backward "-- Context:" nil t) (point)))
             (status-code (if (equal (point-min) context-position) 1 0)))
        (delete-region context-position (point-max))
        (goto-char (point-min))
        (display-buffer (process-buffer process))
        ;; (message "status: %d content: \"%s\""
        ;;          status-code
        ;;          (buffer-substring-no-properties
        ;;           (point-min) (point-max)))

        status-code))))

(provide 'presage-predictor)
;;; presage-predictor.el ends here
