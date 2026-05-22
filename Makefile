# Multisig Program — Quick Commands
#
# Prerequisites:
#   - Rust + risc0 toolchain installed
#   - wallet CLI installed (`cargo install --path wallet` from logos-execution-zone repo)
#   - Sequencer running locally
#   - wallet setup done (`wallet setup`)
#
# Quick start:
#   make build deploy
#   multisig create --threshold 2 --member <ID1> --member <ID2> --member <ID3>
#
# State is saved in .multisig-state so you don't have to re-enter IDs.

SHELL := /bin/bash
STATE_FILE := .multisig-state
PROGRAMS_DIR := target/riscv32im-risc0-zkvm-elf/docker

# Token program binary — set this to point to your lez-programs build
# e.g. LEZ_PROGRAMS_DIR=../lez-programs
LEZ_PROGRAMS_DIR ?=
TOKEN_BIN := $(LEZ_PROGRAMS_DIR)/target/riscv32im-risc0-zkvm-elf/docker/token.bin

MULTISIG_BIN := $(PROGRAMS_DIR)/multisig.bin

# ── Helpers ──────────────────────────────────────────────────────────────────

-include $(STATE_FILE)

define save_var
	@grep -v '^$(1)=' $(STATE_FILE) 2>/dev/null > $(STATE_FILE).tmp || true
	@echo '$(1)=$(2)' >> $(STATE_FILE).tmp
	@mv $(STATE_FILE).tmp $(STATE_FILE)
endef

define require_state
	@if [ -z "$($(1))" ]; then echo "ERROR: $(1) not set. Run the required step first or set it manually."; exit 1; fi
endef

# ── Targets ──────────────────────────────────────────────────────────────────

# ── Code Generation ───────────────────────────────────────────────────────────
# The IDL and FFI client are generated files — do not edit them manually.
# Source of truth: multisig_program/src/lib.rs (Rust macro annotations)
# Pipeline: lib.rs → multisig_idl.json → multisig.rs

SPEL_FW_GIT  := https://github.com/logos-co/spel.git
SPEL_FW_TAG  := $(shell grep -m1 'git = "https://github.com/logos-co/spel.git"' lez-multisig-ffi/Cargo.toml | grep -oP 'tag = "\K[^"]+')
IDL_JSON    := lez-multisig-ffi/src/multisig_idl.json
FFI_RS      := lez-multisig-ffi/src/multisig.rs
HEADER_H    := lez-multisig-ffi/include/lez_multisig.h
GENERATE_IDL_BIN := methods/guest/Cargo.toml

MODULE_SRC := lez-multisig-module/src
MODULE_QML := lez-multisig-module/qml
MODULE_GEN_DIR := /tmp/lez-module-gen

.PHONY: generate generate-idl generate-ffi generate-header generate-module generate-module-scaffold check-generated install-tools

install-tools: ## Install spel-client-gen + cbindgen (required for generate/generate-header)
	source ~/.cargo/env && cargo install --git $(SPEL_FW_GIT) --tag $(SPEL_FW_TAG) spel-client-gen --locked 2>/dev/null || \
	cargo install --git $(SPEL_FW_GIT) --tag $(SPEL_FW_TAG) spel-client-gen
	source ~/.cargo/env && cargo install cbindgen --version 0.29.2 --locked 2>/dev/null || true

generate-idl: ## Regenerate IDL from Rust annotations in lib.rs
	@echo "🔨 Generating IDL from multisig_program/src/lib.rs..."
	source ~/.cargo/env && cargo run -p lez-multisig-idl-gen > $(IDL_JSON)
	@echo "✅ IDL written to $(IDL_JSON)"

generate-ffi: ## Regenerate FFI client (multisig.rs) from IDL
	@echo "🔨 Generating FFI client from $(IDL_JSON)..."
	@mkdir -p /tmp/lez-ffi-gen
	source ~/.cargo/env && spel-client-gen --idl $(IDL_JSON) --out-dir /tmp/lez-ffi-gen || \
		(echo "ERROR: spel-client-gen not found. Run: make install-tools" && exit 1)
	@# Prepend generated-file header, then append spel-client-gen output
	@echo "// GENERATED FILE — do not edit manually. Run 'make generate' to regenerate from Rust annotations." > $(FFI_RS)
	@cat /tmp/lez-ffi-gen/multisig_program_ffi.rs >> $(FFI_RS)
	@echo "✅ FFI client written to $(FFI_RS)"

SPEL_GEN_MODULE_FLAGS := --idl $(IDL_JSON) --target logos-module \
	--module-name lez_multisig \
	--ffi-lib-path ../target/release/liblez_multisig_ffi.so \
	--out-dir $(MODULE_GEN_DIR)

generate-module: ## Regenerate backend/plugin/build files; preserves hand-written qml/Main.qml (use generate-module-scaffold for first run)
	@echo "🔨 Generating logos-module backend from $(IDL_JSON)..."
	source ~/.cargo/env && spel-client-gen $(SPEL_GEN_MODULE_FLAGS) --skip-ui || \
		(echo "ERROR: spel-client-gen not found. Run: make install-tools" && exit 1)
	@cp $(MODULE_GEN_DIR)/src/LezMultisigBackend.h   $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigBackend.cpp $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigPlugin.h    $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigPlugin.cpp  $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/main.cpp               $(MODULE_SRC)/
	@# CMakeLists.txt, manifest.json, module.yaml are hand-edited and tracked in git — do NOT overwrite
	@echo "✅ Backend/plugin/build files written (qml/Main.qml, CMakeLists.txt, manifest.json, module.yaml preserved)"
	$(MAKE) patch-generated

patch-generated: ## Patch generated LezMultisigPlugin.cpp to register the codec context property
	@echo "🔧 Patching generated LezMultisigPlugin.cpp to add codec context property..."
	@# Add #include "LezMultisigCodec.h" after the last #include in the generated file
	@if ! grep -q 'LezMultisigCodec' $(MODULE_SRC)/LezMultisigPlugin.cpp; then \
		sed -i 's|#include "LezMultisigBackend.h"|#include "LezMultisigBackend.h"\n#include "LezMultisigCodec.h"|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		sed -i 's|setContextProperty("backend", m_backend);|setContextProperty("backend", m_backend);\n\tview->engine()->rootContext()->setContextProperty("codec", new LezMultisigCodec(this));|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		echo "✅ Patched: codec context property added"; \
	else \
		echo "ℹ️  Already patched (LezMultisigCodec already present)"; \
	fi

generate-module-scaffold: ## First-time: generate ALL files including qml/Main.qml scaffold (overwrites existing QML)
	@echo "🔨 Generating full logos-module scaffold from $(IDL_JSON)..."
	source ~/.cargo/env && spel-client-gen $(SPEL_GEN_MODULE_FLAGS) || \
		(echo "ERROR: spel-client-gen not found. Run: make install-tools" && exit 1)
	@cp $(MODULE_GEN_DIR)/src/LezMultisigBackend.h   $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigBackend.cpp $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigPlugin.h    $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/LezMultisigPlugin.cpp  $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/src/main.cpp               $(MODULE_SRC)/
	@cp $(MODULE_GEN_DIR)/qml/Main.qml               $(MODULE_QML)/Main.qml
	@cp $(MODULE_GEN_DIR)/CMakeLists.txt             $(MODULE_DIR)/
	@cp $(MODULE_GEN_DIR)/manifest.json              $(MODULE_DIR)/
	@cp $(MODULE_GEN_DIR)/module.yaml                $(MODULE_DIR)/
	@echo "✅ Full scaffold written to $(MODULE_SRC)/, $(MODULE_QML)/, and $(MODULE_DIR)/"

generate: ## Regenerate IDL, FFI client, C header, and Qt module from Rust annotations (run after changing lib.rs)
	@echo "🔄 Regenerating all generated files..."
	$(MAKE) generate-idl
	$(MAKE) generate-ffi
	$(MAKE) generate-header
	$(MAKE) generate-module
	@echo ""
	@echo "✅ Generation complete. Run 'cargo check' to verify."

generate-header: ## Generate C header from Rust FFI via cbindgen
	@echo "🔨 Generating C header from lez-multisig-ffi..."
	@mkdir -p lez-multisig-ffi/include
	cd lez-multisig-ffi && source ~/.cargo/env && cbindgen --config cbindgen.toml --output include/lez_multisig.h || \
		(echo "ERROR: cbindgen not found. Install with: cargo install cbindgen" && exit 1)
	@echo "✅ C header written to $(HEADER_H)"

check-generated: ## CI: regenerate and check for drift vs committed state
	@echo "🔍 Checking for generated file drift..."
	@$(MAKE) generate > /tmp/generate-output.txt 2>&1 || (cat /tmp/generate-output.txt && exit 1)
	@# Only the C header is tracked in git; IDL and FFI client are regenerated each CI run
	@git diff --quiet HEAD -- $(HEADER_H) || \
		(echo "⚠️ C header drift detected. Run 'make generate-header' to update." && exit 1)
	@echo "✅ No drift detected"


.PHONY: help build build-cli deploy status clean test

help: ## Show this help
	@echo "Multisig Program — Make Targets"
	@echo ""
	@echo "  Code Generation (start here after changing lib.rs):"
	@echo "  make install-tools         Install spel-client-gen + cbindgen (first-time setup)"
	@echo "  make generate              Regen IDL + FFI + C header + Qt module (all steps)"
	@echo "  make generate-idl          Regen IDL only"
	@echo "  make generate-ffi          Regen FFI client only (requires IDL)"
	@echo "  make generate-header       Regen C header via cbindgen (requires cbindgen)"
	@echo "  make generate-module          Regen backend/plugin/build (preserves hand-written QML)"
	@echo "  make generate-module-scaffold First-time: regen everything incl. qml/Main.qml scaffold"
	@echo "  make check-generated       CI: regenerate and verify C header not drifted"
	@echo ""
	@echo "  Build & Deploy:"
	@echo "  make build                 Build the guest binary (needs risc0 toolchain)"
	@echo "  make build-cli             Build the standalone multisig CLI"
	@echo "  make build-module          Build the Basecamp UI plugin + preview app (requires Qt6)"
	@echo "  make run-module            Run the standalone UI preview (program ID embedded at build time)"
	@echo "  make deploy                Deploy multisig + token programs to sequencer"
	@echo "  make test                  Run unit tests"
	@echo "  make status                Show saved state (account IDs, etc.)"
	@echo "  make clean                 Remove saved state"
	@echo ""
	@echo "Required env: LEZ_PROGRAMS_DIR=<path to lez-programs repo>"

build: ## Build the multisig guest binary
	cargo risczero build --manifest-path methods/guest/Cargo.toml
	@echo ""
	@echo "✅ Guest binary built: $(MULTISIG_BIN)"
	@ls -la $(MULTISIG_BIN)

build-cli: ## Build the standalone multisig CLI
	cargo build --bin multisig -p multisig-cli
	@echo ""
	@echo "✅ CLI built: target/debug/multisig"

deploy: ## Deploy multisig and token programs to sequencer
	@test -f "$(MULTISIG_BIN)" || (echo "ERROR: Multisig binary not found. Run 'make build' first."; exit 1)
	@test -f "$(TOKEN_BIN)" || (echo "ERROR: Token binary not found at $(TOKEN_BIN). Set LEZ_PROGRAMS_DIR correctly."; exit 1)
	wallet deploy-program $(MULTISIG_BIN)
	wallet deploy-program $(TOKEN_BIN)
	@echo ""
	@echo "✅ Programs deployed"

test: ## Run unit tests
	cargo test -p multisig_program

status: ## Show saved state
	@echo "Multisig State (from $(STATE_FILE)):"
	@echo "──────────────────────────────────────"
	@if [ -f "$(STATE_FILE)" ]; then cat $(STATE_FILE); else echo "(no state saved)"; fi
	@echo ""
	@echo "Binaries:"
	@ls -la $(MULTISIG_BIN) 2>/dev/null || echo "  multisig.bin: NOT BUILT (run 'make build')"
	@ls -la $(TOKEN_BIN) 2>/dev/null || echo "  token.bin: NOT FOUND (check LEZ_PROGRAMS_DIR)"

clean: ## Remove saved state
	rm -f $(STATE_FILE) $(STATE_FILE).tmp
	@echo "✅ State cleaned"

# ── E2E Tests ─────────────────────────────────────────────────────────────────

.PHONY: test-e2e

test-e2e: ## Run full E2E tests (requires sequencer running + lez-programs artifacts)
	@test -n "$(LEZ_PROGRAMS_DIR)" || (echo "ERROR: Set LEZ_PROGRAMS_DIR=<path to lez-programs repo>"; exit 1)
	@echo "🧪 Running E2E tests..."
	RISC0_SKIP_BUILD=1 SEQUENCER_URL=http://127.0.0.1:3040 	  MULTISIG_PROGRAM=$(PROGRAMS_DIR)/multisig.bin 	  TOKEN_PROGRAM=$(TOKEN_BIN) 	  cargo test -p lez-multisig-e2e --test e2e_multisig -- --nocapture
	@echo "✅ E2E tests passed"

# ── FFI .so Build ─────────────────────────────────────────────────────────────

.PHONY: build-ffi

build-ffi: generate ## Build the FFI .so (liblez_multisig_ffi.so) for use in Qt module
	@echo "🔨 Building FFI shared library..."
	@PROGRAM_ID=$$([ -f "$(MULTISIG_BIN)" ] && \
	    spel inspect "$(MULTISIG_BIN)" 2>/dev/null | grep 'ImageID (hex bytes)' | awk '{print $$NF}' || echo ""); \
	echo "  Program ID: $${PROGRAM_ID:-(not embedded — run 'make build' first)}"; \
	source ~/.cargo/env && RISC0_SKIP_BUILD=1 MULTISIG_PROGRAM_ID_HEX=$$PROGRAM_ID cargo build --release -p lez-multisig-ffi
	@echo "✅ FFI .so built: target/release/liblez_multisig_ffi.so"
	@ls -lh target/release/liblez_multisig_ffi.so

# ── Basecamp UI Module ────────────────────────────────────────────────────────

MODULE_DIR      := lez-multisig-module
MODULE_BUILD    := $(MODULE_DIR)/build
MODULE_APP      := $(MODULE_BUILD)/LezMultisigApp
MODULE_PLUGIN   := $(MODULE_BUILD)/liblez_multisig_plugin.so
FFI_LIB_DIR    := target/release

# Logos Design System source root — provides Logos.Theme and Logos.Controls QML modules.
# Set to the logos-design-system repo checkout, e.g.:
#   LOGOS_DESIGN_SYSTEM_DIR=../logos-design-system make build-module
LOGOS_DESIGN_SYSTEM_DIR ?=

# Workspace default (used if LOGOS_DESIGN_SYSTEM_DIR not set explicitly)
_LOGOS_DS_WORKSPACE := $(HOME)/devel/github.com/logos-co/logos-workspace/repos/logos-design-system
ifeq ($(LOGOS_DESIGN_SYSTEM_DIR),)
  ifneq ($(wildcard $(_LOGOS_DS_WORKSPACE)/src/qml/theme/qmldir),)
    LOGOS_DESIGN_SYSTEM_DIR := $(_LOGOS_DS_WORKSPACE)
  endif
endif

_CMAKE_LOGOS_DS :=
ifneq ($(LOGOS_DESIGN_SYSTEM_DIR),)
  _CMAKE_LOGOS_DS := -DLOGOS_DESIGN_SYSTEM_DIR=$(LOGOS_DESIGN_SYSTEM_DIR)
endif

.PHONY: build-module run-module

build-module: build-ffi generate-module ## Build the Basecamp UI module plugin + standalone preview app
	@echo "🔨 Building UI module..."
	$(if $(LOGOS_DESIGN_SYSTEM_DIR),@echo "  Design system: $(LOGOS_DESIGN_SYSTEM_DIR)",@echo "  ⚠️  LOGOS_DESIGN_SYSTEM_DIR not set — Logos.Theme unavailable")
	@mkdir -p $(MODULE_BUILD)
	cd $(MODULE_BUILD) && cmake .. -DCMAKE_BUILD_TYPE=Release $(_CMAKE_LOGOS_DS)
	cmake --build $(MODULE_BUILD) --parallel
	@echo "✅ Plugin: $(MODULE_PLUGIN)"
	@echo "✅ App:    $(MODULE_APP)"

run-module: build-module ## Run the standalone multisig UI preview (set LEZ_MULTISIG_PROGRAM_ID=<hex> to inject program ID)
	LD_LIBRARY_PATH=$(CURDIR)/$(FFI_LIB_DIR):$$LD_LIBRARY_PATH \
	  LEZ_MULTISIG_PROGRAM_ID=$(LEZ_MULTISIG_PROGRAM_ID) \
	  QML_IMPORT_PATH=$(CURDIR)/$(MODULE_BUILD)/logos-qml \
	  $(MODULE_APP)

# ── Headless Demo ─────────────────────────────────────────────────────────────

.PHONY: demo

LOGOSCORE ?= $(HOME)/logoscore-test/logoscore
MULTISIG_MODULE_DIR ?= $(HOME)/logos-lez-multisig-module/result/lib
REGISTRY_MODULE_DIR ?= $(HOME)/logos-lez-registry-module/build

demo: ## Run headless Logos Core demo (loads both modules via logoscore)
	@test -f "$(LOGOSCORE)" || (echo "ERROR: logoscore not found at $(LOGOSCORE)"; exit 1)
	@echo "🚀 Loading multisig module via Logos Core..."
	timeout 8 $(LOGOSCORE) --modules-dir $(MULTISIG_MODULE_DIR) 	  --load-modules lez_multisig_module 	  --call "lez_multisig_module.loadMultisigs()" || true
	@echo ""
	@echo "📋 Loading registry module via Logos Core..."
	timeout 8 $(LOGOSCORE) --modules-dir $(REGISTRY_MODULE_DIR) 	  --load-modules liblez_registry_module 	  --call "liblez_registry_module.listPrograms()" || true
