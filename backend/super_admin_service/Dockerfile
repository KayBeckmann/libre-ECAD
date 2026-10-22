# Build-Kontext ist `backend/` (siehe docker-compose.yml), damit die
# lokale Pfadabhängigkeit `../shared_server_kit` mit in den Kontext
# passt — jeder Dienst bleibt trotzdem ein eigenes, unabhängig
# gebautes Image.
FROM dart:stable AS build
WORKDIR /app
COPY shared_server_kit /app/shared_server_kit
COPY super_admin_service /app/super_admin_service
WORKDIR /app/super_admin_service
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/super_admin_service/bin/server /app/server
EXPOSE 8081
ENTRYPOINT ["/app/server"]
