#!/bin/bash
cd "$(dirname "$0")/.."
cargo test -p lez-multisig-e2e -- --nocapture
