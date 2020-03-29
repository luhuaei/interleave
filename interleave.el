;;; interleave.el --- Interleaving text books since 2015 -*- lexical-binding: t -*-

;; Author: Sebastian Christ <rudolfo.christ@gmail.com>
;; URL: https://github.com/rudolfochrist/interleave
;; Version: 1.4.20161123-610
;; fork: luhuaei <luhuaei@gmail.com>

;; This file is not part of GNU Emacs

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; In the past, textbooks were sometimes published as 'interleaved'
;; editions.  That meant, each page was followed by a blank page and
;; ambitious students/scholars had the ability to take their notes
;; directly in their copy of the textbook.  Newton and Kant were
;; prominent representatives of this technique.

;; Nowadays textbooks (or lecture material) come in PDF format.  Although almost
;; every PDF Reader has the ability to add some notes to the PDF itself, it is
;; not as powerful as it could be.

;; This is what this minor mode tries to accomplish.  It presents your PDF side by
;; side to an [[http://orgmode.org][Org Mode]] buffer with your notes, narrowing
;; down to just those passages that are relevant to the particular page in the
;; document viewer.

;;; Usage:

;;; Code:

(require 'org)
(require 'org-element)
(require 'eaf)

(defgroup interleave nil
  "Interleaving text books since 2015."
  :group 'applications)

(defcustom interleave-org-notes-dir-list '("~/org/interleave_notes" ".")
  "List of directories to look into when opening notes org from a pdf file.

The notes file is assumed to have the exact
same base name as the pdf file (just that the file extension is
.org instead of .pdf).

If the notes org file is not found, it is created in the
directory returned on doing `car' of this list (first element of
the list).

The notes file is searched in order from the first list element
till the last; the search is aborted once the file is found.

If a list element is \".\" or begins with \"./\", that portion is
replaced with the pdf directory name.  e.g. \".\" is interpreted
as \"/pdf/file/dir/\", \"./notes\" is interpreted as
\"/pdf/file/dir/notes/\"."
  :type '(repeat directory)
  :group 'interleave)

(defcustom interleave-sort-order 'asc
  "Specifiy the notes' sort order in the notes buffer.

The possible values are 'asc for ascending and 'desc for descending."
  :type '(choice (const  asc)
                 (const  desc))
  :group 'interleave)

(defcustom interleave-split-direction 'vertical
  "Specify how to split the notes buffer."
  :group 'interleave
  :type '(choice (const vertical)
                 (const horizontal)))

(defcustom interleave-split-lines nil
  "Specify the number of lines the PDF buffer should be increased or decreased.

If nil both buffers are split equally.  If the number is positive,
the window is enlarged.  If the number is negative, the window is
shrunken.

If `interleave-split-direction' is 'vertical then the number is
taken as columns."
  :group 'interleave
  :type '(choice integer
                 (const nil)))

(defcustom interleave-insert-relative-name t
  "Whether inserted name should be relative when creating a property."
  :group 'interleave
  :type 'boolean)

;;; Interleave
;; Minor mode for the org file buffer containing notes
(defvar interleave-mode-map (make-sparse-keymap)
  "Keymap while command `interleave-mode' is active in the org file buffer.")

;;;###autoload
(define-minor-mode interleave-mode
  "Interleaving your text books since 2015.

In the past, textbooks were sometimes published as 'interleaved' editions.
That meant, each page was followed by a blank page and the ambitious student/
scholar had the ability to take their notes directly in their copy of the
textbook. Newton and Kant were prominent representatives of this technique.

Nowadays textbooks (or lecture material) come in PDF format. Although almost
every PDF Reader has the ability to add some notes to the PDF itself, it is
not as powerful as it could be.

This is what this minor mode tries to accomplish. It presents your PDF side by
pppside to an [[http://orgmode.org][Org Mode]] buffer with your notes, narrowing
down to just those passages that are relevant to the particular page in the
document viewer.

The split direction is determined by the customizable variable
`interleave-split-direction'. When `interleave-mode' is invoked
with a prefix argument the inverse split direction is used
e.g. if `interleave-split-direction' is 'vertical the buffer is
split horizontally."
  :keymap interleave-mode-map
  (if interleave-mode
      (progn
        (setq interleave-org-buffer (current-buffer))
        (setq interleave--window-configuration (current-window-configuration))
        (interleave--open-file)
        ;; expand/show all headlines if narrowing is disabled
        (when interleave-disable-narrowing
          (with-current-buffer interleave-org-buffer
            (interleave--goto-search-position)
            (if interleave-multi-pdf-notes-file
                (org-show-subtree)
              (show-all))
            (org-cycle-hide-drawers 'all)))
        (interleave--go-to-page-note 1)
        (message "Interleave enabled"))
    ;; Disable the corresponding minor mode in the PDF file too.
    (set-window-configuration interleave--window-configuration)
    (setq interleave--window-configuration nil)
    (setq interleave-org-buffer nil)
    (setq interleave--current-pdf-file nil)
    (with-current-buffer interleave-pdf-buffer
      (interleave-pdf-mode -1)
      (interleave-pdf-kill-buffer))
    (setq interleave-pdf-buffer nil)
    ))

;;; Interleave PDF Mode
;; Minor mode for the pdf file buffer associated with the notes
(defvar interleave-pdf-mode-map (make-sparse-keymap)
  "Keymap while command `interleave-pdf-mode' is active in the pdf file buffer."
  )

;;;###autoload
(define-minor-mode interleave-pdf-mode
  "Interleave view for the pdf."
  :keymap interleave-pdf-mode-map
  (when interleave-pdf-mode
    ;; if derived mode is eaf.
    (unless interleave--current-pdf-file
      (setq interleave--current-pdf-file eaf--buffer-url))
    (setq interleave-pdf-buffer (get-buffer (file-name-nondirectory interleave--current-pdf-file)))))

;; variables
(defvar interleave-org-buffer nil
  "Org notes buffer name.")

(defvar interleave-pdf-buffer nil
  "Name of PDF buffer associated with `interleave-org-buffer'.")

(defvar interleave--window-configuration nil
  "Variable to store the window configuration before interleave mode was enabled.")

(defvar interleave--current-pdf-file nil)

(defvar-local interleave-multi-pdf-notes-file nil
  "Indicates if the current Org notes file is a multi-pdf notes file.")

(defconst interleave--page-note-prop "interleave_page_note"
  "The page note property string.")

(defconst interleave--pdf-prop "interleave_pdf"
  "The pdf property string.")

;; functions
(defun interleave--open-file ()
  "Opens the pdf file in besides the notes buffer.

SPLIT-WINDOW is a function that actually splits the window, so it must be either
`split-window-right' or `split-window-below'."
  (let ((pdf-file-name
          (or (interleave--headline-pdf-path interleave-org-buffer)
              (interleave--find-pdf-path interleave-org-buffer)
              (interleave--handle-parse-pdf-file-name))))
    (setq interleave--current-pdf-file pdf-file-name)
    (interleave--select-split-function)
    (interleave--eaf-open-pdf pdf-file-name)
    pdf-file-name))

(defun interleave--handle-parse-pdf-file-name ()
  "When don't parse responsive pdf file on current org file."
  (let ((pdf-file-name (read-file-name "No INTERLEAVE_PDF property found. Please specify path: " nil nil t)))
    ;; Check whether we have any entry at point with `org-entry-properties' before
    ;; prompting if the user wants multi-pdf.
    (if (and (org-entry-properties) (y-or-n-p "Is this multi-pdf? "))
        (org-entry-put (point) "INTERLEAVE_PDF" pdf-file-name)
      (save-excursion
        (goto-char (point-min))
        (insert "#+INTERLEAVE_PDF: " pdf-file-name)))
    pdf-file-name))

(defun interleave--eaf-open-pdf (pdf-file-name)
  "Use EAF PdfViewer open this pdf-file-name document."
  (eaf-open pdf-file-name)
  (add-hook 'eaf-pdf-viewer-hook 'interleave-pdf-mode))

(defun interleave--headline-pdf-path (buffer)
  "Return the INTERLEAVE_PDF property of the current headline in BUFFER."
  (with-current-buffer buffer
    (save-excursion
      (let ((headline (org-element-at-point)))
        (when (and (equal (org-element-type headline) 'headline)
                   (org-entry-get nil interleave--pdf-prop))
          (setq interleave-multi-pdf-notes-file t)
          (org-entry-get nil interleave--pdf-prop))))))

(defun interleave--find-pdf-path (buffer)
  "Search the `interleave_pdf' property in BUFFER and extracts it when found."
  (with-current-buffer buffer
    (save-restriction
      (widen)
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^#\\+interleave_pdf: \\(.*\\)" nil :noerror)
          (match-string 1))))))

(defun interleave--select-split-function ()
  "Determine which split function to use.

This returns either `split-window-below' or `split-window-right'
based on a combination of `current-prefix-arg' and
`interleave-split-direction'."
  (let ()
    (delete-other-windows)
    (if (string= interleave-split-direction "vertical")
        (split-window-right)
      (split-window-below))
    (when (integerp interleave-split-lines)
      (if (eql interleave-split-direction 'horizontal)
          (enlarge-window interleave-split-lines)
        (enlarge-window-horizontally interleave-split-lines)))
    ))

(defcustom interleave-disable-narrowing nil
  "Disable narrowing in notes/org buffer."
  :group 'interleave
  :type 'boolean)

(defun interleave--goto-search-position ()
  "Move point to the search start position.

For multi-pdf notes this is the outermost parent headline.  For everything else
this is the beginning of the buffer."
  (if interleave-multi-pdf-notes-file
      (interleave--goto-parent-headline interleave--pdf-prop)
    (goto-char (point-min))))

(defun interleave--go-to-page-note (page)
  "Look up the notes for the current pdf PAGE.

Effectively resolves the headline with the interleave_page_note
property set to PAGE and returns the point.

If `interleave-disable-narrowing' is non-nil then the buffer gets
re-centered to the page heading.

It (possibly) narrows the subtree when found."
  (with-current-buffer interleave-org-buffer
    (let (point (window (get-buffer-window (current-buffer) 'visible)))
      (save-excursion
        (widen)
        (interleave--goto-search-position)
        (when interleave-multi-pdf-notes-file
          ;; only search the current subtree for notes. See. Issue #16
          (interleave--narrow-to-subtree t))
        (when (re-search-forward (format "^\[ \t\r\]*\:interleave_page_note\: %d$" page) nil t)
          ;; widen the buffer again for the case it is narrowed from
          ;; multi-pdf notes search. Kinda ugly I know. Maybe a macro helps?
          (widen)
          (org-back-to-heading t)
          (interleave--narrow-to-subtree)
          (org-show-subtree)
          (org-cycle-hide-drawers t)
          (setq point (point))))
      ;; When narrowing is disabled, and the notes/org buffer is
      ;; visible recenter to the current headline. So even if not
      ;; narrowed the notes buffer scrolls allong with the PDF.
      (when (and interleave-disable-narrowing point window)
        (with-selected-window window
          (goto-char point)
          (recenter)))
      point)))

(defun interleave-pdf-kill-buffer ()
  "Kill the current converter process and buffer."
  (interactive)
  (when interleave-pdf-buffer
    (kill-buffer interleave-pdf-buffer)))

(defun interleave--eaf-pdf-viewer-current-page ()
  "get current page index."
  (let ((id (buffer-local-value 'eaf--buffer-id interleave-pdf-buffer)))
    (+ (string-to-number (eaf-call "call_function" id "current_page")) 1)))

(defun interleave--eaf-pdf-viewer-goto-page (page)
  "goto page"
  (let ((id (buffer-local-value 'eaf--buffer-id interleave-pdf-buffer)))
    (eaf-call "handle_input_message" id "jump_page" page)))

(defun interleave-sync-pdf-page-previous ()
  "Move to the previous set of notes.
This show the previous notes and synchronizes the PDF to the right page number."
  (interactive)
  (interleave--switch-to-org-buffer)
  (widen)
  (interleave--goto-parent-headline interleave--page-note-prop)
  (org-backward-heading-same-level 1)
  (interleave--narrow-to-subtree)
  (org-show-subtree)
  (org-cycle-hide-drawers t)
  (interleave-sync-pdf-page-current))

(defun interleave-sync-pdf-page-next ()
  "Move to the next set of notes.
This shows the next notes and synchronizes the PDF to the right page number."
  (interactive)
  (interleave--switch-to-org-buffer)
  (widen)
  ;; go to the first notes heading if we're not at an headline or if
  ;; we're on multi-pdf heading. This is useful to quickly jump to the
  ;; notes if they start at page 96 or so. Image you need to skip page
  ;; for page.
  (if (interleave--goto-parent-headline interleave--page-note-prop)
      (org-forward-heading-same-level 1)
    (when interleave-multi-pdf-notes-file
      (org-show-subtree))
    (outline-next-visible-heading 1))
  (interleave--narrow-to-subtree)
  (org-show-subtree)
  (org-cycle-hide-drawers t)
  (interleave-sync-pdf-page-current))

(defun interleave--goto-parent-headline (property)
  "Traverse the tree until the parent headline.

Consider a headline with property PROPERTY as parent headline."
  (catch 'done
    (if (and (eql (org-element-type (org-element-at-point)) 'headline)
             (org-entry-get (point) property))
        (org-element-at-point)
      (condition-case nil
          (org-up-element)
        ('error
         (throw 'done nil)))
      (interleave--goto-parent-headline property))))

(defun interleave--narrow-to-subtree (&optional force)
  "Narrow buffer to the current subtree.

If `interleave-disable-narrowing' is non-nil this
function does nothing.

When FORCE is non-nil `interleave-disable-narrowing' is
ignored."
  (when (and (not (org-before-first-heading-p))
             (or (not interleave-disable-narrowing)
                 force))
    (org-narrow-to-subtree)))

(defun interleave--switch-to-org-buffer (&optional insert-newline-maybe position)
  "Switch to the notes buffer.

Inserts a newline into the notes buffer if INSERT-NEWLINE-MAYBE
is non-nil.
If POSITION is non-nil move point to it."
  (if (derived-mode-p 'eaf-mode)
      (switch-to-buffer-other-window interleave-org-buffer)
    (switch-to-buffer interleave-org-buffer))
  (when (integerp position)
    (goto-char position))
  (when insert-newline-maybe
    (save-restriction
      (when interleave-disable-narrowing
        (interleave--narrow-to-subtree t))
      (interleave--goto-insert-position))
    ;; Expand again. Sometimes the new content is outside the narrowed
    ;; region.
    (org-show-subtree)
    (redisplay)
    ;; Insert a new line if not already on a new line
    (when (not (looking-back "^ *" (line-beginning-position)))
      (org-return))))

(defun interleave--goto-insert-position ()
  "Move the point to the right insert postion.

For multi-pdf notes this is the end of the subtree.  For everything else
this is the end of the buffer"
  (if (not interleave-multi-pdf-notes-file)
      (goto-char (point-max))
    (prog1
        (interleave--goto-parent-headline interleave--pdf-prop)
      (org-end-of-subtree))))

(defun interleave--insert-heading-respect-content (parent-headline)
  "Create a new heading in the notes buffer.

Adjust the level of the new headline according to the
PARENT-HEADLINE.

Return the position of the newly inserted heading."
  (org-insert-heading-respect-content)
  (let* ((parent-level (if interleave-multi-pdf-notes-file
                           (org-element-property :level parent-headline)
                         0))
         (change-level (if (> (org-element-property :level (org-element-at-point))
                              (1+ parent-level))
                           #'org-promote
                         #'org-demote)))
    (while (/= (org-element-property :level (org-element-at-point))
               (1+ parent-level))
      (funcall change-level)))
  (point))

(defun interleave--create-new-note (page)
  "Create a new headline for the page PAGE."
  (let (new-note-position)
    (with-current-buffer interleave-org-buffer
      (save-excursion
        (widen)
        (let ((position (interleave--goto-insert-position)))
          (setq new-note-position (interleave--insert-heading-respect-content position)))
        (insert (format "Notes for page %d" page))
        (org-set-property interleave--page-note-prop (number-to-string page))
        (interleave--narrow-to-subtree)
        (org-cycle-hide-drawers t)))
    (interleave--switch-to-org-buffer t new-note-position)))

(defun interleave-add-note ()
  "Add note for the current page.

If there are already notes for this page, jump to the notes
buffer."
  (interactive)
  (let* ((page (interleave--eaf-pdf-viewer-current-page))
         (position (interleave--go-to-page-note page)))
    (if position
        (interleave--switch-to-org-buffer t position)
      (interleave--create-new-note page))))

(defun interleave-sync-pdf-page-current ()
  "Open PDF page for currently visible notes."
  (interactive)
  (let ((pdf-page (string-to-number (org-entry-get-with-inheritance interleave--page-note-prop))))
    (when (and (integerp pdf-page) (> pdf-page 0)) ; The page number needs to be a positive integer
      (interleave--narrow-to-subtree)
      (with-current-buffer interleave-pdf-buffer
        (interleave--eaf-pdf-viewer-goto-page pdf-page))
      )))

;;;###autoload
(defun interleave-open-notes-file-for-pdf ()
  "Open the notes org file for the current pdf file if it exists.
Else create it.

It is assumed that the notes org file will have the exact same base name
as the pdf file (just that the notes file will have a .org extension instead
of .pdf)."
  (interactive)
  (when (derived-mode-p 'eaf-mode)
    (let* ((pdf-file-name (eaf-get-path-or-url))
           (org-file-name-sans-directory (concat (file-name-base pdf-file-name) ".org"))
           org-file-create-dir
           (cnt 0)
           try-org-file-name
           (org-file-name (catch 'break
                            (dolist (dir interleave-org-notes-dir-list)
                              ;; If dir is "." or begins with "./", replace
                              ;; the "." or "./" with the pdf dir name
                              (setq dir (replace-regexp-in-string
                                         "^\\(\\.$\\|\\./\\).*"
                                         (file-name-directory pdf-file-name)
                                         dir nil nil 1))
                              (when (= cnt 0)
                                ;; In the event the org file is needed to be
                                ;; created, it will be created in the directory
                                ;; listed as the first element in
                                ;; `interleave-org-notes-dir-list'
                                (setq org-file-create-dir dir))
                              (setq cnt (1+ cnt))
                              (setq try-org-file-name (locate-file
                                                       org-file-name-sans-directory
                                                       (list dir)))
                              (when try-org-file-name
                                ;; return the first match
                                (throw 'break try-org-file-name))))))
      ;; Create the notes org file if it does not exist
      (when (null org-file-name)
        (setq org-file-name (if (null interleave-org-notes-dir-list)
                                (read-file-name "Path: " "~/")
                              (progn
                                (when (null (file-exists-p org-file-create-dir))
                                  (make-directory org-file-create-dir))
                                (expand-file-name org-file-name-sans-directory
                                                  org-file-create-dir))))
        (with-temp-file org-file-name
          (insert "#+INTERLEAVE_PDF: " pdf-file-name)))
      ;; Open the notes org file and enable `interleave-mode'
      (find-file org-file-name)
      (interleave-mode))))

(defun interleave-quit ()
  "Quit interleave mode."
  (interactive)
  (with-current-buffer interleave-org-buffer
    (widen)
    (interleave--goto-search-position)
    (when (interleave--headlines-available-p)
      (interleave--sort-notes interleave-sort-order)
      (org-overview))
    (interleave-mode 0))
  (interleave-pdf-kill-buffer))

(defun interleave--headlines-available-p ()
  "True if there are headings in the notes buffer."
  (save-excursion
    (re-search-forward "^\* .*" nil t)))

(defun interleave--sort-notes (sort-order)
  "Sort notes by interleave_page_property.

SORT-ORDER is either 'asc or 'desc."
  (condition-case nil
      (org-sort-entries nil ?f
                        (lambda ()
                          (let ((page-note (org-entry-get nil "interleave_page_note")))
                            (if page-note
                                (string-to-number page-note)
                              -1)))
                        (if (eq sort-order 'asc)
                            #'<
                          #'>))
    ('user-error nil)))


;;; Key-bindings
(define-key interleave-mode-map (kbd "M-.") #'interleave-sync-pdf-page-current)
(define-key interleave-mode-map (kbd "M-p") #'interleave-sync-pdf-page-previous)
(define-key interleave-mode-map (kbd "M-n") #'interleave-sync-pdf-page-next)
(define-key interleave-pdf-mode-map (kbd "C-c M-o") #'interleave-open-notes-file-for-pdf)
(define-key interleave-pdf-mode-map (kbd "C-c M-q") #'interleave-quit)
(define-key interleave-pdf-mode-map (kbd "C-c M-i") #'interleave-add-note)

(provide 'interleave)

;;; interleave.el ends here
