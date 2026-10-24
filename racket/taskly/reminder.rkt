#lang racket/base

(require racket/list
         racket/string
         "model.rkt")

(provide (struct-out reminder-decision)
         make-reminder-session
         reminder-session-decide!
         reminder-session-acknowledge!
         reminder-session-decision-phase)

;; Reminder selection is product policy, not notification-transport policy.
;; A session belongs to one opened database. Native hosts ask for decisions,
;; report the OS handoff lifecycle, and never reimplement eligibility,
;; startup summarization, or de-duplication.
(struct reminder-decision (token kind count task) #:transparent)
(struct reminder-session (notified phases next-token lock) #:mutable
  #:transparent)

(define (make-reminder-session)
  (reminder-session (make-hasheqv) (make-hash) 0 (make-semaphore 1)))

(define (task-due? task now-date now-time)
  (and (not (task-item-completed task))
       (let ([due-date (task-item-due-date task)])
         (and due-date
              (not (string=? due-date ""))
              (string<=? (string-append due-date " "
                                        (or (task-item-due-time task) "00:00"))
                         (string-append now-date " " now-time))))))

(define (next-token! session)
  (define next (add1 (reminder-session-next-token session)))
  (set-reminder-session-next-token! session next)
  (format "reminder-~a" next))

(define (register-decision! session kind count task)
  (define token (next-token! session))
  (hash-set! (reminder-session-phases session) token "emitted")
  (reminder-decision token kind count task))

(define (reminder-session-decide! session tasks startup?
                                  #:now-date now-date
                                  #:now-time now-time)
  (call-with-semaphore
   (reminder-session-lock session)
   (lambda ()
     (define due
       (for/list ([task (in-list tasks)]
                  #:when (and (task-due? task now-date now-time)
                              (not (hash-has-key?
                                    (reminder-session-notified session)
                                    (task-item-id task)))))
         task))
     ;; Emission is the de-duplication boundary. A crashed or rejected native
     ;; handoff may be retried after a fresh application/database session, but
     ;; never by a repeated wakeup in this session.
     (for ([task (in-list due)])
       (hash-set! (reminder-session-notified session) (task-item-id task) #t))
     (cond
       [(null? due) '()]
       [(and startup? (> (length due) 3))
        (list (register-decision! session "summary" (length due) #f))]
       [else
        (for/list ([task (in-list due)])
          (register-decision! session "task" 1 task))]))))

(define (valid-transition? current next)
  (or (string=? current next)
      (and (string=? current "emitted")
           (member next '("attempted" "failed")))
      (and (string=? current "attempted")
           (member next '("delivered" "failed")))))

(define (reminder-session-acknowledge! session token phase)
  (call-with-semaphore
   (reminder-session-lock session)
   (lambda ()
     (define current (hash-ref (reminder-session-phases session) token #f))
     (cond
       [(and current (valid-transition? current phase))
        (hash-set! (reminder-session-phases session) token phase)
        #t]
       [else #f]))))

(define (reminder-session-decision-phase session token)
  (call-with-semaphore
   (reminder-session-lock session)
   (lambda ()
     (hash-ref (reminder-session-phases session) token #f))))
