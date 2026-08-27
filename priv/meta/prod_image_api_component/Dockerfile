# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the builder image
#     E.g.: docker.io/hexpm/elixir:1.20.3-erlang-29.0.5-alpine-3.24.1
#   - https://hub.docker.com/_/alpine/tags?name=3.24.1 - for the runner image
#     E.g.: docker.io/alpine:3.24.1
#
# Find builder and runner images on Docker Hub or on Hex's Build Server (Bob).
# We recommend using Bob's Web UI to find recent tags:
#
#   - https://bob.hex.pm/docker
#
# Use the same Alpine version for both the builder and the runner: the release
# is built against the builder's musl and shared libraries, and running it on a
# different libc is what "it worked in the builder" failures are made of.
#
# THIS DIFFERS FROM WHAT `mix phx.gen.release --docker` GENERATES, deliberately.
# Phoenix ships a Debian Dockerfile and its comment recommends Debian/Ubuntu over
# Alpine, citing DNS resolution failures and dynamically linked
# NIFs/precompiled binaries. That advice is real and is not deleted here:
#
#   - DNS: musl's resolver is not glibc's. It historically ignored `search`
#     domains and had no TCP fallback for large responses, which reaches Erlang's
#     `inet` and so reaches clustering and any service discovery by name. If this
#     project resolves peers by short name, or clusters across nodes, test that
#     specifically before trusting this image.
#   - NIFs: any dependency shipping a precompiled binary or a dynamically linked
#     NIF must have a musl build. The dependency set this image was derived
#     against needs none beyond `crypto`, which the builder image provides. Adding
#     one is the moment to re-check.
#
# The trade bought here is image size and pull time. If either risk above bites,
# switching back is mechanical: restore Phoenix's `apt-get` lines, the
# `locale-gen` block, and the Debian base images.
#
# For finding packages in Alpine, search on https://pkgs.alpinelinux.org/packages.

ARG ELIXIR_VERSION=1.20.3
ARG OTP_VERSION=29.0.5
ARG ALPINE_VERSION=3.24.1

ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION}"
ARG RUNNER_IMAGE="docker.io/alpine:${ALPINE_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apk add --no-cache build-base git

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force \
  && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv

COPY lib lib

# Compile the release
RUN mix compile

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

COPY rel rel

# NECESSARY, not defensive. These overlay scripts arrive from a Capstone plugin
# payload, and `Capstone.Plugin.Apply` writes file CONTENTS with `File.write!/2` and
# nothing else -- it has no concept of a file mode, so a plugin cannot ship an
# executable file. `mix release` copies overlays into the release as it finds
# them, so without this `bin/server` lands 0644 and `CMD ["/app/bin/server"]`
# fails at RUNTIME with a permission error, long after the build went green.
# The `.bat` siblings are harmless to include and cheaper than listing exceptions.
RUN chmod +x rel/overlays/bin/*

RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

# libstdc++ and ncurses are the musl-named equivalents of Debian's libstdc++6
# and libncurses6. There is no `locales` package: musl has no locale generation,
# so the locale is set by ENV alone below.
#
# `lksctp-tools` is deliberately NOT here, and that is why this release prints
#
#     [UNIX-ESSIO] Failed open sctp dynamic library: libsctp.so.1
#
# once on every boot. It is benign -- SCTP is not used by Phoenix, Ecto or the
# VM's ordinary networking -- and it is NOT caused by choosing Alpine. Measured
# on both: the alpine and Debian BUILDER images each ship libsctp, and the
# alpine and `debian:*-slim` RUNNER images each lack it, so Phoenix's own
# generated Dockerfile produces the same line. Adding the package silences it for
# 8.8MB on a 47MB image, which is not worth paying for a protocol nothing here
# speaks. Left as upstream has it, documented so the message is not mistaken for
# a symptom of musl.
RUN apk add --no-cache libstdc++ openssl ncurses ca-certificates

# Set the locale. C.UTF-8 rather than en_US.UTF-8: musl ships no locale
# definitions and cannot generate them, so C.UTF-8 is the only UTF-8 locale
# guaranteed to exist. Naming a locale musl lacks makes the VM fall back to
# latin-1 for filenames and IO, silently.
ENV LANG=C.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/new_api_app ./

USER nobody

# If using an environment that doesn't automatically reap zombie processes, it is
# advised to add an init process such as tini via `apk add tini`
# above and adding an entrypoint. See https://github.com/krallin/tini for details
# ENTRYPOINT ["/tini", "--"]

CMD ["/app/bin/server"]
