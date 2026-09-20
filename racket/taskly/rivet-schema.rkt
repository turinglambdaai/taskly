#lang racket/base

(require rivet/backend
         "model.rkt"
         "service.rkt")

(provide (all-defined-out))

;; Product DTOs. Rivet keeps these as named records in Racket/native code while
;; RVT1 continues to encode them as field-ordered lists for wire compatibility.
(define-record SmartCounts
  ([today : Int64]
   [planned : Int64]
   [all : Int64]
   [completed : Int64]))

(define-record TodoList
  ([id : Int64]
   [name : String]
   [icon : (Optional String)]
   [color : (Optional Int64)]
   [pending-count : Int64]))

(define-record Task
  ([id : Int64]
   [list-id : Int64]
   [list-name : (Optional String)]
   [text : String]
   [completed : Bool]
   [due-date : (Optional String)]
   [due-time : (Optional String)]
   [notes : (Optional String)]
   [created-at : String]))

(define-record Snapshot
  ([counts : SmartCounts]
   [lists : (List TodoList)]
   [tasks : (List Task)]))

(define (nullable value)
  (if value value (void)))

(define (optional->false value)
  (if (void? value) #f value))

(define (task->dto task)
  (Task (task-item-id task)
        (task-item-list-id task)
        (nullable (task-item-list-name task))
        (task-item-text task)
        (task-item-completed task)
        (nullable (task-item-due-date task))
        (nullable (task-item-due-time task))
        (nullable (task-item-notes task))
        (task-item-created-at task)))

(define (dto->task dto)
  (task-item (record-ref dto 'id)
             (record-ref dto 'list-id)
             (record-ref dto 'text)
             (optional->false (record-ref dto 'due-date))
             (optional->false (record-ref dto 'due-time))
             (record-ref dto 'completed)
             (record-ref dto 'created-at)
             (optional->false (record-ref dto 'notes))
             (optional->false (record-ref dto 'list-name))))

(define (list->dto item)
  (TodoList (todo-list-id item)
            (todo-list-name item)
            (nullable (todo-list-icon item))
            (nullable (todo-list-color item))
            (todo-list-pending-count item)))

(define (dto->list dto)
  (todo-list (record-ref dto 'id)
             (record-ref dto 'name)
             (optional->false (record-ref dto 'icon))
             (optional->false (record-ref dto 'color))
             (record-ref dto 'pending-count)))

(define (counts->dto counts)
  (SmartCounts (list-ref counts 0)
               (list-ref counts 1)
               (list-ref counts 2)
               (list-ref counts 3)))

(define (snapshot->dto service #:view [view 'all] #:list-id [list-id #f]
                       #:show-completed [show-completed #f])
  (Snapshot
   (counts->dto (service-counts service))
   (map list->dto (service-lists service))
   (map task->dto
        (service-tasks service
                       #:view view
                       #:list-id list-id
                       #:show-completed show-completed))))
