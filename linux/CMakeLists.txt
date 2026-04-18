cmake_minimum_required(VERSION 3.16)

project(RunRatLinux
  VERSION 1.0.3
  DESCRIPTION "Linux tray activity monitor with a running rat"
  LANGUAGES C
)

include(GNUInstallDirs)

option(RUNRAT_ENABLE_SOURCE_ICON_DIR "Enable source-tree icon fallback for development builds" ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)
pkg_check_modules(APPINDICATOR REQUIRED ayatana-appindicator3-0.1)

add_executable(runrat src/main.c)
target_compile_features(runrat PRIVATE c_std_11)
target_compile_options(runrat PRIVATE -Wall -Wextra -Wpedantic)
target_include_directories(runrat PRIVATE ${GTK3_INCLUDE_DIRS} ${APPINDICATOR_INCLUDE_DIRS})
target_link_directories(runrat PRIVATE ${GTK3_LIBRARY_DIRS} ${APPINDICATOR_LIBRARY_DIRS})
target_link_libraries(runrat PRIVATE ${GTK3_LIBRARIES} ${APPINDICATOR_LIBRARIES})
target_compile_options(runrat PRIVATE ${GTK3_CFLAGS_OTHER} ${APPINDICATOR_CFLAGS_OTHER})
target_compile_definitions(runrat PRIVATE
  RUNRAT_VERSION="${PROJECT_VERSION}"
  RUNRAT_ICON_DIR="${CMAKE_INSTALL_FULL_DATADIR}/runrat/icons"
)

if(RUNRAT_ENABLE_SOURCE_ICON_DIR)
  target_compile_definitions(runrat PRIVATE RUNRAT_SOURCE_ICON_DIR="${CMAKE_CURRENT_SOURCE_DIR}/assets")
endif()

install(TARGETS runrat RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(DIRECTORY assets/ DESTINATION ${CMAKE_INSTALL_DATADIR}/runrat/icons FILES_MATCHING PATTERN "*.svg")
install(FILES assets/runrat0.svg DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps RENAME runrat.svg)
install(FILES packaging/runrat.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES ../LICENSE DESTINATION ${CMAKE_INSTALL_DATADIR}/licenses/runrat)
