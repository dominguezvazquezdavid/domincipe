# Proposal

## Why

La **batería de release** de [PROJECT.md](../../../PROJECT.md) §8 —integration con Testcontainers y e2e— se ejecuta hoy solo a mano en el host, por la decisión D13 del change `ci-pipeline`: el gate de PR no tiene daemon Docker y una guarda versionada (`scripts/ci-suite-scope.sh`) hace fallar el build con cualquier `*IT.java` que aparezca en el árbol. La consecuencia ya está a la vista del siguiente change: el primer servicio con persistencia (migraciones Flyway, entidades, `@DataJpaTest`) no puede certificar en el gate justo la capa que más se rompe, y `docker compose up --wait`, `scripts/verify-environment.sh` y `scripts/verify-shutdown.sh` tampoco son ejecutables desde CI. Tampoco lo es el e2e del frontend.

Este change cierra ese hueco con la base hecha de una vez: un daemon Docker propio del stack de CI, aislado del host, sobre el que corren los tres niveles que hoy faltan.

## What Changes

- **Daemon Docker en el stack de CI**: un contenedor `docker:dind` en `ci-net`, nunca el socket del daemon de desarrollo. Excepción consciente y documentada: ese contenedor, y solo él, corre `privileged`; el camino de build sigue siendo BuildKit rootless, sin daemon y sin socket.
- **CLI en el controlador**: la imagen de `ops/jenkins/Dockerfile` incorpora el cliente Docker y el plugin `docker compose` con versión fijada y afirmada en el build, igual que el resto de la toolchain.
- **Etapa `Integration`**: Testcontainers (PostgreSQL 16 y Kafka 4) sobre el daemon de test, ejecutada por `maven-failsafe-plugin`. Se añade la clase base compartida y los primeros `*IT.java`, de nivel **infraestructura**: prueban que el daemon responde y que ambos contenedores levantan y son alcanzables, no comportamiento de dominio.
- **Etapa `E2E`**: e2e de backend con Testcontainers + RestAssured y smoke de frontend con Playwright contra un proyecto Compose aislado (`-p domincipe-e2e`), **sin publicar puertos**. Las aserciones son invariantes que sobreviven al producto real (entorno sano, SPA servida, deep link con fallback, health del gateway por el proxy, `X-Request-Id` en la respuesta, consola sin errores): arnés y contrato, no relleno de pantallas.
- **Etapa `Environment`**: la batería de entorno de §8 (`docker compose up --wait` desde cero, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh`) ejecutable desde el pipeline sobre el daemon de test.
- **Matriz del pipeline**: `Quality ∥ Integration` → `Images` → `E2E ∥ SBOM ∥ Scan`. Los niveles con daemon se solapan con la construcción de imágenes porque no comparten recurso; los tiempos se **miden** en un build real antes de darlos por buenos.
- **Retirada de la guarda** `scripts/ci-suite-scope.sh` y del requisito que la sostenía: su motivo desaparece cuando el gate tiene daemon. El scenario que hoy manda «abrir el change `ci-integration`» se sustituye por el de ejecución real de integration.
- **Gate de cobertura sin cambios de significado**: JaCoCo sigue midiendo unit y slice en los umbrales 80/70 por módulo; los informes de integration y e2e se archivan aparte y no entran en el cómputo.
- **Diagnóstico**: informes de failsafe, trazas de Playwright y logs de los contenedores del entorno e2e se archivan también en builds rojos, con la retención ya declarada (10 builds / 30 días); las trazas solo se conservan del build fallido.
- **Fuera de alcance**: ITs de dominio (llegan con los changes de negocio), publicación de imágenes en un registry, agentes efímeros o Kubernetes, y firma/procedencia de artefactos.

## Capabilities

### New Capabilities

Ninguna: el change modifica el contrato de la integración continua existente, no introduce una capability nueva.

### Modified Capabilities

- `ci-pipeline`: el gate de PR deja de excluir los niveles que necesitan daemon Docker. Cambian el requisito que declaraba `integration` y `e2e` fuera de CI (pasa a exigir su ejecución), el requisito de la guarda de `*IT.java` (se retira) y el alcance del requisito de suite bloqueante (integración y e2e entran con etapa propia). Se añaden requisitos para el daemon de test aislado, para la batería de entorno en CI y para el archivado de sus informes.

## Impact

- `ops/jenkins/docker-compose.yml`, `ops/jenkins/Dockerfile`, `ops/jenkins/Jenkinsfile`, `ops/jenkins/casc/jenkins.yaml` (nodo y etapas) y `ops/jenkins/vars/` (helpers nuevos).
- `scripts/ci-preflight.sh` (requisitos del daemon de test), `scripts/ci-suite-scope.sh` (se retira) y scripts nuevos de la batería e2e/entorno.
- `pom.xml` (Testcontainers, RestAssured, surefire/failsafe y JaCoCo) y `libs/common-test-support` (clase base de integration).
- `apps/web-frontend` (Playwright: dependencia, configuración y spec de humo) y su `package.json`/`package-lock.json`.
- `openspec/specs/ci-pipeline/spec.md` (delta), `PROJECT.md` §4, §7, §8 y §9, y `README.md`.
- Versión: la rama `feat/ci-integration-release-battery` declara **0.3.0-SNAPSHOT** (capacidad nueva, *minor* según §7).
