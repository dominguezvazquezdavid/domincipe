/// <reference types="vite/client" />

interface ImportMetaEnv {
  // Validated by vite.config.ts: the build fails when it is missing, so the
  // optional type reflects the guard that src/config/env.ts still applies.
  readonly VITE_API_BASE_URL?: string
}
