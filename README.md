# Domincipe

Web de recetas para uso personal, construida como **proyecto educativo**: el objetivo no es el producto, sino practicar arquitectura de microservicios con el rigor de un entorno de producción real (12-factor, healthchecks, observabilidad, imágenes inmutables y CI/CD).

- Sin pagos ni monetización.
- Multi-usuario con roles (`ADMIN`, `USER`) y preferencias (dietas, alérgenos).
- Todo corre en Docker local simulando un entorno cloud.

> Documentación de referencia: [PROJECT.md](./PROJECT.md) (fuente de verdad técnica y metodológica) y [AGENTS.md](./AGENTS.md) (reglas de trabajo con agentes de IA).

---

## Estado actual

El repositorio está en **fase de esqueleto**. Hoy existen únicamente la documentación, la configuración de OpenSpec y los ficheros raíz del proyecto.

| Elemento | Estado |
|---|---|
| Documentación (`README.md`, `PROJECT.md`, `AGENTS.md`) | ✅ Disponible |
| Metodología SDD con OpenSpec (`openspec/`) | ✅ Inicializada (`schema: spec-driven`) |
| Change `project-skeleton` (propuesta) | 📝 En revisión — ver [`openspec/changes/project-skeleton/`](./openspec/changes/project-skeleton/) |
| Parent POM, módulos Java, frontend, compose e infraestructura | ⛔ Pendiente de implementar |
| Swagger UI y contrato OpenAPI por servicio | ⛔ Pendiente — incluido en el change `project-skeleton` |

Ningún artefacto de código se genera sin que su change de OpenSpec esté aprobado y su suite de tests en verde.

---

## Requisitos

| Herramienta | Versión mínima | Uso |
|---|---|---|
| JDK | 21 (LTS) | Backend Spring Boot |
| Maven | 3.9+ (vía wrapper `./mvnw` cuando exista) | Build multi-módulo |
| Node.js | ≥ 22.12.0 | Frontend y CLI de OpenSpec |
| npm | 10+ | Dependencias del frontend y del CLI |
| Docker + Docker Compose v2 | última estable | Entorno local completo |
| `openspec` CLI | 1.17.0 | Flujo SDD (`@fission-ai/openspec`) |

Instalación del CLI de OpenSpec:

```bash
npm install -g @fission-ai/openspec@latest
openspec --version
```

---

## Arranque rápido

> Los comandos marcados como **(tras `project-skeleton`)** funcionarán cuando ese change esté implementado; hoy el repositorio no tiene todavía build ni servicios.

```bash
git clone git@github.com:dominguezvazquezdavid/domincipe.git
cd domincipe
cp .env.example .env        # (tras project-skeleton) configuración local, nunca se versiona
```

Backend y frontend:

```bash
./mvnw -B -ntp verify            # (tras project-skeleton) build + toda la suite backend
cd apps/web-frontend
npm ci && npm run lint && npm test
```

Entorno completo en Docker (servicios, dependencias y observabilidad):

```bash
docker compose up --wait        # (tras project-skeleton) usa COMPOSE_FILE declarado en .env
```

La pila de observabilidad (Prometheus, Grafana y Kafka UI) se levanta **siempre**, porque `.env.example` declara `COMPOSE_FILE` con los tres ficheros de Compose. Para arrancar sin ella —por ejemplo en una máquina con pocos recursos— se pasan los ficheros explícitos sin el de observabilidad:

```bash
docker compose -f ops/compose/docker-compose.base.yml \
               -f ops/compose/docker-compose.dev.yml up --wait   # sin observabilidad
```

Documentación de la API (una por servicio, generada desde el código con springdoc-openapi):

```
Swagger UI:    http://localhost:<puerto-del-servicio>/swagger-ui.html
Especificación: http://localhost:<puerto-del-servicio>/v3/api-docs
```

Se puede desactivar con `APP_DOCS_ENABLED=false`, sin tocar código ni reconstruir la imagen.

---

## Estructura del repositorio

```
./workspace/domincipe/
├── README.md              # este documento
├── PROJECT.md             # fuente de verdad técnica y metodológica
├── AGENTS.md              # reglas para agentes de IA
├── LICENSE                # MIT
├── .gitignore             # artefactos de build, dependencias y secretos locales
├── .editorconfig          # UTF-8, LF e indentación por tipo de fichero
├── .mvn/                  # Maven Wrapper (versión de Maven fijada)
├── openspec/              # SDD: config, specs as-built y changes
├── .cline/                # skills de OpenSpec para Cline
├── .clinerules/           # workflows de OpenSpec para Cline
├── config/                # configuración de lint (Checkstyle) compartida
├── scripts/               # verificaciones del esqueleto (módulos, imágenes, entorno)
├── apps/
│   ├── web-frontend/      # React 19 + TypeScript + Vite
│   ├── api-gateway/       # BFF del frontend
│   └── services/          # auth, user, recipe, media, notification
├── libs/                  # common-dto, common-observability
├── ops/                   # operación del proyecto (local y CI)
│   ├── docker/            # Dockerfiles
│   ├── compose/           # docker-compose.{base,dev,obs}.yml
│   └── jenkins/           # Jenkinsfile y shared library
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

En Cline los workflows se invocan escribiendo `/` en el chat (`/opsx-propose`, `/opsx-apply`, `/opsx-archive`, `/opsx-explore`), servidos por las skills de `.cline/skills/`.

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
