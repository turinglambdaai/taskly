#lang racket/base

(require racket/string
         "errors.rkt")

(provide max-task-text-length
         max-list-name-length
         max-search-keyword-length
         min-year
         max-year
         validate-task-text!
         validate-list-name!
         validate-search-keyword!)

(define max-task-text-length 1000)
(define max-list-name-length 100)
(define max-search-keyword-length 200)
(define min-year 1900)
(define max-year 2100)

(define (blank? value)
  (or (not (string? value))
      (string=? "" (string-trim value))))

(define (validate-task-text! text)
  (when (blank? text)
    (raise-taskly 'validation 2 "Please enter a task description."))
  (when (> (string-length text) max-task-text-length)
    (raise-taskly 'validation 2
                  (format "Task description must be ~a characters or fewer." max-task-text-length)))
  (string-trim text))

(define (validate-list-name! name)
  (when (blank? name)
    (raise-taskly 'validation 2 "Please enter a list name."))
  (when (> (string-length name) max-list-name-length)
    (raise-taskly 'validation 2
                  (format "List name must be ~a characters or fewer." max-list-name-length)))
  (string-trim name))

(define (validate-search-keyword! keyword)
  (unless (string? keyword)
    (raise-taskly 'validation 2 "Search keyword must be text."))
  (when (> (string-length keyword) max-search-keyword-length)
    (raise-taskly 'validation 2
                  (format "Search keyword must be ~a characters or fewer." max-search-keyword-length)))
  (string-trim keyword))
