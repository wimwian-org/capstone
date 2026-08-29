import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import liveSveltePlugin from 'live_svelte/vitePlugin'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  server: {
    host: '127.0.0.1',
    port: 5173,
    strictPort: true,
    cors: { origin: 'http://localhost:4000' },
  },
  optimizeDeps: {
    include: ['live_svelte', 'phoenix', 'phoenix_html', 'phoenix_live_view'],
  },
  build: {
    manifest: true,
    rollupOptions: { input: ['js/app.js', 'css/app.css'] },
    outDir: '../priv/static',
    // false, not true: outDir is priv/static ROOT (Vite's default assetsDir: "assets" already nests
    // hashed JS/CSS under priv/static/assets/, matching .gitignore + static_paths()). emptyOutDir: true
    // would delete the whole outDir first, including tracked files like priv/static/favicon.ico that
    // aren't Vite's to manage.
    emptyOutDir: false,
  },
  plugins: [
    tailwindcss(),
    svelte({ compilerOptions: { css: 'injected' } }),
    liveSveltePlugin({ components: './svelte/components/**/*.svelte' }),
  ],
})
