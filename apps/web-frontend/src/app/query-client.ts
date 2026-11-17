import { QueryClient } from '@tanstack/react-query'

const STALE_TIME_MS = 30_000

export function createQueryClient(): QueryClient {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // The local Compose stack is the only backend; a short cache keeps
        // screens responsive without hiding stale data for long.
        staleTime: STALE_TIME_MS,
        retry: 1,
        refetchOnWindowFocus: false,
      },
    },
  })
}
