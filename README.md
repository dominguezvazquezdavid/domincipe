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
| Change `project-skeleton` | ✅ Implementado, mergeado en `main` (PR #1, squash) y archivado — tag **`v0.1.0`** |
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

## Integración continua

El CI es un stack local reproducible en `ops/jenkins/`: un controlador Jenkins con la toolchain fijada (Temurin, Maven, Node.js, `buildctl`, Syft y Trivy) y un `buildkitd` rootless que construye las imágenes sin daemon. El contrato completo —pipeline, SBOM y escaneo— vive en el change `ci-pipeline` (`openspec/changes/ci-pipeline/`).

### Requisitos del host para el builder rootless

El builder (`moby/buildkit:v0.35.0-rootless`) corre sin `root` y sin `privileged`, pero depende de que el host permita *user namespaces* sin privilegios. Comprobado el **2026-11-17** en la máquina de desarrollo:

| Comprobación | Valor verificado | Requisito |
|---|---|---|
| `sysctl user.max_user_namespaces` | `56066` | Valor > `0`. Si es `0`, `buildkitd` falla con `…/proc/sys/user/max_user_namespaces needs to be set to non-zero`; se corrige con `sysctl -w user.max_user_namespaces=<N>` |
| `sysctl kernel.apparmor_restrict_unprivileged_userns` | `0` | `0` cuando el host usa AppArmor (Ubuntu 24.04 y posteriores). Con `1`, `buildkitd` falla con `fork/exec /proc/self/exe: permission denied`; se corrige añadiendo `kernel.apparmor_restrict_unprivileged_userns=0` en `/etc/sysctl.d/` y ejecutando `sudo sysctl -p` |
| `/etc/subuid` | `domin:100000:65536` | Una entrada para el usuario del builder con un subrango de UIDs, que es el mapeo de los *user namespaces* (referencia: <https://rootlesscontaine.rs/getting-started/common/subuid/>) |
| `/dev/fuse` | `crw-rw-rw- 1 root root 10, 229` | Presente y accesible. Solo lo usa el snapshotter `fuse-overlayfs` (kernel < 4.18); con kernel ≥ 5.11 el builder usa `overlayfs` |

El host verificado cumple las cuatro condiciones (kernel `7.0.0-38-generic`, AppArmor activo). Además, el contenedor del builder necesita los tres `--security-opt` que documenta BuildKit v0.35.0 —`seccomp=unconfined`, `apparmor=unconfined` y `systempaths=unconfined`—: sin el último, cada `RUN` no puede montar su propio `/proc` y el build falla con `error mounting "proc" to rootfs at "/proc": … flags=MS_NOSUID|MS_NODEV|MS_NOEXEC: operation not permitted`. Reproducido el **2026-11-17** quitando ese flag: es la misma causa que el `mount proc:/proc (via /proc/self/fd/6), flags: 0xe: operation not permitted` de `docs/rootless.md`, con el formato de un `runc` más nuevo. Al comprobarlo, ojo: Docker 29.10.0 **no** muestra `systempaths=unconfined` en `docker inspect` aunque esté aplicado; la prueba válida es que un `RUN` llegue a ejecutarse.

### Comprobación previa del host

`scripts/ci-preflight.sh` reúne esos requisitos en una comprobación de solo lectura que se ejecuta **en el host**, nunca dentro de un contenedor: desde ahí, los sysctls y `/etc/subuid` que se leen no son los que consumirá `rootlesskit`, así que un verde en esa posición no significaría nada. Falla nombrando el requisito y el ajuste que lo corrige, en lugar de dejar que el problema aparezca como un error opaco del builder:

```bash
scripts/ci-preflight.sh
```

Comprueba, en orden:

- `docker` y el plugin `docker compose` v2.
- El kernel. Con 5.11 o posterior, BuildKit usa `overlayfs`; por debajo **no falla**: avisa de que el snapshotter pasará a `fuse-overlayfs`.
- `user.max_user_namespaces > 0`.
- `kernel.apparmor_restrict_unprivileged_userns = 0`. En un host sin AppArmor la clave no existe y no hay nada que comprobar.
- Una entrada para el usuario actual en `/etc/subuid` y en `/etc/subgid`, por nombre o por UID/GID.
- `/dev/fuse` presente y accesible. Solo es obligatorio si el kernel es anterior a 5.11; por encima, su ausencia queda como aviso.
- El puerto de Jenkins libre. Lo resuelve con la precedencia de Compose —entorno, después `ops/jenkins/.env` y, si no hay ninguno, el `8095` del compose—, y si quien lo ocupa es este mismo stack ya levantado no lo trata como conflicto.

Termina con código 0 cuando el host está listo, 1 cuando falta un requisito y 2 ante un uso incorrecto; debe salir 0 antes de `up`.

### Arranque del stack

```bash
scripts/ci-preflight.sh                                        # en el host; debe salir 0
docker compose -f ops/jenkins/docker-compose.yml up -d --wait
```

- **Jenkins**: <http://localhost:8095/> — el puerto lo fija `JENKINS_PORT`. La interfaz hay que desbloquearla con la contraseña inicial que imprime el log del contenedor y deja en `/var/jenkins_home/secrets/initialAdminPassword`; el bloque 4 del change sustituye ese paso manual por configuración como código con la credencial y el job versionados.
- **Builder**: `buildkitd`, rootless y sin puerto publicado. El pipeline lo alcanza por el socket Unix del volumen `buildkit-run`, que los dos contenedores comparten; no hay daemon Docker ni montaje de `/var/run/docker.sock`.
- **Aislamiento**: proyecto Compose propio (`domincipe-ci`), red propia (`ci-net`) y siete volúmenes nombrados (`jenkins-home`, `buildkit-run`, `buildkit-state`, `buildkit-cache`, `oci-out`, `maven-repo`, `npm-cache`). `ops/jenkins/docker-compose.yml` está **fuera** del `COMPOSE_FILE` de la raíz, así que el CI no arranca con el entorno de desarrollo ni comparte nada con él (design D11).

El stack **no necesita configuración**: cada valor trae su default en el propio compose y un clon limpio arranca sin ningún `.env`. Para cambiarlo se escribe `ops/jenkins/.env` (ignorado por git) o se exporta la variable en el shell. El `.env` de la raíz **no** se lee aquí, porque Compose busca el `.env` en el *project directory*, que con `-f ops/jenkins/docker-compose.yml` es `ops/jenkins/`; `.env.example` documenta las variables de los dos stacks, con esa misma advertencia en su bloque de CI (tarea 3.4).

Para apagarlo:

```bash
docker compose -f ops/jenkins/docker-compose.yml down      # conserva el estado
docker compose -f ops/jenkins/docker-compose.yml down -v   # la próxima vez, arranque en frío
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
│   └── jenkins/           # CI: Dockerfile del controlador, docker-compose.yml y plugins.txt
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

## Ramas y releases

Gitflow-lite: dos ramas permanentes —`main` para releases estables y funcionales, `develop` para integración (rama por defecto)— y ramas cortas que nacen y mueren con cada trabajo.

| Rama | Nace de | Entra en | Se borra |
|---|---|---|---|
| `feat/<change-id>-<slug>` | `develop` | `develop` (PR squash) | al mergear |
| `fix/<slug>` | `develop` | `develop` (PR squash) | al mergear |
| `release/<x.y.z>` | `develop` | `main` (PR squash + tag `vX.Y.Z`) | al mergear |
| `hotfix/<x.y.z>` | `main` | `main` y `develop` (PR squash) | al mergear |

Un release se **congela** —solo arreglos, ninguna feature nueva— y solo pasa a `main` después de la batería completa sobre un entorno recreado: `./mvnw -B -ntp verify`, `npm ci && npm run lint && npm run build && npm test`, `docker compose up --wait` desde cero, `scripts/verify-environment.sh` y `scripts/verify-shutdown.sh`. De la release sobrevive el **tag anotado** `vX.Y.Z` sobre `main`; no hay rama `release` permanente. La regla completa y su porqué están en [PROJECT.md §7](./PROJECT.md).

---

## Convenciones

- **Código en inglés**, **documentación en español**; comentarios que expliquen el *por qué*.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
- **Ramas (Gitflow-lite)**: `main` (solo releases estables), `develop` (integración, **rama por defecto**), `release/<x.y.z>` (congelado, efímera), `feat/<change-id>-<slug>`, `fix/<slug>` y `hotfix/<x.y.z>`. Detalle en [PROJECT.md §7](./PROJECT.md).
- **Merge**: `squash and merge` como único método (un change = un commit; el título del PR pasa a ser el asunto del commit) y la rama del change se borra al mergear.
- **Configuración 100 % por variables de entorno**; `.env.example` versionado, `.env` ignorado.
- **Package base**: `com.domincipe.<servicio>`.

---

## Licencia

[MIT](./LICENSE) © 2026 David Domínguez Vázquez.
