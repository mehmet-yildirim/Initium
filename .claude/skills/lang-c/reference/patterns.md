# C Patterns: Ports, Bounded Parsing, Cleanup, Fuzzing, Tests

Read when implementing a port/adapter pair, parsing untrusted bytes, writing multi-resource
cleanup, adding a fuzz target, or writing a CMocka test. All samples compile as C17.

## Status codes and a port (header)

```c
/* include/orders/orders.h */
#ifndef ORDERS_ORDERS_H
#define ORDERS_ORDERS_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    ORDERS_OK = 0,
    ORDERS_ERR_INVALID_ARG,
    ORDERS_ERR_NOT_FOUND,
    ORDERS_ERR_NO_MEMORY,
    ORDERS_ERR_IO,
} orders_status;

enum { ORDERS_SKU_CAP = 32 };

typedef struct {
    uint64_t id;
    char sku[ORDERS_SKU_CAP];
    int32_t quantity;
} orders_order;

/* Port: implemented by adapters (Postgres, file, in-memory fake). */
typedef struct orders_store orders_store;

typedef struct {
    orders_status (*find)(orders_store *self, uint64_t id, orders_order *out);
    orders_status (*save)(orders_store *self, const orders_order *order);
} orders_store_ops;

typedef struct {
    const orders_store_ops *ops;
    orders_store *self;
} orders_store_port;

/* Domain use case: depends only on the port. */
__attribute__((warn_unused_result))
orders_status orders_change_quantity(orders_store_port store, uint64_t id, int32_t quantity);

#endif
```

## Use case (domain)

```c
/* src/orders/domain/change_quantity.c */
#include "orders/orders.h"

enum { ORDERS_MAX_QUANTITY = 10000 };

orders_status orders_change_quantity(orders_store_port store, uint64_t id, int32_t quantity)
{
    if (store.ops == NULL) return ORDERS_ERR_INVALID_ARG;
    if (quantity < 1 || quantity > ORDERS_MAX_QUANTITY) return ORDERS_ERR_INVALID_ARG;

    orders_order order;
    orders_status status = store.ops->find(store.self, id, &order);
    if (status != ORDERS_OK) return status;

    order.quantity = quantity;
    return store.ops->save(store.self, &order);
}
```

## Bounded parser for untrusted input

```c
/* src/orders/domain/record.c */
#include "orders/record.h"

/* Reads a big-endian u16 length-prefixed field; advances *offset on success. */
orders_status orders_read_field(const uint8_t *buf, size_t buf_len, size_t *offset,
                                const uint8_t **field, size_t *field_len)
{
    if (buf == NULL || offset == NULL || field == NULL || field_len == NULL) {
        return ORDERS_ERR_INVALID_ARG;
    }
    if (*offset > buf_len || buf_len - *offset < 2) return ORDERS_ERR_INVALID_ARG;

    size_t len = ((size_t)buf[*offset] << 8) | (size_t)buf[*offset + 1];
    size_t start = *offset + 2;
    if (len > buf_len - start) return ORDERS_ERR_INVALID_ARG;

    *field = buf + start;
    *field_len = len;
    *offset = start + len;
    return ORDERS_OK;
}
```

Size arithmetic with overflow checks (GCC 14+/Clang 18+ ship `<stdckdint.h>`):

```c
#include <stdckdint.h>
#include <stdlib.h>

orders_status orders_alloc_records(size_t count, size_t record_size, void **out)
{
    if (out == NULL) return ORDERS_ERR_INVALID_ARG;
    *out = NULL;
    size_t bytes = 0;
    if (ckd_mul(&bytes, count, record_size) || bytes == 0) return ORDERS_ERR_INVALID_ARG;
    *out = malloc(bytes);
    return *out == NULL ? ORDERS_ERR_NO_MEMORY : ORDERS_OK;
}
```

## Single-exit cleanup and errno translation (adapter)

```c
/* src/orders/adapters/file_config.c */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include "orders/config.h"

enum { CONFIG_MAX_BYTES = 64 * 1024 };

orders_status orders_load_config(const char *path, orders_config *out)
{
    orders_status status = ORDERS_ERR_IO;
    FILE *file = NULL;
    char *buf = NULL;
    size_t read_bytes = 0;

    if (path == NULL || out == NULL) return ORDERS_ERR_INVALID_ARG;

    file = fopen(path, "rb");
    if (file == NULL) {
        status = (errno == ENOENT) ? ORDERS_ERR_NOT_FOUND : ORDERS_ERR_IO;
        goto cleanup;
    }
    buf = malloc(CONFIG_MAX_BYTES);
    if (buf == NULL) {
        status = ORDERS_ERR_NO_MEMORY;
        goto cleanup;
    }
    read_bytes = fread(buf, 1, CONFIG_MAX_BYTES, file);
    if (ferror(file)) goto cleanup;

    status = orders_config_parse(buf, read_bytes, out);

cleanup:
    free(buf);
    if (file != NULL && fclose(file) != 0 && status == ORDERS_OK) status = ORDERS_ERR_IO;
    return status;
}
```

## libFuzzer target

```c
/* fuzz/fuzz_record.c — build: clang -g -O1 -fsanitize=fuzzer,address,undefined */
#include <stddef.h>
#include <stdint.h>
#include "orders/record.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    size_t offset = 0;
    const uint8_t *field = NULL;
    size_t field_len = 0;
    while (orders_read_field(data, size, &offset, &field, &field_len) == ORDERS_OK) {
        /* Each iteration advances offset by at least 2, so the loop terminates. */
    }
    return 0;
}
```

## CMocka 2.0 test with a fake adapter

```c
/* tests/test_change_quantity.c */
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include <setjmp.h>
#include <cmocka.h>
#include "orders/orders.h"

struct orders_store {
    orders_order row;
    int saves;
};

static orders_status fake_find(orders_store *self, uint64_t id, orders_order *out)
{
    if (id != self->row.id) return ORDERS_ERR_NOT_FOUND;
    *out = self->row;
    return ORDERS_OK;
}

static orders_status fake_save(orders_store *self, const orders_order *order)
{
    self->row = *order;
    self->saves++;
    return ORDERS_OK;
}

static const orders_store_ops FAKE_OPS = { .find = fake_find, .save = fake_save };

static void rejects_zero_quantity(void **state)
{
    (void)state;
    orders_store fake = { .row = { .id = 1, .sku = "SKU-1", .quantity = 1 } };
    orders_store_port port = { .ops = &FAKE_OPS, .self = &fake };

    assert_int_equal(orders_change_quantity(port, 1, 0), ORDERS_ERR_INVALID_ARG);
    assert_int_equal(fake.saves, 0);
}

static void updates_existing_order(void **state)
{
    (void)state;
    orders_store fake = { .row = { .id = 1, .sku = "SKU-1", .quantity = 1 } };
    orders_store_port port = { .ops = &FAKE_OPS, .self = &fake };

    assert_int_equal(orders_change_quantity(port, 1, 5), ORDERS_OK);
    assert_int_equal(fake.row.quantity, 5);
}

int main(void)
{
    const struct CMUnitTest tests[] = {
        cmocka_unit_test(rejects_zero_quantity),
        cmocka_unit_test(updates_existing_order),
    };
    return cmocka_run_group_tests(tests, NULL, NULL);
}
```
