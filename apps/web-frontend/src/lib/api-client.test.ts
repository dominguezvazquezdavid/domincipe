import { afterEach, describe, expect, it, vi } from 'vitest'
import { env } from '@/config/env'
import { ApiError, apiUrl, getJson } from './api-client'

function jsonResponse(body: unknown, status = 200): Response {
  // A plain object keeps the test independent of the fetch/Response polyfills
  // available in the jsdom environment.
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  } as Response
}

describe('api client', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('exposes the API base URL read from the environment', () => {
    expect(env.apiBaseUrl).toBe(import.meta.env.VITE_API_BASE_URL)
  })

  it('builds absolute URLs against the configured base URL', () => {
    expect(apiUrl('/health')).toBe(`${env.apiBaseUrl}/health`)
    expect(apiUrl('health')).toBe(`${env.apiBaseUrl}/health`)
  })

  it('sends requests to the URL configured in VITE_API_BASE_URL', async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse({ status: 'UP' }))
    vi.stubGlobal('fetch', fetchMock)

    await expect(getJson<{ status: string }>('/health')).resolves.toEqual({ status: 'UP' })

    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(fetchMock).toHaveBeenCalledWith(`${import.meta.env.VITE_API_BASE_URL}/health`, {
      headers: { Accept: 'application/json' },
    })
  })

  it('throws an ApiError when the response is not successful', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({}, 503)))

    const request = getJson('/health')

    await expect(request).rejects.toBeInstanceOf(ApiError)
    await expect(request).rejects.toMatchObject({ status: 503 })
  })
})
