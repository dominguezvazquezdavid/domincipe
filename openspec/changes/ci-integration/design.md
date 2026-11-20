# Design

## Context

Ver `proposal.md` para la motivación. El estado actual que condiciona el diseño:

- El agente `ci` **es el contenedor del controlador** (`ops/jenkins/Jenkinsfile:9`, `agent { label 'ci' }` y el nodo declarado en `ops/jenkins/casc/jenkins.yaml`). Su imagen (`ops/jenkins/Dockerfile`) instala Temurin, Maven, Node, `buildctl`, Syft y Trivy; **no lleva cliente Docker ni plugin `docker compose`**, y ningún contenedor del stack monta `/var/run/docker.sock`.
- El builder es BuildKit rootless por un socket Unix en un volumen compartido (`buildkit-run`), sin daemon de build y sin `privileged:`.
- `maven-failsafe-plugin` está enlazado en los nueve módulos, así que cualquier `*IT.java` entra en `./mvnw verify`; por eso existe `scripts/ci-suite-scope.sh`, que falla nombrando el fichero.
- `.dockerignore` excluye `**/target`, `**/node_modules`, `apps/web-frontend/dist`, `apps/web-frontend/coverage`, `sbom` y `security`: el contexto de build no contiene salidas de compilación, así que una etapa de imágenes puede solaparse con Maven o npm sin capturar ficheros a medio escribir.
- Host de desarrollo: **4 cores**, 15 GB de RAM (≈5 GB disponibles), Docker Engine 29.10.0, kernel `7.0.0-38-generic`.
- `ops/compose/docker-compose.dev.yml` es el único fichero que publica puertos (8080-8086, 5432, 7070, 1025, 8025, 29092); `base` no publica ninguno.

Versiones fijadas por este change, **verificadas el 2026-11-19** (Regla 0.2 de [AGENTS.md](../../../AGENTS.md)):

| Componente | Versión | Tag / digest | Cómo se verificó |
|---|---|---|---|
| Daemon de test | Docker 29.10.0 | `docker:29.10.0-dind@sha256:4bbc7223f81db790097c6dea42fb93e05b8fead4f0431fbe6ccaba6e8473201c` | `docker buildx imagetools inspect --format '{{.Manifest.Digest}}'` |
| Alternativa descartada | Docker 29.10.0 rootless | `docker:29.10.0-dind-rootless@sha256:5a703ad0d72cd5e4fb4beca8024d6eddef6d22a46ed1d9812bf3d24ff43ccbce` | igual, el tag existe (D1) |
| Cliente Docker del controlador | 29.10.0 | `https://download.docker.com/linux/static/stable/x86_64/docker-29.10.0.tgz` | `curl -I` → HTTP 200 |
| Plugin `docker compose` | v5.7.1 | asset `docker-compose-linux-x86_64` de `docker/compose` | API de GitHub, release `v5.7.1` |
| Testcontainers | 2.0.5 | BOM de Spring Boot 4.1.2 (`spring-boot-dependencies-4.1.2.pom:209`, 3597-3599) | POM en `~/.m2` + BOM en Maven Central: `testcontainers`, `testcontainers-junit-jupiter`, `testcontainers-postgresql`, `testcontainers-kafka` |
| RestAssured | 6.3.0 | `io.rest-assured:rest-assured` | `maven-metadata.xml`: última estable; `7.0.0-RC1` se descarta por ser *release candidate* |
| Playwright | 1.65.0 | `@playwright/test@1.65.0` y `mcr.microsoft.com/playwright:v1.65.0-noble@sha256:9beb546099e11f52d62e505537914870e01a67e0e6b00ae41da4775324e73dbe` | registro de npm + `docker buildx imagetools inspect` |

## Goals / Non-Goals

**Goals:**

- Que el gate de PR ejecute los cuatro niveles de [PROJECT.md](../../../PROJECT.md) §8 —calidad, integration, e2e y entorno— sobre un entorno recreado, sin `-DskipTests` ni exclusiones.
- Que el daemon Docker que hace falta para eso sea **propiedad del stack de CI**, no del host de desarrollo, y que su coste de seguridad quede acotado y escrito.
- Que la base sirva para los changes de dominio: el arnés, el daemon y las etapas se montan una vez, y cada change posterior solo añade `*IT.java` y specs de Playwright.
- Que un fallo con daemon sea diagnosticable con la misma calidad que uno sin él.

**Non-Goals:**

- ITs de dominio: la persistencia, los endpoints y los flujos llegan con `identity-access` y siguientes. Este change certifica la tubería, no el producto.
- Publicar imágenes en un registry, firmar artefactos, agentes efímeros o Kubernetes (siguen fuera de v1).
- Sustituir BuildKit: la construcción de imágenes sigue siendo rootless y sin daemon; `docker:dind` solo ejecuta tests y el entorno e2e.
- Un segundo daemon de test por build: un único daemon por stack, con limpieza entre etapas.

## Decisions

### D1. `docker:dind` privilegiado como daemon de test, en `ci-net`

`docker:29.10.0-dind` arranca como tercer contenedor del stack, unido a `ci-net`, con volumen propio para `/var/lib/docker` y **sin publicar puertos**. El controlador lo consume por `DOCKER_HOST=tcp://dind:2375`, sin TLS porque la red es privada del stack y el host no la alcanza.

*Por qué:* es la única opción que permite construir el daemon dentro del repositorio y con un `up --wait`, que es la propiedad que el stack ya promete (un clon limpio, un comando). La documentación oficial de la imagen lo deja explícito: «`--privileged` is required for Docker-in-Docker to function properly» (docker-library/docs, `docker/content.md`). Se acepta y se escribe: **el daemon de test es el único contenedor privilegiado del stack**, y ese privilegio no toca el camino de build, que sigue siendo BuildKit rootless.

*Alternativas descartadas:*

- **`docker:dind-rootless`** (digest arriba): el tag existe y sería coherente con el builder, pero no hay garantía documentada de que arranque sin privilegios en este host, y verificarlo empíricamente antes de escribir el change habría bloqueado el diseño. Queda como deuda declarada: si una verificación posterior demuestra que funciona sin `privileged`, la migración es un cambio de imagen y de `security_opt`, sin tocar el pipeline.
- **Socket dedicado del host**: cumple la letra de §8, pero exige preparar el host fuera del repositorio y rompe la reproducibilidad del stack; además, el socket del `dockerd` del host da acceso a las imágenes del desarrollador.
- **Excepción consciente** (seguir en el host): no entrega nada verificable en CI y deja abierto el hueco que este change existe para cerrar.

### D2. Cliente Docker y Compose dentro de la toolchain del controlador

`ops/jenkins/Dockerfile` gana dos `ARG` (`DOCKER_CLI_VERSION=29.10.0`, `DOCKER_COMPOSE_VERSION=5.7.1`), instala el binario estático del CLI y el plugin de Compose, y **afirma la versión durante el build** con `docker --version` y `docker compose version`, igual que ya hace con Maven, Node, `buildctl`, Syft y Trivy.

*Por qué:* el pipeline no debe depender de un binario que aparezca en el PATH por casualidad, y `ops/jenkins/Dockerfile` es el sitio donde vive la toolchain fijada (§4). El CLI se instala **solo como cliente**: apunta a `DOCKER_HOST`, nunca a un socket local. El plugin va en `/usr/local/lib/docker/cli-plugins/docker-compose`, la ruta que el CLI sondea sin configuración extra.

### D3. Una sola invocación de Maven, con el daemon disponible, y la matriz de etapas

El backend se construye **una vez** por build, con `./mvnw -B -ntp clean verify` y `DOCKER_HOST` apuntando al daemon de test. Failsafe sigue enlazado como hoy, así que esa invocación ejecuta Checkstyle, unit, slice, integration, JaCoCo y la verificación de módulos. **No se usa ningún flag de omisión**, y por eso el requisito «Sin omisión dentro de la suite de PR» se mantiene tal cual.

*Por qué no dos invocaciones (una de unit, otra de IT):* dos Maven sobre el mismo árbol se pisan —el `clean` de uno borra el `target/` del otro—, y separarlos en dos *checkouts* duplicaría compilación y CPU en una máquina de 4 cores. Meter `-DskipITs` en la mitad de calidad habría sido lo barato, pero es exactamente la opción que §8 prohíbe y que el requisito citado verifica en el log.

*Consecuencia asumida:* el backend ya no es «la mitad sin Docker». Si el daemon no arranca, la suite de calidad del backend falla con él. Se acepta porque el daemon se levanta con el stack y su salud se comprueba antes de cualquier etapa, y porque la alternativa era un gate que miente. Para que el diagnóstico no empeore, la etapa comprueba el daemon **antes** de invocar Maven y falla nombrando la causa (requisito «Daemon no disponible»).

*Matriz resultante:*

```text
Quality:  Backend (Maven: unit + slice + integration)  ∥  Frontend (npm)  ∥  Images
                                    ↓
             E2E (entorno + RestAssured + Playwright)  ∥  SBOM  ∥  Scan
```

Se solapan los tres primeros porque no comparten recurso ni ficheros: Maven escribe `target/` y npm `node_modules/`, ambos fuera del contexto de build (`.dockerignore`), y las imágenes se construyen contra `buildkitd`, no contra el daemon de test. `E2E` va después de `Images` porque consume las imágenes construidas; `SBOM` y `Scan` leen los mismos archivos OCI de `/out` y solo escriben en directorios distintos (`sbom/`, `security/`), así que pueden ir en paralelo.

*Desviación explícita respecto a la matriz acordada:* la conversación aprobó `Quality ∥ Integration → Images → E2E ∥ SBOM ∥ Scan`, con `Integration` como etapa propia. Al elegir una sola invocación de Maven, integration **vive dentro de la mitad Backend de Quality**, y `Images` se adelanta al primer grupo porque el contexto de build ya está aislado de las salidas de compilación. El efecto buscado —integration en paralelo con la calidad sin daemon y con la construcción de imágenes— se cumple; cambian los nombres de etapa. Si la medición (tarea 1.3) demuestra contención, `Images` vuelve al segundo grupo sin tocar nada más.

### D4. Testcontainers habla con el daemon por TCP, no por socket

`DOCKER_HOST=tcp://dind:2375` en las etapas con daemon. Como los puertos que Testcontainers publica quedan en el *network namespace* del contenedor `dind` y no en el del controlador, hace falta `TESTCONTAINERS_HOST_OVERRIDE=dind` para que el cliente se conecte a `dind:<puerto>` en lugar de a `127.0.0.1:<puerto>`. El reaper de Testcontainers (Ryuk) es un contenedor más en `ci-net`, así que funciona sin desactivarlo.

*Por qué:* sin `TESTCONTAINERS_HOST_OVERRIDE` el síntoma es un `Connection refused` intermitente según el puerto, que es el fallo más caro de diagnosticar de todo el change. Ambas variables se declaran **una vez** en `environment {}` del `Jenkinsfile`, junto a `BUILDKIT_HOST`, y la etapa las imprime en el log (sin secretos) para que el build diga contra qué daemon está hablando.

*Verificación pendiente antes de escribir los ITs (tarea 2.2):* comprobar en la documentación de Testcontainers que `TESTCONTAINERS_HOST_OVERRIDE` sigue siendo el nombre vigente en la 2.0.5 y que el reaper funciona contra un daemon por TCP; si el reaper se queja, `TESTCONTAINERS_RYUK_DISABLED=true` con limpieza explícita al final de la etapa, y se documenta el porqué.

### D5. Proyecto Compose propio para el e2e y el entorno, sin puertos

La etapa `E2E` levanta el entorno con `docker compose --project-name domincipe-ci-e2e -f ops/compose/docker-compose.base.yml -f ops/compose/docker-compose.ci.yml`. El fichero nuevo `docker-compose.ci.yml` **no publica puertos** y sobreescribe lo necesario para correr dentro del daemon de test (sin `dev`, sin `obs`: la observabilidad no forma parte de lo que el e2e certifica y añadiría tres contenedores a un gate de 4 cores).

*Por qué un fichero nuevo y no reutilizar `dev` o `.env`:* `.env` declara `COMPOSE_FILE` con `base:dev:obs`, y `dev` publica 8080-8086 y compañía; dentro de `dind` esos puertos no colisionan con el host, pero publicarlos no aporta nada y deja contenedores innecesariamente expuestos. Un fichero `ci` explícito y versionado hace que el proyecto e2e sea reproducible y que su diferencia con el entorno de desarrollo esté a la vista.

*Imágenes:* `Images` escribe archivos OCI con las etiquetas `<sha>` y `latest`; la etapa `E2E` los inyecta en el daemon de test con `docker load`. **Verificado el 2026-11-19:** `docker load` acepta un archivo OCI y restaura una etiqueta por cada `org.opencontainers.image.ref.name` de su `index.json`, de modo que la forma que usa `ciBuildImage` —`name=<imagen>:<sha>,<imagen>:latest`— produce las dos referencias sobre el mismo `Id`. Reproducido con `docker buildx build --output 'type=oci,dest=…,"name=x:1,x:latest"'` seguido de `docker load`, que informa dos veces `Loaded image` y deja las dos etiquetas. Sin el `name`, el mismo archivo se carga **solo por Id**: por eso la etapa no puede inventarse el tag y usa el que ya trae. No hace falta el plan B de exportar además `type=docker`. Nunca se reconstruyen las imágenes con el daemon de test: lo que se prueba son los artefactos certificados, no unos parecidos.

*Ciclo de vida:* al empezar la etapa, `docker compose down -v` del proyecto e2e para no arrastrar estado; al terminar, `down -v` otra vez. Así el requisito «entorno recreado» de §7 se cumple también dentro del gate.

*Dos servicios extra en el overlay, ambos con perfil para que `up --wait` no los arranque:*

- **`playwright`**: imagen oficial fijada por digest, en `frontend-net`. La etapa la crea a mano porque el código de prueba vive en el *workspace* del controlador y el daemon es remoto: un *bind mount* lo resolvería el daemon de `dind` y no encontraría nada. Los fuentes viajan en un `tar` copiado con `docker cp`, y el contenedor hace `npm ci` con el `package-lock.json` versionado.
- **`battery-client`**: `python:3.13-alpine` fijada por digest, en `backend-net`. `scripts/verify-shutdown.sh` necesita un cliente **dentro** de la red para alcanzar el contenedor por su dirección; desde el controlador esa dirección no existe. La alternativa era publicar puertos, y el proxy de usuario de Docker amortigua megabytes y falsea justo la medida que el script hace.

Ambos son coste añadido respecto al diseño inicial y quedan aquí escritos como tales: sin ellos, dos de los tres elementos de la batería de entorno no serían ejecutables sobre un daemon remoto sin mentir sobre lo que miden.

### D6. La cobertura del gate no incluye integration

JaCoCo hoy inyecta su agente en la JVM de Surefire vía `argLine`. Failsafe lee el mismo `argLine`, así que sin tocarlo la cobertura de los ITs entraría en el mismo `jacoco.exec` y el gate (80/70 por módulo) mediría unit + integration.

*Decisión:* el agente se inyecta **solo** en Surefire; Failsafe corre con `argLine` vacío. La cobertura de integration se produce en una segunda ejecución de JaCoCo con `destFile=target/jacoco-it.exec` y un informe propio en `target/site/jacoco-it`, que se archiva pero no alimenta `check`.

*Por qué:* es la opción conservadora que la conversación aprobó. Si el gate contara integration, un módulo sin tests unitarios podría pasarlo con ITs, y el umbral dejaría de significar lo que §8 dice que significa. El coste es una configuración de plugin con dos ejecuciones, y la ganancia es que el gate sigue siendo comparable con los builds anteriores a este change.

*Verificado al implementarlo:* `prepare-agent-integration` de JaCoCo 0.8.16 **no** trae `failsafeArgLine` por defecto —se comprobó en el descriptor `META-INF/maven/plugin.xml` y en `AgentITMojo`, y la cadena no aparece en el jar—. Sin `<propertyName>` explícito escribe el mismo `argLine` que consumió Surefire, los ITs corren sin agente y el informe no encuentra datos: exactamente el fallo que se reprodujo en el primer `verify`. La configuración declara `propertyName`, `destFile` y `dataFile` para que el par no dependa de una convención que la versión no cumple.

### D7. Smoke de Playwright sobre invariantes, no sobre pantallas

`apps/web-frontend` gana `@playwright/test@1.65.0` como `devDependency`, `playwright.config.ts` y `e2e/smoke.spec.ts`. El navegador **no** se instala en el frontend ni en el controlador: la etapa usa la imagen oficial `mcr.microsoft.com/playwright:v1.65.0-noble` como contenedor en la red del proyecto e2e, que ya trae Chromium y sus dependencias. El proyecto e2e no publica puertos, así que Playwright apunta a `http://web-frontend:8080` por nombre de servicio.

*El e2e de backend no espera a `Images`.* Se implementó como `ApiGatewayE2EIT` dentro de la mitad Backend: arranca el jar que acaba de repackaginar `spring-boot-maven-plugin` sobre la imagen JRE fijada de §4, con `GenericContainer`, y lo consulta con RestAssured. Depende del artefacto del propio reactor, no de una imagen del proyecto, así que no compite con la etapa `Images` ni la necesita. La etapa `E2E` queda para el entorno y el navegador, que sí consumen las imágenes certificadas.

*Qué comprueba el smoke:* los seis invariantes del requisito «E2E de backend y frontend en cada PR». Concretamente: los contenedores quedan sanos, `GET /` devuelve 200 con el nodo de montaje de la SPA, una ruta interna devuelve la SPA (fallback de nginx), `GET /actuator/health` del gateway responde `UP`, la respuesta lleva `X-Request-Id`, y la consola del navegador no registra errores.

*Corrección sobre la idea inicial:* el gateway se consulta **por su nombre de servicio**, no «a través del proxy». Se comprobó `ops/docker/nginx.conf`: el bundle se construye con `VITE_API_BASE_URL` y el navegador llama al gateway directamente; nginx solo sirve ficheros y el fallback de la SPA. Por eso el runner recibe `E2E_GATEWAY_URL=http://api-gateway:8080` y ambos servicios están en `frontend-net`. Inventar un proxy que no existe habría producido un requisito falso.

*Qué no comprueba, a propósito:* textos de copy, número de elementos, ni flujos de negocio. Cuando existan recetas, se añaden `e2e/*.spec.ts` con `data-testid`; el arnés y estos seis invariantes no se reescriben.

*Reintento:* `retries: 1` solo en el proyecto de e2e, tal como permite §8. `trace: retain-on-failure` y `video`/`screenshot` solo en fallo, para no inflar el archivado de los builds verdes.

### D8. Preflight del host y salud del daemon antes de usarlo

`scripts/ci-preflight.sh` gana las comprobaciones que el daemon de test necesita: que el host permita un contenedor privilegiado, que haya espacio libre suficiente para el volumen de `dind` (se exige un mínimo y se nombra el comando que lo libera) y que el puerto 2375 **no** esté publicado. En el pipeline, antes de Maven, un paso hace `docker info` contra `DOCKER_HOST` y falla nombrando el daemon si no responde.

*Por qué:* el modo de fallo barato de este change es un `dind` que no arranca y un Maven que se queda esperando a Testcontainers. El preflight ya existe con esa filosofía (falla nombrando el requisito y el comando que lo arregla) y es el sitio natural para esto; el paso de `docker info` da el mismo mensaje dentro del build, que es donde se lee cuando algo va mal.

### D9. Archivado de los informes nuevos

`ops/jenkins/vars/ciArchiveReports.groovy` gana los patrones de failsafe (`**/target/failsafe-reports/*.xml`), el informe de cobertura de integration (`**/target/site/jacoco-it/**`), las trazas de Playwright (`e2e/test-results/**`) y los logs de los contenedores del proyecto e2e cuando el build falla. El `post { always }` los publica antes de emitir el estado del commit, con la misma retención (10 builds / 30 días).

*Por qué antes del estado:* es la corrección que ya se hizo en `ci-pipeline` (D10, tarea 9.1) y que aquí aplica igual: publicar el estado antes de archivar anunciaría un éxito que un `junit` posterior puede convertir en `UNSTABLE`.

### D10. Se retira `scripts/ci-suite-scope.sh`

La guarda existía porque un `*IT.java` habría entrado en un `verify` sin daemon y habría muerto dentro de Testcontainers. Con el daemon disponible y con failsafe ejecutándose en la misma invocación, el escenario que protegía ya no existe: retirarla es el cierre correcto, no una pérdida de red.

*Qué queda en su lugar:* el requisito «Sin omisión dentro de la suite de PR» sigue verificando el log, y el modo de fallo que la guarda evitaba (verde falso) ya no puede darse, porque el nivel que antes se saltaba ahora se ejecuta.

## Risks / Trade-offs

- **[`privileged` en el daemon de test]** un contenedor privilegiado es una vía de escape al host → solo existe en el stack local de CI, que no se despliega en producción; no recibe el PAT de GitHub (vive en el controlador), no publica puertos y solo es alcanzable desde `ci-net`; el camino de build sigue sin daemon. Queda escrito en §9 como excepción consciente.
- **[4 cores y ≈5 GB libres]** `dind` + BuildKit + Maven + npm en paralelo pueden agotar la memoria → límites explícitos en el contenedor `dind` (memoria y CPU) como el resto del stack; la medición de la tarea 1.3 decide si `Images` sigue en el primer grupo. Si hay contención, se serializa sin cambiar specs.
- **[Testcontainers contra un daemon remoto]** el reaper y los puertos publicados son el punto frágil → variables declaradas en `environment {}` y un *spike* de verificación (tarea 2.2) antes de escribir los ITs de verdad.
- **[`docker load` de un archivo OCI]** puede no aceptar los dos manifiestos → plan B: exportar `type=docker` con caché caliente (D5), y verificación temprana en la tarea 4.1. Nunca se reconstruye la imagen fuera de `Images`.
- **[Desajuste de versión de Playwright]** imagen 1.65.0 y paquete npm 1.65.0 tienen que coincidir o el navegador no aparece → las dos quedan fijadas y la etapa las afirma al arrancar, con un mensaje que nombra ambas.
- **[El gate se hace más largo]** integration, e2e y entorno añaden minutos → la matriz de D3 solapa lo que no compite y la tarea 1.3 mide cada etapa con su tiempo en `tasks.md`; si el total supera el umbral acordado, se abre la decisión de job aparte (Open Questions).
- **[Un fallo del daemon tumba la mitad sin Docker]** es la consecuencia asumida en D3 → el paso `docker info` previo convierte un fallo de Testcontainers en un mensaje que nombra el daemon y el comando de arranque.

## Migration Plan

1. La rama `feat/ci-integration-release-battery` nace de `develop` y declara **0.3.0-SNAPSHOT** en los doce ficheros que llevan la versión (`pom.xml`, los diez módulos y `apps/web-frontend/package.json`).
2. El daemon de test, el CLI y las etapas entran en el mismo cambio que retira la guarda y que añade los primeros `*IT.java`: no existe un commit intermedio con la guarda fuera y los ITs dentro, ni con ITs y sin daemon.
3. `PROJECT.md` §4 (versiones nuevas), §7 (ciclo de release: la batería ya no se ejecuta solo a mano), §8 (pirámide y DoD: integration y e2e entran en el gate; la guarda desaparece) y §9 (tercer contenedor, excepción de privilegio) se actualizan en el mismo change. `README.md` también.
4. Rollback: revert del commit *squash* del PR. No hay migración de datos ni estado que deshacer; los volúmenes del stack se recrean con `down -v`.

## Open Questions

- ¿Migrar a `docker:dind-rootless` si una verificación posterior demuestra que funciona sin `privileged`? Se puede responder sin tocar specs ni tareas: sería un cambio de imagen y `security_opt` (D1).
- ¿Sacar integration a un job aparte si el gate supera un umbral de tiempo? Depende de la medición de la tarea 1.3 y cambiaría la protección de ramas, así que se decide con datos, no ahora.
- ¿Timeouts exactos de arranque del entorno e2e en CI? Se fijan con la primera medición, dentro de `up --wait` y del healthcheck, sin cambiar requisitos.




