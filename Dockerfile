FROM debian:bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git gh jq \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY . .
RUN chmod +x ./scripts/github-ci.sh

CMD ["./scripts/github-ci.sh"]
