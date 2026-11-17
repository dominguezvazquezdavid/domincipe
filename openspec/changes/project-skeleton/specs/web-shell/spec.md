# Spec Delta

## Purpose

Define el comportamiento del shell del frontend: build y lint reproducibles, configuración del API por entorno con fallo temprano y arranque de la SPA con sus proveedores de rutas y de datos.

## ADDED Requirements

### Requirement: Build, lint y test reproducibles

El frontend SHALL instalarse, analizarse y compilarse con comandos reproducibles desde `apps/web-frontend`, y el build SHALL producir un bundle estático servible en `dist/`.

#### Scenario: Cadena completa en verde

- **WHEN** se ejecutan `npm ci`, `npm run lint`, `npm run build` y `npm test`
- **THEN** los cuatro comandos terminan con código 0

#### Scenario: Bundle generado

- **WHEN** finaliza `npm run build`
- **THEN** existe `dist/index.html` y al menos un fichero JavaScript con hash en su nombre

#### Scenario: Lint bloqueante

- **WHEN** se introduce una variable declarada y no usada en un fichero `.ts`
- **THEN** `npm run lint` termina con código distinto de 0 e identifica el fichero infractor

### Requirement: Endpoint del API por entorno

El frontend SHALL obtener la URL base del API exclusivamente de la variable de entorno `VITE_API_BASE_URL`; no SHALL contener hosts del backend codificados en el código y el build SHALL fallar si la variable no está definida.

#### Scenario: URL configurada

- **WHEN** se compila con `VITE_API_BASE_URL=http://localhost:8080`
- **THEN** las peticiones del cliente de datos se dirigen a `http://localhost:8080`

#### Scenario: Variable ausente

- **WHEN** se compila sin definir `VITE_API_BASE_URL`
- **THEN** el build falla con un mensaje que nombra la variable

#### Scenario: Sin hosts embebidos

- **WHEN** se busca en `src/` el patrón de un host del backend codificado
- **THEN** no hay coincidencias fuera de la configuración leída del entorno

### Requirement: Arranque de la SPA con sus proveedores

La aplicación SHALL arrancar con el enrutador de React Router v8 y el cliente de datos de TanStack Query inicializados, mostrando una ruta inicial con un estado vacío explícito y sin errores en consola.

#### Scenario: Renderizado inicial

- **WHEN** se renderiza el componente raíz con React Testing Library
- **THEN** se muestra el título `Domincipe` y el estado vacío de la ruta inicial, sin errores registrados en consola

#### Scenario: Proveedores disponibles

- **WHEN** un componente hijo consume el enrutador y el cliente de consultas
- **THEN** ambos contextos están disponibles sin lanzar excepciones
