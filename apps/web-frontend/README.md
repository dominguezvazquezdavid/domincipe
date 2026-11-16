# web-frontend

SPA del proyecto Domincipe: React 19, TypeScript estricto, Vite 8, Tailwind CSS 4 y
shadcn/ui. Consume el `api-gateway`; no contiene hosts del backend codificados.

## Requisitos

- Node.js ≥ 22.22.0. El `.npmrc` local fija `engine-strict=true`, así que `npm ci`
  falla si la versión instalada no cumple el campo `engines` del `package.json`.

## Comandos

```bash
npm ci                 # instalación reproducible desde package-lock.json
npm run dev            # servidor de desarrollo con HMR
npm run build          # type-check y bundle estático en dist/
npm run lint           # ESLint (configuración plana)
npm test               # tests unitarios con Vitest (una pasada)
npm run test:coverage  # tests + informe de cobertura en coverage/
npm run preview        # sirve el bundle ya construido
```

## Convenciones

- El alias `@/*` apunta a `src/*` (lo usan Tailwind, Vite y shadcn/ui).
- Los componentes generados por shadcn/ui viven en `src/components/ui/` y su
  configuración en `components.json`.
- El enrutador (`src/app/router.tsx`) y el `QueryClient` (`src/app/query-client.ts`)
  se construyen una sola vez fuera del árbol de React: `main.tsx` crea el router y
  `App` monta los proveedores de rutas y de datos.
- Los tests viven junto al código (`*.test.tsx`) y corren con Vitest sobre jsdom;
  `src/test/setup.ts` carga los matchers de `@testing-library/jest-dom` y el
  *cleanup* de Testing Library.
- La URL del API llega por entorno (`VITE_API_BASE_URL`), nunca embebida en el código.

