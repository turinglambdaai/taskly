#lang racket/base

(require racket/list
         racket/string
         "clock.rkt"
         "config.rkt"
         "db.rkt"
         "errors.rkt"
         "model.rkt"
         "validation.rkt")

(provide (struct-out taskly-service)
         open-taskly-service
         close-taskly-service
         service-lists
         service-tasks
         service-task
         service-add-task!
         service-update-task!
         service-update-task-text!
         service-set-completed!
         service-delete-task!
         service-search
         service-add-list!
         service-update-list!
         service-delete-list!
         service-counts)

(struct taskly-service (db) #:transparent)

(define (open-taskly-service [path #f])
  (taskly-service (open-taskly-db (resolve-database-path path))))

(define (close-taskly-service service)
  (close-taskly-db (taskly-service-db service)))

(define (service-lists service)
  (db-lists (taskly-service-db service)))

(define (normalize-view view)
  (define value
    (string-downcase
     (cond [(symbol? view) (symbol->string view)]
           [(string? view) view]
           [else ""])))
  (cond
    [(member value '("all" "today" "planned" "completed")) (string->symbol value)]
    [(string=? value "scheduled") 'planned]
    [else (raise-taskly 'validation 2 (format "Unknown task view: ~a" view))]))

(define (service-tasks service #:view [view 'all] #:list-id [list-id #f]
                       #:limit [limit 1000] #:offset [offset 0]
                       #:show-completed [show-completed #f])
  (db-tasks (taskly-service-db service)
            #:view (normalize-view view)
            #:list-id list-id
            #:limit limit
            #:offset offset
            #:show-completed show-completed))

(define (service-task service id)
  (db-task-by-id (taskly-service-db service) id))

(define (default-list-id service)
  (define lists (service-lists service))
  (unless (pair? lists)
    (raise-taskly 'not-found 3 "No lists exist yet. Create one with `taskly mklist` first."))
  (todo-list-id (car lists)))

(define (require-list service id)
  (or (db-list-by-id (taskly-service-db service) id)
      (raise-taskly 'not-found 3 (format "List not found: ~a" id))))

(define (service-add-task! service text
                           #:list-id [list-id #f]
                           #:due-date [due-date #f]
                           #:due-time [due-time #f]
                           #:notes [notes #f])
  (define clean-text (validate-task-text! text))
  (define selected-list-id (or list-id (default-list-id service)))
  (require-list service selected-list-id)
  (define task
    (task-item 0 selected-list-id clean-text due-date due-time #f (local-timestamp) notes #f))
  (define id (db-add-task! (taskly-service-db service) task))
  (service-task service id))

(define (require-task service id)
  (or (service-task service id)
      (raise-taskly 'not-found 3 (format "Task not found: ~a" id))))

(define (service-update-task! service replacement)
  (unless (task-item? replacement)
    (raise-argument-error 'service-update-task! "task-item?" replacement))
  (define existing (require-task service (task-item-id replacement)))
  (define list-id (task-item-list-id replacement))
  (require-list service list-id)
  (unless (boolean? (task-item-completed replacement))
    (raise-taskly 'validation 2 "completed must be a boolean"))
  (define updated
    (struct-copy task-item existing
                 [list-id list-id]
                 [text (validate-task-text! (task-item-text replacement))]
                 [due-date (task-item-due-date replacement)]
                 [due-time (task-item-due-time replacement)]
                 [completed (task-item-completed replacement)]
                 [notes (task-item-notes replacement)]))
  (db-update-task! (taskly-service-db service) updated)
  (service-task service (task-item-id updated)))

(define (service-update-task-text! service id text)
  (define existing (require-task service id))
  (service-update-task!
   service
   (struct-copy task-item existing [text text])))

(define (service-set-completed! service id completed?)
  (unless (boolean? completed?)
    (raise-taskly 'validation 2 "completed must be a boolean"))
  (unless (db-set-completed! (taskly-service-db service) id completed?)
    (raise-taskly 'not-found 3 (format "Task not found: ~a" id)))
  (service-task service id))

(define (service-delete-task! service id)
  (db-delete-task! (taskly-service-db service) id))

(define (service-search service keyword #:limit [limit 100])
  (db-search-tasks (taskly-service-db service)
                   (validate-search-keyword! keyword)
                   #:limit limit))

(define (service-add-list! service name #:icon [icon default-list-icon] #:color [color default-list-color])
  (define clean-name (validate-list-name! name))
  (define id (db-add-list! (taskly-service-db service) clean-name icon color))
  (db-list-by-id (taskly-service-db service) id))

(define (service-update-list! service replacement)
  (unless (todo-list? replacement)
    (raise-argument-error 'service-update-list! "todo-list?" replacement))
  (define existing (require-list service (todo-list-id replacement)))
  (define updated
    (struct-copy todo-list existing
                 [name (validate-list-name! (todo-list-name replacement))]
                 [icon (todo-list-icon replacement)]
                 [color (todo-list-color replacement)]))
  (db-update-list! (taskly-service-db service) updated)
  (db-list-by-id (taskly-service-db service) (todo-list-id updated)))

(define (service-delete-list! service id)
  (db-delete-list! (taskly-service-db service) id))

(define (service-counts service)
  (define db (taskly-service-db service))
  (list (db-count-today db)
        (db-count-planned db)
        (db-count-incomplete db)
        (db-count-completed db)))
