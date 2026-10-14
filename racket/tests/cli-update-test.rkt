#lang racket/base

;; CLI identity + online-check coverage (CLI-SPEC §version / §check-update).
;; `version` is golden-tested for its bytes; here we pin the contract that
;; the golden suite cannot: version parity with the update feed identity,
;; and `check-update`'s network failure path (HTTPS-only fetch rejects an
;; http:// base URL before any I/O → exit 1 + stderr error JSON, never a
;; crash or a hang).

(require json
         rackunit
         racket/match
         racket/string
         "../taskly/cli.rkt"
         "../taskly/updater.rkt"
         "../taskly/version.rkt")

(define (run-cli/strings args)
  (define out (open-output-string))
  (define err (open-output-string))
  (define code
    (parameterize ([current-output-port out]
                   [current-error-port err])
      (run-cli args)))
  (list code (get-output-string out) (get-output-string err)))

(test-case "version reports the feed identity"
  (match-define (list code out err) (run-cli/strings '("version")))
  (check-equal? code 0)
  (check-equal? err "")
  (check-equal? out (format "~a ~a\n" app-display-name app-version)))

(test-case "version --json parses and matches version.rkt"
  (match-define (list code out err) (run-cli/strings '("version" "--json")))
  (check-equal? code 0)
  (check-equal? err "")
  (define doc (string->jsexpr out))
  (check-equal? (hash-ref doc 'version) app-version)
  (check-equal? (hash-ref doc 'channel) (symbol->string app-channel))
  (check-equal? (hash-ref doc 'platform)
                (symbol->string (platform-symbol)))
  (check-equal? (hash-ref doc 'architecture)
                (symbol->string (architecture-symbol))))

;; The HTTPS-only manifest fetch rejects a plain-http URL before any I/O,
;; so this is deterministic on every platform and in CI.
(test-case "check-update error path exits 1 with the error JSON"
  (match-define (list code out err)
    (parameterize ([current-update-base-url "http://127.0.0.1:1/taskly"])
      (run-cli/strings '("check-update"))))
  (check-equal? out "")
  (check-equal? code 1)
  (define doc (string->jsexpr err))
  (check-equal? (hash-ref doc 'ok) #f)
  (check-equal? (hash-ref doc 'exitCode) 1)
  (check-false (string=? (hash-ref doc 'error) "")))
