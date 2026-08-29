<script>
  import { ModeWatcher } from 'mode-watcher'

  let { flash = {} } = $props()
</script>

<ModeWatcher />

{#each Object.entries(flash) as [kind, message] (kind)}
  <div class="toast toast-{kind}" role="alert">{message}</div>
{/each}
