# Spec Delta

## Purpose

Define el entorno local en Docker con comportamiento cloud-like: un arranque único que solo se declara listo cuando todas las dependencias están sanas, aislamiento de redes, aprovisionamiento idempotente de datos, imágenes no-root con límites de recursos y observabilidad siempre activa.

## ADDED Requirements

### Requirement: Arranque condicionado a la salud de las dependencias

El entorno SHALL levantarse con un único comando que espere a que todos los servicios estén sanos y falle con código distinto de 0 si alguno no alcanza el estado saludable dentro de un tiempo límite; ningún servicio SHALL arrancar por espera fija (`sleep`).

#### Scenario: Arranque en frío

- **WHEN** se ejecuta `docker compose up --wait` en la raíz del repositorio sobre un entorno sin contenedores previos (los ficheros de Compose se resuelven desde `COMPOSE_FILE` declarado en `.env`)
- **THEN** el comando termina con código 0 y todos los contenedores aparecen con estado `healthy`

#### Scenario: Dependencia no saludable

- **WHEN** un servicio del que dependen otros contenedores no alcanza el estado saludable dentro del tiempo límite
- **THEN** ninguno de los contenedores dependientes arranca y el comando `up --wait` termina con código distinto de 0

### Requirement: Aislamiento de redes

El entorno SHALL separar el tráfico en las redes `frontend-net`, `backend-net` y `obs-net`, de modo que el frontend solo alcance el `api-gateway` y las bases de datos, la mensajería y el almacenamiento de objetos solo sean accesibles desde `backend-net`.

#### Scenario: Base de datos inalcanzable desde el frontend

- **WHEN** se ejecuta `docker compose exec web-frontend getent hosts postgres`
- **THEN** la resolución de nombres falla con código distinto de 0

#### Scenario: Base de datos alcanzable desde un servicio

- **WHEN** se ejecuta `docker compose exec api-gateway getent hosts postgres`
- **THEN** la resolución devuelve la dirección del contenedor de PostgreSQL

### Requirement: Aprovisionamiento idempotente de datos

El entorno SHALL crear, sin intervención manual y de forma repetible, un schema de PostgreSQL 16 por servicio (`auth`, `users`, `recipes`, `media`, `notifications`), los topics de Kafka 4.x definidos en el contrato de eventos, el bucket de MinIO y el buzón SMTP de MailHog.

#### Scenario: Schemas creados

- **WHEN** se consulta `\dn` en PostgreSQL con `docker compose exec postgres psql -c '\dn'`
- **THEN** aparecen los cinco schemas de servicio

#### Scenario: Topics creados

- **WHEN** se listan los topics del broker con `kafka-topics --bootstrap-server kafka:9092 --list`
- **THEN** aparecen `user.registered`, `user.updated`, `recipe.created`, `recipe.updated`, `recipe.deleted` y `media.uploaded`

#### Scenario: Reinicio sin duplicados

- **WHEN** se detiene y se vuelve a levantar el entorno
- **THEN** el arranque termina correctamente y no se producen errores por objetos ya existentes

### Requirement: Imágenes inmutables y no privilegiadas

Las imágenes de la aplicación SHALL construirse en varias etapas, ejecutarse con un usuario distinto de root y publicarse con un tag inmutable basado en el SHA de git además de `latest`; cada servicio SHALL declarar límites de CPU y memoria.

#### Scenario: Contenedor sin privilegios

- **WHEN** se inspecciona un contenedor de la aplicación con `docker inspect`
- **THEN** su campo de usuario no está vacío ni es `root`

#### Scenario: Tag inmutable disponible

- **WHEN** se listan las imágenes construidas en una ejecución del build
- **THEN** existe una etiqueta equivalente al SHA de git del commit con el que se construyó, además de `latest`

#### Scenario: Límites declarados

- **WHEN** se inspecciona la configuración de Compose de cualquier servicio
- **THEN** declara límites explícitos de CPU y de memoria

### Requirement: Apagado ordenado en el entorno local

El entorno SHALL conceder a cada servicio un periodo de gracia configurable de al menos 30 segundos antes de forzar su terminación, de modo que las peticiones en curso se completen y el contenedor termine con código 0.

#### Scenario: Parada con tráfico en curso

- **WHEN** se ejecuta `docker compose stop` mientras un servicio atiende una petición
- **THEN** la petición finaliza con su respuesta esperada y el contenedor registra código de salida 0

### Requirement: Observabilidad siempre activa

El entorno SHALL levantar siempre la pila de observabilidad —Prometheus, Grafana y Kafka UI— junto con el resto de servicios, de modo que un único comando deje el entorno completo operativo, incluida la recolección de métricas de todos los servicios.

#### Scenario: Arranque con observabilidad incluida

- **WHEN** se ejecuta `docker compose up --wait` en la raíz del repositorio, sin argumentos adicionales
- **THEN** los contenedores de Prometheus, Grafana y Kafka UI quedan en estado `healthy` junto a los demás

#### Scenario: Recolección de métricas

- **WHEN** se consulta `GET /api/v1/targets` de Prometheus tras el arranque
- **THEN** todos los objetivos de los servicios aparecen con estado `up`

#### Scenario: Desactivación documentada

- **WHEN** se arranca el entorno excluyendo el fichero de observabilidad de la lista de ficheros de Compose
- **THEN** no se crean contenedores de Prometheus, Grafana ni Kafka UI y el resto del entorno arranca con normalidad
