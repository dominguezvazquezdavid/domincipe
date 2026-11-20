// Playwright configuration of the frontend smoke test (change ci-integration, design D7).
//
// It is a second test runner next to Vitest on purpose: Vitest runs in jsdom over the components,
// Playwright drives a real browser against the served bundle. The two never share a spec, and
// `npm test` stays the fast unit runner (vite.config.ts excludes e2e/).
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e',
  // One retry, and only at this level: PROJECT.md §8 allows it for e2e and for nothing else.
  retries: 1,
  // Evidence only when something fails, so a green build archives no trace and a red one
  // archives what it takes to diagnose it (change ci-integration, design D9).
  outputDir: 'e2e/test-results',
  use: {
    // The environment under test is a Docker Compose project. On the development host the bundle
    // is published on 8086 (docker-compose.dev.yml); in the gate the smoke runs in a container of
    // the project network and reaches the service by name, so the address is a variable that
    // defaults to the local one instead of being hard-coded to either.
    baseURL: process.env.E2E_BASE_URL ?? 'http://localhost:8086',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  // junit is what the pipeline publishes next to the surefire and failsafe reports, outside the
  // outputDir Playwright empties on every run.
  reporter: [['list'], ['junit', { outputFile: 'e2e/junit-results.xml' }]],
})
