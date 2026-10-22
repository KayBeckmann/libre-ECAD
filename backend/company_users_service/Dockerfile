FROM dart:stable AS build
WORKDIR /app
COPY shared_server_kit /app/shared_server_kit
COPY company_users_service /app/company_users_service
WORKDIR /app/company_users_service
RUN dart pub get
RUN dart compile exe bin/server.dart -o bin/server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/company_users_service/bin/server /app/server
EXPOSE 8083
ENTRYPOINT ["/app/server"]
