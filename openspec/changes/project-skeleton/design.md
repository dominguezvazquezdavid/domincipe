# Design

## Context

El repositorio no contiene todavía código: solo documentación, `openspec/` y las skills de OpenSpec en `.agents/skills/`, y `main` no tiene commits. Por tanto no hay restricciones de compatibilidad ni datos que migrar, y toda decisión de estructura se puede tomar sin deuda previa. Las restricciones que sí condicionan el diseño vienen de [PROJECT.md](../../../PROJECT.md): Java 21, Spring Boot 4.x, Maven multi-módulo con parent en la raíz, PostgreSQL 16 con un schema por servicio, Kafka 4.x en modo KRaft, Versity S3 Gateway y Mailpit, entorno local cloud-like con healthchecks y límites, y gate de cobertura JaCoCo ≥80 % líneas / ≥70 % ramas. La motivación del change está en [proposal.md](../proposal.md); los requisitos, en [`specs/`](./specs/).

Un condicionante adicional es la **Regla 0.2** de [AGENTS.md](../../../AGENTS.md): ninguna versión se escribe por memoria. Por eso el diseño fija *cómo* se elige cada versión, no un número concreto: la versión exacta de Spring Boot 4.x, de springdoc-openapi, de las imágenes base y de Kafka 4.x se verifica en la tarea 1.2 contra Maven Central y el registro de imágenes antes de fijarla en el POM.

## Goals / Non-Goals

**Goals:**

- Un `./mvnw -B -ntp verify` desde la raíz que compile, analice y pruebe los ocho módulos Java con el gate de cobertura activo.
- Servicios arrancables de verdad (no esqueletos vacíos): salud, métricas, correlación de peticiones, configuración por entorno y apagado ordenado funcionando y cubiertos por tests.
- Un `docker compose ... up --wait` que deje el entorno listo y sano sin pasos manuales, con las mismas garantías operativas que se buscan en producción.
- Un frontend que compila, pasa lint y tests, y no arranca si le falta la configuración obligatoria.

**Non-Goals:**

- Lógica de dominio, entidades, repositorios y migraciones Flyway: los servicios de este change **no se conectan a ninguna base de datos**. Flyway y el acceso a datos entran con el change de cada dominio, para no acoplar dominios todavía inexistentes.
- Flujos de autenticación y emisión de JWT: `spring-boot-starter-security` se añade como dependencia, sin reglas de negocio.
- Pipeline de Jenkins, Kaniko y escaneo Trivy (`ops/jenkins`): requiere un Jenkins real para ser verificable; se aborda en un change propio (`ci-pipeline`).
- Loki y Tempo: la pila de observabilidad de este change se limita a Prometheus, Grafana y Kafka UI; el resto del stack entra cuando haya trazas reales que visualizar.
- Kubernetes, Helm, Vault y Debezium (roadmap de PROJECT.md §10).

## Decisions

### D1. El parent POM hereda de `spring-boot-starter-parent`

La raíz contiene un único `pom.xml` que actúa a la vez como agregador y como parent de todos los módulos, heredando de `spring-boot-starter-parent` con la versión fijada en una property. La versión elegida tras la verificación de la tarea 1.2 es **4.1.2** (ver *Open Questions*).

*Alternativas consideradas:* importar solo `spring-boot-dependencies` como BOM. Se descarta porque obliga a configurar a mano *surefire*, *failsafe*, *jacoco*, *checkstyle* y el filtrado de recursos en cada módulo; heredar del starter-parent aporta esos valores por defecto y concentra la política de build en un solo fichero.

### D2. Maven Wrapper versionado

Se versionan `./mvnw`, `./mvnw.cmd` y `.mvn/wrapper/` con la versión de Maven fijada.

*Por qué:* el build no depende del Maven instalado en la máquina ni del que traiga la imagen de CI, que es la única forma de que «funciona en local» y «funciona en CI» signifiquen lo mismo. *Alternativa:* exigir Maven 3.9+ instalado; se descarta por reproducibilidad.

### D3. Java 21 con hilos virtuales activados

Los servicios arrancan con `spring.threads.virtual.enabled=true` y compilan con `--release 21`.

*Por qué:* la carga del proyecto es intensiva en E/S (HTTP, base de datos, Kafka) y Java 21 es requisito de PROJECT.md. *Alternativa:* hilos de plataforma; se descarta porque no aporta nada aquí y desaprovecha la LTS elegida.

### D4. Lint del backend con Checkstyle en la fase `validate`

`maven-checkstyle-plugin` se declara en `pluginManagement` del parent y se ejecuta atado a `validate` en todos los módulos, con el fichero `config/checkstyle/checkstyle.xml`.

Reglas mínimas: `PackageName` con formato `^com\.domincipe(\.[a-z][a-z0-9]*)*$` (esto es lo que hace fallar el build ante una clase fuera del prefijo exigido por la spec), longitud de línea 120, prohibición de *star imports* y de imports no usados.

*Alternativas:* Spotless o google-java-format. Se descartan **de momento** porque reformatean todo el árbol y generan ruido en los diffs; se pueden añadir después como capa de formato, ya que no se solapan con la comprobación de nombres de paquete.

### D5. Gate JaCoCo en el parent, con exclusiones explícitas

`jacoco-maven-plugin` se configura en el parent: `prepare-agent` + `report` + `check` con `minimum` de 0.80 líneas y 0.70 ramas, excluyendo `**/*Application.class`, `**/dto/**` e `**/*Impl.class` (MapStruct), tal como exige [PROJECT.md §8](../../../PROJECT.md).

**Riesgo conocido y cómo se resuelve:** en este change la mayoría de módulos solo contiene la clase `*Application`, que está excluida del cómputo, y un módulo sin clases analizables puede producir un ratio no computable. El comportamiento exacto de `jacoco:check` en ese caso **no se asume**: se verifica empíricamente en la tarea 2.3 con el build real y, según el resultado, se aplica una de las dos opciones ya decididas —(a) excluir del gate los módulos sin clases ejecutables, o (b) marcar `jacoco.skip` en esos módulos—. En ambos casos el gate sigue activo donde hay código: `libs/common-observability` lo tiene desde este change y la tarea 2.3 comprueba que un test de baja cobertura lo rompe de verdad.

**Verificado el 2026-11-13 (tarea 2.3) — decisión cerrada:** con JaCoCo 0.8.16, un módulo sin fichero de ejecución (`jacoco.exec`) imprime `Skipping JaCoCo execution due to missing execution data file` y el build sigue en verde; un módulo con datos pero sin clases analizables tras las exclusiones imprime `Analyzed bundle ... with 0 classes` y `All coverage checks have been met.`. **No se aplica ninguna de las dos opciones**: ni exclusión de módulos del gate ni `jacoco.skip`, porque el plugin ya resuelve ambos casos por sí solo. Las tres exclusiones se comprobaron en una sola pasada —cuatro clases en disco (`*Application`, `dto`, `*Impl` y una real) y solo una analizada— y la prueba negativa rompe el build con `lines covered ratio is 0.00, but expected minimum is 0.80` y `branches covered ratio is 0.00, but expected minimum is 0.70`. La comprobación se hizo con el módulo desechable `libs/jacoco-probe`, borrado después, porque `libs/common-observability` nace en la tarea 3.1; el gate se vuelve a ejercer sobre código real en 4.1 y 5.4.

**Nota para el PR (tarea 2.4), lista para copiar en la descripción:**

> **Gate JaCoCo: la decisión de D5 queda como está.** La tarea 2.3 verificó empíricamente con JaCoCo 0.8.16 qué hace `jacoco:check` en los dos casos límite que este change introduce, y no hay que añadir nada:
>
> - Módulo **sin datos de ejecución** (sin `jacoco.exec`): el plugin registra `Skipping JaCoCo execution due to missing execution data file` y el build continúa en verde.
> - Módulo **con datos pero sin clases analizables** tras las exclusiones: registra `Analyzed bundle ... with 0 classes` y `All coverage checks have been met.`, porque el ratio no es computable y no se viola ningún límite.
>
> Por eso se descartan las dos opciones que estaban abiertas —(a) excluir del gate los módulos sin clases ejecutables y (b) marcar `jacoco.skip` en esos módulos—: ninguna hace falta y ambas habrían quitado el gate donde sí hay código. El gate sigue activo con los umbrales de `PROJECT.md` §8, **0.80 de líneas y 0.70 de ramas**, y las tres exclusiones (`**/*Application.class`, `**/dto/**`, `**/*Impl.class`) se aplican tanto al informe como al `check`, de modo que el HTML de `target/site/jacoco/index.html` muestra exactamente las clases que se miden.
>
> **La prueba negativa demuestra que el gate muerde**: con una clase real sin tests, el build falla con `lines covered ratio is 0.00, but expected minimum is 0.80` y `branches covered ratio is 0.00, but expected minimum is 0.70`. Se hizo sobre el módulo desechable `libs/jacoco-probe`, borrado después porque `libs/common-observability` nace en la tarea 3.1; el gate se vuelve a ejercer sobre código real en 4.1 y 5.4, y en el `verify` completo de 9.3 cada módulo informa `All coverage checks have been met.`
>
> **Coherencia POM ↔ comentario:** los dos umbrales del `pom.xml` son las properties `jacoco.line.minimum` (0.80) y `jacoco.branch.minimum` (0.70), y el comentario que precede al plugin declara esa misma regla y las mismas tres exclusiones. No hay un segundo juego de valores ni un módulo con configuración propia.

### D6. Detección de módulos no declarados con un script

Maven ignora en silencio cualquier directorio que no figure en `<modules>` del agregador, así que la garantía de la spec necesita un mecanismo propio: `scripts/verify-modules.sh` recorre los directorios con `pom.xml` bajo `apps/`, `apps/services/` y `libs/`, los compara con los módulos declarados y devuelve código distinto de 0 nombrando los que falten. `exec-maven-plugin` lo ejecuta en `validate` desde el POM raíz.

*Alternativa:* un test ArchUnit; se descarta porque ArchUnit analiza el classpath ya construido, no la estructura del repositorio, y nunca vería un directorio que el reactor ni siquiera visita.

### D7. `libs/common-observability` como auto-configuración

La librería aporta una auto-configuración de Spring Boot registrada en `META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports` con: exposición de `health`, `liveness`, `readiness` y `prometheus`; un `OncePerRequestFilter` que propaga o genera `X-Request-Id` y lo inyecta en el MDC; los valores por defecto de apagado ordenado y de hilos virtuales; y el `@ConfigurationProperties` validado de `APP_ENVIRONMENT`.

*Por qué:* los seis servicios deben comportarse igual y la única forma sostenible es un artefacto compartido que se añade como dependencia. *Alternativa:* copiar la configuración en cada `application.yml`; se descarta porque la primera corrección se aplicaría en un módulo y no en los otros cinco.

### D8. Configuración tipada con fallo temprano

`APP_ENVIRONMENT` se modela como enumerado (`local`, `dev`, `obs`) en un `@ConfigurationProperties` anotado con `@Validated` y **sin valor por defecto**. Si falta, el arranque falla nombrando la propiedad; si el valor no está entre los admitidos, el mensaje lista los válidos.

*Por qué:* arrancar con un valor por defecto silencioso es justo el fallo que se quiere evitar en un entorno cloud-like: un contenedor mal configurado debe morir al arrancar, no servir tráfico con la configuración equivocada. *Alternativa:* valores por defecto en `application.yml`; se descarta por lo anterior.

### D9. Compose por capas: base + `dev` + `obs`

`docker-compose.base.yml` define servicios, healthchecks, redes y límites; `docker-compose.dev.yml` añade puertos publicados y volúmenes de datos; `docker-compose.obs.yml` añade la pila de observabilidad y queda incluido en el arranque por defecto a través de `COMPOSE_FILE` declarado en `.env`. El proyecto se nombra `domincipe` para que los contenedores y la red tengan nombres estables que los scripts de verificación puedan resolver.

**El servidor de desarrollo del frontend no vive en Compose (decisión del 2026-11-16, opción B).** `dev` sirve el bundle inmutable de nginx y el hot reload se ejecuta en el host con `VITE_API_BASE_URL=http://localhost:8080 npm run dev` (Vite, puerto 5173), que es el flujo ya documentado en `apps/web-frontend/README.md` y no añade ningún requisito nuevo: Node ≥ 22.22.0 ya lo es del proyecto. *Por qué:* el `up --wait` canónico tiene que ejercitar el artefacto que se despliega —la imagen que se construye en 7.2, se valida en 9.3 y sirve de banco al e2e de Playwright de §8— y no puede depender de la red: un `npm ci` en el arranque mete el registro npm en la ruta crítica de todas las verificaciones posteriores (8.2, 8.3, 9.3), y un volumen de `node_modules` con guarda de existencia no se invalida al cambiar `package-lock.json`, con lo que arrancaría con dependencias viejas en silencio. A eso se suma que el `Dockerfile` oficial de `node:22-alpine` no declara `USER` (verificado: el contenedor corre como root), así que cumplir el requisito de no privilegios exigiría preparar el propietario de ese volumen. *Alternativa descartada:* sustituir `web-frontend` por la imagen de Node en `dev`. Si algún día se quiere HMR dentro de Docker, la forma correcta es una **imagen de desarrollo propia** (dependencias resueltas en la etapa de build y `USER node`) como fichero opcional **fuera** de `COMPOSE_FILE`, nunca en el arranque canónico.

El aprovisionamiento (schemas, topics, bucket) se hace con contenedores de inicialización de vida corta (`restart: "no"`) y ejecución idempotente: `CREATE SCHEMA IF NOT EXISTS` para PostgreSQL, `kafka-topics --create --if-not-exists` para Kafka y `aws --endpoint-url http://versity:7070 s3api create-bucket` con comprobación previa (`head-bucket`) para Versity. Los servicios que los necesitan los declaran con `depends_on: condition: service_completed_successfully`; los que dependen de un proceso de larga vida usan `condition: service_healthy`.

*Por qué:* los contenedores de inicialización hacen el aprovisionamiento observable y repetible, y evitan meter lógica de arranque en las imágenes de los servicios. *Alternativa:* un script de arranque en el host; se descarta porque introduciría pasos manuales y rompería el «un solo comando».

### D10. Aislamiento por pertenencia a redes, con `frontend-net` interna

`frontend-net` agrupa `web-frontend` y `api-gateway` y se declara `internal: true`; `backend-net` agrupa `api-gateway`, los servicios y las dependencias de datos; `obs-net` agrupa el stack de observabilidad con los servicios.

*Por qué:* el requisito es que el frontend no resuelva `postgres`, y eso se consigue excluyéndolo de `backend-net`. *Trade-off asumido y documentado:* esto es aislamiento por DNS de Compose, no un cortafuegos L3/L4; una NetworkPolicy real llega con Kubernetes (roadmap §10). `frontend-net` no se marca interna porque lo que se aísla es la **pertenencia**, no el egreso: el requisito no pide bloquear la salida, y cómo se comportan los puertos publicados sobre una red `internal: true` es algo que este change no ha medido, así que no se cambia sin comprobarlo.

### D11. Un Dockerfile reutilizable por tecnología

`ops/docker/java-service.Dockerfile` se parametriza con `ARG MODULE` y lo comparten los seis módulos Java: etapa de build con Maven + JDK 21 y etapa de runtime con JRE 21 sobre Alpine, usuario `10001` y `ENV` sin secretos. `ops/docker/web-frontend.Dockerfile` compila con Node y sirve con nginx sin privilegios.

El etiquetado `latest` + SHA de git lo hace `scripts/build-images.sh`, que construye cada imagen con `--build-arg GIT_SHA=$(git rev-parse --short HEAD)` y aplica ambos tags. Kaniko sustituirá a ese script en el change de CI sin tocar los Dockerfiles.

*Alternativa:* un Dockerfile por servicio; se descarta hasta que un servicio necesite de verdad una etapa distinta.

### D12. Los servicios no se conectan a datos en este change

Ningún servicio declara `spring-boot-starter-data-jpa`, `flyway-core` ni un `DataSource`. PostgreSQL, Kafka, Versity S3 Gateway y Mailpit se aprovisionan en el entorno y se verifican contra el propio entorno (schemas, topics, bucket, SMTP), no contra los servicios.

*Por qué:* así el esqueleto se puede validar sin inventar modelos de dominio y cada servicio añade su persistencia, con sus migraciones, en el change que la necesita. *Consecuencia:* el gate de cobertura se ejercita en `libs/common-observability` (código real) y en los tests de los servicios, no en capas de datos todavía inexistentes.

### D13. Frontend: Vite + TypeScript estricto y fail-fast de configuración

Vite 8 con `react-ts`, TypeScript 5.9.3 y `strict: true` en `tsconfig.json`, ESLint 10 con configuración plana y `typescript-eslint` 8, Vitest 5 + Testing Library con cobertura. La URL del API se valida en `vite.config.ts` (de modo que `npm run build` falla si `VITE_API_BASE_URL` no está definida) y se consume en `src/config/env.ts` como única fuente. El arranque monta `createBrowserRouter` (React Router 8) y un `QueryClientProvider` (TanStack Query 5) sobre un layout con estado vacío explícito.

*Por qué validar en `vite.config.ts`:* es el único punto que se ejecuta tanto en `dev` como en `build`, así que el fallo aparece antes de empaquetar y no en tiempo de ejecución en el navegador. *Alternativa:* fallar solo en `src/config/env.ts`; se descarta porque `npm run build` terminaría con código 0 generando un bundle inservible.

### D14. Una propiedad repetida se declara una sola vez

La tarea 5.1 deja una clase de test por servicio con `@SpringBootTest(properties = "app.environment=local")`, porque `APP_ENVIRONMENT` es obligatoria y no tiene valor por defecto. La repetición es aceptable mientras haya una sola clase por módulo, pero no escala: 5.2, 5.3 y 5.5 añaden varias clases por servicio. La regla, registrada en [PROJECT.md §7](../../../PROJECT.md), es que **toda propiedad de configuración que se repita entre módulos o clases se declara una sola vez**: en un fichero `.properties` cuando la repetición es de configuración y en una anotación compuesta compartida cuando la repetición está en anotaciones de test.

La forma prevista es `libs/common-test-support` con `@DomincipeServiceTest`, una anotación meta-anotada con `@SpringBootTest` que aporta `app.environment=local` y replica `webEnvironment` con `@AliasFor`; los servicios la declaran en scope `test`. **Se implementa en la tarea 5.2**, no en 5.1, para diseñarla con los requisitos ya conocidos de 5.2 (entorno web real), 5.3 (caso sin la propiedad, que no puede usar la anotación tal cual) y 5.5 (documentación OpenAPI).

*Verificado el 2026-11-13 con un módulo desechable:* una anotación compuesta sobre `@SpringBootTest` aplica sus propiedades a un test real, y un módulo que solo contiene la anotación deja el gate JaCoCo en verde (`Analyzed bundle ... with 0 classes` → `All coverage checks have been met.`), sin necesidad de `jacoco.skip` ni de exclusiones nuevas, por lo que D5 sigue cerrada.

### D15. Documentación como parte del entregable

Al aplicar el change se actualizan `PROJECT.md` §3 (alcance real de la pila de observabilidad), §4 (versiones verificadas), §6 (nuevos `config/`, `scripts/`, `.env.example` y `.mvn/`) y §9 (`COMPOSE_FILE` y arranque por defecto con observabilidad), y `README.md` (estado del proyecto y comandos ya ejecutados). Sin esta actualización, la fuente de verdad quedaría desalineada con el repositorio en el mismo commit que lo crea.

### D16. Documentación OpenAPI con springdoc-openapi 3.x

Cada servicio añade `springdoc-openapi-starter-webmvc-ui`, que expone la especificación generada desde el código en `/v3/api-docs` (y `/v3/api-docs.yaml`) y Swagger UI en `/swagger-ui.html`, sin configuración adicional. El título y la versión del documento se alimentan del nombre y la versión del módulo, para que la documentación identifique el servicio que la publica.

**Compatibilidad verificada**, no supuesta: la tabla oficial del repositorio de springdoc indica Spring Boot 4.x → springdoc **3.x** y Spring Boot 3.x → springdoc **2.x**; en Maven Central (`repo1.maven.org/maven2/org/springdoc/springdoc-openapi-starter-webmvc-ui/maven-metadata.xml`) la última publicada de la línea 3.x es **3.2.0**, cuyo POM hereda de `spring-boot-starter-parent` **4.1.2**, exactamente la versión elegida para el proyecto. Queda descartada la línea 2.x (última **2.10.0**, construida sobre Spring Boot 3.5.16, fuera de soporte OSS desde el 2026-06-30). La versión exacta se confirma junto al resto en la tarea 1.2.

Desactivación: `springdoc.api-docs.enabled` y `springdoc.swagger-ui.enabled` se alimentan de una única variable de entorno `APP_DOCS_ENABLED` (por defecto `true`), de modo que apagar la documentación no exige tocar código ni la imagen.

*Trade-offs:* publicar el contrato revela la superficie de la API, así que en un entorno real se desactivaría o se protegería en el gateway; aquí se mantiene activo porque el proyecto es didáctico y consultar Swagger es parte del aprendizaje. *Alternativa considerada:* agregar las especificaciones de todos los servicios en el `api-gateway`; se pospone porque añade configuración de springdoc en el gateway antes de que existan endpoints reales que agregar.

### D17. La carpeta de operación se llama `ops/`, no `infra/`

Los Dockerfiles, los ficheros de Compose y el pipeline de Jenkins viven bajo **`ops/`** (`ops/docker`, `ops/compose`, `ops/jenkins`). `infra/` se descarta por decisión del usuario, y también por precisión: en la mayoría de repos `infra/` se asocia a infraestructura como código (Terraform, CloudFormation, manifiestos de Kubernetes) y aquí no hay nada de eso — son artefactos de operación del proyecto en local y en CI.

*Alternativas evaluadas:* `platform/` (sugiere un equipo o una plataforma interna, demasiado grandilocuente para un proyecto personal), `deploy/` (sugiere despliegue, pero la carpeta también contiene la definición de imágenes y el entorno local), `devops/` (más largo y menos concreto) y `docker/` (no cubriría `jenkins/`). El cambio afecta a `PROJECT.md` §6 y §9, `README.md`, `.gitignore` y a los artefactos de este change; se hace ahora, antes de que exista ningún fichero con esa ruta, para no arrastrar un renombrado con historial detrás.

### D18. Almacenamiento de objetos: Versity S3 Gateway en lugar de MinIO

MinIO se descarta porque sus imágenes oficiales ya no se publican: `minio/minio` responde 404 en Docker Hub, `quay.io/minio/minio` y `ghcr.io/minio/minio` no ofrecen manifiesto anónimo, y el último release upstream es RELEASE.2025-10-15 (oct-2025). Se adopta **Versity S3 Gateway v1.11.0** (`versity/versitygw:v1.11.0`, Apache-2.0, digest `sha256:8319a530…`), que traduce el protocolo S3 a un backend POSIX: un solo contenedor, datos en un volumen y credenciales por `ROOT_ACCESS_KEY`/`ROOT_SECRET_KEY`.

*Verificado el 2026-11-12*: la imagen arranca en el puerto **7070** y responde **403** a las peticiones sin firmar; no expone `/health` ni `/metrics` por defecto, así que el healthcheck de Compose se define sobre esa respuesta y el aprovisionamiento del bucket pasa de `mc mb` a `aws s3api`. *Consecuencia:* las presigned URLs, que `media-service` necesita, deben validarse explícitamente en la tarea 7.x.

### D19. El apagado ordenado se verifica con 0 o 143, nunca 137

El contrato de apagado se cumplió con un `docker compose stop` real y una petición en curso, y la medición obligó a corregir las specs: **el JVM sale con 143 (`128 + SIGTERM`), no con 0**. Un proceso Java que atiende `SIGTERM` drena el contexto y termina por la señal, y Docker reporta ese 143; forzar el 0 exigiría un wrapper de entrypoint que reescribiera el código de salida, lo que además oculta si la parada fue externa. El código que delata un fallo de verdad es **137 (`128 + SIGKILL`)**: el periodo de gracia se agotó antes de que el drenaje terminase.

Medido el 2026-11-16 con `scripts/verify-shutdown.sh`: `docker compose stop api-gateway` tarda ~3,3 s (tres ejecuciones consecutivas: 3321, 3302 y 3323 ms), la respuesta en curso llega completa (`HTTP 200`, 1 684 244 B de `swagger-ui-bundle.js`) y el contenedor figura con `ExitCode` 143; el log del servicio muestra `Commencing graceful shutdown. Waiting for active requests` y `Graceful shutdown complete` separados por esos ~3 s. `web-frontend` sí sale 0 porque su imagen fija `STOPSIGNAL=SIGQUIT` y nginx drena con esa señal; por eso el contrato se enuncia como «0 o 143».

Dos detalles de la implementación, también medidos: la petición tiene que ir **directa a la IP del contenedor**, porque el *userland proxy* que Docker pone delante del puerto publicado bufferiza megabytes y el servicio no llega a bloquearse (el stop terminaba en ~0,4 s y truncaba la respuesta); y se envían **tres peticiones pipelineadas** del bundle de Swagger UI, el mayor recurso sin endpoints de negocio (1,68 MB), para que la primera siga escribiéndose cuando llega `SIGTERM`. Las peticiones pipelineadas que Tomcat no llegó a despachar se cierran con la conexión al terminar el drenaje: es el comportamiento normal de HTTP/1.1 y no se exige respuesta para ellas; lo que nunca se acepta es un cuerpo incompleto.

*Alternativas descartadas:* exigir 0 (mentira sobre la causa de la terminación, más un wrapper como PID 1 con su propia clase de fallos de *signal forwarding*), aceptar también 137 (taparía el único fallo real) y verificar solo `web-frontend` (no ejercitaría el drenaje de Spring, que es el requisito de `service-runtime`).

### D20. Observabilidad siempre activa, no un perfil opt-in

`docker-compose.obs.yml` levanta Prometheus, Grafana y Kafka UI **sin `profiles:`**, y `.env.example` declara `COMPOSE_FILE` con los tres ficheros (base, dev y obs). Así el comando canónico `docker compose up --wait` desde la raíz levanta el entorno completo, observabilidad incluida.

*Verificado empíricamente en esta máquina* (Docker 29.9.3 / Compose v5.7.1 en la medición original; Docker 29.10.0 / Compose v5.7.1 al verificar la tarea 8.3): con `COMPOSE_FILE=ops/compose/docker-compose.base.yml:ops/compose/docker-compose.obs.yml` en `.env`, `docker compose config --services` desde la raíz lista los servicios de ambos ficheros, resolviendo las rutas relativas correctamente. No es una suposición sobre el comportamiento de Compose.

*Por qué siempre activa:* en un entorno real la recolección de métricas no es opcional —si los objetivos no se scrapean desde el primer minuto, no hay histórico cuando aparece el problema— y el objetivo educativo del proyecto es precisamente ver esa instrumentación funcionando. Un perfil desactivado por defecto acaba no arrancándose nunca.

*Trade-off asumido:* Prometheus, Grafana y Kafka UI consumen RAM y CPU en local. Se mitiga con límites de recursos en Compose y con una vía de escape documentada: quitar el fichero de observabilidad de `COMPOSE_FILE` (o pasar `-f` explícitos) arranca el resto del entorno sin ella. *Alternativas descartadas:* `profiles: [obs]` (oculta por defecto lo que el proyecto quiere enseñar) e integrar el stack directamente en `docker-compose.base.yml` (rompe la separación por capas que fija PROJECT.md §9 y obliga a editar el fichero base para cambiar de escenario).

**Alcance:** en este change la pila se limita a Prometheus, Grafana y Kafka UI. Loki y Tempo exigirían instrumentación de trazas (exportador OTLP, colector) sin tráfico real que analizar; incluirlos ahora daría contenedores decorativos. PROJECT.md §3 y §9 se actualizan para reflejar el reparto.

**Nota de numeración:** esta decisión nació como D14 y al cerrar la tarea 9.1 se renumeró a D20 y se movió al final del apartado, porque D14 estaba asignado dos veces en este documento y así las decisiones se leen en orden D1–D20. Se conserva el identificador D14 para la decisión «Una propiedad repetida se declara una sola vez», que es la que citan `PROJECT.md` §6 y §7, los seis `pom.xml` de servicio y las clases de `libs/common-test-support`; renumerar aquella habría roto catorce referencias, mientras que esta solo figuraba en dos comentarios de Compose.

## Risks / Trade-offs

- **Deriva de versiones** (Spring Boot, imágenes base, Kafka) → se fija cada versión en una única property tras verificarla contra Maven Central y el registro de imágenes (tarea 1.2); ninguna versión se escribe por memoria.
- **Ratio de cobertura no computable en módulos sin clases analizables** → comportamiento verificado empíricamente en la tarea 2.3 y resuelto con exclusión explícita del módulo o `jacoco.skip`, documentando la decisión; el gate se demuestra rompiéndolo con un test de baja cobertura.
- **Healthcheck de Kafka KRaft frágil** (el broker tarda en elegir líder) → `start_period` amplio, comprobación con `kafka-topics --list` en lugar de un `nc` al puerto, y sin reintentos infinitos: si no está sano, `up --wait` falla y el fallo es visible.
- **El aislamiento de redes no es un cortafuegos** → asumido y documentado; se mitiga de verdad con NetworkPolicies al migrar a Kubernetes.
- **Testcontainers descarga imágenes pesadas en cada ejecución limpia** → reutilización local opcional documentada; la CI siempre parte de estado limpio para no ocultar dependencias del entorno.
- **`npm ci` ignora `engines` por defecto** → `.npmrc` con `engine-strict=true`, que es lo que convierte el requisito de Node ≥ 22.12.0 en un fallo real de instalación.
- **`frontend-net` interna bloquearía el egreso del contenedor del frontend** → no necesita salir (sirve el bundle construido fuera de Compose), pero bloquear el egreso no forma parte del requisito y el comportamiento de los puertos publicados sobre una red `internal: true` no se ha medido; se deja no interna y el aislamiento efectivo sigue siendo la pertenencia a redes (D10).
- **Presigned URLs en Versity** → la compatibilidad S3 no garantiza todas las variantes de firma; se valida con una subida y una descarga presignadas en la tarea 7.x y, si falla alguna variante, se documenta el límite antes de escribir `media-service`.

## Migration Plan

No hay migración de datos ni compatibilidad que preservar: el repositorio no tiene commits previos ni código desplegado.

1. Crear la rama `feat/project-skeleton-bootstrap` desde `main`.
2. Aplicar las tareas de `tasks.md` en orden; cada grupo deja su verificación en verde antes de pasar al siguiente.
3. Verificar la suite completa (backend, frontend y scripts de infraestructura) y actualizar la documentación.
4. **Rollback**: revertir el commit o abandonar la rama; al no existir versiones anteriores ni datos productivos, no se requiere plan de vuelta atrás adicional.

## Open Questions

- **Cerrada en la tarea 1.2 (2026-11-12)**: Spring Boot **4.1.2**, springdoc-openapi **3.2.0**, `apache/kafka:4.4.0` y `versity/versitygw:v1.11.0`, verificados en Maven Central, la documentación de springdoc, Docker Hub y el arranque real de la imagen S3. Se descartó Spring Boot 3.5.16 (última de la línea 3.x) por estar fuera de soporte OSS desde el 2026-06-30, y con ella springdoc 2.10.0; MinIO se descartó porque ya no publica imágenes oficiales. El cambio obligó a actualizar este design, `proposal.md`, `tasks.md`, `PROJECT.md` §4 y `AGENTS.md`.
- **Toolchain del frontend (2026-11-12)**: React 19.3.1, Vite 8.3.8, TypeScript 5.9.3, ESLint 10.14.0 con `typescript-eslint` 8.72.2, Tailwind 4.3.5, React Router 8.5.1, TanStack Query 5.107.1, Vitest 5.1.0 y Node ≥ 22.22.0. TypeScript 7.0.2 queda descartado porque `typescript-eslint` 8.72.2 solo admite `<6.1.0`.
- **Cerrada en la tarea 7.1 (2026-11-16)**: imágenes base fijadas tras verificar los tags en el registro de Docker Hub — `maven:3.9.16-eclipse-temurin-21-alpine`, `eclipse-temurin:21.0.13_9-jre-alpine`, `node:22.23.5-alpine` y `nginxinc/nginx-unprivileged:1.30.6-alpine` — y registradas en `PROJECT.md` §4.
- **Remitente por defecto de Mailpit** (`MAIL_FROM`): se elige un placeholder en `.env.example`; no afecta a ningún requisito de este change.



