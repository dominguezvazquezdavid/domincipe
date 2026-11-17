# Domincipe

Web de recetas para uso personal, construida como **proyecto educativo**: el objetivo no es el producto, sino practicar arquitectura de microservicios con el rigor de un entorno de producción real (12-factor, healthchecks, observabilidad, imágenes inmutables y CI/CD).

- Sin pagos ni monetización.
- Multi-usuario con roles (`ADMIN`, `USER`) y preferencias (dietas, alérgenos).
- Todo corre en Docker local simulando un entorno cloud.

> Documentación de referencia: [PROJECT.md](./PROJECT.md) (fuente de verdad técnica y metodológica) y [AGENTS.md](./AGENTS.md) (reglas de trabajo con agentes de IA).

---

## Estado actual

El change `project-skeleton` está implementado y verificado: el repositorio contiene el esqueleto ejecutable completo —parent POM multi-módulo, seis servicios, frontend, imágenes Docker y entorno Compose con observabilidad siempre activa—.

| Elemento | Estado |
|---|---|
| Documentación (`README.md`, `PROJECT.md`, `AGENTS.md`) | ✅ Disponible |
| Metodología SDD con OpenSpec (`openspec/`) | ✅ Inicializada (`schema: spec-driven`) |
| Change `project-skeleton` | ✅ Implementado y verificado — pendientes la documentación del PR (tarea 2.4) y el archivado del change |
| Parent POM, módulos Java y frontend | ✅ Disponible (`./mvnw -B -ntp verify`) |
| Imágenes Docker y Compose (base + dev + obs) | ✅ Disponible (`docker compose up --wait`) |
| Observabilidad (Prometheus, Grafana, Kafka UI) | ✅ Siempre activa, sin `profiles` |
| Swagger UI y OpenAPI por servicio | ✅ Disponible con `APP_DOCS_ENABLED=true` |

Ningún artefacto de código se genera sin que su change de OpenSpec esté aprobado y su suite de tests en verde.

---

## Requisitos

| Herramienta | Versión mínima | Uso |
|---|---|---|
| JDK | 21.0.13+9 (Temurin LTS) | Backend Spring Boot |
| Maven | 3.9.16 (vía wrapper `./mvnw`) | Build multi-módulo |
| Node.js | ≥ 22.22.0 | Frontend y CLI de OpenSpec (React Router 8.5 lo exige) |
| npm | 10+ | Dependencias del frontend y del CLI |
| Docker Engine + `docker compose` | 29.10.0 / Compose v5.7.1 (versiones probadas) | Entorno local completo |
| `openspec` CLI | 2.0.0 | Flujo SDD (`@fission-ai/openspec`) |

Instalación del CLI de OpenSpec:

```bash
npm install -g @fission-ai/openspec@latest
openspec --version
```

---

## Arranque rápido

```bash
git clone git@github.com:dominguezvazquezdavid/domincipe.git
cd domincipe
cp .env.example .env        # configuración local; .env nunca se versiona
```

Backend y frontend (la suite completa, con lint y gate de cobertura):

```bash
./mvnw -B -ntp verify       # build multi-módulo + toda la suite backend

cd apps/web-frontend
export VITE_API_BASE_URL=http://localhost:8080   # Vite la exige en build y en test
npm ci && npm run lint && npm run build && npm test
```

Entorno completo en Docker (servicios, dependencias y observabilidad):

```bash
docker compose up --wait    # usa COMPOSE_FILE declarado en .env
```

La pila de observabilidad (Prometheus, Grafana y Kafka UI) se levanta **siempre**, porque `.env.example` declara `COMPOSE_FILE` con los tres ficheros de Compose. Para arrancar sin ella —por ejemplo en una máquina con pocos recursos— se pasan los ficheros explícitos sin el de observabilidad:

```bash
docker compose -f ops/compose/docker-compose.base.yml \
               -f ops/compose/docker-compose.dev.yml up --wait   # sin observabilidad
```

### Puertos publicados

| Servicio | URL / puerto en el host |
|---|---|
| `web-frontend` (nginx) | http://localhost:8086 |
| `api-gateway` (BFF) | http://localhost:8080 |
| `auth-service` | http://localhost:8081 |
| `user-service` | http://localhost:8082 |
| `recipe-service` | http://localhost:8083 |
| `media-service` | http://localhost:8084 |
| `notification-service` | http://localhost:8085 |
| Prometheus | http://localhost:9090 (`/api/v1/targets`) |
| Grafana | http://localhost:3000 |
| Kafka UI | http://localhost:8087 |
| PostgreSQL | `localhost:5432` |
| Kafka (listener de host) | `localhost:29092` |
| Versity S3 Gateway | API S3 en http://localhost:7070 (sin UI: las peticiones van firmadas) |
| Mailpit | SMTP `localhost:1025`, UI/API http://localhost:8025 |

### Documentación de la API

Una por servicio, generada desde el código con springdoc-openapi (puerto del host de cada fila de la tabla anterior):

```
Swagger UI:     http://localhost:8081/swagger-ui.html   # auth-service
                http://localhost:8082/swagger-ui.html   # user-service
                http://localhost:8083/swagger-ui.html   # recipe-service
                http://localhost:8084/swagger-ui.html   # media-service
                http://localhost:8085/swagger-ui.html   # notification-service
                http://localhost:8080/swagger-ui.html   # api-gateway
Especificación: http://localhost:<puerto-del-servicio>/v3/api-docs
```

Se puede desactivar con `APP_DOCS_ENABLED=false`, sin tocar código ni reconstruir la imagen.

### Verificación del entorno

```bash
scripts/verify-environment.sh   # schemas de PostgreSQL, topics, bucket y SMTP (solo lectura)
scripts/verify-shutdown.sh      # apagado ordenado con una petición en curso (reinicia el servicio)
```

---

## Estructura del repositorio

```
./workspace/domincipe/
├── README.md              # este documento
├── PROJECT.md             # fuente de verdad técnica y metodológica
├── AGENTS.md              # reglas para agentes de IA
├── LICENSE                # MIT
├── .gitignore             # artefactos de build, dependencias y secretos locales
├── .gitattributes         # fin de línea: blob en LF, *.cmd en CRLF
├── .dockerignore          # contexto de build de los Dockerfiles
├── .editorconfig          # UTF-8, LF e indentación por tipo de fichero
├── .mvn/                  # Maven Wrapper (versión de Maven fijada)
├── mvnw, mvnw.cmd         # lanzadores del wrapper (POSIX y Windows)
├── openspec/              # SDD: config, specs as-built y changes
├── .agents/skills/        # skills de OpenSpec 2.0 (compartidas)
├── config/                # configuración de lint (Checkstyle) compartida
├── scripts/               # verificaciones: módulos, imágenes, entorno y apagado ordenado
├── apps/
│   ├── web-frontend/      # React 19 + TypeScript + Vite
│   ├── api-gateway/       # BFF del frontend
│   └── services/          # auth, user, recipe, media, notification
├── libs/                  # common-dto, common-observability y common-test-support
├── ops/                   # operación del proyecto (local y CI)
│   ├── docker/            # Dockerfiles y nginx.conf
│   ├── compose/           # docker-compose.{base,dev,obs}.yml + obs/prometheus.yml
│   └── jenkins/           # pendiente: Jenkinsfile y shared library (change de CI)
├── pom.xml                # parent Maven multi-módulo
└── .env.example           # plantilla de configuración (el .env real nunca se versiona)
```

La estructura completa y el detalle de cada capa viven en [PROJECT.md §6](./PROJECT.md).

---

## Metodología: SDD + OpenSpec

Cada cambio sigue este ciclo, sin excepciones:

1. **Proponer** — se crea el change en `openspec/changes/<id>/` con `proposal.md`, `specs/`, `design.md` y `tasks.md`.
2. **Validar** — el usuario revisa y aprueba el change.
3. **Implementar** — en una rama `feat/<change-id>-<slug>`.
4. **Probar** — la suite completa (unit + slice + integration + contract + e2e + lint) debe pasar en verde, incluida la regresión.
5. **Archivar** — `openspec archive` consolida la spec as-built en `openspec/specs/`.

Comandos habituales:

```bash
openspec list                 # changes en curso
openspec list --specs         # capacidades ya consolidadas
openspec show <change>        # detalle de un change o spec
openspec validate --strict    # validación estricta de los artefactos
openspec status --change <id> # progreso de los artefactos y tareas
```

En Cline las skills se invocan escribiendo `/` en el chat (`/openspec-propose`, `/openspec-apply`, `/openspec-archive`, `/openspec-explore`); desde OpenSpec 2.0 viven en `.agents/skills/` y ya no se generan los slash commands `/opsx-*`.

---

## Convenciones

- **Código en inglés**, **documentación en español**; comentarios que expliquen el *por qué*.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
- **Ramas**: `main` (estable), `feat/<change-id>-<slug>`, `fix/<slug>`.
- **Configuración 100 % por variables de entorno**; `.env.example` versionado, `.env` ignorado.
- **Package base**: `com.domincipe.<servicio>`.

---

## Licencia

[MIT](./LICENSE) © 2026 David Domínguez Vázquez.
