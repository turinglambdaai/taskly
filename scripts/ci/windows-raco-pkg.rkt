#lang racket/base

;; Windows CI only: Racket 9.3 sometimes fails inside its OS root-store
;; importer with "X509*->C: argument is not non-null X509*".
;; Use the same machine's trusted public root certificates exported as PEM.
;; Never disable peer/hostname verification or trust an unchecked download.
(require openssl)

(define bundle (getenv "TASKLY_WINDOWS_TRUSTED_ROOTS"))
(unless (and bundle (file-exists? bundle))
  (error 'windows-raco-pkg
         "missing Windows trusted roots PEM; refusing TLS without verification"))

(ssl-default-verify-sources (list bundle))
;; Execute the exact raco pkg CLI submodule in the SAME Racket process so
;; the TLS trust-source override remains active for catalog dependencies too.
(dynamic-require '(submod pkg/main main) #f)
