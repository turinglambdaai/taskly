#lang racket/base

;; Online update support for Taskly, built on rivet/distribution — the
;; family pattern (payback/syncpilot): the backend verifies and downloads
;; the signed update artifact; the native host owns installation. A check
;; fetches and verifies the Ed25519-signed channel manifest; the artifact
;; download runs on a background thread with progress published to a state
;; box that the UI polls through the `update-state` RPC (RVT1 events are
;; thread-local, so a background thread cannot emit them directly).
;;
;; Taskly-specific rules (shared/spec/UPDATE.md): the 4-hour silent-check
;; throttle lives in the hosts via the last-update-check config key — this
;; module only persists the sticky rollout bucket. Downloads land under
;; <taskly-dir>/updates and tasks.db is never touched.

;; Note on crypto factories: rivet/distribution pins the provider set to
;; libcrypto at module load and deliberately avoids crypto/all — factory
;; FFIs load at import time and the gmp factory kills embedded runtimes on
;; hosts without libgmp. This module runs inside the embedded CS runtime,
;; so it must not require crypto/all either (tests may, they are headless).

(require crypto
         net/base64
         net/url
         rivet/distribution
         racket/file
         racket/port
         racket/string
         "config.rkt"
         "paths.rkt")

(provide app-version
         app-build
         app-identifier
         app-channel
         app-display-name
         update-key-id
         update-public-key-b64
         default-update-base-url
         current-update-base-url
         platform-symbol
         architecture-symbol
         installer-extension
         manifest-url
         destination-path
         copy-with-progress!
         update-state-snapshot
         reset-update-state!
         set-update-error!
         perform-check!
         start-download!
         rollout-bucket)

;; Release identity duplicated from rivet.rktd. The packaged app cannot
;; read the project file at runtime, so the updater embeds these constants.
;; scripts/check-release-version.sh re-checks app-version against VERSION.
(define app-version "1.4.0")
(define app-build 1)
(define app-identifier "app.taskly.Taskly")
(define app-channel 'stable)
(define app-display-name "Taskly")

(define update-key-id "taskly-2026-10")

;; SubjectPublicKeyInfo DER, base64 — the same keypair the macOS host
;; embeds in raw form (UpdateService.swift). The private half lives outside
;; the repository (Sync/Keys backup + the CI secret
;; UPDATE_ED25519_PRIVATE_KEY) and never ships. Rotate by shipping a build
;; that trusts the next key before signing releases exclusively with it.
(define update-public-key-b64
  "MCowBQYDK2VwAyEAlgCdBU0qFDNgamTJBIVX2jjPzehbTmCp3eV5ViubtF0=")

;; Where the updater looks for the signed manifest. The release pipeline
;; pins artifact URLs to the concrete tag; the manifest itself is always
;; fetched from the moving "latest" location. Tests parameterize this at
;; an unreachable local URL instead of touching the network.
(define default-update-base-url
  "https://github.com/turinglambdaai/taskly/releases/latest/download")

(define current-update-base-url (make-parameter #f))

(define maximum-download-bytes (* 800 1024 1024))

;; ---------- public key ----------

(define (embedded-public-key)
  (datum->pk-key (base64-string->bytes update-public-key-b64)
                 'SubjectPublicKeyInfo))

;; ---------- platform identity ----------

;; rivet release tooling emits these exact symbols into update manifests
(define (platform-symbol)
  (case (system-type 'os)
    [(macosx) 'macos]
    [(windows) 'windows]
    [else 'linux]))

(define (architecture-symbol)
  (case (system-type 'arch)
    [(aarch64 arm64) 'arm64]
    [else 'x64]))

(define (installer-extension)
  (case (system-type 'os)
    [(macosx) ".zip"]
    [(windows) ".zip"]
    [else ".tar.gz"]))

(define (manifest-url)
  (string-append
   (string-trim (or (current-update-base-url) default-update-base-url)
                "/" #:right? #t)
   "/update-manifest.json"))

;; ---------- shared update state (UI-visible) ----------

;; phase: idle | checking | downloading | downloaded | error
(define update-state
  (box (hasheq 'phase "idle"
               'percent 0
               'message #f
               'downloadedPath #f
               'availableVersion #f)))

(define candidate-box (box #f))
(define worker-thread-box (box #f))

(define (state-set! key value)
  (set-box! update-state (hash-set (unbox update-state) key value)))

(define (update-state-snapshot)
  (unbox update-state))

(define (reset-update-state!)
  (set-box! candidate-box #f)
  (set-box! update-state
            (hasheq 'phase "idle"
                    'percent 0
                    'message #f
                    'downloadedPath #f
                    'availableVersion #f)))

;; Pre-spawn download failures (already running, no candidate) surface
;; through the state instead of an RPC error, so host UIs have a single
;; failure channel.
(define (set-update-error! message)
  (state-set! 'phase "error")
  (state-set! 'message message))

;; ---------- rollout bucket ----------

;; Stable random 0..99 assigned on first check so staged rollouts are
;; sticky per installation. Persisted as an integer-as-string config key
;; (DATA-FORMAT §7); crypto-random-bytes, not `random`: racket/base's PRNG
;; has a fixed seed, which would put every fresh install in the same
;; lockstep bucket.
(define (rollout-bucket)
  (define existing (config-ref (read-config) "rollout-bucket" #f))
  (define parsed (and existing (string->number existing)))
  (if (and parsed (exact-integer? parsed) (<= 0 parsed 99))
      parsed
      (let ([bucket
             (modulo (integer-bytes->integer (crypto-random-bytes 4) #t #t)
                     100)])
        (define config (read-config))
        (hash-set! config "rollout-bucket" (number->string bucket))
        (write-config! config)
        bucket)))

;; ---------- check ----------

;; Returns a plain hasheq describing the outcome; the backend maps it onto
;; the typed UpdateCheck record. Throttling is the host's job (UPDATE.md).
(define (perform-check!)
  (reset-update-state!)
  (state-set! 'phase "checking")
  (with-handlers
      ([exn:fail?
        (lambda (e)
          (state-set! 'phase "error")
          (state-set! 'message (exn-message e))
          (hasheq 'status "error" 'message (exn-message e)))])
    (define manifest
      (fetch-update-manifest (manifest-url)
                             (embedded-public-key)
                             #:key-id update-key-id))
    (define config
      (updater-config app-identifier
                      app-version
                      app-channel
                      (platform-symbol)
                      (architecture-symbol)
                      (embedded-public-key)
                      update-key-id
                      (rollout-bucket)
                      maximum-download-bytes))
    (define candidate (select-update config manifest))
    (cond
      [candidate
       (set-box! candidate-box candidate)
       (define artifact (update-candidate-artifact candidate))
       (state-set! 'phase "idle")
       (state-set! 'availableVersion
                   (update-manifest-version
                    (update-candidate-manifest candidate)))
       (hasheq 'status "available"
               'currentVersion app-version
               'availableVersion
               (update-manifest-version
                (update-candidate-manifest candidate))
               'build (update-manifest-build
                       (update-candidate-manifest candidate))
               'publishedAt
               (update-manifest-published-at
                (update-candidate-manifest candidate))
               'installer (symbol->string (update-artifact-installer artifact))
               'sizeBytes (update-artifact-size artifact))]
      [else
       (state-set! 'phase "idle")
       (state-set! 'availableVersion #f)
       (hasheq 'status "up-to-date" 'currentVersion app-version)])))

;; ---------- download ----------

(define (destination-path data-dir candidate)
  (define version
    (update-manifest-version (update-candidate-manifest candidate)))
  (build-path data-dir
              "updates"
              (string-append app-display-name "-" version
                             (installer-extension))))

;; Copy with progress; same limits as rivet's download-update but publishes
;; integer percent changes to the state box while streaming. Release asset
;; URLs redirect to the CDN, so follow redirections like rivet's own
;; downloader does (the 302-into-an-empty-body trap, rivet#153).
(define (copy-with-progress! in out total)
  (define buffer (make-bytes 65536))
  (let loop ([done 0] [last-percent -1])
    (define count (read-bytes-avail! buffer in))
    (cond
      [(eof-object? count) done]
      [else
       (write-bytes buffer out 0 count)
       (define next (+ done count))
       (define percent
         (if (> total 0)
             (min 100 (quotient (* next 100) total))
             0))
       (when (> percent last-percent)
         (state-set! 'percent percent))
       (loop next percent)])))

(define (download-with-progress! config candidate destination)
  (define artifact (update-candidate-artifact candidate))
  (define total (update-artifact-size artifact))
  (when (> total (updater-config-maximum-download-bytes config))
    (error 'download-update "signed artifact size exceeds the download limit"))
  (make-parent-directory* destination)
  (define temporary (path-add-extension destination #".partial"))
  (when (file-exists? temporary) (delete-file temporary))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (when (file-exists? temporary) (delete-file temporary))
                     (raise e))])
    (define in
      (get-pure-port (string->url (update-artifact-url artifact))
                     '("User-Agent: Taskly-Updater/1")
                     #:redirections 10))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file temporary
          #:exists 'truncate/replace
          #:mode 'binary
          (lambda (out) (copy-with-progress! in out total))))
      (lambda () (close-input-port in)))
    ;; size + SHA-256 against the signed manifest before the file is trusted
    (verify-update-artifact! candidate temporary)
    (rename-file-or-directory temporary destination #t)
    destination))

;; Runs on a backend worker thread; the host follows progress via the
;; update-state RPC. Never raises: failures surface through the phase.
(define (start-download! data-dir)
  (define worker (unbox worker-thread-box))
  (when (and worker (thread-running? worker))
    (error 'start-download! "an update download is already running"))
  (define candidate (unbox candidate-box))
  (unless candidate
    (error 'start-download! "no update is available; run a check first"))
  (state-set! 'phase "downloading")
  (state-set! 'percent 0)
  (state-set! 'message #f)
  (define config
    (updater-config app-identifier
                    app-version
                    app-channel
                    (platform-symbol)
                    (architecture-symbol)
                    (embedded-public-key)
                    update-key-id
                    (rollout-bucket)
                    maximum-download-bytes))
  (define destination (destination-path data-dir candidate))
  (set-box! worker-thread-box
            (thread
             (lambda ()
               (with-handlers
                   ([exn:fail?
                     (lambda (e)
                       (state-set! 'phase "error")
                       (state-set! 'message (exn-message e)))])
                 (define path
                   (download-with-progress! config candidate destination))
                 (state-set! 'phase "downloaded")
                 (state-set! 'percent 100)
                 (state-set! 'downloadedPath (path->string path)))))))
