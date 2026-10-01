#lang racket/base

(require rivet/backend
         racket/string
         "config.rkt"
         "model.rkt"
         "rivet-schema.rkt"
         "service.rkt")

(provide start
         start-stdio)

(define current-service (box #f))
(define-event changed)

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

(define-rpc (close_database : Void)
  (define service (unbox current-service))
  (when service
    (close-taskly-service service)
    (set-box! current-service #f))
  (void))

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

(define-rpc (update_task [task : Task] : Task)
  (define service (require-service))
  (define updated (service-update-task! service (dto->task task)))
  (publish! service)
  (task->dto updated))

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

(define-rpc (update_list [item : TodoList] : TodoList)
  (define service (require-service))
  (define updated (service-update-list! service (dto->list item)))
  (publish! service)
  (list->dto updated))

(define-rpc (delete_list [id : Int64] : Bool)
  (define service (require-service))
  (define deleted? (service-delete-list! service id))
  (when deleted? (publish! service))
  deleted?)

(define-rpc (default_database : String)
  (path->string (resolve-database-path)))

(define-rpc (get_settings : Settings)
  (settings->dto))

;; Keys and values are validated here so hosts can persist preferences
;; without each one re-implementing the config grammar.
(define allowed-settings
  '(("language" ("zh" "en"))
    ("theme" ("system" "light" "dark"))
    ("close-to-tray" ("0" "1"))))

(define-rpc (set_setting [key : String] [value : String] : Settings)
  (define normalized-key (string-downcase (string-trim key)))
  ;; Integer-as-string per DATA-FORMAT §7; sidebar selection persists here.
  (unless (or (assoc normalized-key allowed-settings)
              (string=? normalized-key "last-selected-list-id"))
    (error 'set_setting "unknown setting: ~a" normalized-key))
  (cond
    [(assoc normalized-key allowed-settings)
     (unless (member value (cadr (assoc normalized-key allowed-settings)))
       (error 'set_setting "invalid value for ~a: ~a" normalized-key value))]
    [else
     (define parsed (string->number (string-trim value)))
     (unless (and parsed (exact-integer? parsed))
       (error 'set_setting "invalid value for ~a: ~a" normalized-key value))])
  (define config (read-config))
  (write-config! (hash-set config normalized-key (string-trim value)))
  (settings->dto))

;; Native embedded hosts pass anonymous pipe file descriptors here.
(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))

;; The managed development host speaks the exact same RVT1 protocol over
;; stdin/stdout. This is deliberately only a transport alternative: the
;; Taskly service and RPC surface remain identical to the embedded host.
(define (start-stdio)
  (serve (current-input-port) (current-output-port)))

(module+ main
  (start-stdio))
