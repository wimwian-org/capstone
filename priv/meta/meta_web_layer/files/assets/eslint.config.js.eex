import svelte from 'eslint-plugin-svelte'
import prettier from 'eslint-config-prettier'

export default [
  ...svelte.configs['flat/recommended'],
  prettier,
  {
    rules: {
      complexity: ['warn', { max: 10 }],
      'max-depth': ['warn', 4],
      'max-lines-per-function': ['warn', { max: 60 }],
      'svelte/no-unused-svelte-ignore': 'error'
    }
  },
  { ignores: ['../priv/static/assets/', 'node_modules/', 'vendor/'] }
]
