import path from 'node:path'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { loadEnv } from 'vite'
import { configDefaults, defineConfig } from 'vitest/config'

const API_BASE_URL_VARIABLE = 'VITE_API_BASE_URL'

// Vite is the only entry point shared by dev, build and test, so validating the
// variable here fails before a bundle without an API endpoint is produced
// (design decision D13). loadEnv reads this package's .env files and the
// VITE_* variables already present in the process environment.
function assertApiBaseUrl(mode: string): void {
  const apiBaseUrl = loadEnv(mode, import.meta.dirname)[API_BASE_URL_VARIABLE]?.trim()

  if (!apiBaseUrl) {
    throw new Error(
      `${API_BASE_URL_VARIABLE} is not defined. Set it in the environment before running Vite ` +
        `(for example: ${API_BASE_URL_VARIABLE}=http://localhost:8080 npm run build).`,
    )
  }
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => {
  assertApiBaseUrl(mode)

  return {
    plugins: [react(), tailwindcss()],
    resolve: {
      alias: {
        // shadcn/ui resolves generated components through the "@/*" alias.
        '@': path.resolve(import.meta.dirname, './src'),
      },
    },
    test: {
      environment: 'jsdom',
      setupFiles: ['./src/test/setup.ts'],
      // e2e/ belongs to Playwright, not to Vitest (change ci-integration, design D7): those
      // specs import @playwright/test and would fail here with no browser to drive.
      exclude: [...configDefaults.exclude, 'e2e/**'],
      coverage: {
        provider: 'v8',
        reporter: ['text', 'html'],
        include: ['src/**/*.{ts,tsx}'],
        // The bootstrap entry point and the test scaffolding are not product code.
        exclude: ['src/main.tsx', 'src/test/**', 'src/**/*.test.{ts,tsx}', 'src/**/*.d.ts'],
      },
    },
  }
})

