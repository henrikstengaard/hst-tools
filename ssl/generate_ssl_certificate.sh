#/bin/bash

DOMAIN="*.firstoncloud.com"

ALTNAMES=""

if echo "$DOMAIN" | grep -e '^\*\.' > /dev/null; then
    ALTNAMES="DNS.$(echo "$ALTNAMES" | wc -l) = `echo $DOMAIN | sed -e 's/^\*\.//'`"$'\n'
fi
ALTNAMES="$ALTNAMES""DNS.$(echo "$ALTNAMES" | wc -l) = $DOMAIN"$'\n'

echo "$ALTNAMES"

#	$altNames += "DNS.{0} = {1}" -f ($altNames.Count + 1), ($domain -replace '^\*.', '')
#}
#$altNames += "DNS.{0} = {1}" -f ($altNames.Count + 1), $domain
