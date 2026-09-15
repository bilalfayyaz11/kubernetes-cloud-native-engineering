FROM nginxinc/nginx-unprivileged:1.29-alpine

COPY --chown=101:101 index.html /usr/share/nginx/html/index.html

USER 101

EXPOSE 8080
