# Design

## Context

El estado de partida y la motivación están en [proposal.md](./proposal.md); los requisitos, en [`specs/ci-pipeline/spec.md`](./specs/ci-pipeline/spec.md). Lo que condiciona el diseño:

- **Restricciones del proyecto**: [PROJECT.md](../../../PROJECT.md) §7 fija ramas y ciclo de release (un change = un PR con *squash*; los *status checks* bloqueantes «llegan con Jenkins»), §8 exige hoy la suite completa en cada PR sin `-DskipTests` y con gate JaCoCo (este change la parte en «suite de PR», sin Docker, y «batería de release», con integration y e2e: D13), y §9 exige imágenes inmutables con SBOM y escaneo que rompa el build con CVEs HIGH/CRITICAL. §7 también fija el idioma: **comentarios de código y configuración en inglés, documentación en español**.
- **Lo que ya existe**: `scripts/build-images.sh` construye las siete imágenes con `docker build` del host y las etiqueta con SHA corto y `latest`; `ops/docker/` tiene los dos Dockerfiles multi-stage; el backend es un reactor Maven de nueve módulos y el frontend una SPA de Vite. Todo eso se consume, no se reescribe.
- **Regla 0.2 de [AGENTS.md](../../../AGENTS.md)**: ninguna versión se escribe de memoria. Las de este diseño se verificaron el 2026-11-17 y se registran abajo con su fuente y su digest.
- **Entorno de ejecución verificado en la máquina de desarrollo** (condiciona la decisión D1): kernel `7.0.0-38-generic` (≥ 5.11, así que hay `overlayfs` sin fuse), `user.max_user_namespaces = 56066`, `kernel.apparmor_restrict_unprivileged_userns = 0`, `/etc/subuid` con `domin:100000:65536`, `/dev/fuse` presente y **AppArmor activo**. Docker Engine 29.10.0 con `overlayfs`.

Versiones e imágenes fijadas en este change, verificadas contra Docker Hub y GitHub el 2026-11-17:

| Componente | Versión | Tag / digest | Fuente |
|---|---|---|---|
| Jenkins LTS | 2.580.2 | `jenkins/jenkins:2.580.2-lts-jdk21`, índice `sha256:74401de6a6f92e1afe1b02d1c8e3d0c33f263bfb5275dd8813f9150355f2367b` | GitHub `jenkinsci/jenkins` tag `jenkins-2.580.2` (2026-10-28) + Docker Hub, push 2026-10-28 |
| BuildKit rootless | 0.35.0 | `moby/buildkit:v0.35.0-rootless`, índice `sha256:5987568f92dafbfb679879de59c1cd8d26597f5f6635c314e166164e2615870c` | GitHub Releases `moby/buildkit v0.35.0` (2026-11-11) + Docker Hub, push 2026-11-11 |
| Syft | 1.57.2 | `anchore/syft:v1.57.2`, índice `sha256:e97e20b6e6d1699c60296b66ab337941724f9bd06ac279d893eda89601fc4b2a` | GitHub Releases `anchore/syft v1.57.2` (2026-11-16) + Docker Hub, push 2026-11-16 |
| Trivy | 0.76.2 | `aquasec/trivy:0.76.2`, índice `sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb` | GitHub Releases `aquasecurity/trivy v0.76.2` (2026-11-05) + Docker Hub, push 2026-11-05 |

Comprobación del **2026-11-17 10:05 UTC**: `docker manifest inspect` resuelve los cuatro tags y el digest del índice, obtenido con `docker buildx imagetools inspect --format '{{.Manifest.Digest}}'` y contrastado con la API de Docker Hub, coincide con la tabla. En GitHub, `gh release view` confirma que las cuatro releases existen, publicadas en las fechas anotadas y ninguna en estado borrador ni *prerelease*.

## Goals / Non-Goals

**Goals:**

- Un `docker compose -f ops/jenkins/docker-compose.yml up --wait` que deje el CI operativo sin tocar la interfaz de Jenkins, y que reproducido tras borrar volúmenes dé el mismo resultado.
- Un build de PR que sea el gate real de la Definition of Done: si algo de la suite falla, no hay merge.
- Construir, inventariar y escanear las siete imágenes **sin** `docker-in-docker` y **sin** montar el socket de Docker en el contenedor que ejecuta el pipeline.
- Que el fallo sea diagnosticable: informes archivados incluso cuando el build va mal.

**Non-Goals:**

- **Ejecutar integration y e2e en CI**: los niveles que §8 resuelve con Testcontainers (PostgreSQL y Kafka) más Playwright en e2e necesitan un daemon Docker, que es precisamente lo que D1 evita. Quedan en la batería de release y su entrada en CI es el change `ci-integration` (D13); una guarda impide que el hueco se descubra como verde falso.
- **Ejecutar la batería de entorno en CI** (`docker compose up --wait`, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh`, Playwright). Consume el daemon Docker del host; merece su propio change con su propio análisis.
- **Publicar imágenes en un registry**: v1 no tiene ninguno, así que el pipeline exporta y escanea artefactos OCI en lugar de empujarlos.
- **Etiquetar y promover releases** (`vX.Y.Z` sobre `main`): la decisión de *cuándo* se libera sigue siendo humana, y la automatización del tag no aporta al gate de PR.
- **Agentes efímeros o agentes Kubernetes**: se asume un nodo único (D8).
- **Firma, procedencia y atestaciones** (`cosign`, SLSA, la atestación SBOM nativa de BuildKit): Syft cubre el requisito de inventario de §9.

## Decisions

### D1. BuildKit rootless 0.35.0 como builder; Kaniko se descarta

Se construye con `moby/buildkit:v0.35.0-rootless` arrancado con los tres `--security-opt` que exige su documentación para contenedor:

```bash
docker run --name buildkitd -d \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  moby/buildkit:v0.35.0-rootless
```

*Por qué:* Kaniko quedó **archivado el 2025-06-03** («no longer developed or maintained», README del repositorio), y un pipeline cuyo contrato es romper el build con CVEs HIGH/CRITICAL no puede apoyarse en un builder sin parches de seguridad. BuildKit es la implementación de referencia del build que usan Docker y buildx, soporta nuestros Dockerfiles sin cambios y exporta OCI con nombre de referencia, que es lo que permite la cadena *daemonless* de D3/D4.

*Qué se gana y qué se paga (verificado en el `Dockerfile` y `docs/rootless.md` de la v0.35.0):* la imagen rootless define `USER 1000:1000`, `ENTRYPOINT ["rootlesskit","buildkitd"]` y un mapeo `subuid/subgid` `100000:65536`, así que **el builder no corre como root** y un escape no devuelve UID 0. A cambio: los tres `--security-opt` no son opcionales (AppArmor está activo en el host y `systempaths` hace falta aunque no lo esté, ver más abajo), el *snapshotter* `overlayfs` exige kernel ≥ 5.11 (cumplido) y la red del worker va siempre en modo `host`, de modo que los `RUN` no quedan aislados por red entre builds. Todo eso queda escrito en `PROJECT.md` §4 y no se maquilla.

*Comprobado en el host de desarrollo el 2026-11-17 (tarea 1.4):* el fallo **se reproduce**. Un `buildkitd` arrancado solo con `seccomp=unconfined` y `apparmor=unconfined`, con volumen de estado limpio, falla en el primer `RUN` del `java-service.Dockerfile`:

```text
#8 [runtime 2/4] RUN addgroup -S -g 10001 domincipe && adduser -S -H -u 10001 -G domincipe -s /sbin/nologin domincipe
#8 0.025 runc run failed: unable to start container process: error during container init: error mounting "proc" to rootfs at "/proc": mount src=proc, dst=/proc, dstFd=/proc/thread-self/fd/16, flags=MS_NOSUID|MS_NODEV|MS_NOEXEC: operation not permitted
```

El mismo build —mismo commit, mismo volumen limpio, sin caché— contra un `buildkitd` con los **tres** flags termina en verde y ejecuta los cuatro `RUN` (`#8 DONE 0.1s`, `#14 DONE 28.2s`). El flag, por tanto, no es cosmético, y el texto de `docs/rootless.md` (`mount proc:/proc (via /proc/self/fd/6), flags: 0xe: operation not permitted`) describe la misma causa con el formato de un `runc` anterior.

*Trampa de verificación:* el motor de este host (Docker `29.10.0`) **no** refleja `systempaths=unconfined` en `.HostConfig.SecurityOpt` de `docker inspect`; un contenedor arrancado con los tres flags muestra solo `seccomp` y `apparmor`. La comprobación válida es un `RUN` completo, no el `inspect`.

*Alternativas consideradas:* (a) **Kaniko 1.24.0**, que no necesita privilegios de contenedor pero está sin mantenimiento; (b) **BuildKit sin rootless con `--privileged`**, más simple y rápido pero con root equivalente del host dentro del builder; (c) **`buildx` con el socket de Docker del host**, que rompe el «sin Docker-in-Docker» de §4 y da al pipeline control total del daemon. Se descartan por ese orden de motivos.

### D2. Dos contenedores y un socket Unix, no TCP

`ops/jenkins/docker-compose.yml` declara dos servicios en una red propia (`ci-net`): `buildkitd` y `jenkins`. El Jenkinsfile no habla con un daemon Docker: habla con `buildkitd` por su socket, compartido con un **volumen nombrado montado en `/run/user/1000`** en ambos contenedores. La imagen rootless ya crea ese directorio con `XDG_RUNTIME_DIR=/run/user/1000` y `BUILDKIT_HOST=unix:///run/user/1000/buildkit/buildkitd.sock`; Docker inicializa el volumen copiando la propiedad del directorio de la imagen, que en `v0.35.0-rootless` es **`1000:0`** (modo 755) —no `1000:1000`—. `buildkitd` crea debajo `/run/user/1000/buildkit` (`1000:1000`, modo 1700) y el socket (`1000:1000`, modo 660). El usuario `jenkins` de la imagen oficial es UID 1000, así que es **propietario** del directorio y del socket aunque el GID del directorio no coincida.

La implementación **verifica el acceso real** antes de cablear el pipeline, no la propiedad literal: `stat -c '%u:%g' /run/user/1000` dentro de `jenkins` da `1000:0`, el del socket da `1000:1000`, y `buildctl debug workers` ejecutado como UID 1000 lista el worker. El *copy-up* del volumen solo hereda la propiedad cuando la ruta existe en la imagen; si la ruta se crea dentro del contenedor, nace `root:root` y el cliente no puede abrir el socket. Comprobado en el spike de la tarea 1.3: un contenedor con el usuario por defecto de la imagen (`uid=1000 gid=1000`) consultó `debug workers` contra el volumen compartido y obtuvo el worker `6cr31sprn7qbniqtjsimsrrr7`.

*Por qué no TCP:* expondría `buildkitd` en la red sin autenticación; el socket Unix no abre puerto y la autorización es la del sistema de ficheros. Si en la implementación el volumen no conserva la propiedad esperada, el plan B está documentado: `rootlesskit buildkitd --addr tcp://0.0.0.0:1234` + `buildctl --addr tcp://buildkitd:1234` en la red interna.

*Por qué no un solo contenedor:* mezclar builder y controlador impide razonar sobre qué proceso tiene qué privilegio, y un reinicio del controlador tiraría la caché de build.

### D3. Salida OCI con nombre de referencia y caché local

Cada imagen se construye con **una sola** invocación de `buildctl` que deja las dos referencias en el mismo archivo OCI:

```bash
# Java: api-gateway usa MODULE=apps/api-gateway; el resto, apps/services/<imagen>.
buildctl --addr unix:///run/user/1000/buildkit/buildkitd.sock build \
  --frontend dockerfile.v0 \
  --local context=. --local dockerfile=ops/docker \
  --opt filename=java-service.Dockerfile \
  --opt build-arg:MODULE=apps/services/auth-service \
  --opt build-arg:GIT_SHA=<sha> \
  --import-cache type=local,src=/cache \
  --export-cache type=local,dest=/cache,mode=max \
  --output 'type=oci,dest=/out/auth-service.tar,"name=domincipe/auth-service:<sha>,domincipe/auth-service:latest"'

# web-frontend: mismo esqueleto, con filename=web-frontend.Dockerfile y además
# --opt build-arg:VITE_API_BASE_URL=<url>, que su Dockerfile exige: sin él el
# build falla (web-frontend.Dockerfile, design D13 de project-skeleton).
```

Las dos referencias viajan **dentro** del archivo OCI (`org.opencontainers.image.ref.name`), así que hay referencia inmutable sin daemon y sin registry. Van en **un único `name=` separado por comas**, no en dos `--output`: el exporter OCI de BuildKit normaliza ese atributo con `strings.Split(name, ",")` y escribe un descriptor por nombre (`exporter/oci/export.go`, `normalizedNames`), mientras que dos salidas distintas producirían dos archivos que podrían divergir.

*La lista de nombres hay que entrecomillarla como campo CSV.* `buildctl` no parte `--output` por comas a lo bruto: lo parsea con `go-csvvalue` (`cmd/buildctl/build/output.go`, `parseOutputCSV`), así que la coma que separa los dos nombres tiene que viajar dentro de un campo entrecomillado. Las tres formas se probaron contra el builder el 2026-11-17:

| Forma | Resultado |
|---|---|
| `--output 'type=oci,dest=…,name=a:sha,a:latest'` | `error: invalid value a:latest` (el segundo nombre se lee como atributo sin `=`) |
| `--output 'type=oci,dest=…,name="a:sha,a:latest"'` | `error: parse error on line 1, column 32: bare " in non-quoted-field` (la comilla debe abrir el campo, no el valor) |
| `--output 'type=oci,dest=…,"name=a:sha,a:latest"'` | correcto: `index.json` con `ref.name` `sha` y `latest` apuntando al mismo digest |

Repetir la clave (`name=a:sha,name=a:latest`) tampoco sirve: `parseOutputCSV` la guarda en un mapa y la última gana, así que el archivo sale con **una sola** referencia —comprobado en el spike—. El entrecomillado del campo es, por tanto, parte del contrato del pipeline y no un detalle de estilo.

*La caché y `/out` son del cliente:* `--import-cache`/`--export-cache type=local` los lee y los escribe **`buildctl`**, no `buildkitd`, y lo mismo ocurre con `dest=/out`. Por eso `/cache` y `/out` se montan en el contenedor de Jenkins, y `buildkitd` solo conserva su estado en `/home/user/.local/share/buildkit`. La etapa vacía `/out` antes de construir —tarballs y layouts extraídos—: los artefactos son por build y, sin eso, el volumen crece sin límite.

*Alternativa considerada:* `type=docker` (tarball cargable con `docker load`). Se descarta porque exige un daemon para verificar las etiquetas y no aporta nada al escaneo.

### D4. SBOM y escaneo sin daemon sobre el artefacto OCI

Sobre el artefacto de D3, sin daemon. Syft lee el `.tar` directamente; Trivy 0.76.2 **no**: su `--input` acepta un tar de `docker save` (con `manifest.json`) o un **layout OCI en directorio**, no un archivo OCI. El spike de la tarea 1.3 lo comprobó con el artefacto real y el error exacto es:

```text
FATAL Fatal error run error: image scan error: scan error: unable to initialize a scan service: unable to initialize artifact: unable to initialize archive image: 2 errors occurred:
  * unable to open /out/api-gateway.tar as a Docker image: file manifest.json not found in tar
  * unable to open /out/api-gateway.tar as an OCI Image: stat /out/api-gateway.tar/index.json: not a directory
```

Por eso el pipeline extrae el archivo una vez y escanea el layout, sin un segundo export ni un daemon:

```bash
syft --from oci-archive /out/auth-service.tar \
  -o cyclonedx-json=/out/sbom/auth-service.cdx.json
mkdir -p /out/auth-service && tar -xf /out/auth-service.tar -C /out/auth-service
trivy image --input /out/auth-service \
  --ignorefile /workspace/ops/jenkins/.trivyignore \
  --severity HIGH,CRITICAL --exit-code 1 --format json --output /out/trivy/auth-service.json
```

*Sobre el fichero de excepciones:* el flag es `--ignorefile` (`IgnoreFileFlag`, nombre `ignorefile`, default `result.DefaultIgnoreFile`, es decir el `.trivyignore` del directorio de trabajo). Se pasa **siempre** con ruta absoluta al fichero versionado, tanto porque el directorio de trabajo del build no es el del repositorio como porque Trivy valida la ruta: si el fichero no existe, falla con `ignore file not found` en lugar de ignorar excepciones en silencio.

*Resultado del spike (2026-11-17, `api-gateway` con `GIT_SHA=e6b4e32`, 103 MB de tar):* `syft --from oci-archive` genera CycloneDX con 1370 componentes; `trivy image --input <layout extraído>` sale con código 0 y detecta 1 MEDIUM (`CVE-2026-4738`, zlib de la base Alpine 3.24.4) y 0 HIGH/CRITICAL, así que el árbol actual pasaría el gate. Se descarta el plan B que se había anotado (exportar además un `type=docker` para escanear): la extracción no añade un segundo artefacto que pueda divergir y deja el `.tar` OCI como única fuente de verdad. El directorio extraído se borra junto al `.tar` en la limpieza de `/out` de cada build, para no duplicar el crecimiento del volumen.

*Por qué:* es la única forma de cumplir §9 (SBOM + escaneo) manteniendo la promesa de R3 de no tocar el daemon. Escanear el archivo es además equivalente a escanear la imagen publicada, porque es exactamente el artefacto que se etiquetaría.

### D5. Imagen propia de Jenkins con la toolchain dentro

`ops/jenkins/Dockerfile` parte de `jenkins/jenkins:2.580.2-lts-jdk21` y añade, con versión explícita y verificable: Maven 3.9.16 (la versión que fija el wrapper), Node.js 22.23.5 (el mínimo del frontend), `buildctl` 0.35.0 (binario estático descargado de la release oficial) y los binarios de Syft 1.57.2 y Trivy 0.76.2. **Temurin 21.0.13 no se instala**: la etiqueta `-jdk21` ya lo trae como `JAVA_HOME` (`/opt/java/openjdk`, comprobado con `java -version` en la imagen base), así que el Dockerfile lo declara en un `ARG` y lo **afirma** durante el build; un segundo JDK solo añadiría peso y una segunda fuente de verdad sobre cuál usa el build. El mismo criterio se aplica a las otras cinco versiones: cada una se afirma al instalarse, de modo que una etiqueta base que derive rompe la construcción en vez de producir una imagen silenciosamente distinta (tarea 2.1).

*Por qué:* el pipeline tiene que hacer exactamente lo mismo que hace el mantenedor en local; cualquier diferencia de versión entre «mi máquina» y «el CI» convierte el verde en una opinión. Se descarta ejecutar cada herramienta en su propio contenedor (`maven:…`, `node:…`) porque eso exige un runtime de contenedores dentro del pipeline, es decir, lo que D1 evita.

*Trade-off asumido:* la imagen pesa más y hay que reconstruirla para subir una versión. A cambio, un único `docker compose up` deja el CI con toda la toolchain.

### D6. Plugins fijados y configuración como código

Los *plugins* se declaran en `ops/jenkins/plugins.txt` con versión exacta y se instalan con `jenkins-plugin-cli --plugin-file`; el controlador se configura con JCasC (`CASC_JENKINS_CONFIG=/var/jenkins_home/casc` apuntando a `ops/jenkins/casc/`).

*Por qué:* instalar plugins «a mano» en la interfaz hace que el CI no sea reproducible y que R1 (mismo resultado tras borrar volúmenes) sea falso. El `plugins.txt` es además el único sitio donde se sube una versión de plugin.

*Credenciales:* JCasC solo declara la **referencia** a la credencial (`github-token`), nunca el valor; el secreto entra por variable de entorno del stack de CI, fuera de git.

### D7. Multibranch contra GitHub y estado en el commit

Job multibranch con *GitHub Branch Source*, que descubre ramas y PRs y reporta el estado del build al commit. La credencial de D6 se consume siempre con `withCredentials`, que enmascara el valor en el log.

*Por qué multibranch:* R6 exige que un PR nuevo o actualizado acabe construido sin intervención; un job de tipo *pipeline* con la rama codificada no lo cumple.

*Disparador: escaneo periódico, no webhook.* La instancia vive en `localhost` y GitHub no puede entregar webhooks a una dirección no pública, así que el *branch source* escanea cada **5 minutos**: un push se construye en el siguiente escaneo (≤ 5 min) y el escenario de R6 se lee con ese margen. El **estado sí llega al commit**, porque el envío es saliente: Jenkins llama a la API de GitHub con el PAT, de modo que la protección de rama puede exigir el check aunque el controlador no sea accesible desde fuera. Un túnel o un webhook quedan fuera de alcance.

*Credencial:* PAT *fine-grained* con `Contents: read`, `Pull requests: read`, `Commit statuses: read and write` y `Metadata: read` (obligatorio), con caducidad de 90 días anotada en el `README.md`. Un PAT que solo tenga `repo:status` y lectura no descubre PRs, así que ese alcance mínimo que decía la primera versión de este diseño era insuficiente. Si el *branch source* no acepta *fine-grained* en la versión de plugin fijada, el plan B es un PAT clásico con `repo`, que es lo mínimo para un repositorio privado. Migrar a GitHub App es una mejora que no cambia ninguna spec y queda como pregunta abierta.

### D8. Un nodo único: el controlador ejecuta los builds

Se configura un ejecutor en el controlador y las etapas corren en él, con `labels` explícitas para no depender del nombre del nodo.

*Por qué:* con un mantenedor y un entorno local, añadir agentes efímeros multiplica la infraestructura sin cambiar el comportamiento observable. La práctica habitual en producción es no ejecutar builds en el controlador; aquí se anota como deuda consciente, y el Jenkinsfile usa `agent { label … }` para que pasar a agentes sea cambiar la etiqueta, no reescribir el pipeline.

*Alternativa considerada:* agente *inbound* separado. Se pospone hasta que haya más de un consumidor del CI.

### D9. Política del gate de vulnerabilidades

`trivy image --input … --severity HIGH,CRITICAL --exit-code 1`. **Sin** `--ignore-unfixed`: §9 dice que el build rompe con HIGH/CRITICAL, y filtrar las no corregidas convertiría el gate en una opinión. La única vía de excepción es `ops/jenkins/.trivyignore`, versionada, pasada **siempre** con `--ignorefile` (D4), con el identificador, la justificación y una **fecha de caducidad** al lado, y revisable en el PR. El fichero nace vacío: una excepción solo entra cuando un falso positivo real la justifica, no como parte de la definición del gate.

*Por qué una excepción por fichero y no por parámetro:* un parámetro (`-PskipScan`) se usa una vez y se queda; un fichero versionado deja rastro en el historial y obliga a justificarlo.

*Sobre el orden de etapas:* escanear cuesta minutos, así que las etapas de calidad (backend, frontend) van antes y las de imagen después: un test rojo no debe esperar a Trivy para fallar. Dentro de las de imagen, primero las siete construcciones, después SBOM y escaneo de cada una.

### D10. Artefactos y retención

Con `post { always { archiveArtifacts … junit … } }` se archivan: informes JaCoCo por módulo, resultados de tests (`junit`), los siete SBOM CycloneDX, los informes JSON de Trivy y el resumen de referencias. La retención se declara en el propio `Jenkinsfile` con `options { buildDiscarder(logRotator(numToKeepStr: …, daysToKeepStr: …)) }`, y la estrategia de *items* huérfanos en la configuración del job multibranch.

*Por qué `always`:* el valor de un informe está en el build que falló; archivarlos solo en el camino feliz es archivar lo que nadie necesita.

### D11. El stack de CI no contamina el entorno de desarrollo

`ops/jenkins/docker-compose.yml` es un fichero propio, con sus redes (`ci-net`) y volúmenes (`jenkins-home`, `buildkit-run`, `buildkit-state`, `buildkit-cache`, `oci-out`), y se invoca siempre con `-f` explícito. **No** se añade a `COMPOSE_FILE` de `.env`, que sigue apuntando a los tres ficheros de §9.

*Por qué:* `local-environment` R1 exige que `docker compose up --wait` desde la raíz levante los servicios de la aplicación; meter Jenkins ahí cambiaría el significado de ese comando y obligaría a cargar el CI en cada arranque de desarrollo.

*Configuración con defaults en el propio fichero.* Compose resuelve el `.env` en el **project directory**, que con `-f ops/jenkins/docker-compose.yml` es `ops/jenkins/` y no la raíz; por eso el `.env` raíz **no** se lee aquí y el stack no puede depender de él. Las variables se declaran con default en el compose (`${JENKINS_IMAGE:-jenkins/jenkins:2.580.2-lts-jdk21@sha256:74401de6…}`, `${BUILDKIT_IMAGE:-moby/buildkit:v0.35.0-rootless@sha256:5987568f…}`, `${JENKINS_PORT:-8090}`), de modo que un clon limpio arranca sin configurar nada. Para cambiarlas se usa `ops/jenkins/.env` (ignorado por la regla `.env` de `.gitignore`) o variables de entorno. El puerto **8090** está libre en el entorno local: §9 ya publica 5432, 8080-8087, 9090, 3000, 7070, 8025, 1025 y 29092. `.env.example` documenta las variables con una nota de que el stack de CI no lee ese fichero.

*Sobre las dos vías de construcción:* `scripts/build-images.sh` sigue siendo el camino local (`docker build` contra el daemon, con su verificación de que SHA y `latest` coinciden) y el Jenkinsfile usa `buildctl`. Comparten Dockerfiles, `build-arg`s y esquema de etiquetas; una tarea del change verifica que ambos caminos producen la misma referencia para el mismo commit. Unificar los dos caminos queda fuera de alcance: el script es el que usa el mantenedor y funciona sin CI.

### D12. La documentación es parte del entregable

Al implementar se actualizan [PROJECT.md](../../../PROJECT.md) §4 (Jenkins 2.580.2, BuildKit rootless 0.35.0, Syft 1.57.2, Trivy 0.76.2, y la fila «Imágenes» deja de decir Kaniko), §6 (`ops/jenkins/` con su contenido real), §9 (builder y alcance real del pipeline), §7 (los *status checks* dejan de estar pendientes), §8 (la suite se parte en «suite de PR», bloqueante y sin Docker, y «batería de release», con integration y e2e) y `README.md` (cómo se levanta el CI, qué se exige para mergear, el intervalo de escaneo y la caducidad del PAT).

*Por qué:* §9 promete hoy «SBOM (Syft) y escaneo Trivy en Jenkins» y §4 promete Kaniko; si el change cierra con eso sin tocar, la fuente de verdad del proyecto pasa a mentir. La documentación no puede ser una tarea opcional del final.

### D13. El nivel integration no entra en el CI v1, y hay una guarda que lo recuerda

`./mvnw verify` no ejecuta hoy ningún test de integración: no existe ningún `*IT.java` en `apps/` ni en `libs/`. Pero el `maven-failsafe-plugin` **ya está activo en los nueve módulos** y el starter parent lo ata a las fases `integration-test` y `verify` (`pom.xml:159-162` y `315-318`), así que el primer test de Testcontainers que se escriba se ejecutará dentro del gate del PR y fallará con `Could not find a valid Docker environment`, porque D1/R3 dejan el contenedor del pipeline sin socket ni daemon.

**Decisión:** integration y e2e quedan **fuera** del CI v1. Se ejecutan en la **batería de release** de [PROJECT.md](../../../PROJECT.md) §7, que ya corre sobre el host con Docker disponible, y su entrada en CI es un change propio, `ci-integration`, que decidirá entre un socket dedicado a tests, un daemon propio por TCP en una red interna o la excepción consciente. En ningún caso se reutiliza el socket del daemon de desarrollo.

**Cómo se evita que se olvide:**
1. La spec lo declara en el requisito de la suite (alcance: lo que no necesita Docker) y en su `Purpose`.
2. [PROJECT.md](../../../PROJECT.md) §8 se parte en «Suite de PR (bloqueante, sin Docker)» y «Batería de release (con Docker: integration y e2e)», con la DoD ajustada a esa división (tarea 7.6).
3. `scripts/ci-suite-scope.sh` corre antes de `./mvnw -B -ntp verify` y **falla** nombrando los `*IT.java` encontrados y la acción a tomar (abrir `ci-integration`), en vez de dejar que Testcontainers muera dentro del gate (tarea 5.6).
4. El `README.md` explica qué cubre el check de PR y qué se ejecuta en release.

*Por qué esta opción y no montar el socket:* montar `/var/run/docker.sock` o un `docker-in-docker` privilegiado contradice R3, que es el corazón del change, y todavía no hay ningún test que justifique ese precio. La guarda convierte un hueco silencioso en un rojo accionable: el día que alguien añada un `*IT`, el build lo dice y la decisión se toma en un change con su propio análisis.

*Coste asumido:* el check de PR no cubre todo §8. Es un trade-off escrito, no una omisión.

## Risks / Trade-offs

- **[El volumen del socket no conserva la propiedad UID 1000]** → verificación temprana con `stat -c '%u:%g'` sobre el directorio y el socket (D2) y plan B documentado: `--addr tcp://0.0.0.0:1234` en la red `ci-net`.
- **[Los tres `--security-opt` hacen que el builder «parezca» privilegiado]** → la ganancia real es no ejecutar como root; se documenta en PROJECT.md §4/§9 con la misma honestidad que en D1, y se añade una prueba negativa: sin `systempaths=unconfined` el build falla al montar `/proc`.
- **[Otra máquina no cumple los requisitos de user namespaces]** → `scripts/ci-preflight.sh`, ejecutado **en el host** antes de `up` (desde un contenedor los sysctls del host no se leen de forma fiable), comprueba kernel ≥ 5.11, `user.max_user_namespaces`, `apparmor_restrict_unprivileged_userns`, `subuid`/`subgid`, `/dev/fuse`, que el puerto de Jenkins esté libre y `docker compose version`, y falla diciendo qué ajustar en vez de dejar un error opaco de `rootlesskit`.
- **[El builder rootless tarda en aceptar trabajo y `depends_on: service_healthy` lo confunde con un fallo]** → healthcheck con `buildctl debug workers` (o, si `buildctl` no está en la imagen, la presencia del socket) y `start_period` amplio; la tarea 3.1 comprueba antes qué probe es posible, y el primer paso del pipeline ejecuta `buildctl debug workers` para no medir la caché en frío.
- **[Un `*IT.java` nuevo rompe el gate por falta de daemon]** → guarda `scripts/ci-suite-scope.sh` (D13) que falla nombrando los ficheros y la acción; montar el socket se descarta en R3.
- **[Primer build sin caché muy lento]** → caché `type=local` en volumen persistente; la spec no fija tiempo máximo a propósito.
- **[La caché y los artefactos crecen sin límite]** → la etapa vacía `/out` (tarballs y layouts extraídos) antes de construir y el `README.md` documenta `buildctl prune` como mantenimiento; la retención de artefactos de Jenkins (D10) no cubre los volúmenes.
- **[La base de datos de Trivy se descarga en cada build o queda obsoleta si se fija]** → volumen de caché para la DB, sin fijar su versión: el gate debe valorar contra datos frescos.
- **[Un falso positivo de Trivy bloquea PRs legítimos]** → `.trivyignore` versionado con justificación y actualización de la imagen base; nunca un parámetro que salte el escaneo.
- **[El PAT caduca y el pipeline deja de publicar estado]** → alcance mínimo real (`Contents: read`, `Pull requests: read`, `Commit statuses: read and write`, `Metadata: read`), caducidad de 90 días anotada en el README y GitHub App como evolución (pregunta abierta).
- **[El controlador ejecuta los builds]** → deuda consciente (D8): `agent { label … }` deja la puerta abierta a agentes sin tocar el pipeline.
- **[Dos vías de construcción (script local y `buildctl`) divergen]** → tarea que compara la etiqueta de revisión de ambas para el mismo commit y deja explicado por qué el digest no es comparable entre builders.
- **[La suite de PR alarga el ciclo]** → se paralelizan backend y frontend; no se recorta cobertura, que es justo el contrato de §8. Los niveles con Docker quedan fuera (D13).

## Migration Plan

No hay datos, esquema ni estado que migrar: todo lo que añade el change son ficheros nuevos y variables nuevas en `.env.example`. Nada existente cambia de comportamiento, así que no hay ventana de incompatibilidad.

1. Infraestructura (`ops/jenkins/docker-compose.yml`) y preflight de requisitos del host (`scripts/ci-preflight.sh`).
2. Imagen de Jenkins con toolchain y *plugins* fijados.
3. JCasC, multibranch y credencial.
4. Etapas de calidad (con la guarda `scripts/ci-suite-scope.sh`), imágenes, SBOM y escaneo.
5. Publicación de estado y activación de los *status checks* obligatorios en `develop` y `main`.
6. Documentación (PROJECT.md §4/§6/§7/§8/§9, README, `.env.example`).

**Rollback:** `docker compose -f ops/jenkins/docker-compose.yml down -v` elimina contenedores, red y volúmenes; desactivar los *status checks* obligatorios es una llamada a la API de GitHub; el resto se revierte con el *revert* del commit del change. Como nada del pipeline es dependencia de ejecución de la aplicación, un CI caído no impide arrancar el entorno local.

## Open Questions

- ¿Agentes efímeros (o Jenkins en Kubernetes) cuando haya más de un consumidor del CI? No cambia ninguna spec: D8 usa etiquetas.
- ¿GitHub App en lugar de PAT para publicar estado? Mejora de seguridad, no de comportamiento observable.
- ¿Añadir un *registry* local (`registry:2`) para publicar las imágenes en lugar de solo exportarlas? Change propio, porque altera el contrato de R3.
- ¿Meter integration y e2e en CI? Change `ci-integration` (D13): exige decidir entre un socket dedicado a tests, un daemon propio por TCP o la excepción consciente. Hoy esos niveles corren en la batería de release. La batería de entorno (`docker compose up --wait`, `scripts/verify-environment.sh`, `scripts/verify-shutdown.sh`, Playwright) va en el mismo cambio de alcance.

