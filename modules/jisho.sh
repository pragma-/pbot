#!/bin/bash
url=https://jisho.org/api/v1/search/words
n=1 w=()
while (( $# )); do
    case $1 in
        -n) shift; n=$1;;
        -n*) n=${1#-n};;
        -all) n=0;;
        *) w+=("$1");;
    esac
    shift
done
w=${w[*]}
if [[ $w ]]; then
    curl -fsSLG "$url" --data-urlencode "keyword=$w" |
    jq -r --arg w "$w" --argjson n "$n" '
        .data |
        length as $N |
        if $N == 0 then
            "\($w): word not found"
        else if $n > $N then
            "\($w): only \($N) definition\(if $N > 1 then "s" else "" end) available"
        else
            (if $n == 0 then range($N) else $n - 1 end) as $i |
            .[$i] |
            .japanese[0].reading as $r |
            .slug +
            if $r != .slug then " (\($r))" else "" end +
            " [\($i + 1)/\($N)]: " +
            (.senses | map(.english_definitions | join(", ")) | join("; "))
        end end'
else
    echo "usage: jisho [-n INDEX] WORD"
fi
