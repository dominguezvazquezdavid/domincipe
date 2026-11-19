# Spec Delta

## Purpose

Define el contrato de la integración continua local: un Jenkins reproducible que ejecuta la **suite de verificación** (backend y frontend, sin los niveles que exigen Docker) como gate bloqueante, construye imágenes sin daemon de build, inventaría su contenido con SBOM, escanea vulnerabilidades con umbral y publica el resultado en el PR. Los niveles **integration** y **e2e** de [PROJECT.md](../../../../../PROJECT.md) §8 pertenecen a la batería de release y su entrada en CI exige un change propio (design D13).

## ADDED Requirements

### Requirement: Pipeline reproducible en frío

El stack de integración continua SHALL levantarse desde el repositorio con un único comando y SHALL quedar operativo sin intervención manual en la interfaz: plugins, jobs y credenciales se declaran en ficheros versionados. Un arranque desde cero y otro tras borrar los volúmenes SHALL producir el mismo conjunto de jobs y la misma configuración del controlador.

#### Scenario: Arranque en frío del stack

- **WHEN** se ejecuta `docker compose -f ops/jenkins/docker-compose.yml up --wait` sobre un clon sin `.env` en `ops/jenkins/` y sin volúmenes previos
- **THEN** el comando termina con código 0, los contenedores quedan en estado `healthy` y `GET /login` del controlador responde HTTP 200

#### Scenario: Jobs sin configuración manual

- **WHEN** se consultan los jobs del controlador inmediatamente después de un arranque en frío
- **THEN** existen los jobs del repositorio, creados desde la configuración versionada, sin ningún paso manual en la interfaz

#### Scenario: Reproducibilidad tras borrar el estado

- **WHEN** se eliminan los volúmenes del stack y se repite el arranque
- **THEN** el conjunto de jobs y la versión de cada plugin coinciden con los del arranque anterior

### Requirement: Suite de verificación bloqueante en cada PR

El pipeline SHALL ejecutar en cada PR el build del backend con `./mvnw -B -ntp verify` —lint, tests y gate de cobertura— y la cadena del frontend con `npm ci`, `npm run lint`, `npm run build` y `npm test`, y SHALL terminar en fallo si cualquiera de ellos falla. La ejecución MUST NOT omitir tests ni rebajar los umbrales de cobertura. El alcance excluye los niveles integration y e2e de [PROJECT.md](../../../../../PROJECT.md) §8, que corren en la batería de release (design D13).

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
- **THEN** el build termina en fallo nombrando el fichero y la acción a tomar (abrir el change `ci-integration`), sin llegar a ejecutar Testcontainers

### Requirement: Construcción de imágenes sin daemon de build

Las siete imágenes del monorepo SHALL construirse contra un daemon de build que no ejecuta como root, y el contenedor que lanza el build MUST NOT recibir el socket de Docker: la única vía de acceso al builder SHALL ser su API. Cada imagen SHALL llevar dos **referencias** dentro del archivo OCI —`<imagen>:<sha>` y `<imagen>:latest`— que resuelvan al mismo contenido.

#### Scenario: Build sin socket de Docker

- **WHEN** se inspecciona el contenedor que ejecuta el pipeline
- **THEN** no tiene montado el socket de Docker y la etapa de imágenes termina con código 0

#### Scenario: Builder sin privilegios de root

- **WHEN** se inspecciona el contenedor del daemon de build
- **THEN** su usuario no es `root` y su UID es distinto de 0

#### Scenario: Referencias coherentes

- **WHEN** termina la etapa de construcción de imágenes
- **THEN** cada imagen tiene una referencia con el SHA corto del commit y otra `latest`, y ambas resuelven al mismo identificador de imagen

### Requirement: SBOM por imagen

El pipeline SHALL generar un SBOM en formato CycloneDX por cada imagen construida y SHALL archivarlo como artefacto del build, identificando la imagen y el commit que lo originaron.

#### Scenario: SBOM disponible por imagen

- **WHEN** termina un build correcto de las siete imágenes
- **THEN** hay siete SBOM archivados, uno por imagen, cada uno con su nombre de imagen y al menos un componente inventariado

#### Scenario: SBOM del build fallido

- **WHEN** una etapa posterior al SBOM falla
- **THEN** los SBOM ya generados siguen archivados en el build fallido

### Requirement: Gate de vulnerabilidades

Cada imagen SHALL escanearse en busca de vulnerabilidades y el build SHALL fallar si aparece al menos una de severidad HIGH o CRITICAL. El umbral SHALL ser HIGH y CRITICAL: relajarlo MUST exigir un cambio en esta spec, no un parámetro del pipeline.

#### Scenario: Vulnerabilidad alta rompe el build

- **WHEN** una imagen contiene al menos una vulnerabilidad de severidad HIGH o CRITICAL
- **THEN** la etapa termina en fallo y el informe nombra la imagen, el identificador de la vulnerabilidad y el paquete afectado

#### Scenario: Solo severidad inferior

- **WHEN** las únicas vulnerabilidades detectadas son de severidad MEDIUM o inferior
- **THEN** la etapa termina con código 0 y el build continúa

#### Scenario: Excepción versionada

- **WHEN** una vulnerabilidad figura en el fichero de excepciones versionado con su justificación
- **THEN** el build no falla por ella y deja constancia de la excepción aplicada

### Requirement: Estado publicado en el PR

El pipeline SHALL publicar el resultado de cada build como estado del commit en el repositorio remoto, y la rama de destino SHALL poder exigir ese estado para integrar. Un build fallido SHALL dejar el commit en estado de fallo.

#### Scenario: Estado correcto publicado

- **WHEN** el build de un PR termina correctamente
- **THEN** el commit muestra el estado de éxito publicado por el pipeline

#### Scenario: Merge bloqueado con build rojo

- **WHEN** el PR tiene el estado del pipeline en fallo
- **THEN** la rama de destino rechaza el merge hasta que exista un build correcto

#### Scenario: El escaneo detecta el PR

- **WHEN** se abre o se actualiza un PR contra la rama de integración
- **THEN** el siguiente escaneo de la rama (≤ 5 minutos) lanza un build de ese commit sin intervención manual

### Requirement: Credenciales fuera del repositorio y del log

Las credenciales que usa el pipeline SHALL residir en el almacén de credenciales del servidor de CI y SHALL referenciarse por identificador. El repositorio y el log del build MUST NOT contener ningún valor secreto.

#### Scenario: Sin secretos versionados

- **WHEN** se busca en `ops/jenkins/` un token, una contraseña o una clave privada literal
- **THEN** no hay coincidencias fuera de marcadores de referencia a credenciales

#### Scenario: Secreto enmascarado en el log

- **WHEN** una etapa usa una credencial del almacén
- **THEN** el log muestra el valor enmascarado y el comando ejecutado no imprime el secreto

### Requirement: Trazabilidad del build

Cada build SHALL archivar sus informes —cobertura, resultados de tests, SBOM y hallazgos de seguridad— con una retención declarada, de modo que un fallo se pueda diagnosticar después de ocurrir y un build antiguo se pueda auditar.

#### Scenario: Informes archivados

- **WHEN** termina un build, tanto correcto como fallido
- **THEN** el build expone los informes de cobertura, de tests, los SBOM y el resultado del escaneo

#### Scenario: Retención declarada

- **WHEN** se inspecciona la configuración del job
- **THEN** declara cuántos builds se conservan y qué artefactos archiva cada uno
