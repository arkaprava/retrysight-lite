// SPDX-License-Identifier: Apache-2.0

import { timingSafeEqual } from 'node:crypto'
import { config } from './config.js'

export function extractAdminToken(
  headers: Record<string, string | string[] | undefined>,
): string | undefined {
  const auth = headers.authorization
  if (typeof auth === 'string') {
    const m = /^Bearer\s+(.+)$/i.exec(auth.trim())
    if (m?.[1]) return m[1].trim()
  }
  const primary = headers['x-retrysight-admin-token']
  const legacy = headers['x-retrysitelite-admin-token']
  const header = primary ?? legacy
  if (typeof header === 'string' && header.trim()) return header.trim()
  if (Array.isArray(header) && header[0]?.trim()) return header[0].trim()
  return undefined
}

function safeEqualString(a: string, b: string): boolean {
  const ab = Buffer.from(a)
  const bb = Buffer.from(b)
  const maxLen = Math.max(ab.length, bb.length)
  const paddedA = Buffer.alloc(maxLen, ab)
  const paddedB = Buffer.alloc(maxLen, bb)
  return timingSafeEqual(paddedA, paddedB)
}

/** Throws with statusCode 401 when the admin token is missing or wrong. */
export function assertAdminToken(provided: string | undefined): void {
  if (!provided || !safeEqualString(provided, config.adminToken)) {
    console.error(`[retrysight-lite] Failed admin auth attempt`)
    const err = new Error('Unauthorized')
    ;(err as Error & { statusCode: number }).statusCode = 401
    throw err
  }
}

export function isPublicPath(pathname: string): boolean {
  return pathname === '/api/v1/health' || pathname === '/graphql'
}

export function isIngestPath(pathname: string): boolean {
  return pathname === '/api/v1/ingest' || pathname.startsWith('/api/v1/ingest/')
}
