# CMake, Presets, vcpkg, and Conan Templates

Read when creating or editing `CMakeLists.txt`, `CMakePresets.json`, `vcpkg.json`, or
`conanfile.py`. Targets CMake 3.28+ (tested against the 4.x series).

## Top-level CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.28...4.4)
project(orders VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(CheckPIESupported)
check_pie_supported()

option(ORDERS_HARDENING "Enable release hardening flags" ON)
set(ORDERS_SANITIZE "" CACHE STRING "Semicolon list: address;undefined | thread")

add_library(orders_warnings INTERFACE)
target_compile_options(orders_warnings INTERFACE
  "$<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wconversion;-Wsign-conversion;-Wshadow;-Wnon-virtual-dtor;-Wold-style-cast;-Woverloaded-virtual;-Wnull-dereference;-Wimplicit-fallthrough>"
  "$<$<CXX_COMPILER_ID:GNU>:-Wdangling-reference>"
  "$<$<CXX_COMPILER_ID:MSVC>:/W4;/permissive-;/utf-8>")

add_library(orders_hardening INTERFACE)
if(ORDERS_HARDENING AND CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_compile_definitions(orders_hardening INTERFACE
    _GLIBCXX_ASSERTIONS
    _LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST)
  target_compile_options(orders_hardening INTERFACE
    "$<$<NOT:$<CONFIG:Debug>>:-U_FORTIFY_SOURCE;-D_FORTIFY_SOURCE=3>"
    -fstack-protector-strong -fstack-clash-protection)
  target_link_options(orders_hardening INTERFACE
    -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack)
endif()

if(ORDERS_SANITIZE)
  list(JOIN ORDERS_SANITIZE "," orders_sanitizers)
  target_compile_options(orders_hardening INTERFACE
    -fsanitize=${orders_sanitizers} -fno-omit-frame-pointer -fno-sanitize-recover=all)
  target_link_options(orders_hardening INTERFACE -fsanitize=${orders_sanitizers})
endif()

find_package(spdlog CONFIG REQUIRED)

add_library(orders_domain STATIC src/orders/domain/order.cpp)
target_include_directories(orders_domain PUBLIC src)
target_link_libraries(orders_domain PRIVATE orders_warnings orders_hardening)

add_library(orders_app STATIC src/orders/app/change_quantity.cpp)
target_link_libraries(orders_app PUBLIC orders_domain PRIVATE orders_warnings orders_hardening)

add_executable(orders_api src/main.cpp src/orders/adapters/http_handler.cpp)
target_link_libraries(orders_api PRIVATE orders_app spdlog::spdlog orders_warnings orders_hardening)

include(CTest)
if(BUILD_TESTING)
  add_subdirectory(tests)
endif()
```

`tests/CMakeLists.txt`:

```cmake
find_package(GTest CONFIG REQUIRED)
include(GoogleTest)

add_executable(orders_tests change_quantity_test.cpp)
target_link_libraries(orders_tests PRIVATE orders_app GTest::gtest_main orders_warnings orders_hardening)
gtest_discover_tests(orders_tests)
```

Modules (optional, internal code only): add sources with
`target_sources(orders_domain PUBLIC FILE_SET CXX_MODULES FILES src/orders/domain/order.cppm)`
and build with Ninja. Do not enable `import std;` in shared code while it is experimental.

## CMakePresets.json (schema version 6, CMake 3.25+)

```json
{
  "version": 6,
  "cmakeMinimumRequired": { "major": 3, "minor": 28, "patch": 0 },
  "configurePresets": [
    {
      "name": "base",
      "hidden": true,
      "generator": "Ninja",
      "binaryDir": "${sourceDir}/build/${presetName}",
      "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
      "cacheVariables": { "CMAKE_EXPORT_COMPILE_COMMANDS": "ON" }
    },
    {
      "name": "debug",
      "inherits": "base",
      "cacheVariables": { "CMAKE_BUILD_TYPE": "Debug" }
    },
    {
      "name": "ci-asan",
      "inherits": "base",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "ORDERS_SANITIZE": "address;undefined",
        "CMAKE_COMPILE_WARNING_AS_ERROR": "ON"
      }
    },
    {
      "name": "ci-release",
      "inherits": "base",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "RelWithDebInfo",
        "ORDERS_HARDENING": "ON",
        "CMAKE_COMPILE_WARNING_AS_ERROR": "ON"
      }
    }
  ],
  "buildPresets": [
    { "name": "debug", "configurePreset": "debug" },
    { "name": "ci-asan", "configurePreset": "ci-asan" },
    { "name": "ci-release", "configurePreset": "ci-release" }
  ],
  "testPresets": [
    { "name": "ci-asan", "configurePreset": "ci-asan", "output": { "outputOnFailure": true } },
    { "name": "ci-release", "configurePreset": "ci-release", "output": { "outputOnFailure": true } }
  ],
  "workflowPresets": [
    {
      "name": "ci-asan",
      "steps": [
        { "type": "configure", "name": "ci-asan" },
        { "type": "build", "name": "ci-asan" },
        { "type": "test", "name": "ci-asan" }
      ]
    }
  ]
}
```

Run with `cmake --workflow --preset ci-asan`. Keep machine-specific settings in the
uncommitted `CMakeUserPresets.json`. With Conan, drop `toolchainFile` and point presets at the
`conan_toolchain.cmake` generated by `conan install` (or include Conan's generated
`CMakePresets.json`).

## vcpkg.json (manifest mode)

```json
{
  "name": "orders",
  "version-semver": "0.1.0",
  "dependencies": ["spdlog", "ms-gsl", "opentelemetry-cpp", "gtest"]
}
```

Add the baseline with `vcpkg x-update-baseline --add-initial-baseline` (writes
`builtin-baseline`, a commit of the vcpkg registry); pin individual packages with
`overrides` only when required. Enable OTLP exporters via port features
(`{ "name": "opentelemetry-cpp", "features": ["otlp-http"] }`) after checking the port's
feature list.

## conanfile.py (Conan 2)

```python
from conan import ConanFile
from conan.tools.cmake import cmake_layout


class OrdersRecipe(ConanFile):
    settings = "os", "compiler", "build_type", "arch"
    generators = "CMakeToolchain", "CMakeDeps"

    def requirements(self):
        self.requires("spdlog/[>=1.14 <2]")
        self.requires("ms-gsl/[>=4.0 <5]")

    def build_requirements(self):
        self.test_requires("gtest/[>=1.15 <2]")

    def layout(self):
        cmake_layout(self)
```

Commit `conan.lock` (`conan lock create .`) so version ranges resolve identically in CI; set
`compiler.cppstd=23` in the profile.
