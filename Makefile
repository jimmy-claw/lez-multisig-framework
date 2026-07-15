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
SPEL_FW_REV  := $(shell grep -m1 'git = "https://github.com/logos-co/spel.git"' lez-multisig-ffi/Cargo.toml | grep -oP 'rev = "\K[^"]+')
IDL_JSON    := lez-multisig-ffi/src/multisig_idl.json
FFI_RS      := lez-multisig-ffi/src/multisig.rs
HEADER_H    := lez-multisig-ffi/include/lez_multisig.h
GENERATE_IDL_BIN := methods/guest/Cargo.toml

MODULE_SRC := lez-multisig-module/src
MODULE_QML := lez-multisig-module/qml
MODULE_GEN_DIR := /tmp/lez-module-gen

.PHONY: generate generate-idl generate-ffi generate-header generate-module generate-module-scaffold check-generated install-tools

install-tools: ## Install spel-client-gen + cbindgen (required for generate/generate-header)
	$(if $(SPEL_FW_TAG), \
	  source ~/.cargo/env && cargo install --git $(SPEL_FW_GIT) --tag $(SPEL_FW_TAG) spel-client-gen --locked 2>/dev/null || \
	  cargo install --git $(SPEL_FW_GIT) --tag $(SPEL_FW_TAG) spel-client-gen, \
	  source ~/.cargo/env && cargo install --git $(SPEL_FW_GIT) --rev $(SPEL_FW_REV) spel-client-gen --locked 2>/dev/null || \
	  cargo install --git $(SPEL_FW_GIT) --rev $(SPEL_FW_REV) spel-client-gen)
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

patch-generated: ## Patch generated files to register codec + spelbook context properties
	@echo "🔧 Patching generated main.cpp (codec, spelbook, LOGOS_QML_IMPORT_PATH)..."
	@sed -i 's|#include "LezMultisigPlugin.h"|#include "LezMultisigCodec.h"\n#include "LezMultisigPlugin.h"\n#include "LezSpelbookBridge.h"|' $(MODULE_SRC)/main.cpp 2>/dev/null || true
	@sed -i 's|LezMultisigBackend backend(nullptr);|LezMultisigBackend backend(nullptr);\n\tLezMultisigCodec codec(nullptr);\n\tLezSpelbookBridge spelbook(nullptr);|' $(MODULE_SRC)/main.cpp 2>/dev/null || true
	@sed -i 's|setContextProperty("backend", \&backend);|setContextProperty("backend", \&backend);\n\tview.engine()->rootContext()->setContextProperty("codec", \&codec);\n\tview.engine()->rootContext()->setContextProperty("spelbook", \&spelbook);|' $(MODULE_SRC)/main.cpp 2>/dev/null || true
	@if ! grep -q 'LOGOS_QML_IMPORT_PATH' $(MODULE_SRC)/main.cpp; then \
		sed -i 's|const char\* qmlPath|// Logos.Theme / Logos.Controls import path\n#ifdef LOGOS_QML_IMPORT_PATH\n\tview.engine()->addImportPath(QStringLiteral(LOGOS_QML_IMPORT_PATH));\n#endif\n\tconst char* runtimeImportPath = std::getenv("LOGOS_QML_IMPORT_PATH");\n\tif (runtimeImportPath)\n\t\tview.engine()->addImportPath(QString::fromUtf8(runtimeImportPath));\n\n\tconst char* qmlPath|' $(MODULE_SRC)/main.cpp; \
	fi
	@echo "  ✅ Patched: main.cpp"
	@echo "🔧 Patching generated LezMultisigBackend.cpp (normalizeCreateKey)..."
	@if ! grep -q 'normalizeCreateKey' $(MODULE_SRC)/LezMultisigBackend.cpp; then \
		sed -i 's|#include <QJsonArray>|#include <QCryptographicHash>\n#include <QJsonArray>|' $(MODULE_SRC)/LezMultisigBackend.cpp; \
		sed -i 's|#include <QSettings>|#include <QRegularExpression>\n#include <QSettings>|' $(MODULE_SRC)/LezMultisigBackend.cpp; \
		printf '\nstatic QString normalizeCreateKey(const QString& key) {\n    static const QRegularExpression hexRe(QStringLiteral("^[0-9a-fA-F]{64}$$"));\n    if (hexRe.match(key).hasMatch()) return key;\n    return QString::fromLatin1(QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha256).toHex());\n}\n' >> $(MODULE_SRC)/LezMultisigBackend.cpp.tmp && \
		head -n $$(grep -n '#include' $(MODULE_SRC)/LezMultisigBackend.cpp | tail -1 | cut -d: -f1) $(MODULE_SRC)/LezMultisigBackend.cpp > $(MODULE_SRC)/LezMultisigBackend.cpp.new && \
		cat $(MODULE_SRC)/LezMultisigBackend.cpp.tmp >> $(MODULE_SRC)/LezMultisigBackend.cpp.new && \
		tail -n +$$(( $$(grep -n '#include' $(MODULE_SRC)/LezMultisigBackend.cpp | tail -1 | cut -d: -f1) + 1 )) $(MODULE_SRC)/LezMultisigBackend.cpp >> $(MODULE_SRC)/LezMultisigBackend.cpp.new && \
		mv $(MODULE_SRC)/LezMultisigBackend.cpp.new $(MODULE_SRC)/LezMultisigBackend.cpp && \
		rm -f $(MODULE_SRC)/LezMultisigBackend.cpp.tmp && \
		sed -i 's|args\["create_key"\] = createKey;|args["create_key"] = normalizeCreateKey(createKey);|g' $(MODULE_SRC)/LezMultisigBackend.cpp; \
		echo "  ✅ Added: normalizeCreateKey"; \
	else \
		echo "  ℹ️  Skipped: normalizeCreateKey already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.cpp (target_accounts for execute)..."
	@if ! grep -q 'target_accounts' $(MODULE_SRC)/LezMultisigBackend.cpp; then \
		sed -i 's|args\["create_key"\] = normalizeCreateKey(createKey);\n    dispatchFfi("execute"|args["create_key"] = normalizeCreateKey(createKey);\n    args["target_accounts"] = QJsonArray();\n    dispatchFfi("execute"|' $(MODULE_SRC)/LezMultisigBackend.cpp; \
		python3 -c "\
import re, sys;\
path='$(MODULE_SRC)/LezMultisigBackend.cpp';\
txt=open(path).read();\
patched=re.sub(\
    r'(void LezMultisigBackend::execute\b.*?args\[\"create_key\"\] = normalizeCreateKey\(createKey\);)',\
    r'\1\n    args[\"target_accounts\"] = QJsonArray();',\
    txt, flags=re.DOTALL);\
open(path,'w').write(patched);\
print('  patched') if patched != txt else print('  no-op')\
"; \
		echo "  ✅ Added: target_accounts to execute"; \
	else \
		echo "  ℹ️  Skipped: target_accounts already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigPlugin.cpp..."
	@# 1) Add codec include + context property (idempotent)
	@if ! grep -q 'LezMultisigCodec' $(MODULE_SRC)/LezMultisigPlugin.cpp; then \
		sed -i 's|#include "LezMultisigBackend.h"|#include "LezMultisigBackend.h"\n#include "LezMultisigCodec.h"|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		sed -i 's|setContextProperty("backend", m_backend);|setContextProperty("backend", m_backend);\n\tview->engine()->rootContext()->setContextProperty("codec", new LezMultisigCodec(this));|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		echo "  ✅ Added: codec context property"; \
	else \
		echo "  ℹ️  Skipped: LezMultisigCodec already present"; \
	fi
	@# 2) Add spelbook include + context property (idempotent)
	@if ! grep -q 'LezSpelbookBridge' $(MODULE_SRC)/LezMultisigPlugin.cpp; then \
		sed -i 's|#include "LezMultisigCodec.h"|#include "LezMultisigCodec.h"\n#include "LezSpelbookBridge.h"|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		sed -i 's|setContextProperty("codec", new LezMultisigCodec(this));|setContextProperty("codec", new LezMultisigCodec(this));\n\tview->engine()->rootContext()->setContextProperty("spelbook", new LezSpelbookBridge(this));|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		echo "  ✅ Added: spelbook context property"; \
	else \
		echo "  ℹ️  Skipped: LezSpelbookBridge already present"; \
	fi
	@# 3) Add storage bridge include + context property (idempotent)
	@if ! grep -q 'LezStorageBridge' $(MODULE_SRC)/LezMultisigPlugin.cpp; then \
		sed -i 's|#include "LezSpelbookBridge.h"|#include "LezSpelbookBridge.h"\n#include "LezStorageBridge.h"|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		sed -i 's|setContextProperty("spelbook", new LezSpelbookBridge(this));|setContextProperty("spelbook", new LezSpelbookBridge(this));\n\tview->engine()->rootContext()->setContextProperty("storage", new LezStorageBridge(m_api, this));|' $(MODULE_SRC)/LezMultisigPlugin.cpp; \
		echo "  ✅ Added: storage context property"; \
	else \
		echo "  ℹ️  Skipped: LezStorageBridge already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.h/.cpp (fetching flag)..."
	@if ! grep -q 'fetching' $(MODULE_SRC)/LezMultisigBackend.h; then \
		sed -i 's|Q_PROPERTY(bool       busy       READ busy       NOTIFY busyChanged)|Q_PROPERTY(bool       busy       READ busy       NOTIFY busyChanged)\n    Q_PROPERTY(bool       fetching   READ fetching   NOTIFY fetchingChanged)|' $(MODULE_SRC)/LezMultisigBackend.h; \
		sed -i 's|bool       busy()       const { return m_busy; }|bool       busy()       const { return m_busy; }\n    bool       fetching()   const { return m_fetching; }|' $(MODULE_SRC)/LezMultisigBackend.h; \
		sed -i 's|void busyChanged();|void busyChanged();\n    void fetchingChanged();|' $(MODULE_SRC)/LezMultisigBackend.h; \
		sed -i 's|bool       m_busy      = false;|bool       m_busy      = false;\n    bool       m_fetching  = false;|' $(MODULE_SRC)/LezMultisigBackend.h; \
		python3 -c "\
path='$(MODULE_SRC)/LezMultisigBackend.cpp';\
txt=open(path).read();\
txt=txt.replace(\
    'void LezMultisigBackend::fetchMultisigState(const QString& createKey) {\n    QJsonObject args = baseArgs();',\
    'void LezMultisigBackend::fetchMultisigState(const QString& createKey) {\n    m_fetching = true;\n    emit fetchingChanged();\n    QJsonObject args = baseArgs();',\
    1);\
txt += '\nvoid LezMultisigBackend::markFetchDone() {\n    if (!m_fetching) return;\n    m_fetching = false;\n    emit fetchingChanged();\n}\n';\
open(path,'w').write(txt);\
"; \
		sed -i 's|Q_INVOKABLE QStringList fieldHistory|Q_INVOKABLE void        markFetchDone();\n    Q_INVOKABLE QStringList fieldHistory|' $(MODULE_SRC)/LezMultisigBackend.h; \
		echo "  ✅ Added: fetching property + markFetchDone"; \
	else \
		echo "  ℹ️  Skipped: fetching already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.h (clearHistory, computePda)..."
	@if ! grep -q 'clearHistory' $(MODULE_SRC)/LezMultisigBackend.h; then \
		sed -i 's|Q_INVOKABLE void        saveHistory(const QString\& key, const QString\& value);|Q_INVOKABLE void        saveHistory(const QString\& key, const QString\& value);\n    Q_INVOKABLE void        clearHistory(const QString\& key);\n    Q_INVOKABLE QVariantMap computePda(const QString\& createKey, const QString\& purpose) const;\n    Q_INVOKABLE QString     pdaFromSeed(const QString\& seedHex) const;|' $(MODULE_SRC)/LezMultisigBackend.h; \
		echo "  ✅ Added: clearHistory + computePda + pdaFromSeed declarations"; \
	else \
		echo "  ℹ️  Skipped: clearHistory already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.cpp (clearHistory, computePda, pdaFromSeed, FFI)..."
	@if ! grep -q 'lez_multisig_compute_pda' $(MODULE_SRC)/LezMultisigBackend.cpp; then \
		sed -i 's|    char\* multisig_program_decode_account(const char\* args_json);|    char* multisig_program_decode_account(const char* args_json);\n    char* lez_multisig_compute_pda(const char* args_json);\n    void  lez_multisig_free_string(char* s);\n    char* lez_multisig_pda_from_seed(const char* args_json);|' $(MODULE_SRC)/LezMultisigBackend.cpp; \
		python3 -c "\
path='$(MODULE_SRC)/LezMultisigBackend.cpp';\
txt=open(path).read();\
impl='''\n\nvoid LezMultisigBackend::clearHistory(const QString& key) {\n    QSettings(\"logos-co\", \"lez_multisig\").remove(\"history/\" + key);\n}\n\nQVariantMap LezMultisigBackend::computePda(const QString& createKey, const QString& purpose) const {\n    QJsonObject args;\n    args[\"program_id_hex\"] = m_programIdHex;\n    args[\"create_key\"]     = createKey;\n    args[\"purpose\"]        = purpose;\n    QByteArray json = QJsonDocument(args).toJson(QJsonDocument::Compact);\n    char* raw = lez_multisig_compute_pda(json.constData());\n    if (!raw) return {};\n    auto result = QJsonDocument::fromJson(QByteArray(raw)).object().toVariantMap();\n    lez_multisig_free_string(raw);\n    return result;\n}\n\nQString LezMultisigBackend::pdaFromSeed(const QString& seedHex) const {\n    QJsonObject args;\n    args[\"program_id_hex\"] = m_programIdHex;\n    args[\"seed_hex\"]       = seedHex;\n    QByteArray json = QJsonDocument(args).toJson(QJsonDocument::Compact);\n    char* raw = lez_multisig_pda_from_seed(json.constData());\n    if (!raw) return {};\n    auto obj = QJsonDocument::fromJson(QByteArray(raw)).object();\n    lez_multisig_free_string(raw);\n    return obj.value(\"account_id\").toString();\n}''';\
patched=txt.replace('    s.setValue(\"history/\" + key, h);\n}', '    s.setValue(\"history/\" + key, h);\n}' + impl, 1);\
open(path,'w').write(patched);\
print('  patched') if patched != txt else print('  no-op')\
"; \
		echo "  ✅ Added: clearHistory + computePda + pdaFromSeed implementations"; \
	else \
		echo "  ℹ️  Skipped: lez_multisig_compute_pda already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.cpp (error handling for fetch/list)..."
	@if ! grep -q 'operationError.*fetch_multisig_state' $(MODULE_SRC)/LezMultisigBackend.cpp; then \
		python3 -c "\
path='$(MODULE_SRC)/LezMultisigBackend.cpp';\
txt=open(path).read();\
txt=txt.replace(\
    '            if (obj.value(\"success\").toBool() && obj.contains(\"state\")) {\n                m_multisigState = obj.value(\"state\").toObject().toVariantMap();\n                emit multisigStateChanged();\n            }\n        }, Qt::QueuedConnection);\n    });\n}\n\nvoid LezMultisigBackend::fetchProposal',\
    '            if (obj.value(\"success\").toBool() && obj.contains(\"state\")) {\n                m_multisigState = obj.value(\"state\").toObject().toVariantMap();\n                emit multisigStateChanged();\n            } else if (!obj.value(\"success\").toBool()) {\n                emit operationError(\"fetch_multisig_state\", obj.value(\"error\").toString(result));\n            }\n        }, Qt::QueuedConnection);\n    });\n}\n\nvoid LezMultisigBackend::fetchProposal',\
    1);\
txt=txt.replace(\
    '            if (obj.value(\"success\").toBool() && obj.contains(\"state\")) {\n                m_proposal = obj.value(\"state\").toObject().toVariantMap();\n                emit proposalChanged();\n            }\n        }, Qt::QueuedConnection);\n    });\n}',\
    '            if (obj.value(\"success\").toBool() && obj.contains(\"state\")) {\n                m_proposal = obj.value(\"state\").toObject().toVariantMap();\n                emit proposalChanged();\n            } else if (!obj.value(\"success\").toBool()) {\n                emit operationError(\"fetch_proposal\", obj.value(\"error\").toString(result));\n            }\n        }, Qt::QueuedConnection);\n    });\n}',\
    1);\
txt=txt.replace(\
    '                m_lastError = obj.value(\"error\").toString(result);\n                emit lastErrorChanged();\n            }\n        }, Qt::QueuedConnection);\n    });\n}\n\nvoid LezMultisigBackend::createAccount',\
    '                emit operationError(\"list_accounts\", obj.value(\"error\").toString(result));\n            }\n        }, Qt::QueuedConnection);\n    });\n}\n\nvoid LezMultisigBackend::createAccount',\
    1);\
open(path,'w').write(txt);\
"; \
		echo "  ✅ Added: error handling for fetchMultisigState, fetchProposal, listAccounts"; \
	else \
		echo "  ℹ️  Skipped: fetch error handling already present"; \
	fi
	@echo "🔧 Patching generated LezMultisigBackend.h/.cpp (executeWithAccounts)..."
	@if ! grep -q 'executeWithAccounts' $(MODULE_SRC)/LezMultisigBackend.h; then \
		sed -i 's|Q_INVOKABLE QString     pdaFromSeed(const QString\& seedHex) const;|Q_INVOKABLE QString     pdaFromSeed(const QString\& seedHex) const;\n    Q_INVOKABLE void        executeWithAccounts(const QString\& executorId, const QString\& proposalIndex, const QString\& createKey, const QVariantList\& targetAccounts);|' $(MODULE_SRC)/LezMultisigBackend.h; \
		python3 -c "\
path='$(MODULE_SRC)/LezMultisigBackend.cpp';\
txt=open(path).read();\
impl='''\nvoid LezMultisigBackend::executeWithAccounts(const QString& executorId, const QString& proposalIndex, const QString& createKey, const QVariantList& targetAccounts) {\n    QJsonObject args = baseArgs();\n    args[\"executor\"]        = executorId;\n    args[\"proposal_index\"]  = proposalIndex;\n    args[\"create_key\"]      = normalizeCreateKey(createKey);\n    QJsonArray accts;\n    for (const QVariant& v : targetAccounts) accts.append(QJsonValue::fromVariant(v));\n    args[\"target_accounts\"] = accts;\n    dispatchFfi(\"execute\", [this, args]() {\n        return callFfi(multisig_program_execute, args);\n    });\n}''';\
anchor='    return obj.value(\"account_id\").toString();\n}';\
patched=txt.replace(anchor, anchor + impl, 1);\
open(path,'w').write(patched);\
print('  patched') if patched != txt else print('  no-op')\
"; \
		echo "  ✅ Added: executeWithAccounts"; \
	else \
		echo "  ℹ️  Skipped: executeWithAccounts already present"; \
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
	$(MAKE) patch-generated

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

# Spelbook FFI library directory — set to vpavlin/spelbook target/release.
# e.g.: SPELBOOK_FFI_DIR=../spelbook/target/release make build-module
SPELBOOK_FFI_DIR ?=
_SPELBOOK_WORKSPACE := $(HOME)/devel/github.com/vpavlin/spelbook/target/release
ifeq ($(SPELBOOK_FFI_DIR),)
  ifneq ($(wildcard $(_SPELBOOK_WORKSPACE)/liblez_registry_ffi.so),)
    SPELBOOK_FFI_DIR := $(_SPELBOOK_WORKSPACE)
  endif
endif

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

_CMAKE_SPELBOOK :=
ifneq ($(SPELBOOK_FFI_DIR),)
  _CMAKE_SPELBOOK := -DSPELBOOK_FFI_DIR=$(SPELBOOK_FFI_DIR)
endif

.PHONY: build-module run-module

build-module: build-ffi ## Build the Basecamp UI module plugin + standalone preview app (run generate-module separately to regenerate backend scaffold)
	@echo "🔨 Building UI module..."
	$(if $(LOGOS_DESIGN_SYSTEM_DIR),@echo "  Design system: $(LOGOS_DESIGN_SYSTEM_DIR)",@echo "  ⚠️  LOGOS_DESIGN_SYSTEM_DIR not set — Logos.Theme unavailable")
	$(if $(SPELBOOK_FFI_DIR),@echo "  Spelbook FFI:  $(SPELBOOK_FFI_DIR)",@echo "  ⚠️  SPELBOOK_FFI_DIR not set — spelbook bridge unavailable")
	@mkdir -p $(MODULE_BUILD)
	cd $(MODULE_BUILD) && cmake .. -DCMAKE_BUILD_TYPE=Release $(_CMAKE_LOGOS_DS) $(_CMAKE_SPELBOOK)
	cmake --build $(MODULE_BUILD) --parallel
	@echo "✅ Plugin: $(MODULE_PLUGIN)"
	@echo "✅ App:    $(MODULE_APP)"

run-module: build-module ## Run the standalone multisig UI preview (set LEZ_MULTISIG_PROGRAM_ID=<hex> to inject program ID)
	LD_LIBRARY_PATH=$(CURDIR)/$(FFI_LIB_DIR):$(SPELBOOK_FFI_DIR):$$LD_LIBRARY_PATH \
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
