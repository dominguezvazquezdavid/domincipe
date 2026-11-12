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

Trabajamos con **Spec-Driven Development (SDD)** orquestado por **OpenSpec** (`@fission-ai/openspec`, versión **1.17.0**, binario `openspec`, licencia MIT, repositorio `Fission-AI/OpenSpec`).

- La **spec es el contrato**: primero se escribe, se revisa y se aprueba; después se implementa.
- Cada cambio vive en `openspec/changes/<id>/` con:
  - `proposal.md` → qué se quiere y por qué (lenguaje de negocio).
  - `specs/` → requirements y scenarios (`## ADDED Requirements`, `#### Scenario:`).
  - `design.md` → cómo se hará (decisiones técnicas).
  - `tasks.md` → checklist ejecutable.
- El ciclo se opera con los *workflows* de OpenSpec: `explore`, `propose`, `apply`, `archive` (y opcionales `update`, `sync`, `verify`, `bulk-archive`). Invocación: en Cline se escriben como `/opsx-apply`, desde las skills de `.cline/skills/`.
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
  - MinIO (S3-compatible, imágenes de recetas)
  - MailHog (SMTP fake para email)

Observabilidad (siempre activa en local):
  - Prometheus + Grafana + Kafka UI
  - Loki + Tempo (pendiente, ver roadmap §10)
```

## 4. Stack tecnológico

| Capa | Tecnología | Versión | Notas |
|---|---|---|---|
| Lenguaje backend | Java | 21 LTS | records, pattern matching, virtual threads |
| Framework | Spring Boot | 3.x | última estable |
| Build | Maven | multi-módulo | parent POM en raíz |
| Migraciones | Flyway | última | por servicio |
| Persistencia | PostgreSQL | 16 | un schema por servicio, escalable a DB separada |
| Mensajería | Apache Kafka | 4.x KRaft | sin ZooKeeper |
| Almacenamiento de objetos | MinIO | última | S3-compatible |
| Email fake | MailHog | última | captura SMTP |
| Seguridad | Spring Security + JWT | propio | BCrypt + refresh token |
| Documentación API | springdoc-openapi | OpenAPI 3.1 | por servicio |
| Testing backend | JUnit 5, Mockito, AssertJ, Testcontainers, RestAssured | — | ver §8 |
| Cobertura | JaCoCo | — | gate (ver §8) |
| Frontend | React 19 + TypeScript | 19.x | — |
| Bundler | Vite | última | — |
| Estado servidor | TanStack Query | última | — |
| Estilos | Tailwind CSS + shadcn/ui | última | — |
| Router | React Router | v7 | — |
| Testing frontend | Vitest + RTL + Playwright | — | — |
| CI/CD | Jenkins | LTS | corre en Docker |
| Imágenes | Kaniko | — | sin Docker-in-Docker |
| SBOM / escaneo | Syft + Trivy | — | rompe build si HIGH/CRITICAL |
| Observabilidad | Micrometer + Prometheus + Grafana + Loki + Tempo | — | — |
| SDD | OpenSpec (`@fission-ai/openspec`) | 1.17.0 | requiere **Node ≥ 22.12.0**; tool id `cline` |

## 5. Bounded contexts (servicios y responsabilidades)

| Servicio | Responsabilidad | BD | Topics Kafka |
|---|---|---|---|
| `api-gateway` | BFF del frontend, routing, CORS, rate-limit | — | — |
| `auth-service` | Login, emisión/renovación de JWT, roles | `auth` schema | — |
| `user-service` | Perfil, preferencias, dietas, alérgenos | `users` schema | produce `user.registered`, `user.updated` |
| `recipe-service` | CRUD recetas, ingredientes, pasos, tags, búsqueda FTS | `recipes` schema | produce `recipe.created/updated/deleted`; consume `media.uploaded` |
| `media-service` | Subida de imágenes, presigned URLs, borrado | `media` schema + MinIO | produce `media.uploaded`; consume `recipe.deleted` |
| `notification-service` | Feed de actividad + email (MailHog) | `notifications` schema | consume todos los anteriores |

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
├── .cline/              # skills de OpenSpec para Cline
│   └── skills/
├── .clinerules/         # workflows de OpenSpec para Cline
│   └── workflows/
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
- **Presigned URL**: URL temporal firmada para subir/descargar de S3/MinIO sin exponer credenciales.
- **SBOM**: Software Bill of Materials (inventario de dependencias).
- **BFF**: Backend For Frontend (el `api-gateway` aquí).
