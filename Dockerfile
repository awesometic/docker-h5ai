FROM nginx:1.15-alpine
LABEL maintainer="Awesometic <awesometic.lab@gmail.com>" \
      description="Lightweight h5ai container with Nginx 1.15 & PHP 7 based on Alpine Linux."

ENV TZ=Asia/Seoul

RUN apk update
RUN apk add --no-cache \
    bash bash-completion tzdata \
    php7 php7-fpm php7-json php7-xml php7-mbstring php7-intl \
    php7-gd php7-imagick php7-gmagick php7-zip ffmpeg imagemagick graphicsmagick zip

RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apk del tzdata

RUN mkdir /h5ai_shared

COPY config/nginx/h5ai.conf /etc/nginx/conf.d/h5ai.conf
COPY config/php/php_before_set_timezone.ini /etc/php7/conf.d/zzz_custom.ini
COPY config/_h5ai /usr/share/h5ai

RUN sed --in-place=.bak 's/worker_processes  1/worker_processes  auto/g' /etc/nginx/nginx.conf
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak
RUN echo $TZ"\"" >> /etc/php7/conf.d/zzz_custom.ini
RUN chown -R nginx:nogroup /usr/share/h5ai/public/cache
RUN chown -R nginx:nogroup /usr/share/h5ai/private/cache

EXPOSE 80
VOLUME ["/h5ai_shared"]
