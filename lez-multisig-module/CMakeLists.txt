cmake_minimum_required(VERSION 3.16)
project(LezMultisig VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Qml Quick QuickWidgets Concurrent)

# ── Logos Design System (optional — provides Logos.Theme and Logos.Controls) ──
# Set LOGOS_DESIGN_SYSTEM_DIR to the logos-design-system source root, e.g.:
#   cmake -DLOGOS_DESIGN_SYSTEM_DIR=/path/to/logos-design-system ..
set(LOGOS_DESIGN_SYSTEM_DIR "" CACHE PATH "logos-design-system source root (contains src/qml/theme/ and src/qml/controls/)")

if(NOT "${LOGOS_DESIGN_SYSTEM_DIR}" STREQUAL "")
    set(LOGOS_QML_DIR "${CMAKE_BINARY_DIR}/logos-qml")

    # Stage Logos.Theme into logos-qml/Logos/Theme/
    file(MAKE_DIRECTORY "${LOGOS_QML_DIR}/Logos/Theme/fonts")
    file(COPY "${LOGOS_DESIGN_SYSTEM_DIR}/src/qml/theme/qmldir" DESTINATION "${LOGOS_QML_DIR}/Logos/Theme/")
    file(GLOB _theme_qml  "${LOGOS_DESIGN_SYSTEM_DIR}/src/qml/theme/*.qml")
    file(GLOB _theme_fonts "${LOGOS_DESIGN_SYSTEM_DIR}/src/qml/theme/fonts/*.ttf")
    foreach(_f ${_theme_qml} ${_theme_fonts})
        get_filename_component(_ext "${_f}" EXT)
        if("${_ext}" STREQUAL ".ttf")
            file(COPY "${_f}" DESTINATION "${LOGOS_QML_DIR}/Logos/Theme/fonts/")
        else()
            file(COPY "${_f}" DESTINATION "${LOGOS_QML_DIR}/Logos/Theme/")
        endif()
    endforeach()

    # Stage Logos.Controls into logos-qml/Logos/Controls/
    file(MAKE_DIRECTORY "${LOGOS_QML_DIR}/Logos/Controls")
    file(COPY "${LOGOS_DESIGN_SYSTEM_DIR}/src/qml/controls/qmldir" DESTINATION "${LOGOS_QML_DIR}/Logos/Controls/")
    file(GLOB _controls_qml "${LOGOS_DESIGN_SYSTEM_DIR}/src/qml/controls/*.qml")
    foreach(_f ${_controls_qml})
        file(COPY "${_f}" DESTINATION "${LOGOS_QML_DIR}/Logos/Controls/")
    endforeach()

    add_compile_definitions(LOGOS_QML_IMPORT_PATH="${LOGOS_QML_DIR}")
    message(STATUS "Logos Design System: ${LOGOS_DESIGN_SYSTEM_DIR}")
    message(STATUS "  QML import path: ${LOGOS_QML_DIR}")
else()
    message(STATUS "Logos Design System: not configured (set -DLOGOS_DESIGN_SYSTEM_DIR=...)")
endif()

# ── FFI shared library (built by `make ffi`) ──────────────────────────────────
add_library(lez_multisig_ffi SHARED IMPORTED)
set_target_properties(lez_multisig_ffi PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_SOURCE_DIR}/../target/release/liblez_multisig_ffi.so"
)

# ── Spelbook registry FFI (liblez_registry_ffi.so from vpavlin/spelbook) ──────
# Set SPELBOOK_FFI_DIR to the spelbook target/release dir, e.g.:
#   cmake -DSPELBOOK_FFI_DIR=/path/to/spelbook/target/release ..
set(SPELBOOK_FFI_DIR "" CACHE PATH "spelbook target/release dir containing liblez_registry_ffi.so")
if(NOT "${SPELBOOK_FFI_DIR}" STREQUAL "")
    add_library(lez_registry_ffi SHARED IMPORTED)
    set_target_properties(lez_registry_ffi PROPERTIES
        IMPORTED_LOCATION "${SPELBOOK_FFI_DIR}/liblez_registry_ffi.so"
    )
    add_compile_definitions(SPELBOOK_AVAILABLE)
    message(STATUS "Spelbook FFI: ${SPELBOOK_FFI_DIR}/liblez_registry_ffi.so")
else()
    message(STATUS "Spelbook FFI: not configured (set -DSPELBOOK_FFI_DIR=...)")
endif()

# ── Logos CPP SDK (optional — provides StorageModule for native IDL fetch) ──
# Set LOGOS_CPP_SDK_INC to the directory containing logos_api.h, logos_types.h, etc.
# e.g.: cmake -DLOGOS_CPP_SDK_INC=/path/to/logos-cpp-sdk/cpp ..
# Workspace default is auto-detected from repos/logos-cpp-sdk/cpp/.
set(LOGOS_CPP_SDK_INC "" CACHE PATH "logos-cpp-sdk include dir (contains logos_api.h)")
if("${LOGOS_CPP_SDK_INC}" STREQUAL "")
    set(_LOGOS_SDK_WORKSPACE "$ENV{HOME}/devel/github.com/logos-co/logos-workspace/repos/logos-cpp-sdk/cpp")
    if(EXISTS "${_LOGOS_SDK_WORKSPACE}/logos_api.h")
        set(LOGOS_CPP_SDK_INC "${_LOGOS_SDK_WORKSPACE}")
    endif()
endif()
if(NOT "${LOGOS_CPP_SDK_INC}" STREQUAL "")
    message(STATUS "Logos CPP SDK include: ${LOGOS_CPP_SDK_INC} — StorageModule enabled for plugin")
else()
    message(STATUS "Logos CPP SDK include: not configured (set -DLOGOS_CPP_SDK_INC=...) — StorageModule disabled")
endif()
# LOGOS_STORAGE_AVAILABLE is set per-target (plugin only) below to avoid
# linking storage_module_api.cpp into LezMultisigApp where logos_sdk is absent.

set(_STORAGE_API_SRC vendor/storage_module_api/storage_module_api.cpp)
set(_STORAGE_API_INC vendor/storage_module_api)

# ── Plugin (loaded by Basecamp) ────────────────────────────────────────────
add_library(LezMultisigPlugin SHARED
    src/LezMultisigBackend.cpp
    src/LezMultisigPlugin.cpp
    src/LezMultisigCodec.h        # header-only; listed for IDE visibility
    src/LezSpelbookBridge.h       # header-only; listed for IDE visibility
    src/LezStorageBridge.h        # header-only; listed for IDE visibility
)

# storage_module_api.cpp added only to the plugin (.so) — undefined LogosAPI symbols
# are resolved at runtime from Basecamp's process. The standalone app can't link them.
if(NOT "${LOGOS_CPP_SDK_INC}" STREQUAL "")
    target_sources(LezMultisigPlugin PRIVATE ${_STORAGE_API_SRC})
    target_compile_definitions(LezMultisigPlugin PRIVATE LOGOS_STORAGE_AVAILABLE)
    target_include_directories(LezMultisigPlugin PRIVATE ${_STORAGE_API_INC} ${LOGOS_CPP_SDK_INC} src)
endif()

# Resource name "lez_multisig_qml" must match Q_INIT_RESOURCE(lez_multisig_qml) in LezMultisigPlugin.cpp
qt_add_resources(LezMultisigPlugin "lez_multisig_qml"
    PREFIX "/"
    FILES qml/Main.qml
)

target_link_libraries(LezMultisigPlugin PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickWidgets Qt6::Concurrent
    lez_multisig_ffi
    $<$<BOOL:${SPELBOOK_FFI_DIR}>:lez_registry_ffi>
)

# Output name must match manifest.json "main" value (lib<name>_plugin.so)
set_target_properties(LezMultisigPlugin PROPERTIES OUTPUT_NAME "lez_multisig_plugin")

# ── Standalone preview app ─────────────────────────────────────────────────
add_executable(LezMultisigApp
    src/main.cpp
    src/LezMultisigBackend.cpp
    src/LezMultisigPlugin.cpp
    src/LezMultisigCodec.h        # header-only; listed for IDE visibility
    src/LezSpelbookBridge.h       # header-only; listed for IDE visibility
    src/LezStorageBridge.h        # header-only; listed for IDE visibility
)

# App only needs include dirs so LezStorageBridge.h compiles (storage disabled
# at runtime — no LOGOS_STORAGE_AVAILABLE, no storage_module_api.cpp linked).
target_include_directories(LezMultisigApp PRIVATE src)
if(NOT "${LOGOS_CPP_SDK_INC}" STREQUAL "")
    target_include_directories(LezMultisigApp PRIVATE ${_STORAGE_API_INC} ${LOGOS_CPP_SDK_INC})
endif()

# Same resource name as the plugin so Q_INIT_RESOURCE resolves in both targets
qt_add_resources(LezMultisigApp "lez_multisig_qml"
    PREFIX "/"
    FILES qml/Main.qml
)

target_link_libraries(LezMultisigApp PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickWidgets Qt6::Concurrent
    lez_multisig_ffi
    $<$<BOOL:${SPELBOOK_FFI_DIR}>:lez_registry_ffi>
)

set_target_properties(LezMultisigApp PROPERTIES
    BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}/../target/release:${SPELBOOK_FFI_DIR}"
)
