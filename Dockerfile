FROM nginx:1.15-alpine
LABEL maintainer="Awesometic <awesometic.lab@gmail.com>" \
      description="Lightweight h5ai 0.29 container with Nginx 1.15 & PHP 7 based on Alpine Linux."

ENV TZ=Asia/Seoul

RUN apk update
RUN apk add --no-cache \
    bash bash-completion supervisor tzdata \
    php7 php7-fpm php7-session php7-json php7-xml php7-mbstring php7-exif \
    php7-intl php7-gd php7-imagick php7-gmagick php7-zip \
    ffmpeg imagemagick graphicsmagick zip

# Configure system timezone
RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apk del tzdata

# Configure Nginx server
RUN sed --in-place=.bak 's/worker_processes  1/worker_processes  auto/g' /etc/nginx/nginx.conf
COPY config/h5ai.conf /etc/nginx/conf.d/h5ai.conf
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak

# Configure PHP
COPY config/php_set_timezone.ini /etc/php7/conf.d/zzz_custom.ini
RUN echo $TZ"\"" >> /etc/php7/conf.d/zzz_custom.ini

# Configure Supervisor
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy prepared h5ai data and configure it for caching
COPY config/_h5ai /h5ai/_h5ai
RUN chmod -R 777 /h5ai/_h5ai/public/cache
RUN chmod -R 777 /h5ai/_h5ai/private/cache

EXPOSE 80
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
