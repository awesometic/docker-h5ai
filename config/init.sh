#!/usr/bin/env bash

msg() {
    echo -E "$1"
}

# Display environment variables
echo -e "Variables:
\\t- PUID=${PUID}
\\t- PGID=${PGID}
\\t- TZ=${TZ}
\\t- HTPASSWD=${HTPASSWD}
\\t- HTPASSWD_USER=${HTPASSWD_USER}
\\t- HTPASSWD_PW=${HTPASSWD_PW}"

if [ "$( grep -rni "$TZ" /etc/php82/conf.d/00_timezone.ini | wc -l )" -eq 0 ]; then
    msg "Configure timezone for PHP..."
    echo "$TZ\"" >> /etc/php82/conf.d/00_timezone.ini
fi

msg "Make config directories..."
mkdir -p /config/{nginx,h5ai}

msg "Add dummy user for better handle permission..."
useradd -u 911 -U -d /config -s /bin/false abc && usermod -G users abc
groupmod -o -g "$PGID" abc
usermod -o -u "$PUID" abc

# Locations of configuration files
orig_nginx="/etc/nginx/conf.d/h5ai.conf"
orig_h5ai="/usr/share/h5ai/_h5ai"
conf_nginx="/config/nginx/h5ai.conf"
conf_h5ai="/config/h5ai/_h5ai"
conf_htpwd="/config/nginx/.htpasswd"
options_file="/private/conf/options.json"

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

    msg "Check if h5ai version updated..."
    new_ver=$(head -n 1 $orig_h5ai$options_file | awk '{print $3}' | sed 's/[^0-9]//g')
    pre_ver=$(head -n 1 $conf_h5ai$options_file | awk '{print $3}' | sed 's/[^0-9]//g')
    if [ $new_ver -gt $pre_ver ]; then
		msg "New version detected. Make existing options.json backup file..."
		cp $conf_h5ai$options_file /config/$(date '+%Y%m%d_%H%M%S')_options.json.bak

		msg "Remove existing h5ai files..."
		rm -rf $conf_h5ai

		msg "Copy the new version..."
		cp -arf $orig_h5ai $conf_h5ai
	fi

    msg "Remove image's default setup files and copy the existing version..."
fi
rm -rf $orig_h5ai
ln -s $conf_h5ai $orig_h5ai

msg "Set permission for caching..."
chmod -R 777 $conf_h5ai/public/cache
chmod -R 777 $conf_h5ai/private/cache

# If an user wants to set htpasswd
if [ "$HTPASSWD" = "true" ]; then
    if [ ! -f "$conf_htpwd" ]; then
        msg "Create an authenticate account for h5ai website..."

        if [ -z "$HTPASSWD_PW" ]; then
            msg "Please enter a password for user $HTPASSWD_USER"

            # Create a new htpasswd file with user's entered password
            htpasswd -c "$conf_htpwd" "$HTPASSWD_USER"
        else
            # Create a new htpasswd file with environment variables
            htpasswd -b -c "$conf_htpwd" "$HTPASSWD_USER" "$HTPASSWD_PW"
        fi
    else
        msg "User setup files found: $conf_htpwd"
    fi

    # Patch Nginx server instance
    if [ "$( grep -rni "auth" /config/nginx/h5ai.conf | wc -l )" -eq 0 ]; then
        patch -p1 /config/nginx/h5ai.conf -i /h5ai.conf.htpasswd.patch
    fi
else
    if [ "$( grep -rni "auth" /config/nginx/h5ai.conf | wc -l )" -gt 0 ]; then
        msg "HTPASSWD not configured but Nginx server sets. Reverse the patch..."
        patch -R -p1 /config/nginx/h5ai.conf -i /h5ai.conf.htpasswd.patch
    fi
fi

msg "Fix ownership for Nginx and php-fpm..."
sed -i "s#user  nginx;.*#user  abc;#g" /etc/nginx/nginx.conf
sed -i "s#user = nobody.*#user = abc#g" /etc/php82/php-fpm.d/www.conf
sed -i "s#group = nobody.*#group = abc#g" /etc/php82/php-fpm.d/www.conf

msg "Set ownership to the configuration files..."
chown -R abc:abc /config

msg "Start supervisord..."
supervisord -c /etc/supervisor/conf.d/supervisord.conf
