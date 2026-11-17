# Spec Delta

## Purpose

Define el contrato del monorepo: un único reactor de build reproducible para todos los módulos, la toolchain exigida, la nomenclatura de paquetes, la higiene del repositorio y la política de secretos.

## ADDED Requirements

### Requirement: Build único desde la raíz

El repositorio SHALL construir todos los módulos de código (el `api-gateway`, los cinco servicios de `apps/services/` y las librerías de `libs/`) desde la raíz con un único comando de Maven, sin pasos previos por módulo.

#### Scenario: Build completo del reactor

- **WHEN** se ejecuta `./mvnw -B -ntp verify` en la raíz del repositorio
- **THEN** el reactor compila y verifica cada módulo declarado, ejecutando su lint, sus tests y el gate de cobertura, y el comando termina con código de salida 0

#### Scenario: Directorio de módulo no declarado

- **WHEN** existe un directorio con `pom.xml` bajo `apps/` o `libs/` que no está declarado en el parent POM
- **THEN** `./mvnw -B -ntp validate` falla con un mensaje que nombra el directorio no declarado

### Requirement: Toolchain fijada

El build del backend SHALL exigir JDK 21 y el del frontend SHALL exigir Node.js ≥ 22.12.0; una versión inferior SHALL abortar el build con un mensaje explícito.

#### Scenario: JDK incorrecto

- **WHEN** se ejecuta el build con un JDK anterior a 21
- **THEN** el build falla antes de compilar indicando que se requiere Java 21

#### Scenario: Node.js incorrecto

- **WHEN** se ejecuta `npm ci` en `apps/web-frontend` con una versión de Node.js inferior a 22.12.0
- **THEN** la instalación falla indicando la versión requerida

### Requirement: Nomenclatura de paquetes

Cada clase de producción SHALL residir bajo el prefijo `com.domincipe.`, y cada servicio SHALL exponer una única clase anotada como aplicación Spring Boot.

#### Scenario: Clase fuera del prefijo

- **WHEN** se añade una clase de producción en un paquete que no empieza por `com.domincipe.`
- **THEN** `./mvnw -B -ntp verify` falla en la fase de lint indicando el fichero infractor

#### Scenario: Servicio sin clase de arranque

- **WHEN** un módulo de servicio no contiene exactamente una clase anotada con `@SpringBootApplication`
- **THEN** los tests del módulo fallan indicando que no se encontró una configuración de arranque válida

### Requirement: Higiene del repositorio

El repositorio SHALL ignorar artefactos de build, dependencias instaladas y ficheros de entorno locales, y SHALL versionar únicamente `.env.example` como plantilla de configuración.

#### Scenario: Fichero de entorno local ignorado

- **WHEN** se ejecuta `git check-ignore -v .env`
- **THEN** el comando termina con código 0 y muestra la regla de `.gitignore` que lo excluye

#### Scenario: Plantilla sin secretos

- **WHEN** se inspecciona el contenido versionado de `.env.example`
- **THEN** todas sus variables tienen valores de ejemplo o vacíos y ninguna contiene credenciales reales

### Requirement: Ficheros raíz del proyecto

La raíz del repositorio SHALL contener `README.md`, `LICENSE` con la licencia MIT y `.editorconfig` que fije UTF-8, finales de línea LF y la indentación por tipo de fichero.

#### Scenario: Configuración de editor coherente

- **WHEN** se lee `.editorconfig`
- **THEN** declara `charset = utf-8`, `end_of_line = lf` e indentación de 4 espacios para `*.java` y de 2 para `*.ts`

#### Scenario: Licencia declarada

- **WHEN** se lee la cabecera de `LICENSE` y la sección de licencia de `README.md`
- **THEN** ambas identifican la licencia MIT
