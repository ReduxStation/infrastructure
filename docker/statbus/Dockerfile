FROM php:7.4-fpm-bullseye

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        unzip \
        zip \
        libbz2-dev \
    && docker-php-ext-install -j$(nproc) pdo_mysql bz2 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Install dependencies before copying source for better layer caching.
COPY slimbus/composer.json ./
RUN composer install \
        --no-dev \
        --no-interaction \
        --no-ansi \
        --no-scripts

COPY slimbus/ .

# Generate the optimized classmap now that application source is in place.
RUN composer dump-autoload --optimize --no-interaction --no-ansi

RUN mkdir -p tmp/twig \
    && chown -R www-data:www-data /var/www/html/tmp /var/www/html/public \
    && chmod -R ug+rwX /var/www/html/tmp

COPY docker/statbus/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 9000

ENTRYPOINT ["/entrypoint.sh"]
CMD ["php-fpm"]
