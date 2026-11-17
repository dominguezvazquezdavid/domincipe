const API_BASE_URL_VARIABLE = 'VITE_API_BASE_URL'

// Single read of the API base URL. vite.config.ts already fails dev, build and
// test runs when the variable is missing, so this guard only covers entry
// points that load the module without going through Vite.
function readApiBaseUrl(): string {
  const value = import.meta.env.VITE_API_BASE_URL?.trim()

  if (!value) {
    throw new Error(
      `${API_BASE_URL_VARIABLE} is not defined. Set it in the environment before starting the frontend.`,
    )
  }

  // A trailing slash would produce double slashes once a path is appended.
  return value.replace(/\/+$/, '')
}

export const env = Object.freeze({
  apiBaseUrl: readApiBaseUrl(),
})
