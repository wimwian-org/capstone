import { describe, expect, it } from 'vitest'
import { render } from '@testing-library/svelte'
import AppShell from '../../../svelte/components/AppShell.svelte'

describe('AppShell', () => {
  it('renders no toasts when flash is empty', () => {
    const { queryAllByRole } = render(AppShell)

    expect(queryAllByRole('alert')).toHaveLength(0)
  })

  it('renders one toast per flash entry', () => {
    const { getByText } = render(AppShell, {
      props: {
        flash: { info: 'Saved successfully', error: 'Something went wrong' },
      },
    })

    expect(getByText('Saved successfully').className).toBe('toast toast-info')
    expect(getByText('Something went wrong').className).toBe(
      'toast toast-error'
    )
  })
})
