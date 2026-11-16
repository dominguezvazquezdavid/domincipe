import { QueryClientProvider } from '@tanstack/react-query'
import { useState } from 'react'
import { RouterProvider, type RouterProviderProps } from 'react-router'
import { createQueryClient } from '@/app/query-client'

interface AppProps {
  // Created once outside the React tree, as React Router requires for data routers.
  router: RouterProviderProps['router']
}

function App({ router }: AppProps) {
  const [queryClient] = useState(createQueryClient)

  return (
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  )
}

export default App

