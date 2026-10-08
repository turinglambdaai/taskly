#lang racket/base

(require racket/path)

(provide current-taskly-home
         taskly-home
         taskly-directory
         default-database-path
         config-file-path)

;; #f means use the real process environment. Tests may parameterize this to a
;; temporary directory without mutating HOME/USERPROFILE.
(define current-taskly-home (make-parameter #f))

(define (taskly-home)
  (or (current-taskly-home)
      (let* ([windows? (eq? (system-type 'os) 'windows)]
             [preferred (and windows? (getenv "USERPROFILE"))]
             [fallback (getenv "HOME")])
        (cond
          [(and preferred (not (string=? preferred ""))) (string->path preferred)]
          [(and fallback (not (string=? fallback ""))) (string->path fallback)]
          [else (find-system-path 'home-dir)]))))

(define (taskly-directory)
  (build-path (taskly-home) ".taskly"))

(define (default-database-path)
  (build-path (taskly-directory) "tasks.db"))

(define (config-file-path)
  (build-path (taskly-directory) "config.ini"))
