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
- El ciclo (`explore` → `propose` → `apply` → `archive`) se opera con las *skills* de OpenSpec. La operativa de la herramienta —invocación, workflows y CLI— es contexto del agente y vive en `AGENTS.md` §8.
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
  - PostgreSQL 16.16 (database-per-service)
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
| Persistencia | PostgreSQL | 16.16 | imagen `postgres:16.16-alpine`; un schema por servicio, escalable a DB separada |
| Mensajería | Apache Kafka | 4.4.0 KRaft | imagen oficial `apache/kafka:4.4.0`; sin ZooKeeper |
| Almacenamiento de objetos | Versity S3 Gateway | 1.11.0 | S3 sobre POSIX; puerto 7070 |
| Email fake | Mailpit | 1.33.1 | SMTP en 1025, UI/API en 8025 |
| Seguridad | Spring Security + JWT | propio | BCrypt + refresh token |
| Documentación API | springdoc-openapi | 3.2.0 (OpenAPI 3.1) | línea 3.x para Spring Boot 4.x; por servicio |
| Testing backend | JUnit 5, Mockito, AssertJ, Testcontainers, RestAssured | 2.0.5 / 6.3.0 | Testcontainers por el BOM de Spring Boot; RestAssured fijado en el padre (Boot no lo gestiona) |
| Cobertura | JaCoCo | — | gate (ver §8) |
| Frontend | React 19 + TypeScript | 19.3.1 / 5.9.3 | TypeScript 5.9.3: la 7.x aún no la soporta `typescript-eslint` 8 |
| Bundler | Vite | 8.3.8 | `@vitejs/plugin-react` 6.3.0 |
| Estado servidor | TanStack Query | 5.107.1 | — |
| Estilos | Tailwind CSS + shadcn/ui | 4.3.5 / CLI 4.23.0 | — |
| Router | React Router | 8.5.1 | exige React ≥ 19.2.7 y Node ≥ 22.22.0 |
| Testing frontend | Vitest + RTL + Playwright | 5.1.0 / 16.3.3 / 1.65.0 | cobertura con `@vitest/coverage-v8` |
| Lint frontend | ESLint + `typescript-eslint` | 10.14.0 / 8.72.2 | configuración plana |
| CI/CD | Jenkins | 2.580.2 LTS | imagen propia `ops/jenkins/Dockerfile` (Temurin 21.0.13+9, Maven 3.9.16, Node.js 22.23.5, `buildctl`, Syft y Trivy) con los plugins fijados en `ops/jenkins/plugins.txt`; corre en Docker |
| Contenedores | Docker Engine + Compose | 29.10.0 / v5.7.1 | plugin `docker compose`; `up --wait` y healthchecks en todos los servicios |
| Daemon de test | Docker-in-Docker | 29.10.0 | `docker:29.10.0-dind` en el stack de CI, el único contenedor privilegiado; sirve integration, e2e y la batería de entorno |
| Imágenes | BuildKit rootless | 0.35.0 | `moby/buildkit:v0.35.0-rootless` como `buildkitd`; `buildctl` construye sin daemon ni socket; Kaniko se descarta porque está archivado desde el 2025-06-03 |
| SBOM / escaneo | Syft + Trivy | 1.57.2 / 0.76.2 | CycloneDX con `syft`; `trivy` rompe el build si HIGH/CRITICAL |
| Observabilidad (métricas) | Micrometer + Prometheus | Prometheus 3.16.0 | `/actuator/prometheus` en los seis servicios; *scrape* cada 15 s por DNS de `obs-net` |
| Dashboards | Grafana | 13.3.1 | puerto 3000; sin dashboards aprovisionados todavía |
| UI de Kafka | Kafka UI (`kafbat/kafka-ui`) | 1.5.0 | fork mantenido de `provectuslabs/kafka-ui`; puerto 8087 |
| Trazas y logs | Loki + Tempo | — | pendiente (roadmap §10): el change `project-skeleton` solo levanta métricas |
| SDD | OpenSpec (`@fission-ai/openspec`) | 2.0.0 | skills en `.agents/skills/`; requiere **Node ≥ 22.12.0**, el proyecto fija 22.22.0 |

Versiones verificadas en la tarea 1.2 (2026-11-12) contra Maven Central y Docker Hub: Spring Boot **4.1.2**, springdoc-openapi **3.2.0** y `apache/kafka:4.4.0`. Se descarta la línea 3.5 (última 3.5.16) por estar fuera de soporte OSS desde el 2026-06-30; springdoc 2.x (última 2.10.0) solo aplica a Spring Boot 3.x.

Versiones del frontend verificadas el 2026-11-12 en el registro de npm: React **19.3.1**, Vite **8.3.8**, TypeScript **5.9.3**, ESLint **10.14.0**, `typescript-eslint` **8.72.2**, Tailwind **4.3.5**, React Router **8.5.1**, TanStack Query **5.107.1** y Vitest **5.1.0**. TypeScript no se fija en la 7.0.2 porque `typescript-eslint` 8.72.2 declara `typescript >=4.8.4 <6.1.0`; React Router 8.5.1 eleva el mínimo de Node a **22.22.0**.

Almacenamiento de objetos: **Versity S3 Gateway 1.11.0** (`versity/versitygw:v1.11.0`, digest `sha256:8319a530…`) verificado el 2026-11-12; MinIO se descarta porque sus imágenes oficiales ya no se publican (Docker Hub 404, Quay y ghcr sin manifiesto) y su último release upstream es de octubre de 2025. Toolchain local: Temurin **21.0.13+9** y Maven **3.9.16**.

Imágenes base de los Dockerfiles verificadas el 2026-11-16 en el registro de Docker Hub: `maven:3.9.16-eclipse-temurin-21-alpine` (coincide con el Maven del wrapper), `eclipse-temurin:21.0.13_9-jre-alpine` (coincide con el Temurin local), `node:22.23.5-alpine` (cumple el mínimo 22.22.0 del frontend; la 22.24.0 aún no existe) y `nginxinc/nginx-unprivileged:1.30.6-alpine` (línea estable, UID 101 y puerto 8080).

Imágenes de la pila de observabilidad verificadas el 2026-11-17 contra Docker Hub: `prom/prometheus:v3.16.0` y `grafana/grafana:13.3.1` son las últimas publicadas y su digest **coincide** con el del tag `latest`; `kafbat/kafka-ui:v1.5.0` es la última release del proyecto. Con esas tres versiones, `docker compose up --wait` deja la pila sana y `/api/v1/targets` de Prometheus devuelve los seis objetivos en estado `up` (tareas 8.1 y 8.2).

Las imágenes de las dependencias que fija `ops/compose/docker-compose.base.yml` coinciden con esta tabla y se comprobaron en el entorno en marcha el 2026-11-17: `postgres:16.16-alpine` (postgres y postgres-init), `axllent/mailpit:v1.33.1`, `apache/kafka:4.4.0` (por `KAFKA_IMAGE`, también en kafka-init), `versity/versitygw:v1.11.0` (por `S3_IMAGE`) y `amazon/aws-cli:2.40.3` (cliente con el que versity-init crea el bucket).

Versiones de CI verificadas el 2026-11-17 contra Docker Hub y GitHub: Jenkins **2.580.2** LTS (`jenkins/jenkins:2.580.2-lts-jdk21`, digest `sha256:74401de6…`, release 2026-10-28), BuildKit rootless **0.35.0** (`moby/buildkit:v0.35.0-rootless`, digest `sha256:5987568f…`, release 2026-11-11), Syft **1.57.2** (`anchore/syft:v1.57.2`, digest `sha256:e97e20b6…`, release 2026-11-16) y Trivy **0.76.2** (`aquasec/trivy:0.76.2`, digest `sha256:8f6bb947…`, release 2026-11-05). La imagen del controlador (`ops/jenkins/Dockerfile`) declara las seis versiones de la toolchain en `ARG` y las afirma durante el build: dentro de la imagen `java -version` reporta Temurin 21.0.13+9 —el JDK que ya trae la etiqueta `-jdk21`, idéntico al local, por eso no se reinstala—, `mvn -v` 3.9.16, `node -v` 22.23.5, `buildctl --version` 0.35.0, `syft version` 1.57.2 y `trivy --version` 0.76.2 (tarea 2.1). Los **76** plugins fijados en `ops/jenkins/plugins.txt` son exactamente los que el controlador carga, versión a versión, tras un arranque en frío (tarea 2.2).

Versión de la herramienta de release verificada el 2026-11-19 contra Maven Central: `versions-maven-plugin` **2.25.2**, la última publicada (`maven-metadata.xml` con `lastUpdated` 2026-11-14). Se invoca con `-DprocessAllModules` y `-DgenerateBackupPoms=false`, comprobado en la práctica: recorre el reactor entero y no deja ficheros `pom.xml.versionsBackup`.

Versiones del nivel de integration y del e2e verificadas el 2026-11-19 (change `ci-integration`): Testcontainers **2.0.5** por el BOM que importa `spring-boot-dependencies` 4.1.2 (`testcontainers.version`, línea 209), con los módulos 2.x `testcontainers-junit-jupiter`, `testcontainers-postgresql` y `testcontainers-kafka` —paquetes `org.testcontainers.postgresql` y `org.testcontainers.kafka`, no las clases de compatibilidad de 1.x—; RestAssured **6.3.0**, la última estable de `io.rest-assured:rest-assured` (`7.0.0-RC1` se descarta por ser *release candidate*); Playwright **1.65.0** en npm y su imagen `mcr.microsoft.com/playwright:v1.65.0-noble` (digest `sha256:9beb5460…`). Imágenes del daemon de test verificadas el mismo día: `docker:29.10.0-dind` (`sha256:4bbc7223…`; el tag `-rootless` existe, `sha256:5a703ad0…`, y queda como deuda si se demuestra que arranca sin privilegios), cliente Docker estático 29.10.0 (HTTP 200 en `download.docker.com`) y plugin Compose v5.7.1 (asset `docker-compose-linux-x86_64` del release de `docker/compose`). Para el cliente del apagado ordenado, `python:3.13-alpine` (`sha256:9ef1a599…`).


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
├── .gitattributes       # normalización de fin de línea (blob en LF, *.cmd en CRLF)
├── .dockerignore        # contexto de build que reciben los Dockerfiles
├── .editorconfig
├── .env.example         # plantilla de configuración (.env real ignorado)
├── .mvn/                # Maven Wrapper (versión fijada y suma SHA-256 del zip)
├── mvnw                 # lanzador del wrapper (POSIX)
├── mvnw.cmd             # lanzador del wrapper (Windows; se guarda en LF y sale en CRLF)
├── openspec/            # SDD (generado por `openspec init`)
│   ├── config.yaml      # config del proyecto (schema: spec-driven)
│   ├── specs/           # specs as-built
│   └── changes/         # changes pendientes
│       └── archive/     # changes cerrados + specs consolidadas
├── .agents/             # skills de OpenSpec 2.0 (compartidas por todas las herramientas)
│   └── skills/
├── config/              # configuración compartida de lint (Checkstyle)
├── scripts/             # verificaciones: módulos, imágenes, entorno y apagado ordenado
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
│   ├── common-observability/
│   └── common-test-support/   # anotaciones compuestas de test (§7, D14)
├── ops/                 # operación del proyecto (local y CI)
│   ├── docker/          # Dockerfiles (java-service, web-frontend) y nginx.conf
│   ├── compose/         # docker-compose.{base,dev,obs}.yml
│   │   └── obs/         # prometheus.yml (scrape de los seis servicios)
│   └── jenkins/         # stack de CI local: controlador Jenkins + builder rootless
│       ├── Dockerfile           # controlador con la toolchain fijada en ARG (§4)
│       ├── docker-compose.yml   # los dos servicios, su red y los siete volúmenes
│       └── plugins.txt          # los 76 plugins con su versión exacta
└── pom.xml              # parent Maven multi-módulo
```

## 7. Convenciones

- **Código en inglés**: clases, métodos, variables, mensajes de commit y **todos los comentarios de ficheros de código o de configuración/build** (`pom.xml`, `config/checkstyle/*.xml`, `.editorconfig`, `.gitignore`, `.gitattributes`, `Dockerfile`, Compose, scripts).
- **Documentación en español**: README, PROJECT.md, AGENTS.md y specs OpenSpec (incluido `openspec/config.yaml`). El idioma de un comentario lo decide **el tipo de fichero**, no el tema del que habla, y **no hay excepciones** por tamaño del fichero ni por quién lo lea. Los comentarios explican el *por qué*, no el *qué*.
- **Commits**: Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
- **Ramas (Gitflow-lite)**: dos permanentes —`main` (solo releases estables y funcionales) y `develop` (integración, **rama por defecto**)— y cuatro tipos cortos: `feat/<change-id>-<slug>`, `fix/<slug>`, `release/<x.y.z>` y `hotfix/<x.y.z>`. **No hay rama `release` permanente**: el release es una rama efímera de congelado y lo que sobrevive es el tag `vX.Y.Z` sobre `main`.
- **Rama por change**: cada change OpenSpec se implementa en su propia rama `feat/<change-id>-<slug>`, que **nace de `develop`**; el PR referencia el `change-id` y se abre contra `develop`.
- **Merge de PRs: `squash and merge`, y solo ese método.** En el repositorio están activos `allow_squash_merge=true` con `allow_merge_commit=false` y `allow_rebase_merge=false`, de modo que **un change = un commit** en `main`: historial lineal, `git log` legible y revert del change completo en una sola operación. Consecuencias asumidas, que no se replantean sin cambiar esta sección: (a) el **asunto del commit resultante es el título del PR**, así que el título debe ser un Conventional Commit y el cuerpo del commit se redacta al mergear (`gh pr merge --squash -t … -b …`); (b) los commits granulares de la rama **no** llegan a `main`, y el rastro por tarea con su verificación se conserva en el `tasks.md` del change, que sobrevive al archivado en `openspec/changes/archive/<fecha>-<change>/`; (c) la rama remota se borra sola al mergear (`delete_branch_on_merge=true`) y la copia local se descarta con `git branch -D`, porque tras un squash git no la reconoce como mergeada.
- **Ciclo de release**: (1) `release/<x.y.z>` nace de `develop` y queda **congelada**: solo arreglos, ninguna feature nueva; (2) se ejecuta la batería completa sobre un entorno **recreado**: `./mvnw -B -ntp verify`, `npm ci && npm run lint && npm run build && npm test`, `scripts/build-images.sh` (las siete imágenes del árbol ya comiteado —la etiqueta es el SHA, así que el script se niega a construir con cambios pendientes—, porque Compose consume `latest` y sin este paso el entorno certificado arranca artefactos de otro commit), `docker compose down -v` seguido de `up --wait` desde cero, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh` y `scripts/verify-version.sh`; (3) PR `release → main` con squash y tag anotado `vX.Y.Z`; (4) back-merge a `develop` como PR de contenido que lleva la versión liberada, de modo que `develop` solo vuelva a declarar un `-SNAPSHOT` cuando una rama le añada trabajo; (5) la rama `release/<x.y.z>` se borra al mergear. El CI solo automatiza el **gate de PR** (§8); esta batería sigue ejecutándose a mano y su automatización es el change `ci-integration`.
- **Versionado (Maven, un número por aplicación)**: SemVer en **un solo sitio**, la versión del parent POM que los diez módulos heredan por `<parent>`, replicada en `apps/web-frontend/package.json`. La versión es la de la **aplicación completa**, no la de cada servicio: los servicios evolucionan por separado, pero lo que se libera es un producto. `v1.0.0` marca el MVP; hasta entonces, `0.x.y`, y **el alcance del change decide el incremento**: lo que añade capacidades sube el *minor* (`0.3.0`), la documentación o un ajuste suben el *patch* (`0.2.1`). **La rama del change declara el objetivo**: el cambio de versión viaja en el diff de su PR, con `./mvnw -B -ntp versions:set -DnewVersion=<x.y.z>-SNAPSHOT -DprocessAllModules -DgenerateBackupPoms=false` y `npm version <x.y.z>-SNAPSHOT --no-git-tag-version`, y dentro de un ciclo solo puede moverla **hacia arriba**. Así `develop` declara la versión liberada mientras su árbol sea el de la release, y `X.Y.Z-SNAPSHOT` en cuanto una rama le añade contenido: el back-merge nunca pre-asigna la release siguiente. La rama `release/<x.y.z>` **solo quita el sufijo** (`0.3.0-SNAPSHOT` → `0.3.0`), porque el número ya lo eligieron las ramas; el tag anotado `vX.Y.Z` se crea **sobre `main`** al mergear y nunca se mueve ni se borra; y el back-merge deja `develop` en la versión liberada. Regla dura: **lo etiquetado nunca lleva `-SNAPSHOT`**, porque un SNAPSHOT es un identificador que puede cambiar de contenido y `main` solo contiene releases. `scripts/verify-version.sh` comprueba las dos orillas de la regla: que un árbol distinto del último tag anuncie `-SNAPSHOT` —y que solo una rama `release/` declare versión sin sufijo, coincidiendo con su nombre— y que los artefactos en marcha declaren la versión del árbol. Todo esto se ejecuta en el host, no en el pipeline (el gate no versiona), y con `versions-maven-plugin` fijado en el parent. Se desvía a propósito de `maven-release-plugin`: ese plugin crea el tag en la rama donde corre y deja siempre un `-SNAPSHOT` posterior, mientras que aquí el tag va sobre `main` —que solo recibe squash—, no hay repositorio de artefactos y la decisión de versión pertenece al alcance de cada change.
- **Protección de ramas**: `main` y `develop` exigen PR (sin pushes directos), prohíben force-push y borrado, y `main` exige historial lineal; los tags `v*` no se pueden borrar ni actualizar. Con un solo mantenedor las aprobaciones requeridas son 0 —no se puede aprobar el PR propio— y los *status checks* bloqueantes son el **gate de PR**: las dos ramas exigen el estado que publica el job `domincipe` de Jenkins sobre el commit del PR y rechazan el merge mientras ese estado esté en rojo (§9).
- **Package base**: `com.domincipe.<servicio>`.
- **Configuración**: 100% por variables de entorno. `.env.example` versionado, `.env` ignorado.
- **Propiedades repetidas**: toda propiedad de configuración que se repita en más de un módulo o clase se declara **una sola vez** en un fichero `.properties` (del módulo o compartido), nunca copiada en cada clase. En los tests, la forma prevista es una anotación compuesta compartida sobre `@SpringBootTest` (decisión D14 del change `project-skeleton`, tarea 5.2).

## 8. Testing

**Pirámide** por servicio:

| Nivel | Backend | Frontend |
|---|---|---|
| Unit | JUnit 5 + Mockito + AssertJ | Vitest + React Testing Library |
| Slice | `@WebMvcTest`, `@DataJpaTest` | Component tests (RTL) |
| Integration | Testcontainers (PostgreSQL + Kafka) | — |
| Contract | Spring Cloud Contract / Pact | MSW (mock service worker) |
| E2E | Testcontainers + RestAssured | Playwright contra `docker compose up` |

La frontera entre ambos bloques es el **daemon Docker**, y desde el change `ci-integration` el gate de PR tiene uno propio: un contenedor `docker:dind` del stack de CI, aislado del daemon de desarrollo (§9). Por eso la pirámide entera se ejecuta en el gate y la batería de release deja de ser el único sitio donde se certifican integration y e2e.

**Suite de PR (bloqueante, con daemon de test):** es la que ejecuta Jenkins en cada PR y la que decide si un change puede mergearse.

- **Backend**: `./mvnw -B -ntp clean verify`, una sola invocación para toda la suite: unit y slice con JUnit 5, Mockito y AssertJ, el contract de Spring Cloud Contract / Pact cuando exista, **integration** con Testcontainers (PostgreSQL + Kafka) por `maven-failsafe-plugin`, Checkstyle y gate JaCoCo. Antes de Maven, la etapa comprueba que el daemon responde y falla nombrando la causa si no lo hace.
- **Frontend**: `npm ci`, `npm run lint`, `npm run build` y `npm test` (Vitest + React Testing Library, con MSW en los contract tests cuando existan), dentro de `apps/web-frontend`.
- **Paralelismo**: backend, frontend e imágenes corren a la vez y cualquiera de ellos en rojo tumba el build; un rojo no espera a sus hermanos. Integration viaja dentro de la mitad backend porque comparte el `target/` con la compilación y separarla exigiría dos Maven sobre el mismo árbol.
- Imágenes, SBOM y escaneo de vulnerabilidades forman parte del mismo gate, pero no de esta sección: se describen en §9.
- **Sin omisión**: ni `-DskipTests`, ni `-DskipITs`, ni exclusiones de módulos. Que un nivel corra en una etapa propia no lo saca del gate.

**Batería de release (con Docker: entorno recreado y artefactos):** completa la suite de PR con lo que solo tiene sentido sobre un entorno real:

- **Entorno**: `docker compose up --wait` desde cero sobre un entorno recreado, `scripts/verify-environment.sh` y `scripts/verify-shutdown.sh`.
- **E2E**: además del e2e de backend y del smoke de Playwright que ya corre en el gate, la comprobación contra las **imágenes construidas** en el host, tal como las publica el ciclo de release (§7).
- Se ejecuta **en el host**, dentro del ciclo de release (§7), y es la que certifica el artefacto, no solo el código. El gate de PR ejecuta la misma batería sobre el daemon de test del stack de CI (§9), con el proyecto e2e aislado y sin publicar puertos.
- **Nunca** se reutiliza el socket del daemon de desarrollo: el daemon de test es un contenedor propio del stack.

**Reglas de validación (Definition of Done):**

- Ningún change se cierra con la **suite de PR** en rojo: todos los niveles que el árbol tenga —unit, slice, contract, integration y e2e—, lint y cobertura, no solo los tests nuevos. Es el gate bloqueante de Jenkins.
- Un change que añada o modifique tests de **integration** o **e2e** deja la evidencia de su ejecución en el gate en su `tasks.md`; si además toca el entorno o las imágenes, ejecuta la batería de release en el host antes de darse por cerrado.
- Antes de cada release se ejecuta la **batería de release completa** sobre un entorno recreado, dentro del ciclo de release (§7); ningún tag sale con ella en rojo.
- **Nunca** `-DskipTests` en CI, ni exclusiones de módulos, ni umbrales rebajados para salir del paso.
- **Coverage gate (JaCoCo)**: ≥ 80% líneas y ≥ 70% ramas por módulo, medido **solo** sobre unit y slice. La cobertura de integration se publica aparte (`target/site/jacoco-it`) y no alimenta el umbral: un módulo no puede pasar el gate a base de ITs. Si baja, el build falla. Excluidos del cómputo: clases `*Application`, DTOs, interfaces, código generado (`*Impl` de MapStruct, getters de Lombok).
- Los tests `e2e` pueden reintentarse **una vez** por flakiness. Unit e integration no se reintentan.
- Herramienta de cobertura backend: **JaCoCo** (informe HTML en `target/site/jacoco/index.html`; el de integration, en `target/site/jacoco-it/index.html`).

## 9. Entornos

**v1 = local Docker Compose**, con perfil cloud-like:

- `ops/compose/docker-compose.base.yml` — servicios, datos, salud, redes, límites.
- `ops/compose/docker-compose.dev.yml` — override para desarrollo local: puertos publicados en el host y volúmenes persistentes de datos. El **hot reload del frontend** se ejecuta en el host (`VITE_API_BASE_URL=http://localhost:8080 npm run dev`); Compose sirve siempre el bundle inmutable de nginx.
- `ops/compose/docker-compose.obs.yml` — pila de observabilidad (Prometheus, Grafana, Kafka UI), **siempre activa**.

El comando canónico es `docker compose up --wait` desde la raíz: `.env` declara `COMPOSE_FILE` con los tres ficheros, de modo que la observabilidad se levanta siempre. Para arrancar sin ella (equipos con pocos recursos) se pasan `-f` explícitos sobre `base` y `dev`.

**Principios cloud-like aplicados en local:**

- 12-factor: toda configuración por entorno; cero secretos en imágenes ni en git.
- Service discovery por **DNS de Compose** (mismo modelo que los `Service` de Kubernetes).
- **Healthchecks** en todos los contenedores, con `depends_on: condition: service_healthy` (nunca `sleep`).
- **Graceful shutdown** (`server.shutdown: graceful` + `stop_grace_period`).
- Imágenes **multi-stage, no-root**, con tags inmutables (git SHA) además de `latest`. El tag de versión (`:<x.y.z>`) **no** se publica todavía: en un build de PR la versión es un `-SNAPSHOT`, que no identifica el commit, y no hay registro al que empujarlo. Entrará con el registro, solo desde un commit etiquetado, sin sobrescritura, y con `latest` moviéndose únicamente en release. La **batería de release** construye las siete imágenes con `scripts/build-images.sh` antes de recrear el entorno, porque Compose consume `latest` y sin ese paso el entorno certificado correría artefactos de otro commit (medido: 210 s con las capas base y la caché del builder calientes).
- **SBOM (Syft)** y **escaneo Trivy** en el gate de PR; rompe el build con CVEs HIGH/CRITICAL salvo excepción versionada, con motivo y caducidad, en `ops/jenkins/.trivyignore`.
- **Resource limits** en Compose para simular *requests/limits* de K8s.
- **Redes separadas** (`frontend-net`, `backend-net`, `obs-net`) simulando NetworkPolicies.

**Entorno de integración continua (`ops/jenkins/`)** — deliberadamente **fuera** del `COMPOSE_FILE` de desarrollo: el CI no arranca con `docker compose up` y un CI caído no impide levantar la aplicación.

- **Arranque**: `docker compose -f ops/jenkins/docker-compose.yml up --wait`. Red propia (`ci-net`), puerto **8095** del host para el controlador (8080-8087, 8090, 9090, 3000, 7070, 8025, 1025 y 29092 ya están ocupados), y ningún `.env` obligatorio en `ops/jenkins/`: cada valor trae su default en el fichero y el PAT llega por `GITHUB_TOKEN`.
- **Tres contenedores**: el controlador `jenkins` (imagen propia de `ops/jenkins/Dockerfile` con la toolchain de §4), el builder `buildkitd` (`moby/buildkit:v0.35.0-rootless`) y el daemon de test `dind` (`docker:29.10.0-dind`). Ninguno monta `/var/run/docker.sock`: el socket del entorno de desarrollo no entra en el stack (design D1 del change `ci-integration`).
- **Daemon de test**: `dind` es el **único contenedor privilegiado** del stack y la excepción está escrita, no escondida. La imagen oficial documenta `--privileged` como requisito para que Docker-in-Docker funcione; a cambio, el stack tiene un daemon propio para integration, e2e y la batería de entorno, sin tocar el del desarrollador. No construye imágenes —eso sigue siendo `buildkitd`—, no publica puertos (`DOCKER_TLS_CERTDIR` vacío, escucha en 2375 solo dentro de `ci-net`) y no recibe credenciales. Su espacio y su disponibilidad se comprueban en `scripts/ci-preflight.sh`. La deuda declarada es migrar a `docker:dind-rootless` si una verificación demuestra que funciona sin privilegios.
- **Builder real**: BuildKit rootless 0.35.0 como **UID 1000** dentro de su contenedor, sin `privileged:`, con los tres `--security-opt` que rootless BuildKit documenta para contenedores —`seccomp=unconfined`, `apparmor=unconfined` y `systempaths=unconfined`—. Qué son y qué no: sin `systempaths=unconfined` cada `RUN` falla al montar su propio `/proc` (`operation not permitted`), y la ganancia real es **no ejecutar como root**, no un aislamiento reforzado. Docker 29.10.0 no muestra `systempaths` en `docker inspect` aunque lo aplique, así que la única comprobación válida es un build que llegue a un `RUN`.
- **Comunicación**: el `buildctl` del controlador construye hablando con `buildkitd` por el socket Unix `/run/user/1000/buildkit/buildkitd.sock`, compartido con el volumen `buildkit-run`. El healthcheck del builder —y primer paso del pipeline— es `buildctl debug workers`, que distingue «worker listo» de «socket presente».
- **Caché y artefactos**: `/cache` (`type=local`) y `/out` (archivos OCI, un `.tar` por imagen con `sha` y `latest` sobre el mismo manifiesto) son volúmenes del **controlador**, porque quien los escribe es el cliente `buildctl`; la etapa `Images` vacía `/out` al empezar.
- **Qué ejecuta el gate de PR**, mismo orden y mismo alcance que el `Jenkinsfile`: primer grupo, en paralelo con `failFast` —**Backend** (`docker info` contra el daemon de test y `./mvnw -B -ntp clean verify`, que incluye unit, slice, integration, checkstyle y gate JaCoCo), **Frontend** (`npm ci`, `npm run lint`, `npm run build` y `npm test`) e **Images** (las siete imágenes contra el builder rootless)—; segundo grupo, en paralelo —**E2E** (proyecto Compose propio sobre el daemon de test, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh` y smoke de Playwright), **SBOM** (CycloneDX por imagen con Syft) y **Scan** (Trivy con umbral HIGH/CRITICAL y el fichero de excepciones versionado)—. Los informes (cobertura de unit y de integration, resultados de surefire y failsafe, junit de Playwright, trazas del fallo, SBOM y JSON de Trivy) se archivan también en los builds rojos, con retención de 10 builds o 30 días.
- **Publicación**: el *branch source* escanea el repositorio cada **5 minutos** —sin webhooks, porque el controlador vive en `localhost` y GitHub no puede entregarlos— y el estado del build se publica sobre el commit del PR con el PAT del almacén de credenciales (§7).
- **El proyecto e2e del gate**: `ops/compose/docker-compose.base.yml` + `ops/compose/docker-compose.ci.yml`, con nombre propio (`domincipe-ci-e2e`) y **sin publicar puertos**, para no competir con el entorno de desarrollo ni con el 8095 del controlador. Las imágenes que usa son las que certificó la etapa `Images`, cargadas en el daemon de test.

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
