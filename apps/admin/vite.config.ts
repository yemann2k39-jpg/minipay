import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:3000',
        // Backend routes have no /api prefix — strip it when proxying.
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
})
