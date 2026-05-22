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

# ── Plugin (loaded by Basecamp) ────────────────────────────────────────────
add_library(LezMultisigPlugin SHARED
    src/LezMultisigBackend.cpp
    src/LezMultisigPlugin.cpp
)

# Resource name "lez_multisig_qml" must match Q_INIT_RESOURCE(lez_multisig_qml) in LezMultisigPlugin.cpp
qt_add_resources(LezMultisigPlugin "lez_multisig_qml"
    PREFIX "/"
    FILES qml/Main.qml
)

target_link_libraries(LezMultisigPlugin PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickWidgets Qt6::Concurrent
    lez_multisig_ffi
)

# Output name must match manifest.json "main" value (lib<name>_plugin.so)
set_target_properties(LezMultisigPlugin PROPERTIES OUTPUT_NAME "lez_multisig_plugin")

# ── Standalone preview app ─────────────────────────────────────────────────
add_executable(LezMultisigApp
    src/main.cpp
    src/LezMultisigBackend.cpp
    src/LezMultisigPlugin.cpp
)

# Same resource name as the plugin so Q_INIT_RESOURCE resolves in both targets
qt_add_resources(LezMultisigApp "lez_multisig_qml"
    PREFIX "/"
    FILES qml/Main.qml
)

target_link_libraries(LezMultisigApp PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickWidgets Qt6::Concurrent
    lez_multisig_ffi
)

set_target_properties(LezMultisigApp PROPERTIES
    BUILD_RPATH "${CMAKE_CURRENT_SOURCE_DIR}/../target/release"
)
