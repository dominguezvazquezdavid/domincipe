import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { createAppRouter } from '@/app/router'
import './index.css'
import App from './App.tsx'

const router = createAppRouter()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App router={router} />
  </StrictMode>,
)
