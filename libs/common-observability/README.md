# common-observability

Librería interna con el comportamiento operativo común de todos los servicios de Domincipe. No
contiene lógica de negocio: el módulo que la declara como dependencia hereda la correlación de
peticiones, la exposición de Actuator y los valores por defecto de operación que fijan
[PROJECT.md §4 y §9](../../PROJECT.md).

## Dependencia

La versión la gestiona `domincipe-parent` en su `dependencyManagement`, así que el servicio declara
el artefacto sin `<version>`:

```xml
<dependency>
    <groupId>com.domincipe</groupId>
    <artifactId>common-observability</artifactId>
</dependency>
```

El consumidor tiene que ser una aplicación web Spring Boot: la librería arrastra
`spring-boot-starter-webmvc` (el filtro necesita el API de servlet) y
`spring-boot-starter-actuator`. La auto-configuración se registra en
`META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`, de modo que no
hay que importar ni escanear ningún paquete desde el servicio.

## Variables de entorno

### Obligatoria

| Variable | Valores admitidos | Efecto |
|---|---|---|
| `APP_ENVIRONMENT` | `local`, `dev`, `obs` (sin distinguir mayúsculas; se recortan los espacios) | Se enlaza a `app.environment`. Si falta, está en blanco o no es válida, el arranque falla con un mensaje que nombra la variable y enumera los valores admitidos. No tiene valor por defecto. |

### Valores por defecto que el servicio puede sobrescribir

Se declaran en `observability-defaults.properties` con la precedencia más baja (`@PropertySource`),
así que `application.yml`, un perfil o una variable de entorno del servicio siempre ganan:

| Propiedad | Variable de entorno | Valor por defecto |
|---|---|---|
| `management.endpoints.web.exposure.include` | `MANAGEMENT_ENDPOINTS_WEB_EXPOSURE_INCLUDE` | `health,prometheus` |
| `management.endpoint.health.probes.enabled` | `MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED` | `true` |
| `spring.threads.virtual.enabled` | `SPRING_THREADS_VIRTUAL_ENABLED` | `true` |
| `server.shutdown` | `SERVER_SHUTDOWN` | `graceful` |
| `spring.lifecycle.timeout-per-shutdown-phase` | `SPRING_LIFECYCLE_TIMEOUTPERSHUTDOWNPHASE` | `30s` |
| `springdoc.api-docs.enabled` | `APP_DOCS_ENABLED` | `true` |
| `springdoc.swagger-ui.enabled` | `APP_DOCS_ENABLED` | `true` |

## Comportamiento en tiempo de ejecución

- **Salud y métricas**: `GET /actuator/health` (con los grupos `liveness` y `readiness`) y
  `GET /actuator/prometheus`.
- **Correlación de peticiones**: cada respuesta incluye `X-Request-Id`, reutilizando el valor
  recibido o generando un UUID cuando falta o viene en blanco. El identificador se publica en el MDC
  bajo la clave `requestId`, por lo que el patrón de log del servicio debe incluir `%X{requestId}`
  para imprimirlo. El filtro retrocede (`@ConditionalOnMissingBean`) si el servicio declara el suyo.
- **Apagado ordenado**: `server.shutdown=graceful` y una ventana de drenaje de 30 s, sobrescribibles
  con las variables de la tabla anterior.
- **Documentación OpenAPI**: con `springdoc-openapi-starter-webmvc-ui` en el servicio, el contrato
  generado se publica en `/v3/api-docs` y la interfaz interactiva en `/swagger-ui.html`. El título
  del documento es `spring.application.name` y su versión, `spring.application.version` (el POM la
  filtra a `src/main/resources/application*.yml` con `@project.version@`). `APP_DOCS_ENABLED=false`
  apaga ambos endpoints sin tocar código.

## Arranque

Con el módulo del servicio en el reactor, basta con aportar la variable obligatoria (ejemplo con el
`api-gateway`; sirve cualquier módulo que declare la dependencia):

```bash
APP_ENVIRONMENT=local ./mvnw -pl apps/api-gateway spring-boot:run
```

Sin `APP_ENVIRONMENT` el arranque termina con error y el mensaje nombra la variable; con
`APP_ENVIRONMENT=produccion`, el mensaje enumera `local`, `dev` y `obs`.
