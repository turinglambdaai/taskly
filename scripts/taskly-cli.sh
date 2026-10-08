#!/bin/sh
# Dev/CI shim: run the M6 Racket CLI through the system racket.
exec racket "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)/racket/taskly/cli.rkt" "$@"
