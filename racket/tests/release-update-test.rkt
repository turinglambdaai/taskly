#lang racket/base

;; Release-kind acceptance suite (#58 slice 1): the N→N+1 update lifecycle
;; with data preservation, driven end-to-end at the backend boundary every
;; host shares. Rivet's manifest fetch hard-requires HTTPS (the production
;; feed is HTTPS-only), so the suite splits in two: perform-check! proves a
;; plain-http feed can never yield a candidate, and the full lifecycle runs
;; the identical verify→select→download pipeline over a loopback feed
;; signed with a throwaway key. Host-side install arms (macOS zip swap,
;; Windows cmd/MSI handoff) are exercised by the release pipeline on every
;; tag; the backend-owned arm — the Linux AppImage in-place swap — runs
;; here for real. The invariant under everything: ~/.taskly/tasks.db stays
;; byte-identical and the seeded task survives.

(require crypto
         crypto/all
         racket/file
         racket/list
         racket/port
         racket/tcp
         rackunit
         (only-in rivet/distribution
                  write-signed-manifest
                  verify-signed-manifest
                  update-manifest
                  update-artifact
                  update-artifact-installer
                  update-candidate-manifest
                  update-candidate-artifact
                  update-candidate
                  updater-config
                  select-update
                  update-manifest-version
                  sha256-file/hex)
         racket/path
         net/url
         "../taskly/config.rkt"
         "../taskly/db.rkt"
         "../taskly/model.rkt"
         "../taskly/paths.rkt"
         "../taskly/updater.rkt")

(use-all-factories!)

;; Rivet exports the file-level hash (sha256-file/hex); route in-memory
;; artifact bytes through a scratch file so the suite compares digests
;; with the exact function the verifier uses.
(define (sha256-bytes/hex bytes)
  (define scratch (make-temporary-file "taskly-release-sha-~a"))
  (dynamic-wind
    (lambda ()
      (call-with-output-file scratch #:exists 'truncate
        (lambda (out) (write-bytes bytes out))))
    (lambda () (sha256-file/hex scratch))
    (lambda () (delete-file scratch))))

(define (wait-until ready? who [timeout-ms 15000])
  (let loop ([deadline (+ (current-inexact-milliseconds) timeout-ms)])
    (cond
      [(ready?) (void)]
      [(> (current-inexact-milliseconds) deadline)
       (fail (string-append "timed out waiting for " who))]
      [else (sleep 0.05) (loop deadline)])))

;; Loopback feed: reserve a port first (manifest URLs must embed it), then
;; serve an assoc list of (path-substring . bytes) over HTTP — the same
;; transport the artifact downloads already test against.
(define (open-loopback)
  (tcp-listen 0 16 #f))

(define (loopback-port listener)
  (cadr (call-with-values (lambda () (tcp-addresses listener #t)) list)))

(define (serve-on! listener routes)
  (thread
   (lambda ()
     (let accept ()
       (define-values (cin cout) (tcp-accept listener))
       (thread
        (lambda ()
          (with-handlers ([exn:fail? (lambda (_) (void))])
            (define request-line (read-line cin 'return-linefeed))
            (let drain ()
              (define line (read-line cin 'return-linefeed))
              (unless (or (eof-object? line) (equal? line "")) (drain)))
            (define text request-line) ; read-line already yields a string
            (define route
              (for/first ([pair (in-list routes)]
                          #:when (regexp-match? (regexp-quote (car pair)) text))
                pair))
            (cond
              [route
               (define body (cdr route))
               (display "HTTP/1.1 200 OK\r\n" cout)
               (display (format "Content-Length: ~a\r\n" (bytes-length body))
                        cout)
               (display "Connection: close\r\n\r\n" cout)
               (write-bytes body cout)]
              [else
               (display
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                cout)])
            (flush-output cout)
            ;; Closing the input half first would block on the peer's EOF
            ;; (close-input-port waits; the client waits for the response —
            ;; a deadlock). The output half-close is the EOF signal.
            (close-output-port cout))))
       (accept)))))

;; A throwaway Ed25519 identity: the private half signs the feed, the
;; public half plays the role the embedded production key plays live.
(define (test-signing-key)
  (define priv (generate-private-key 'eddsa '((curve ed25519))))
  (values priv
          (datum->pk-key (pk-key->datum priv 'rkt-public) 'rkt-public)))

(define (wrapped-feed manifest priv)
  (define wrapped (open-output-bytes))
  (write-signed-manifest manifest priv "taskly-test" wrapped)
  (get-output-bytes wrapped))

;; A check config pinned one version behind the feed, matching the current
;; platform so select-update sees a realistic offer.
(define (check-config key version)
  (updater-config app-identifier version 'stable
                  (platform-symbol) (architecture-symbol)
                  key "taskly-test" 0 (* 100 1024 1024) #f))

(define (zip-artifact url bytes)
  (update-artifact (platform-symbol) (architecture-symbol)
                   url (sha256-bytes/hex bytes)
                   (bytes-length bytes) 'zip '()
                   ;; rivet #271: component #f = the plain whole-app artifact.
                   #f))

;; A user profile with a real database (the seeded default list plus one
;; task) — the thing an update must never touch.
(define (seeded-home)
  (define home (make-temporary-file "taskly-release-home-~a" 'directory))
  (define db (open-taskly-db (build-path home ".taskly" "tasks.db")))
  (define default-list (car (db-lists db)))
  (db-add-task! db (task-item 0 (todo-list-id default-list)
                              "OTA survival probe" #f #f #f
                              "2026-10-23T00:00:00" #f #f))
  (close-taskly-db db)
  home)

(define (database-sha home)
  (sha256-file/hex (build-path home ".taskly" "tasks.db")))

(define (task-survives? home)
  (define db (open-taskly-db (build-path home ".taskly" "tasks.db")))
  (define survived?
    (ormap (lambda (t) (equal? (task-item-text t) "OTA survival probe"))
           (db-tasks db)))
  (close-taskly-db db)
  survived?)

(test-case "a plain-http feed can never yield a candidate"
  ;; fetch-update-manifest is HTTPS-only by contract; a loopback http feed
  ;; must land in the error phase with no offer — the transport gate is
  ;; part of the release chain, not a nicety.
  (define-values (priv _pub) (test-signing-key))
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact "https://dl.example/taskly-9.9.9.zip"
                                         (make-bytes 64 1)))))
  (define listener (open-loopback))
  (define server-thread
    (serve-on! listener
               (list (cons "update-manifest.json"
                           (wrapped-feed manifest priv)))))
  (parameterize ([current-update-base-url
                  (format "http://127.0.0.1:~a" (loopback-port listener))]
                 [current-taskly-home
                  (make-temporary-file "taskly-release-http-~a" 'directory)])
    (reset-update-state!)
    (define result (perform-check!))
    (check-equal? (hash-ref result 'status) "error")
    (check-equal? (hash-ref (update-state-snapshot) 'phase) "error")
    (check-false (hash-ref (update-state-snapshot) 'availableVersion)))
  (kill-thread server-thread)
  (tcp-close listener))

(test-case "a re-keyed or re-signed feed fails closed"
  (define-values (priv-a pub-a) (test-signing-key))
  (define-values (priv-b pub-b) (test-signing-key))
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact "https://dl.example/taskly-9.9.9.zip"
                                         (make-bytes 8 2)))))
  ;; The exact bytes, under their own key-id: the happy path every client
  ;; runs against the production feed.
  (check-not-exn
   (lambda ()
     (verify-signed-manifest (open-input-bytes (wrapped-feed manifest priv-a))
                             pub-a
                             #:key-id "taskly-test")))
  ;; A different key-id must fail closed (the shipped clients pin ours).
  (check-exn exn:fail?
             (lambda ()
               (verify-signed-manifest
                (open-input-bytes (wrapped-feed manifest priv-a))
                pub-a
                #:key-id "some-other-key")))
  ;; The same key-id under a different trusted key (a re-signed feed from
  ;; a key rotation the client never adopted) must also fail closed.
  (check-exn exn:fail?
             (lambda ()
               (verify-signed-manifest
                (open-input-bytes (wrapped-feed manifest priv-b))
                pub-a
                #:key-id "taskly-test"))))

(test-case "rollout 0 gates the offer for every bucket"
  (define-values (priv pub) (test-signing-key))
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 0
                     (list (zip-artifact "https://dl.example/taskly-9.9.9.zip"
                                         (make-bytes 8 3)))))
  (check-false (select-update (check-config pub "0.2.3") manifest)))

(test-case "the N→N+1 lifecycle preserves the database byte for byte"
  (define home (seeded-home))
  (define db-sha (database-sha home))
  (define artifact-bytes (make-bytes 4096 7))
  (define-values (priv pub) (test-signing-key))
  (define listener (open-loopback))
  (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
  ;; The feed offers 0.2.4; a 0.2.2 feed exists only to prove the semver
  ;; gate refuses downgrades of 0.2.3.
  ;; The signed envelope carries https URLs — the sign/parse layers
  ;; reject anything else (transport gate) — and selection never fetches.
  (define manifest
    (update-manifest app-identifier "0.2.4" 8 'stable
                     "2026-10-23T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "https://dl.example/taskly-0.2.4-x64.zip"
                            artifact-bytes))))
  (define downgrade
    (update-manifest app-identifier "0.2.2" 6 'stable
                     "2026-10-01T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "http://127.0.0.1:1/taskly-0.2.2-x64.zip"
                            artifact-bytes))))
  (check-false (select-update (check-config pub "0.2.3") downgrade)
               "a downgrade offer violates the semver gate")
  (define server-thread
    (serve-on! listener
               (list (cons "update-manifest.json" (wrapped-feed manifest priv))
                     (cons "taskly-0.2.4-x64.zip" artifact-bytes))))
  (parameterize ([current-taskly-home home])
    (reset-update-state!)
    ;; Fetch + verify + select over the loopback feed — the same pipeline
    ;; steps perform-check! runs against the production feed and key.
    (define in
      (get-pure-port (string->url (string-append base "/update-manifest.json"))))
    (define envelope (port->bytes in))
    (close-input-port in)
    (define verified
      (verify-signed-manifest (open-input-bytes envelope) pub
                              #:key-id "taskly-test"))
    (check-equal? (update-manifest-version verified) "0.2.4")
    (define candidate (select-update (check-config pub "0.2.3") manifest))
    (check-true (and candidate #t) "0.2.3 must be offered the 0.2.4 update")
    (check-equal? (update-manifest-version
                   (update-candidate-manifest candidate))
                  "0.2.4")
    (check-equal? (update-artifact-installer
                   (update-candidate-artifact candidate))
                  'zip)
    ;; Download through the real worker, then the invariants. The signed
    ;; envelope carries https artifact URLs (the sign/parse layers reject
    ;; anything else, which is itself contract), so the download leg runs
    ;; on the same artifact re-targeted at the loopback server — the
    ;; transport rivet's own download tests use.
    (define loopback-artifact
      (zip-artifact (string-append base "/taskly-0.2.4-x64.zip")
                    artifact-bytes))
    (define download-candidate
      (update-candidate
       (struct-copy update-manifest manifest
                    [artifacts (list loopback-artifact)])
       loopback-artifact))
    (set-update-candidate! download-candidate)
    (define data-dir (make-temporary-file "taskly-release-data-~a" 'directory))
    (start-download! data-dir)
    (wait-until (lambda ()
                  (equal? (hash-ref (update-state-snapshot) 'phase)
                          "downloaded"))
                "the downloaded phase")
    (define downloaded (hash-ref (update-state-snapshot) 'downloadedPath))
    (check-true (and downloaded (file-exists? downloaded)))
    (check-equal? (sha256-file/hex downloaded)
                  (sha256-bytes/hex artifact-bytes))
    (check-false
     (file-exists? (path-add-extension downloaded #".partial"))
     "the .partial must be renamed away, not left behind")
    (check-equal? (database-sha home) db-sha
                  "the update flow must not touch tasks.db")
    (check-true (task-survives? home) "the seeded task must survive")
    (reset-update-state!))
  (kill-thread server-thread)
  (tcp-close listener))

(test-case "a sha-mismatched artifact refuses to land"
  (define home (seeded-home))
  (define db-sha (database-sha home))
  (define-values (priv pub) (test-signing-key))
  (define listener (open-loopback))
  (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
  ;; The manifest vouches for zeros; the server sends nines — the size
  ;; matches, the hash cannot.
  (define manifest
    (update-manifest app-identifier "9.9.9" 7 'stable
                     "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                     (list (zip-artifact
                            "https://dl.example/taskly-9.9.9-x64.zip"
                            (make-bytes 512 0)))))
  (define server-thread
    (serve-on! listener
               (list (cons "update-manifest.json" (wrapped-feed manifest priv))
                     (cons "taskly-9.9.9-x64.zip" (make-bytes 512 9)))))
  (define candidate (select-update (check-config pub "0.2.3") manifest))
  (check-true (and candidate #t))
  (define loopback-artifact
    (zip-artifact (string-append base "/taskly-9.9.9-x64.zip")
                  (make-bytes 512 0)))
  (define download-candidate
    (update-candidate
     (struct-copy update-manifest manifest
                  [artifacts (list loopback-artifact)])
     loopback-artifact))
  (parameterize ([current-taskly-home home])
    (reset-update-state!)
    (set-update-candidate! download-candidate)
    (define data-dir (make-temporary-file "taskly-release-bad-~a" 'directory))
    (start-download! data-dir)
    (wait-until (lambda ()
                  (equal? (hash-ref (update-state-snapshot) 'phase) "error"))
                "the sha-mismatch error phase")
    (define destination
      (build-path data-dir "updates"
                  (string-append app-display-name "-9.9.9"
                                 (installer-extension))))
    (check-false (file-exists? destination)
                 "a rejected artifact must never reach the destination")
    (check-false
     (file-exists? (path-add-extension destination #".partial")))
    (check-equal? (database-sha home) db-sha)
    (check-true (task-survives? home))
    (reset-update-state!))
  (kill-thread server-thread)
  (tcp-close listener))

;; Backend-owned install arm: Linux only — the AppImage in-place swap.
(define run-appimage-swap-test?
  (eq? (system-type 'os) 'linux))

(when run-appimage-swap-test?
  (test-case "the AppImage swap replaces the running image and keeps the database"
    (define home (seeded-home))
    (define db-sha (database-sha home))
    (define running-image
      (make-temporary-file "taskly-release-self-~a.AppImage"))
    (call-with-output-file running-image
      #:exists 'truncate
      (lambda (out) (write-bytes (make-bytes 64 1) out)))
    (define new-image-bytes (make-bytes 2048 5))
    (define-values (priv pub) (test-signing-key))
    (define listener (open-loopback))
    (define base (format "http://127.0.0.1:~a" (loopback-port listener)))
    ;; The feed advertises the tar.gz artifact; the AppImage arm derives
    ;; the x86_64.AppImage asset name from it — that derivation is the trap.
    (define manifest
      (update-manifest app-identifier "9.9.9" 7 'stable
                       "2026-10-09T00:00:00Z" "0.0.0" #f #t 100
                       (list (update-artifact
                              'linux (architecture-symbol)
                              (string-append base
                                             "/taskly-9.9.9-linux-x64.tar.gz")
                              (sha256-bytes/hex new-image-bytes)
                              (bytes-length new-image-bytes)
                              'targz '() #f))))
    (define server-thread
      (serve-on! listener
                 (list (cons "update-manifest.json"
                             (wrapped-feed manifest priv))
                       (cons "taskly-9.9.9-linux-x86_64.AppImage"
                             new-image-bytes))))
    (define candidate
      (select-update (check-config pub "0.2.3") manifest
                     #:install-kind 'appimage))
    (check-true (and candidate #t)
                "the appimage install kind must select the feed artifact")
    (parameterize ([current-taskly-home home])
      (write-config! (hash-set (read-config) "install-flavor" "appimage"))
      (define had-appimage (getenv "APPIMAGE"))
      (putenv "APPIMAGE" (path->string running-image))
      (reset-update-state!)
      (set-update-candidate! candidate)
      (start-download!
       (make-temporary-file "taskly-release-appimage-data-~a" 'directory))
      (wait-until (lambda ()
                    (equal? (hash-ref (update-state-snapshot) 'phase)
                            "downloaded"))
                  "the appimage downloaded phase")
      (check-equal? (hash-ref (update-state-snapshot) 'downloadedPath)
                    (path->string running-image)
                    "the swap must replace the running image in place")
      (check-equal? (file->bytes running-image) new-image-bytes)
      (check-true
       (memq 'execute (file-or-directory-permissions running-image 'bits))
       "the replaced image must stay executable")
      (check-equal? (database-sha home) db-sha)
      (check-true (task-survives? home))
      (reset-update-state!)
      (if (and (string? had-appimage) (not (equal? had-appimage "")))
          (putenv "APPIMAGE" had-appimage)
          (putenv "APPIMAGE" "")))
    (kill-thread server-thread)
    (tcp-close listener)))
