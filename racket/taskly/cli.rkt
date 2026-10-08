#lang racket/base

;; Taskly agent-facing CLI (shared/spec/CLI-SPEC.md). Golden-tested against
;; shared/cli-golden/ — byte-identical stdout/stderr/exit codes with the v1
;; native binaries, including the v1 quirk that validation messages are
;; localized (zh) while structural errors are English.

(require racket/string
         racket/format
         racket/file
         "clock.rkt"
         "config.rkt"
         "db.rkt"
         "date-parser.rkt"
         "errors.rkt"
         "model.rkt"
         "paths.rkt"
         "validation.rkt")

(provide run-cli)

;; ---- JSON emission (v1 parity: 2-space indent, non-ASCII \u-escaped,
;; null fields omitted, fixed key order) ----

(define (json-escape str)
  (define out (open-output-string))
  (for ([ch (in-string str)])
    (define n (char->integer ch))
    (cond
      [(= n 34) (display "\\\"" out)]
      [(= n 92) (display "\\\\" out)]
      [(= n 8) (display "\\b" out)]
      [(= n 9) (display "\\t" out)]
      [(= n 10) (display "\\n" out)]
      [(= n 12) (display "\\f" out)]
      [(= n 13) (display "\\r" out)]
      [(and (>= n 32) (<= n 126)) (display ch out)]
      [(< n 65536)
       (display "\\u" out)
       (display (~r n #:base 16 #:min-width 4 #:pad-string "0") out)]
      [else
       (define offset (- n 65536))
       (for ([unit (list (+ 55296 (quotient offset 1024))
                         (+ 56320 (remainder offset 1024)))])
         (display "\\u" out)
         (display (~r unit #:base 16 #:min-width 4 #:pad-string "0") out))]))
  (get-output-string out))

(define (jstr v) (string-append "\"" (json-escape v) "\""))
(define (jbool v) (if v "true" "false"))

;; fields: list of (cons key value-string); a field whose value is #f is
;; dropped (the CLI-SPEC "null fields omitted" rule).
(define (json-object fields pad)
  (string-append pad "{\n"
                 (string-join
                  (for/list ([f (in-list fields)])
                    (format "~a  ~a: ~a" pad (jstr (car f)) (cdr f)))
                  ",\n")
                 (format "\n~a}" pad)))

(define (json-array objects)
  (string-append "[\n" (string-join objects ",\n") "\n]"))

(define (task-fields t)
  (filter values
          (list (cons "id" (~a (task-item-id t)))
                (cons "listId" (~a (task-item-list-id t)))
                (and (task-item-list-name t)
                     (cons "listName" (jstr (task-item-list-name t))))
                (cons "text" (jstr (task-item-text t)))
                (cons "completed" (jbool (task-item-completed t)))
                (and (task-item-due-date t)
                     (cons "dueDate" (jstr (task-item-due-date t))))
                (and (task-item-due-time t)
                     (cons "dueTime" (jstr (task-item-due-time t))))
                (and (task-item-notes t)
                     (cons "notes" (jstr (task-item-notes t))))
                (cons "createdAt" (jstr (task-item-created-at t))))))

(define (task-json t [pad ""])
  (json-object (task-fields t) pad))

(define (list-fields l)
  (filter values
          (list (cons "id" (~a (todo-list-id l)))
                (cons "name" (jstr (todo-list-name l)))
                (and (todo-list-icon l)
                     (cons "icon" (jstr (todo-list-icon l))))
                (and (todo-list-color l)
                     (cons "color" (~a (todo-list-color l))))
                (cons "pendingCount" (~a (todo-list-pending-count l))))))

(define (list-json l [pad ""])
  (json-object (list-fields l) pad))

(define (ok-json id key value)
  (json-object (list (cons "ok" "true")
                     (cons "id" (~a id))
                     (cons key (jbool value)))
               ""))

;; ---- output / exit ----

(define (emit-json text)
  (displayln text (current-output-port)))

(define (fail exit-code message)
  (displayln
   (json-object (list (cons "ok" "false")
                      (cons "error" (jstr message))
                      (cons "exitCode" (~a exit-code)))
                "")
   (current-error-port))
  exit-code)

;; Validation errors surface localized (v1 zh-only GUI strings); every
;; other taskly error keeps its internal (English) message.
(define (zh-validation-message message)
  (cond
    [(equal? message "Please enter a task description.") "请输入任务描述"]
    [(string-prefix? message "Task description must be")
     (format "任务描述不能超过 ~a 个字符" max-task-text-length)]
    [(equal? message "Please enter a list name.") "请输入列表名称"]
    [(string-prefix? message "List name must be")
     (format "列表名称不能超过 ~a 个字符" max-list-name-length)]
    [(string-prefix? message "Search keyword must be")
     (format "搜索关键词不能超过 ~a 个字符" max-search-keyword-length)]
    [else message]))

(define (run-catching thunk)
  (with-handlers ([exn:fail:taskly?
                   (lambda (e)
                     (fail (exn:fail:taskly-exit-code e)
                           (zh-validation-message (exn-message e))))])
    (thunk)))

;; ---- arg parsing ----

(define value-flags
  '("--db" "--list" "--view" "--status" "--limit" "--due" "--time"
    "--notes" "--text" "--icon" "--color"))

(struct cli-args (subcommand positionals flags) #:transparent)

;; Returns (cli-args subcommand positionals flags); raises on a malformed
;; flag. Flags may appear anywhere; the first bare word is the subcommand.
(define (parse-args argv)
  (define flags (make-hash))
  (define positionals '())
  (define subcommand #f)
  (let loop ([rest argv])
    (unless (null? rest)
      (define a (car rest))
      (cond
        [(member a value-flags)
         (when (null? (cdr rest))
           (raise-taskly 'validation 2 (format "Missing value for ~a." a)))
         (define key (string->symbol (substring a 2)))
         (hash-set! flags key (cadr rest))
         (loop (cddr rest))]
        [(equal? a "--json")
         (hash-set! flags 'json #t)
         (loop (cdr rest))]
        [(or (equal? a "--quiet") (equal? a "-q"))
         (hash-set! flags 'quiet #t)
         (loop (cdr rest))]
        [(or (equal? a "--clear-due") (equal? a "--clear-time")
             (equal? a "--clear-notes"))
         (hash-set! flags (string->symbol (substring a 2)) #t)
         (loop (cdr rest))]
        [(and (string-prefix? a "-") (not (equal? a "-"))
              (not (member a '("--help" "-h"))))
         (raise-taskly 'validation 2 (format "Unknown option: \"~a\"" a))]
        [(not subcommand)
         (set! subcommand a)
         (loop (cdr rest))]
        [else
         (set! positionals (append positionals (list a)))
         (loop (cdr rest))])))
  (cli-args subcommand positionals flags))

(define (flag flags key [default #f])
  (hash-ref flags key default))

(define (flag-number flags key what)
  (define raw (flag flags key))
  (and raw
       (let ([n (string->number (string-trim raw))])
         (unless n
           (raise-taskly 'validation 2 (format "Invalid ~a: \"~a\"" what raw)))
         n)))

;; "--list ID|NAME": numeric means id, anything else is a case-sensitive
;; exact name (CLI-SPEC § list).
(define (resolve-list db raw)
  (define n (string->number (string-trim raw)))
  (define list
    (if n
        (db-list-by-id db n)
        (db-list-by-name db (string-trim raw))))
  (unless list
    (raise-taskly 'not-found 3 (format "List not found by name: \"~a\"" raw)))
  list)

(define (normalize-view raw)
  (define v (string-downcase (string-trim raw)))
  (cond
    [(equal? v "scheduled") 'planned]
    [(member v '("today" "planned" "all" "completed")) (string->symbol v)]
    [else
     (raise-taskly 'validation 2
                   (format "Invalid --view: \"~a\". Use today | planned | all | completed" raw))]))

;; all|completed → include completed (sunk to bottom); everything else →
;; incomplete only (CLI-SPEC § list --status).
(define (status->show-completed raw)
  (define s (and raw (string-downcase (string-trim raw))))
  (if (member s '("all" "completed")) #t #f))

(define (resolve-due! flags)
  (define raw (flag flags 'due))
  (if raw
      (let-values ([(d tm) (parse-due-expression raw)])
        (cons d tm))
      (cons #f #f)))

(define (parse-time-flag flags existing)
  (define explicit (flag flags 'time))
  (cond
    [(and explicit (not (regexp-match? #px"^\\d{2}:\\d{2}$" explicit)))
     (raise-taskly 'validation 2 (format "Invalid --time: \"~a\". Use HH:mm" explicit))]
    [explicit explicit]
    [else existing]))

(define (join-positionals positionals)
  (string-join positionals " "))

(define (parse-id positionals what)
  (define n (and (pair? positionals) (string->number (string-trim (car positionals)))))
  (unless n
    (raise-taskly 'validation 2 (format "~a requires a numeric id." what)))
  n)

;; ---- human-readable rows (v1 parity) ----

(define (task-row t)
  (define due
    (if (task-item-due-date t)
        (format "  🗓 ~a~a"
                (task-item-due-date t)
                (if (task-item-due-time t)
                    (format " ~a" (task-item-due-time t))
                    ""))
        ""))
  (format "~a  [~a]  ~a~a"
          (~r (task-item-id t) #:min-width 7 #:pad-string " ")
          (if (task-item-completed t) "x" " ")
          (task-item-text t)
          due))

(define (list-row l)
  (format "~a  ~a ~a  (~a)"
          (~r (todo-list-id l) #:min-width 7 #:pad-string " ")
          (or (todo-list-icon l) default-list-icon)
          (todo-list-name l)
          (todo-list-pending-count l)))

;; ---- commands ----

(define help-text
  (string-append
   "Taskly — task manager command-line interface (for AI agents & scripting)\n"
   "Commands: list, lists, add, update, done, undone, rm, search, mklist, rmlist, install-cli, uninstall-cli\n"
   "Global options: --json, --db <path>, --quiet (-q)\n"))

(define (cmd-list db a)
  (define flags (cli-args-flags a))
  (define list-filter (flag flags 'list))
  (define list-row*
    (and list-filter (resolve-list db list-filter)))
  (define view
    (if list-row*
        'all
        (normalize-view (or (flag flags 'view) "all"))))
  (define show-completed (status->show-completed (flag flags 'status)))
  (define limit (or (flag-number flags 'limit "--limit") 1000))
  (define tasks
    (db-tasks db
              #:view view
              #:list-id (and list-row* (todo-list-id list-row*))
              #:limit limit
              #:show-completed show-completed))
  (cond
    [(flag flags 'json)
     (if (flag flags 'quiet)
         (for ([t (in-list tasks)]) (displayln (task-item-id t)))
         (emit-json
          (if (null? tasks)
              "[]"
              (json-array (for/list ([t (in-list tasks)]) (task-json t "  "))))))]
    [(flag flags 'quiet)
     (for ([t (in-list tasks)]) (displayln (task-item-id t)))]
    [else
     (if (null? tasks)
         (displayln "(no tasks)")
         (for ([t (in-list tasks)]) (displayln (task-row t))))])
  0)

(define (cmd-lists db a)
  (define flags (cli-args-flags a))
  (define lists (db-lists db))
  (cond
    [(flag flags 'json)
     (emit-json
      (if (null? lists)
          "[]"
          (json-array (for/list ([l (in-list lists)]) (list-json l "  ")))))]
    [(flag flags 'quiet)
     (for ([l (in-list lists)]) (displayln (todo-list-id l)))]
    [else
     (if (null? lists)
         (displayln "(no lists)")
         (for ([l (in-list lists)]) (displayln (list-row l))))])
  0)

(define (cmd-add db a)
  (define flags (cli-args-flags a))
  (define text (validate-task-text! (join-positionals (cli-args-positionals a))))
  (define due (resolve-due! flags))
  (define time (parse-time-flag flags (cdr due)))
  (define list
    (if (flag flags 'list)
        (resolve-list db (flag flags 'list))
        (let ([lists (db-lists db)])
          (when (null? lists)
            (raise-taskly 'not-found 3
                          "No lists exist yet. Create one with `taskly mklist` first."))
          (car lists))))
  (define new-id
    (db-add-task!
     db
     (task-item 0
                (todo-list-id list)
                text
                (car due)
                time
                #f
                (local-timestamp)
                (flag flags 'notes)
                #f)))
  (define t (db-task-by-id db new-id))
  (cond
    [(flag flags 'json)
     (if (flag flags 'quiet)
         (displayln (task-item-id t))
         (emit-json (task-json t)))]
    [(flag flags 'quiet) (displayln (task-item-id t))]
    [else (displayln (task-row t))])
  0)

(define (cmd-update db a)
  (define flags (cli-args-flags a))
  (define id (parse-id (cli-args-positionals a) "update"))
  (define t (db-task-by-id db id))
  (unless t (raise-taskly 'not-found 3 (format "Task not found: ~a" id)))

  (define text (task-item-text t))
  (when (flag flags 'text)
    (set! text (validate-task-text! (flag flags 'text))))
  (define list-id (task-item-list-id t))
  (when (flag flags 'list)
    (set! list-id (todo-list-id (resolve-list db (flag flags 'list)))))
  (define due-date (task-item-due-date t))
  (define due-time (task-item-due-time t))
  (when (flag flags 'due)
    (define parsed (resolve-due! flags))
    ;; A pure-date expression keeps the existing time (CLI-SPEC § update).
    (set! due-date (car parsed))
    (when (cdr parsed) (set! due-time (cdr parsed))))
  (when (flag flags 'clear-due) (set! due-date #f))
  (set! due-time (parse-time-flag flags due-time))
  (when (flag flags 'clear-time) (set! due-time #f))
  (define notes (task-item-notes t))
  (when (flag flags 'notes) (set! notes (flag flags 'notes)))
  (when (flag flags 'clear-notes) (set! notes #f))

  (db-update-task!
   db
   (task-item id list-id text due-date due-time
              (task-item-completed t) (task-item-created-at t) notes
              (task-item-list-name t)))
  (define updated (db-task-by-id db id))
  (cond
    [(flag flags 'json) (emit-json (task-json updated))]
    [(flag flags 'quiet) (displayln id)]
    [else (displayln (task-row updated))])
  0)

(define (cmd-set-completed db a completed?)
  (define flags (cli-args-flags a))
  (define id (parse-id (cli-args-positionals a) (if completed? "done" "undone")))
  (unless (db-set-completed! db id completed?)
    (raise-taskly 'not-found 3 (format "Task not found: ~a" id)))
  (define t (db-task-by-id db id))
  (cond
    [(and (flag flags 'json) (flag flags 'quiet))
     (emit-json (ok-json id "completed" (task-item-completed t)))]
    [(flag flags 'json) (emit-json (task-json t))]
    [(flag flags 'quiet) (displayln id)]
    [else
     (displayln (if completed? (format "Task ~a completed" id)
                    (format "Task ~a reopened" id)))])
  0)

(define (cmd-rm db a)
  (define flags (cli-args-flags a))
  (define id (parse-id (cli-args-positionals a) "rm"))
  (define deleted? (db-delete-task! db id))
  (if (flag flags 'json)
      (emit-json (ok-json id "deleted" deleted?))
      (if deleted?
          (displayln (format "Deleted task ~a" id))
          (displayln (format "Task ~a did not exist" id))))
  0)

(define (cmd-search db a)
  (define flags (cli-args-flags a))
  (define keyword (join-positionals (cli-args-positionals a)))
  (define limit (or (flag-number flags 'limit "--limit") 100))
  (define tasks
    (if (equal? keyword "")
        '()
        (db-search-tasks db keyword #:limit limit)))
  (cond
    [(flag flags 'json)
     (emit-json
      (if (null? tasks)
          "[]"
          (json-array (for/list ([t (in-list tasks)]) (task-json t "  ")))))]
    [(flag flags 'quiet)
     (for ([t (in-list tasks)]) (displayln (task-item-id t)))]
    [else
     (if (null? tasks)
         (displayln "(no tasks)")
         (for ([t (in-list tasks)]) (displayln (task-row t))))])
  0)

(define (parse-color raw)
  (define s (string-trim raw))
  (define n (string->number s))
  (cond
    [n n]
    [(regexp-match? #px"^#[0-9a-fA-F]{6}$" s)
     (define rgb (string->number (substring s 1) 16))
     (+ -16777216 rgb)] ; 0xFF000000 | rgb
    [(regexp-match? #px"^#[0-9a-fA-F]{8}$" s)
     (string->number (substring s 1) 16)]
    [else
     (raise-taskly 'validation 2
                   (format "Invalid hex color: \"~a\". Use #RRGGBB (6) or #AARRGGBB (8)" raw))]))

(define (cmd-mklist db a)
  (define flags (cli-args-flags a))
  (define name (validate-list-name! (join-positionals (cli-args-positionals a))))
  (define color (and (flag flags 'color) (parse-color (flag flags 'color))))
  (define new-id
    (db-add-list! db name
                  (or (flag flags 'icon) default-list-icon)
                  (or color default-list-color)))
  (define l (db-list-by-id db new-id))
  (cond
    [(flag flags 'json)
     (if (flag flags 'quiet)
         (displayln (todo-list-id l))
         (emit-json (list-json l)))]
    [(flag flags 'quiet) (displayln (todo-list-id l))]
    [else (displayln (list-row l))])
  0)

(define (cmd-rmlist db a)
  (define flags (cli-args-flags a))
  (define id (parse-id (cli-args-positionals a) "rmlist"))
  (define deleted? (db-delete-list! db id))
  (if (flag flags 'json)
      (emit-json (ok-json id "deleted" deleted?))
      (if deleted?
          (displayln (format "Deleted list ~a (and its tasks)" id))
          (displayln (format "List ~a did not exist" id))))
  0)

;; install-cli: a shell wrapper at ~/.local/bin/taskly. Under development the
;; CLI runs through the racket interpreter, so the wrapper execs the running
;; racket with this script; packaged builds pass their own binary (M7).
(define (cmd-install-cli)
  (define bin-dir (expand-user-path "~/.local/bin"))
  (define wrapper (build-path bin-dir "taskly"))
  (make-directory* bin-dir)
  (define exe (path->string (find-system-path 'exec-file)))
  (define script (path->string (find-system-path 'run-file)))
  (define dev-mode? (string-suffix? script ".rkt"))
  (define body
    (if dev-mode?
        (format "#!/bin/sh\nexec \"~a\" \"~a\" \"$@\"\n" exe script)
        (format "#!/bin/sh\nexec \"~a\" \"$@\"\n" exe)))
  (display-to-file body wrapper #:exists 'truncate)
  (file-or-directory-permissions wrapper '(read write execute))
  (define path-env (getenv "PATH"))
  (unless (and path-env (member (path->string bin-dir) (string-split path-env ":")))
    (define rc (expand-user-path "~/.zshrc"))
    (when (file-exists? rc)
      (define content (file->string rc))
      (unless (string-contains? content "# Added by Taskly")
        (call-with-output-file rc
          (lambda (out)
            (display content out)
            (displayln "\n# Added by Taskly" out)
            (displayln "export PATH=\"$HOME/.local/bin:$PATH\"" out))
          #:exists 'append))))
  (displayln (format "Installed: ~a" (path->string wrapper)))
  0)

(define (cmd-uninstall-cli)
  (define wrapper (expand-user-path "~/.local/bin/taskly"))
  (if (file-exists? wrapper)
      (begin
        (delete-file wrapper)
        (displayln (format "Removed: ~a" (path->string wrapper)))
        0)
      (begin
        (displayln "taskly command was not installed (nothing to remove)."
                   (current-error-port))
        1)))

;; ---- entry ----

;; Raises (so the run-catching wrapper formats it as the exit-4 JSON):
;; `Cannot open database: <path> (<detail>)` — CLI-SPEC pins the prefix.
(define (open-cli-database flags)
  (define override (flag flags 'db))
  (define resolved
    (or override
        (let ([config (read-config)])
          (path->string (resolve-database-path #f config)))))
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (raise-taskly 'database 4
                        (format "Cannot open database: ~a (~a)" resolved (exn-message e))))])
    (open-taskly-db resolved)))

;; Golden contract (db-unopenable): v1 `list --json` had already emitted
;; the empty array to stdout when the open failed, so the failure carries
;; a leading `[]` on stdout ahead of the exit-4 error JSON on stderr.
(define (open-cli-database-for-list flags)
  (with-handlers ([exn:fail:taskly?
                   (lambda (e)
                     (when (flag flags 'json) (displayln "[]"))
                     (raise e))])
    (open-cli-database flags)))

(define (dispatch a)
  (define sub (cli-args-subcommand a))
  (define flags (cli-args-flags a))
  (cond
    [(or (not sub) (equal? sub "help") (equal? sub "--help") (equal? sub "-h"))
     (display help-text)
     0]
    [(member sub '("list" "ls"))
     (cmd-list (open-cli-database-for-list flags) a)]
    [(equal? sub "lists")
     (cmd-lists (open-cli-database flags) a)]
    [(equal? sub "add")
     (cmd-add (open-cli-database flags) a)]
    [(equal? sub "update")
     (cmd-update (open-cli-database flags) a)]
    [(equal? sub "done")
     (cmd-set-completed (open-cli-database flags) a #t)]
    [(equal? sub "undone")
     (cmd-set-completed (open-cli-database flags) a #f)]
    [(equal? sub "rm")
     (cmd-rm (open-cli-database flags) a)]
    [(equal? sub "search")
     (cmd-search (open-cli-database flags) a)]
    [(equal? sub "mklist")
     (cmd-mklist (open-cli-database flags) a)]
    [(equal? sub "rmlist")
     (cmd-rmlist (open-cli-database flags) a)]
    [(equal? sub "install-cli") (cmd-install-cli)]
    [(equal? sub "uninstall-cli") (cmd-uninstall-cli)]
    [else (fail 1 (format "Unknown command: \"~a\"" sub))]))

(define (run-cli argv)
  (run-catching (lambda () (dispatch (parse-args argv)))))

(module+ main
  (exit (run-cli (vector->list (current-command-line-arguments)))))
