# Design

## Context

El repositorio no contiene todavía código: solo documentación, `openspec/` y `.continue/`, y `main` no tiene commits. Por tanto no hay restricciones de compatibilidad ni datos que migrar, y toda decisión de estructura se puede tomar sin deuda previa. Las restricciones que sí condicionan el diseño vienen de [PROJECT.md](../../../PROJECT.md): Java 21, Spring Boot 3.x, Maven multi-módulo con parent en la raíz, PostgreSQL 16 con un schema por servicio, Kafka 4.x en modo KRaft, MinIO y MailHog, entorno local cloud-like con healthchecks y límites, y gate de cobertura JaCoCo ≥80 % líneas / ≥70 % ramas. La motivación del change está en [proposal.md](../proposal.md); los requisitos, en [`specs/`](./specs/).

Un condicionante adicional es la **Regla 0.2** de [AGENTS.md](../../../AGENTS.md): ninguna versión se escribe por memoria. Por eso el diseño fija *cómo* se elige cada versión, no un número concreto: la versión exacta de Spring Boot 3.x, de las imágenes base y de Kafka 4.x se verifica en la tarea 1.2 contra Maven Central y el registro de imágenes antes de fijarla en el POM.

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

La raíz contiene un único `pom.xml` que actúa a la vez como agregador y como parent de todos los módulos, heredando de `spring-boot-starter-parent` con la versión fijada en una property.

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

`docker-compose.base.yml` define servicios, healthchecks, redes y límites; `docker-compose.dev.yml` añade puertos publicados, volúmenes de datos y el servidor de desarrollo del frontend; `docker-compose.obs.yml` añade la pila de observabilidad y queda incluido en el arranque por defecto a través de `COMPOSE_FILE` declarado en `.env`. El proyecto se nombra `domincipe` para que los contenedores y la red tengan nombres estables que los scripts de verificación puedan resolver.

El aprovisionamiento (schemas, topics, bucket) se hace con contenedores de inicialización de vida corta (`restart: "no"`) y ejecución idempotente: `CREATE SCHEMA IF NOT EXISTS` para PostgreSQL, `kafka-topics --create --if-not-exists` para Kafka y `mc mb --ignore-existing` para MinIO. Los servicios que los necesitan los declaran con `depends_on: condition: service_completed_successfully`; los que dependen de un proceso de larga vida usan `condition: service_healthy`.

*Por qué:* los contenedores de inicialización hacen el aprovisionamiento observable y repetible, y evitan meter lógica de arranque en las imágenes de los servicios. *Alternativa:* un script de arranque en el host; se descarta porque introduciría pasos manuales y rompería el «un solo comando».

### D10. Aislamiento por pertenencia a redes, con `frontend-net` interna

`frontend-net` agrupa `web-frontend` y `api-gateway` y se declara `internal: true`; `backend-net` agrupa `api-gateway`, los servicios y las dependencias de datos; `obs-net` agrupa el stack de observabilidad con los servicios.

*Por qué:* el requisito es que el frontend no resuelva `postgres`, y eso se consigue excluyéndolo de `backend-net`. *Trade-off asumido y documentado:* esto es aislamiento por DNS de Compose, no un cortafuegos L3/L4; una NetworkPolicy real llega con Kubernetes (roadmap §10). `frontend-net` no se marca interna porque el servidor de desarrollo de Vite necesita alcanzar el registro de npm en `dev`.

### D11. Un Dockerfile reutilizable por tecnología

`ops/docker/java-service.Dockerfile` se parametriza con `ARG MODULE` y lo comparten los seis módulos Java: etapa de build con Maven + JDK 21 y etapa de runtime con JRE 21 sobre Alpine, usuario `10001` y `ENV` sin secretos. `ops/docker/web-frontend.Dockerfile` compila con Node y sirve con nginx sin privilegios.

El etiquetado `latest` + SHA de git lo hace `scripts/build-images.sh`, que construye cada imagen con `--build-arg GIT_SHA=$(git rev-parse --short HEAD)` y aplica ambos tags. Kaniko sustituirá a ese script en el change de CI sin tocar los Dockerfiles.

*Alternativa:* un Dockerfile por servicio; se descarta hasta que un servicio necesite de verdad una etapa distinta.

### D12. Los servicios no se conectan a datos en este change

Ningún servicio declara `spring-boot-starter-data-jpa`, `flyway-core` ni un `DataSource`. PostgreSQL, Kafka, MinIO y MailHog se aprovisionan en el entorno y se verifican contra el propio entorno (schemas, topics, bucket, SMTP), no contra los servicios.

*Por qué:* así el esqueleto se puede validar sin inventar modelos de dominio y cada servicio añade su persistencia, con sus migraciones, en el change que la necesita. *Consecuencia:* el gate de cobertura se ejercita en `libs/common-observability` (código real) y en los tests de los servicios, no en capas de datos todavía inexistentes.

### D13. Frontend: Vite + TypeScript estricto y fail-fast de configuración

Vite con `react-ts`, `strict: true` en `tsconfig.json`, ESLint 9 con configuración plana y `typescript-eslint`, Vitest + Testing Library con cobertura. La URL del API se valida en `vite.config.ts` (de modo que `npm run build` falla si `VITE_API_BASE_URL` no está definida) y se consume en `src/config/env.ts` como única fuente. El arranque monta `createBrowserRouter` (React Router v7) y un `QueryClientProvider` (TanStack Query) sobre un layout con estado vacío explícito.

*Por qué validar en `vite.config.ts`:* es el único punto que se ejecuta tanto en `dev` como en `build`, así que el fallo aparece antes de empaquetar y no en tiempo de ejecución en el navegador. *Alternativa:* fallar solo en `src/config/env.ts`; se descarta porque `npm run build` terminaría con código 0 generando un bundle inservible.

### D14. Observabilidad siempre activa, no un perfil opt-in

`docker-compose.obs.yml` levanta Prometheus, Grafana y Kafka UI **sin `profiles:`**, y `.env.example` declara `COMPOSE_FILE` con los tres ficheros (base, dev y obs). Así el comando canónico `docker compose up --wait` desde la raíz levanta el entorno completo, observabilidad incluida.

*Verificado empíricamente en esta máquina* (Docker 29.9.3 / Compose v5.7.1): con `COMPOSE_FILE=ops/compose/docker-compose.base.yml:ops/compose/docker-compose.obs.yml` en `.env`, `docker compose config --services` desde la raíz lista los servicios de ambos ficheros, resolviendo las rutas relativas correctamente. No es una suposición sobre el comportamiento de Compose.

*Por qué siempre activa:* en un entorno real la recolección de métricas no es opcional —si los objetivos no se scrapean desde el primer minuto, no hay histórico cuando aparece el problema— y el objetivo educativo del proyecto es precisamente ver esa instrumentación funcionando. Un perfil desactivado por defecto acaba no arrancándose nunca.

*Trade-off asumido:* Prometheus, Grafana y Kafka UI consumen RAM y CPU en local. Se mitiga con límites de recursos en Compose y con una vía de escape documentada: quitar el fichero de observabilidad de `COMPOSE_FILE` (o pasar `-f` explícitos) arranca el resto del entorno sin ella. *Alternativas descartadas:* `profiles: [obs]` (oculta por defecto lo que el proyecto quiere enseñar) e integrar el stack directamente en `docker-compose.base.yml` (rompe la separación por capas que fija PROJECT.md §9 y obliga a editar el fichero base para cambiar de escenario).

**Alcance:** en este change la pila se limita a Prometheus, Grafana y Kafka UI. Loki y Tempo exigirían instrumentación de trazas (exportador OTLP, colector) sin tráfico real que analizar; incluirlos ahora daría contenedores decorativos. PROJECT.md §3 y §9 se actualizan para reflejar el reparto.


### D15. Documentación como parte del entregable

Al aplicar el change se actualizan `PROJECT.md` §3 (alcance real de la pila de observabilidad), §4 (versiones verificadas), §6 (nuevos `config/`, `scripts/`, `.env.example` y `.mvn/`) y §9 (`COMPOSE_FILE` y arranque por defecto con observabilidad), y `README.md` (estado del proyecto y comandos ya ejecutados). Sin esta actualización, la fuente de verdad quedaría desalineada con el repositorio en el mismo commit que lo crea.

### D16. Documentación OpenAPI con springdoc-openapi 2.x

Cada servicio añade `springdoc-openapi-starter-webmvc-ui`, que expone la especificación generada desde el código en `/v3/api-docs` (y `/v3/api-docs.yaml`) y Swagger UI en `/swagger-ui.html`, sin configuración adicional. El título y la versión del documento se alimentan del nombre y la versión del módulo, para que la documentación identifique el servicio que la publica.

**Compatibilidad verificada**, no supuesta: la tabla oficial del repositorio de springdoc indica Spring Boot 4.x → springdoc **3.x** y Spring Boot 3.x → springdoc **2.x**; en Maven Central (`repo1.maven.org/maven2/org/springdoc/springdoc-openapi-starter-webmvc-ui/maven-metadata.xml`) la última publicada de la línea 2.x es **2.10.0** (existe ya la 3.2.0, que **no** aplica aquí porque exige Spring Boot 4). La versión exacta se confirma junto al resto en la tarea 1.2.

Desactivación: `springdoc.api-docs.enabled` y `springdoc.swagger-ui.enabled` se alimentan de una única variable de entorno `APP_DOCS_ENABLED` (por defecto `true`), de modo que apagar la documentación no exige tocar código ni la imagen.

*Trade-offs:* publicar el contrato revela la superficie de la API, así que en un entorno real se desactivaría o se protegería en el gateway; aquí se mantiene activo porque el proyecto es didáctico y consultar Swagger es parte del aprendizaje. *Alternativa considerada:* agregar las especificaciones de todos los servicios en el `api-gateway`; se pospone porque añade configuración de springdoc en el gateway antes de que existan endpoints reales que agregar.

### D17. La carpeta de operación se llama `ops/`, no `infra/`

Los Dockerfiles, los ficheros de Compose y el pipeline de Jenkins viven bajo **`ops/`** (`ops/docker`, `ops/compose`, `ops/jenkins`). `infra/` se descarta por decisión del usuario, y también por precisión: en la mayoría de repos `infra/` se asocia a infraestructura como código (Terraform, CloudFormation, manifiestos de Kubernetes) y aquí no hay nada de eso — son artefactos de operación del proyecto en local y en CI.

*Alternativas evaluadas:* `platform/` (sugiere un equipo o una plataforma interna, demasiado grandilocuente para un proyecto personal), `deploy/` (sugiere despliegue, pero la carpeta también contiene la definición de imágenes y el entorno local), `devops/` (más largo y menos concreto) y `docker/` (no cubriría `jenkins/`). El cambio afecta a `PROJECT.md` §6 y §9, `README.md`, `.gitignore` y a los artefactos de este change; se hace ahora, antes de que exista ningún fichero con esa ruta, para no arrastrar un renombrado con historial detrás.

## Risks / Trade-offs

- **Deriva de versiones** (Spring Boot, imágenes base, Kafka) → se fija cada versión en una única property tras verificarla contra Maven Central y el registro de imágenes (tarea 1.2); ninguna versión se escribe por memoria.
- **Ratio de cobertura no computable en módulos sin clases analizables** → comportamiento verificado empíricamente en la tarea 2.3 y resuelto con exclusión explícita del módulo o `jacoco.skip`, documentando la decisión; el gate se demuestra rompiéndolo con un test de baja cobertura.
- **Healthcheck de Kafka KRaft frágil** (el broker tarda en elegir líder) → `start_period` amplio, comprobación con `kafka-topics --list` en lugar de un `nc` al puerto, y sin reintentos infinitos: si no está sano, `up --wait` falla y el fallo es visible.
- **El aislamiento de redes no es un cortafuegos** → asumido y documentado; se mitiga de verdad con NetworkPolicies al migrar a Kubernetes.
- **Testcontainers descarga imágenes pesadas en cada ejecución limpia** → reutilización local opcional documentada; la CI siempre parte de estado limpio para no ocultar dependencias del entorno.
- **`npm ci` ignora `engines` por defecto** → `.npmrc` con `engine-strict=true`, que es lo que convierte el requisito de Node ≥ 22.12.0 en un fallo real de instalación.
- **`frontend-net` interna rompería el `npm install` en contenedor** → el frontend no instala dependencias dentro de Compose: la imagen se construye en la fase de build y el servidor de desarrollo solo resuelve el `api-gateway`.

## Migration Plan

No hay migración de datos ni compatibilidad que preservar: el repositorio no tiene commits previos ni código desplegado.

1. Crear la rama `feat/project-skeleton-bootstrap` desde `main`.
2. Aplicar las tareas de `tasks.md` en orden; cada grupo deja su verificación en verde antes de pasar al siguiente.
3. Verificar la suite completa (backend, frontend y scripts de infraestructura) y actualizar la documentación.
4. **Rollback**: revertir el commit o abandonar la rama; al no existir versiones anteriores ni datos productivos, no se requiere plan de vuelta atrás adicional.

## Open Questions

- **Versión exacta de Spring Boot 3.x, de las imágenes base y de Kafka 4.x**: se resuelve en la tarea 1.2 contra los repositorios oficiales. No cambia specs, enfoque ni desglose de tareas, así que puede cerrarse durante la aplicación.
- **Remitente por defecto de MailHog** (`MAIL_FROM`): se elige un placeholder en `.env.example`; no afecta a ningún requisito de este change.



