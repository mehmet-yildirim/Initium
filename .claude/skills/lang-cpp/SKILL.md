---
name: lang-cpp
description: Modern C++ standards — C++23 baseline with C++26 status, CMake 4.x presets, Conan 2 or vcpkg manifests, modules status, RAII and smart pointers, span/string_view lifetime rules, std::expected errors, ranges, jthread/atomics, C++ Core Guidelines + GSL, clang-tidy, sanitizers, libstdc++/libc++ hardening modes, fuzzing, GoogleTest/Catch2, spdlog/std::format, and OpenTelemetry C++. Use when writing, reviewing, building, or packaging C++ code, CMake files, or Conan/vcpkg manifests.
paths:
  - "**/*.cpp"
  - "**/*.cc"
  - "**/*.cxx"
  - "**/*.hpp"
  - "**/*.hh"
  - "**/*.hxx"
  - "**/*.ixx"
  - "**/*.cppm"
  - "**/CMakeLists.txt"
  - "**/*.cmake"
  - "**/CMakePresets.json"
  - "**/conanfile.*"
  - "**/vcpkg.json"
---

# Modern C++ Standards

Covers C++ code and the CMake/Conan/vcpkg build (shared with C projects). C-specific rules
(`.c`/`.h`) live in `lang-c`; SAST pipelines in `security-sast`; CI in `devops-cicd`.

## Baseline

- **C++23** for new code: `CMAKE_CXX_STANDARD 23`, `CXX_STANDARD_REQUIRED ON`,
  `CXX_EXTENSIONS OFF`. Minimum toolchains: GCC 14, Clang 18, MSVC (VS 2022 17.13+ /
  VS 2026) with `/std:c++23preview` or `/std:c++latest` — MSVC has no final `/std:c++23` switch.
- GCC 16 changed its default to `gnu++20`; never rely on compiler defaults.
- **C++26**: technically complete (WG21, March 2026), awaiting the ISO DIS ballot; contracts
  remain contested. Compilers are partial (GCC 16 reflection via `-std=c++26 -freflection`;
  Clang 23 `-std=c++2c`). Do not make C++26 the baseline; adopt individual features only behind
  `__cpp_*`/`__cpp_lib_*` feature-test macros.
- **Modules**: CMake 3.28+ builds named modules with Ninja and Visual Studio generators; GCC 16
  still labels modules experimental (`-fmodules`); `import std;` is UUID-gated experimental in
  CMake 4.4 (Ninja only). Use modules only for internal code when every target toolchain
  supports them; keep headers for public library APIs.

## Toolchain

- CMake 4.x + Ninja, driven by committed `CMakePresets.json` (configure/build/test/workflow
  presets). No in-source builds; no global `add_compile_options` for warnings — use an
  `INTERFACE` target.
- Dependencies: **vcpkg** manifest mode (`vcpkg.json` + `builtin-baseline`) or **Conan 2**
  (2.32 current; `conanfile.py` + `conan.lock`). Pick one per repo; never mix; never
  `FetchContent` a moving branch.
- Format with `clang-format` (committed config, CI `--dry-run --Werror`).
- `clang-tidy` blocking in CI: `bugprone-*`, `cppcoreguidelines-*`, `modernize-*`,
  `performance-*`, `concurrency-*`, `readability-*`, `clang-analyzer-*`, `misc-*`; suppress
  individual checks in `.clang-tidy` with a reason.
- Warnings: `-Wall -Wextra -Wpedantic -Wconversion -Wsign-conversion -Wshadow
  -Wnon-virtual-dtor -Wold-style-cast -Woverloaded-virtual -Wnull-dereference
  -Wimplicit-fallthrough` (+ GCC `-Wdangling-reference`); MSVC `/W4 /permissive- /analyze`.
  `-Werror` via `CMAKE_COMPILE_WARNING_AS_ERROR` in CI presets.
- Sanitizers, fuzzing, and hardening flags follow `lang-c` plus the C++ library modes below.

Read `reference/cmake-presets.md` when creating or editing `CMakeLists.txt`,
`CMakePresets.json`, `vcpkg.json`, or `conanfile.py`.

## Structure

- Feature folders with hexagonal layers:
  `src/<feature>/domain/` (value types, invariants, no I/O) →
  `src/<feature>/ports/` (abstract interfaces or concepts) →
  `src/<feature>/app/` (use cases depending only on ports) →
  `src/<feature>/adapters/` (DB, HTTP, queues, vendor SDKs) → `src/main.cpp` (composition root).
- Ports: an abstract class with a virtual destructor for runtime polymorphism, or a
  **concept** when the adapter is fixed at compile time (templates, zero overhead). Vendor SDK
  types never appear in port signatures.
- One CMake target per layer/feature; domain targets link nothing but the standard library.
- Headers: `#pragma once`, include what you use, no `using namespace` at namespace scope in
  headers, strong types for identifiers (`struct OrderId { std::uint64_t value; };`).

## Resource Management

- RAII for every resource (memory, files, sockets, locks, transactions). No naked
  `new`/`delete`, no `malloc`/`free`.
- `std::unique_ptr` by default; `std::shared_ptr` only for genuinely shared ownership; raw
  pointers and references are non-owning. Use `gsl::not_null` (GSL 4.2) where null is invalid.
- Rule of zero; if you must write one special member, define or delete all five.
- Moves and swaps are `noexcept`; destructors never throw.

## Lifetimes: views, spans, ranges

- `std::string_view`, `std::span`, and range views are **non-owning**. Never return one that
  refers to a local or temporary; never store one in a member unless the owner's lifetime is
  documented and longer.
- Pass `std::string_view`/`std::span<const T>` as parameters; return owning types.
- `std::string_view` is not null-terminated — convert to `std::string` before C APIs.
- Classic dangles: `std::string_view name = user.name();` when `name()` returns
  `std::string` by value; `std::span<const int> s = make_vector();`; a lambda capturing a view
  by value that outlives its owner. Range algorithms on rvalue ranges return
  `std::ranges::dangling` — treat that compile error as a design signal, not an obstacle.
- Enable `-Wdangling-reference` (GCC), `[[clang::lifetimebound]]` on accessors, and
  clang-tidy `bugprone-dangling-handle`; run ASan in CI to catch the rest.

## Errors

- Expected failures (validation, not-found, conflicts): return
  `std::expected<T, DomainError>` with a domain `enum class` or small error struct; chain with
  `and_then`/`transform`/`or_else`. Mark such functions `[[nodiscard]]`.
- Exceptions only for truly exceptional conditions (allocation failure, broken invariants,
  constructor failure) and never across module, thread, or C ABI boundaries; catch at the top
  of each thread/request.
- Map domain errors to HTTP/gRPC status in one function at the adapter edge.
- Never `catch (...) {}` silently; log and rethrow or convert.

## Concurrency

- `std::jthread` + `std::stop_token` for owned threads; never `detach()`.
- Protect shared state with `std::mutex` + `std::scoped_lock`; keep critical sections free of
  I/O and callbacks.
- `std::atomic` with default `seq_cst` unless a documented, TSan-tested reason exists for a
  weaker order.
- Prefer a task/executor abstraction (thread pool, Asio) behind a port; C++26
  `std::execution` is not yet broadly shipped.
- Every blocking call to a remote system has a timeout.

## Security

- Release builds use the `lang-c` hardening flags plus standard-library hardening:
  - libstdc++: `-D_GLIBCXX_ASSERTIONS` in production (not ABI-breaking); `_GLIBCXX_DEBUG`
    only in test builds (ABI-breaking).
  - libc++: `-D_LIBCPP_HARDENING_MODE=_LIBCPP_HARDENING_MODE_FAST` in production;
    `_EXTENSIVE` or `_DEBUG` in test builds.
  - C++26 standardizes library hardening; the modes above are the portable path today.
- Prefer `.at()` or bounds-checked `gsl::span` at trust boundaries; `std::span` is unchecked
  unless the library hardening mode is on.
- Validate all external input into domain types at the adapter boundary (schema/JSON
  validation before constructing domain objects).
- Parameterized queries only (driver prepared statements); never build SQL or shell commands
  with `std::format`.
- No secrets in source or logs; read from the environment or a secrets manager at startup.

## Observability

- Log via a logger port; default adapter **spdlog** (fmt or `std::format` backend) with a JSON
  sink in production. `std::print`/`std::cout` are for CLI output only, never service logs.
- **OpenTelemetry C++** (1.29.x; traces, metrics, logs all stable) behind an adapter; export
  OTLP to the Collector; propagate context across threads explicitly.
- Never log credentials, tokens, or PII; include trace/span ids in log records.

## Testing

- **GoogleTest 1.18** (requires C++17+) or **Catch2 3.16**; register with CTest
  (`gtest_discover_tests` / `catch_discover_tests`).
- Unit-test use cases against in-memory port fakes; integration-test adapters against real
  dependencies (Testcontainers or docker compose).
- CI matrix: GCC + Clang (+ MSVC if shipped), Debug with ASan+UBSan, a TSan job, and a
  hardened Release job.
- libFuzzer targets for every parser/deserializer; coverage with llvm-cov or gcovr.

Read `reference/patterns.md` when implementing ports (virtual or concept-based), use cases
with `std::expected`, error mapping, GoogleTest fakes, or fuzz targets.

## Supply Chain

- Lock dependencies (`vcpkg.json` baseline, `conan.lock`); review license and CVE status
  before adding a package; update via Renovate/Dependabot (`security-supply-chain`).
- Generate an SBOM per release (CMake 4.3+ experimental `install(SBOM)` SPDX 3.0.1, or a
  scanner such as Syft over the install tree).

_Versions verified September 2026._
