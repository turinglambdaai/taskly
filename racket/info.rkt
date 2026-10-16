#lang info

(define collection 'multi)
;; Direct requires only: backend.rkt rides on rivet/backend, updater.rkt on
;; rivet/distribution + crypto + net/base64 + net/url, db.rkt on db-lib.
;; Naming follows rivet's own info.rkt (runtime "-lib" packages).
(define deps '("base"
               "crypto-lib"
               "db-lib"
               "net-lib"
               "rivet"))
(define build-deps '("rackunit-lib"))
(define pkg-desc "Taskly shared Racket application core")
(define version "0.2.1")
(define pkg-authors '("turinglambdaai"))
