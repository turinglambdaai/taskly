#lang racket/base

(require racket/file
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

(define evidence-directory
  (build-path (current-directory) ".rivet" "acceptance" platform))
(make-directory* evidence-directory)

;; A package suite must exercise an installer, not merely prove that a staging
;; directory can be built. Development release mode creates the same human
;; installation shapes as a release without requiring production credentials.
(unless (system* raco "rivet" "release" "--development" "--without-updates")
  (error 'taskly-acceptance "raco rivet release --development failed"))

(define-values (launcher script)
  (case (system-type 'os)
    [(windows)
     (values (or (find-executable-path "pwsh")
                 (error 'taskly-acceptance "pwsh was not found"))
             (build-path (current-directory)
                         "scripts" "acceptance" "install-windows.ps1"))]
    [(macosx)
     (values (or (find-executable-path "bash")
                 (error 'taskly-acceptance "bash was not found"))
             (build-path (current-directory)
                         "scripts" "acceptance" "install-macos.sh"))]
    [(unix)
     (values (or (find-executable-path "bash")
                 (error 'taskly-acceptance "bash was not found"))
             (build-path (current-directory)
                         "scripts" "acceptance" "install-linux.sh"))]))

(define install-ok?
  (if (eq? (system-type 'os) 'windows)
      (system* launcher "-NoProfile" "-File" script
               "-Repo" (current-directory)
               "-Output" evidence-directory)
      (system* launcher script (current-directory) evidence-directory)))
(unless install-ok?
  (error 'taskly-acceptance "native installer preparation failed"))

(unless (file-exists? (build-path evidence-directory "package.json"))
  (error 'taskly-acceptance "installer did not produce package evidence"))
