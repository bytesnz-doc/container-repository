ARG BASE_IMAGE=ghcr.io/bytesnz-doc/alpine:latest
FROM ${BASE_IMAGE}

RUN apk add --no-cache sudo \
    && addgroup -S developer \
    && adduser -S -G developer developer \
    && echo "developer ALL=(ALL) NOPASSWD: /sbin/apk" > /etc/sudoers.d/developer \
    && chmod 440 /etc/sudoers.d/developer

USER developer
