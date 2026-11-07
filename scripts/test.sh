#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
# This executable harness works with Command Line Tools, which do not ship XCTest.
swift run RestFlowChecks
