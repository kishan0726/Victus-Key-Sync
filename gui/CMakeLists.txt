cmake_minimum_required(VERSION 3.21)
project(victus-sync-gui LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(victus-sync-gui src/main.cpp)

qt_add_qml_module(victus-sync-gui
    URI VictusSync
    VERSION 1.0
    QML_FILES qml/Main.qml
    SOURCES include/config_manager.h src/config_manager.cpp
)

target_include_directories(victus-sync-gui PRIVATE include)
target_link_libraries(victus-sync-gui PRIVATE Qt6::Quick Qt6::QuickControls2)
