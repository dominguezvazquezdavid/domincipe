import { createBrowserRouter, type RouteObject } from 'react-router'
import { AppLayout } from '@/components/layout/app-layout'
import { HomePage } from '@/routes/home-page'

export const appRoutes: RouteObject[] = [
  {
    path: '/',
    element: <AppLayout />,
    children: [{ index: true, element: <HomePage /> }],
  },
]

export function createAppRouter() {
  return createBrowserRouter(appRoutes)
}
