#lang racket/base

(require rivet/backend
         json
         racket/date
         racket/file
         racket/format
         racket/string
         "config.rkt"
         "date-parser.rkt"
         "errors.rkt"
         "model.rkt"
         "paths.rkt"
         "rivet-schema.rkt"
         "service.rkt"
         "updater.rkt")

(provide start
         start-stdio)

;; Rivet's diagnostic sink defaults to current-error-port. A Windows
;; GUI-subsystem process has no console, and the embedded Chez runtime
;; lazily allocates one on the first stderr write — the black console
;; window users saw open before the app window, streaming RVT1 protocol
;; records (on mac/Linux stderr lands in a terminal or /dev/null, so it
;; never showed there). Diagnostics keep their value as JSONL appended to
;; ~/.taskly/diagnostics.log instead; stderr is never touched, so no
;; console is ever allocated. Rivet already swallows sink exceptions, so
;; an unwritable path drops records rather than failing the backend.
(define diagnostics-port (box #f))
(define diagnostics-lock (make-semaphore 1))

(define (diagnostics-log-path)
  (build-path (taskly-directory) "diagnostics.log"))

(define (diagnostic-timestamp)
  ;; Local ISO-8601 (no zone suffix): machine-sortable, human-readable.
  (define d (seconds->date (current-seconds) #f))
  (format "~a-~a-~aT~a:~a:~a"
          (date-year d)
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0")
          (~r (date-minute d) #:min-width 2 #:pad-string "0")
          (~r (date-second d) #:min-width 2 #:pad-string "0")))

(define (taskly-diagnostic-sink record)
  (call-with-semaphore
   diagnostics-lock
   (lambda ()
     (define out
       (or (unbox diagnostics-port)
           (let ([port
                  (begin
                    ;; The directory may not exist yet during the very first
                    ;; handshake (open_database creates it right after).
                    (with-handlers ([exn:fail? void])
                      (make-directory* (taskly-directory)))
                    (open-output-file (diagnostics-log-path)
                                      #:exists 'append))])
             (set-box! diagnostics-port port)
             port)))
     (write-json (hash-set record 'ts (diagnostic-timestamp)) out)
     (newline out)
     (flush-output out))))

;; Module top level: runs on the boot thread that later invokes `start`,
;; so serve-fds picks this sink up as its default.
(current-rivet-diagnostic-sink taskly-diagnostic-sink)

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

;; Canonical quick-add/date-expression parsing (CLI-SPEC `--due` grammar).
;; Returns `yyyy-MM-dd` for pure-date intents, `yyyy-MM-dd HH:mm:ss`
;; otherwise — the 10-char shape IS the pure-date signal. Unparseable input
;; raises the validation error; hosts decide how to surface it.
(define-rpc (parse_due [expression : String] : String)
  (define-values (d t) (parse-due-expression expression))
  (if t (format "~a ~a:00" d t) d))

(define-rpc (parse_quick_add [text : String] : QuickAddParse)
  (if (string=? (string-trim text) "")
      (QuickAddParse text (void) (void))
      (let-values ([(clean command) (extract-quick-add-command text)])
        (if (not command)
            (QuickAddParse clean (void) (void))
            (with-handlers
                ([exn:fail:taskly?
                  (lambda (_) (QuickAddParse clean (void) (void)))])
              (let-values ([(d t) (parse-due-expression command)])
                (QuickAddParse clean (nullable d) (nullable t))))))))

(define-rpc (get_settings : Settings)
  (settings->dto))

;; Keys and values are validated here so hosts can persist preferences
;; without each one re-implementing the config grammar.
(define allowed-settings
  '(("language" ("zh" "en"))
    ("theme" ("system" "light" "dark"))
    ("close-to-tray" ("0" "1"))
    ;; Host-declared install shape (Windows: msi vs portable zip) — the
    ;; updater picks the download flavor from it (UPDATE.md).
    ("install-flavor" ("zip" "msi"))))

;; Integer-as-string per DATA-FORMAT §7: sidebar selection and the
;; update-check throttle (shared/spec/UPDATE.md) persist as plain integers.
(define integer-settings '("last-selected-list-id" "last-update-check"))

(define-rpc (set_setting [key : String] [value : String] : Settings)
  (define normalized-key (string-downcase (string-trim key)))
  (unless (or (assoc normalized-key allowed-settings)
              (member normalized-key integer-settings))
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
  ;; read-config returns a mutable hash — hash-set! (not the
  ;; immutable-only hash-set) or every write would fail and hosts'
  ;; try?-swallowed RPC errors would silently drop preferences.
  (hash-set! config normalized-key (string-trim value))
  (write-config! config)
  (settings->dto))

;; Raw config read for host-side state that has no Settings slot (e.g. the
;; last-update-check throttle, DATA-FORMAT §7). Unset keys read as the empty
;; string so hosts parse a single shape ("value or default").
(define-rpc (get_setting [key : String] : String)
  (config-ref (read-config) (string-downcase (string-trim key)) ""))

;; ------------------------------------------------------------ online update
;; The family pattern (rivet/distribution): this backend verifies and
;; downloads the signed artifact; hosts own installation and the silent
;; 4-hour throttle (last-update-check config key, shared/spec/UPDATE.md).

(define (update-check->record result)
  (define (opt key) (nullable (hash-ref result key #f)))
  (UpdateCheck
   (hash-ref result 'status "error")
   (opt 'message)
   (hash-ref result 'currentVersion app-version)
   (opt 'availableVersion)
   (opt 'build)
   (opt 'publishedAt)
   (opt 'installer)
   (opt 'sizeBytes)))

;; Never raises: network/manifest failures surface as status "error" so a
;; headless check can't take the host down with it.
(define-rpc (check_updates : UpdateCheck)
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (UpdateCheck "error" (nullable (exn-message e)) app-version
                       (void) (void) (void) (void) (void)))])
    (update-check->record (perform-check!))))

;; Runs on a backend worker thread; the host follows progress via
;; update_state. Never raises: failures surface through the state's phase.
(define-rpc (start_download : Void)
  (with-handlers
      ([exn:fail? (lambda (e) (set-update-error! (exn-message e)))])
    (start-download! (taskly-directory)))
  (void))

(define-rpc (update_state : UpdateState)
  (define s (update-state-snapshot))
  (UpdateState
   (hash-ref s 'phase "idle")
   (hash-ref s 'percent 0)
   (nullable (hash-ref s 'message #f))
   (nullable (hash-ref s 'downloadedPath #f))
   (nullable (hash-ref s 'availableVersion #f))))

;; Native embedded hosts pass anonymous pipe file descriptors here.
(define (start in-fd out-fd)
  (serve-fds in-fd out-fd))

;; Test seam: the generated RPC handlers are plain functions; contract
;; tests import them directly without standing up an RVT1 server.
(module+ rpcs
  (provide get_setting set_setting))

;; The managed development host speaks the exact same RVT1 protocol over
;; stdin/stdout. This is deliberately only a transport alternative: the
;; Taskly service and RPC surface remain identical to the embedded host.
(define (start-stdio)
  (serve (current-input-port) (current-output-port)
         ;; serve's own default sink is `void`; pass the file sink so the
         ;; managed dev host records diagnostics like the packaged one.
         #:diagnostic-sink (current-rivet-diagnostic-sink)))

(module+ main
  (start-stdio))
