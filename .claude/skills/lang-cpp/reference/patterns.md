# C++23 Patterns: Ports, std::expected, Error Mapping, Tests, Fuzzing

Read when implementing a port (virtual or concept-based), a use case returning
`std::expected`, adapter-edge error mapping, GoogleTest fakes, or a fuzz target.
Compiles with GCC 14+, Clang 18+ (libc++ or libstdc++), MSVC `/std:c++latest`.

## Domain

```cpp
// src/orders/domain/order.hpp
#pragma once
#include <cstdint>
#include <string>

namespace orders::domain {

struct OrderId {
    std::uint64_t value;
    friend bool operator==(OrderId, OrderId) = default;
};

enum class OrderError { not_found, invalid_quantity, storage_unavailable };

struct Order {
    OrderId id;
    std::string sku;
    std::int32_t quantity;
};

}  // namespace orders::domain
```

## Port: runtime interface and compile-time concept

```cpp
// src/orders/ports/order_repository.hpp
#pragma once
#include <concepts>
#include <expected>
#include "orders/domain/order.hpp"

namespace orders::ports {

class OrderRepository {
public:
    virtual ~OrderRepository() = default;
    [[nodiscard]] virtual std::expected<domain::Order, domain::OrderError> find(domain::OrderId id) = 0;
    [[nodiscard]] virtual std::expected<void, domain::OrderError> save(const domain::Order& order) = 0;
};

// Same contract for template-based wiring (no vtable).
template <typename T>
concept OrderRepositoryLike = requires(T& repo, domain::OrderId id, const domain::Order& order) {
    { repo.find(id) } -> std::same_as<std::expected<domain::Order, domain::OrderError>>;
    { repo.save(order) } -> std::same_as<std::expected<void, domain::OrderError>>;
};

}  // namespace orders::ports
```

## Use case with monadic std::expected

```cpp
// src/orders/app/change_quantity.hpp
#pragma once
#include <cstdint>
#include <expected>
#include "orders/ports/order_repository.hpp"

namespace orders::app {

class ChangeQuantity {
public:
    explicit ChangeQuantity(ports::OrderRepository& repository) : repository_{repository} {}

    [[nodiscard]] std::expected<domain::Order, domain::OrderError>
    operator()(domain::OrderId id, std::int32_t quantity) {
        if (quantity < 1 || quantity > MAX_QUANTITY) {
            return std::unexpected{domain::OrderError::invalid_quantity};
        }
        return repository_.find(id).and_then(
            [&](domain::Order order) -> std::expected<domain::Order, domain::OrderError> {
                order.quantity = quantity;
                return repository_.save(order).transform([&] { return order; });
            });
    }

private:
    static constexpr std::int32_t MAX_QUANTITY = 10'000;
    ports::OrderRepository& repository_;
};

}  // namespace orders::app
```

## Error mapping at the adapter edge

```cpp
// src/orders/adapters/http_status.hpp
#pragma once
#include <string_view>
#include <utility>
#include "orders/domain/order.hpp"

namespace orders::adapters {

struct HttpError {
    int status;
    std::string_view code;  // points at string literals only: static lifetime
};

constexpr HttpError to_http(domain::OrderError error) noexcept {
    switch (error) {
        case domain::OrderError::not_found: return {404, "not_found"};
        case domain::OrderError::invalid_quantity: return {422, "invalid_quantity"};
        case domain::OrderError::storage_unavailable: return {503, "storage_unavailable"};
    }
    std::unreachable();
}

}  // namespace orders::adapters
```

## Logger port with spdlog adapter

```cpp
// src/platform/logger.hpp
#pragma once
#include <string_view>

namespace platform {

class Logger {
public:
    virtual ~Logger() = default;
    virtual void info(std::string_view event, std::string_view detail) = 0;
    virtual void error(std::string_view event, std::string_view detail) = 0;
};

}  // namespace platform
```

```cpp
// src/platform/spdlog_logger.hpp
#pragma once
#include <memory>
#include <utility>
#include <spdlog/spdlog.h>
#include "platform/logger.hpp"

namespace platform {

class SpdlogLogger final : public Logger {
public:
    explicit SpdlogLogger(std::shared_ptr<spdlog::logger> sink) : sink_{std::move(sink)} {}
    void info(std::string_view event, std::string_view detail) override {
        sink_->info("event={} detail={}", event, detail);
    }
    void error(std::string_view event, std::string_view detail) override {
        sink_->error("event={} detail={}", event, detail);
    }

private:
    std::shared_ptr<spdlog::logger> sink_;
};

}  // namespace platform
```

Configure a JSON pattern or a JSON sink in `main.cpp`; never pass user-controlled strings as
the format string.

## GoogleTest with an in-memory fake

```cpp
// tests/change_quantity_test.cpp
#include <gtest/gtest.h>
#include <unordered_map>
#include "orders/app/change_quantity.hpp"

namespace {

using orders::domain::Order;
using orders::domain::OrderError;
using orders::domain::OrderId;

class InMemoryOrders final : public orders::ports::OrderRepository {
public:
    std::expected<Order, OrderError> find(OrderId id) override {
        auto it = rows_.find(id.value);
        if (it == rows_.end()) return std::unexpected{OrderError::not_found};
        return it->second;
    }
    std::expected<void, OrderError> save(const Order& order) override {
        rows_.insert_or_assign(order.id.value, order);
        return {};
    }
    std::unordered_map<std::uint64_t, Order> rows_;
};

TEST(ChangeQuantity, RejectsNonPositiveQuantity) {
    InMemoryOrders repository;
    orders::app::ChangeQuantity change{repository};

    auto result = change(OrderId{1}, 0);

    ASSERT_FALSE(result.has_value());
    EXPECT_EQ(result.error(), OrderError::invalid_quantity);
}

TEST(ChangeQuantity, UpdatesExistingOrder) {
    InMemoryOrders repository;
    repository.rows_.insert_or_assign(1, Order{OrderId{1}, "SKU-1", 1});
    orders::app::ChangeQuantity change{repository};

    auto result = change(OrderId{1}, 5);

    ASSERT_TRUE(result.has_value());
    EXPECT_EQ(repository.rows_.at(1).quantity, 5);
}

}  // namespace
```

## libFuzzer target

```cpp
// fuzz/order_json_fuzz.cpp — build with -fsanitize=fuzzer,address,undefined
#include <cstddef>
#include <cstdint>
#include <string_view>
#include "orders/adapters/order_json.hpp"

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t* data, std::size_t size) {
    std::string_view input{reinterpret_cast<const char*>(data), size};
    [[maybe_unused]] auto parsed = orders::adapters::parse_order_json(input);
    return 0;
}
```

`parse_order_json` must return `std::expected` (never throw on malformed input) so the fuzzer
explores error paths without aborting.
