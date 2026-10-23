#lang racket/base

;; Backend RPC contract for host preferences (set_setting/get_setting),
;; including the update-check throttle key (shared/spec/UPDATE.md).

(require rackunit
         racket/file
         racket/path
         (submod "../taskly/backend.rkt" rpcs)
         "../taskly/config.rkt"
         "../taskly/paths.rkt"
         "../taskly/service.rkt")

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
     (check-equal? (get_setting "last-selected-list-id") "7")

     ;; UPDATE.md auto-check toggle: round-trips as a string enum, rejects
     ;; anything but "0"/"1", and survives the config writer's key list.
     (set_setting "auto-check-updates" "0")
     (check-equal? (get_setting "auto-check-updates") "0")
     (check-equal? (config-ref (read-config) "auto-check-updates") "0")
     (set_setting "auto-check-updates" "1")
     (check-exn exn:fail? (lambda () (set_setting "auto-check-updates" "off")))

     ;; open_database remembers the opened file (DATA-FORMAT §7) so hosts
     ;; restart against it — the 0.2.1 OTA regression: manually opened DBs
     ;; were forgotten because nothing ever wrote last-db-path.
     (define remembered-db (build-path temp-root "remembered.db"))
     (close-taskly-service (open-taskly-service remembered-db))
     (open_database (path->string remembered-db))
     (check-equal? (config-ref (read-config) "last-db-path")
                   (path->string (path->complete-path remembered-db)))
     (check-equal? (resolve-database-path)
                   (path->complete-path remembered-db))

     ;; A legacy underscore key survives a config rewrite (pre-0.x files),
     ;; and the new key wins over it when both exist.
     (define legacy-config (build-path temp-root "legacy-config.ini"))
     (call-with-output-file legacy-config
       (lambda (out)
         (displayln "# Taskly configuration" out)
         (displayln "language = zh" out)
         (displayln "last_db_path = /sync/old.db" out)))
     (define legacy-loaded (read-config legacy-config))
     (check-equal? (resolve-database-path #f legacy-loaded)
                   (path->complete-path "/sync/old.db"))
     (write-config! legacy-loaded legacy-config)
     (check-equal? (config-ref (read-config legacy-config) "last_db_path")
                   "/sync/old.db")))
 (lambda ()
   ;; open_database installs a process-wide service just like the embedded
   ;; host. Close it before removing the disposable profile so Windows does
   ;; not retain an open SQLite handle during test cleanup.
   (close_database)
   (delete-directory/files temp-root)))
