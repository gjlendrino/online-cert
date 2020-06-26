#!/bin/bash
set -e


if [ "$#" -eq 2 ]; then
  if [ "$1" == "test" ]; then
    DIR=test-req-online-cert
    TYPE=$1
    DOMAIN=$2
  else
    echo "Usage: $0 test domain-name"
    echo "Usage: $0 request domain-name contact-email"
    exit -1
  fi
elif [ "$#" -eq 3 ]; then
  if [ "$1" == "request" ]; then
    TYPE=$1
    DOMAIN=$2
    EMAIL=$3
    DIR=req-online-cert
  else
    echo "Usage: $0 test domain-name"
    echo "Usage: $0 request domain-name contact-email"
    exit -1
  fi
else
  echo "Usage: $0 test domain-name"
  echo "Usage: $0 request domain-name contact-email"
  exit -1
fi

rm -Rf $DIR
mkdir $DIR
cd $DIR

mkdir nginx
mkdir nginx/conf.d
tee nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        root   /usr/share/nginx/html;
        index  index.html index.htm;
    }
    location ~ /.well-known/acme-challenge {
        allow all;
        root /usr/share/nginx/html;
    }
}
EOF
tee docker-compose.yml <<EOF
version: '3.1'
services:
  nginx:
    container_name: nginx
    image: nginx
    ports:
      - 80:80
    volumes:
      - ./nginx/conf.d/default.conf:/etc/nginx/conf.d/default.conf
EOF
docker-compose up -d
mkdir certbot
mkdir certbot/etc
mkdir certbot/lib
mkdir certbot/log
read -p "Press any key to continue ..."

if [ "$TYPE" == "test" ]; then
  docker run -it --rm \
  -u $(id -u):$(id -g) \
  -v $PWD/certbot/etc:/etc/letsencrypt \
  -v $PWD/certbot/lib:/var/lib/letsencrypt \
  -v $PWD/certbot/log:/var/log/letsencrypt \
  -v $PWD/letsencrypt-site:/data/letsencrypt \
  certbot/certbot \
  certonly --webroot \
  --register-unsafely-without-email --agree-tos \
  --webroot-path=/data/letsencrypt \
  --staging \
  -d $DOMAIN
  #Saving debug log to /var/log/letsencrypt/letsencrypt.log
  #Plugins selected: Authenticator webroot, Installer None
  #Registering without email!
  #Obtaining a new certificate
  #Performing the following challenges:
  #http-01 challenge for <DOMAIN>
  #Using the webroot path /data/letsencrypt for all unmatched domains.
  #Waiting for verification...
  #Cleaning up challenges
  #
  #IMPORTANT NOTES:
  # - Congratulations! Your certificate and chain have been saved at:
  #   /etc/letsencrypt/live/<DOMAIN>/fullchain.pem
  #   Your key file has been saved at:
  #   /etc/letsencrypt/live/<DOMAIN>/privkey.pem
  #   Your cert will expire on <DATE>. To obtain a new or tweaked
  #   version of this certificate in the future, simply run certbot
  #   again. To non-interactively renew *all* of your certificates, run
  #   "certbot renew"
  # - Your account credentials have been saved in your Certbot
  #   configuration directory at /etc/letsencrypt. You should make a
  #   secure backup of this folder now. This configuration directory will
  #   also contain certificates and private keys obtained by Certbot so
  #   making regular backups of this folder is ideal.
  cd ..
  echo
  echo "If the staging command executed successfully stop the containers: docker rm -f letsencrypt-nginx-container"
  echo "Then execute the script with 'request' argument"
else
  docker run -it --rm \
  -u $(id -u):$(id -g) \
  -v $PWD/certbot/etc:/etc/letsencrypt \
  -v $PWD/certbot/lib:/var/lib/letsencrypt \
  -v $PWD/certbot/log:/var/log/letsencrypt \
  -v $PWD/letsencrypt-site:/data/letsencrypt \
  certbot/certbot \
  certonly --webroot \
  --email $EMAIL --agree-tos --no-eff-email \
  --webroot-path=/data/letsencrypt \
  -d $DOMAIN
  #Saving debug log to /var/log/letsencrypt/letsencrypt.log
  #Plugins selected: Authenticator webroot, Installer None
  #Obtaining a new certificate
  #Performing the following challenges:
  #http-01 challenge for <DOMAIN>
  #Using the webroot path /data/letsencrypt for all unmatched domains.
  #Waiting for verification...
  #Cleaning up challenges
  #
  #IMPORTANT NOTES:
  # - Congratulations! Your certificate and chain have been saved at:
  #   /etc/letsencrypt/live/<DOMAIN>/fullchain.pem
  #   Your key file has been saved at:
  #   /etc/letsencrypt/live/<DOMAIN>/privkey.pem
  #   Your cert will expire on <DATE>. To obtain a new or tweaked
  #   version of this certificate in the future, simply run certbot
  #   again. To non-interactively renew *all* of your certificates, run
  #   "certbot renew"
  # - Your account credentials have been saved in your Certbot
  #   configuration directory at /etc/letsencrypt. You should make a
  #   secure backup of this folder now. This configuration directory will
  #   also contain certificates and private keys obtained by Certbot so
  #   making regular backups of this folder is ideal.
  # - If you like Certbot, please consider supporting our work by:
  #
  #   Donating to ISRG / Let's Encrypt:   https://letsencrypt.org/donate
  #   Donating to EFF:                    https://eff.org/donate-le
  echo
  echo "If the command executed successfully stop the containers: docker rm -f letsencrypt-nginx-container"
  cd ..
  mkdir -p ./certs/online
  cp $DIR/certbot/etc/live/$DOMAIN/fullchain.pem ./certs/online
  cp $DIR/certbot/etc/live/$DOMAIN/privkey.pem ./certs/online
  echo "ssl_certificate is located in ../certs/online/fullchain.pem"
  echo "ssl_certificate_key is located in ../certs/online/privkey.pem"
  echo "Copy the following lines to the server block listening in the 80 port"
  echo "location ~ /.well-known/acme-challenge {"
  echo "  allow all;"
  echo "  root /usr/share/nginx/html;"
  echo "}"
  echo "Add a crontab with the following line:"
  echo "0 23 * * * docker run --rm -it --name certbot -v $PWD/certbot/etc:/etc/letsencrypt -v $PWD/certbot/lib:/var/lib/letsencrypt -v $PWD/certbot/log:/var/log/letsencrypt -v $PWD/letsencrypt-site:/data/letsencrypt certbot/certbot renew --webroot -w /data/letsencrypt --quiet && 
  docker kill --signal=HUP production-nginx-container"
fi
