# Go HTTP service example

Read when building or reviewing an HTTP service. Targets Go 1.27 (stdlib `uuid`, `errors.AsType`).
`example.com/orders` is a placeholder module path; `config` and `postgres` are project packages.

## Domain and port (`internal/order`)

```go
package order

import (
	"context"
	"errors"
	"fmt"
	"uuid"
)

// ErrNotFound is returned when an order does not exist or is not visible to the caller.
var ErrNotFound = errors.New("order not found")

// ValidationError reports a rejected field value.
type ValidationError struct {
	Field  string
	Reason string
}

func (e *ValidationError) Error() string { return e.Field + ": " + e.Reason }

// Order is a placed customer order.
type Order struct {
	ID          uuid.UUID
	CustomerID  uuid.UUID
	AmountCents int64
}

// Store is the persistence port implemented by an adapter (for example internal/postgres).
type Store interface {
	Get(ctx context.Context, id uuid.UUID) (Order, error)
	Insert(ctx context.Context, o Order) error
}

// Service implements order use cases.
type Service struct {
	store Store
}

// NewService returns a Service backed by store.
func NewService(store Store) *Service { return &Service{store: store} }

// Get returns the order with the given id.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (Order, error) {
	o, err := s.store.Get(ctx, id)
	if err != nil {
		return Order{}, fmt.Errorf("getting order %s: %w", id, err)
	}
	return o, nil
}

// Place validates and stores a new order.
func (s *Service) Place(ctx context.Context, customerID uuid.UUID, amountCents int64) (Order, error) {
	if amountCents <= 0 {
		return Order{}, &ValidationError{Field: "amount_cents", Reason: "must be positive"}
	}
	o := Order{ID: uuid.NewV7(), CustomerID: customerID, AmountCents: amountCents}
	if err := s.store.Insert(ctx, o); err != nil {
		return Order{}, fmt.Errorf("inserting order: %w", err)
	}
	return o, nil
}
```

## Inbound adapter (`internal/httpapi`)

```go
package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"uuid"

	"example.com/orders/internal/order"
)

const maxBodyBytes = 1 << 20

// Handler serves the order HTTP API.
type Handler struct {
	orders *order.Service
	logger *slog.Logger
}

// NewHandler returns a Handler for the given service.
func NewHandler(orders *order.Service, logger *slog.Logger) *Handler {
	return &Handler{orders: orders, logger: logger}
}

// Routes returns the router with all order endpoints and panic recovery.
func (h *Handler) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /orders/{id}", h.getOrder)
	mux.HandleFunc("POST /orders", h.createOrder)
	return h.recoverPanics(mux)
}

type createOrderRequest struct {
	CustomerID  string `json:"customer_id"`
	AmountCents int64  `json:"amount_cents"`
}

type orderResponse struct {
	ID          string `json:"id"`
	CustomerID  string `json:"customer_id"`
	AmountCents int64  `json:"amount_cents"`
}

type errorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

type errorBody struct {
	Error errorDetail `json:"error"`
}

func (h *Handler) getOrder(w http.ResponseWriter, r *http.Request) {
	id, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		h.writeError(w, r, http.StatusBadRequest, "INVALID_ID", "id must be a UUID")
		return
	}
	o, err := h.orders.Get(r.Context(), id)
	if err != nil {
		h.writeDomainError(w, r, err)
		return
	}
	h.writeJSON(w, r, http.StatusOK, toResponse(o))
}

func (h *Handler) createOrder(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	var req createOrderRequest
	if err := dec.Decode(&req); err != nil {
		h.writeError(w, r, http.StatusBadRequest, "INVALID_BODY", "request body is not valid JSON")
		return
	}
	customerID, err := uuid.Parse(req.CustomerID)
	if err != nil {
		h.writeError(w, r, http.StatusBadRequest, "INVALID_CUSTOMER_ID", "customer_id must be a UUID")
		return
	}
	o, err := h.orders.Place(r.Context(), customerID, req.AmountCents)
	if err != nil {
		h.writeDomainError(w, r, err)
		return
	}
	h.writeJSON(w, r, http.StatusCreated, toResponse(o))
}

// writeDomainError is the single place where domain errors become HTTP statuses.
func (h *Handler) writeDomainError(w http.ResponseWriter, r *http.Request, err error) {
	if verr, ok := errors.AsType[*order.ValidationError](err); ok {
		h.writeError(w, r, http.StatusUnprocessableEntity, "VALIDATION", verr.Error())
		return
	}
	if errors.Is(err, order.ErrNotFound) {
		h.writeError(w, r, http.StatusNotFound, "NOT_FOUND", "order not found")
		return
	}
	h.logger.ErrorContext(r.Context(), "order request failed",
		slog.String("path", r.URL.Path), slog.Any("error", err))
	h.writeError(w, r, http.StatusInternalServerError, "INTERNAL", "internal error")
}

func (h *Handler) writeError(w http.ResponseWriter, r *http.Request, status int, code, msg string) {
	h.writeJSON(w, r, status, errorBody{Error: errorDetail{Code: code, Message: msg}})
}

func (h *Handler) writeJSON(w http.ResponseWriter, r *http.Request, status int, v any) {
	body, err := json.Marshal(v)
	if err != nil {
		h.logger.ErrorContext(r.Context(), "encoding response", slog.Any("error", err))
		w.WriteHeader(http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if _, err := w.Write(body); err != nil {
		h.logger.WarnContext(r.Context(), "writing response", slog.Any("error", err))
	}
}

func (h *Handler) recoverPanics(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			rec := recover()
			if rec == nil {
				return
			}
			if rec == http.ErrAbortHandler {
				panic(rec)
			}
			h.logger.ErrorContext(r.Context(), "panic in handler", slog.Any("panic", rec))
			h.writeError(w, r, http.StatusInternalServerError, "INTERNAL", "internal error")
		}()
		next.ServeHTTP(w, r)
	})
}

func toResponse(o order.Order) orderResponse {
	return orderResponse{ID: o.ID.String(), CustomerID: o.CustomerID.String(), AmountCents: o.AmountCents}
}
```

- Authentication middleware (not shown) puts the principal in the request context; the service
  checks ownership before returning an order and returns `ErrNotFound` for orders the caller may
  not see.

## Composition root (`cmd/orders/main.go`)

```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"example.com/orders/internal/config"
	"example.com/orders/internal/httpapi"
	"example.com/orders/internal/order"
	"example.com/orders/internal/postgres"
)

const shutdownTimeout = 20 * time.Second

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	if err := run(logger); err != nil {
		logger.Error("server stopped", slog.Any("error", err))
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}
	store, err := postgres.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return fmt.Errorf("opening store: %w", err)
	}
	defer store.Close()

	api := httpapi.NewHandler(order.NewService(store), logger)
	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           otelhttp.NewHandler(api.Routes(), "orders"),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serveErr := make(chan error, 1)
	go func() { serveErr <- srv.ListenAndServe() }()

	select {
	case err := <-serveErr:
		return fmt.Errorf("listening: %w", err)
	case <-ctx.Done():
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutting down: %w", err)
	}
	return nil
}
```

- Initialize the OpenTelemetry SDK (tracer and meter providers with OTLP exporters) in `run`
  before building the server, and shut it down after `srv.Shutdown`.

## Testing time-dependent code

```go
func TestSessionExpires(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		sessions := NewSessionCache(time.Minute)
		sessions.Put("abc", "user-1")

		time.Sleep(61 * time.Second) // fake clock inside the bubble: returns immediately
		synctest.Wait()

		if _, ok := sessions.Get("abc"); ok {
			t.Fatal("session should have expired")
		}
	})
}
```

## Fuzzing a parser

```go
func FuzzParseAmount(f *testing.F) {
	f.Add("12.50")
	f.Add("0.01")
	f.Fuzz(func(t *testing.T, input string) {
		cents, err := ParseAmount(input)
		if err != nil {
			return
		}
		if cents < 0 {
			t.Fatalf("ParseAmount(%q) = %d, want non-negative", input, cents)
		}
	})
}
```
