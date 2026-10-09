#lang racket/base

;; Backend RPC contract for host preferences (set_setting/get_setting),
;; including the update-check throttle key (shared/spec/UPDATE.md).

(require rackunit
         racket/file
         (submod "../taskly/backend.rkt" rpcs)
         "../taskly/config.rkt"
         "../taskly/paths.rkt")

(define temp-root (make-temporary-file "taskly-backend-test-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-taskly-home temp-root])
     ;; get_setting reads raw config; unset keys read as the empty string.
     (check-equal? (get_setting "last-update-check") "")

     ;; set_setting accepts the integer-as-string throttle key and persists
     ;; it through the shared config writer (DATA-FORMAT §7).
     (set_setting "last-update-check" "1728460800")
     (check-equal? (get_setting "last-update-check") "1728460800")
     (check-equal? (config-ref (read-config) "last-update-check") "1728460800")

     ;; Keys are case-insensitive end to end (read + write).
     (set_setting "LAST-Update-Check" "1728461000")
     (check-equal? (get_setting "last-update-check") "1728461000")

     ;; Validation: the throttle must be an integer string; unknown keys are
     ;; rejected as before.
     (check-exn exn:fail? (lambda () (set_setting "last-update-check" "yesterday")))
     (check-exn exn:fail? (lambda () (set_setting "no-such-key" "1")))

     ;; The whitelist regression: last-selected-list-id still works.
     (set_setting "last-selected-list-id" "7")
     (check-equal? (get_setting "last-selected-list-id") "7")))
 (lambda ()
   (delete-directory/files temp-root)))
