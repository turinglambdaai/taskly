#lang racket/base

(require racket/date
         racket/format
         racket/match
         racket/string
         "clock.rkt"
         "errors.rkt"
         "validation.rkt")

(provide parse-date-time
         parse-due-expression
         extract-date-only
         extract-time-only)

(define (pad2 n) (~r n #:min-width 2 #:pad-string "0"))
(define (pad4 n) (~r n #:min-width 4 #:pad-string "0"))

(define (format-date d)
  (format "~a-~a-~a" (pad4 (date-year d)) (pad2 (date-month d)) (pad2 (date-day d))))

(define (format-full seconds)
  (define d (seconds->date seconds #t))
  (format "~a ~a:~a:~a"
          (format-date d)
          (pad2 (date-hour d))
          (pad2 (date-minute d))
          (pad2 (date-second d))))

(define (valid-local-date-seconds year month day [hour 12] [minute 0])
  (and (<= min-year year max-year)
       (with-handlers ([exn:fail? (lambda (_) #f)])
         (define seconds (find-seconds 0 minute hour day month year #t))
         (and seconds
              (let ([d (seconds->date seconds #t)])
                (and (= year (date-year d))
                     (= month (date-month d))
                     (= day (date-day d))
                     (= hour (date-hour d))
                     (= minute (date-minute d))))
              seconds))))

(define (parse-absolute input)
  (define candidates
    (list
     (cons #px"^(\\d{4})-(\\d{2})-(\\d{2})$" '(y m d))
     (cons #px"^(\\d{4})/(\\d{2})/(\\d{2})$" '(y m d))
     (cons #px"^(\\d{2})/(\\d{2})/(\\d{4})$" '(m d y))
     (cons #px"^(\\d{2})/(\\d{2})/(\\d{4})$" '(d m y))))
  (for/or ([candidate (in-list candidates)])
    (define match-result (regexp-match (car candidate) input))
    (and match-result
         (let* ([numbers (map string->number (cdr match-result))]
                [labels (cdr candidate)]
                [parts (for/hash ([label (in-list labels)]
                                  [number (in-list numbers)])
                         (values label number))]
                [year (hash-ref parts 'y)]
                [month (hash-ref parts 'm)]
                [day (hash-ref parts 'd)]
                [seconds (valid-local-date-seconds year month day)])
           (and seconds
                (format "~a-~a-~a" (pad4 year) (pad2 month) (pad2 day)))))))

(define (parse-relative input)
  (match (regexp-match #px"^\\+(\\d*)([mhdwM])$" input)
    [(list _ amount-text unit)
     (define amount (if (string=? amount-text "") 1 (string->number amount-text)))
     (define factor
       (case (string-ref unit 0)
         [(#\m) 60]
         [(#\h) 3600]
         [(#\d) 86400]
         [(#\w) (* 7 86400)]
         [(#\M) (* 30 86400)]
         [else #f]))
     (and factor (format-full (+ (now-seconds) (* amount factor))))]
    [_ #f]))

(define weekday-map
  (hash "sun" 0 "mon" 1 "tue" 2 "wed" 3 "thu" 4 "fri" 5 "sat" 6))

(define (parse-at input)
  (cond
    [(string-ci=? input "now") (format-full (now-seconds))]
    [else
     (match (regexp-match
             #px"^(\\d{1,2})(?::(\\d{2}))?(am|pm)?(?:\\s+(tomorrow|tmw|sun|mon|tue|wed|thu|fri|sat))?$"
             input)
       [(list _ hour-text minute-text ampm-text modifier-text)
        (define hour0 (string->number hour-text))
        (define minute (if minute-text (string->number minute-text) 0))
        (define ampm (and ampm-text (string-downcase ampm-text)))
        (define hour
          (cond
            [(and ampm (string=? ampm "am") (= hour0 12)) 0]
            [(and ampm (string=? ampm "pm") (< hour0 12)) (+ hour0 12)]
            [else hour0]))
        (and (<= 0 hour 23)
             (<= 0 minute 59)
             (let* ([today (seconds->date (now-seconds) #t)]
                    [base (valid-local-date-seconds
                           (date-year today) (date-month today) (date-day today)
                           hour minute)])
               (and base
                    (let ([target
                           (cond
                             [(and modifier-text
                                   (member (string-downcase modifier-text) '("tomorrow" "tmw")))
                              (+ base 86400)]
                             [modifier-text
                              (define target-day (hash-ref weekday-map (string-downcase modifier-text) #f))
                              (and target-day
                                   (let* ([current-day (date-week-day (seconds->date base #t))]
                                          [raw-diff (modulo (- target-day current-day) 7)]
                                          [diff (if (zero? raw-diff) 7 raw-diff)])
                                     (+ base (* diff 86400))))]
                             [(< base (now-seconds)) (+ base 86400)]
                             [else base])])
                      (and target (format-full target))))))]
       [_ #f])]))

(define (parse-date-time input)
  (and (string? input)
       (let ([s (string-trim input)])
         (cond
           [(string-prefix? s "+") (parse-relative s)]
           [(string-prefix? s "@") (parse-at (substring s 1))]
           [else (parse-absolute s)]))))

(define (extract-date-only value)
  (and value
       (if (>= (string-length value) 10)
           (substring value 0 10)
           value)))

(define (extract-time-only value)
  (and value
       (>= (string-length value) 16)
       (substring value 11 16)))

(define (pure-date-intent? original normalized parsed)
  (or (member (string-downcase original) '("today" "tomorrow" "tmw"))
      (regexp-match? #px"^\\+\\d*[dwM]$" normalized)
      (= (string-length parsed) 10)))

;; CLI-facing parser. Returns two values: canonical due_date and due_time.
;; A pure-date expression intentionally returns #f for due_time.
(define (parse-due-expression input)
  (define original (string-trim input))
  (define normalized
    (cond
      [(string-ci=? original "today") "+0d"]
      [(or (string-ci=? original "tomorrow") (string-ci=? original "tmw")) "+1d"]
      [(string-ci=? original "tonight") "@20:00"]
      [else original]))
  (define parsed (parse-date-time normalized))
  (unless parsed
    (raise-taskly
     'validation 2
     (format "Cannot parse date/time: \"~a\". Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd"
             original)))
  (values (extract-date-only parsed)
          (if (pure-date-intent? original normalized parsed)
              #f
              (extract-time-only parsed))))
