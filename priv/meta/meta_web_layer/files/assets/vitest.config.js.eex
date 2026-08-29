import { defineConfig } from 'vitest/config'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import { playwright } from '@vitest/browser-playwright'

export default defineConfig({
  plugins: [svelte({ compilerOptions: { hmr: false } })],
  test: {
    include: ['test/**/*.{test,spec}.{js,ts}', 'test/**/*.svelte.{test,spec}.{js,ts}'],
    browser: {
      enabled: true,
      provider: playwright(),
      instances: [{ browser: 'chromium' }],
      headless: true,
    },
    coverage: {
      provider: 'v8',
      include: ['svelte/**/*.{js,ts,svelte}'],
      exclude: ['**/*.{test,spec}.*'],
      thresholds: { statements: 100, branches: 100, functions: 100, lines: 100 },
      reporter: ['text', 'html', 'lcov'],
    },
  },
})
