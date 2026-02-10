# Phase 4: Primitives — Brainstorming Design Document

**Date:** 2026-02-10
**Phase:** 4 (Primitives)
**Status:** Design complete, ready for issue creation

## Process

The Phase 4 primitive set was designed through collaborative brainstorming, grounded in empirical analysis of 6 production webapps and validated against competitor platforms.

### Apps Surveyed

| App | Stack | Key Patterns |
|---|---|---|
| **autodock** | Next.js + PostgreSQL (Neon) + Vercel | 5 Vercel crons, Stripe/Clerk/GitHub/SES webhooks, Vercel Workflows, UploadThing+EFS storage, quota enforcement |
| **veeton** | React + Supabase + Hono | Clerk orgs, Orb billing webhooks, pg_cron + PGMQ, Inngest background jobs, Supabase Storage, feature gating by plan tier |
| **revolt** | Next.js + PostgreSQL (Prisma) | Lucia+WorkOS SSO, PDF Monkey/Switchgrid webhooks, Scheduler table (delayed execution), custom RBAC, credit system, Brevo email+SMS |
| **extuitive-v2** | Next.js + Supabase | Supabase Auth, Stripe webhooks, 5 Inngest crons, 98 Inngest background jobs, Supabase Storage, billing gates |
| **activeloop** | React + FastAPI + PostgreSQL | Auth0+OpenFGA, Nango/Orb webhooks, RabbitMQ workers, DeepLake/Azure storage, rate limiter, SSE streaming |
| **rightware/author** | AWS Lambda + DynamoDB | Cognito JWT, fal.ai webhook callbacks (stable endpoint + request_id correlation), WebSocket push to clients |

### Competitor Platforms Reviewed

| Platform | Primitives | Key Insight |
|---|---|---|
| **Convex** | Queries, Mutations, Actions, Scheduled Functions, Cron, File Storage, Auth, Reactive Subscriptions | Reactive subscriptions (auto-update queries) are a killer feature |
| **Cloudflare Workflows** | step.do(), step.sleep(), step.sleepUntil(), step.waitForEvent() | GA product; sleep maps to our after(), waitForEvent bridges webhook+workflow |
| **Supabase** | Auth, Storage, Realtime, Edge Functions, pg_cron | Realtime (Postgres changes streamed to clients) |
| **Firebase** | Auth, Firestore, Storage, Cloud Functions, onSnapshot | onSnapshot (real-time document listeners) |

## Key Design Decisions

### 1. Webhook: stable endpoints, not per-request URLs

**Finding:** All 6 surveyed apps (including fal.ai integration in rightware/author) use stable, signature-verified endpoints with payload-based correlation. None use per-request dynamically-minted URLs. The fal.ai pattern passes a static `FAL_WEBHOOK_URL` environment variable, correlating via `request_id` in the payload.

**Decision:** `webhook(path, handler)` registers a fixed route with signature verification. The VISION.md pattern of `webhook_url: wh.url` for per-request URLs is removed.

### 2. safe{} replaced by automatic context splitting

**Finding:** None of the 6 surveyed apps have anything like safe{} blocks. The original purpose was two-fold:

1. **Determinism verification** — proving client/server produce identical results. But pure computations are already deterministic without annotation, and interesting code (proxyFetch, db ops) can't be in safe blocks.

2. **Execution placement optimization** — enabling the compiler to move code between client and server. This is the compelling use case: a block with 3 proxyFetch calls should run on the server (0 round-trips) not the client (3 round-trips).

**Decision:** The compiler detects browser API usage (DOM, Canvas, etc.) automatically as "client anchors" and determines optimal split points. No developer annotation needed. The dual-target compilation mechanism from the PoC becomes an internal compiler pass, not a user-facing primitive.

### 3. guard() and permit() are separate primitives

**Finding:** Guard and permit both answer "who can do what" but differ fundamentally:

| | guard() | permit() |
|---|---|---|
| Enforcement | Compile-time structural constraint + runtime event provenance | Runtime identity-based check |
| What it checks | "Was this event minted by server code?" | "Does this user have the right role?" |
| Identity needed | No | Yes |

**Decision:** Keep separate. Guard is a structural impossibility (client cannot generate guarded events). Permit is a runtime gate (code exists, server checks role). They compose: `guard("credits")` + `permit("credits.spend", allowed = ["subscriber"])`.

### 4. permit() is separate from auth()

**Finding:** 4/6 apps have no separate permission layer (auth suffices). The 2 that do (Revolt, Activeloop) treat auth and authz as explicitly separate systems.

**Decision:** Permit is opt-in. Auth generates routes (signup, login, OAuth). Permit generates DO-level checks. Different artifacts, different change frequency. Can mix hosted auth (Clerk) with framework-native permit.

### 5. after() is distinct from cron()

**Finding:** Revolt uses a `Scheduler` table with `scheduledAt` for patterns like "remind in 7 days." Convex provides `scheduler.runAfter()`. Cloudflare Workflows provides `step.sleep()`.

**Decision:** `after(duration, handler)` as one-shot delayed execution (DO Alarms), distinct from `cron(schedule, handler)` (recurring, Cron Triggers). Different declaration sites (after is inline, cron is top-level), different recurrence, different triggers.

### 6. store() fills a universal gap

**Finding:** All 6 surveyed apps need file/blob storage. Common pattern: client gets signed upload URL, uploads directly to storage, stores key in database.

**Decision:** `store(name)` backed by Cloudflare R2 (zero egress). Generates signed upload URL endpoints, download URL endpoints, and garbage collection tied to event log compaction.

### 7. Reactive push is not a gap

**Finding:** Convex reactive queries, Firebase onSnapshot, and Supabase Realtime provide instant UI updates when data changes. Initially identified as a gap in Unanim.

**Decision:** Reactive push flows naturally from existing infrastructure. The WebSocket to the DO (needed for lease detection in Phase 3b and shared state in Phase 4) can push server-minted events (from webhook, cron, after, guard) to connected clients. No new system needed — but this claim requires explicit validation testing.

## Final Primitive Set

| Primitive | Purpose | Required? |
|---|---|---|
| `guard()` | Server-only state transitions (compile-time structural constraint) | Some apps |
| `permit()` | Role-based access control (runtime identity check) | Some apps |
| `webhook()` | Stable incoming endpoints with signature verification | Some apps |
| `cron()` | Recurring scheduled work | Some apps |
| `after()` | One-shot delayed execution (DO Alarms) | Some apps |
| `shared()` | Multi-user org DO with WebSocket | Some apps |
| `auth()` | Identity + session management | Most apps |
| `store()` | File/blob storage (R2) | Most apps |

Plus **automatic context splitting** as a compiler optimization (not a user-facing primitive).

## Validation Sources

- [Convex Overview](https://docs.convex.dev/understanding/)
- [Cloudflare Workflows GA](https://blog.cloudflare.com/workflows-ga-production-ready-durable-execution/)
- [Convex Scheduled Functions](https://docs.convex.dev/scheduling/scheduled-functions)
- [Web Development Trends 2026](https://blog.logrocket.com/8-trends-web-dev-2026/)
- [Google Agent Payments Protocol (AP2)](https://cloud.google.com/blog/products/ai-machine-learning/announcing-agents-to-payments-ap2-protocol)
- [Cloudflare Full-Stack Workers](https://blog.cloudflare.com/full-stack-development-on-cloudflare-workers/)
- [useworkflow.dev](https://useworkflow.dev/) primitives analysis
