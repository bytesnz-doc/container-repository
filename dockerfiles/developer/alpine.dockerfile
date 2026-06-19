FROM alpine:3.24.1

RUN apk add --no-cache sudo \
    && addgroup -S developer \
    && adduser -S -G developer developer \
    && echo "developer ALL=(ALL) NOPASSWD: /sbin/apk" > /etc/sudoers.d/developer \
    && chmod 440 /etc/sudoers.d/developer

USER developer
