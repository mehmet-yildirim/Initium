---
name: lang-c
description: C development standards — C17 baseline with opt-in C23 (GCC 15+/Clang 18+), CMake 4.x or Meson, clang-format, clang-tidy, cppcheck, GCC -fanalyzer, strict warnings, ASan/UBSan/MSan/TSan, libFuzzer/AFL++, hardening (_FORTIFY_SOURCE=3, -fhardened, PIE, full RELRO), checked integer arithmetic, MISRA C:2025 awareness, and Unity/CMocka/Criterion tests. Use when writing, reviewing, building, fuzzing, or hardening C sources and headers.
paths:
  - "**/*.c"
  - "**/*.h"
---

# C Development Standards

Covers C sources and headers. CMake files, presets, Conan and vcpkg manifests are owned by
`lang-cpp` (shared build rules live there); SAST pipelines by `security-sast`; CI wiring by
`devops-cicd`.

## Baseline

- Target **C17** (`-std=c17`, `CMAKE_C_STANDARD 17`, `C_EXTENSIONS OFF`) for portable code.
  Opt into **C23** (`-std=c23`) only when every toolchain supports it:
  - GCC 15+ defaults to `gnu23` (C23 essentially complete); GCC 16.x is current.
  - Clang 18+ accepts `-std=c23` (support still partial per the Clang status page); 23.1 is current.
  - MSVC has `/std:c11`, `/std:c17`, and `/std:clatest` only — **no `/std:c23`**. Use clang-cl
    if Windows builds need C23.
- Always pass `-std=` explicitly: the GCC 15 default switch to C23 breaks old code (`bool` is a
  keyword, `int f();` now means `int f(void)`).
- C23 features worth using when enabled: `nullptr`, `constexpr` objects, `typeof`,
  `[[nodiscard]]`, `static_assert` without header, `<stdckdint.h>` (`ckd_add/sub/mul`),
  fixed-underlying-type enums, `#embed` (GCC 15+, Clang 19+).
- MISRA projects: MISRA C:2025 (March 2025) covers C90/C99/C11/C18 only — stay on C11/C17.

## Toolchain

- Build: CMake 4.x with presets (see `lang-cpp`) or Meson; always emit
  `compile_commands.json` for tooling. No hand-written recursive Makefiles for new projects.
- Format: `clang-format` with a committed `.clang-format`; CI runs
  `clang-format --dry-run --Werror`.
- Warnings (GCC/Clang), treated as errors in CI:
  `-Wall -Wextra -Wpedantic -Werror -Wconversion -Wsign-conversion -Wshadow -Wformat=2
  -Wstrict-prototypes -Wmissing-prototypes -Wimplicit-fallthrough -Wvla -Wcast-qual
  -Wnull-dereference -Wdouble-promotion`. MSVC: `/W4 /WX /sdl /analyze`.
- Static analysis, all blocking in CI:
  - `clang-tidy` with `bugprone-*`, `cert-*`, `clang-analyzer-*`, `misc-*`,
    `readability-*`, `performance-*` (disable noisy checks explicitly with a reason).
  - `cppcheck --enable=warning,style,performance,portability --error-exitcode=1`.
  - GCC `-fanalyzer` on a dedicated CI job (interprocedural leak/double-free/UAF detection).
  - CodeQL or equivalent via `security-sast`.
- Sanitizer jobs (Clang or GCC, `-O1 -g -fno-omit-frame-pointer`):
  - ASan + UBSan together: `-fsanitize=address,undefined -fno-sanitize-recover=all`.
  - TSan alone (incompatible with ASan) for threaded code.
  - MSan alone, Clang/Linux only, requires all code (including deps) instrumented.
- Fuzzing: libFuzzer (`-fsanitize=fuzzer,address,undefined`) or AFL++ (`afl-clang-fast`)
  for every parser, decoder, and protocol handler. Commit seed corpora; run in CI for a fixed
  time budget and continuously in OSS-Fuzz/ClusterFuzzLite when public.

Read `reference/build-hardening.md` when writing compiler/linker flags, sanitizer presets, or
the CI analysis job.

## Structure

- Feature folders, hexagonal layering:
  `src/<feature>/domain/` (pure logic, no I/O) → `src/<feature>/ports/` (headers declaring
  function-pointer tables) → `src/<feature>/adapters/` (POSIX, sockets, DB clients, vendor SDKs).
  `src/main.c` only wires adapters into ports.
- Vendor SDKs and OS APIs are included **only** in adapters; domain headers include nothing
  beyond the standard library.
- Public headers: include guards or `#pragma once` consistently, include what you use, no
  definitions of objects in headers (`extern` declarations only), opaque structs
  (`typedef struct parser parser;`) to hide layout.
- One module per `.c`/`.h` pair; mark everything not in the header `static`.
- Prefix exported symbols with the module name (`orders_parse`, `orders_status`).

## Memory and Ownership

- Document ownership in every API that takes or returns a pointer: *borrowed*, *transferred*,
  or *caller-allocated*. Pair each constructor with a destructor (`x_create` / `x_destroy`);
  `x_destroy(NULL)` is a no-op.
- Prefer caller-provided buffers with explicit capacity (`char *buf, size_t cap`) over
  functions that allocate. Always pass sizes as `size_t` alongside pointers.
- Single-exit cleanup with `goto cleanup` for multi-resource functions; set freed pointers
  to `NULL`.
- Never use `gets`, `strcpy`, `strcat`, `sprintf`, `vsprintf`, or `scanf("%s")`. Use
  `snprintf` and check its return for truncation; use `memcpy` with validated lengths.
- Do not rely on Annex K (`*_s`) functions: glibc and musl do not ship them and MSVC's
  versions differ from the standard.
- No VLAs (`-Wvla`); no `alloca`. Bound every stack buffer by a named constant.
- Wipe secrets with a non-elidable call (`memset_explicit` in C23 where the libc provides it,
  `explicit_bzero`, or `SecureZeroMemory`), never plain `memset`.

## Integers and Bounds

- Validate every length/offset read from input before use; compare as
  `len > buf_len - offset` (after checking `offset <= buf_len`), never `offset + len > buf_len`.
- Checked arithmetic for sizes: `ckd_add/ckd_mul` from `<stdckdint.h>` (GCC 14+, Clang 18+,
  also available pre-C23 on those compilers) or `__builtin_*_overflow` as fallback.
- Use `<stdint.h>` fixed-width types for wire formats and `size_t` for sizes/indexes; avoid
  mixing signed and unsigned in comparisons (`-Wsign-conversion` catches it).
- Signed overflow is undefined behavior — UBSan must run in CI.

## Errors

- Return a module status enum (`typedef enum { ORDERS_OK = 0, ORDERS_ERR_... } orders_status;`)
  and write results through out-parameters. Reserve the return value for status.
- Mark status-returning functions `[[nodiscard]]` (C23) or
  `__attribute__((warn_unused_result))`.
- Translate `errno` at the adapter boundary into domain status codes immediately; read `errno`
  only right after a failing call.
- Never ignore return values of `malloc`, `fread`, `fwrite`, `close`, `snprintf`,
  `pthread_*`. `abort()` only for broken invariants, never for input errors.
- Map status codes to transport errors (HTTP, exit codes) in one table at the edge.

## Concurrency

- Prefer C11 `<threads.h>`/`<stdatomic.h>` only where the libc supports them; otherwise
  pthreads behind a small port.
- Every shared mutable object has one documented lock or is `_Atomic`; no lock-free code
  without TSan coverage and a written memory-ordering argument.
- Signal handlers call only async-signal-safe functions and set a `volatile sig_atomic_t` flag.

## Security

- Release builds use the hardening baseline (details in `reference/build-hardening.md`):
  `-O2 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fstack-protector-strong
  -fstack-clash-protection -fstrict-flex-arrays=3 -fPIE -pie -Wl,-z,relro,-z,now
  -Wl,-z,noexecstack`, plus `-fcf-protection=full` (x86-64) or
  `-mbranch-protection=standard` (AArch64). GCC 14+ `-fhardened` bundles most of these on
  GNU/Linux.
- Treat all external input as hostile: length-check, range-check, reject early.
- Never build shell commands from input; use `execve`/`posix_spawn` with an argument vector.
- Format strings are always literals (`-Wformat=2 -Werror=format-security`).
- Drop privileges early; open files with `O_CLOEXEC` and, when following untrusted paths,
  `O_NOFOLLOW`/`openat`.

## Embedded

- Freestanding targets: no heap after init (static pools), no recursion, bounded loops,
  `volatile` only for MMIO/ISR-shared data (not for thread sync).
- MISRA C:2025: enforce with a qualified checker, keep a deviation record per rule, and
  compile at C11/C17. Addendum 5 maps rules to the CWE memory-safety category.
- Keep hardware access in adapters (`hal_*`) so domain logic runs in host unit tests.

## Observability

- No `printf`/`fprintf(stderr, ...)` debugging in production code. Log through a `log_*` port
  that emits structured key=value or JSON lines with a level and request/trace id; the adapter
  targets stderr, syslog, or journald.
- Never log secrets, keys, or full payloads containing PII.
- There is no official OpenTelemetry C SDK: ship logs to the OpenTelemetry Collector, or wrap
  `opentelemetry-cpp` behind a C ABI adapter when traces/metrics are required.

## Testing

- Unit tests with **Unity** (+ CMock/Ceedling 1.0, strong for embedded), **CMocka 2.0**
  (C99+, mocks, TAP/JUnit output), or **Criterion**; one framework per repo. Run via CTest or
  `meson test`.
- Test domain code on the host with fake adapters (function-pointer tables).
- Every bug fix adds a regression test; every parser has a fuzz target and a seed corpus.
- Run the full suite under ASan+UBSan in CI; collect coverage with gcov/llvm-cov (gcovr).

Read `reference/patterns.md` when implementing a port/adapter pair, a bounded parser, error
handling with cleanup, a fuzz target, or a CMocka test.

## Supply Chain

- Pin third-party C code by version and checksum (CMake `FetchContent` with `URL_HASH`,
  Meson wraps with `source_hash`, or Conan/vcpkg lockfiles); record vendored sources and their
  licenses in the SBOM.
- SBOM: CMake 4.3+ has an experimental, UUID-gated `install(SBOM)` (SPDX 3.0.1); otherwise
  generate SPDX/CycloneDX from the build output with a scanner such as Syft.
- Track CVEs for vendored libraries (zlib, OpenSSL, libcurl) and rebuild on advisories.

_Versions verified September 2026._
