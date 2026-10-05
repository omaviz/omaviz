cmake_minimum_required(VERSION 3.21)
project(omaviz_controls LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Quick Test)
add_executable(controls-test main.cpp)
target_link_libraries(controls-test PRIVATE Qt6::Quick Qt6::Test)

add_executable(desktop-controls-test desktop.cpp)
target_link_libraries(desktop-controls-test PRIVATE Qt6::Quick Qt6::Test)
