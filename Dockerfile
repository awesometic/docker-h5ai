FROM apline:3.8
LABEL maintainer="Awesometic <awesometic.lab@gmail.com>" \
      description="Lightweight h5ai container with Nginx & PHP 7 based on Alpine Linux."

ENV TZ=Asia/Seoul

RUN apk add --no-cache \
    tzdata \
    nginx php7 php7-fpm php7-json php7-xml php7-mbstring php7-intl \
    php7-gd php7-imagick php7-gmagick php7-zip ffmpeg imagemagick graphicsmagick zip

RUN cp /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apk del tzdata

COPY config/nginx/nginx.conf /etc/nginx/nginx.conf
COPY config/nginx/fastcgi_params /etc/nginx/fastcgi_params
COPY config/php/php_before_set_timezone.ini /etc/php7/conf.d/zzz_custom.ini
COPY _h5ai /h5ai_share

RUN chown -R nginx:nogroup /h5ai_share


