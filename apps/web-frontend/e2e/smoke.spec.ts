import { expect, test } from '@playwright/test'

// PROVOCACIÓN DE LA TAREA 4.5 — se revierte en el commit siguiente.
//
// Falla siempre, a propósito, para que un build de verdad recorra la etapa E2E en rojo y archive
// la traza y el vídeo del smoke junto con los logs del proyecto (tareas 4.5 y 5.4 de
// `ci-integration`). No describe producto y no sobrevive a este change.
test('deliberate failure of task 4.5', async ({ page }) => {
  await page.goto('/')

  await expect(page.locator('#root')).not.toBeAttached()
})

// Smoke test of the served application: the wiring, not the product.
//
// Every assertion here is an invariant that survives the real screens: the bundle is served,
// the server resolves an internal route to the shell, the gateway answers, the correlation
// header travels and the browser console stays clean. Copy, layout and business flows are out on
// purpose — when the recipe screens exist, their own specs are added next to this file and none
// of these has to be rewritten (change ci-integration, design D7).
const gatewayURL = process.env.E2E_GATEWAY_URL ?? 'http://localhost:8080'

test('the SPA is served with its mount point', async ({ page }) => {
  const response = await page.goto('/')

  expect(response?.status()).toBe(200)
  await expect(page.locator('#root')).toBeAttached()
})

test('an internal route falls back to the SPA shell', async ({ page }) => {
  // nginx has to answer with the shell instead of a 404 for a path that is not a file: that is
  // the try_files rule of ops/docker/nginx.conf, and React Router does the rest in the browser.
  const response = await page.goto('/recipes/this-path-is-not-a-file')

  expect(response?.status()).toBe(200)
  await expect(page.locator('#root')).toBeAttached()
})

test('the gateway reports itself healthy', async ({ request }) => {
  const response = await request.get(`${gatewayURL}/actuator/health`)

  expect(response.status()).toBe(200)
  expect(await response.json()).toMatchObject({ status: 'UP' })
})

test('the gateway answers with a correlation id', async ({ request }) => {
  const response = await request.get(`${gatewayURL}/actuator/health`)

  expect(response.headers()['x-request-id']).toMatch(/^[0-9a-f-]{36}$/)
})

test('the console registers no errors while the application loads', async ({ page }) => {
  const problems: string[] = []
  page.on('console', (message) => {
    if (message.type() === 'error') {
      problems.push(message.text())
    }
  })
  page.on('pageerror', (error) => problems.push(error.message))

  await page.goto('/')
  // networkidle is what turns "the page answered" into "the page finished loading": a console
  // error from a module or a fetch arrives after the document, and this is the settle that lets
  // it be captured. The page is a static bundle with no polling, so it settles.
  await page.waitForLoadState('networkidle')

  expect(problems).toEqual([])
})
