;;;; 	Copyright (C) 2009, 2010, 2011, 2012 Free Software Foundation, Inc.
;;;;
;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU Lesser General Public
;;;; License as published by the Free Software Foundation; either
;;;; version 3 of the License, or (at your option) any later version.
;;;;
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; Lesser General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU Lesser General Public
;;;; License along with this library; if not, write to the Free Software
;;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
;;;;


(define-module (language tree-il)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-11)
  #:use-module (system base pmatch)
  #:use-module (system base syntax)
  #:export (tree-il-src

            <void> void? make-void void-src
            <const> const? make-const const-src const-exp
            <primitive-ref> primitive-ref? make-primitive-ref primitive-ref-src primitive-ref-name
            <lexical-ref> lexical-ref? make-lexical-ref lexical-ref-src lexical-ref-name lexical-ref-gensym
            <lexical-set> lexical-set? make-lexical-set lexical-set-src lexical-set-name lexical-set-gensym lexical-set-exp
            <module-ref> module-ref? make-module-ref module-ref-src module-ref-mod module-ref-name module-ref-public?
            <module-set> module-set? make-module-set module-set-src module-set-mod module-set-name module-set-public? module-set-exp
            <toplevel-ref> toplevel-ref? make-toplevel-ref toplevel-ref-src toplevel-ref-name
            <toplevel-set> toplevel-set? make-toplevel-set toplevel-set-src toplevel-set-name toplevel-set-exp
            <toplevel-define> toplevel-define? make-toplevel-define toplevel-define-src toplevel-define-name toplevel-define-exp
            <conditional> conditional? make-conditional conditional-src conditional-test conditional-consequent conditional-alternate
            <call> call? make-call call-src call-proc call-args
            <primcall> primcall? make-primcall primcall-src primcall-name primcall-args
            <seq> seq? make-seq seq-src seq-head seq-tail
            <lambda> lambda? make-lambda lambda-src lambda-meta lambda-body
            <lambda-case> lambda-case? make-lambda-case lambda-case-src
                          lambda-case-req lambda-case-opt lambda-case-rest lambda-case-kw
                          lambda-case-inits lambda-case-gensyms
                          lambda-case-body lambda-case-alternate
            <let> let? make-let let-src let-names let-gensyms let-vals let-body
            <letrec> letrec? make-letrec letrec-src letrec-in-order? letrec-names letrec-gensyms letrec-vals letrec-body
            <fix> fix? make-fix fix-src fix-names fix-gensyms fix-vals fix-body
            <let-values> let-values? make-let-values let-values-src let-values-exp let-values-body
            <dynwind> dynwind? make-dynwind dynwind-src dynwind-winder dynwind-pre dynwind-body dynwind-post dynwind-unwinder
            <dynlet> dynlet? make-dynlet dynlet-src dynlet-fluids dynlet-vals dynlet-body
            <dynref> dynref? make-dynref dynref-src dynref-fluid
            <dynset> dynset? make-dynset dynset-src dynset-fluid dynset-exp
            <prompt> prompt? make-prompt prompt-src prompt-tag prompt-body prompt-handler
            <abort> abort? make-abort abort-src abort-tag abort-args abort-tail

            list->seq

            parse-tree-il
            unparse-tree-il
            tree-il->scheme

            tree-il-fold
            make-tree-il-folder
            post-order!
            pre-order!))

(define (print-tree-il exp port)
  (format port "#<tree-il ~S>" (unparse-tree-il exp)))

(define-syntax borrow-core-vtables
  (lambda (x)
    (syntax-case x ()
      ((_)
       (let lp ((n 0) (out '()))
         (if (< n (vector-length %expanded-vtables))
             (lp (1+ n)
                 (let* ((vtable (vector-ref %expanded-vtables n))
                        (stem (struct-ref vtable (+ vtable-offset-user 0)))
                        (fields (struct-ref vtable (+ vtable-offset-user 2)))
                        (sfields (map
                                  (lambda (f) (datum->syntax x f))
                                  fields))
                        (type (datum->syntax x (symbol-append '< stem '>)))
                        (ctor (datum->syntax x (symbol-append 'make- stem)))
                        (pred (datum->syntax x (symbol-append stem '?))))
                   (let lp ((n 0) (fields fields)
                            (out (cons*
                                  #`(define (#,ctor #,@sfields)
                                      (make-struct #,type 0 #,@sfields))
                                  #`(define (#,pred x)
                                      (and (struct? x)
                                           (eq? (struct-vtable x) #,type)))
                                  #`(struct-set! #,type vtable-index-printer
                                                 print-tree-il)
                                  #`(define #,type
                                           (vector-ref %expanded-vtables #,n))
                                       out)))
                     (if (null? fields)
                         out
                         (lp (1+ n)
                             (cdr fields)
                             (let ((acc (datum->syntax
                                         x (symbol-append stem '- (car fields)))))
                               (cons #`(define #,acc
                                         (make-procedure-with-setter
                                          (lambda (x) (struct-ref x #,n))
                                          (lambda (x v) (struct-set! x #,n v))))
                                     out)))))))
             #`(begin #,@(reverse out))))))))

(borrow-core-vtables)

  ;; (<void>)
  ;; (<const> exp)
  ;; (<primitive-ref> name)
  ;; (<lexical-ref> name gensym)
  ;; (<lexical-set> name gensym exp)
  ;; (<module-ref> mod name public?)
  ;; (<module-set> mod name public? exp)
  ;; (<toplevel-ref> name)
  ;; (<toplevel-set> name exp)
  ;; (<toplevel-define> name exp)
  ;; (<conditional> test consequent alternate)
  ;; (<call> proc args)
  ;; (<primcall> name args)
  ;; (<seq> head tail)
  ;; (<lambda> meta body)
  ;; (<lambda-case> req opt rest kw inits gensyms body alternate)
  ;; (<let> names gensyms vals body)
  ;; (<letrec> in-order? names gensyms vals body)
  ;; (<dynlet> fluids vals body)

(define-type (<tree-il> #:common-slots (src) #:printer print-tree-il)
  (<fix> names gensyms vals body)
  (<let-values> exp body)
  (<dynwind> winder pre body post unwinder)
  (<dynref> fluid)
  (<dynset> fluid exp)
  (<prompt> tag body handler)
  (<abort> tag args tail))



;; A helper.
(define (list->seq loc exps)
  (if (null? (cdr exps))
      (car exps)
      (make-seq loc (car exps) (list->seq #f (cdr exps)))))



(define (location x)
  (and (pair? x)
       (let ((props (source-properties x)))
	 (and (pair? props) props))))

(define (parse-tree-il exp)
  (let ((loc (location exp))
        (retrans (lambda (x) (parse-tree-il x))))
    (pmatch exp
     ((void)
      (make-void loc))

     ((call ,proc . ,args)
      (make-call loc (retrans proc) (map retrans args)))

     ((primcall ,name . ,args)
      (make-primcall loc name (map retrans args)))

     ((if ,test ,consequent ,alternate)
      (make-conditional loc (retrans test) (retrans consequent) (retrans alternate)))

     ((primitive ,name) (guard (symbol? name))
      (make-primitive-ref loc name))

     ((lexical ,name) (guard (symbol? name))
      (make-lexical-ref loc name name))

     ((lexical ,name ,sym) (guard (symbol? name) (symbol? sym))
      (make-lexical-ref loc name sym))

     ((set! (lexical ,name) ,exp) (guard (symbol? name))
      (make-lexical-set loc name name (retrans exp)))

     ((set! (lexical ,name ,sym) ,exp) (guard (symbol? name) (symbol? sym))
      (make-lexical-set loc name sym (retrans exp)))

     ((@ ,mod ,name) (guard (and-map symbol? mod) (symbol? name))
      (make-module-ref loc mod name #t))

     ((set! (@ ,mod ,name) ,exp) (guard (and-map symbol? mod) (symbol? name))
      (make-module-set loc mod name #t (retrans exp)))

     ((@@ ,mod ,name) (guard (and-map symbol? mod) (symbol? name))
      (make-module-ref loc mod name #f))

     ((set! (@@ ,mod ,name) ,exp) (guard (and-map symbol? mod) (symbol? name))
      (make-module-set loc mod name #f (retrans exp)))

     ((toplevel ,name) (guard (symbol? name))
      (make-toplevel-ref loc name))

     ((set! (toplevel ,name) ,exp) (guard (symbol? name))
      (make-toplevel-set loc name (retrans exp)))

     ((define ,name ,exp) (guard (symbol? name))
      (make-toplevel-define loc name (retrans exp)))

     ((lambda ,meta ,body)
      (make-lambda loc meta (retrans body)))

     ((lambda-case ((,req ,opt ,rest ,kw ,inits ,gensyms) ,body) ,alternate)
      (make-lambda-case loc req opt rest kw
                        (map retrans inits) gensyms
                        (retrans body)
                        (and=> alternate retrans)))

     ((lambda-case ((,req ,opt ,rest ,kw ,inits ,gensyms) ,body))
      (make-lambda-case loc req opt rest kw
                        (map retrans inits) gensyms
                        (retrans body)
                        #f))

     ((const ,exp)
      (make-const loc exp))

     ((seq ,head ,tail)
      (make-seq loc (retrans head) (retrans tail)))

     ;; Convenience.
     ((begin . ,exps)
      (list->seq loc (map retrans exps)))

     ((let ,names ,gensyms ,vals ,body)
      (make-let loc names gensyms (map retrans vals) (retrans body)))

     ((letrec ,names ,gensyms ,vals ,body)
      (make-letrec loc #f names gensyms (map retrans vals) (retrans body)))

     ((letrec* ,names ,gensyms ,vals ,body)
      (make-letrec loc #t names gensyms (map retrans vals) (retrans body)))

     ((fix ,names ,gensyms ,vals ,body)
      (make-fix loc names gensyms (map retrans vals) (retrans body)))

     ((let-values ,exp ,body)
      (make-let-values loc (retrans exp) (retrans body)))

     ((dynwind ,winder ,pre ,body ,post ,unwinder)
      (make-dynwind loc (retrans winder) (retrans pre)
                    (retrans body)
                    (retrans post) (retrans unwinder)))

     ((dynlet ,fluids ,vals ,body)
      (make-dynlet loc (map retrans fluids) (map retrans vals) (retrans body)))

     ((dynref ,fluid)
      (make-dynref loc (retrans fluid)))

     ((dynset ,fluid ,exp)
      (make-dynset loc (retrans fluid) (retrans exp)))

     ((prompt ,tag ,body ,handler)
      (make-prompt loc (retrans tag) (retrans body) (retrans handler)))

     ((abort ,tag ,args ,tail)
      (make-abort loc (retrans tag) (map retrans args) (retrans tail)))

     (else
      (error "unrecognized tree-il" exp)))))

(define (unparse-tree-il tree-il)
  (record-case tree-il
    ((<void>)
     '(void))

    ((<call> proc args)
     `(call ,(unparse-tree-il proc) ,@(map unparse-tree-il args)))

    ((<primcall> name args)
     `(primcall ,name ,@(map unparse-tree-il args)))

    ((<conditional> test consequent alternate)
     `(if ,(unparse-tree-il test) ,(unparse-tree-il consequent) ,(unparse-tree-il alternate)))

    ((<primitive-ref> name)
     `(primitive ,name))

    ((<lexical-ref> name gensym)
     `(lexical ,name ,gensym))

    ((<lexical-set> name gensym exp)
     `(set! (lexical ,name ,gensym) ,(unparse-tree-il exp)))

    ((<module-ref> mod name public?)
     `(,(if public? '@ '@@) ,mod ,name))

    ((<module-set> mod name public? exp)
     `(set! (,(if public? '@ '@@) ,mod ,name) ,(unparse-tree-il exp)))

    ((<toplevel-ref> name)
     `(toplevel ,name))

    ((<toplevel-set> name exp)
     `(set! (toplevel ,name) ,(unparse-tree-il exp)))

    ((<toplevel-define> name exp)
     `(define ,name ,(unparse-tree-il exp)))

    ((<lambda> meta body)
     `(lambda ,meta ,(unparse-tree-il body)))

    ((<lambda-case> req opt rest kw inits gensyms body alternate)
     `(lambda-case ((,req ,opt ,rest ,kw ,(map unparse-tree-il inits) ,gensyms)
                    ,(unparse-tree-il body))
                   . ,(if alternate (list (unparse-tree-il alternate)) '())))

    ((<const> exp)
     `(const ,exp))

    ((<seq> head tail)
     `(seq ,(unparse-tree-il head) ,(unparse-tree-il tail)))
    
    ((<let> names gensyms vals body)
     `(let ,names ,gensyms ,(map unparse-tree-il vals) ,(unparse-tree-il body)))

    ((<letrec> in-order? names gensyms vals body)
     `(,(if in-order? 'letrec* 'letrec) ,names ,gensyms
       ,(map unparse-tree-il vals) ,(unparse-tree-il body)))

    ((<fix> names gensyms vals body)
     `(fix ,names ,gensyms ,(map unparse-tree-il vals) ,(unparse-tree-il body)))

    ((<let-values> exp body)
     `(let-values ,(unparse-tree-il exp) ,(unparse-tree-il body)))

    ((<dynwind> winder pre body post unwinder)
     `(dynwind ,(unparse-tree-il winder) ,(unparse-tree-il pre)
               ,(unparse-tree-il body)
               ,(unparse-tree-il post) ,(unparse-tree-il unwinder)))

    ((<dynlet> fluids vals body)
     `(dynlet ,(map unparse-tree-il fluids) ,(map unparse-tree-il vals)
              ,(unparse-tree-il body)))

    ((<dynref> fluid)
     `(dynref ,(unparse-tree-il fluid)))

    ((<dynset> fluid exp)
     `(dynset ,(unparse-tree-il fluid) ,(unparse-tree-il exp)))

    ((<prompt> tag body handler)
     `(prompt ,(unparse-tree-il tag) ,(unparse-tree-il body) ,(unparse-tree-il handler)))

    ((<abort> tag args tail)
     `(abort ,(unparse-tree-il tag) ,(map unparse-tree-il args)
             ,(unparse-tree-il tail)))))

(define* (tree-il->scheme e #:optional (env #f) (opts '()))
  (values ((@ (language scheme decompile-tree-il)
              decompile-tree-il)
           e env opts)))


(define (tree-il-fold leaf down up seed tree)
  "Traverse TREE, calling LEAF on each leaf encountered, DOWN upon descent
into a sub-tree, and UP when leaving a sub-tree.  Each of these procedures is
invoked as `(PROC TREE SEED)', where TREE is the sub-tree or leaf considered
and SEED is the current result, intially seeded with SEED.

This is an implementation of `foldts' as described by Andy Wingo in
``Calls of fold to XML transformation''."
  (let loop ((tree   tree)
             (result seed))
    (if (or (null? tree) (pair? tree))
        (fold loop result tree)
        (record-case tree
          ((<lexical-set> exp)
           (up tree (loop exp (down tree result))))
          ((<module-set> exp)
           (up tree (loop exp (down tree result))))
          ((<toplevel-set> exp)
           (up tree (loop exp (down tree result))))
          ((<toplevel-define> exp)
           (up tree (loop exp (down tree result))))
          ((<conditional> test consequent alternate)
           (up tree (loop alternate
                          (loop consequent
                                (loop test (down tree result))))))
          ((<call> proc args)
           (up tree (loop (cons proc args) (down tree result))))
          ((<primcall> name args)
           (up tree (loop args (down tree result))))
          ((<seq> head tail)
           (up tree (loop tail (loop head (down tree result)))))
          ((<lambda> body)
           (up tree (loop body (down tree result))))
          ((<lambda-case> inits body alternate)
           (up tree (if alternate
                        (loop alternate
                              (loop body (loop inits (down tree result))))
                        (loop body (loop inits (down tree result))))))
          ((<let> vals body)
           (up tree (loop body
                          (loop vals
                                (down tree result)))))
          ((<letrec> vals body)
           (up tree (loop body
                          (loop vals
                                (down tree result)))))
          ((<fix> vals body)
           (up tree (loop body
                          (loop vals
                                (down tree result)))))
          ((<let-values> exp body)
           (up tree (loop body (loop exp (down tree result)))))
          ((<dynwind> winder pre body post unwinder)
           (up tree (loop unwinder
                      (loop post
                        (loop body
                          (loop pre
                            (loop winder
                              (down tree result))))))))
          ((<dynlet> fluids vals body)
           (up tree (loop body
                          (loop vals
                                (loop fluids (down tree result))))))
          ((<dynref> fluid)
           (up tree (loop fluid (down tree result))))
          ((<dynset> fluid exp)
           (up tree (loop exp (loop fluid (down tree result)))))
          ((<prompt> tag body handler)
           (up tree
               (loop tag (loop body (loop handler
                                          (down tree result))))))
          ((<abort> tag args tail)
           (up tree (loop tail (loop args (loop tag (down tree result))))))
          (else
           (leaf tree result))))))


(define-syntax-rule (make-tree-il-folder seed ...)
  (lambda (tree down up seed ...)
    (define (fold-values proc exps seed ...)
      (if (null? exps)
          (values seed ...)
          (let-values (((seed ...) (proc (car exps) seed ...)))
            (fold-values proc (cdr exps) seed ...))))
    (let foldts ((tree tree) (seed seed) ...)
      (let*-values
          (((seed ...) (down tree seed ...))
           ((seed ...)
            (record-case tree
              ((<lexical-set> exp)
               (foldts exp seed ...))
              ((<module-set> exp)
               (foldts exp seed ...))
              ((<toplevel-set> exp)
               (foldts exp seed ...))
              ((<toplevel-define> exp)
               (foldts exp seed ...))
              ((<conditional> test consequent alternate)
               (let*-values (((seed ...) (foldts test seed ...))
                             ((seed ...) (foldts consequent seed ...)))
                 (foldts alternate seed ...)))
              ((<call> proc args)
               (let-values (((seed ...) (foldts proc seed ...)))
                 (fold-values foldts args seed ...)))
              ((<primcall> name args)
               (fold-values foldts args seed ...))
              ((<seq> head tail)
               (let-values (((seed ...) (foldts head seed ...)))
                 (foldts tail seed ...)))
              ((<lambda> body)
               (foldts body seed ...))
              ((<lambda-case> inits body alternate)
               (let-values (((seed ...) (fold-values foldts inits seed ...)))
                 (if alternate
                     (let-values (((seed ...) (foldts body seed ...)))
                       (foldts alternate seed ...))
                     (foldts body seed ...))))
              ((<let> vals body)
               (let*-values (((seed ...) (fold-values foldts vals seed ...)))
                 (foldts body seed ...)))
              ((<letrec> vals body)
               (let*-values (((seed ...) (fold-values foldts vals seed ...)))
                 (foldts body seed ...)))
              ((<fix> vals body)
               (let*-values (((seed ...) (fold-values foldts vals seed ...)))
                 (foldts body seed ...)))
              ((<let-values> exp body)
               (let*-values (((seed ...) (foldts exp seed ...)))
                 (foldts body seed ...)))
              ((<dynwind> winder pre body post unwinder)
               (let*-values (((seed ...) (foldts winder seed ...))
                             ((seed ...) (foldts pre seed ...))
                             ((seed ...) (foldts body seed ...))
                             ((seed ...) (foldts post seed ...)))
                 (foldts unwinder seed ...)))
              ((<dynlet> fluids vals body)
               (let*-values (((seed ...) (fold-values foldts fluids seed ...))
                             ((seed ...) (fold-values foldts vals seed ...)))
                 (foldts body seed ...)))
              ((<dynref> fluid)
               (foldts fluid seed ...))
              ((<dynset> fluid exp)
               (let*-values (((seed ...) (foldts fluid seed ...)))
                 (foldts exp seed ...)))
              ((<prompt> tag body handler)
               (let*-values (((seed ...) (foldts tag seed ...))
                             ((seed ...) (foldts body seed ...)))
                 (foldts handler seed ...)))
              ((<abort> tag args tail)
               (let*-values (((seed ...) (foldts tag seed ...))
                             ((seed ...) (fold-values foldts args seed ...)))
                 (foldts tail seed ...)))
              (else
               (values seed ...)))))
        (up tree seed ...)))))

(define (post-order! f x)
  (let lp ((x x))
    (record-case x
      ((<call> proc args)
       (set! (call-proc x) (lp proc))
       (set! (call-args x) (map lp args)))

      ((<primcall> name args)
       (set! (primcall-args x) (map lp args)))

      ((<conditional> test consequent alternate)
       (set! (conditional-test x) (lp test))
       (set! (conditional-consequent x) (lp consequent))
       (set! (conditional-alternate x) (lp alternate)))

      ((<lexical-set> name gensym exp)
       (set! (lexical-set-exp x) (lp exp)))

      ((<module-set> mod name public? exp)
       (set! (module-set-exp x) (lp exp)))

      ((<toplevel-set> name exp)
       (set! (toplevel-set-exp x) (lp exp)))

      ((<toplevel-define> name exp)
       (set! (toplevel-define-exp x) (lp exp)))

      ((<lambda> body)
       (set! (lambda-body x) (lp body)))

      ((<lambda-case> inits body alternate)
       (set! inits (map lp inits))
       (set! (lambda-case-body x) (lp body))
       (if alternate
           (set! (lambda-case-alternate x) (lp alternate))))

      ((<seq> head tail)
       (set! (seq-head x) (lp head))
       (set! (seq-tail x) (lp tail)))
      
      ((<let> gensyms vals body)
       (set! (let-vals x) (map lp vals))
       (set! (let-body x) (lp body)))

      ((<letrec> gensyms vals body)
       (set! (letrec-vals x) (map lp vals))
       (set! (letrec-body x) (lp body)))

      ((<fix> gensyms vals body)
       (set! (fix-vals x) (map lp vals))
       (set! (fix-body x) (lp body)))

      ((<let-values> exp body)
       (set! (let-values-exp x) (lp exp))
       (set! (let-values-body x) (lp body)))

      ((<dynwind> winder pre body post unwinder)
       (set! (dynwind-winder x) (lp winder))
       (set! (dynwind-pre x) (lp pre))
       (set! (dynwind-body x) (lp body))
       (set! (dynwind-post x) (lp post))
       (set! (dynwind-unwinder x) (lp unwinder)))

      ((<dynlet> fluids vals body)
       (set! (dynlet-fluids x) (map lp fluids))
       (set! (dynlet-vals x) (map lp vals))
       (set! (dynlet-body x) (lp body)))

      ((<dynref> fluid)
       (set! (dynref-fluid x) (lp fluid)))

      ((<dynset> fluid exp)
       (set! (dynset-fluid x) (lp fluid))
       (set! (dynset-exp x) (lp exp)))

      ((<prompt> tag body handler)
       (set! (prompt-tag x) (lp tag))
       (set! (prompt-body x) (lp body))
       (set! (prompt-handler x) (lp handler)))

      ((<abort> tag args tail)
       (set! (abort-tag x) (lp tag))
       (set! (abort-args x) (map lp args))
       (set! (abort-tail x) (lp tail)))

      (else #f))

    (or (f x) x)))

(define (pre-order! f x)
  (let lp ((x x))
    (let ((x (or (f x) x)))
      (record-case x
        ((<call> proc args)
         (set! (call-proc x) (lp proc))
         (set! (call-args x) (map lp args)))

        ((<primcall> name args)
         (set! (primcall-args x) (map lp args)))

        ((<conditional> test consequent alternate)
         (set! (conditional-test x) (lp test))
         (set! (conditional-consequent x) (lp consequent))
         (set! (conditional-alternate x) (lp alternate)))

        ((<lexical-set> exp)
         (set! (lexical-set-exp x) (lp exp)))

        ((<module-set> exp)
         (set! (module-set-exp x) (lp exp)))

        ((<toplevel-set> exp)
         (set! (toplevel-set-exp x) (lp exp)))

        ((<toplevel-define> exp)
         (set! (toplevel-define-exp x) (lp exp)))

        ((<lambda> body)
         (set! (lambda-body x) (lp body)))

        ((<lambda-case> inits body alternate)
         (set! inits (map lp inits))
         (set! (lambda-case-body x) (lp body))
         (if alternate (set! (lambda-case-alternate x) (lp alternate))))

        ((<seq> head tail)
         (set! (seq-head x) (lp head))
         (set! (seq-tail x) (lp tail)))
        
        ((<let> vals body)
         (set! (let-vals x) (map lp vals))
         (set! (let-body x) (lp body)))

        ((<letrec> vals body)
         (set! (letrec-vals x) (map lp vals))
         (set! (letrec-body x) (lp body)))

        ((<fix> vals body)
         (set! (fix-vals x) (map lp vals))
         (set! (fix-body x) (lp body)))

        ((<let-values> exp body)
         (set! (let-values-exp x) (lp exp))
         (set! (let-values-body x) (lp body)))

        ((<dynwind> winder pre body post unwinder)
         (set! (dynwind-winder x) (lp winder))
         (set! (dynwind-pre x) (lp pre))
         (set! (dynwind-body x) (lp body))
         (set! (dynwind-post x) (lp post))
         (set! (dynwind-unwinder x) (lp unwinder)))

        ((<dynlet> fluids vals body)
         (set! (dynlet-fluids x) (map lp fluids))
         (set! (dynlet-vals x) (map lp vals))
         (set! (dynlet-body x) (lp body)))

        ((<dynref> fluid)
         (set! (dynref-fluid x) (lp fluid)))

        ((<dynset> fluid exp)
         (set! (dynset-fluid x) (lp fluid))
         (set! (dynset-exp x) (lp exp)))

        ((<prompt> tag body handler)
         (set! (prompt-tag x) (lp tag))
         (set! (prompt-body x) (lp body))
         (set! (prompt-handler x) (lp handler)))

        ((<abort> tag args tail)
         (set! (abort-tag x) (lp tag))
         (set! (abort-args x) (map lp args))
         (set! (abort-tail x) (lp tail)))

        (else #f))
      x)))
