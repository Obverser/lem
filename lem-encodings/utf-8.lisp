(uiop/package:define-package :lem-encodings/utf-8 (:use :cl :lem-base))
(in-package :lem-encodings/utf-8)
;;;don't edit above

(defclass utf-8 (encoding) ())
(register-encoding 'utf-8)

(defmethod encoding-read ((external-format utf-8) input output-char)
  (declare (ignore external-format))
  (labels ((commit (c)
             (funcall output-char c))
           (ecommit (c)
             (cond ((<= #x00 c #x7f) (commit c))
                   ((<= #x80 c #xff) (commit (+ #xe000 c)))))
           (cr ()
             (commit #.(+ #xe000 (char-code #\cr))))
           (lf ()
             (commit #.(+ #xe000 (char-code #\lf)))))
    (loop
      :with state := 0
      :with count := 0
      :with read := 0
      :with buffer-size := 8192
      :with buffer := (make-array (list buffer-size) :element-type '(unsigned-byte 8))
      :for end := (read-sequence buffer input)
      :until (zerop end)
      :do (loop :for i :from 0 :below end
                :for c := (aref buffer i)
                :do (if (= 0 count)
                        #1=(multiple-value-setq (count state) ;; take first byte
                             (cond ((<= #x00 c #x7f) (commit c) (values 0 0))
                                   ((<= #x80 c #xbf) (ecommit c) (values 0 0))
                                   ((<= #xc0 c #xdf) (values 1 (logand #x1f c)))
                                   ((<= #xe0 c #xef) (values 2 (logand #x0f c)))
                                   ((<= #xf0 c #xf7) (values 3 (logand #x07 c)))
                                   ((<= #xf8 c #xfd) (ecommit c)) ;; error exceed 21bit
                                   ((<= #xfe c #xff) (values 0 0)))) ;; ignore bom
                        (cond ((or (<= #x00 c #x7f)  ;;error input
                                   (<= #xc0 c #xff))
                               #2=(loop :with result ;;revert partial read.
                                        :for i :from 1 :to read
                                        :do (push (+ #x80 (logand #x3f state)) result)
                                            (setf state (ash state -6))
                                        :finally (ecommit (+ (logand (ash #x3f (- count))
                                                                     state)
                                                             (logxor #xff (ash #x7f (- count)))))
                                                 (mapc (lambda (c) (ecommit c)) result))
                               (setf state 0 count 0 read 0)
                               #1#)
                              ((<= #x80 c #xbf)
                               (setf state (+ (ash state 6) (logand c #x7f))
                                     read (1+ read))
                               (when (= read count)
                                 (if (case count ;; range check
                                       (1 (< state #x80))
                                       (2 (< state #x800))
                                       (3 (< state #x10000)))
                                     (progn (incf read) #2#)
                                     (commit state))
                                 (setf state 0 count 0 read 0))))))
          (when (< end buffer-size)
            (return)))
    (commit nil))) ;; signal eof

(defmethod encoding-write ((external-format utf-8) out)
  (declare(ignore external-format))
  (lambda (c)
    (when c
      (let ((p (char-code c)))
        (cond ((<=    #x00 p   #x7f) (write-byte p out))
              ((<=  #xe000 p #xe0ff) (write-byte (- p #xe000) out))
              ((<=    #x80 p  #x7ff) 
               (write-byte (+ #xc0 (ash p -6)) out)
               (write-byte (+ #x80 (logand p #x3f)) out))
              ((<=   #x800 p #xffff)
               (write-byte (+ #xe0 (ash p -12)) out)
               (write-byte (+ #x80 (logand (ash p -6) #x3f)) out)
               (write-byte (+ #x80 (logand p #x3f)) out))
              ((<= #x10000 p #x1fffff)
               (write-byte (+ #xf0 (ash p -18)) out)
               (write-byte (+ #x80 (logand (ash p -12) #x3f)) out)
               (write-byte (+ #x80 (logand (ash p -6) #x3f)) out)
               (write-byte (+ #x80 (logand p #x3f)) out)))))))
