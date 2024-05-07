FROM alpine:latest

RUN apk add --no-cache curl

ENV XP_VERSION=v1.15.0

RUN curl -sL "https://raw.githubusercontent.com/crossplane/crossplane/master/install.sh" | XP_VERSION=${XP_VERSION} sh

RUN mv crossplane /usr/local/bin/

WORKDIR /app/

CMD ["crossplane"]