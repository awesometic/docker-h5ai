FROM nginx:1.27-alpine3.19
LABEL maintainer="Deokgyu Yang <secugyu@gmail.com>" \
      description="Lightweight h5ai 0.30.0 container with Nginx 1.27 & PHP 8.2 based on Alpine Linux."

RUN apk update
RUN apk add --no-cache \
    bash bash-completion supervisor tzdata shadow \
    php82 php82-fpm php82-session php82-json php82-xml php82-mbstring php82-exif \
    php82-intl php82-gd php82-pecl-imagick php82-zip php82-opcache \
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
COPY config/php_set_timezone.ini /etc/php82/conf.d/00_timezone.ini
COPY config/php_set_jit.ini /etc/php82/conf.d/00_jit.ini
COPY config/php_set_memory_limit.ini /etc/php82/conf.d/00_memlimit.ini
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
