#lang racket/base

(provide (struct-out todo-list)
         (struct-out task-item)
         default-list-name
         default-list-icon
         default-list-color)

;; Shared domain records. Optional persisted fields use #f in the Racket core;
;; adapters translate #f to the target transport/database null representation.
(struct todo-list (id name icon color pending-count) #:transparent)
(struct task-item (id list-id text due-date due-time completed created-at notes list-name) #:transparent)

(define default-list-name "工作")
(define default-list-icon "📋")
;; Signed ARGB 0xFF007AFF, matching DATA-FORMAT.md v4.
(define default-list-color -16745729)
