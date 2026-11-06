# nginx 1.27.5-alpine, pinned by digest.
FROM nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10

RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx/nginx.conf /etc/nginx/nginx.conf
COPY nginx/conf.d/00-resolver.conf nginx/conf.d/20-server.conf /etc/nginx/conf.d/
# 10-security.conf holds ${GATEWAY_ALLOWED_ORIGIN}; the image renders templates into conf.d at start.
COPY nginx/conf.d/10-security.conf /etc/nginx/templates/10-security.conf.template
COPY nginx/snippets/ /etc/nginx/snippets/
COPY nginx/routes/ /etc/nginx/routes/

ENV GATEWAY_ALLOWED_ORIGIN=http://localhost:8080
# Trust no proxy by default: X-Forwarded-For is ignored until the front address is configured.
ENV GATEWAY_TRUSTED_PROXY=127.0.0.1/32

EXPOSE 8080

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
