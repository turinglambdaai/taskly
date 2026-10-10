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
         racket/list
         racket/path
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
         appimage-asset-name
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
(define app-version "0.1.2")
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

;; ---------- MSI flavor (Windows installs under Program Files) ----------
;; The feed's windows entry is the portable zip; MSI installs update through
;; the sibling .msi release asset: same asset base with .zip → .msi, and the
;; checksum comes from the published .msi.sha256 sidecar. (The Ed25519
;; manifest still authenticates the zip entry that carried the version; the
;; sidecar is a plain checksum fetched over the same HTTPS origin.)

(define (install-flavor)
  (string-downcase (or (config-ref (read-config) "install-flavor") "zip")))

(define (msi-flavor?)
  (and (eq? (platform-symbol) 'windows)
       (equal? (install-flavor) "msi")))

;; ---------- AppImage flavor (Linux installs run from an AppImage) ----------
;; The feed's linux entry is the tar.gz; AppImage installs update through the
;; sibling .AppImage release asset. Asset families disagree on arch names —
;; feed/deb/rpm use x64|arm64, AppImage builds use x86_64|aarch64 — so the
;; derivation maps the arch before appending. The download lands NEXT TO the
;; running image (same filesystem → atomic rename) and replaces it after the
;; sidecar checksum verifies; the host re-execs the replaced image on consent.

(define (appimage-flavor?)
  (and (eq? (platform-symbol) 'linux)
       (equal? (install-flavor) "appimage")))

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

(define (download-appimage-with-progress! candidate)
  (define-values (appimage-url sidecar-url)
    (appimage-artifact-urls candidate))
  (define-values (self temporary) (appimage-download-target))
  (define expected (fetch-sidecar-sha256! sidecar-url))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (when (file-exists? temporary)
                       (delete-file temporary))
                     (raise e))])
    (define-values (in total) (open-download-with-total! appimage-url))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file temporary
          #:exists 'truncate/replace
          #:mode 'binary
          (lambda (out) (copy-with-progress! in out total))))
      (lambda () (close-input-port in)))
    (define actual (string-downcase (sha256-file/hex temporary)))
    (unless (string=? actual expected)
      (raise-arguments-error 'start-download
                             "downloaded appimage does not match its checksum sidecar"
                             "expected" expected
                             "actual" actual))
    ;; The replaced image must stay executable: rename carries the temp
    ;; file's modes, so set them explicitly before the swap.
    (file-or-directory-permissions
     temporary
     #(user-read user-write user-execute
                 group-read group-execute
                 other-read other-execute))
    (rename-file-or-directory temporary self #t)
    self))

(define (msi-artifact-urls candidate)
  (define url (update-artifact-url (update-candidate-artifact candidate)))
  (unless (string-suffix? url ".zip")
    (error 'start-download "cannot derive an msi url from a non-zip feed entry"))
  (define stem (substring url 0 (- (string-length url) 4)))
  (values (string-append stem ".msi")
          (string-append stem ".msi.sha256")))

(define (fetch-sidecar-sha256! url)
  ;; sha256sum format: "<hex>  <filename>"; the first token is the digest.
  (define in (get-pure-port (string->url url)
                            '("User-Agent: Taskly-Updater/1")
                            #:redirections 10))
  (dynamic-wind
    void
    (lambda ()
      (define digest
        (let ([body (string-trim (port->string in))])
          (if (string=? body "") "" (first (string-split body)))))
      (unless (regexp-match? #px"^[0-9a-fA-F]{64}$" digest)
        (error 'start-download "msi checksum sidecar has an unexpected shape"))
      (string-downcase digest))
    (lambda () (close-input-port in))))

;; MSI downloads come from the same CDN without a signed manifest, so the
;; response head is the only total available: open an impure port, parse
;; Content-Length for the progress percent (0 → indeterminate), and hand the
;; body port to the same copy loop. Connection: close keeps the copy ending
;; at EOF, exactly like the zip flow.
(define (open-download-with-total! url)
  ;; Shared by the msi and appimage flows: parse the response head so the
  ;; progress percent can use Content-Length (0 → indeterminate), then hand
  ;; the body port to the copy loop. Connection: close makes the copy end at
  ;; EOF like the manifest-verified zip flow.
  (define in (get-impure-port (string->url url)
                              '("User-Agent: Taskly-Updater/1"
                                "Connection: close")))
  (let loop ([total 0])
    (define line (read-line in 'return-linefeed))
    (cond
      [(eof-object? line) (values in 0)]
      [(non-empty-string? (string-trim line))
       (define match
         (regexp-match #px"(?i:^content-length:\\s*(\\d+))" line))
       (loop (if match (string->number (second match)) total))]
      [else (values in total)])))

(define (download-msi-with-progress! config candidate destination)
  (define-values (msi-url sidecar-url) (msi-artifact-urls candidate))
  (define expected (fetch-sidecar-sha256! sidecar-url))
  (make-parent-directory* destination)
  (define temporary (path-add-extension destination #".partial"))
  (when (file-exists? temporary) (delete-file temporary))
  (with-handlers ([exn:fail?
                   (lambda (e)
                     (when (file-exists? temporary) (delete-file temporary))
                     (raise e))])
    (define-values (in total) (open-download-with-total! msi-url))
    (dynamic-wind
      void
      (lambda ()
        (call-with-output-file temporary
          #:exists 'truncate/replace
          #:mode 'binary
          (lambda (out) (copy-with-progress! in out total))))
      (lambda () (close-input-port in)))
    (define actual (string-downcase (sha256-file/hex temporary)))
    (unless (string=? actual expected)
      (raise-arguments-error 'start-download
                             "downloaded msi does not match its checksum sidecar"
                             "expected" expected
                             "actual" actual))
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
  (define destination
    (cond
      [(msi-flavor?) (destination-path data-dir candidate ".msi")]
      [else (destination-path data-dir candidate)]))
  (set-box! last-progress-seconds (current-seconds))
  (define worker-thread
    (thread
     (lambda ()
       ;; The watchdog breaks a stalled worker; exn:break is not an
       ;; exn:fail, so it needs its own arm — either way the .partial file
       ;; is removed and the phase lands on error (never mid-flight).
       (with-handlers
           ([(lambda (e) (or (exn:fail? e) (exn:break? e)))
             (lambda (e)
               (state-set! 'phase "error")
               (state-set! 'message
                           (if (exn:break? e)
                               "update download stalled or timed out"
                               (exn-message e))))])
         (define path
           (cond
             [(msi-flavor?)
              (download-msi-with-progress! config candidate destination)]
             [(appimage-flavor?)
              (download-appimage-with-progress! candidate)]
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
