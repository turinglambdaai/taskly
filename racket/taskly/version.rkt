#lang racket/base

;; Release identity and platform mapping for Taskly, duplicated from
;; rivet.rktd — the packaged app cannot read the project file at runtime.
;; scripts/check-release-version.sh re-checks app-version against VERSION.
;;
;; This is a leaf module on purpose: the CLI's `version` command reports
;; identity without loading the update machinery (crypto / rivet) that
;; updater.rkt pulls in.

(provide app-version
         app-build
         app-identifier
         app-channel
         app-display-name
         platform-symbol
         architecture-symbol)

(define app-version "0.2.0")
(define app-build 1)
(define app-identifier "app.taskly.Taskly")
(define app-channel 'stable)
(define app-display-name "Taskly")

;; rivet release tooling emits these exact symbols into update manifests
(define (platform-symbol)
  (case (system-type 'os)
    [(macosx) 'macos]
    [(windows) 'windows]
    [else 'linux]))

(define (architecture-symbol)
  (case (system-type 'arch)
    [(aarch64 arm64) 'arm64]
    [else 'x64]))
