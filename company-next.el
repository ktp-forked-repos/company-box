;;; company-next.el --- Company front-end  -*- lexical-binding: t -*-

;; Copyright (C) 2017 Sebastien Chapuis

;; Author: Sebastien Chapuis <sebastien@chapu.is>
;; URL: https://github.com/sebastiencs/company-next
;; Keywords: company, font-end

;;; License
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; A company front-end

;;; Code:

(defcustom company-next-align-annotations company-tooltip-align-annotations
  "When non-nil, align annotations to the right border."
  :type 'boolean
  :group 'company-next)

(defvar company-next-frame-parameters
  '((left . -1)
    (no-accept-focus . t)
    (no-focus-on-map . t)
    (min-width  . 0)
    (width  . 0)
    (min-height  . 0)
    (height  . 0)
    (internal-border-width . 1)
    (vertical-scroll-bars . nil)
    (horizontal-scroll-bars . nil)
    (left-fringe . 0)
    (right-fringe . 0)
    (menu-bar-lines . 0)
    (tool-bar-lines . 0)
    (line-spacing . 0)
    (unsplittable . t)
    (undecorated . t)
    (top . -1)
    (visibility . nil)
    (mouse-wheel-frame . nil)
    (no-other-frame . t)
    (cursor-type . nil)
    (inhibit-double-buffering . t)
    (drag-internal-border . t)
    (no-special-glyphs . t))
  "Frame parameters used to create the frame.")

(defvar-local company-next--buffer nil)
(defvar-local company-next~point nil)
(defvar-local company-next~ov nil)

(defmacro company-next~get-frame ()
  "Return the child frame."
  `(frame-parameter nil 'company-next-frame))

(defmacro company-next~set-frame (frame)
  "Set the frame parameter ‘company-next-frame’ to FRAME."
  `(set-frame-parameter nil 'company-next-frame ,frame))

(defun company-next~make-buffer-name nil
  "Construct the buffer name, it should be unique for each frame."
  (concat " *company-next-"
          (or (frame-parameter nil 'window-id)
              (frame-parameter nil 'name))
          "*"))

(defun company-next~with-icons-p nil
  (and (or (bound-and-true-p lsp--cur-workspace)
           t)
       (> (- (current-column) (string-width company-prefix)) 3)))

(defun company-next~make-frame ()
  "Create the child frame and return it."
  (let* ((after-make-frame-functions nil)
         (before-make-frame-hook nil)
         (buffer (get-buffer (company-next~make-buffer-name)))
         (params (append company-next-frame-parameters
                         `((default-minibuffer-frame . ,(selected-frame))
                           (minibuffer . ,(minibuffer-window))
                           (background-color . ,(face-background 'lsp-ui-doc-background nil t)))))
         (window (display-buffer-in-child-frame buffer `((child-frame-parameters . ,params))))
         (frame (window-frame window)))
    (set-frame-parameter nil 'company-next-buffer buffer)
    (set-frame-parameter nil 'company-next-window window)
    (set-window-dedicated-p window t)
    (redirect-frame-focus frame (frame-parent frame))
    frame))

(defun company-next~get-ov nil
  (or company-next~ov
      (setq company-next~ov (make-overlay 1 1))))

(defun company-next~render-buffer (string)
  (let ((selection company-selection)
        (with-icons-p company-next~with-icons))
    (with-current-buffer (get-buffer-create (company-next~make-buffer-name))
      (erase-buffer)
      (insert string "\n")
      (setq mode-line-format nil)
      (setq-local scroll-step 1)
      (setq-local scroll-conservatively 10000)
      (setq-local scroll-margin  0)
      (setq-local scroll-preserve-screen-position t)
      (goto-char 1)
      (forward-line selection)
      (move-overlay (company-next~get-ov)
                    (line-beginning-position)
                    (line-beginning-position 2))
      (overlay-put (company-next~get-ov)
                   'face 'company-tooltip-selection))))

(defun company-next~line-height (&optional line)
  "Return the pos-y of the LINE on screen, in pixel."
  (nth 2 (or (window-line-height line)
             (and (redisplay t)
                  (window-line-height line)))))

(defun company-next~move-frame (frame)
  (-let* (((left top right _bottom) (window-edges nil t nil t))
          (window (frame-root-window frame))
          ((width . height) (window-text-pixel-size window nil nil 10000 10000))
          (frame-resize-pixelwise t))
    (-let* ((point (- (point) (length company-prefix)))
            (mode-line-y (company-next~line-height 'mode-line))
            ((p-x . p-y) (nth 2 (posn-at-point point)))
            (char-height (frame-char-height))
            (char-width (frame-char-width))
            (y (or (and (> p-y (/ mode-line-y 2))
                        (<= (- mode-line-y p-y) (+ char-height height))
                        (> (- p-y height) 0)
                        (- p-y height))
                   (+ p-y char-height)))
            (height (or (and (> y p-y)
                             (> height (- mode-line-y y))
                             (- mode-line-y y))
                        height))
            (x (if company-next~with-icons
                   (- p-x (+ (* char-width 3) (/ char-width 2)))
                 (- p-x char-width))))
      (set-frame-size frame (company-next~update-width t (/ height char-height))
                      height t)
      (set-frame-position frame (+ (max x 0) left) (+ y top)))))

(defun company-next~display (string)
  "Display the documentation."
  (company-next~render-buffer string)
  (unless (company-next~get-frame)
    (company-next~set-frame (company-next~make-frame)))
  (company-next~move-frame (company-next~get-frame))
  (unless (frame-visible-p (company-next~get-frame))
    (make-frame-visible (company-next~get-frame))))

(defvar-local company-next~max 0)
(defvar-local company-next~with-icons nil)

(defvar random 0)

(defun company-next~add-icon (candidate)
  (concat
   (icons-in-terminal (if (= (mod random 2) 0) 'fa_tag 'fa_cog))
   (propertize " " 'display '(space :align-to (+ left-fringe 3.5)))))

(defun company-next~make-line (candidate)
  (-let* (((candidate annotation len-c len-a) candidate)
          (line (concat
                 " "
                 (when company-next~with-icons
                   (company-next~add-icon candidate))
                 candidate
                 (when annotation
                   (if company-next-align-annotations
                       (propertize " " 'display `(space :align-to (- right-fringe ,(or len-a 0) 1)))
                     " "))
                 (when annotation
                   (propertize annotation 'face 'company-tooltip-annotation)))))
    (add-text-properties 0 (length line) (list 'company-next~len (+ len-c len-a)) line)
    (setq random (1+ random))
    line
    ))

(defun company-next~make-candidate (candidate)
  (let* ((annotation (-some->> (company-call-backend 'annotation candidate)
                               (replace-regexp-in-string "[ \t\n\r]+" " ")
                               (company--clean-string)))
         (len-candidate (string-width candidate))
         (len-annotation (if annotation (string-width annotation) 0))
         (len-total (+ len-candidate len-annotation)))
    (when (> len-total company-next~max)
      (setq company-next~max len-total))
    (list candidate
          annotation
          len-candidate
          len-annotation)))

(defun company-next-show nil
  (setq company-next~max 0)
  (setq company-next~with-icons (company-next~with-icons-p))
  (--> (mapcar 'company-next~make-candidate company-candidates)
       (mapcar 'company-next~make-line it)
       (mapconcat 'identity it "\n")
       (company-next~display it)))

(defun company-next-hide nil
  (make-frame-invisible (company-next~get-frame)))

(defun company-next~calc-len (buffer start end char-width)
  (let ((max 0))
    (with-current-buffer buffer
      (save-excursion
        (goto-char start)
        (while (< (point) end)
          (let ((len (or (get-text-property (point) 'company-next~len) 0)))
            (when (> len max)
              (setq max len)))
          (forward-line))))
    (* (+ max (if company-next~with-icons 6 2))
       char-width)))

(defun company-next~update-width (&optional no-update height)
  (unless no-update
    (redisplay))
  (-let* ((frame (company-next~get-frame))
          (window (frame-parameter nil 'company-next-window))
          (start (window-start window))
          (char-width (frame-char-width frame))
          (end (or (and height (with-current-buffer (window-buffer window)
                                 (save-excursion
                                   (goto-char start)
                                   (forward-line height)
                                   (point))))
                   (window-end window)))
          (width (if company-next-align-annotations
                     ;; With align-annotations, `window-text-pixel-size' doesn't return
                     ;; good values because of the display properties in the buffer
                     ;; More specifically, because of the spaces specifications
                     (company-next~calc-len (window-buffer window) start end char-width)
                   (car (window-text-pixel-size window start end 10000 10000))))
          (width (+ width char-width)))
    (or (and no-update width)
        (set-frame-width (company-next~get-frame) width nil t))))

(defun company-next~change-line nil
  (let ((selection company-selection))
    (with-selected-window (get-buffer-window (company-next~make-buffer-name) t)
      (goto-char 1)
      (forward-line selection)
      (move-overlay (company-next~get-ov)
                    (line-beginning-position)
                    (line-beginning-position 2)))))

(defun company-next~next-line nil
  (interactive)
  (when (< (1+ company-selection) company-candidates-length)
    (setq company-selection (1+ company-selection))
    (company-next~change-line)
    (company-next~update-width)))

(defun company-next~prev-line nil
  (interactive)
  (setq company-selection (max (1- company-selection) 0))
  (company-next~change-line)
  (company-next~update-width))

(defun company-next-frontend (command)
  "`company-mode' frontend using child-frame.
COMMAND: See `company-frontends'."
  ;; (message "\nCOMMMAND: %s" command)
  ;; (message "prefix: %s" company-prefix)
  ;; (message "candidates: %s" company-candidates)
  ;; (message "common: %s" company-common)
  ;; (message "selection: %s" company-selection)
  ;; (message "point: %s" company-point)
  ;; (message "search-string: %s" company-search-string)
  ;;(message "last-command: %s" last-command)
  (pcase command
    ('hide (company-next-hide))
    ('update (company-next-show))
    ))

(defvar company-next-mode-map nil
  "Keymap when `company-next' is active")

(unless company-next-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap company-select-next-or-abort] 'company-next~next-line)
    (define-key map [remap company-select-previous-or-abort] 'company-next~prev-line)
    (setq company-next-mode-map map)))

;;;###autoload
(define-minor-mode company-next-mode
  "Company-next minor mode."
  :group 'company-next
  :lighter " company-next"
  (cond
   (company-next-mode
    (setq-local company-frontends
                (delete 'company-pseudo-tooltip-unless-just-one-frontend company-frontends))
    (add-to-list 'company-frontends 'company-next-frontend))
   (t
    (setq-local company-frontends (delete 'company-next-frontend  company-frontends))
    (add-to-list 'company-frontends 'company-pseudo-tooltip-unless-just-one-frontend))))

(provide 'company-next)
;; company-next ends here
