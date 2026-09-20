#lang racket/base

(require racket/date
         racket/format)

(provide current-clock
         now-seconds
         local-date
         local-date-string
         local-time-string
         local-timestamp)

;; Tests and adapters can replace the clock without contaminating domain logic.
(define current-clock (make-parameter current-seconds))

(define (now-seconds)
  ((current-clock)))

(define (local-date [seconds (now-seconds)])
  (seconds->date seconds #t))

(define (pad2 n) (~r n #:min-width 2 #:pad-string "0"))
(define (pad4 n) (~r n #:min-width 4 #:pad-string "0"))

(define (local-date-string [seconds (now-seconds)])
  (define d (local-date seconds))
  (format "~a-~a-~a" (pad4 (date-year d)) (pad2 (date-month d)) (pad2 (date-day d))))

(define (local-time-string [seconds (now-seconds)])
  (define d (local-date seconds))
  (format "~a:~a" (pad2 (date-hour d)) (pad2 (date-minute d))))

(define (local-timestamp [seconds (now-seconds)])
  (define d (local-date seconds))
  (define offset (date-time-zone-offset d))
  (define sign (if (negative? offset) "-" "+"))
  (define abs-offset (abs offset))
  (define offset-hours (quotient abs-offset 3600))
  (define offset-minutes (quotient (remainder abs-offset 3600) 60))
  (format "~aT~a:~a:~a~a~a:~a"
          (local-date-string seconds)
          (pad2 (date-hour d))
          (pad2 (date-minute d))
          (pad2 (date-second d))
          sign
          (pad2 offset-hours)
          (pad2 offset-minutes)))
