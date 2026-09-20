#lang racket/base

(require rivet/backend
         "model.rkt"
         "rivet-schema.rkt"
         "service.rkt")

(provide start)

(define current-service (box #f))
(define-event changed)

(define (optional->false value)
  (if (void? value) #f value))

(define (require-service)
  (or (unbox current-service)
      (error 'taskly "database is not open")))

(define (publish! service)
  (changed (snapshot->dto service)))

(define-rpc (open_database [path : String] : Snapshot)
  (define previous (unbox current-service))
  (when previous (close-taskly-service previous))
  (define service (open-taskly-service path))
  (set-box! current-service service)
  (snapshot->dto service))

(define-rpc (load_snapshot [view : String]
                           [list-id : (Optional Int64)]
                           [show-completed : Bool]
                           : Snapshot)
  (snapshot->dto (require-service)
                 #:view view
                 #:list-id (optional->false list-id)
                 #:show-completed show-completed))

(define-rpc (add_task [text : String]
                      [list-id : (Optional Int64)]
                      [due-date : (Optional String)]
                      [due-time : (Optional String)]
                      [notes : (Optional String)]
                      : Task)
  (define service (require-service))
  (define task
    (service-add-task! service text
                       #:list-id (optional->false list-id)
                       #:due-date (optional->false due-date)
                       #:due-time (optional->false due-time)
                       #:notes (optional->false notes)))
  (publish! service)
  (task->dto task))

(define-rpc (update_task_text [id : Int64] [text : String] : Task)
  (define service (require-service))
  (define task (service-update-task-text! service id text))
  (publish! service)
  (task->dto task))

(define-rpc (set_completed [id : Int64] [completed : Bool] : Task)
  (define service (require-service))
  (define task (service-set-completed! service id completed))
  (publish! service)
  (task->dto task))

(define-rpc (delete_task [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-task! service id))
  (when deleted? (publish! service))
  deleted?)

(define-rpc (search_tasks [keyword : String] : (List Task))
  (map task->dto (service-search (require-service) keyword)))

(define-rpc (create_list [name : String]
                         [icon : (Optional String)]
                         [color : (Optional Int64)]
                         : TodoList)
  (define service (require-service))
  (define item
    (service-add-list! service name
                       #:icon (or (optional->false icon) default-list-icon)
                       #:color (or (optional->false color) default-list-color)))
  (publish! service)
  (list->dto item))

(define-rpc (delete_list [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-list! service id))
  (when deleted? (publish! service))
  deleted?)

(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))
