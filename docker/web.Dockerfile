FROM debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.44.6
ARG DOMAIN

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --branch "${FLUTTER_VERSION}" --depth 1 https://github.com/flutter/flutter.git /opt/flutter

ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN flutter config --enable-web \
    && flutter precache --web

WORKDIR /src

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY analysis_options.yaml ./
COPY assets ./assets
COPY lib ./lib
COPY web ./web

RUN test -n "${DOMAIN}" \
    && flutter build web --release \
      --dart-define=APP_ENV=production \
      --dart-define="API_BASE_URL=https://${DOMAIN}/api/v1" \
      --dart-define=WS_PATH=/api/v1/ws \
      --dart-define=CONNECT_TIMEOUT_SECONDS=15

FROM caddy:2.10-alpine

COPY docker/Caddyfile /etc/caddy/Caddyfile
COPY --from=build /src/build/web /srv

EXPOSE 80 443
