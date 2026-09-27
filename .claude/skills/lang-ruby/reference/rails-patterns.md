# Rails Patterns: Use Case, Port, Adapter, Controller, Specs, Telemetry

Read when implementing a use case with a Result, a port and its Active Record adapter,
controller error mapping, specs with fakes, the OpenTelemetry initializer, or a
`Rails.event` subscriber. Targets Ruby 3.4+/4.0 and Rails 8.1.

## Result value object

```ruby
# app/domain/result.rb
Result = Data.define(:value, :error) do
  def self.success(value) = new(value:, error: nil)
  def self.failure(error) = new(value: nil, error:)

  def success? = error.nil?
end
```

## Domain object and use case

```ruby
# app/domain/orders/order.rb
module Orders
  Order = Data.define(:id, :sku, :quantity)
end
```

```ruby
# app/domain/orders/change_quantity.rb
module Orders
  # Changes the quantity of an existing order.
  # repository must respond to #find(id) -> Order | nil and #save(order) -> Order.
  class ChangeQuantity
    MAX_QUANTITY = 10_000

    def initialize(repository:)
      @repository = repository
    end

    def call(order_id:, quantity:)
      return Result.failure(:invalid_quantity) unless quantity.between?(1, MAX_QUANTITY)

      order = @repository.find(order_id)
      return Result.failure(:not_found) if order.nil?

      updated = @repository.save(order.with(quantity:))
      Rails.event.notify("orders.quantity_changed", order_id: updated.id, quantity:)
      Result.success(updated)
    end
  end
end
```

## Active Record adapter

```ruby
# app/models/order_record.rb
class OrderRecord < ApplicationRecord
  self.table_name = "orders"

  validates :sku, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
```

```ruby
# app/adapters/orders/active_record_repository.rb
module Orders
  class ActiveRecordRepository
    def find(id)
      record = OrderRecord.find_by(id:)
      record && to_domain(record)
    end

    def save(order)
      record = OrderRecord.find(order.id)
      record.update!(quantity: order.quantity)
      to_domain(record)
    end

    private

    def to_domain(record) = Order.new(id: record.id, sku: record.sku, quantity: record.quantity)
  end
end
```

## Controller: validate input, call, map errors

```ruby
# app/controllers/order_quantities_controller.rb
class OrderQuantitiesController < ApplicationController
  ERROR_STATUS = { invalid_quantity: 422, not_found: 404 }.freeze

  rate_limit to: 30, within: 1.minute, only: :update

  def update
    quantity = Integer(params.expect(order: [:quantity]).fetch(:quantity), exception: false)
    return render_error(:invalid_quantity) if quantity.nil?

    result = change_quantity.call(order_id: params[:order_id], quantity:)
    return render_error(result.error) unless result.success?

    render json: { id: result.value.id, quantity: result.value.quantity }
  end

  private

  def change_quantity
    Orders::ChangeQuantity.new(repository: Orders::ActiveRecordRepository.new)
  end

  def render_error(code)
    render json: { error: code }, status: ERROR_STATUS.fetch(code)
  end
end
```

`params.expect` responds with 400 when the shape is wrong. Authorization (does the current
user own this order?) belongs in the use case or a policy object before `find` returns data.

## RSpec: use case with a fake port

```ruby
# spec/domain/orders/change_quantity_spec.rb
require "rails_helper"

RSpec.describe Orders::ChangeQuantity do
  let(:fake_repository) do
    Class.new do
      def initialize(orders) = @orders = orders.to_h { [_1.id, _1] }
      def find(id) = @orders[id]
      def save(order) = @orders[order.id] = order
    end
  end
  let(:order) { Orders::Order.new(id: 1, sku: "SKU-1", quantity: 1) }
  let(:repository) { fake_repository.new([order]) }

  subject(:change_quantity) { described_class.new(repository:) }

  it "rejects quantities above the maximum" do
    result = change_quantity.call(order_id: 1, quantity: described_class::MAX_QUANTITY + 1)

    expect(result.error).to eq(:invalid_quantity)
  end

  it "returns not_found for unknown orders" do
    expect(change_quantity.call(order_id: 99, quantity: 2).error).to eq(:not_found)
  end

  it "updates the quantity" do
    result = change_quantity.call(order_id: 1, quantity: 5)

    expect(result).to be_success
    expect(repository.find(1).quantity).to eq(5)
  end
end
```

## OpenTelemetry initializer

```ruby
# Gemfile
gem "opentelemetry-sdk"
gem "opentelemetry-exporter-otlp"
gem "opentelemetry-instrumentation-all"
```

```ruby
# config/initializers/opentelemetry.rb
require "opentelemetry/sdk"
require "opentelemetry/exporter/otlp"
require "opentelemetry/instrumentation/all"

OpenTelemetry::SDK.configure do |c|
  c.service_name = ENV.fetch("OTEL_SERVICE_NAME", "orders-api")
  c.use_all
end
```

The exporter endpoint and headers come from `OTEL_EXPORTER_OTLP_ENDPOINT` /
`OTEL_EXPORTER_OTLP_HEADERS`; never hardcode collector credentials.

## Rails.event JSON subscriber (Rails 8.1)

```ruby
# app/adapters/observability/json_event_subscriber.rb
module Observability
  class JsonEventSubscriber
    def initialize(logger: Rails.logger)
      @logger = logger
    end

    def emit(event)
      @logger.info(event.slice(:name, :payload, :tags, :context, :timestamp).to_json)
    end
  end
end
```

```ruby
# config/initializers/events.rb
Rails.application.config.after_initialize do
  Rails.event.subscribe(Observability::JsonEventSubscriber.new)
end
```

Set request-wide fields once (for example in a controller `before_action`):
`Rails.event.set_context(request_id: request.request_id)`. Never put passwords, tokens, or
raw PII in event payloads.
