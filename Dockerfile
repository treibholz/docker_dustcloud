FROM alpine

RUN apk update \
    # only for build miio
    && apk add --no-cache --virtual .build-deps \
    build-base \
    python3-dev \
    && apk add --no-cache \
    apache2 \
    curl \
    git \
    libcap \
    libffi-dev \
    linux-headers \
    openssl-dev \
    php7 \
    php7-apache2 \
    php7-mysqli \
    php7-mbstring \
    php7-phar \
    php7-json \
    py-bottle \
    py-mysqldb \
    py-pillow \
    py-pip \
    python3 \
    tzdata \
    && pip3 install python-miio \
    pymysql \
    && apk del .build-deps \
    && rm -f /var/cache/apk/*


###########################################################################
# Copy dustcloud Data
ENV WWWDATA /var/www/localhost/htdocs
ENV DUSTCLOUD /dustcloud
ENV GITDIR /gitdata
RUN git clone --depth 1 https://github.com/dgiese/dustcloud.git $GITDIR \
    && cp -r $GITDIR/dustcloud/www/* $WWWDATA \
    && mkdir $DUSTCLOUD \
    && cp $GITDIR/devices/xiaomi.vacuum.gen1/mapextractor/extractor.py $DUSTCLOUD/map_extractor.py \
    && cp $GITDIR/dustcloud/server.py $DUSTCLOUD/server.py.master \
    && cp $GITDIR/dustcloud/build_map.py $DUSTCLOUD/build_map.py \
    && echo 'su -c "python3 $DUSTCLOUD/server.py --enable-live-map" -s /bin/sh - apache' > $DUSTCLOUD/server.sh \
    && chmod +x $DUSTCLOUD/server.sh \
    && echo "<?php phpinfo(); ?>" > $WWWDATA/info.php \
    && rm -rf $GITDIR \
    && rm $WWWDATA/index.html

# Change vars in server.py.master
RUN sed -i -e "s/pymysql.connect(\"localhost\", \"dustcloud\", \"\", \"dustcloud\")/pymysql.connect(\"{{MYSQLSERVER}}\",\"{{MYSQLUSER}}\",\"{{MYSQLPW}}\",\"{{MYSQLDB}}\")/g" $DUSTCLOUD/server.py.master \
    && sed -i -e "s/my_cloudserver_ip = \"10.0.0.1\"/my_cloudserver_ip = \"{{CLOUDSERVERIP}}\"/g" $DUSTCLOUD/server.py.master \
    && sed -i -e "s/cmd_server.run(host=\"localhost\", port=cmd_server_port)/cmd_server.run(host=\"0.0.0.0\", port={{CMDSERVER_PORT}})/g" $DUSTCLOUD/server.py.master \
    && sed -i -e "s/cloud_server_address = ('ott.io.mi.com', 80)/cloud_server_address = ('{{CLOUD_SERVER_ADDRESS}}', 80)/g" $DUSTCLOUD/server.py.master

# Customization for dustcloud database connection in php
RUN sed -i -e "s/'host' => 'localhost',/'host' => '{{MYSQLSERVER}}',/g" $WWWDATA/conf.sample.php \
    && sed -i -e "s/'username' => 'user123',/'username' => '{{MYSQLUSER}}',/g" $WWWDATA/conf.sample.php \
    && sed -i -e "s/'password' => '',/'password' => '{{MYSQLPW}}',/g" $WWWDATA/conf.sample.php \
    && sed -i -e "s/'database' => 'dustcloud',/'database' => '{{MYSQLDB}}',/g" $WWWDATA/conf.sample.php \
    && sed -i -e "s/'cmd.server' => 'http:\/\/localhost:1121\/',/'cmd.server' => 'http:\/\/{{CMDSERVER}}:{{CMDSERVER_PORT}}\/',/g" $WWWDATA/conf.sample.php

###########################################################################
# Install composer
RUN cd $WWWDATA \
    && curl https://raw.githubusercontent.com/composer/getcomposer.org/master/web/installer | php -- \
    && php composer.phar install

###########################################################################
# Customization for PHP and Apache
ENV APACHE_PORT 81

RUN mkdir /run/apache2 \
    && sed -i -e "s/Listen 80/Listen ${APACHE_PORT}/g" /etc/apache2/httpd.conf \
    && sed -i -e "s/error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT/error_reporting = E_ALL/g" /etc/php7/php.ini \
    && sed -i -e "s/display_errors = Off/display_errors = On/g" /etc/php7/php.ini \
    && sed -i -e "s@;date.timezone =@date.timezone = \"{{TZ}}\"@g" /etc/php7/php.ini

# allow python to bind ports < 1024
RUN setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/python3.6



###########################################################################
# Start script
RUN mkdir /bootstrap
ADD start.sh /bootstrap/
RUN chmod +x /bootstrap/start.sh

WORKDIR $DUSTCLOUD

EXPOSE 80/tcp
EXPOSE 81/tcp
EXPOSE 8053/udp
EXPOSE 1121/tcp

CMD ["/bootstrap/start.sh"]

# Build-time metadata as defined at http://label-schema.org
ENV VERSION v1.3.3
ARG BUILD_DATE
ARG VCS_REF
ARG BRANCH
LABEL org.label-schema.build-date=$BUILD_DATE \
      org.label-schema.name="dustcloud" \
      org.label-schema.description="Image for Xiaomi Mi Robot Vacuum dustcloud project (https://github.com/dgiese/dustcloud)" \
      org.label-schema.url="https://github.com/JackGruber/docker_dustcloud" \
      org.label-schema.vcs-ref=$VCS_REF \
      org.label-schema.vcs-url="https://github.com/JackGruber/docker_dustcloud.git" \
      org.label-schema.version="$BRANCH $VERSION" \
      org.label-schema.schema-version="1.0"
