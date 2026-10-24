#lang racket/base

;; Wire-level backend regression: drive the production backend module over
;; RVT1 the way a native host does — real frames, real codec, real serve
;; dispatch — and exercise every registered RPC (encoding, decoding, result
;; shape). Direct-contract tests (backend-test.rkt) call plain functions;
;; this layer additionally catches RPC-name shadowing, handler arity,
;; record field order across the wire, Optional void-encoding, and Event
;; emission (fulcrum once shipped RPCs whose handlers recursed into their
;; own definitions — invisible until driven over the wire). The data RPCs
;; (load_snapshot/add_task/update_task/search_tasks, list CRUD) previously
;; had only the CLI golden suite backing them indirectly.

(require rackunit
         racket/file
         racket/list
         racket/match
         racket/path
         racket/string
         rivet/backend
         rivet/protocol
         "../taskly/paths.rkt"
         "../taskly/updater.rkt" ; current-update-base-url test seam
         "../taskly/version.rkt")

;; Isolation: the whole backend runs against a throwaway home (config.ini,
;; tasks.db, diagnostics.log) and the update feed is pinned to a closed
;; local port, so no RPC here touches the network or ~/.taskly. Parameters
;; are set before the serve thread spawns, and every thread serve creates
;; inherits them.
(define root (make-temporary-file "taskly-wire-~a" 'directory))
(current-taskly-home root)
(current-update-base-url "https://127.0.0.1:9/taskly")

;; Load the production backend module: registering every RPC/Event happens
;; at require time, exactly as in the embedded runtime.
(define test-dir (or (current-load-relative-directory) (current-directory)))
(define backend-path
  (simplify-path (build-path test-dir ".." "taskly" "backend.rkt")))
(void (dynamic-require backend-path #f))

;; The registered surface must be exactly the declared one. This is the
;; shadowing guard: a name colliding with (or vanishing behind) another
;; binding shifts this set instead of silently serving the wrong handler.
(check-equal?
 (sort (map (lambda (rpc) (hash-ref rpc 'name)) (rpc-schema)) string<?)
 (sort (map symbol->string
            '(acknowledge_reminder add_task check_updates close_database create_list
              default_database delete_list delete_task get_setting
              get_settings load_snapshot open_database parse_due
              parse_quick_add reminder_decisions search_tasks set_completed set_setting
              start_download update_list update_state update_task
              update_task_text))
       string<?)
 "the registered RPC surface drifted; extend this wire test to cover it")

(define-values (server-in client-out) (make-pipe))
(define-values (client-in server-out) (make-pipe))
(define srv (thread (lambda () (serve server-in server-out))))

;; Waiting on a dedicated reader thread (not port readiness, like a naive
;; sync/timeout on the port) means a partial frame never trips the timeout.
(define (read-frame/timeout what)
  (define result-box (box #f))
  (define failure-box (box #f))
  (define reader
    (thread
     (lambda ()
       (with-handlers ([exn:fail? (lambda (e) (set-box! failure-box e))])
         (set-box! result-box (read-frame client-in))))))
  (unless (sync/timeout 30 reader)
    (fail (format "wire test: timed out waiting for ~a (server alive: ~a)"
                  what (not (thread-dead? srv)))))
  (when (unbox failure-box)
    (raise (unbox failure-box)))
  (unbox result-box))

;; Returns two values: the decoded response (or #f on an error frame) and
;; the decoded error message (or #f). Events observed while the request ran
;; land in last-events.
(define last-events '())
(define next-id 100)
(define (call-rpc rpc-name . args)
  (set! next-id (add1 next-id))
  (define id next-id)
  (write-frame (frame message:request
                      id
                      (encode-value (list* (symbol->string rpc-name) args)))
               client-out)
  (flush-output client-out)
  (let loop ([events '()])
    (define f (read-frame/timeout (format "~a response" rpc-name)))
    (match (frame-type f)
      [(== message:hello) (loop events)]
      [(== message:event)
       (loop (cons (decode-value (frame-payload f)) events))]
      [(== message:response)
       (check-equal? (frame-id f) id "response id must correlate with the request")
       (set! last-events events)
       (values (decode-value (frame-payload f)) #f)]
      [(== message:error)
       (set! last-events events)
       (values #f (decode-value (frame-payload f)))]
      [_ (loop events)])))

(define date-shape #px"^\\d{4}-\\d{2}-\\d{2}$")

(dynamic-wind
 void
 (lambda ()
   ;; Handshake: the server opens with the RVT1 hello frame.
   (define hello (read-frame/timeout "hello"))
   (check-equal? (frame-type hello) message:hello)
   (check-equal? (decode-value (frame-payload hello))
                 (list "rivet" protocol-version))

   ;; ---- RPCs that work with no database open ----------------------------

   (define-values (default-db _db-err) (call-rpc 'default_database))
   (check-true (string-prefix? default-db (path->string root))
               "default_database resolves under the taskly home")

   ;; parse_due: pure date stays a date; relative days resolve to a date;
   ;; garbage raises the validation error as an error frame.
   (define-values (due-fixed _df-err) (call-rpc 'parse_due "2026-11-03"))
   (check-equal? due-fixed "2026-11-03")
   (define-values (due-rel _dr-err) (call-rpc 'parse_due "tomorrow"))
   (check-true (regexp-match? date-shape due-rel))
   (define-values (_pd-val pd-err) (call-rpc 'parse_due "not a date at all"))
   (check-true (and (string? pd-err) (string-contains? pd-err "Cannot parse"))
               "unparseable expressions surface the validation error")

   ;; parse_quick_add: the trailing @time command splits off and parses;
   ;; plain text round-trips with both optionals empty ((void) on the wire).
   (define-values (qa-plain _qp-err) (call-rpc 'parse_quick_add "plain task"))
   (check-equal? qa-plain (list "plain task" (void) (void)))
   (define-values (qa-due _qd-err) (call-rpc 'parse_quick_add "pay rent @10am"))
   (check-equal? (list-ref qa-due 0) "pay rent")
   (check-true (regexp-match? date-shape (list-ref qa-due 1)))
   (check-equal? (list-ref qa-due 2) "10:00")

   ;; Error shape before open: require-service fails as an error frame, not
   ;; a crash and not an empty success.
   (define-values (_pre-open pre-open-err)
     (call-rpc 'search_tasks "anything"))
   (check-true (and (string? pre-open-err)
                    (string-contains? pre-open-err "database is not open")))

   ;; ---- open + the data plane -------------------------------------------

   (define db-path (path->string (build-path root "wire.db")))
   (define-values (snap0 _open-err) (call-rpc 'open_database db-path))
   ;; Snapshot wire shape: [counts lists tasks], counts [today planned all
   ;; completed] (all counts incomplete tasks), lists [id name icon color
   ;; pending-count], tasks [id list-id list-name text completed due-date
   ;; due-time notes created-at].
   (check-equal? (length snap0) 3)
   (check-equal? (list-ref snap0 0) (list 0 0 0 0))
   (check-equal? (list-ref snap0 1)
                 (list (list 1 "工作" "📋" -16745729 0)))
   (check-equal? (list-ref snap0 2) '())

   (define-values (task-a-wire _add-a-err)
     (call-rpc 'add_task "write wire test" (void) (void) (void) (void)))
   (check-false _add-a-err)
   (check-equal? (length task-a-wire) 9)
   (check-equal? (list-ref task-a-wire 0) 1)
   (check-equal? (list-ref task-a-wire 1) 1)
   (check-equal? (list-ref task-a-wire 2) "工作")
   (check-equal? (list-ref task-a-wire 3) "write wire test")
   (check-equal? (list-ref task-a-wire 4) #f)
   (check-equal? (list-ref task-a-wire 5) (void))
   (check-equal? (list-ref task-a-wire 7) (void))
   (check-true (string? (list-ref task-a-wire 8)) "created-at travels")
   ;; Every mutation publishes the changed event with a wire snapshot.
   (check-equal? (length last-events) 1)
   (check-equal? (car (car last-events)) "changed")
   (check-equal? (length (cadr (car last-events))) 3)

   (define-values (task-b-wire _add-b-err)
     (call-rpc 'add_task "with due" (void) "2026-11-03" "09:30" "some notes"))
   (check-false _add-b-err)
   (check-equal? task-b-wire
                 (list 2 1 "工作" "with due" #f "2026-11-03" "09:30"
                       "some notes" (list-ref task-b-wire 8)))

   (define-values (snap-all _ls-err) (call-rpc 'load_snapshot "all" (void) #f))
   (check-equal? (list-ref snap-all 0) (list 0 1 2 0)
                 "counts: today/planned/all/completed; planned counts dated rows")
   ;; all-view orders incomplete tasks newest first.
   (check-equal? (map (lambda (t) (list-ref t 0)) (list-ref snap-all 2))
                 (list 2 1))

   (define-values (_bv-val bad-view-err)
     (call-rpc 'load_snapshot "bogus" (void) #f))
   (check-true (and (string? bad-view-err)
                    (string-contains? bad-view-err "Unknown task view")))

   (define-values (snap-planned _lp-err)
     (call-rpc 'load_snapshot "planned" (void) #f))
   (check-equal? (map (lambda (t) (list-ref t 0)) (list-ref snap-planned 2))
                 (list 2)
                 "planned view keeps only dated tasks")

   ;; update_task takes a record back over the wire (wire->typed decode)
   ;; and returns the freshly persisted row.
   (define modified (list-set task-b-wire 3 "edited over the wire"))
   (define-values (upd-wire _ut-err) (call-rpc 'update_task modified))
   (check-false _ut-err)
   (check-equal? (list-ref upd-wire 3) "edited over the wire")
   (check-equal? (list-ref upd-wire 5) "2026-11-03")
   (check-equal? (list-ref upd-wire 7) "some notes")

   (define-values (renamed-wire _rt-err)
     (call-rpc 'update_task_text 2 "renamed over wire"))
   (check-equal? (list-ref renamed-wire 3) "renamed over wire")

   (define-values (done-wire _sc-err) (call-rpc 'set_completed 2 #t))
   (check-equal? (list-ref done-wire 4) #t)
   (define-values (snap-after-done _sa-err)
     (call-rpc 'load_snapshot "all" (void) #f))
   (check-equal? (list-ref snap-after-done 0) (list 0 0 1 1))
   (define-values (snap-completed _lc-err)
     (call-rpc 'load_snapshot "completed" (void) #f))
   (check-equal? (map (lambda (t) (list-ref t 0)) (list-ref snap-completed 2))
                 (list 2))
   (define-values (snap-open _lo-err)
     (call-rpc 'load_snapshot "all" (void) #t))
   (check-equal? (length (list-ref snap-open 2)) 2
                 "show-completed surfaces both rows")

   (define-values (hits _sh-err) (call-rpc 'search_tasks "wire"))
   (check-equal? (sort (map (lambda (t) (list-ref t 0)) hits) <)
                 (list 1 2)
                 "search matches across completed and open rows")
   (define-values (misses _sm-err) (call-rpc 'search_tasks "zzz-none"))
   (check-equal? misses '())

   ;; ---- list CRUD --------------------------------------------------------

   (define-values (side-list _cl-err)
     (call-rpc 'create_list "side" (void) (void)))
   (check-equal? side-list (list 2 "side" "📋" -16745729 0)
                 "unset icon/color fall back to the defaults")

   (define-values (side-task _as-err)
     (call-rpc 'add_task "in second list" 2 (void) (void) (void)))
   (check-equal? (list-ref side-task 1) 2)
   (check-equal? (list-ref side-task 2) "side")

   (define-values (renamed-list _ul-err)
     (call-rpc 'update_list (list-set side-list 1 "side-two")))
   (check-equal? (list-ref renamed-list 1) "side-two")
   (check-equal? (list-ref renamed-list 4) 1 "pending-count re-reads the db")

   (define-values (snap-list2 _lf-err) (call-rpc 'load_snapshot "all" 2 #f))
   (check-equal? (map (lambda (t) (list-ref t 0)) (list-ref snap-list2 2))
                 (list 3))

   (define-values (del-true _dt1-err) (call-rpc 'delete_task 3))
   (check-equal? del-true #t)
   (define-values (del-false _dt2-err) (call-rpc 'delete_task 3))
   (check-equal? del-false #f "a second delete of the same row is #f")
   (define-values (del-list _dl-err) (call-rpc 'delete_list 2))
   (check-equal? del-list #t)
   (define-values (del-list-miss _dlm-err) (call-rpc 'delete_list 99))
   (check-equal? del-list-miss #f)

   ;; ---- reminder decisions + native handoff acknowledgement --------------

   (define-values (_reminder-task _ra-err)
     (call-rpc 'add_task "wire reminder" (void) "2000-01-01" "00:00" (void)))
   (check-false _ra-err)
   (define-values (decisions _rd-err) (call-rpc 'reminder_decisions #f))
   (check-false _rd-err)
   (check-equal? (length decisions) 1)
   ;; ReminderDecision wire shape: [token kind count optional-task].
   (define decision (car decisions))
   (check-equal? (length decision) 4)
   (check-true (string? (list-ref decision 0)))
   (check-equal? (take (cdr decision) 2) (list "task" 1))
   (check-equal? (list-ref (list-ref decision 3) 3) "wire reminder")
   (define token (list-ref decision 0))
   (define-values (attempted _ar1-err)
     (call-rpc 'acknowledge_reminder token "attempted"))
   (check-equal? attempted #t)
   (define-values (delivered _ar2-err)
     (call-rpc 'acknowledge_reminder token "delivered"))
   (check-equal? delivered #t)
   (define-values (no-duplicate _rd2-err) (call-rpc 'reminder_decisions #f))
   (check-equal? no-duplicate '())
   (define-values (_bad-phase bad-phase-err)
     (call-rpc 'acknowledge_reminder token "retry"))
   (check-true (and (string? bad-phase-err)
                    (string-contains? bad-phase-err "Unknown reminder phase")))

   ;; ---- settings ----------------------------------------------------------

   (define-values (settings0 _gs-err) (call-rpc 'get_settings))
   ;; Settings wire shape: [language theme close-to-tray
   ;; last-selected-list-id database-path]; fresh config defaults.
   (check-equal? (length settings0) 5)
   (check-equal? (take settings0 4) (list "zh" "system" "1" 0))
   (check-true (string-prefix? (list-ref settings0 4) (path->string root)))

   (define-values (settings-dark _ss1-err)
     (call-rpc 'set_setting "theme" "dark"))
   (check-equal? (list-ref settings-dark 1) "dark")
   (define-values (_sv1 bad-value-err) (call-rpc 'set_setting "theme" "neon"))
   (check-true (and (string? bad-value-err)
                    (string-contains? bad-value-err "invalid value")))
   (define-values (_sk1 unknown-key-err)
     (call-rpc 'set_setting "no-such-key" "1"))
   (check-true (and (string? unknown-key-err)
                    (string-contains? unknown-key-err "unknown setting")))

   ;; Integer-as-string throttle key round-trips through the raw config.
   (define-values (_ss2 _th-err)
     (call-rpc 'set_setting "last-update-check" "1728460800"))
   (check-false _th-err)
   (define-values (throttle _gt-err)
     (call-rpc 'get_setting "last-update-check"))
   (check-equal? throttle "1728460800")
   (define-values (unset _gu-err) (call-rpc 'get_setting "never-set"))
   (check-equal? unset "" "unset keys read as the empty string")

   ;; ---- update surface, pinned offline ------------------------------------

   (define-values (check-wire _cu-err) (call-rpc 'check_updates))
   (check-false _cu-err)
   ;; UpdateCheck wire shape: [status error current-version available-version
   ;; build published-at installer size-bytes]. The unreachable local feed
   ;; surfaces the honest error record instead of raising.
   (check-equal? (length check-wire) 8)
   (check-equal? (list-ref check-wire 0) "error")
   (check-true (string-contains? (list-ref check-wire 1) "127.0.0.1"))
   (check-equal? (list-ref check-wire 2) app-version)
   (check-equal? (list-ref check-wire 3) (void))

   (define-values (state0 _us1-err) (call-rpc 'update_state))
   ;; UpdateState wire shape: [phase percent message downloaded-path
   ;; available-version].
   (check-equal? (length state0) 5)
   (check-equal? (list-ref state0 0) "error")
   (check-true (string-contains? (list-ref state0 2) "127.0.0.1"))

   ;; No candidate yet: start_download fails into the state machine, and
   ;; Void travels as (void).
   (define-values (dl-void _sd-err) (call-rpc 'start_download))
   (check-true (void? dl-void))
   (define-values (state1 _us2-err) (call-rpc 'update_state))
   (check-true (string-contains? (list-ref state1 2) "no update"))

   ;; ---- close + dispatch-level errors --------------------------------------

   (define-values (close-void _cd-err) (call-rpc 'close_database))
   (check-true (void? close-void))
   (define-values (_post-close post-close-err) (call-rpc 'load_snapshot "all" (void) #f))
   (check-true (and (string? post-close-err)
                    (string-contains? post-close-err "database is not open")))

   (define-values (_unk unknown-rpc-err) (call-rpc 'no_such_rpc "x"))
   (check-true (and (string? unknown-rpc-err)
                    (string-contains? unknown-rpc-err "unknown RPC")))
   (define-values (_arity arity-err) (call-rpc 'delete_task))
   (check-true (and (string? arity-err)
                    (string-contains? arity-err "expected 1 argument")))
   ;; A payload that is not [name args...] is rejected by the dispatcher.
   (set! next-id (add1 next-id))
   (write-frame (frame message:request next-id (encode-value '())) client-out)
   (flush-output client-out)
   (let loop ()
     (define f (read-frame/timeout "payload-shape error"))
     (unless (= (frame-type f) message:error) (loop))
     (check-true (string-contains? (decode-value (frame-payload f))
                                   "invalid RPC request payload shape"))))
 (lambda ()
   (kill-thread srv)
   (delete-directory/files root)))
