# Build, packages, and CI settings

Versions verified against nuget.org in September 2026. Let Dependabot/Renovate bump them;
never use floating versions (`*`) in `Directory.Packages.props`.

## global.json

```json
{
  "sdk": {
    "version": "10.0.401",
    "rollForward": "latestFeature"
  },
  "test": {
    "runner": "Microsoft.Testing.Platform"
  }
}
```

With the MTP runner set, every test project in the solution must support MTP (xUnit v3 does);
a leftover VSTest-only project will not run.

## Directory.Build.props (repo root)

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest-recommended</AnalysisLevel>
    <EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>
    <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
    <NuGetAuditLevel>low</NuGetAuditLevel>
  </PropertyGroup>
</Project>
```

- `NuGetAuditMode` already defaults to `all` for `net10.0`; do not set it to `direct`.
- `TreatWarningsAsErrors` turns NuGetAudit warnings (NU1901–NU1904) into restore failures.
  Suppress a single advisory only with a linked issue:
  `<NuGetAuditSuppress Include="https://github.com/advisories/GHSA-xxxx" />`.

## Directory.Packages.props (repo root)

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
  </PropertyGroup>
  <ItemGroup>
    <!-- Web -->
    <PackageVersion Include="Microsoft.AspNetCore.OpenApi" Version="10.0.12" />
    <PackageVersion Include="Microsoft.Extensions.Http.Resilience" Version="10.10.0" />
    <!-- Data -->
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="10.0.12" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.Design" Version="10.0.12" />
    <PackageVersion Include="Npgsql.EntityFrameworkCore.PostgreSQL" Version="10.0.3" />
    <!-- Observability -->
    <PackageVersion Include="OpenTelemetry.Extensions.Hosting" Version="1.19.1" />
    <PackageVersion Include="OpenTelemetry.Exporter.OpenTelemetryProtocol" Version="1.19.1" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.AspNetCore" Version="1.19.0" />
    <PackageVersion Include="OpenTelemetry.Instrumentation.Http" Version="1.19.0" />
    <!-- Tests -->
    <PackageVersion Include="xunit.v3" Version="4.0.1" />
    <PackageVersion Include="xunit.analyzers" Version="2.1.0" />
    <PackageVersion Include="NSubstitute" Version="6.2.0" />
    <PackageVersion Include="Shouldly" Version="4.3.0" />
    <PackageVersion Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.12" />
    <PackageVersion Include="Testcontainers.PostgreSql" Version="4.15.0" />
  </ItemGroup>
</Project>
```

Project files then reference packages without versions:

```xml
<ItemGroup>
  <PackageReference Include="Npgsql.EntityFrameworkCore.PostgreSQL" />
  <PackageReference Include="Microsoft.EntityFrameworkCore.Design" PrivateAssets="all" />
</ItemGroup>
```

Optional mediator (MIT): `Mediator.SourceGenerator` 3.0.2 in the outermost executable project
only (with `PrivateAssets="all"`) and `Mediator.Abstractions` 3.0.2 wherever messages and
handlers are defined.

## Test project

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <IsPackable>false</IsPackable>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="xunit.v3" />
    <PackageReference Include="xunit.analyzers" PrivateAssets="all" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="Shouldly" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\..\src\Orders.Application\Orders.Application.csproj" />
  </ItemGroup>
</Project>
```

xUnit v3 test projects are executables (`OutputType=Exe`); `xunit.v3` brings in MTP v2 support.
Keep `xunit.runner.visualstudio`/`Microsoft.NET.Test.Sdk` only while some IDE in the team still
needs VSTest.

## CI steps

```bash
dotnet restore --locked-mode
dotnet format --verify-no-changes --no-restore
dotnet build --no-restore -c Release
dotnet test --no-build -c Release
dotnet list package --vulnerable --include-transitive
```

EF Core migrations ship as a self-contained bundle built in CI and executed by the deploy job
with the connection string injected from the secret store:

```bash
dotnet ef migrations bundle --project src/Orders.Infrastructure --startup-project src/Orders.Api -o efbundle
./efbundle --connection "$ORDERS_DB_CONNECTION"
```
