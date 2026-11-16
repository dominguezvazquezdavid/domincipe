import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// RTL only auto-registers its cleanup hook when Vitest globals are enabled,
// and this project keeps globals off to rely on explicit imports.
afterEach(() => {
  cleanup()
})
