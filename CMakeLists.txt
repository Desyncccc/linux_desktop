cmake_minimum_required(VERSION 3.22)
project(vitrum VERSION 0.1.0 DESCRIPTION "Vitrum desktop shell" LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(GNUInstallDirs)

option(VITRUM_BUILD_TESTS "Build unit tests" ON)
option(VITRUM_WITH_PAM "Use PAM for the lock screen" ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui DBus Qml Quick QuickControls2 WaylandCompositor ShaderTools Svg)
qt_standard_project_setup()

# Core logic without GUI dependencies, shared with the tests.
add_library(vitrumcore STATIC src/desktopentry.cpp src/desktopentry.h)
target_link_libraries(vitrumcore PUBLIC Qt6::Core)
target_include_directories(vitrumcore PUBLIC src)

qt_add_executable(vitrum src/main.cpp src/iconprovider.cpp src/iconprovider.h)
target_compile_definitions(vitrum PRIVATE VITRUM_VERSION="${PROJECT_VERSION}")
target_link_libraries(vitrum PRIVATE vitrumcore Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick Qt6::QuickControls2
                                     Qt6::WaylandCompositor Qt6::Svg)

if(VITRUM_WITH_PAM)
    find_library(PAM_LIBRARY pam)
    find_path(PAM_INCLUDE_DIR security/pam_appl.h)
    if(PAM_LIBRARY AND PAM_INCLUDE_DIR)
        set(VITRUM_PAM ON)
        message(STATUS "Lock screen: PAM enabled")
    else()
        message(WARNING "PAM not found: lock screen will defer to loginctl")
    endif()
endif()

file(GLOB_RECURSE VITRUM_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml)
file(GLOB VITRUM_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS icons/*.svg)
set_source_files_properties(qml/Theme.qml qml/Shell.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# C++ backends exposed to QML as the "Vitrum.Core" module. Kept separate from
# the QML shell module so QML singletons don't form import cycles.
qt_add_library(vitrumbackend STATIC)
target_compile_definitions(vitrumbackend PRIVATE VITRUM_VERSION="${PROJECT_VERSION}")
target_link_libraries(vitrumbackend PUBLIC vitrumcore Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Quick Qt6::WaylandCompositor)
qt6_generate_wayland_protocol_server_sources(vitrumbackend FILES ${CMAKE_CURRENT_SOURCE_DIR}/protocols/server-decoration.xml)
target_include_directories(vitrumbackend PUBLIC src ${CMAKE_CURRENT_BINARY_DIR})
qt_add_qml_module(vitrumbackend
    URI Vitrum.Core
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    SOURCES
        src/appmodel.cpp src/appmodel.h
        src/authenticator.cpp src/authenticator.h
        src/compat.cpp src/compat.h
        src/files.cpp src/files.h
        src/keyfilter.cpp src/keyfilter.h
        src/launcher.cpp src/launcher.h
        src/notifications.cpp src/notifications.h
        src/prefs.cpp src/prefs.h
        src/serverdecoration.cpp src/serverdecoration.h
        src/session.cpp src/session.h
        src/systemstatus.cpp src/systemstatus.h
)

qt_add_qml_module(vitrum
    URI Vitrum
    VERSION 1.0
    RESOURCE_PREFIX /qt/qml
    QML_FILES ${VITRUM_QML}
    RESOURCES ${VITRUM_ICONS}
    IMPORTS Vitrum.Core
)
target_link_libraries(vitrum PRIVATE vitrumbackend vitrumbackendplugin)
# Qt 6.4's AOT-compiled bindings can spin forever on singleton lookups inside
# dynamically created components; bytecode-only caching avoids that.
set_target_properties(vitrum PROPERTIES QT_QMLCACHEGEN_ARGUMENTS "--only-bytecode")

qt_add_shaders(vitrum "vitrum_shaders"
    PREFIX /qt/qml/Vitrum
    FILES shaders/glass.frag shaders/wallpaper.frag
)

if(VITRUM_PAM)
    target_compile_definitions(vitrumbackend PRIVATE VITRUM_HAVE_PAM)
    target_include_directories(vitrumbackend PRIVATE ${PAM_INCLUDE_DIR})
    target_link_libraries(vitrumbackend PRIVATE ${PAM_LIBRARY})
endif()

install(TARGETS vitrum RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(PROGRAMS data/vitrum-session data/vitrum-open DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/vitrum-open.desktop data/vitrum-mimeapps.list DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES data/vitrum.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions)
install(FILES data/vitrum-portals.conf DESTINATION ${CMAKE_INSTALL_DATADIR}/xdg-desktop-portal)
install(FILES data/pam.d/vitrum DESTINATION ${CMAKE_INSTALL_FULL_SYSCONFDIR}/pam.d)
install(FILES data/vitrum.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps)

if(VITRUM_BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Packaging: `cpack -G DEB` produces an installable .deb.
set(CPACK_PACKAGE_NAME vitrum)
set(CPACK_PACKAGE_CONTACT "Vitrum maintainers")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Glass-styled desktop shell and Wayland compositor")
set(CPACK_PACKAGING_INSTALL_PREFIX /usr)
set(CPACK_DEBIAN_PACKAGE_SHLIBDEPS ON)
set(CPACK_DEBIAN_PACKAGE_DEPENDS "qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-layouts, qml6-module-qtquick-window, qml6-module-qtquick-templates, qml6-module-qtwayland-compositor, qml6-module-qt5compat-graphicaleffects, qml6-module-qt-labs-folderlistmodel, qml6-module-qtqml-workerscript, qt6-qpa-plugins, xdg-utils")
set(CPACK_DEBIAN_PACKAGE_RECOMMENDS "foot | x-terminal-emulator, wireplumber, network-manager, wine, icoutils, xinit, xserver-xorg-core, dbus-user-session")
set(CPACK_DEBIAN_PACKAGE_SUGGESTS "default-jre")
set(CPACK_DEBIAN_FILE_NAME DEB-DEFAULT)
set(CPACK_DEBIAN_PACKAGE_SECTION x11)
include(CPack)
