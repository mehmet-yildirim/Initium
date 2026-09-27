# Worked example: one hexagonal feature in Spring Boot 4

A "place order" feature showing domain → ports → use case → adapters → error mapping → tests.
Every package has a `@NullMarked` `package-info.java` (omitted below). Imports are trimmed to the
non-obvious ones.

## Domain (plain Java)

```java
package com.acme.orders.domain;

public record OrderId(UUID value) {
    public static OrderId newId() {
        return new OrderId(UUID.randomUUID());
    }
}

public record Order(OrderId id, String customerId, long totalCents) {
    public Order {
        if (totalCents <= 0) {
            throw new InvalidOrderException("Order total must be positive");
        }
    }
}

public abstract sealed class DomainException extends RuntimeException
        permits InvalidOrderException {
    protected DomainException(String message) {
        super(message);
    }
}

public final class InvalidOrderException extends DomainException {
    public InvalidOrderException(String message) {
        super(message);
    }
}
```

## Application: ports and use case

```java
package com.acme.orders.application.port.in;

public interface PlaceOrderUseCase {
    PlaceOrderResult place(PlaceOrderCommand command);
}

public record PlaceOrderCommand(String customerId, long totalCents) {}

public sealed interface PlaceOrderResult {
    record Placed(OrderId orderId) implements PlaceOrderResult {}
    record CustomerBlocked(String customerId) implements PlaceOrderResult {}
}
```

```java
package com.acme.orders.application.port.out;

public interface OrderRepository {
    void save(Order order);
}

public interface CustomerDirectory {
    boolean isBlocked(String customerId);
}
```

```java
package com.acme.orders.application;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
class PlaceOrderService implements PlaceOrderUseCase {
    private final OrderRepository orders;
    private final CustomerDirectory customers;

    PlaceOrderService(OrderRepository orders, CustomerDirectory customers) {
        this.orders = orders;
        this.customers = customers;
    }

    @Override
    @Transactional
    public PlaceOrderResult place(PlaceOrderCommand command) {
        if (customers.isBlocked(command.customerId())) {
            return new PlaceOrderResult.CustomerBlocked(command.customerId());
        }
        var order = new Order(OrderId.newId(), command.customerId(), command.totalCents());
        orders.save(order);
        return new PlaceOrderResult.Placed(order.id());
    }
}
```

`@Service` and `@Transactional` are the only framework touch points in the application layer;
the domain has none.

## Inbound web adapter

```java
package com.acme.orders.adapter.in.web;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Positive;
import java.net.URI;
import java.security.Principal;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

record PlaceOrderRequest(@Positive long totalCents) {}

record PlaceOrderResponse(UUID orderId) {}

@RestController
@RequestMapping("/orders")
class OrderController {
    private final PlaceOrderUseCase placeOrder;

    OrderController(PlaceOrderUseCase placeOrder) {
        this.placeOrder = placeOrder;
    }

    @PostMapping
    ResponseEntity<?> place(@Valid @RequestBody PlaceOrderRequest request, Principal principal) {
        // Customer id comes from the authenticated principal, never from the request body.
        var command = new PlaceOrderCommand(principal.getName(), request.totalCents());
        return switch (placeOrder.place(command)) {
            case PlaceOrderResult.Placed(var orderId) ->
                    ResponseEntity.created(URI.create("/orders/" + orderId.value()))
                            .body(new PlaceOrderResponse(orderId.value()));
            case PlaceOrderResult.CustomerBlocked blocked ->
                    ResponseEntity.of(ProblemDetail.forStatusAndDetail(
                                    HttpStatus.FORBIDDEN, "Customer cannot place orders"))
                            .build();
        };
    }
}
```

```java
package com.acme.orders.adapter.in.web;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestControllerAdvice
class ApiExceptionHandler {
    private static final Logger LOG = LoggerFactory.getLogger(ApiExceptionHandler.class);

    @ExceptionHandler(InvalidOrderException.class)
    ProblemDetail handleInvalidOrder(InvalidOrderException e) {
        return ProblemDetail.forStatusAndDetail(HttpStatus.BAD_REQUEST, e.getMessage());
    }

    @ExceptionHandler(Exception.class)
    ProblemDetail handleUnexpected(Exception e) {
        LOG.error("Unhandled exception", e);
        return ProblemDetail.forStatusAndDetail(
                HttpStatus.INTERNAL_SERVER_ERROR, "An unexpected error occurred");
    }
}
```

The switch is exhaustive over the sealed result: adding a new outcome is a compile error until
the adapter handles it.

## Outbound persistence adapter

```java
package com.acme.orders.adapter.out.persistence;

import jakarta.persistence.*;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Component;

@Entity
@Table(name = "orders")
class OrderJpaEntity {
    @Id private UUID id;

    @Column(nullable = false)
    private String customerId;

    @Column(nullable = false)
    private long totalCents;

    protected OrderJpaEntity() {}

    OrderJpaEntity(UUID id, String customerId, long totalCents) {
        this.id = id;
        this.customerId = customerId;
        this.totalCents = totalCents;
    }
}

interface SpringDataOrderRepository extends JpaRepository<OrderJpaEntity, UUID> {}

@Component
class JpaOrderRepository implements OrderRepository {
    private final SpringDataOrderRepository repository;

    JpaOrderRepository(SpringDataOrderRepository repository) {
        this.repository = repository;
    }

    @Override
    public void save(Order order) {
        repository.save(new OrderJpaEntity(order.id().value(), order.customerId(), order.totalCents()));
    }
}
```

## Tests

Use case — no Spring context, hand-written fakes for ports:

```java
class PlaceOrderServiceTest {
    private final List<Order> saved = new ArrayList<>();
    private final OrderRepository orders = saved::add;

    @Test
    void shouldRejectBlockedCustomer() {
        var service = new PlaceOrderService(orders, customerId -> true);

        var result = service.place(new PlaceOrderCommand("c-1", 1_500));

        assertThat(result).isInstanceOf(PlaceOrderResult.CustomerBlocked.class);
        assertThat(saved).isEmpty();
    }
}
```

Web slice — `MockMvcTester` + `@MockitoBean`:

```java
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;

import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

@WebMvcTest(OrderController.class)
class OrderControllerTest {
    @Autowired private MockMvcTester mvc;

    @MockitoBean private PlaceOrderUseCase placeOrder;

    @Test
    @WithMockUser(username = "c-1")
    void shouldReturnCreatedWhenOrderIsPlaced() {
        given(placeOrder.place(any()))
                .willReturn(new PlaceOrderResult.Placed(OrderId.newId()));

        assertThat(mvc.post().uri("/orders").with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"totalCents": 1500}
                                """))
                .hasStatus(HttpStatus.CREATED);
    }
}
```

Persistence — real PostgreSQL via Testcontainers 2 and `@ServiceConnection`:

```java
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.testcontainers.postgresql.PostgreSQLContainer;

@SpringBootTest
@Testcontainers
class JpaOrderRepositoryIT {
    @Container
    @ServiceConnection
    static PostgreSQLContainer postgres = new PostgreSQLContainer("postgres:18-alpine");

    @Autowired private OrderRepository orders;

    @Test
    void shouldPersistOrder() {
        assertThatNoException()
                .isThrownBy(() -> orders.save(new Order(OrderId.newId(), "c-1", 1_500)));
    }
}
```

Test dependencies: `spring-boot-starter-test`, `spring-boot-starter-webmvc-test`,
`spring-security-test`, `spring-boot-testcontainers`, `org.testcontainers:testcontainers-junit-jupiter`,
`org.testcontainers:testcontainers-postgresql` (versions from the Boot BOM).
