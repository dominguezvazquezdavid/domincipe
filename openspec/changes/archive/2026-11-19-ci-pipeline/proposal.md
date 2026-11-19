# Proposal

## Why

La Definition of Done de [PROJECT.md §8](../../../PROJECT.md) y el ciclo de release de [§7](../../../PROJECT.md) describen una batería (suite completa, gate de cobertura, imágenes, SBOM y escaneo) que hoy solo existe como comandos manuales: sin un pipeline que la ejecute y la bloquee, «en verde» significa lo que cada máquina quiera decir y la protección de ramas de `main`/`develop` no tiene *status checks* que exigir. El esqueleto ya construye, prueba y arranca (`local-environment`, `repo-layout`, `service-runtime`, `web-shell` en `openspec/specs/`), así que el gate de integración continua es lo que falta para que el proyecto deje de depender de la memoria del mantenedor.

## What Changes

- **Stack de CI reproducible en local**: `ops/jenkins/docker-compose.yml` con dos servicios —Jenkins LTS y el daemon de build— que se levantan con un comando y quedan sanos; el arranque no exige configurar nada a mano en la interfaz.
- **Builder sin daemon de build**: las siete imágenes del monorepo se construyen con **BuildKit rootless 0.35.0** (`moby/buildkit:v0.35.0-rootless`) invocado por `buildctl` sobre gRPC, sin socket de Docker montado y sin `docker-in-docker`.
- **Imagen de Jenkins con toolchain fijada**: construida desde `jenkins/jenkins:2.580.2-lts-jdk21` con JDK 21, Maven 3.9.16, Node.js 22, `buildctl`, `syft` y `trivy`, todos con versión explícita.
- **Configuración como código**: *plugins* fijados en `plugins.txt` (instalados por `jenkins-plugin-cli`) y configuración del controlador en JCasC (`ops/jenkins/casc/`), incluidas las credenciales por referencia.
- **Pipeline declarativo y biblioteca compartida**: `ops/jenkins/Jenkinsfile` + `ops/jenkins/vars/` con las etapas de calidad, construcción de imágenes, SBOM y escaneo.
- **Suite de verificación bloqueante, sin Docker**: backend (`./mvnw -B -ntp verify`, con lint, tests y gate JaCoCo) y frontend (`npm ci`, lint, build y tests) en cada PR; nunca `-DskipTests`. Los niveles **integration** y **e2e** de §8 no entran aquí: requieren daemon Docker y quedan en la batería de release (`design.md` D13). Una guarda (`scripts/ci-suite-scope.sh`) hace fallar el build si aparece un `*IT.java`, para que el hueco no se descubra como verde falso.
- **Interacción con el entorno local sin colisiones**: el stack de CI usa sus propios volúmenes y su propio puerto (8095 por defecto, declarado en el compose), y no lee el `.env` de la raíz, porque Compose resuelve ese fichero en el directorio del primer `-f`.
- **Cadena daemonless de SBOM y escaneo**: cada imagen se exporta como archivo OCI (`--output type=oci,"name=…"`), se inventaría con Syft (`syft --from oci-archive`) y se escanea con Trivy sobre el layout OCI extraído (`trivy image --input <directorio> --severity HIGH,CRITICAL --exit-code 1`), que rompe el build.
- **Estado publicado en el PR**: Jenkins publica el resultado como *commit status* y la protección de ramas de `develop`/`main` exige esos checks para mergear.
- **Documentación**: [PROJECT.md](../../../PROJECT.md) §4 (versiones de Jenkins, BuildKit, Syft y Trivy), §6 (`ops/jenkins/`), §7 (los *status checks* dejan de estar pendientes), §8 (la suite se parte en «suite de PR» y «batería de release», para que la fuente de verdad no prometa integration ni e2e en CI) y §9 (builder y alcance real del pipeline), más `README.md` y `.env.example`.
- Sin **BREAKING** changes: no se modifica código de aplicación ni ningún requisito de las specs consolidadas.

## Capabilities

### New Capabilities

- `ci-pipeline`: contrato de la integración continua local — un Jenkins reproducible en frío, la suite de verificación como gate bloqueante, la construcción de imágenes sin daemon de build, el inventario SBOM y el escaneo de vulnerabilidades con umbral, el estado publicado en el PR y las credenciales fuera del repositorio.

### Modified Capabilities

Ninguna: `ci-pipeline` añade comportamiento nuevo sobre un sistema que ya cumple sus specs. No cambia ningún requisito de `local-environment`, `repo-layout`, `service-runtime` ni `web-shell`; el stack de CI vive en su propio fichero de Compose y no altera el arranque local documentado.

## Impact

- **Código nuevo**: `ops/jenkins/` (Dockerfile, `plugins.txt`, `casc/`, `Jenkinsfile`, `vars/`, `docker-compose.yml`, `.trivyignore`) y dos scripts de apoyo, `scripts/ci-preflight.sh` y `scripts/ci-suite-scope.sh`.
- **Ficheros modificados**: `.env.example` (variables del stack de CI, con la nota de que ese `.env` no lo lee el CI), `PROJECT.md` §4/§6/§7/§8/§9, `README.md`; la configuración de protección de ramas del repositorio (vía API de GitHub, no versionada).
- **Dependencias nuevas**: `jenkins/jenkins:2.580.2-lts-jdk21`, `moby/buildkit:v0.35.0-rootless`, `anchore/syft:v1.57.2`, `aquasec/trivy:0.76.2` y los *plugins* de Jenkins fijados en `plugins.txt`; ninguna dependencia nueva de Java ni de Node.
- **Sin impacto** en `apps/`, `libs/`, `pom.xml` ni en los Dockerfiles existentes: el pipeline consume el build y las imágenes que ya existen.
- **Fuera de alcance de este change**: los niveles **integration** (Testcontainers con PostgreSQL y Kafka) y **e2e** (Testcontainers + RestAssured y Playwright), que necesitan daemon Docker y tienen su propio change (`ci-integration`, `design.md` D13); la batería de entorno en CI (`docker compose up --wait`, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh`); publicación de imágenes en un *registry* (v1 no tiene ninguno); etiquetado y promoción de releases; y Kubernetes, Helm o cualquier destino que no sea el entorno local.
