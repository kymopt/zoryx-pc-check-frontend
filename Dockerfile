# ---- Base image ----
FROM node:20-alpine AS base
# libc6-compat is required for some Next.js dependencies on Alpine
RUN apk add --no-cache libc6-compat
WORKDIR /app

# ---- Dependencies stage ----
FROM base AS deps
COPY package.json package-lock.json* ./
# Use npm ci for reproducible, clean installs when a lockfile is present,
# otherwise fall back to npm install.
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ---- Build stage ----
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ENV NEXT_TELEMETRY_DISABLED=1
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

RUN npm run build

# ---- Runner (production) stage ----
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 nextjs

# Ensure the public directory exists even if the builder stage has no static
# assets to serve, so this COPY never fails the build.
RUN mkdir -p ./public
COPY --from=builder /app/public ./public

# Copy the full build output, package.json/lockfile, and production
# node_modules so "next start" can run normally without standalone mode.
COPY --from=builder --chown=nextjs:nodejs /app/.next ./.next
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

CMD ["npm", "start"]
