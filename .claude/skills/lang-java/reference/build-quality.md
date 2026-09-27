# Build quality gates (Gradle and Maven)

Versions verified September 2026. Pin exact versions in the version catalog / POM properties and
let Dependabot or Renovate bump them; never use dynamic versions (`+`, `latest.release`) for
Error Prone, because new releases add checks that can break the build.

| Tool | Coordinates | Version |
|---|---|---|
| Spring Boot Gradle plugin | `org.springframework.boot` | 4.1.1 |
| Error Prone Gradle plugin | `net.ltgt.errorprone` | 5.1.1 |
| Error Prone | `com.google.errorprone:error_prone_core` | 2.50.0 |
| NullAway | `com.uber.nullaway:nullaway` | 0.14.1 |
| JSpecify | `org.jspecify:jspecify` | 1.0.0 |
| Spotless Gradle plugin | `com.diffplug.spotless` | 8.10.1 |
| Spotless Maven plugin | `com.diffplug.spotless:spotless-maven-plugin` | 3.10.1 |
| OWASP Dependency-Check Maven plugin | `org.owasp:dependency-check-maven` | 13.0.0 |

## Gradle (Kotlin DSL shown; Groovy is equivalent)

```kotlin
import net.ltgt.gradle.errorprone.CheckSeverity
import net.ltgt.gradle.errorprone.errorprone

plugins {
    java
    id("org.springframework.boot") version "4.1.1"
    id("net.ltgt.errorprone") version "5.1.1"
    id("com.diffplug.spotless") version "8.10.1"
}

java {
    toolchain { languageVersion = JavaLanguageVersion.of(25) }
}

repositories {
    mavenCentral()
}

dependencies {
    implementation(platform(org.springframework.boot.gradle.plugin.SpringBootPlugin.BOM_COORDINATES))
    implementation("org.springframework.boot:spring-boot-starter-webmvc")
    implementation("org.springframework.boot:spring-boot-starter-validation")
    implementation("org.jspecify:jspecify:1.0.0")

    errorprone("com.google.errorprone:error_prone_core:2.50.0")
    errorprone("com.uber.nullaway:nullaway:0.14.1")

    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.boot:spring-boot-starter-webmvc-test")
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 25
    options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror"))
    options.errorprone {
        disableWarningsInGeneratedCode = true
        check("NullAway", CheckSeverity.ERROR)
        option("NullAway:OnlyNullMarked", "true")
        option("NullAway:CustomContractAnnotations", "org.springframework.lang.Contract")
        // Step 2, once the codebase is clean under OnlyNullMarked:
        // option("NullAway:JSpecifyMode", "true")
    }
}

tasks.compileTestJava {
    options.errorprone.disable("NullAway")
}

spotless {
    java {
        googleJavaFormat("1.30.0")
        removeUnusedImports()
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

- `-Werror` together with `-Xlint:all` can be noisy on legacy code; introduce it per module.
- Lombok (legacy code only): `compileOnly("org.projectlombok:lombok")` and
  `annotationProcessor("org.projectlombok:lombok")` — the Boot BOM manages the version.
- Dependency scanning on Gradle: apply the `org.owasp.dependencycheck` plugin with the same
  settings as the Maven plugin below, or rely on the GitHub dependency graph + Dependabot alerts.

## Package-level null marking

```java
// src/main/java/com/acme/orders/domain/package-info.java
@NullMarked
package com.acme.orders.domain;

import org.jspecify.annotations.NullMarked;
```

Every package needs its own `package-info.java`; `@NullMarked` is not inherited by sub-packages.

## Maven

```xml
<properties>
  <java.version>25</java.version>
  <maven.compiler.release>25</maven.compiler.release>
  <error-prone.version>2.50.0</error-prone.version>
  <nullaway.version>0.14.1</nullaway.version>
</properties>

<build>
  <plugins>
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-compiler-plugin</artifactId>
      <configuration>
        <compilerArgs>
          <arg>-XDcompilePolicy=simple</arg>
          <arg>--should-stop=ifError=FLOW</arg>
          <arg>-Xplugin:ErrorProne -Xep:NullAway:ERROR -XepOpt:NullAway:OnlyNullMarked=true -XepOpt:NullAway:CustomContractAnnotations=org.springframework.lang.Contract</arg>
        </compilerArgs>
        <annotationProcessorPaths>
          <path>
            <groupId>com.google.errorprone</groupId>
            <artifactId>error_prone_core</artifactId>
            <version>${error-prone.version}</version>
          </path>
          <path>
            <groupId>com.uber.nullaway</groupId>
            <artifactId>nullaway</artifactId>
            <version>${nullaway.version}</version>
          </path>
        </annotationProcessorPaths>
      </configuration>
    </plugin>

    <plugin>
      <groupId>com.diffplug.spotless</groupId>
      <artifactId>spotless-maven-plugin</artifactId>
      <version>3.10.1</version>
      <configuration>
        <java>
          <googleJavaFormat><version>1.30.0</version></googleJavaFormat>
          <removeUnusedImports/>
        </java>
      </configuration>
      <executions>
        <execution><goals><goal>check</goal></goals></execution>
      </executions>
    </plugin>

    <plugin>
      <groupId>org.owasp</groupId>
      <artifactId>dependency-check-maven</artifactId>
      <version>13.0.0</version>
      <configuration>
        <nvdApiKeyEnvironmentVariable>NVD_API_KEY</nvdApiKeyEnvironmentVariable>
        <failBuildOnCVSS>7</failBuildOnCVSS>
      </configuration>
    </plugin>
  </plugins>
</build>
```

- Error Prone on JDK 16+ also needs the `--add-exports`/`--add-opens` flags for `jdk.compiler`;
  put them in `.mvn/jvm.config` as described in the Error Prone installation guide.
- Never pass the NVD key as `-DnvdApiKey=...`: Maven debug logs can expose it.
- Run `dependency-check:check` in a scheduled CI job with a cached NVD database; it is too slow
  for every pull request.
