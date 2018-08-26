;;; polymode-classes.el --- Core polymode classes -*- lexical-binding: t -*-
;;
;; Copyright (C) 2013-2018, Vitalie Spinu
;; Author: Vitalie Spinu
;; URL: https://github.com/vspinu/polymode
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; This file is *NOT* part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;;; Commentary:
;;
;;; Code:

(require 'eieio)
(require 'eieio-base)
(require 'eieio-custom)

;; FIXME: fix emacs eieo-named bug #22840 where they wrongly set name of the
;; parent object in clone method

(setq eieio-backward-compatibility nil)

(defvar pm--object-counter 0)

(defun pm--filter-slots (slots)
  (delq nil (mapcar (lambda (slot)
                      (unless (or (= (elt (symbol-name slot) 0) ?-)
                                  (eq slot 'minor-mode)
                                  (eq slot 'parent-instance)
                                  (eq slot 'object-name))
                        (intern (concat ":" (symbol-name slot)))))
                    slots)))

(defclass pm-root (eieio-instance-inheritor)
  ((object-name
    :initarg :object-name
    :initform "UNNAMED"
    :type string
    :custom string
    :documentation
    "Name of the object used to for display and info.")
   (-id
    :initform 0
    :type number
    :documentation
    "[Internal] Numeric id to track objects. Every object has an id.")
   (-props
    :initform '()
    :type list
    :documentation
    "[Internal] Plist used to store various extra metadata such as user history.
Use `pm--prop-get' and `pm--prop-put' to place key value pairs
into this list."))
  "Root polymode class.")

(cl-defmethod eieio-object-name-string ((obj pm-root))
  (eieio-oref obj 'object-name))

(defclass pm-polymode (pm-root)
  ((hostmode
    :initarg :hostmode
    :initform nil
    :type symbol
    :custom symbol
    :documentation
    "Symbol pointing to a `pm-host-chunkmode' object.
When nil, any host-mode will be matched (suitable for
poly-minor-modes. ")
   (innermodes
    :initarg :innermodes
    :type list
    :initform nil
    :custom (repeat symbol)
    :documentation
    "List of inner-mode names (symbols) associated with this polymode.")
   (exporters
    :initarg :exporters
    :initform '(pm-exporter/pandoc)
    :custom (repeat symbol)
    :documentation
    "List of names of polymode exporters available for this polymode.")
   (exporter
    :initarg :exporter
    :initform nil
    :type symbol
    :custom symbol
    :documentation
    "Current exporter name.
If non-nil should be the name of the default exporter for this
polymode. Can be set with `polymode-set-exporter' command.")
   (weavers
    :initarg :weavers
    :initform '()
    :type list
    :custom (repeat symbol)
    :documentation
    "List of names of polymode weavers available for this polymode.")
   (weaver
    :initarg :weaver
    :initform nil
    :type symbol
    :custom symbol
    :documentation
    "Current weaver name.
If non-nil this is the default weaver for this polymode. Can be
dynamically set with `polymode-set-weaver'")
   (switch-buffer-functions
    :initarg :switch-buffer-functions
    :initform '()
    :type list
    :custom (repeat symbol)
    :documentation
    "List of functions to run at polymode buffer switch.
Each function is run with two arguments, OLD-BUFFER and
NEW-BUFFER.")
   (keylist
    :initarg :keylist
    :initform 'polymode-minor-mode-map
    :type (or symbol list)
    :custom (choice (symbol :tag "Keymap")
                    (repeat (cons string symbol)))
    :documentation
    "A list of elements of the form (KEY . BINDING).
This slot is reserved for building hierarchies through cloning
and should not be used in `define-polymode'.")

   ;; fixme: prefix with -
   (minor-mode
    :initarg :minor-mode
    :initform 'polymode-minor-mode
    :type symbol
    :documentation
    "[Internal] Symbol pointing to minor-mode function.")
   (-hostmode
    :type (or null pm-chunkmode)
    :documentation
    "[Dynamic] Dynamically populated `pm-chunkmode' object.")
   (-innermodes
    :type list
    :initform '()
    :documentation
    "[Dynamic] List of chunkmodes objects.")
   (-auto-innermodes
    :type list
    :initform '()
    :documentation
    "[Dynamic] List of auto chunkmodes.")
   (-buffers
    :initform '()
    :type list
    :documentation
    "[Dynamic] Holds all buffers associated with current buffer."))

  "Polymode Configuration object.
Each polymode buffer holds a local variable `pm/polymode'
instantiated from this class or a subclass of this class.")

(defvar pm--polymode-slots
  (mapcar #'cl--slot-descriptor-name
          (eieio-class-slots 'pm-polymode)))

(defclass pm-chunkmode (pm-root)
  ((mode
    :initarg :mode
    :initform nil
    :type symbol
    :custom symbol
    :documentation
    "Emacs major mode in the chunk's body.")
   (indent-offset
    :initarg :indent-offset
    :initform 0
    :type integer
    :custom integer
    :documentation
    "Offset to add when indenting chunk's line.
Takes effect only when :protect-indent is non-nil.")
   (protect-indent
    :initarg :protect-indent
    :initform t
    :type boolean
    :custom boolean
    :documentation
    "Whether to narrowing to current span before indent.")
   (protect-font-lock
    :initarg :protect-font-lock
    :initform t
    :type boolean
    :custom boolean
    :documentation
    "Whether to narrow to span during font lock.")
   (protect-syntax
    :initarg :protect-syntax
    :initform t
    :type boolean
    :custom boolean
    :documentation
    "Whether to narrow to span when calling `syntax-propertize-function'.")
   (adjust-face
    :initarg :adjust-face
    :initform '()
    :type (or number face list)
    :custom (choice number face sexp)
    :documentation
    "Fontification adjustment for the body of the chunk.
It should be either, nil, number, face or a list of text
properties as in `put-text-property' specification. If nil no
highlighting occurs. If a face, use that face. If a number, it is
a percentage by which to lighten/darken the default chunk
background. If positive - lighten the background on dark themes
and darken on light thems. If negative - darken in dark thems and
lighten in light thems.")
   (init-functions
    :initarg :init-functions
    :initform '()
    :type list
    :custom hook
    :documentation
    "List of functions called after the initialization.
Functions are called in the buffer associated with this
chunkmode. All init-functions in the inheritance chain are called
in parent-first order. Either customize this slot or use
`object-add-to-list' function.")
   (switch-buffer-functions
    :initarg :switch-buffer-functions
    :initform '()
    :type list
    :custom hook
    :documentation
    "List of functions to run at polymode buffer switch.
Each function is run with two arguments, OLD-BUFFER and
NEW-BUFFER. In contrast to identically named slot in
`pm-polymode' class, these functions are run only when NEW-BUFFER
is of this chunkmode.")

   (-buffer
    :type (or null buffer)
    :initform nil))
  "Generic chunkmode object.")

(defclass pm-host-chunkmode (pm-chunkmode)
  ()
  "This chunkmode doesn't know how to compute spans and takes
over all the other space not claimed by other chunkmodes in the
buffer.")

(defclass pm-inner-chunkmode (pm-chunkmode)
  ((can-nest
    :initarg :can-nest
    :initform nil
    :type boolean
    :custom boolean
    :documentation
    "Non-nil if this chunk can nest within other inner modes.
All chunks can nest within the host-mode.")
   (can-overlap
    :initarg :can-overlap
    :initform nil
    :type boolean
    :custom boolean
    :documentation
    "Non-nil if chunks of this type can overlap with other chunks of the same type.
See noweb for an example.")
   (head-mode
    :initarg :head-mode
    :initform 'poly-head-tail-mode
    :type symbol
    :custom symbol
    :documentation
    "Chunk's head mode.
If set to 'body, the head is considered part of the chunk body.
If set to 'host, head is considered part of the surrounding host
mode.")
   (tail-mode
    :initarg :tail-mode
    :initform nil
    :type symbol
    :custom (choice (const nil :tag "From Head")
                    function)
    :documentation
    "Chunk's tail mode.
If 'body or 'host the tail's mode is the same as chunk's body or
host mode. If nil, pick the mode from :HEAD-MODE slot.")
   (head-matcher
    :initarg :head-matcher
    :initform nil
    :type (or string symbol cons)
    :custom (choice string (cons string integer) function)
    :documentation
    "A regexp, a cons (REGEXP . SUB-MATCH) or a function.
When a function, the matcher must accept one argument that can
take either values 1 (forwards search) or -1 (backward search).
This function must return either nil (no match) or a (cons BEG
END) representing the span of the head or tail respectively. See
the code of `pm-fun-matcher' for a simple example.")
   (tail-matcher
    :initarg :tail-matcher
    :initform nil
    :type (or string cons symbol)
    :custom (choice string (cons string integer) function)
    :documentation
    "A regexp, a cons (REGEXP . SUB-MATCH) or a function.
Like :head-matcher but for the chunk's tail. It is always called
with the point at the end of the matched head and with the
positive argument.")
   (adjust-face
    :initform 2)
   (head-adjust-face
    :initarg :head-adjust-face
    :initform 'bold
    :type (or number face list)
    :custom (choice number face sexp)
    :documentation
    "Head's face adjustment.
Can be a number, a list of properties or a face.")
   (tail-adjust-face
    :initarg :tail-adjust-face
    :initform nil
    :type (or null number face list)
    :custom (choice (const :tag "From Head" nil)
                    number face sexp)
    :documentation
    "Tail's face adjustment.
A number, a list of properties, a face or nil. When nil, take the
configuration from :head-adjust-face.")

   (-head-buffer
    :type (or null buffer)
    :initform nil
    :documentation
    "[Internal] This buffer is set automatically to -buffer if
:head-mode is 'body, and to base-buffer if :head-mode is 'host.")
   (-tail-buffer
    :initform nil
    :type (or null buffer)
    :documentation
    "[Internal] Same as -head-buffer, but for tail span."))

  "Inner-chunkmodes represent innermodes (or sub-modes) within a
buffer. Chunks are commonly delimited by head and tail markup but
can be delimited by some other logic (e.g. indentation). In the
latter case, heads or tails have zero length and are not
physically present in the buffer.")

(defclass pm-inner-auto-chunkmode (pm-inner-chunkmode)
  ((mode-matcher
    :initarg :mode-matcher
    :type (or string cons symbol)
    :initform nil
    :custom (choice )
    :documentation
    "Matcher used to retrieve the mode's symbol from the chunk's head.
Can be either a regexp string, cons of the form (REGEXP .
SUBEXPR) or a function to be called with no arguments. If a
function, it must return a string name of the mode. Function is
called at the beginning of the head span."))

  "Inner chunkmodes with unknown (at definition time) mode of the
body span. The body mode is determined dynamically by retrieving
the name with the :mode-matcher.")

(setq eieio-backward-compatibility t)

(provide 'polymode-classes)
;;; polymode-classes.el ends here
