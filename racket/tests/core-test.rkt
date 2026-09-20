#lang racket/base

(require db
         rackunit
         racket/date
         racket/file
         racket/path
         "../taskly/clock.rkt"
         "../taskly/config.rkt"
         "../taskly/date-parser.rkt"
         "../taskly/db.rkt"
         "../taskly/errors.rkt"
         "../taskly/model.rkt"
         "../taskly/paths.rkt"
         "../taskly/service.rkt"
         "../taskly/validation.rkt")

(define fixed-now (find-seconds 0 15 10 20 9 2026 #t))
(define temp-root (make-temporary-file "taskly-racket-test-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-clock (lambda () fixed-now)]
                  [current-taskly-home temp-root])
     ;; Validation is shared behavior, not a UI concern.
     (check-equal? (validate-task-text! "  hello  ") "hello")
     (check-exn exn:fail:taskly? (lambda () (validate-task-text! "   ")))
     (check-exn exn:fail:taskly? (lambda () (validate-list-name! "")))

     ;; Date grammar parity with CLI-SPEC.md.
     (check-equal? (parse-date-time "2026-09-20") "2026-09-20")
     (check-false (parse-date-time "2026-02-30"))
     (check-equal? (parse-date-time "+2h") "2026-09-20 12:15:00")
     (check-equal? (parse-date-time "@10:30") "2026-09-20 10:30:00")
     (check-equal? (parse-date-time "@09:00") "2026-09-21 09:00:00")
     (define-values (today-date today-time) (parse-due-expression "today"))
     (check-equal? today-date "2026-09-20")
     (check-false today-time)
     (define-values (tonight-date tonight-time) (parse-due-expression "tonight"))
     (check-equal? tonight-date "2026-09-20")
     (check-equal? tonight-time "20:00")

     ;; Config and path resolution are now one implementation for all hosts.
     (define config (make-hash))
     (hash-set! config "language" "en")
     (hash-set! config "last-selected-list-id" "7")
     (hash-set! config "last-db-path" (path->string (build-path temp-root "custom.db")))
     (write-config! config)
     (define loaded-config (read-config))
     (check-equal? (config-language loaded-config) "en")
     (check-equal? (config-last-selected-list-id loaded-config) 7)
     (check-equal? (resolve-database-path #f loaded-config)
                   (path->complete-path (build-path temp-root "custom.db")))

     ;; SQLite v4 and the product editing slice.
     (define db-path (build-path temp-root "slice.db"))
     (define service (open-taskly-service db-path))
     (define db (taskly-service-db service))
     (check-equal? (query-value (taskly-db-connection db) "PRAGMA user_version") 4)
     (define initial-lists (service-lists service))
     (check-equal? (length initial-lists) 1)
     (define default-list (car initial-lists))
     (check-equal? (todo-list-name default-list) default-list-name)
     (check-equal? (todo-list-color default-list) default-list-color)

     (define created (service-add-task! service "  first task  " #:due-date "2026-09-20"))
     (check-equal? (task-item-text created) "first task")
     (check-equal? (service-counts service) '(1 1 1 0))
     (check-equal? (length (service-tasks service #:view 'today)) 1)

     (define edited (service-update-task-text! service (task-item-id created) "renamed"))
     (check-equal? (task-item-text edited) "renamed")
     (define completed (service-set-completed! service (task-item-id created) #t))
     (check-true (task-item-completed completed))
     (check-equal? (service-counts service) '(0 0 0 1))
     (check-equal? (length (service-tasks service #:view 'today #:show-completed #t)) 1)

     (define personal (service-add-list! service "Personal" #:icon "🏠"))
     (define renamed-list
       (service-update-list!
        service
        (struct-copy todo-list personal [name "Home"] [icon #f] [color #f])))
     (check-equal? (todo-list-name renamed-list) "Home")
     (check-false (todo-list-icon renamed-list))
     (check-false (todo-list-color renamed-list))

     (define second (service-add-task! service "home" #:list-id (todo-list-id renamed-list)))
     (define moved
       (service-update-task!
        service
        (struct-copy task-item second
                     [list-id (todo-list-id default-list)]
                     [text "moved home"]
                     [due-date "2026-09-21"]
                     [due-time "09:30"]
                     [completed #t]
                     [notes "note"])))
     (check-equal? (task-item-list-id moved) (todo-list-id default-list))
     (check-equal? (task-item-text moved) "moved home")
     (check-equal? (task-item-due-date moved) "2026-09-21")
     (check-equal? (task-item-due-time moved) "09:30")
     (check-equal? (task-item-notes moved) "note")
     (check-true (task-item-completed moved))
     (check-equal? (task-item-created-at moved) (task-item-created-at second))

     ;; Deleting a list still cascades tasks that remain in it.
     (define doomed (service-add-task! service "delete me" #:list-id (todo-list-id renamed-list)))
     (check-true (service-delete-list! service (todo-list-id renamed-list)))
     (check-false (service-task service (task-item-id doomed)))
     (check-not-false (service-task service (task-item-id moved)))

     (close-taskly-service service)))
 (lambda ()
   (delete-directory/files temp-root)))
