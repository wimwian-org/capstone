import 'phoenix_html'
import { Socket } from 'phoenix'
import { LiveSocket } from 'phoenix_live_view'
import { getHooks } from 'live_svelte'
import Components from 'virtual:live-svelte-components'
import topbar from 'topbar'

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute('content')
const liveSocket = new LiveSocket('/live', Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: getHooks(Components),
})

topbar.config({ barColors: { 0: '#29d' }, shadowColor: 'rgba(0,0,0,.3)' })
window.addEventListener('phx:page-loading-start', () => topbar.show(300))
window.addEventListener('phx:page-loading-stop', () => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
