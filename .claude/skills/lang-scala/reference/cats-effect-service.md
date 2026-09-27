# Cats Effect Service: Build, Domain, tapir + http4s, otel4s, Tests

Read when setting up an sbt or Mill build, a tapir + http4s endpoint with typed errors, otel4s
tracing, an in-memory port, a munit test, or scalafmt/scalafix configuration.
Targets Scala 3.9 LTS, JDK 21+, Cats Effect 3.7.

## sbt build (sbt 2.0)

`project/build.properties`:

```properties
sbt.version=2.0.9
```

`project/plugins.sbt`:

```scala
addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.6.2")
addSbtPlugin("ch.epfl.scala" % "sbt-scalafix" % "0.14.9")
```

`build.sbt`:

```scala
ThisBuild / scalaVersion := "3.9.0"
ThisBuild / semanticdbEnabled := true
ThisBuild / scalacOptions ++= Seq(
  "-deprecation", "-feature", "-unchecked",
  "-Wunused:all", "-Wvalue-discard", "-Wnonunit-statement", "-Werror"
)

val CatsEffectVersion = "3.7.1"
val TapirVersion = "1.13.32"
val Http4sVersion = "0.23.37"
val Otel4sVersion = "1.1.0"
val OtelJavaVersion = "1.66.0"

val testDependencies = Seq(
  "org.scalameta" %% "munit" % "1.3.6" % Test,
  "org.typelevel" %% "munit-cats-effect" % "2.2.1" % Test
)

lazy val domain = project
  .settings(libraryDependencies += "org.typelevel" %% "cats-core" % "2.13.0")

lazy val app = project
  .dependsOn(domain)
  .settings(
    libraryDependencies ++= testDependencies :+ ("org.typelevel" %% "cats-effect" % CatsEffectVersion)
  )

lazy val adapters = project
  .dependsOn(app)
  .settings(
    libraryDependencies ++= testDependencies ++ Seq(
      "com.softwaremill.sttp.tapir" %% "tapir-http4s-server" % TapirVersion,
      "com.softwaremill.sttp.tapir" %% "tapir-json-circe" % TapirVersion,
      "org.http4s" %% "http4s-ember-server" % Http4sVersion,
      "org.typelevel" %% "otel4s-oteljava" % Otel4sVersion,
      "io.opentelemetry" % "opentelemetry-exporter-otlp" % OtelJavaVersion % Runtime,
      "io.opentelemetry" % "opentelemetry-sdk-extension-autoconfigure" % OtelJavaVersion % Runtime,
      "org.typelevel" %% "log4cats-slf4j" % "2.8.0",
      "ch.qos.logback" % "logback-classic" % "1.6.4" % Runtime
    )
  )
```

Let Scala Steward bump these versions rather than hand-editing them.

## Mill build (Mill 1.x)

```scala
//| mill-version: 1.1.8
package build
import mill.*, scalalib.*

trait StrictModule extends ScalaModule {
  def scalaVersion = "3.9.0"
  def scalacOptions = Seq(
    "-deprecation", "-feature", "-unchecked",
    "-Wunused:all", "-Wvalue-discard", "-Wnonunit-statement", "-Werror"
  )
}

object domain extends StrictModule {
  def mvnDeps = Seq(mvn"org.typelevel::cats-core:2.13.0")
}

object app extends StrictModule {
  def moduleDeps = Seq(domain)
  def mvnDeps = Seq(mvn"org.typelevel::cats-effect:3.7.1")

  object test extends ScalaTests, TestModule.Munit {
    def mvnDeps = Seq(
      mvn"org.scalameta::munit:1.3.6",
      mvn"org.typelevel::munit-cats-effect:2.2.1"
    )
  }
}
```

## Domain (no effect library)

```scala
// domain/src/main/scala/orders/domain/Order.scala
package orders.domain

opaque type OrderId = Long
object OrderId:
  def apply(value: Long): OrderId = value
  extension (id: OrderId) def value: Long = id

final case class Order(id: OrderId, sku: String, quantity: Int)

enum OrderError:
  case NotFound(id: OrderId)
  case InvalidQuantity(requested: Int)
```

## Port and use case

```scala
// app/src/main/scala/orders/app/ChangeQuantity.scala
package orders.app

import cats.Monad
import cats.data.EitherT
import orders.domain.{Order, OrderError, OrderId}

trait OrderRepository[F[_]]:
  def find(id: OrderId): F[Option[Order]]
  def save(order: Order): F[Unit]

final class ChangeQuantity[F[_]: Monad](repository: OrderRepository[F]):
  import ChangeQuantity.MAX_QUANTITY

  def apply(id: OrderId, quantity: Int): F[Either[OrderError, Order]] =
    (for
      _ <- EitherT.cond[F](quantity >= 1 && quantity <= MAX_QUANTITY, (), OrderError.InvalidQuantity(quantity))
      order <- EitherT.fromOptionF(repository.find(id), OrderError.NotFound(id))
      updated = order.copy(quantity = quantity)
      _ <- EitherT.liftF(repository.save(updated))
    yield updated).value

object ChangeQuantity:
  val MAX_QUANTITY: Int = 10_000
```

## tapir endpoint with typed errors, served by http4s

```scala
// adapters/src/main/scala/orders/adapters/OrderEndpoints.scala
package orders.adapters

import cats.effect.IO
import io.circe.Codec
import orders.app.ChangeQuantity
import orders.domain.{OrderError, OrderId}
import org.typelevel.otel4s.trace.Tracer
import sttp.model.StatusCode
import sttp.tapir.*
import sttp.tapir.json.circe.*

final case class QuantityRequest(quantity: Int) derives Codec.AsObject, Schema
final case class OrderResponse(id: Long, sku: String, quantity: Int) derives Codec.AsObject, Schema
final case class ErrorResponse(code: String) derives Codec.AsObject, Schema

object OrderEndpoints:
  val changeQuantity =
    endpoint.put
      .in("orders" / path[Long]("orderId") / "quantity")
      .in(jsonBody[QuantityRequest])
      .out(jsonBody[OrderResponse])
      .errorOut(statusCode.and(jsonBody[ErrorResponse]))

  def toHttp(error: OrderError): (StatusCode, ErrorResponse) = error match
    case OrderError.NotFound(_)        => (StatusCode.NotFound, ErrorResponse("not_found"))
    case OrderError.InvalidQuantity(_) => (StatusCode.UnprocessableEntity, ErrorResponse("invalid_quantity"))

  def serverEndpoints(useCase: ChangeQuantity[IO])(using tracer: Tracer[IO]) =
    List(
      changeQuantity.serverLogic { (orderId, request) =>
        tracer.span("orders.change_quantity").surround {
          useCase(OrderId(orderId), request.quantity).map(
            _.left.map(toHttp).map(order => OrderResponse(order.id.value, order.sku, order.quantity))
          )
        }
      }
    )
```

```scala
// adapters/src/main/scala/orders/adapters/Main.scala
package orders.adapters

import cats.effect.{IO, IOApp, Resource}
import com.comcast.ip4s.*
import org.http4s.ember.server.EmberServerBuilder
import org.http4s.implicits.*
import org.typelevel.log4cats.slf4j.Slf4jLogger
import org.typelevel.otel4s.oteljava.OtelJava
import orders.app.ChangeQuantity
import sttp.tapir.server.http4s.Http4sServerInterpreter

object Main extends IOApp.Simple:
  def run: IO[Unit] =
    OtelJava.autoConfigured[IO]().use { otel =>
      otel.tracerProvider.get("orders-api").flatMap { tracer =>
        given org.typelevel.otel4s.trace.Tracer[IO] = tracer
        val program =
          for
            logger <- Resource.eval(Slf4jLogger.create[IO])
            repository <- Resource.eval(InMemoryOrderRepository.empty)
            routes = Http4sServerInterpreter[IO]()
              .toRoutes(OrderEndpoints.serverEndpoints(ChangeQuantity[IO](repository)))
            server <- EmberServerBuilder.default[IO]
              .withHost(host"0.0.0.0")
              .withPort(port"8080")
              .withHttpApp(routes.orNotFound)
              .build
            _ <- Resource.eval(logger.info(s"listening on ${server.address}"))
          yield ()
        program.useForever
      }
    }
```

Swap `InMemoryOrderRepository` for a Doobie/Skunk adapter in production; with Doobie, only
`sql"... WHERE id = $id"` interpolation (parameterized), never `Fragment.const(userInput)`.

## In-memory port with Ref

```scala
// adapters/src/main/scala/orders/adapters/InMemoryOrderRepository.scala
package orders.adapters

import cats.effect.{IO, Ref}
import orders.app.OrderRepository
import orders.domain.{Order, OrderId}

final class InMemoryOrderRepository private (rows: Ref[IO, Map[OrderId, Order]])
    extends OrderRepository[IO]:
  def find(id: OrderId): IO[Option[Order]] = rows.get.map(_.get(id))
  def save(order: Order): IO[Unit] = rows.update(_.updated(order.id, order))

object InMemoryOrderRepository:
  def empty: IO[InMemoryOrderRepository] = from(Map.empty)
  def from(initial: Map[OrderId, Order]): IO[InMemoryOrderRepository] =
    Ref.of[IO, Map[OrderId, Order]](initial).map(InMemoryOrderRepository(_))
```

## munit + Cats Effect test

```scala
// adapters/src/test/scala/orders/adapters/ChangeQuantitySuite.scala
package orders.adapters

import cats.effect.IO
import munit.CatsEffectSuite
import orders.app.ChangeQuantity
import orders.domain.{Order, OrderError, OrderId}

class ChangeQuantitySuite extends CatsEffectSuite:
  private val id = OrderId(1L)
  private val tooMany = ChangeQuantity.MAX_QUANTITY + 1

  private def useCaseWith(order: Order): IO[(ChangeQuantity[IO], InMemoryOrderRepository)] =
    InMemoryOrderRepository.from(Map(order.id -> order)).map(repo => (ChangeQuantity[IO](repo), repo))

  test("rejects quantities above the maximum"):
    for
      (changeQuantity, _) <- useCaseWith(Order(id, "SKU-1", 1))
      result <- changeQuantity(id, tooMany)
    yield assertEquals(result, Left(OrderError.InvalidQuantity(tooMany)))

  test("updates an existing order"):
    for
      (changeQuantity, repository) <- useCaseWith(Order(id, "SKU-1", 1))
      result <- changeQuantity(id, 5)
      stored <- repository.find(id)
    yield
      assertEquals(result.map(_.quantity), Right(5))
      assertEquals(stored.map(_.quantity), Some(5))
```

## scalafmt and scalafix configuration

`.scalafmt.conf`:

```conf
version = "3.11.1"
runner.dialect = scala3
maxColumn = 110
```

`.scalafix.conf`:

```conf
rules = [
  OrganizeImports,
  RemoveUnused,
  DisableSyntax
]
OrganizeImports.targetDialect = Scala3
OrganizeImports.removeUnused = true
DisableSyntax.noNulls = true
DisableSyntax.noReturns = true
DisableSyntax.noVars = true
```

CI: `sbt scalafmtCheckAll "scalafixAll --check" test`.
