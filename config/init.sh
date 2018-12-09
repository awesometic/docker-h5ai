#!/usr/bin/env bash

msg() {
    echo -E "$1"
}

# Display environment variables
echo -e "Variables:
\t- TZ=${TZ}"

msg "Configure timezone for PHP..."
echo "$TZ\"" >> /etc/php7/conf.d/zzz_custom.ini

msg "Make config directories..."
mkdir -p /config/{nginx,h5ai}

# Locations of configuration files
orig_nginx="/etc/nginx/conf.d/h5ai.conf"
orig_h5ai="/usr/share/h5ai/_h5ai"
conf_nginx="/config/nginx/h5ai.conf"
conf_h5ai="/config/h5ai/_h5ai"

msg "Check configuration files for Nginx..."
if [ ! -f "$conf_nginx" ]; then
    msg "Copy original setup files to /config folder..."
    cp -arf $orig_nginx $conf_nginx
else
    msg "User setup files found: $conf_nginx"
    msg "Remove image's default setup files and copy the previous version..."
fi
rm -f $orig_nginx
ln -s $conf_nginx $orig_nginx

msg "Check configuration files for h5ai..."
if [ ! -d "$conf_h5ai" ]; then
    msg "Copy original setup files to /config folder..."
    cp -arf $orig_h5ai $conf_h5ai
else
    msg "User setup files found: $conf_h5ai"
    msg "Remove image's default setup files and copy the previous version..."
fi
rm -rf $orig_h5ai
ln -s $conf_h5ai $orig_h5ai

msg "Set ownership to make Nginx can read h5ai files..."
chown -R nginx:nogroup $conf_h5ai

msg "Set permission for caching..."
chmod -R 777 $conf_h5ai/public/cache
chmod -R 777 $conf_h5ai/private/cache

msg "Start supervisord..."
supervisord -c /etc/supervisor/conf.d/supervisord.conf
