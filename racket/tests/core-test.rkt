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
         "../taskly/reminder.rkt"
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
     ;; Day/week/month-shaped relative expressions use civil-calendar
     ;; arithmetic so the local wall clock does not drift across DST.
     (check-equal? (parse-date-time "+1d") "2026-09-21 10:15:00")
     (check-equal? (parse-date-time "+1w") "2026-09-27 10:15:00")
     (check-equal? (parse-date-time "+1M") "2026-10-20 10:15:00")
     (check-equal? (parse-date-time "@10:30") "2026-09-20 10:30:00")
     (check-equal? (parse-date-time "@09:00") "2026-09-21 09:00:00")
     (check-equal? (parse-date-time "@10:30 tomorrow") "2026-09-21 10:30:00")
     (check-equal? (parse-date-time "@10:30 mon") "2026-09-21 10:30:00")
     (define-values (today-date today-time) (parse-due-expression "today"))
     (check-equal? today-date "2026-09-20")
     (check-false today-time)
     (define-values (tonight-date tonight-time) (parse-due-expression "tonight"))
     (check-equal? tonight-date "2026-09-20")
     (check-equal? tonight-time "20:00")

     ;; Quick-add extraction: one grammar behind parse_quick_add for all hosts.
     (define-values (qa-text qa-command) (extract-quick-add-command "买牛奶 @10am"))
     (check-equal? qa-text "买牛奶")
     (check-equal? qa-command "@10am")
     (define-values (qa-2-text qa-2-command) (extract-quick-add-command "买菜 +1d"))
     (check-equal? qa-2-text "买菜")
     (check-equal? qa-2-command "+1d")
     (define-values (qa-3-text qa-3-command) (extract-quick-add-command "no command"))
     (check-equal? qa-3-text "no command")
     (check-false qa-3-command)

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

     (close-taskly-service service)

     ;; Reminder eligibility, startup summarization and session de-duplication
     ;; belong to the shared service. Native hosts only acknowledge their OS
     ;; handoff; the clock/calendar is explicit here for midnight/DST-safe
     ;; deterministic fixtures.
     (define reminder-path (build-path temp-root "reminders.db"))
     (define reminder-service (open-taskly-service reminder-path))
     (for ([i (in-range 4)])
       (service-add-task! reminder-service (format "overdue ~a" i)
                          #:due-date "2026-09-19" #:due-time "23:59"))
     (service-add-task! reminder-service "future"
                        #:due-date "2026-09-21" #:due-time "00:00")
     (define done-due
       (service-add-task! reminder-service "already done"
                          #:due-date "2026-09-19"))
     (service-set-completed! reminder-service (task-item-id done-due) #t)
     (define startup-decisions
       (service-reminder-decisions!
        reminder-service #t #:now-date "2026-09-20" #:now-time "00:00"))
     (check-equal? (length startup-decisions) 1)
     (define summary (car startup-decisions))
     (check-equal? (reminder-decision-kind summary) "summary")
     (check-equal? (reminder-decision-count summary) 4)
     (check-false (reminder-decision-task summary))
     (check-equal? (service-reminder-decision-phase
                    reminder-service (reminder-decision-token summary))
                   "emitted")
     (check-true (service-acknowledge-reminder!
                  reminder-service (reminder-decision-token summary)
                  "attempted"))
     (check-true (service-acknowledge-reminder!
                  reminder-service (reminder-decision-token summary)
                  "delivered"))
     ;; Repeated wakeups cannot duplicate a decision, even after delivery.
     (check-equal?
      (service-reminder-decisions!
       reminder-service #f #:now-date "2026-09-20" #:now-time "00:01")
      '())

     ;; A task becoming due later is emitted once. A failed native handoff is
     ;; terminal for this session and does not create a retry duplicate.
     (define later
       (service-add-task! reminder-service "later"
                          #:due-date "2026-09-20" #:due-time "00:02"))
     (check-equal?
      (service-reminder-decisions!
       reminder-service #f #:now-date "2026-09-20" #:now-time "00:01")
      '())
     (define later-decisions
       (service-reminder-decisions!
        reminder-service #f #:now-date "2026-09-20" #:now-time "00:02"))
     (check-equal? (length later-decisions) 1)
     (check-equal? (task-item-id
                    (reminder-decision-task (car later-decisions)))
                   (task-item-id later))
     (check-true (service-acknowledge-reminder!
                  reminder-service
                  (reminder-decision-token (car later-decisions))
                  "attempted"))
     (check-true (service-acknowledge-reminder!
                  reminder-service
                  (reminder-decision-token (car later-decisions))
                  "failed"))
     (check-equal?
      (service-reminder-decisions!
       reminder-service #f #:now-date "2026-09-20" #:now-time "00:03")
      '())

     ;; Reopening the database starts a new logical session. An outstanding
     ;; token from the old service cannot acknowledge the new one.
     (define stale-token (reminder-decision-token summary))
     (close-taskly-service reminder-service)
     (define reopened (open-taskly-service reminder-path))
     (check-false
      (service-acknowledge-reminder! reopened stale-token "attempted"))
     (check-not-false
      (service-reminder-decisions!
       reopened #t #:now-date "2026-09-20" #:now-time "00:03"))
     (close-taskly-service reopened)))
 (lambda ()
   (delete-directory/files temp-root)))
