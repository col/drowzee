#########################
###### Build Image ######
#########################

FROM elixir:1.18 AS builder

ENV MIX_ENV=prod \
  MIX_HOME=/opt/mix \
  HEX_HOME=/opt/hex

# install build dependencies (only required for mix assets.deploy)
# RUN apt-get update -y && apt-get install -y build-essential git npm \
#     && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

COPY mix.lock mix.exs ./
COPY config config

RUN mix deps.get --only-prod && mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

# compile assets (not currently required)
# RUN npm --prefix ./assets ci --progress=false --no-audit --loglevel=error
# RUN mix assets.deploy

# run digest for static assets
RUN mix phx.digest

RUN mix release

#########################
##### Release Image #####
#########################

FROM elixir:1.18-slim

# set runner ENV
ENV MIX_ENV="prod"

# elixir expects utf8.
ENV LANG=C.UTF-8
ENV PORT=8080

WORKDIR /app
RUN chown nobody /app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/drowzee ./

USER nobody

EXPOSE 8080
ENTRYPOINT ["/app/bin/drowzee"]
CMD ["start"]
