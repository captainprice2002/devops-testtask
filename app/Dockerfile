# syntax=docker/dockerfile:1.7
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0
COPY --from=deps /app/node_modules ./node_modules
COPY server.js ./
COPY package.json ./

# Run as a non-root user. We use the numeric UID (the `node` user in
# node:20-alpine has UID 1000) so Kubernetes' runAsNonRoot check can verify it
# without resolving a name.
USER 1000

EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health >/dev/null || exit 1
CMD ["node", "server.js"]
