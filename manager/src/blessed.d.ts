// SPDX-License-Identifier: Apache-2.0

declare module 'blessed' {
  type Style = Record<string, unknown>
  interface BlessedNode {
    setContent(text: string): void
    setLabel(text: string): void
    scroll(offset: number): void
    focus(): void
  }
  interface Screen extends BlessedNode {
    key(keys: string | string[], handler: () => void): void
    on(event: string, handler: () => void): void
    render(): void
    destroy(): void
  }
  interface BoxOptions {
    parent?: Screen | BlessedNode
    top?: number | string
    left?: number | string
    bottom?: number | string
    width?: number | string
    height?: number | string
    label?: string
    tags?: boolean
    border?: { type?: string }
    style?: Style
    scrollable?: boolean
    alwaysScroll?: boolean
    keys?: boolean
    vi?: boolean
    mouse?: boolean
    scrollbar?: Style
  }
  interface ScreenOptions {
    smartCSR?: boolean
    title?: string
    fullUnicode?: boolean
  }
  function screen(opts?: ScreenOptions): Screen
  function box(opts?: BoxOptions): BlessedNode
  export { screen, box, Screen, BlessedNode, BoxOptions }
}
