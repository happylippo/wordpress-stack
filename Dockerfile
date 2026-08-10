ARG WORDPRESS_IMAGE=wordpress:php8.3-apache
FROM ${WORDPRESS_IMAGE}

RUN a2enmod remoteip
