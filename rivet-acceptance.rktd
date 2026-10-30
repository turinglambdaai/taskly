#hasheq(
 (version . 1)
 (requirements
  . (#hasheq((kind . contract) (platforms . (windows macos linux)))
     #hasheq((kind . bridge) (platforms . (windows macos linux)))
     #hasheq((kind . native-build) (platforms . (windows macos linux)))
     #hasheq((kind . package) (platforms . (windows macos linux)))
     #hasheq((kind . native-ui) (platforms . (windows macos linux)))
     #hasheq((kind . release) (platforms . (windows macos linux)))))
 (suites
  . (#hasheq((id . core-contract)
             (kind . contract)
             (platforms . (windows macos linux))
             (command . ("raco" "test"
                         "racket/tests/backend-test.rkt"
                         "racket/tests/cli-update-test.rkt"
                         "racket/tests/core-test.rkt"
                         "racket/tests/rivet-schema-test.rkt"
                         "racket/tests/updater-test.rkt"))
             (timeout-seconds . 600))
     #hasheq((id . embedded-wire)
             (kind . bridge)
             (platforms . (windows macos linux))
             (command . ("raco" "test" "racket/tests/backend-wire-test.rkt"))
             (timeout-seconds . 300))
     #hasheq((id . native-host)
             (kind . native-build)
             (platforms . (windows macos linux))
             (command . ("raco" "rivet" "build"))
             (timeout-seconds . 1800))
     #hasheq((id . windows-package)
             (kind . package)
             (platforms . (windows))
             (command . ("racket" "scripts/acceptance/package.rkt"))
             (timeout-seconds . 1800)
             (evidence . (".rivet/acceptance/windows/package.json")))
     #hasheq((id . macos-package)
             (kind . package)
             (platforms . (macos))
             (command . ("racket" "scripts/acceptance/package.rkt"))
             (timeout-seconds . 1800)
             (evidence . (".rivet/acceptance/macos/package.json")))
     #hasheq((id . linux-package)
             (kind . package)
             (platforms . (linux))
             (command . ("racket" "scripts/acceptance/package.rkt"))
             (timeout-seconds . 1800)
             (evidence . (".rivet/acceptance/linux/package.json")))
     #hasheq((id . windows-native-ui)
             (kind . native-ui)
             (platforms . (windows))
             (command . ("pwsh" "-NoProfile" "-File"
                         "scripts/e2e/e2e-windows.ps1"))
             (timeout-seconds . 600)
             (evidence . (".rivet/acceptance/windows/interaction-trace.json"
                          ".rivet/acceptance/windows/persistence-restart.json"
                          ".rivet/acceptance/windows/install-lifecycle.json")))
     #hasheq((id . macos-native-ui)
             (kind . native-ui)
             (platforms . (macos))
             (command . ("bash" "scripts/e2e/e2e-macos.sh"))
             (timeout-seconds . 600)
             (evidence . (".rivet/acceptance/macos/interaction-trace.json"
                          ".rivet/acceptance/macos/persistence-restart.json"
                          ".rivet/acceptance/macos/install-lifecycle.json")))
     #hasheq((id . linux-native-ui)
             (kind . native-ui)
             (platforms . (linux))
             (command . ("bash" "scripts/e2e/e2e-linux.sh"))
             (timeout-seconds . 600)
             (evidence . (".rivet/acceptance/linux/interaction-trace.json"
                          ".rivet/acceptance/linux/first-run-trace.json"
                          ".rivet/acceptance/linux/persistence-restart.json"
                          ".rivet/acceptance/linux/install-lifecycle.json")))
     #hasheq((id . release-update)
             (kind . release)
             (platforms . (windows macos linux))
             (command . ("racket" "scripts/acceptance/release-update.rkt"))
             (timeout-seconds . 900)
             (evidence . (".rivet/acceptance/release-update.json"))))))
