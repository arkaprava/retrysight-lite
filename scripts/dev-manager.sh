#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail
cd "$(dirname "$0")/.."
npm run install:app
npm run dev
