FROM nginx:1.25-alpine3.17
LABEL maintainer="Deokgyu Yang <secugyu@gmail.com>" \
      description="Lightweight h5ai 0.30.0 container with Nginx 1.25 & PHP 8.1 based on Alpine Linux."

RUN apk update
RUN apk add --no-cache \
    bash bash-completion supervisor tzdata shadow \
    php81 php81-fpm php81-session php81-json php81-xml php81-mbstring php81-exif \
    php81-intl php81-gd php81-pecl-imagick php81-zip php81-opcache \
    ffmpeg imagemagick zip apache2-utils patch

# Environments
ENV PUID=911
ENV PGID=911
ENV TZ='Asia/Seoul'
ENV HTPASSWD='false'
ENV HTPASSWD_USER='guest'
ENV HTPASSWD_PW=''

# Copy configuration files
COPY config/h5ai.conf /etc/nginx/conf.d/h5ai.conf
COPY config/php_set_timezone.ini /etc/php81/conf.d/00_timezone.ini
COPY config/php_set_jit.ini /etc/php81/conf.d/00_jit.ini
COPY config/php_set_memory_limit.ini /etc/php81/conf.d/00_memlimit.ini
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy h5ai
COPY config/_h5ai /usr/share/h5ai/_h5ai

# Configure Nginx server
RUN sed --in-place=.bak 's/worker_processes  1/worker_processes  auto/g' /etc/nginx/nginx.conf
RUN mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak

# Add shell script, patch files
ADD config/init.sh /
ADD config/h5ai.conf.htpasswd.patch /
# Set entry point file permission
RUN chmod a+x /init.sh

EXPOSE 80
VOLUME [ "/config", "/h5ai" ]
ENTRYPOINT [ "/init.sh" ]
