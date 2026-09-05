cmake_minimum_required(VERSION 3.16)
project(kryptic-test-runner LANGUAGES CXX)

include(FetchContent)
FetchContent_Declare(
    kryptic-daemon-client
    GIT_REPOSITORY https://github.com/dev-kryptic/Kryptic.Cpp.git
    GIT_TAG v1.0.0
)
FetchContent_MakeAvailable(kryptic-daemon-client)

add_executable(kryptic-test-runner main.cpp)
target_link_libraries(kryptic-test-runner PRIVATE kryptic-daemon-client)
target_compile_features(kryptic-test-runner PRIVATE cxx_std_17)
