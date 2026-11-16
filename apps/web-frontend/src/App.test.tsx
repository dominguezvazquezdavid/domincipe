import { useQueryClient } from '@tanstack/react-query'
import { render, screen } from '@testing-library/react'
import { createMemoryRouter, useLocation } from 'react-router'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { appRoutes } from '@/app/router'
import App from './App'

function ProvidersProbe() {
  const location = useLocation()
  const queryClient = useQueryClient()
  const cachedQueries = queryClient.getQueryCache().getAll().length

  return (
    <p data-testid="providers-probe">{`route:${location.pathname} queries:${cachedQueries}`}</p>
  )
}

describe('App', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('renders the shell title and the initial empty state without console errors', () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => {})

    render(<App router={createMemoryRouter(appRoutes, { initialEntries: ['/'] })} />)

    expect(screen.getByRole('heading', { level: 1, name: 'Domincipe' })).toBeInTheDocument()
    expect(screen.getByText(/todavía no hay recetas/i)).toBeInTheDocument()
    expect(consoleError).not.toHaveBeenCalled()
  })

  it('exposes the router and query client contexts to child components', () => {
    const router = createMemoryRouter([{ path: '/', element: <ProvidersProbe /> }], {
      initialEntries: ['/'],
    })

    render(<App router={router} />)

    expect(screen.getByTestId('providers-probe')).toHaveTextContent('route:/ queries:0')
  })
})
