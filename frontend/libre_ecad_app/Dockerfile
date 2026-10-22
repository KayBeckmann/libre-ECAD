# Liefert nur den fertig gebauten Flutter-Web-Build aus (`flutter
# build web --release` läuft lokal, nicht im Container — gleiches
# Muster wie WerkkernERP, siehe docs/architecture.md).
FROM nginx:alpine
COPY build/web /usr/share/nginx/html
EXPOSE 80
