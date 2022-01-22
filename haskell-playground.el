;;; haskell-playground.el --- Local Haskell playground for short code snippets.

;; Copyright (C) 2022  nilninull
;; Author: (Haskell version) nilninull <nilninull@gmail.com>
;; URL: https://github.com/nilninull/haskell-playground
;; Version: 0.1.0
;; Keywords: tools, haskell
;; Package-Requires: ((emacs "24.3"))

;; Copyright (C) 2016-2017 Alexander I.Grafov (axel)
;; Author: Alexander I.Grafov <grafov@gmail.com> + all the contributors (see git log)
;; URL: https://github.com/grafov/haskell-playground

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:
;; This program was ported from rust-playground.
;; And rust-playground is port of github.com/grafov/go-playground for Go language.

;; Local playground for the Haskell programs similar to play.rust-lang.org.
;; `M-x haskell-playground` and type you haskell code then make&run it with `C-c C-c`.
;; Toggle between foo.cabal and Main.hs with `C-c b`
;; Delete the current playground and close all buffers with `C-c k`

;; Playground requires preconfigured environment for Haskell language.

;; If you want to automatically enable haskell-playground-mode for
;; previously created haskell-playground files, write below code
;; in your config file.
;; (add-hook 'haskell-mode-hook 'haskell-playground-enable)

;;; Code:

(require 'compile)
(require 'time-stamp)

(defgroup haskell-playground nil
  "Options specific to Haskell Playground."
  :group 'haskell)

;; I think it should be defined in haskell-mode.
(defcustom haskell-playground-run-command "cabal run"
  "The ’haskell’ command."
  :type 'string
  :group 'haskell-playground)

(defcustom haskell-playground-confirm-deletion t
  "Non-nil means you will be asked for confirmation on the snippet deletion with `haskell-playground-rm'.

By default confirmation required."
  :type 'boolean
  :group 'haskell-playground)

(defcustom haskell-playground-basedir (locate-user-emacs-file "haskell-playground")
  "Base directory for playground snippets."
  :type 'directory
  :group 'haskell-playground)

(defcustom haskell-playground-cabal-template
  "cabal-version:      2.4
name:               foo
version:            0.1.0.0
author:             Haskell Example
maintainer:         haskell-snippet@example.com
executable foo
    main-is:          Main.hs
    build-depends:    base
    hs-source-dirs:   app
    default-language: Haskell2010"
  "When creating a new playground, this will be used as the foo.cabal file"
  :type 'string
  :group 'haskell-playground)

(defcustom haskell-playground-Main-hs-template
  "main :: IO ()
main = do
  undefined"
  "When creating a new playground, this will be used as the body of the Main.hs file.

Please match the value of `haskell-playground-Main-hs-template-starting-word'"
  :type 'string
  :group 'haskell-playground)

(defcustom haskell-playground-Main-hs-template-starting-word "undefined"
  "When creating a new playground, search this word for starting cursor position.

Please match the value of `haskell-playground-Main-hs-template'."
  :type 'string
  :group 'haskell-playground)

(define-minor-mode haskell-playground-mode
  "A place for playing with Haskell code and export it in short snippets."
  :init-value nil
  :lighter " Play(Haskell)"
  :keymap (let ((map (make-sparse-keymap)))
	    (define-key map (kbd "C-c C-c") 'haskell-playground-exec)
	    (define-key map (kbd "C-c b") 'haskell-playground-switch-between-cabal-and-main)
	    (define-key map (kbd "C-c k") 'haskell-playground-rm)
	    map))

(defun haskell-playground-dir-name (&optional snippet-name)
  "Get the name of the directory where the snippet will exist, with SNIPPET-NAME as part of the directory name."
  (file-name-as-directory (concat (file-name-as-directory haskell-playground-basedir)
				  (time-stamp-string "at-%:y-%02m-%02d-%02H%02M%02S"))))

(defun haskell-playground-snippet-main-file-name (basedir)
  "Get the snippet Main.hs file from BASEDIR."
  (concat basedir (file-name-as-directory "app") "Main.hs"))

(defun haskell-playground-cabal-file-name (basedir)
  "Get the foo.cabal filename from BASEDIR."
  (concat basedir "foo.cabal"))

(defun haskell-playground-get-snippet-basedir (&optional path)
  "Get the path of the dir containing this snippet.
Start from PATH or the path of the current buffer's file, or NIL if this is not a snippet."
  (unless path
    (setq path (buffer-file-name)))
  (when (and path (not (string= path "/")))
    (let ((base (expand-file-name haskell-playground-basedir))
	  (path-parent (file-name-directory (directory-file-name path))))
      (if (string= (file-name-as-directory base)
		   (file-name-as-directory path-parent))
	  path
	(haskell-playground-get-snippet-basedir path-parent)))))

;; I think the proper way to check for this is to test if the minor mode is active
;; TODO base this check off the minor mode, once that mode gets set on all files
;; in a playground
(defmacro in-haskell-playground (&rest forms)
  "Execute FORMS if current buffer is part of a haskell playground.
Otherwise message the user that they aren't in one."
  `(if (not (haskell-playground-get-snippet-basedir))
       (message "You aren't in a Haskell playground.")
     ,@forms))

(defun haskell-playground-exec ()
  "Save the buffer then run Haskell compiler for executing the code."
  (interactive)
  (in-haskell-playground
   (save-buffer t)
   (let ((default-directory (haskell-playground-get-snippet-basedir)))
     (compile haskell-playground-run-command))))

;;;###autoload
(defun haskell-playground ()
  "Run playground for Haskell language in a new buffer."
  (interactive)
  ;; get the dir name
  (let* ((snippet-dir (haskell-playground-dir-name))
	 (snippet-file-name (haskell-playground-snippet-main-file-name snippet-dir))
	 (snippet-cabal-file (haskell-playground-cabal-file-name snippet-dir)))
    ;; create a buffer for foo.cabal and switch to it
    (make-directory snippet-dir t)
    (set-buffer (create-file-buffer snippet-cabal-file))
    (set-visited-file-name snippet-cabal-file t)
    (haskell-playground-mode)
    (insert haskell-playground-cabal-template)
    (unless (= ?\n (char-before (point-max)))
      (insert ?\n))
    (haskell-playground-insert-template-head "snippet of code" snippet-dir)
    (save-buffer)
    ;;now do app/Main.hs
    (make-directory (concat snippet-dir "app"))
    (switch-to-buffer (create-file-buffer snippet-file-name))
    (set-visited-file-name snippet-file-name t)
    (haskell-playground-insert-template-head "snippet of code" snippet-dir)
    (unless (= ?\n (char-before (point-max)))
      (insert ?\n))
    (insert haskell-playground-Main-hs-template)
    ;; back up to a good place to edit from
    (goto-char (point-min))
    (when (string-match-p haskell-playground-Main-hs-template-starting-word
			  haskell-playground-Main-hs-template)
      (search-forward haskell-playground-Main-hs-template-starting-word nil t)
      (search-backward haskell-playground-Main-hs-template-starting-word nil t))
    (haskell-playground-mode)))

(defun haskell-playground-switch-between-cabal-and-main ()
  "Change buffers between the Main.hs and foo.cabal files for the current snippet."
  (interactive)
  (in-haskell-playground
   (let ((basedir (haskell-playground-get-snippet-basedir)))
     ;; If you're in a haskell snippet, but in some file other than Main.hs,
     ;; then just switch to Main.hs
     ;; how to switch to existing or create new, given filename?
     (if (string= "Main.hs" (file-name-nondirectory buffer-file-name))
	 (find-file (haskell-playground-cabal-file-name basedir))
       (find-file (haskell-playground-snippet-main-file-name basedir))))))

(defun haskell-playground-insert-template-head (description basedir)
  "Inserts a template about the snippet into the file."
  (let ((starting-point (point)))
    (insert (format
	     "%s @ %s

=== Haskell Playground ===
This snippet is in: %s

Execute the snippet: C-c C-c
Delete the snippet completely: C-c k
Toggle between Main.hs and foo.cabal: C-c b" description (time-stamp-string "%:y-%02m-%02d %02H:%02M:%02S") basedir))
    (comment-region starting-point (point))))

(defun haskell-playground-get-all-buffers ()
  "Get all the buffers visiting foo.cabal or any *.hs file under app/."
  (in-haskell-playground
   (let* ((basedir (haskell-playground-get-snippet-basedir))
	  (srcdir (concat basedir (file-name-as-directory "app"))))
     ;; now get the fullpath of foo.cabal, and the fullpath of every file under app/
     (remove 'nil (mapcar 'find-buffer-visiting
			   (cons (concat basedir "foo.cabal")
				 (directory-files srcdir t ".*\.hs")))))))

;;;###autoload
(defun haskell-playground-rm ()
  "Remove files of the current snippet together with directory of this snippet."
  (interactive)
  (in-haskell-playground
   (let ((playground-basedir (haskell-playground-get-snippet-basedir)))
     (if playground-basedir
	 (when (or (not haskell-playground-confirm-deletion)
		   (y-or-n-p (format "Do you want delete whole snippet dir %s? "
				     playground-basedir)))
	   (dolist (buf (haskell-playground-get-all-buffers))
	     (kill-buffer buf))
	   (delete-directory playground-basedir t t))
       (message "Won't delete this! Because %s is not under the path %s. Remove the snippet manually!" (buffer-file-name) haskell-playground-basedir)))))

;;;###autoload
(defun haskell-playground-enable ()
  "Enable `haskell-playground-mode' when in `haskell-playground-basedir'.

The expected usage is to add it to haskell-mode-hook.
\(add-hook 'haskell-mode-hook 'haskell-playground-enable)"
  (when (string-prefix-p (file-name-as-directory (expand-file-name haskell-playground-basedir))
			 (buffer-file-name))
    (haskell-playground-mode)))

(provide 'haskell-playground)
;;; haskell-playground.el ends here
