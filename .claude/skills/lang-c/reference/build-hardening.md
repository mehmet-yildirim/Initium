# C Build, Hardening, and Analysis Recipes

Read when writing compiler/linker flags, sanitizer or fuzzing builds, or the CI analysis job.
Sources: OpenSSF *Compiler Options Hardening Guide for C and C++*, GCC 16 and LLVM 23 docs.

## Flag sets (GCC 14+ / Clang 18+, GNU/Linux)

| Purpose | Flags | Notes |
|---|---|---|
| Warnings | `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow -Wformat=2 -Wstrict-prototypes -Wmissing-prototypes -Wimplicit-fallthrough -Wvla -Wcast-qual -Wnull-dereference -Wdouble-promotion` | Add `-Werror` in CI, not in released build scripts consumed by distros |
| Fortify | `-U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3` | Needs `-O1`+; `=3` needs GCC 12+/Clang 9+ and a libc that implements level 3 |
| Stack | `-fstack-protector-strong -fstack-clash-protection` | |
| Flex arrays | `-fstrict-flex-arrays=3` | GCC 13+, Clang 16+; only `[]` members are unbounded |
| Uninit | `-ftrivial-auto-var-init=zero` | GCC 12+, Clang 16+ |
| CFI (x86-64) | `-fcf-protection=full` | Intel CET |
| CFI (AArch64) | `-mbranch-protection=standard` | PAC + BTI |
| PIE | `-fPIE` (compile) + `-pie` (link) | |
| Linker | `-Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed` | Full RELRO |
| Umbrella | `-fhardened` (GCC 14+, GNU/Linux only) | Enables `_FORTIFY_SOURCE=3` (`=2` on glibc < 2.35), `_GLIBCXX_ASSERTIONS`, `-ftrivial-auto-var-init=zero`, PIE, full RELRO, `-fstack-protector-strong`, `-fstack-clash-protection`, `-fcf-protection=full` (x86). Only sets options not already given; list with `gcc --help=hardened` |

Distro compilers (Ubuntu 24.04+, Fedora) may already predefine `_FORTIFY_SOURCE`; the
`-U_FORTIFY_SOURCE` prefix avoids redefinition warnings, and `-fhardened` warns
(`-Whardened`) when it skips an option you set explicitly.

MSVC equivalents: `/W4 /WX /sdl /guard:cf /analyze /DYNAMICBASE /HIGHENTROPYVA /NXCOMPAT`
(linker flags go to `link.exe`); ASan via `/fsanitize=address`.

## CMake snippet (C project)

```cmake
cmake_minimum_required(VERSION 3.28...4.4)
project(orders LANGUAGES C VERSION 0.1.0)

set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
include(CheckPIESupported)
check_pie_supported()

option(ORDERS_HARDENING "Enable release hardening flags" ON)
set(ORDERS_SANITIZE "" CACHE STRING "Semicolon list: address;undefined | thread | memory")

add_library(orders_flags INTERFACE)
target_compile_options(orders_flags INTERFACE
  "$<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wconversion;-Wsign-conversion;-Wshadow;-Wformat=2;-Wstrict-prototypes;-Wmissing-prototypes;-Wimplicit-fallthrough;-Wvla>"
  "$<$<C_COMPILER_ID:MSVC>:/W4;/sdl>")

if(ORDERS_HARDENING AND CMAKE_C_COMPILER_ID MATCHES "GNU|Clang" AND CMAKE_SYSTEM_NAME STREQUAL "Linux")
  target_compile_options(orders_flags INTERFACE
    "$<$<NOT:$<CONFIG:Debug>>:-U_FORTIFY_SOURCE;-D_FORTIFY_SOURCE=3>"
    -fstack-protector-strong -fstack-clash-protection -fstrict-flex-arrays=3)
  target_link_options(orders_flags INTERFACE
    -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack)
endif()

if(ORDERS_SANITIZE)
  list(JOIN ORDERS_SANITIZE "," orders_sanitizers)
  target_compile_options(orders_flags INTERFACE
    -fsanitize=${orders_sanitizers} -fno-omit-frame-pointer -fno-sanitize-recover=all)
  target_link_options(orders_flags INTERFACE -fsanitize=${orders_sanitizers})
endif()

add_library(orders_core STATIC src/orders/domain/record.c)
target_include_directories(orders_core PUBLIC include)
target_link_libraries(orders_core PRIVATE orders_flags)
```

Add `-Werror` from the CI preset (`CMAKE_COMPILE_WARNING_AS_ERROR=ON`, CMake 3.24+) rather than
hard-coding it. Put configure/build/test presets in `CMakePresets.json` (template in
`lang-cpp/reference/cmake-presets.md`).

## Meson equivalent

```meson
project('orders', 'c',
  version: '0.1.0',
  default_options: ['c_std=c17', 'warning_level=3', 'werror=true', 'b_pie=true'])

add_project_arguments(
  '-Wconversion', '-Wsign-conversion', '-Wshadow', '-Wformat=2', '-Wvla',
  language: 'c')
```

Sanitizers: `meson setup build-asan -Db_sanitize=address,undefined -Db_lundef=false`.

## Sanitizer matrix (CI)

| Job | Compiler | Flags | Catches |
|---|---|---|---|
| asan-ubsan | Clang or GCC | `-fsanitize=address,undefined -fno-sanitize-recover=all` | OOB, UAF, leaks, UB |
| tsan | Clang or GCC | `-fsanitize=thread` | Data races |
| msan | Clang (Linux) | `-fsanitize=memory -fsanitize-memory-track-origins` | Uninitialized reads; all deps must be instrumented |

Environment: `ASAN_OPTIONS=detect_leaks=1:abort_on_error=1`,
`UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1`.

## Fuzzing

- libFuzzer: `clang -g -O1 -fsanitize=fuzzer,address,undefined fuzz_record.c src/...`;
  run `./fuzz_record -max_total_time=300 corpus/`.
- AFL++: build with `afl-clang-fast` (or `afl-clang-lto`), run
  `afl-fuzz -i corpus -o findings -- ./target @@`.
- Keep the harness deterministic, free of global state, and fast (< 1 ms per input).
- Minimize crashers into regression tests under `tests/regressions/`.

## CI analysis job (commands)

```bash
cmake --preset ci-release
cmake --build --preset ci-release
clang-format --dry-run --Werror $(git ls-files '*.c' '*.h')
run-clang-tidy -p build/ci-release -quiet
cppcheck --project=build/ci-release/compile_commands.json \
  --enable=warning,style,performance,portability --error-exitcode=1 --inline-suppr
cmake --preset ci-asan && cmake --build --preset ci-asan && ctest --preset ci-asan
```

GCC analyzer job: add `-fanalyzer` to a GCC build (slow; run on changed files or nightly).
Pin third-party GitHub Actions by commit SHA (see `devops-cicd`).
