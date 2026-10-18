#lang racket/base

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

(unless (system* raco "rivet" "package" "--skip-launch-smoke")
  (error 'taskly-acceptance "raco rivet package failed"))

(define evidence-directory
  (build-path (current-directory) ".rivet" "acceptance" platform))
(make-directory* evidence-directory)
(call-with-output-file (build-path evidence-directory "package.json")
  #:exists 'truncate/replace
  (lambda (output)
    (write-json
     (hash 'platform platform
           'package-verified #t
           'source "raco rivet package --skip-launch-smoke")
     output)
    (newline output)))
