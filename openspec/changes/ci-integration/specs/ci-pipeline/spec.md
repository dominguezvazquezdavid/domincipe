# Spec Delta

## MODIFIED Requirements

### Requirement: Suite de verificación bloqueante en cada PR

El pipeline SHALL ejecutar en cada PR la suite de calidad (backend con `./mvnw -B -ntp verify` —lint, unit, slice y gate de cobertura—, frontend con `npm ci`, `npm run lint`, `npm run build` y `npm test`), la suite de integration (Testcontainers), el e2e y la batería de entorno, y SHALL terminar en fallo si cualquiera de ellas falla. La ejecución MUST NOT omitir tests ni rebajar los umbrales de cobertura: que un nivel corra en una etapa propia no lo saca del gate.

#### Scenario: Test rojo rompe el build

- **WHEN** un test del backend falla en un PR
- **THEN** el build termina en fallo y el log identifica el módulo y el test que falló

#### Scenario: Cobertura por debajo del umbral

- **WHEN** la cobertura de líneas de un módulo queda por debajo del umbral del proyecto
- **THEN** la etapa termina en fallo nombrando el módulo y la métrica incumplida

#### Scenario: Lint del frontend bloqueante

- **WHEN** `npm run lint` del frontend devuelve errores en un PR
- **THEN** el build termina en fallo sin llegar a las etapas de construcción de imágenes

#### Scenario: Sin omisión dentro de la suite de PR

- **WHEN** se inspecciona la invocación de Maven registrada en el log del build
- **THEN** no contiene opciones que omitan la ejecución de tests ni exclusiones de módulos

#### Scenario: Test que exige Docker

- **WHEN** el árbol contiene un `*IT.java` que necesita un daemon Docker
- **THEN** el test se ejecuta contra el daemon de test dentro del mismo build y su resultado decide el del build

### Requirement: Trazabilidad del build

Cada build SHALL archivar sus informes —cobertura, resultados de unit y slice, resultados de integration, e2e, SBOM y hallazgos de seguridad— con una retención declarada, de modo que un fallo se pueda diagnosticar después de ocurrir y un build antiguo se pueda auditar. Las trazas del e2e y los logs de sus contenedores SHALL conservarse cuando el build falla.

#### Scenario: Informes archivados

- **WHEN** termina un build, tanto correcto como fallido
- **THEN** el build expone los informes de cobertura, de unit y slice, de integration, de e2e, los SBOM y el resultado del escaneo

#### Scenario: Retención declarada

- **WHEN** se inspecciona la configuración del job
- **THEN** declara cuántos builds se conservan y qué artefactos archiva cada uno

#### Scenario: Fallo del e2e con evidencia

- **WHEN** el smoke de e2e falla en un build
- **THEN** el build conserva la traza de Playwright y los logs de los contenedores del entorno e2e que lo produjeron

## ADDED Requirements

### Requirement: Daemon Docker de test aislado del host

El stack de CI SHALL disponer de un daemon Docker propio, alcanzable solo desde la red del stack y sin puertos publicados al host, y ese daemon MUST NOT ser el del entorno de desarrollo: ningún contenedor del stack monta su socket. El daemon de test SHALL ser el único contenedor con privilegios del stack, y la construcción de imágenes MUST seguir sin depender de él.

#### Scenario: Socket del desarrollo ausente

- **WHEN** se inspeccionan los contenedores del stack de CI
- **THEN** ninguno monta `/var/run/docker.sock`

#### Scenario: Sin puertos publicados

- **WHEN** se inspecciona la configuración del daemon de test
- **THEN** no publica ningún puerto del host y solo es alcanzable desde la red del stack

#### Scenario: Privilegio acotado

- **WHEN** se listan los contenedores del stack que se ejecutan con privilegios
- **THEN** solo aparece el daemon de test, y las imágenes siguen construyéndose contra el builder sin daemon

### Requirement: Integration ejecutada en cada PR

El pipeline SHALL ejecutar los `*IT.java` presentes en el árbol contra el daemon de test en cada PR, con `maven-failsafe-plugin`, y SHALL terminar en fallo si alguno falla. El resultado SHALL nombrar el módulo y el test responsable.

#### Scenario: Integration en verde

- **WHEN** los `*IT.java` del árbol pasan contra el daemon de test
- **THEN** el build continúa con las etapas siguientes

#### Scenario: Integration en rojo

- **WHEN** un `*IT.java` falla
- **THEN** el build termina en fallo y el log nombra el módulo, la clase y el test

#### Scenario: Daemon no disponible

- **WHEN** el daemon de test no responde al arrancar la etapa
- **THEN** el build falla de inmediato nombrando la causa y no espera un tiempo de expiración de Testcontainers

### Requirement: E2E de backend y frontend en cada PR

El pipeline SHALL ejecutar el e2e de backend con Testcontainers y RestAssured y el smoke de frontend con Playwright contra un proyecto Compose propio del stack, sin publicar puertos al host, y SHALL terminar en fallo si alguno falla. Las aserciones del smoke SHALL cubrir invariantes del sistema: entorno sano, SPA servida, deep link resuelto, salud del gateway a través del proxy, `X-Request-Id` en la respuesta y consola del navegador sin errores.

#### Scenario: Smoke en verde

- **WHEN** se abre la aplicación servida por el proyecto Compose del stack
- **THEN** la página carga con su punto de montaje, el gateway responde sano por su nombre de servicio y la respuesta lleva `X-Request-Id`

#### Scenario: Deep link de la SPA

- **WHEN** se solicita una ruta interna de la aplicación que no corresponde a un fichero
- **THEN** el servidor devuelve la página de la SPA en lugar de un error de recurso no encontrado

#### Scenario: E2E en rojo

- **WHEN** una aserción del e2e de backend o del smoke falla
- **THEN** el build termina en fallo y archiva la traza y los logs correspondientes

#### Scenario: Reintento único del e2e

- **WHEN** el e2e falla por una causa inestable
- **THEN** se reintenta una sola vez y solo ese nivel se reintenta; unit e integration no se reintentan


### Requirement: Batería de entorno en cada PR

El pipeline SHALL arrancar el entorno desde cero con `docker compose up --wait` sobre el daemon de test, ejecutar `scripts/verify-environment.sh` y `scripts/verify-shutdown.sh`, y SHALL terminar en fallo si cualquiera de ellos falla.

#### Scenario: Entorno certificado en el gate

- **WHEN** el build llega a la etapa de entorno
- **THEN** los contenedores quedan sanos, los cinco schemas, los seis topics, el bucket y el buzón quedan verificados, y el apagado ordenado termina con código 0 o 143

#### Scenario: Entorno en rojo

- **WHEN** una de las comprobaciones de la batería de entorno falla
- **THEN** el build termina en fallo nombrando la comprobación y el contenedor responsable

### Requirement: Cobertura del gate sin la suite con Docker

El gate de cobertura SHALL seguir midiendo la cobertura de unit y slice con los umbrales por módulo, y MUST NOT computar la cobertura producida por integration ni por e2e.

#### Scenario: Módulo sin tests unitarios

- **WHEN** un módulo tiene tests de integration y ninguno de unit
- **THEN** el gate sigue exigiendo los umbrales sobre la cobertura de unit y slice y el módulo no los supera por la cobertura de integration

#### Scenario: Informe de integration separado

- **WHEN** termina la etapa de integration
- **THEN** su informe de cobertura se archiva por separado y no altera el resultado del gate

