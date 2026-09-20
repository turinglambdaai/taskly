#lang racket/base

(require rivet/backend
         "model.rkt"
         "service.rkt"
         "wire.rkt")

(provide start)

(define current-service (box #f))
(define-event changed)

(define (optional->false value)
  (if (void? value) #f value))

(define (require-service)
  (or (unbox current-service)
      (error 'taskly "database is not open")))

(define (publish! service)
  (changed (snapshot->wire service)))

(define-rpc (open_database [path : String] : Any)
  (define previous (unbox current-service))
  (when previous (close-taskly-service previous))
  (define service (open-taskly-service path))
  (set-box! current-service service)
  (snapshot->wire service))

(define-rpc (load_snapshot [view : String]
                           [list-id : (Optional Int64)]
                           [show-completed : Bool]
                           : Any)
  (snapshot->wire (require-service)
                  #:view view
                  #:list-id (optional->false list-id)
                  #:show-completed show-completed))

(define-rpc (add_task [text : String]
                      [list-id : (Optional Int64)]
                      [due-date : (Optional String)]
                      [due-time : (Optional String)]
                      [notes : (Optional String)]
                      : Any)
  (define service (require-service))
  (define task
    (service-add-task! service text
                       #:list-id (optional->false list-id)
                       #:due-date (optional->false due-date)
                       #:due-time (optional->false due-time)
                       #:notes (optional->false notes)))
  (publish! service)
  (task->wire task))

(define-rpc (update_task_text [id : Int64] [text : String] : Any)
  (define service (require-service))
  (define task (service-update-task-text! service id text))
  (publish! service)
  (task->wire task))

(define-rpc (set_completed [id : Int64] [completed : Bool] : Any)
  (define service (require-service))
  (define task (service-set-completed! service id completed))
  (publish! service)
  (task->wire task))

(define-rpc (delete_task [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-task! service id))
  (when deleted? (publish! service))
  deleted?)

(define-rpc (search_tasks [keyword : String] : Any)
  (map task->wire (service-search (require-service) keyword)))

(define-rpc (create_list [name : String]
                         [icon : (Optional String)]
                         [color : (Optional Int64)]
                         : Any)
  (define service (require-service))
  (define item
    (service-add-list! service name
                       #:icon (or (optional->false icon) default-list-icon)
                       #:color (or (optional->false color) default-list-color)))
  (publish! service)
  (list->wire item))

(define-rpc (delete_list [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-list! service id))
  (when deleted? (publish! service))
  deleted?)

(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))
