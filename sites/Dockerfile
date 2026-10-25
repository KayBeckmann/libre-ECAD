FROM python:3.12-alpine AS build
WORKDIR /repo
COPY sites ./sites
COPY LICENSE ./LICENSE
COPY frontend/libre_ecad_app/assets/fonts/NotoSans-Regular.ttf frontend/libre_ecad_app/assets/fonts/NotoSans-Bold.ttf frontend/libre_ecad_app/assets/fonts/LICENSE-Noto.txt ./frontend/libre_ecad_app/assets/fonts/
ARG HOMEPAGE_ORIGIN=
ARG WIKI_ORIGIN=
ARG APP_ORIGIN=
RUN python sites/build.py --output /output

FROM nginx:alpine
ARG SITE=homepage
COPY sites/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /output/${SITE}/ /usr/share/nginx/html/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1/health.txt || exit 1
