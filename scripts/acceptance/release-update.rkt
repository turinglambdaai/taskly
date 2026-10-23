#lang racket/base

;; Release-kind acceptance runner (#58 slice 1): runs the release-update
;; suite — signed-feed rejection, download cancellation, the N→N+1
;; lifecycle, data preservation, and the platform's install arm — and
;; archives evidence under .rivet/acceptance/ on success, the executable
;; record the acceptance contract requires for `release` suites.

(require json
         racket/file
         racket/path
         racket/system)

(define platform
  (case (system-type 'os)
    [(windows) "windows"]
    [(macosx) "macos"]
    [(unix) "linux"]
    [else (error 'taskly-acceptance "unsupported platform")]))

(define raco
  (or (find-executable-path "raco")
      (error 'taskly-acceptance "raco was not found")))

(unless (system* raco "test" "racket/tests/release-update-test.rkt")
  (error 'taskly-acceptance "release-update suite failed"))

(define evidence-directory
  (build-path (current-directory) ".rivet" "acceptance" platform))
(make-directory* evidence-directory)
(call-with-output-file (build-path evidence-directory "release-update.json")
  #:exists 'truncate/replace
  (lambda (output)
    (write-json
     (hash 'platform platform
           'release-update-verified #t
           'source "raco test racket/tests/release-update-test.rkt")
     output)
    (newline output)))
