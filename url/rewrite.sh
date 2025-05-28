#!/bin/bash
version=0.0.0A

rewrites=()
rewritten=0

addrewrite() {
    name=$1
    rewrites+=("$name")
    ((rewritten++))
}

while read urlS; do
    url=$(echo "$urlS" | sed 's/\?/\?/' | cut -d' ' -f1)
    uri=$url

    if [[ "$url" =~ ^(https?://)?(www\.)?google\.com(:[0-9]+)?.* ]]; then
        if [[ "$url" != *"udm=14"* ]]; then
            uri="${url}&udm=14"
            addrewrite "google.com/search"
        fi
    fi

    IFS=", "
    status="?"
    rewritesString="${rewrites[@]}"

    if [ ${#rewrites[@]} -eq 0 ]; then
        rewritesString="none"
    fi

    if [[ $rewritten -gt 0 ]]; then
        status="!"
    fi

    echo "[$status] ($version) rewrite \"$urlS\" to \"$uri\" (rewrites (${#rewrites[@]}): $rewritesString)" >> /var/www/home/logs/rewrite.log
    echo "$uri"
done
