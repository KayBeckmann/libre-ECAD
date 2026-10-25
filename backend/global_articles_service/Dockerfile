FROM dart:stable AS build
WORKDIR /app
COPY ecad_core /app/ecad_core
COPY shared_server_kit /app/shared_server_kit
COPY global_articles_service /app/global_articles_service
WORKDIR /app/global_articles_service
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/global_articles_service/bin/server /app/server
EXPOSE 8082
ENTRYPOINT ["/app/server"]
