# Spec Delta

## Purpose

Define el comportamiento común de arranque y operación de los servicios Java: exposición de salud y métricas, configuración exclusiva por variables de entorno con fallo temprano, apagado ordenado y correlación de peticiones.

## ADDED Requirements

### Requirement: Endpoints de salud

Cada servicio SHALL exponer `/actuator/health` y los grupos `liveness` y `readiness`, devolviendo HTTP 200 con estado `UP` cuando el servicio está operativo, sin requerir autenticación.

#### Scenario: Servicio operativo

- **WHEN** se solicita `GET /actuator/health` a un servicio recién arrancado
- **THEN** la respuesta es HTTP 200 con cuerpo JSON cuyo campo `status` es `UP`

#### Scenario: Sondas de liveness y readiness

- **WHEN** se solicitan `GET /actuator/health/liveness` y `GET /actuator/health/readiness`
- **THEN** ambas responden HTTP 200 con `status` igual a `UP`

### Requirement: Métricas para scraping

Cada servicio SHALL exponer `/actuator/prometheus` en formato de texto de Prometheus, incluyendo al menos las métricas de JVM y de peticiones HTTP del servicio.

#### Scenario: Scraping correcto

- **WHEN** se solicita `GET /actuator/prometheus`
- **THEN** la respuesta es HTTP 200 y contiene al menos una métrica de JVM y una de peticiones HTTP

### Requirement: Configuración por entorno y fallo temprano

Toda configuración SHALL resolverse desde variables de entorno; una variable obligatoria ausente o con valor no válido SHALL impedir el arranque con un mensaje que la nombre, en lugar de arrancar con un valor por defecto silencioso.

#### Scenario: Variable obligatoria ausente

- **WHEN** se arranca un servicio sin la variable obligatoria `APP_ENVIRONMENT`
- **THEN** el proceso termina con código de salida distinto de 0 y el log nombra `APP_ENVIRONMENT`

#### Scenario: Valor no válido

- **WHEN** se arranca un servicio con `APP_ENVIRONMENT=produccion`
- **THEN** el arranque falla indicando los valores admitidos (`local`, `dev`, `obs`)

### Requirement: Apagado ordenado

Cada servicio SHALL apagarse de forma ordenada: al recibir `SIGTERM` deja de aceptar peticiones nuevas, completa las que están en curso dentro de un tiempo configurable por entorno y termina con código 0.

#### Scenario: Petición en curso durante el apagado

- **WHEN** se envía `SIGTERM` a un servicio mientras atiende una petición
- **THEN** la petición en curso finaliza con la respuesta esperada y el proceso termina con código 0

#### Scenario: Tiempo de apagado configurable

- **WHEN** se define la variable de entorno que fija el tiempo máximo de apagado
- **THEN** el servicio respeta ese valor en lugar de un valor fijo embebido en la imagen

### Requirement: Documentación OpenAPI publicada

Cada servicio SHALL publicar su contrato OpenAPI 3 generado desde el código, con la especificación en `/v3/api-docs` y la interfaz interactiva en `/swagger-ui.html`, incluyendo título y versión del servicio. La exposición SHALL poder desactivarse con una única variable de entorno, sin cambios de código.

#### Scenario: Especificación disponible

- **WHEN** se solicita `GET /v3/api-docs` a un servicio arrancado
- **THEN** la respuesta es HTTP 200 con un documento JSON que declara `openapi` en versión 3.x y con `info.title` e `info.version` no vacíos

#### Scenario: Interfaz interactiva disponible

- **WHEN** se solicita `GET /swagger-ui.html` a un servicio arrancado
- **THEN** la respuesta termina en `/swagger-ui/index.html` con HTTP 200 y contenido HTML

#### Scenario: Endpoint nuevo documentado sin configuración extra

- **WHEN** se añade un controlador con una ruta nueva al servicio
- **THEN** el documento de `/v3/api-docs` incluye esa ruta sin necesidad de configuración adicional

#### Scenario: Documentación desactivada

- **WHEN** se arranca el servicio con la variable de entorno de desactivación de la documentación
- **THEN** `/v3/api-docs` y `/swagger-ui.html` responden 404 y el resto de endpoints operativos siguen funcionando

### Requirement: Correlación de peticiones

Cada respuesta de los servicios SHALL incluir la cabecera `X-Request-Id`, reutilizando el valor recibido del cliente o generándolo cuando esté ausente, y el log SHALL registrar ese identificador en las trazas de la petición.

#### Scenario: Identificador propagado

- **WHEN** se envía una petición con `X-Request-Id: 7d1f-abc`
- **THEN** la respuesta incluye `X-Request-Id: 7d1f-abc` y el log de la petición contiene ese mismo valor

#### Scenario: Identificador generado

- **WHEN** se envía una petición sin `X-Request-Id`
- **THEN** la respuesta incluye un `X-Request-Id` no vacío distinto en cada petición
