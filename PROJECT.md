# PROJECT.md — Domincipe

> **Fuente de verdad** técnica y metodológica del proyecto.
> Léelo junto a [AGENTS.md](./AGENTS.md) (reglas del agente IA) y [openspec/](./openspec/) (SDD).
> Mantenedor: dominguezvazquezdavid · Repositorio: https://github.com/dominguezvazquezdavid/domincipe

---

## 1. Visión y propósito

**Domincipe** es una aplicación web de recetas para uso personal, construida con fines **educativos**. El objetivo no es el producto en sí, sino practicar arquitectura de microservicios con el rigor de un entorno profesional real.

- Sin pagos, sin monetización, sin features comerciales.
- Multi-usuario con roles (`ADMIN`, `USER`) y preferencias (dietas, alérgenos).
- Todo corre en Docker local, **simulando un entorno cloud real**: principios 12-factor, healthchecks, observabilidad, imágenes inmutables y CI/CD con Jenkins.

## 2. Metodología: SDD + OpenSpec

Trabajamos con **Spec-Driven Development (SDD)** orquestado por **OpenSpec** (`@fission-ai/openspec`, versión **2.0.0**, binario `openspec`, licencia MIT, repositorio `Fission-AI/OpenSpec`).

- La **spec es el contrato**: primero se escribe, se revisa y se aprueba; después se implementa.
- Cada cambio vive en `openspec/changes/<id>/` con:
  - `proposal.md` → qué se quiere y por qué (lenguaje de negocio).
  - `specs/` → requirements y scenarios (`## ADDED Requirements`, `#### Scenario:`).
  - `design.md` → cómo se hará (decisiones técnicas).
  - `tasks.md` → checklist ejecutable.
- El ciclo se opera con las *skills* de OpenSpec: `explore`, `propose`, `apply`, `archive` (y opcionales `update`, `sync`, `verify`, `bulk-archive`, que se añaden con `openspec config profile`). Desde la 2.0 las skills viven en `.agents/skills/` y no hay slash commands: en Cline se invocan como `/openspec-apply` o pidiéndoselo al agente.
- Al cerrarse, el change se mueve a `openspec/changes/archive/<fecha>-<change>/` y la spec "as-built" se consolida en `openspec/specs/`.
- La configuración del proyecto (contexto para la IA + schema) vive en **`openspec/config.yaml`** con schema `spec-driven`. **No** usamos `openspec/project.md`: es un formato legacy en esta versión (el `init` no lo crea y propone migrarlo a `config.yaml`).
- **Nada se implementa sin un change aprobado por el usuario.**

## 3. Arquitectura

```
web-frontend (React) ──► api-gateway ──┬─► auth-service
                                        ├─► user-service
                                        ├─► recipe-service ◄──┐
                                        └─► media-service     │
                                                             Kafka (KRaft)
                                                              │
                                                notification-service (consumer)

Persistencia:
  - PostgreSQL 16 (database-per-service)
  - Versity S3 Gateway (S3-compatible sobre POSIX, imágenes de recetas)
  - Mailpit (SMTP fake para email, con UI web y API)

Observabilidad (siempre activa en local):
  - Prometheus + Grafana + Kafka UI (imagen `kafbat/kafka-ui`)
  - Loki + Tempo (pendiente, ver roadmap §10)
```

## 4. Stack tecnológico

| Capa | Tecnología | Versión | Notas |
|---|---|---|---|
| Lenguaje backend | Java | 21.0.13+9 (Temurin LTS) | records, pattern matching, virtual threads |
| Framework | Spring Boot | 4.1.2 | línea 4.x, soportada hasta 2027-07-31; Java 21 |
| Build | Maven | 3.9.16 (wrapper) | multi-módulo; parent POM en raíz |
| Migraciones | Flyway | última | por servicio |
| Persistencia | PostgreSQL | 16 | un schema por servicio, escalable a DB separada |
| Mensajería | Apache Kafka | 4.4.0 KRaft | imagen oficial `apache/kafka:4.4.0`; sin ZooKeeper |
| Almacenamiento de objetos | Versity S3 Gateway | 1.11.0 | S3 sobre POSIX; puerto 7070 |
| Email fake | Mailpit | 1.33.1 | SMTP en 1025, UI/API en 8025 |
| Seguridad | Spring Security + JWT | propio | BCrypt + refresh token |
| Documentación API | springdoc-openapi | 3.2.0 (OpenAPI 3.1) | línea 3.x para Spring Boot 4.x; por servicio |
| Testing backend | JUnit 5, Mockito, AssertJ, Testcontainers, RestAssured | — | ver §8 |
| Cobertura | JaCoCo | — | gate (ver §8) |
| Frontend | React 19 + TypeScript | 19.3.1 / 5.9.3 | TypeScript 5.9.3: la 7.x aún no la soporta `typescript-eslint` 8 |
| Bundler | Vite | 8.3.8 | `@vitejs/plugin-react` 6.3.0 |
| Estado servidor | TanStack Query | 5.107.1 | — |
| Estilos | Tailwind CSS + shadcn/ui | 4.3.5 / CLI 4.23.0 | — |
| Router | React Router | 8.5.1 | exige React ≥ 19.2.7 y Node ≥ 22.22.0 |
| Testing frontend | Vitest + RTL + Playwright | 5.1.0 / 16.3.3 / 1.65.0 | cobertura con `@vitest/coverage-v8` |
| Lint frontend | ESLint + `typescript-eslint` | 10.14.0 / 8.72.2 | configuración plana |
| CI/CD | Jenkins | LTS | corre en Docker |
| Imágenes | Kaniko | — | sin Docker-in-Docker |
| SBOM / escaneo | Syft + Trivy | — | rompe build si HIGH/CRITICAL |
| Observabilidad | Micrometer + Prometheus + Grafana + Loki + Tempo | — | — |
| SDD | OpenSpec (`@fission-ai/openspec`) | 2.0.0 | skills en `.agents/skills/`; requiere **Node ≥ 22.12.0**, el proyecto fija 22.22.0 |

Versiones verificadas en la tarea 1.2 (2026-11-12) contra Maven Central y Docker Hub: Spring Boot **4.1.2**, springdoc-openapi **3.2.0** y `apache/kafka:4.4.0`. Se descarta la línea 3.5 (última 3.5.16) por estar fuera de soporte OSS desde el 2026-06-30; springdoc 2.x (última 2.10.0) solo aplica a Spring Boot 3.x.

Versiones del frontend verificadas el 2026-11-12 en el registro de npm: React **19.3.1**, Vite **8.3.8**, TypeScript **5.9.3**, ESLint **10.14.0**, `typescript-eslint` **8.72.2**, Tailwind **4.3.5**, React Router **8.5.1**, TanStack Query **5.107.1** y Vitest **5.1.0**. TypeScript no se fija en la 7.0.2 porque `typescript-eslint` 8.72.2 declara `typescript >=4.8.4 <6.1.0`; React Router 8.5.1 eleva el mínimo de Node a **22.22.0**.

Almacenamiento de objetos: **Versity S3 Gateway 1.11.0** (`versity/versitygw:v1.11.0`, digest `sha256:8319a530…`) verificado el 2026-11-12; MinIO se descarta porque sus imágenes oficiales ya no se publican (Docker Hub 404, Quay y ghcr sin manifiesto) y su último release upstream es de octubre de 2025. Toolchain local: Temurin **21.0.13+9** y Maven **3.9.16**.

## 5. Bounded contexts (servicios y responsabilidades)

| Servicio | Responsabilidad | BD | Topics Kafka |
|---|---|---|---|
| `api-gateway` | BFF del frontend, routing, CORS, rate-limit | — | — |
| `auth-service` | Login, emisión/renovación de JWT, roles | `auth` schema | — |
| `user-service` | Perfil, preferencias, dietas, alérgenos | `users` schema | produce `user.registered`, `user.updated` |
| `recipe-service` | CRUD recetas, ingredientes, pasos, tags, búsqueda FTS | `recipes` schema | produce `recipe.created/updated/deleted`; consume `media.uploaded` |
| `media-service` | Subida de imágenes, presigned URLs, borrado | `media` schema + Versity | produce `media.uploaded`; consume `recipe.deleted` |
| `notification-service` | Feed de actividad + email (Mailpit) | `notifications` schema | consume todos los anteriores |

**Contrato de eventos**: se formalizará en `openspec/specs/events/spec.md` cuando exista.

## 6. Estructura de carpetas

```
./workspace/domincipe/
├── README.md
├── PROJECT.md           # este documento
├── AGENTS.md            # reglas del agente IA
├── LICENSE              # MIT
├── .gitignore
├── .editorconfig
├── .env.example         # plantilla de configuración (.env real ignorado)
├── .mvn/                # Maven Wrapper (versión de Maven fijada)
├── openspec/            # SDD (generado por `openspec init`)
│   ├── config.yaml      # config del proyecto (schema: spec-driven)
│   ├── specs/           # specs as-built
│   └── changes/         # changes pendientes
│       └── archive/     # changes cerrados + specs consolidadas
├── .agents/             # skills de OpenSpec 2.0 (compartidas por todas las herramientas)
│   └── skills/
├── config/              # configuración compartida de lint (Checkstyle)
├── scripts/             # verificaciones del esqueleto (módulos, imágenes, entorno)
├── apps/
│   ├── web-frontend/    # React + Vite
│   ├── api-gateway/
│   └── services/
│       ├── auth-service/
│       ├── user-service/
│       ├── recipe-service/
│       ├── media-service/
│       └── notification-service/
├── libs/
│   ├── common-dto/
│   └── common-observability/
├── ops/                 # operación del proyecto (local y CI)
│   ├── docker/          # Dockerfiles
│   ├── compose/         # docker-compose.{base,dev,obs}.yml
│   └── jenkins/         # Jenkinsfile, shared library
└── pom.xml              # parent Maven multi-módulo
```

## 7. Convenciones

- **Código en inglés**: clases, métodos, variables, mensajes de commit.
- **Documentación en español**: README, PROJECT.md, specs OpenSpec. Comentarios que expliquen el *por qué*, no el *qué*.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
- **Ramas**: `main` (estable), `feat/<change-id>-<slug>`, `fix/<slug>`.
- **Rama por change**: cada change OpenSpec se implementa en su propia rama; el PR referencia el `change-id`.
- **Package base**: `com.domincipe.<servicio>`.
- **Configuración**: 100% por variables de entorno. `.env.example` versionado, `.env` ignorado.

## 8. Testing

**Pirámide** por servicio:

| Nivel | Backend | Frontend |
|---|---|---|
| Unit | JUnit 5 + Mockito + AssertJ | Vitest + React Testing Library |
| Slice | `@WebMvcTest`, `@DataJpaTest` | Component tests (RTL) |
| Integration | Testcontainers (PostgreSQL + Kafka) | — |
| Contract | Spring Cloud Contract / Pact | MSW (mock service worker) |
| E2E | Testcontainers + RestAssured | Playwright contra `docker compose up` |

**Reglas de validación (Definition of Done):**

- Ningún change se cierra hasta que la **suite COMPLETA** de tests pase: unit + slice + integration + contract + e2e + lint. No solo los nuevos.
- El pipeline Jenkins corre **toda** la suite en cada PR (regresión bloqueante).
- **Nunca** `-DskipTests` en CI.
- **Coverage gate (JaCoCo)**: ≥ 80% líneas y ≥ 70% ramas por módulo. Si baja, el build falla. Excluidos del cómputo: clases `*Application`, DTOs, interfaces, código generado (`*Impl` de MapStruct, getters de Lombok).
- Los tests `e2e` pueden reintentarse **una vez** por flakiness. Unit e integration no se reintentan.
- Herramienta de cobertura backend: **JaCoCo** (informe HTML en `target/site/jacoco/index.html`).

## 9. Entornos

**v1 = local Docker Compose**, con perfil cloud-like:

- `ops/compose/docker-compose.base.yml` — servicios, datos, salud, redes, límites.
- `ops/compose/docker-compose.dev.yml` — override para desarrollo local (hot reload, puertos expuestos).
- `ops/compose/docker-compose.obs.yml` — pila de observabilidad (Prometheus, Grafana, Kafka UI), **siempre activa**.

El comando canónico es `docker compose up --wait` desde la raíz: `.env` declara `COMPOSE_FILE` con los tres ficheros, de modo que la observabilidad se levanta siempre. Para arrancar sin ella (equipos con pocos recursos) se pasan `-f` explícitos sobre `base` y `dev`.

**Principios cloud-like aplicados en local:**

- 12-factor: toda configuración por entorno; cero secretos en imágenes ni en git.
- Service discovery por **DNS de Compose** (mismo modelo que los `Service` de Kubernetes).
- **Healthchecks** en todos los contenedores, con `depends_on: condition: service_healthy` (nunca `sleep`).
- **Graceful shutdown** (`server.shutdown: graceful` + `stop_grace_period`).
- Imágenes **multi-stage, no-root**, con tags inmutables (git SHA) además de `latest`.
- **SBOM (Syft)** y **escaneo Trivy** en Jenkins; rompe el build con CVEs HIGH/CRITICAL.
- **Resource limits** en Compose para simular *requests/limits* de K8s.
- **Redes separadas** (`frontend-net`, `backend-net`, `obs-net`) simulando NetworkPolicies.

**Fuera de alcance v1** (roadmap, ver §10): Kubernetes real (k3d/Helm), Vault, Debezium, Elasticsearch.

## 10. Roadmap / changes futuros

| Idea | Cuándo |
|---|---|
| Keycloak como IdP (reemplaza JWT propio) | cuando haya que federar identidades |
| k3d / Helm charts para desplegar en K8s local | tras v1 estable y con tests verdes |
| Debezium (CDC) en lugar de Outbox con poller | cuando el Outbox con poller quede corto |
| Elasticsearch / OpenSearch para búsqueda | si FTS de PostgreSQL no cubre |
| Vault para gestión de secretos | al simular secretos de producción |
| PIT (mutation testing) semanal | endurecimiento de la suite |
| Migración a MongoDB en `recipe-service` | si los atributos de receta se vuelven muy heterogéneos |

## 11. Glosario

- **SDD**: Spec-Driven Development. Se especifica antes de implementar.
- **OpenSpec**: herramienta que orquesta SDD (changes → specs as-built).
- **Bounded Context**: límite de un modelo de dominio (aquí, un microservicio).
- **Database-per-service**: cada microservicio tiene su propia BD lógica.
- **Outbox pattern**: los eventos se guardan en una tabla `outbox_event` en la misma transacción que el dato; un poller los publica a Kafka. Garantiza "at-least-once" sin perder eventos.
- **KRaft**: modo de Kafka sin ZooKeeper (metadatos gestionados por el propio cluster).
- **FTS**: Full-Text Search (búsqueda de texto completo de PostgreSQL vía `tsvector` + índice GIN).
- **JaCoCo**: herramienta de medición de cobertura de tests en Java.
- **Gate de cobertura**: umbral mínimo que, de no cumplirse, hace fallar el build.
- **Testcontainers**: lanza contenedores reales (Postgres, Kafka) para tests de integración.
- **Presigned URL**: URL temporal firmada para subir/descargar de S3/Versity sin exponer credenciales.
- **SBOM**: Software Bill of Materials (inventario de dependencias).
- **BFF**: Backend For Frontend (el `api-gateway` aquí).
