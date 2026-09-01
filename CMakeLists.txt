cmake_minimum_required(VERSION 3.15)
project(MediaBridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(MediaBridge main.cpp)

target_link_libraries(MediaBridge PRIVATE
    ws2_32
    ole32
    wininet
    gdiplus
)
