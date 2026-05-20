cmake_minimum_required(VERSION 3.20)
project(lez-multisig-module LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ── Framework build (logos-module-builder / Nix) ──────────────────────────────
if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)

    logos_module(
        NAME lez_multisig
        SOURCES
            src/LezMultisigPlugin.h
            src/LezMultisigPlugin.cpp
            src/LezMultisigBackend.h
            src/LezMultisigBackend.cpp
        EXTERNAL_LIBS lez_multisig_ffi
    )

# ── Manual build (development / standalone) ───────────────────────────────────
else()
    set(CMAKE_AUTOMOC ON)

    find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets Quick QuickWidgets Qml Concurrent)

    # Location of the compiled Rust cdylib.
    # Override via -DLEZ_MULTISIG_FFI_LIB_DIR=... or env var of same name.
    if(DEFINED ENV{LEZ_MULTISIG_FFI_LIB_DIR})
        set(LEZ_MULTISIG_FFI_LIB_DIR "$ENV{LEZ_MULTISIG_FFI_LIB_DIR}")
    elseif(NOT DEFINED LEZ_MULTISIG_FFI_LIB_DIR)
        set(LEZ_MULTISIG_FFI_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../target/release")
    endif()

    set(PLUGIN_TARGET lez_multisig_plugin)

    qt_add_plugin(${PLUGIN_TARGET} CLASS_NAME LezMultisigPlugin)

    target_sources(${PLUGIN_TARGET} PRIVATE
        src/LezMultisigPlugin.cpp
        src/LezMultisigBackend.cpp
    )

    qt_add_resources(${PLUGIN_TARGET} "lez_multisig_qml"
        PREFIX "/qml"
        BASE "qml"
        FILES qml/Main.qml
    )

    if(DEFINED ENV{LOGOS_CPP_SDK_ROOT})
        set(LOGOS_CPP_SDK_ROOT "$ENV{LOGOS_CPP_SDK_ROOT}")
    endif()

    target_include_directories(${PLUGIN_TARGET} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    if(LOGOS_CPP_SDK_ROOT)
        target_include_directories(${PLUGIN_TARGET} PRIVATE
            ${LOGOS_CPP_SDK_ROOT}/include
            ${LOGOS_CPP_SDK_ROOT}/include/cpp
            ${LOGOS_CPP_SDK_ROOT}/include/core
            ${LOGOS_CPP_SDK_ROOT}/cpp
        )
    endif()

    target_link_directories(${PLUGIN_TARGET} PRIVATE "${LEZ_MULTISIG_FFI_LIB_DIR}")
    target_link_libraries(${PLUGIN_TARGET} PRIVATE
        Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Quick Qt6::QuickWidgets
        Qt6::Qml Qt6::Concurrent
        lez_multisig_ffi
    )

    if(APPLE)
        set_target_properties(${PLUGIN_TARGET} PROPERTIES
            BUILD_RPATH   "@loader_path"
            INSTALL_RPATH "@loader_path"
        )
    elseif(UNIX)
        set_target_properties(${PLUGIN_TARGET} PROPERTIES
            BUILD_RPATH   "$ORIGIN"
            INSTALL_RPATH "$ORIGIN"
        )
    endif()

    install(TARGETS ${PLUGIN_TARGET} LIBRARY DESTINATION lib)
    install(FILES "${LEZ_MULTISIG_FFI_LIB_DIR}/liblez_multisig_ffi.so" DESTINATION lib)

    # ── Standalone preview app ────────────────────────────────────────────────
    set(APP_TARGET lez_multisig_app)

    qt_add_executable(${APP_TARGET} src/main.cpp
        src/LezMultisigPlugin.cpp
        src/LezMultisigBackend.cpp
    )

    qt_add_resources(${APP_TARGET} "lez_multisig_qml"
        PREFIX "/qml"
        BASE "qml"
        FILES qml/Main.qml
    )

    target_include_directories(${APP_TARGET} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)
    if(LOGOS_CPP_SDK_ROOT)
        target_include_directories(${APP_TARGET} PRIVATE
            ${LOGOS_CPP_SDK_ROOT}/include
            ${LOGOS_CPP_SDK_ROOT}/include/cpp
            ${LOGOS_CPP_SDK_ROOT}/include/core
            ${LOGOS_CPP_SDK_ROOT}/cpp
        )
    endif()

    target_link_directories(${APP_TARGET} PRIVATE "${LEZ_MULTISIG_FFI_LIB_DIR}")
    target_link_libraries(${APP_TARGET} PRIVATE
        Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Quick Qt6::QuickWidgets
        Qt6::Qml Qt6::Concurrent
        lez_multisig_ffi
    )

    if(APPLE)
        set_target_properties(${APP_TARGET} PROPERTIES
            BUILD_RPATH   "@loader_path"
            INSTALL_RPATH "@loader_path"
        )
    elseif(UNIX)
        set_target_properties(${APP_TARGET} PROPERTIES
            BUILD_RPATH   "$ORIGIN"
            INSTALL_RPATH "$ORIGIN"
        )
    endif()

    install(TARGETS ${APP_TARGET} RUNTIME DESTINATION bin)
endif()
