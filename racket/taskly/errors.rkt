#lang racket/base

(provide (struct-out exn:fail:taskly)
         raise-taskly
         taskly-error?)

;; kind is one of 'validation, 'not-found, 'database, 'generic.
;; exit-code mirrors CLI-SPEC.md so CLI/native adapters do not re-invent error
;; classification on each platform.
(struct exn:fail:taskly exn:fail (kind exit-code) #:transparent)

(define (raise-taskly kind exit-code message)
  (raise (exn:fail:taskly message (current-continuation-marks) kind exit-code)))

(define taskly-error? exn:fail:taskly?)
