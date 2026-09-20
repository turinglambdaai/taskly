#lang racket/base

(require rackunit
         racket/file
         rivet/backend
         "../taskly/clock.rkt"
         "../taskly/model.rkt"
         "../taskly/paths.rkt"
         "../taskly/rivet-schema.rkt"
         "../taskly/service.rkt")

(define temp-root (make-temporary-file "taskly-rivet-schema-~a" 'directory))

(dynamic-wind
 void
 (lambda ()
   (parameterize ([current-taskly-home temp-root])
     (define names
       (map (lambda (entry) (hash-ref entry 'name)) (record-schema)))
     (check-equal? names '("SmartCounts" "Snapshot" "Task" "TodoList"))

     (define service (open-taskly-service (build-path temp-root "schema.db")))
     (define created (service-add-task! service "typed task" #:due-date "2026-09-20"))
     (define dto (task->dto created))
     (check-equal? (record-ref dto 'id) (task-item-id created))
     (check-equal? (record-ref dto 'text) "typed task")
     (check-equal? (record-ref dto 'due-date) "2026-09-20")
     (check-true (void? (record-ref dto 'due-time)))

     (define snapshot (snapshot->dto service))
     (define counts (record-ref snapshot 'counts))
     (check-equal? (record-ref counts 'all) 1)
     (check-equal? (length (record-ref snapshot 'lists)) 1)
     (check-equal? (length (record-ref snapshot 'tasks)) 1)

     (close-taskly-service service)))
 (lambda ()
   (delete-directory/files temp-root)))
