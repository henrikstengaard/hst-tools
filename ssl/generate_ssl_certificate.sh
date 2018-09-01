#/bin/bash

BITS=2048
EXPIREDAYS=1825

# prompt for domain name
read -p "Enter domain name: " DOMAIN

# create base domain and alt names
BASEDOMAIN="$DOMAIN"
ALTNAMES=""
if echo "$DOMAIN" | grep -e '^\*\.' > /dev/null; then
    BASEDOMAIN="`echo $DOMAIN | sed -e 's/^\*\.//'`"
    ALTNAMES="DNS.$(echo "$ALTNAMES" | wc -l) = $BASEDOMAIN"$'\n'
fi
ALTNAMES="$ALTNAMES""DNS.$(echo "$ALTNAMES" | wc -l) = $DOMAIN"$'\n'

# create base domain directory
if [ ! -d "$BASEDOMAIN" ]; then
    mkdir "$BASEDOMAIN"
fi

# create openssl.cfg
OPENSSLFILE="$BASEDOMAIN/openssl.cfg"
if [ ! -f "$OPENSSLFILE" ]; then
    sed -e "s/\[\$Domain\]/$DOMAIN/ig" -e "s/\[\$AltNames\]//ig" "openssl.cfg" >"$OPENSSLFILE"
    echo "$ALTNAMES" >>"$OPENSSLFILE"
fi

# create root ca private key file
CAKEYFILE="$BASEDOMAIN/$BASEDOMAIN root ca.key"
if [ ! -f "$CAKEYFILE" ]; then
    openssl genrsa -out "$CAKEYFILE" $BITS
fi

# create root ca certificate
CACERFILE="$BASEDOMAIN/$BASEDOMAIN root ca.cer"
if [ ! -f "$CACERFILE" ]; then
    openssl req -x509 -sha256 -new -key "$CAKEYFILE" -out "$CACERFILE" -days $EXPIREDAYS -subj /CN="$BASEDOMAIN root ca" -config "$OPENSSLFILE"
fi

# create domain private key file
DOMAINKEYFILE="$BASEDOMAIN/$BASEDOMAIN domain.key"
if [ ! -f "$DOMAINKEYFILE" ]; then
    openssl genrsa -out "$DOMAINKEYFILE" $BITS
fi

# create domain certificate signing request
DOMAINCSRFILE="$BASEDOMAIN/$BASEDOMAIN domain.csr"
if [ ! -f "$DOMAINCSRFILE" ]; then
    openssl req -new -out "$DOMAINCSRFILE" -key "$DOMAINKEYFILE" -subj /CN="$DOMAIN" -config "$OPENSSLFILE"
fi

# create domain certificate
DOMAINCERFILE="$BASEDOMAIN/$BASEDOMAIN domain.cer"
if [ ! -f "$DOMAINCERFILE" ]; then
    openssl x509 -req -sha256 -in "$DOMAINCSRFILE" -out "$DOMAINCERFILE" -CAkey "$CAKEYFILE" -CA "$CACERFILE" -CAcreateserial -CAserial "$BASEDOMAIN/$BASEDOMAIN domain.serial" -days $EXPIREDAYS -extfile "$OPENSSLFILE" -extensions v3_req
fi

# create personal information exchange for iis
DOMAINPFXFILE="$BASEDOMAIN/$BASEDOMAIN domain.pfx"
if [ ! -f "$DOMAINPFXFILE" ]; then
    openssl pkcs12 -export -out "$DOMAINPFXFILE" -inkey "$DOMAINKEYFILE" -in "$DOMAINCERFILE" -name "$BASEDOMAIN domain" -password "pass:$BASEDOMAIN"
fi

# copy import certificates
cp "import-certificates.ps1" "$BASEDOMAIN"
sed -e "s/\[\$BaseDomain\]/$BASEDOMAIN/ig" "import-certificates.cmd" >"$BASEDOMAIN/import-certificates.cmd"