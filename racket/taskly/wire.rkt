#lang racket/base

(require "model.rkt"
         "service.rkt")

(provide task-wire-fields
         list-wire-fields
         count-wire-fields
         task->wire
         list->wire
         snapshot->wire)

;; Rivet protocol v1 has primitives + nested lists but no records yet. Keep the
;; positional contract explicit here so Taskly drives a future Rivet Record
;; type instead of scattering magic indexes through native hosts.
(define task-wire-fields
  '(id list-id list-name text completed due-date due-time notes created-at))
(define list-wire-fields
  '(id name icon color pending-count))
(define count-wire-fields
  '(today planned all completed))

(define (nullable value)
  (if value value (void)))

(define (task->wire task)
  (list (task-item-id task)
        (task-item-list-id task)
        (nullable (task-item-list-name task))
        (task-item-text task)
        (task-item-completed task)
        (nullable (task-item-due-date task))
        (nullable (task-item-due-time task))
        (nullable (task-item-notes task))
        (task-item-created-at task)))

(define (list->wire item)
  (list (todo-list-id item)
        (todo-list-name item)
        (nullable (todo-list-icon item))
        (nullable (todo-list-color item))
        (todo-list-pending-count item)))

(define (snapshot->wire service #:view [view 'all] #:list-id [list-id #f]
                       #:show-completed [show-completed #f])
  (list (service-counts service)
        (map list->wire (service-lists service))
        (map task->wire
             (service-tasks service
                            #:view view
                            #:list-id list-id
                            #:show-completed show-completed))))
