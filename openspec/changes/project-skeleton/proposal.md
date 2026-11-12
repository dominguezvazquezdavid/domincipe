# Proposal

## Why

El repositorio contiene hoy solo documentación y la configuración de OpenSpec: no hay build, ni módulos, ni forma de arrancar nada. Sin un esqueleto verificable no se puede aplicar ningún change posterior cumpliendo la Definition of Done del proyecto (suite completa en verde + gate de cobertura JaCoCo), ni comprobar en la práctica las decisiones arquitectónicas de [PROJECT.md §3–§9](../../../PROJECT.md).

## What Changes

- **Build multi-módulo**: parent POM en la raíz con Java 21, Spring Boot 3.x, JaCoCo con gate (≥80 % líneas / ≥70 % ramas), Checkstyle como lint y reglas de codificación; Maven Wrapper (`mvnw`) para fijar la versión de Maven.
- **Módulos Java arrancables**: `apps/api-gateway` y los cinco servicios de `apps/services/` (`auth`, `user`, `recipe`, `media`, `notification`) como aplicaciones Spring Boot mínimas que exponen *health* y métricas, con configuración por variables de entorno y *graceful shutdown*.
- **Documentación de API**: cada servicio publica su contrato OpenAPI 3 generado desde el código con `springdoc-openapi` (línea 2.x, la compatible con Spring Boot 3.x): especificación en `/v3/api-docs` e interfaz interactiva en `/swagger-ui.html`, desactivable por variable de entorno.
- **Librerías compartidas**: `libs/common-dto` (tipos y contratos comunes) y `libs/common-observability` (Micrometer, métricas Prometheus y correlación de trazas).
- **Frontend**: `apps/web-frontend` con React 19 + TypeScript + Vite + Tailwind + shadcn/ui + TanStack Query + React Router v7, con lint, *smoke test* y URL del API por variable de entorno.
- **Entorno local cloud-like**: `ops/compose/docker-compose.{base,dev,obs}.yml` con PostgreSQL 16 (un schema por servicio), Kafka 4.x en modo KRaft con topics creados de forma idempotente, MinIO con bucket, MailHog, healthchecks, `depends_on: condition: service_healthy`, redes separadas, límites de recursos y *graceful shutdown* con `stop_grace_period`. La pila de observabilidad (Prometheus, Grafana y Kafka UI) se levanta **siempre**, incluida en el arranque por defecto mediante `COMPOSE_FILE`, no como perfil opcional.
- **Imágenes**: Dockerfiles multi-stage y no-root para los seis servicios (uno reutilizable, parametrizado por módulo) y para el frontend, con tag inmutable por git SHA además de `latest`.
- **Configuración**: `.env.example` versionado con todas las variables, `config/checkstyle/checkstyle.xml`, y actualización de [PROJECT.md §6](../../../PROJECT.md) para reflejar `config/`, `.env.example` y `.mvn/`.
- **Ficheros raíz ya creados junto a esta propuesta** (orden explícita del usuario): `README.md`, `LICENSE` (MIT), `.gitignore` y `.editorconfig`.
- Sin **BREAKING** changes: no existe código previo que romper.

## Capabilities

### New Capabilities

- `repo-layout`: contrato del monorepo — reactor Maven único, toolchain (Java 21 / Node ≥ 22.12.0), nomenclatura de paquetes, higiene del repositorio y política de secretos.
- `service-runtime`: comportamiento común de arranque de los servicios Java — endpoints de salud y métricas, documentación OpenAPI publicada, configuración exclusivamente por variables de entorno con fallo temprano y apagado ordenado.
- `local-environment`: entorno Docker local con comportamiento cloud-like — arranque único condicionado a healthchecks, aislamiento de redes, aprovisionamiento de PostgreSQL/Kafka/MinIO/MailHog, límites de recursos y observabilidad siempre activa.
- `web-shell`: comportamiento del *shell* del frontend — build y lint reproducible, configuración del API por entorno y arranque de la SPA con sus proveedores (router y cliente de datos).

### Modified Capabilities

Ninguna: `openspec/specs/` está vacío (`openspec list --specs` → "No specs found"), por lo que no hay requisitos existentes que cambien.

## Impact

- **Código nuevo**: `pom.xml` raíz, `.mvn/`, `config/`, `apps/api-gateway`, `apps/services/{auth,user,recipe,media,notification}-service`, `apps/web-frontend`, `libs/common-dto`, `libs/common-observability`, `ops/docker`, `ops/compose`, `.env.example`.
- **Dependencias nuevas**: Spring Boot (BOM), Spring Web, Actuator, Micrometer Prometheus, springdoc-openapi (2.x), Spring Security (solo dependencia, sin flujos de auth), Testcontainers, JaCoCo, Checkstyle, Maven Wrapper; React 19, Vite, TypeScript, Tailwind, TanStack Query, React Router v7, Vitest, React Testing Library, ESLint.
- **Documentación**: `PROJECT.md` §3, §4, §6 y §9 (estructura, versiones, alcance real de observabilidad) y `README.md` (estado del proyecto) se actualizan al cerrar el change.
- **Fuera de alcance de este change**: lógica de dominio, modelos de datos de negocio, flujos de autenticación, pipeline de Jenkins (`ops/jenkins`), Loki y Tempo (trazas) y la agregación de las especificaciones OpenAPI en el `api-gateway`. Se abordan en changes posteriores.
