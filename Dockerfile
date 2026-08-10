ARG WORDPRESS_IMAGE=wordpress:php8.3-apache
FROM ${WORDPRESS_IMAGE}

RUN a2enmod remoteip

COPY docker-entrypoint-realip.sh /usr/local/bin/docker-entrypoint-realip.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-realip.sh

ENTRYPOINT ["docker-entrypoint-realip.sh"]
CMD ["apache2-foreground"]
