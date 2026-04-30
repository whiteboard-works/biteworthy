# syntax=docker/dockerfile:1
# Phase 5.1 — production image for Fly.io.
#
# Multi-stage:
#   1. `base`  — common ENV + WORKDIR; the smallest layer both later
#                stages share. ruby:3.3.6-slim matches .ruby-version.
#   2. `build` — installs OS build deps + gems + bootsnap precompiles.
#                Throws away apt caches / .git so the final image is
#                lean.
#   3. `final` — runtime deps only (libpq, libvips for image_processing,
#                imagemagick for Phase 4.11.1's DishPhotoCropper),
#                copies the bundled gems + app from `build`, runs as
#                a non-root rails:1000 user.
#
# Both fly.toml processes (`app` = puma, `worker` = solid_queue:start)
# share this image — the entrypoint just dispatches on argv.

ARG RUBY_VERSION=3.3.6
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# --- build stage -------------------------------------------------------------
FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        build-essential \
        git \
        libpq-dev \
        libyaml-dev \
        pkg-config \
        curl

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

COPY . .

# Precompile bootsnap cache for app + lib (faster cold boots on Fly).
RUN bundle exec bootsnap precompile app/ lib/

# --- final stage -------------------------------------------------------------
FROM base

# Runtime-only OS deps. libvips + imagemagick are both used by
# image_processing (review photos + Phase 4.11 dish photos); libpq for
# Postgres; libjemalloc2 trims puma's RSS by ~30%.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
        curl \
        libjemalloc2 \
        libpq5 \
        libvips42 \
        imagemagick \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log tmp
USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
