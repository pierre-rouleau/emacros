;;; emacros.el --- Package for organizing and handling keyboard macros.  -*- lexical-binding: t; -*-

;; Original author: Thomas Becker <emacros@thbecker.net>
;; Modifications, updates after EMacros 5.0:  Pierre Rouleau

;; This is EMACROS 5.1, an extension to GNU Emacs.
;; Copyright (C) 1993, 2007, 2020 Free Software Foundation, Inc.

;; EMACROS is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY.  No author or distributor
;; accepts responsibility to anyone for the consequences of using it
;; or for whether it serves any particular purpose or works at all,
;; unless he says so in writing.  Refer to the GNU Emacs General Public
;; License for full details.

;; Everyone is granted permission to copy, modify and redistribute
;; EMACROS, but only under the conditions described in the
;; GNU Emacs General Public License.   A copy of this license is
;; supposed to have been given to you along with GNU Emacs so you
;; can know your rights and responsibilities.  It should be in a
;; file named COPYING.  Among other things, the copyright notice
;; and this notice must be preserved on all copies.

;; The HTML documentation for the Emacros package can be found at
;;
;; http://thbecker.net/free_software_utilities/emacs_lisp/emacros/emacros.html
;;
;; Send bug reports, questions, and comments to: emacros@thbecker.net



;;; Commentary:
;;
;; Usage:
;;
;; - Add the following code to your Emacs initialization code:
;;
;;   (add-hook 'find-file-hook 'emacros-load-macros)



;; The following describes the emacros commands ('*'), functions ('-'),
;; interactive functions ('+') and macros ('@') code hierarchy.
;;
;; - `emacros-dirname-expanded'
;; - `emacros-same-dirname'
;; - `emacros--macrop'
;; - `emacros--processed-mode-name'

;; - `emacros--db-mode-filename'
;; - `emacros--db-mode-filepath'
;; - `emacros--db-mode-str'

;; - `emacros-read-macro-name2'
;;   + `emacros--exit-macro-read2'

;; - `emacros-new-macro'

;; * `emacros-name-last-kbd-macro-add'
;;   - `emacros-read-macro-name1'
;;     + `emacros--exit-macro-read1'
;;   - `emacros--select-scope'
;;     - `emacros--waitforkey'
;;     - `emacros--warn'
;;     - `emacros--continue-or-abort'
;;   - `emacros--is-overwrite-needed-and-allowed'
;;     - `emacros--is-kbmacro-in'
;;       @ `emacros--within'
;;     - `emacros--continue-or-abort'
;;   - `emacros--write-kbmacro-to'
;;      @ `emacros--within'

;; * `emacros-rename-macro'
;;   - `emacros-read-macro-name1'
;;     + `emacros--exit-macro-read1'

;; * `emacros-move-macro'
;; * `emacros-remove-macro'
;; * `emacros-execute-named-macro'
;; * `emacros-auto-execute-named-macro'
;; * `emacros-load-macros'
;; * `emacros-show-macros'
;; * `emacros-show-macro-names'
;; * `emacros-refresh-macros'
;; - `emacros-insert-kbd-macro'
;; - `emacros-remove-macro-definition-from-file'
;; - `emacros-remove-macro-definition'
;; - `emacros-make-macro-list'

;; ---------------------------------------------------------------------------
;;; Code:

;;; TODO
;; - enhance ability to use the repeat command to execute the last executed
;;   emacro quickly. repeat fails at the moment with an error about the
;;   failed execution of emacros--exit-macro-read2.  However, we can use M-x
;;   to execute the named emacro and that can be repeated.  So, check if changing
;;   the execution code to use execute-extended-command would not solve the
;;   problem, but only after reviewing the code related to the 2 prompts.

;; - Enhance storage:
;;   - save kb-macros in pure Elisp, like elmacro does.  That would allow
;;     exchanging keyboard macros between users that do not have the same key
;;     bindings.
;;   - use one file per directory, use a zip or tar file
;;   - maintain a hash of each keyboard macro text, to ensure that the macros
;;     have not been tampered with??
;;   - allow macros to be byte compiled, to speed up?
;;   - package this with true elpa support and all that's needed for true autoload.

;; ---------------------------------------------------------------------------
;; Customization Support
;; ---------------------

(defgroup emacros nil
  "Emacros: organize recorded keyboard macros."
  :group 'convenience
  :group 'kmacro)

(defcustom emacros-global-dirpath "~"
  "Default directory for saving global kbd-macros."
  :type 'string)

(defcustom emacros-subdir-name ".emacros"
  "Name of sub-directory for saving the kbd-macro definition files.
The default is \".emacros\".
Any valid sub-directory name can be used.
You can also specify that you do not want to use any sub-directory
and save all emacros kbd-macro definition files directly in the
global or local directory.
NOTE:
 If you select a sub-directory the files stored in that directory
 have a visible name that start with \"for-\" and then finish with the major
 mode name.
 If you do not select a sub-directory, the emacros keyboard definition
 files all have a name that starts with \".emacros-for-\" and then end with
  the major mode name.  Note that they also have a name that starts with a
  period to hide the file under Unix.
 "
  :type '(choice
          (const :tag "Store all emacros kbd-macro definition files\n\
directly inside the current (local) or global directory." nil)
          (string :tag "Store them all inside the following\n\
sub-directory")))

;; ---------------------------------------------------------------------------
;; Variables
;; ---------

(defvar emacros-minibuffer-local-map
  nil
  "Local keymap for reading a new name for a keyboard macro from minibuffer.
Used by function `emacros-read-macro-name1'.")

(setq emacros-minibuffer-local-map (make-sparse-keymap))

(define-key emacros-minibuffer-local-map "\C-g" 'abort-recursive-edit)
(define-key emacros-minibuffer-local-map "\n" 'emacros--exit-macro-read1)
(define-key emacros-minibuffer-local-map "\r" 'emacros--exit-macro-read1)

(defvar-local emacros-glob-loc ?l
  "Default for saving named kbd-macros.
Value ?l means local, value ?g means global.")


(defvar-local emacros-last-name
  nil
  "Name of most recently named, renamed, moved, or executed kbd-macro.")

(defvar-local emacros-last-saved
  nil
  "Name of macro that was most recently moved or saved.

This is the name of the last macro moved or saved by function
`emacros-name-last-kbd-macro-add' with no prefix argument.")


(defvar emacros-ok
  nil
  "List of lists of directories from which kbd-macro files have been loaded.
Each list is headed by the name of the mode to which it pertains.")


(defvar emacros-read-existing-macro-name-history-list
  nil
  "History list variable for reading the name of an existing macro.")

;; ---------------------------------------------------------------------------

(defun emacros-dirname-expanded (dirname)
  "Return DIRNAME string fully expanded with path and single trailing slash."
  (file-name-as-directory (expand-file-name dirname)))

(defun emacros-same-dirname (d1 d2)
  "Return t if D1 and D2 correspond to the same directory name, nil otherwise."
  (string=
   (emacros-dirname-expanded d1)
   (emacros-dirname-expanded d2)))

(defun emacros--macrop (name)
  "Return t if the NAME symbol is the name of a keyboard macro.
Return nil otherwise."
  (and (null (integerp name))
       (fboundp name)
       (let ((sym-fu (symbol-function name)))
         (or (vectorp sym-fu)
             (stringp sym-fu)))))

(defun emacros--processed-mode-name ()
  "Return a valid mode name.
For all modes that have a name that ends with \"-mode\", use the name
without its \"-mode\" suffix.
For the others, if the current mode name contains no slash,
returns the current mode name.
Otherwise, returns the initial substring of the current mode name up to but
not including the first slash."
  (let ((major-mode-name (symbol-name major-mode)))
    (if (string-match "-mode\\'" major-mode-name)
        ;; for major-mode names that end with "-mode", just trim that off
        (substring major-mode-name 0 -5)
      ;; otherwise, use original code
      (let ((slash-pos-in-mode-name (string-match "/" mode-name)))
        (if slash-pos-in-mode-name
            (substring mode-name 0 slash-pos-in-mode-name)
          mode-name)))))

;; ---------------------------------------------------------------------------
;; Utilities - Identify name and location of the emacros kbd-macro def files
;; -------------------------------------------------------------------------

(defun emacros--db-mode-filename ()
  "Return the file name storing emacros for current major mode."
  ;; TODO: store all files inside a .emacros sub-directory.
  (format ".emacros-for-%s.el"
          (emacros--processed-mode-name)))

(defun emacros--db-mode-filepath (&optional global)
  "Return the absolute path for the macro storage file.
By default returns the local directory name unless GLOBAL
is non-nil, in which case it returns the global one.

The returned string is:
- the filename based on the current major mode,
- inside a \".emacros\" directory,
- inside the current (local) or global directory as specified
  by the user option variable `emacros-global-dirpath'."
  (let* ((dirpath      (if global
                           emacros-global-dirpath
                         default-directory))
         (dirname      (if emacros-subdir-name
                           (expand-file-name ".emacros" dirpath)
                         dirpath))
         (fname-format (if emacros-subdir-name
                           "for-%s.el"
                         ".emacros-for-%s.el")))
    (expand-file-name (format fname-format
                              (emacros--processed-mode-name))
                      dirname)))

(defun emacros--db-mode-str (&optional global)
  "Return \"local\" if GLOBAL is nil otherwise return \"global\"."
  (if global
      "global"
    "local"))

;; ---------------------------------------------------------------------------


(defun emacros--exit-macro-read1 ()
  "Terminate the new macro name from the minibuffer.
The equivalent of function `exit-minibuffer' for reading a new macroname
from minibuffer.  Used by function `emacros-read-macro-name1'."
  (interactive)
  (let* ((name (buffer-substring (minibuffer-prompt-end) (point-max)))
         (parse-list (append name nil)))
    (if (equal name "")
        (progn (ding)
               (insert "[Can't use empty string]")
               (goto-char (minibuffer-prompt-end))
               (sit-for 2)
               (delete-region (minibuffer-prompt-end) (point-max)))
      (catch 'illegal
        (while parse-list
          (let ((char (car parse-list)))
            (if (or
                 (and (>= char ?0) (<= char ?9))
                 (and (>= char ?A) (<= char ?Z))
                 (and (>= char ?a) (<= char ?z))
                 (memq char (list ?- ?_)))
                (setq parse-list (cdr parse-list))
              (goto-char (point-max))
              (let ((pos (point)))
                (ding)
                (if (= char ? )
                    (insert " [No blanks, please!]")
                  (insert " [Use letters, digits, \"-\", \"_\"]"))
                (goto-char pos)
                (sit-for 2)
                (delete-region (point) (point-max)))
              (throw 'illegal t))))
        (if (integerp (car (read-from-string name)))
            (and (goto-char (point-max))
                 (let ((pos (point)))
                   (ding)
                   (insert " [Can't use integer]")
                   (goto-char pos)
                   (sit-for 2)
                   (delete-region (point) (point-max))))
          (exit-minibuffer))))))



(defun emacros-read-macro-name1 (prompt &optional letgo)
  "Read a new name for a macro from minibuffer, prompting with PROMPT.
Rejects existing function names
with the exception of optional argument LETGO symbol."
  (let* ((name (read-from-minibuffer prompt "" emacros-minibuffer-local-map))
         (symbol (car (read-from-string name)))
         (sym-fu))
    (if (and (fboundp symbol)
             (not (equal symbol letgo)))
        (progn (setq sym-fu (symbol-function symbol))
               (if (and
                    (not (vectorp sym-fu))
                    (not (stringp sym-fu)))
                   (error "Function %s is already defined and not a keyboard macro" symbol))))
    symbol))

;; ---------------------------------------------------------------------------

(defvar emacros--default
  nil
  "Dynamic binding storage for emacros last name.
Temporary storage of the last used macro name for the
minibuffer completion of commands dealing with emacros.

Set by the function `emacros-read-macro-name2' to allow use inside
its minibuffer completion function `emacros--exit-macro-read2'.")

(defun emacros--exit-macro-read2 ()
  "Exit if the minibuffer contain a valid macro name.
Otherwise try to complete it.

This function substitutes `minibuffer-complete-and-exit'
when reading an existing macro or macroname as used by the
function `emacros-read-macro-name2'."
  (interactive)
  (if (or (not (= (minibuffer-prompt-end) (point-max)))
          emacros--default)
      (minibuffer-complete-and-exit)
    (ding)
    (goto-char (minibuffer-prompt-end))
    (insert "[No default]")
    (sit-for 2)
    (delete-region (minibuffer-prompt-end) (point-max))))

(defun emacros-read-macro-name2 (prompt)
  "Read an existing name of a kbd-macro, prompting with PROMPT.
PROMPT must be given without trailing colon and blank.
Supports minibuffer completion."
  (let ((emacros--default (emacros--macrop emacros-last-name))
        (inp))
    (unwind-protect
        (progn
          (substitute-key-definition 'minibuffer-complete-and-exit
                                     'emacros--exit-macro-read2
                                     minibuffer-local-must-match-map)
          (setq inp (completing-read
                     (format "%s%s: "
                             prompt
                             (if emacros--default
                                 (format " (default %s)" emacros-last-name)
                               ""))
                     obarray            ; collection: all objects
                     'emacros--macrop    ; predicate: that are macros
                     t                  ; require-match: must chose complete element
                     nil                ;
                     'emacros-read-existing-macro-name-history-list
                     (if emacros--default
                         (format "%s" emacros-last-name)
                       ""))))
      (substitute-key-definition 'emacros--exit-macro-read2
                                 'minibuffer-complete-and-exit
                                 minibuffer-local-must-match-map))
    (car (read-from-string inp))))

;; ---------------------------------------------------------------------------

(defun emacros-new-macro (name macro-text)
  "Assigns to the symbol NAME the function definition MACRO-TEXT.
- NAME       := macro name symbol
- MACRO-TEXT := string; the recorded macro keys.
This function is stored inside the emacros macro storage files."
  (fset name macro-text))

;; ---------------------------------------------------------------------------
;; Buffer/File protection macro
;; ----------------------------

(defmacro emacros--within (mbuf or fname do &rest body)
  "Evaluate BODY in the keyboard macro buffer MBUF or a new one for FNAME.
The OR and DO argument are cosmetic markers.
The file-saving hooks are disabled for the duration of the evaluation
and after evaluation the BODY everything is restored: if a new buffer
had to be opened for visiting FNAME it is killed.

Example:
  (emacros--within buf or filename
    do
     (some-call some-data)
     (some-other-call some-other-data)) "
  (declare (indent 3))
  ;; prevent byte-compile warning about unused cosmetic arguments
  (ignore or do)
  `(if (or ,mbuf (file-exists-p ,fname))
       (let ((find-file-hook nil)
             (emacs-lisp-mode-hook nil)
             (after-save-hook nil)
             (kill-buffer-hook nil))
         (save-excursion
           (if ,mbuf
               (set-buffer ,mbuf)
             (find-file ,fname))
           ,@body
           (unless ,mbuf
             (kill-buffer (buffer-name)))))
     (error (format "No buffer, no file %s!" ,fname))))

;; ---------------------------------------------------------------------------
;; Store a new keyboard macro recording
;; ------------------------------------

(defun emacros--waitforkey (msg)
  "Display message and wait for any key."
  (message "%s\nPress any key to continue: " msg)
  (read-char))

(defun emacros--warn (msg)
  "Warn user.  Beep, display MSG, wait and return typed key."
  (ding)
  (message "%s" msg)
  (read-char))

(defun emacros--continue-or-abort (msg continue-question)
  "Warn user. Beep, display MSG, prompt to continue with CONTINUE-QUESTION.
Both MSG and CONTINUE-QUESTION are strings.
MSG must end with a period.
CONTINUE-QUESTION must end with a question mark.
If user selects to continue the function return t,
otherwise it raise a \"Aborted\" user-error."
  (ding)
  (if (y-or-n-p (format "%s  %s " msg continue-question))
      t
    (user-error "Aborted")))

(defun emacros--select-scope (prompt-user)
  "Return the keyboard macro definition type and the storage file.
Prompt the user if PROMPT-USER is non-nil, otherwise
use the current settings.

The current settings are identified by:
- variable `emacros-glob-loc'
  - location of the current (local) directory or
    the global directory identified by the user
    option variable `emacros-??'

Return a (gl . filepath) cons cell, where
gl is ?g or ?l (identifying global or local)
and filepath is the absolute path and name of the keyboard definition file."
  (let* ((gl     emacros-glob-loc)
         (fname (emacros--db-mode-filepath (= gl ?g))))
    (if prompt-user
        ;; request to let user select the file
        (setq fname
              (expand-file-name
               (read-file-name
                (format "Write macro to file (default %s): " fname)
                default-directory
                fname)))
      ;; no request to explicitly select a file
      (let ((cursor-in-echo-area t))
        (if (emacros-same-dirname default-directory emacros-global-dirpath)
            ;; in global directory: use global
            (progn
              (emacros--waitforkey
               "Using global as current = global for this buffer.")
              (setq gl ?g))
          ;; not in global directory: make user select the scope
          (message "Save as local or global macro? (l/g, default %s) "
                   (emacros--db-mode-str (= emacros-glob-loc ?g)))
          (setq gl (read-char))
          (while (not (memq gl (list ?l ?g ?\r)))
            (setq gl
                  (emacros--warn
                   (format
                    "Please answer l for local, g for global, or RET for %s: "
                    (emacros--db-mode-str (= emacros-glob-loc ?g))))))
        (when (= gl ?\r)
          (setq gl emacros-glob-loc))
        (setq fname (emacros--db-mode-filepath (= gl ?g))))))
      (cons gl fname)))

(defun emacros--is-kbmacro-in (kbmacro buf filename)
  "Check if KBMACRO is present in either BUF or FILENAME.
Return t if it is, nil otherwise."
  (let ((macro-name-exists nil))
    (emacros--within buf or filename
      do
      (goto-char (point-min))
      (when (search-forward
             (format "(emacros-new-macro '%s " kbmacro) nil :no-error)
        (setq macro-name-exists t)))
    macro-name-exists))

(defun emacros--is-overwrite-needed-and-allowed
    (macro-file buf kbmacro gl use-custom-file filename)
  "Check if KBMACRO definition is in a MACRO-FILE or buffer BUF.
If so, prompt for overwriting it.
Return t if user want to overwrite existing file/buffer,
nil if overwrite is not allowed,
issue a user-error when user wants to abort."
  (if (and (not buf)
           (not (file-exists-p filename)))
      ;; no buffer & no file: no need to overwrite
      nil
    ;; buffer or file exist: check if macro name exists
    (if (emacros--is-kbmacro-in kbmacro buf filename)
        ;; If macro already exist, check if user wants to overwrite
        ;; and return t to overwrite, abort if not.
        ;; If macro does not exist return nil.
        (emacros--continue-or-abort
         (format "Macro %s exists in %s"
                 kbmacro
                 (if use-custom-file
                     (format "file %s" filename)
                   (format "%s macro file %s"
                           (emacros--db-mode-str (= gl ?g))
                           macro-file)))
         "Overwrite?"))))

(defun emacros--write-kbmacro-to
    (macro-name macro-code buf filename overwrite)
  "Write keyboard macro of name MACRO-NAME and code MACRO-CODE.
Store it in either buffer BUF or file FILENAME.
Allow OVERWRITE is requested."
  ;; disable hooks while writing to file
  (emacros--within buf or filename
    do
    (emacros-insert-kbd-macro macro-name macro-code overwrite)
    ;; prevent backup
    (save-buffer 0)))

(defun emacros-name-last-kbd-macro-add (&optional arg)
  "Assigns a name to the last keyboard macro defined.
Accepts letters and digits as well as \"_\" and \"-\".
Requires at least one non-numerical character.
Prompts for a choice betwen local and global saving.
With ARG, prompt the user for the name of a file
to save to. Default is the last location that was saved
or moved to in the current buffer."
  (interactive "P")
  (unless last-kbd-macro
      (user-error "No kbd-macro defined!"))
  (let* ((symbol     (emacros-read-macro-name1 "Name for last kbd-macro: "))
         (macro-file (emacros--db-mode-filename))
         (gl.fname   (emacros--select-scope arg))
         (gl         (car gl.fname))
         (filename   (cdr gl.fname))
         (buf        (get-file-buffer filename)))
    (when (and buf
               (buffer-modified-p buf))
      ;; User is about to store the definition of a new macro in a file
      ;; that is opened in Emacs with unsaved modifications.
      ;; Warn the user and allow aborting.
      (emacros--continue-or-abort
       (format
        "Buffer visiting %s modified."
        (if arg
            (format "file %s" filename)
          (format "%s macro file" (emacros--db-mode-str (= gl ?g)))))
       "Continue? (Will save!)?"))
    (emacros--write-kbmacro-to symbol
                               last-kbd-macro
                               buf
                               filename
                               (emacros--is-overwrite-needed-and-allowed
                                macro-file buf symbol gl arg filename))
    (message "Wrote definition of %s to %s"
             symbol
             (if arg
                 (format "file %s" filename)
               (format "%s file %s"
                       (emacros--db-mode-str (= gl ?g))
                       (emacros--db-mode-filepath (= gl ?g)))))
    ;; Store all info.
    (unless arg
      (setq emacros-glob-loc gl))
    (fset symbol last-kbd-macro)
    (setq emacros-last-name symbol)
    (setq emacros-last-saved (if arg nil symbol))))

;; ---------------------------------------------------------------------------

(defun emacros-rename-macro ()
  "Renames macro in macrofile(s) and in current session.
Prompts for an existing name of a keyboard macro and a new name
to replace it.  Default for the old name is the name of the most recently
named, inserted, or manipulated macro in the current buffer."
  (interactive)
  (or (emacros-there-are-keyboard-macros) (error "No named kbd-macros defined"))
  (let* ((old-name (emacros-read-macro-name2 "Replace macroname"))
         (new-name (emacros-read-macro-name1
                    (format "Replace macroname %s with: " old-name) old-name))
         (macro-file (emacros--db-mode-filename))
         (filename)
         (local-macro-filename)
         (global-macro-filename)
         (buf)
         (old-name-found)
         (new-name-found)
         (skip-this-file nil)
         (renamed))
    (while (equal new-name old-name)
      (or (ding)
          (y-or-n-p
           (format "%s and %s are identical.  Repeat choice for new name? "
                   old-name new-name))
          (error "Aborted"))
      (setq new-name
            (emacros-read-macro-name1
             (format "Replace macroname %s with: " old-name) old-name)))
    (setq local-macro-filename  (emacros--db-mode-filepath))
    (setq global-macro-filename (emacros--db-mode-filepath :global))
    (setq filename local-macro-filename)
    (if (and (setq buf (get-file-buffer filename))
             (buffer-modified-p buf))
        (or
         (ding)
         (y-or-n-p "Buffer visiting local macro file modified.  Continue? (May save!)? ")
         (error "Aborted")))
    (while filename
      (when (or buf (file-exists-p filename))
        (emacros--within buf or filename
          do
          (goto-char (point-min))
          (when (search-forward
                 (format "(emacros-new-macro '%s " old-name)
                 (point-max) t)
            (setq old-name-found t))
          (goto-char (point-min))
          (when (search-forward
                 (format "(emacros-new-macro '%s " new-name)
                 (point-max) t)
            (setq new-name-found t))))
      (when old-name-found
        (when new-name-found
          (ding)
          (if (y-or-n-p
               (format "Macro %s exists in %s macro file %s.  Overwrite? "
                       new-name
                       (if (equal filename local-macro-filename) "local" "global")
                       macro-file))
              (emacros-remove-macro-definition-from-file new-name buf filename)
            (setq skip-this-file t)))
        (if (not skip-this-file)
            (emacros--within buf or filename
              do
              (goto-char (point-min))
              (when (search-forward (format "(emacros-new-macro '%s " old-name) nil :noerror)
                (let ((end (point)))
                  (beginning-of-line)
                  (delete-region (point) end))
                (insert (format "(emacros-new-macro '%s "
                                new-name))
                (if renamed
                    (setq renamed (concat renamed " and ")))
                (setq renamed (concat renamed
                                      (if (equal filename local-macro-filename)
                                          "local"
                                        "global")))
                (save-buffer 0)))))
      (if (equal filename global-macro-filename)
          (setq filename nil)
        (setq filename global-macro-filename)
        (setq old-name-found nil)
        (setq new-name-found nil)
        (setq skip-this-file nil)
        (if (and (setq buf (get-file-buffer filename))
                 (buffer-modified-p buf))
            (or
             (ding)
             (y-or-n-p
              (format
               "Buffer visiting global macro file modified.  Continue? (May save!)? "))
             (error "Aborted")))))
    (or renamed
        (error
         "Macro named %s not found or skipped at user request in current local and global file %s: no action taken"
         old-name macro-file))
    (fset new-name (symbol-function old-name))
    (fmakunbound old-name)
    (setq emacros-last-name new-name)
    (and (equal old-name emacros-last-saved)
         (setq emacros-last-saved new-name))
    (message "Renamed macro named %s to %s in %s file %s"
             old-name
             new-name
             renamed
             macro-file)))

(defun emacros-move-macro ()
  "Move macro from local to global macro file or vice versa.
Prompts for the name of a keyboard macro and a choice between
\"from local\" and \"from global\", then moves the definition of the
macro from the current local macro file to the global one or
vice versa. Default is the name of the most recently saved, inserted,
or manipulated macro in the current buffer."
  (interactive)
  (or (emacros-there-are-keyboard-macros) (error "No named kbd-macros defined"))
  (if (emacros-same-dirname default-directory emacros-global-dirpath)
      (error "Local = global in this buffer"))
  (let ((name (emacros-read-macro-name2 "Move macro named"))
        (macro-file (emacros--db-mode-filename))
        (gl)
        (moved)
        (filename1)
        (filename2)
        (buf1)
        (buf2)
        (name-found-in-source nil)
        (name-found-in-target nil)
        (buffername))
    (let ((cursor-in-echo-area t))
      (message "Move FROM local or FROM global? (l/g%s) "
               (if (equal name emacros-last-saved)
                   (format ", default %s"
                           (if (= emacros-glob-loc ?g) "global" "local")) ""))
      (setq gl (read-char))
      (while (not (if (equal name emacros-last-saved)
                      (memq gl (list ?l ?g ?\r))
                    (memq gl (list ?l ?g))))
        (ding)
        (message
         "Please answer l for local, g for global%s: "
         (if (equal name emacros-last-saved)
             (format ", or RET for %s"
                     (if (= emacros-glob-loc ?g) "global" "local")) ""))
        (setq gl (read-char))))
    (and (= gl ?\r) (setq gl emacros-glob-loc))
    (if (= gl ?l)
        (progn (setq filename1 (emacros--db-mode-filepath))
               (setq filename2 (emacros--db-mode-filepath :global)))
      (setq filename1 (expand-file-name macro-file emacros-global-dirpath))
      (setq filename2 (expand-file-name macro-file default-directory)))
    (if (and (setq buf1 (get-file-buffer filename1))
             (buffer-modified-p buf1))
        (or
         (ding)
         (y-or-n-p
          (format
           "Buffer visiting %s macro file modified.  Continue? (May save!)? "
           (if (= gl ?g) "global" "local")))
         (error "Aborted")))
    (if (and (setq buf2 (get-file-buffer filename2))
             (buffer-modified-p buf2))
        (or
         (ding)
         (y-or-n-p
          (format
           "Buffer visiting %s macro file modified.  Continue? (May save!)? "
           (if (= gl ?g) "local" "global")))
         (error "Aborted")))
    (let ((find-file-hook nil)
          (emacs-lisp-mode-hook nil)
          (after-save-hook nil)
          (kill-buffer-hook nil))
      (save-excursion
        (if (or buf1 (file-exists-p filename1))
            (progn (if buf1
                       (set-buffer buf1)
                     (find-file filename1))
                   (goto-char (point-min))
                   (if (search-forward
                        (format "(emacros-new-macro '%s " name)
                        (point-max) t)
                       (setq name-found-in-source t))
                   (or buf1 (kill-buffer (buffer-name)))))
        (if (or buf2 (file-exists-p filename2))
            (progn (if buf2
                       (set-buffer buf2)
                     (find-file filename2))
                   (goto-char (point-min))
                   (if (search-forward
                        (format "(emacros-new-macro '%s " name)
                        (point-max) t)
                       (setq name-found-in-target t))
                   (or buf2 (kill-buffer (buffer-name)))))))
    (if (not name-found-in-source)
        (error "Macro named %s not found in %s file %s"
               name (if (= gl ?l) "local" "global") macro-file))
    (if name-found-in-target
        (progn (ding)
               (if (y-or-n-p
                    (format "Macro %s exists in %s macro file %s.  Overwrite? "
                            name
                            (if (= gl ?l) "global" "local")
                            macro-file))
                   (emacros-remove-macro-definition-from-file name buf2 filename2)
                 (error "Aborted"))))
    (let ((find-file-hook nil)
          (emacs-lisp-mode-hook nil)
          (after-save-hook nil)
          (kill-buffer-hook nil))
      (setq moved nil)
      (save-excursion
        (if buf1 (set-buffer buf1)
          (find-file filename1))
        (setq buffername (buffer-name))
        (goto-char (point-min))
        (if (search-forward
             (format "(emacros-new-macro '%s " name) (point-max) t)
            (progn (setq moved t)
                   (beginning-of-line)
                   (let ((beg (point)))
                     (search-forward "\n(emacros-new-macro '"
                                     (point-max) 'move)
                     (beginning-of-line)
                     (let ((end (point)))
                       (save-excursion
                         (if buf2 (set-buffer buf2)
                           (find-file filename2))
                         (goto-char (point-max))
                         (insert-buffer-substring buffername beg end)
                         (save-buffer 0)
                         (or buf2 (kill-buffer (buffer-name))))
                       (delete-region beg end)))
                   (save-buffer 0)))
        (or buf1 (kill-buffer buffername))))
    (if (null moved)
        (error "Macro named %s not found in %s file %s"
               name (if (= gl ?l) "local" "global") macro-file)
      (setq emacros-last-name name)
      (setq emacros-last-saved name)
      (if (= gl ?l)
          (setq emacros-glob-loc ?g)
        (setq emacros-glob-loc ?l))
      (message "Moved macro named %s to %s file %s"
               name (if (= gl ?l) "global" "local") macro-file))))

(defun emacros-remove-macro ()
  "Remove macro from current session and from current macro files.
The macroname defaults to the name of the most recently saved,
inserted, or manipulated macro in the current buffer."
  (interactive)
  (or (emacros-there-are-keyboard-macros) (error "No named kbd-macros defined"))
  (let* ((name (emacros-read-macro-name2 "Remove macro named"))
         (macro-file            (emacros--db-mode-filename))
         (local-macro-filename  (emacros--db-mode-filepath))
         (global-macro-filename (emacros--db-mode-filepath :global))
         (filename              local-macro-filename)
         (buf)
         (deleted))
    (if (and (setq buf (get-file-buffer filename))
             (buffer-modified-p buf))
        (or
         (ding)
         (y-or-n-p "Buffer visiting local macro file modified.  Continue? (May save!)? ")
         (error "Aborted")))
    (while filename
      (let ((find-file-hook nil)
            (emacs-lisp-mode-hook nil)
            (after-save-hook nil)
            (kill-buffer-hook nil))
        (save-excursion
          (if (or buf (file-exists-p filename))
              (progn (if buf
                         (set-buffer buf)
                       (find-file filename))
                     (goto-char (point-min))
                     (if (search-forward
                          (format "(emacros-new-macro '%s " name)
                          (point-max) t)
                         (progn (beginning-of-line)
                                (let ((beg (point)))
                                  (search-forward "\n(emacros-new-macro '"
                                                  (point-max) 'move)
                                  (beginning-of-line)
                                  (delete-region beg (point)))
                                (if deleted
                                    (setq deleted (concat deleted " and ")))
                                (setq deleted (concat deleted
                                                      (if (equal filename local-macro-filename)
                                                          "local"
                                                        "global")))
                                (save-buffer 0)))
                     (or buf (kill-buffer (buffer-name)))))))
      (if (equal filename global-macro-filename)
          (setq filename nil)
        (setq filename global-macro-filename)
        (if (and (setq buf (get-file-buffer filename))
                 (buffer-modified-p buf))
            (or
             (ding)
             (y-or-n-p
              (format
               "Buffer visiting global macro file modified.  Continue? (May save!)? "))
             (error "Aborted")))))
    (if (not deleted)
        (error
         "Macro named %s not found in current file(s) %s: no action taken"
         name macro-file))
    (fmakunbound name)
    (and (equal name emacros-last-saved)
         (setq emacros-last-saved nil))
    (and (equal name emacros-last-name)
         (setq emacros-last-name nil))
    (message "Removed macro named %s from %s file %s"
             name
             deleted
             macro-file)))

(defun emacros-execute-named-macro ()
  "Prompts for the name of a macro and execute it.  Does completion.
Default is the most recently saved, inserted, or manipulated macro
in the current buffer."
  (interactive)
  (or (emacros-there-are-keyboard-macros) (error "No named kbd-macros defined"))
  (let ((name (emacros-read-macro-name2 "Execute macro named")))
    (setq emacros-last-name name)
    (execute-kbd-macro name)))

(defun emacros-auto-execute-named-macro ()
  "Prompts for the name of a macro and execute when a match has been found.
Accepts letters and digits as well as \"_\" and \"-\".
Backspace acts normally, \\[keyboard-quit] exits, RET does rudimentary completion.
Default is the most recently saved, inserted, or manipulated macro
in the current buffer."
  (interactive)
  (or (emacros-there-are-keyboard-macros) (error "No named kbd-macros defined"))
  (let ((prompt (format "Auto-execute macro named%s: "
                        (if (emacros--macrop emacros-last-name)
                            (format " (default %s)" emacros-last-name)
                          "")))
        (name "")
        (is-macro)
        (char)
        (symbol)
        (compl))
    (while (not is-macro)
      (message "%s%s" prompt name)
      (setq char (read-char))
      (if (and (not (or (= char ?\r) (= char ?-) (= char ?_)
                        (= char ?\C-?)))
               (or (< char ?0)
                   (and (> char ?9) (< char ?A))
                   (and (> char ?Z) (< char ?a))
                   (> char ?z)))
          (and (null (ding))
               (message "%s%s [Illegal character]" prompt name)
               (sit-for 2))
        (if (= char ?\C-?)
        (if (equal name "")
            (ding)
          (setq name (substring name 0 (- (length name) 1))))
        (if (= char ?\r)
            (if (equal name "")
                (if (emacros--macrop emacros-last-name)
                    (progn (setq symbol emacros-last-name)
                           (setq is-macro t))
                  (ding)
                  (message "%s[No default]" prompt)
                  (sit-for 2))
              (if (null (setq compl
                              (try-completion name obarray 'emacros--macrop)))
                  (and (null (ding))
                       (message "%s%s [No match]" prompt name)
                       (sit-for 2))
                (if (equal compl name)
                    (and (null (ding))
                         (message "%s%s [Not yet unique]" prompt name)
                         (sit-for 2))
                  (setq name compl)
                  (setq symbol (car (read-from-string name)))
                  (setq is-macro (emacros--macrop symbol)))))
          (setq name (concat name (char-to-string char)))
          (setq symbol (car (read-from-string name)))
          (setq is-macro (emacros--macrop symbol))))))
    (setq emacros-last-name symbol)
    (execute-kbd-macro symbol)))

;;;###autoload
(defun emacros-load-macros ()
  "Attempt to load macro definitions file.
The file is mode-mac.el  (where \"mode\"
stands for the name of the current mode\)
from current directory and from directory emacros-global-dirpath.
If the mode name contains a forward slash, then only the
initial substring of the mode name up to but not including
the forward slash is used.

Does not consider files that have been loaded previously or
created during present session."
  (interactive)
  (let ((processed-mode-name (emacros--processed-mode-name)))
    (let ((macro-file (emacros--db-mode-filename))
          (mac-ok)
          (nextmac)
          (filename))
      (catch 'found-mode
        (while emacros-ok
          (setq nextmac (car emacros-ok))
          (setq emacros-ok (cdr emacros-ok))
          (and (equal processed-mode-name (car nextmac))
               (throw 'found-mode t))
          (setq mac-ok (cons nextmac mac-ok))
          (setq nextmac nil)))
      (setq filename (emacros--db-mode-filepath :global))
      (if (file-exists-p filename)
          (progn (or nextmac (load-file filename))
                 (setq emacros-glob-loc ?g)))
      (if (emacros-same-dirname default-directory emacros-global-dirpath)
          (progn (setq emacros-glob-loc ?g)
                 (setq nextmac (cons processed-mode-name (cdr nextmac))))
        (let ((dirlist (cdr nextmac))
              (dirli)
              (nextdir))
          (catch 'found-dir
            (while dirlist
              (setq nextdir (car dirlist))
              (setq dirlist (cdr dirlist))
              (and (equal default-directory nextdir) (throw 'found-dir t))
              (setq dirli (cons nextdir dirli))
              (setq nextdir nil)))
          (setq filename (expand-file-name macro-file default-directory))
          (if (file-exists-p filename)
              (progn (or nextdir (load-file filename))
                     (setq emacros-glob-loc ?l)))
          (setq nextmac (cons processed-mode-name
                              (append (cons default-directory dirli) dirlist)))))
      (setq emacros-ok (append (cons nextmac mac-ok) emacros-ok)))))

(defun emacros-show-macros ()
  "Displays the kbd-macros that are currently defined."
  (interactive)
  (let* ((mlist (emacros-make-macro-list))
         (next-macro-name (car mlist))
         (next-macro-definition (if next-macro-name (symbol-function next-macro-name) nil)))
    (or next-macro-name (error "No named kbd-macros defined"))
    (with-output-to-temp-buffer "*Help*"
      (princ "Below are all currently defined keyboard macros.\n")
      (princ "Use emacros-show-macro-names to see just the macro names.\n\n")
      (while next-macro-name
        (setq next-macro-definition (symbol-function next-macro-name))
        (princ next-macro-name)
        (princ "  ")
        (if (stringp next-macro-definition)
            (prin1 next-macro-definition)
          (let ((nextevent)
                (eventlist (append next-macro-definition nil))
                (in-char-sequence nil)
                (in-keyboard-event-sequence nil))
            (while eventlist
              (setq nextevent (car eventlist))
              (setq eventlist (cdr eventlist))
              (if (integerp nextevent)
                  (progn
                    (if in-keyboard-event-sequence (princ " "))
                    (if (not in-char-sequence) (princ "\""))
                    (if (and (<= 0 nextevent)
                             (<= nextevent 255))
                        (princ (char-to-string nextevent))
                      (princ (char-to-string 127))) ;for the lack of better
                    (setq in-char-sequence t)
                    (setq in-keyboard-event-sequence nil))
                (if in-char-sequence (princ "\""))
                (if (or in-char-sequence in-keyboard-event-sequence) (princ " "))
                (princ "<")
                (prin1 nextevent)
                (princ ">")
                (setq in-char-sequence nil)
                (setq in-keyboard-event-sequence t)))
            (if in-char-sequence (princ "\""))))
        (terpri)
        (setq mlist (cdr mlist))
        (setq next-macro-name (car mlist)))
      (princ " ") ; Funny, RMS is such a stickler for newline at EOF, and
                  ; his own printstream drops newlines at the end unless you
                  ; follow them by something else.
    (help-print-return-message))))

(defun emacros-show-macro-names (arg)
  "Display the names of the kbd-macros that are currently defined.
With prefix ARG, display macro names in a single column instead of the
usual two column format."
  (interactive "P")
  (let* ((mlist (emacros-make-macro-list))
         (current-macro-name (car mlist))
         (current-column 0)
         (padding-width 0))
    (or current-macro-name (error "No named kbd-macros defined"))
    (with-output-to-temp-buffer "*Help*"
      (princ "Below are the names of all currently defined macros.\n")
      (princ "Use emacros-show-macros to see the macro names with their definitions.\n\n")
      (while current-macro-name
        (if (not (eq current-column 0))
            (progn
              (setq padding-width (- 35 current-column))
              (if (< 0 padding-width)
                  (progn  (princ (make-string padding-width 32))
                          (setq current-column (+ current-column padding-width)))
                (terpri)
                (setq current-column 0))))
        (setq current-macro-name (prin1-to-string current-macro-name))
        (princ current-macro-name)
        (if (not arg)
            (setq current-column (+ current-column (length current-macro-name)))
          (terpri))
        (setq mlist (cdr mlist))
        (setq current-macro-name (car mlist)))
      (if (not arg)(terpri))
      (princ " ") ; Funny, RMS is such a stickler for newline at EOF, and
                  ; his nown printstream drops newlines at the end unless you
                  ; follow it by something else.
    (help-print-return-message))))

(defun emacros-refresh-macros ()
  "Erases all macros and then reloads for current buffer.
When called in a buffer, this function produces, as far as
kbd-macros are concerned, the same situation as if Emacs had
just been started and the current file read from the file system."
  (interactive)
  (let* ((mlist (emacros-make-macro-list))
         (next (car mlist)))
    (while next
      (fmakunbound next)
      (setq mlist (cdr mlist))
      (setq next (car mlist))))
  (setq emacros-ok nil)
  (setq last-kbd-macro nil)
  (setq emacros-last-name nil)
  (setq emacros-last-saved nil)
  (emacros-load-macros)
  (message "Macros refreshed for current buffer"))

(defun emacros-insert-kbd-macro
    (symbol kbd-macro overwrite-existing-macro-definition)
  "Insert macro definition in current buffer.
Overwrite existing definition if requested."
  (if overwrite-existing-macro-definition
      (emacros-remove-macro-definition symbol))
  (goto-char (point-max))
  (if (not (bolp)) (insert "\n"))
  (insert "(emacros-new-macro '")
  (prin1 symbol (current-buffer))
  (insert " ")
  (prin1 kbd-macro (current-buffer))
  (insert (if (eobp) ")\n" ")")))

(defun emacros-remove-macro-definition-from-file (symbol buf filename)
  "Remove first definition of macro named SYMBOL from FILENAME."
  (when (or buf (file-exists-p filename))
    (emacros--within buf or filename
      do
      (emacros-remove-macro-definition symbol)
      (save-buffer 0))))

(defun emacros-remove-macro-definition (symbol)
  "Remove definition of macro named SYMBOL from current buffer."
  (goto-char (point-min))
  (if (search-forward
       (format "(emacros-new-macro '%s " symbol)
       (point-max) t)
      (progn
        (end-of-line)
        (let ((eol (point)))
          (beginning-of-line)
          (delete-region (point) eol))
        (if (not (eobp))
                 (delete-char 1)))))

(defun emacros-make-macro-list ()
  "Return a sorted list of all keyboard macro symbols.
Those are the symbols that have a non-void function definition and are macro."
  (let (macro-list)
    (mapatoms (lambda (symbol)
                (if (emacros--macrop symbol)
                    (setq macro-list (cons symbol macro-list)))))
    (sort
     macro-list
     #'(lambda (sym1 sym2)
        (let* ((str1 (prin1-to-string sym1))
              (str2 (prin1-to-string sym2))
              (cmp (compare-strings str1 nil nil
                                    str2 nil nil
                                    t)))
          (and (integerp cmp) (< cmp 0)))))))

(defun emacros-there-are-keyboard-macros ()
  "Return t if there is at least one keyboard macro currently defined."
  (catch 'macro-found
    (mapatoms (lambda (symbol)
                (if (emacros--macrop symbol)
                    (throw 'macro-found t))))
    nil))

;; ---------------------------------------------------------------------------
(provide 'emacros)

;;; emacros.el ends here

; LocalWords:  emacros
