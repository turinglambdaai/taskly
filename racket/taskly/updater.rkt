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
         ;; rivet/distribution centralized the release-target vocabulary
         ;; (platform-symbol, architecture-symbol, installer-extension);
         ;; taskly keeps its own leaf copies — version.rkt must load without
         ;; the update machinery, and the local installer-extension maps the
         ;; portable update payload, not the installer taxonomy. An explicit
         ;; whitelist compiles against both the current pin and rivet main;
         ;; revisit the overlap when the pin advances past that change.
         (only-in rivet/distribution
                  fetch-update-manifest
                  select-update
                  download-update
                  verify-update-artifact!
                  update-artifact
                  update-artifact-installer
                  update-artifact-size
                  update-artifact-url
                  update-candidate
                  update-candidate-artifact
                  update-candidate-manifest
                  update-manifest
                  update-manifest-version
                  update-manifest-build
                  update-manifest-published-at
                  updater-config
                  updater-config-maximum-download-bytes
                  base64-string->bytes
                  sha256-file/hex)
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         "config.rkt"
         "paths.rkt"
         "version.rkt")

(provide (all-from-out "version.rkt")
         update-key-id
         update-public-key-b64
         default-update-base-url
         current-update-base-url
         installer-extension
         manifest-url
         destination-path
         appimage-asset-name
         copy-with-progress!
         update-state-snapshot
         reset-update-state!
         set-update-error!
         set-update-candidate!
         update-worker-thread
         cancel-download!
         perform-check!
         update-install-kind
         start-download!
         rollout-bucket)

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
  "https://github.com/turlamai/taskly/releases/latest/download")

(define current-update-base-url (make-parameter #f))

(define maximum-download-bytes (* 800 1024 1024))

;; ---------- public key ----------

(define (embedded-public-key)
  (datum->pk-key (base64-string->bytes update-public-key-b64)
                 'SubjectPublicKeyInfo))

;; ---------- platform identity ----------

;; platform-symbol / architecture-symbol live in version.rkt (the CLI's
;; `version` command reports identity without loading this module's
;; crypto/rivet dependencies; they are re-provided above).

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
(define cancel-requested-box (box #f))

;; Test seams: install a checked candidate without a live network check,
;; and reach the running worker so a test can break it the way the
;; watchdog does and observe the cleanup arm deterministically.
(define (set-update-candidate! candidate)
  (set-box! candidate-box candidate))

(define (update-worker-thread)
  (unbox worker-thread-box))

(define (cancel-download!)
  (define worker (unbox worker-thread-box))
  (cond
    [(and worker (thread-running? worker))
     (set-box! cancel-requested-box #t)
     (break-thread worker)
     ;; Wait for termination before publishing idle. A very early cancel can
     ;; land before the worker enters its with-handlers body, so the caller
     ;; owns the final state normalization instead of relying solely on the
     ;; worker cleanup arm.
     (sync (thread-dead-evt worker))
     (set-box! worker-thread-box #f)
     (state-set! 'phase "idle")
     (state-set! 'percent 0)
     (state-set! 'message #f)
     (state-set! 'downloadedPath #f)
     (set-box! cancel-requested-box #f)
     #t]
    [else #f]))

;; Download watchdog bounds. The copy loop waits on read-bytes-avail! with
;; no timeout, so a connection that stalls without RST/FIN parks the worker
;; thread forever — visibly "stuck at 100%" (all bytes had arrived; the
;; loop was still waiting for EOF). Two finite bounds keep the phase
;; machine honest: no byte progress for the stall limit, or wall clock
;; past the total limit, breaks the worker (it cleans up the .partial and
;; reports phase=error itself) so the host always gets a terminal state.
(define download-stall-limit-seconds 120)
(define download-total-limit-seconds (* 30 60))
(define last-progress-seconds (box 0))

(define (state-set! key value)
  (set-box! update-state (hash-set (unbox update-state) key value)))

(define (update-state-snapshot)
  (unbox update-state))

(define (reset-update-state!)
  (set-box! candidate-box #f)
  (set-box! cancel-requested-box #f)
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
                      maximum-download-bytes
                      ;; rivet #271: component #f = the plain whole-app
                      ;; artifact (legacy manifests carry no component).
                      #f))
    (define kind (update-install-kind))
    (define candidate
      (if kind
          (select-update config manifest #:install-kind kind)
          (select-update config manifest)))
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
               'sizeBytes (update-artifact-size artifact)
               ;; Not part of the RPC record — `check-update` (CLI) reads it
               ;; so an agent gets the pinned download URL directly.
               'url (update-artifact-url artifact))]
      [else
       (state-set! 'phase "idle")
       (state-set! 'availableVersion #f)
       (hasheq 'status "up-to-date" 'currentVersion app-version)])))

;; ---------- download ----------

(define (destination-path data-dir candidate [extension (installer-extension)])
  (define version
    (update-manifest-version (update-candidate-manifest candidate)))
  (build-path data-dir
              "updates"
              (string-append app-display-name "-" version extension)))

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
       ;; Every successful read feeds the watchdog's stall clock (not just
       ;; integer percent changes, so a slow link never false-trips it).
       (set-box! last-progress-seconds (current-seconds))
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

;; ---------- install flavor selection ----------
;; MSI and AppImage are first-class artifacts in the signed manifest. The
;; installed flavor selects the matching signed artifact during check-update,
;; so the bytes later executed/installed are covered by Ed25519 + SHA-256.

(define (install-flavor)
  (string-downcase (or (config-ref (read-config) "install-flavor") "zip")))

(define (msi-flavor?)
  (and (eq? (platform-symbol) 'windows)
       (equal? (install-flavor) "msi")))

;; AppImage downloads land next to the running image (same filesystem →
;; atomic rename), verify against the signed manifest, then replace $APPIMAGE;
;; the host re-execs the replaced image on consent.

(define (appimage-flavor?)
  (and (eq? (platform-symbol) 'linux)
       (equal? (install-flavor) "appimage")))

(define (update-install-kind)
  (cond
    [(msi-flavor?) 'msi]
    [(appimage-flavor?) 'appimage]
    [else #f]))

;; Pure so tests can pin the derivation — the arch-name mapping is the trap.
(define (appimage-asset-name tar-gz-filename architecture)
  (unless (string-suffix? tar-gz-filename ".tar.gz")
    (error 'appimage-asset-name "not a tar.gz filename: ~a" tar-gz-filename))
  (define stem
    (substring tar-gz-filename 0 (- (string-length tar-gz-filename) 7)))
  (define feed-arch (string-append "-" (symbol->string architecture)))
  (unless (string-suffix? stem feed-arch)
    (error 'appimage-asset-name
           "feed filename does not end in ~a: ~a" feed-arch stem))
  (define appimage-arch
    (case architecture [(arm64) "aarch64"] [else "x86_64"]))
  (string-append (substring stem 0 (- (string-length stem)
                                      (string-length feed-arch)))
                 "-"
                 appimage-arch
                 ".AppImage"))

(define (appimage-artifact-urls candidate)
  (define url (update-artifact-url (update-candidate-artifact candidate)))
  (define filename
    (last (string-split (car (string-split url "?")) "/")))
  (define appimage-name
    (appimage-asset-name filename (architecture-symbol)))
  (values (string-replace url filename appimage-name)
          (string-append (string-replace url filename appimage-name)
                         ".sha256")))

(define (appimage-download-target)
  ;; $APPIMAGE (set by the AppImage runtime) points at the running image;
  ;; stage the download next to it so the final rename stays on one device.
  (define self (getenv "APPIMAGE"))
  (unless (and self (non-empty-string? self))
    (error 'start-download "APPIMAGE is not set; not running as an AppImage"))
  (values self
          (make-temporary-file "taskly-update-~a.AppImage"
                               #f
                               (path-only self))))

(define (download-appimage-with-progress! config candidate)
  (define-values (self temporary) (appimage-download-target))
  (with-handlers ([(lambda (e) (or (exn:fail? e) (exn:break? e)))
                   (lambda (e)
                     (when (file-exists? temporary)
                       (delete-file temporary))
                     (raise e))])
    (define artifact (update-candidate-artifact candidate))
    (define total (update-artifact-size artifact))
    (when (> total (updater-config-maximum-download-bytes config))
      (error 'download-update "signed artifact size exceeds the download limit"))
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
    (verify-update-artifact! candidate temporary)
    (unless (eq? (system-type 'os) 'windows)
      (file-or-directory-permissions temporary #o755))
    (rename-file-or-directory temporary self #t)
    self))

;; Runs on a backend worker thread; the host follows progress via the
;; update-state RPC. Never raises: failures surface through the phase.
(define (start-download! data-dir)
  (define worker (unbox worker-thread-box))
  (when (and worker (thread-running? worker))
    (error 'start-download! "an update download is already running"))
  (define candidate (unbox candidate-box))
  (unless candidate
    (error 'start-download! "no update is available; run a check first"))
  (set-box! cancel-requested-box #f)
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
                    maximum-download-bytes
                    ;; rivet #271: component #f = the plain whole-app
                    ;; artifact (legacy manifests carry no component).
                    #f))
  (define destination
    (cond
      [(msi-flavor?) (destination-path data-dir candidate ".msi")]
      [else (destination-path data-dir candidate)]))
  (set-box! last-progress-seconds (current-seconds))
  (define worker-thread
    (thread
     (lambda ()
       ;; The watchdog breaks a stalled worker; exn:break is not an
       ;; exn:fail, so it needs its own arm — either way the .partial
       ;; file is removed and the phase lands on error (never
       ;; mid-flight). The download handlers only catch exn:fail, so the
       ;; break arm cleans the .partial here (same shape as the
       ;; pre-clean in download-with-progress!) or a stalled download
       ;; would orphan a half-written file.
       (with-handlers
           ([(lambda (e) (or (exn:fail? e) (exn:break? e)))
             (lambda (e)
               (define temporary
                 (path-add-extension destination #".partial"))
               (when (file-exists? temporary) (delete-file temporary))
               (define cancelled?
                 (and (exn:break? e) (unbox cancel-requested-box)))
               (if cancelled?
                   (begin
                     (state-set! 'phase "idle")
                     (state-set! 'percent 0)
                     (state-set! 'message #f)
                     (state-set! 'downloadedPath #f))
                   (begin
                     (state-set! 'phase "error")
                     (state-set! 'message
                                 (if (exn:break? e)
                                     "update download stalled or timed out"
                                     (exn-message e)))))
               (set-box! cancel-requested-box #f))])
         (define path
           (cond
             [(appimage-flavor?)
              (download-appimage-with-progress! config candidate)]
             [else
              (download-with-progress! config candidate destination)]))
         (state-set! 'phase "downloaded")
         (state-set! 'percent 100)
         (state-set! 'downloadedPath (path->string path))))))
  (set-box! worker-thread-box worker-thread)
  ;; Watchdog: exits once the worker finishes on its own; otherwise a stall
  ;; (no byte progress) or the total wall-clock limit breaks the worker so
  ;; phase never rests on "downloading" indefinitely.
  (define download-started (current-seconds))
  (thread
   (lambda ()
     (let loop ()
       (cond
         [(sync/timeout download-stall-limit-seconds
                        (thread-dead-evt worker-thread))
          (void)]
         [(> (- (current-seconds) (unbox last-progress-seconds))
             download-stall-limit-seconds)
          (break-thread worker-thread)]
         [(> (- (current-seconds) download-started)
             download-total-limit-seconds)
          (break-thread worker-thread)]
         [else (loop)]))))
  (void))
