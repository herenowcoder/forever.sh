#!/bin/bash
#
# (c) 2014-2017 Wojciech Kaczmarek. All rights reserved.
# Released under the BSD 2-clause license - see this for details:
# http://github.com/wkhere/forever.sh/blob/master/LICENSE

# see http://superuser.com/a/781762/20912

stepfile="./.forever.step"

err() {
    echo "$1" >&2; exit 1
}

blue() {
    echo $'\e[34m'${1}$'\e[0m' >&2
}

log() {
    blue "[forever.sh $1 `date +%H:%M:%S`]"
}

discover_project() {
    if [ -r setup.py ]; then echo "project_py"; return 0; fi
    gocount=$(find . -type f -name '*.go' 2>/dev/null | wc -l)
    if [ $gocount -gt 0 ]; then echo "project_go"; return 0; fi
    mix deps >/dev/null 2>&1
    if [ $? -eq 0 ]; then echo "project_mix"; return 0; fi
    return 1
}

project_py() {
cat <<'EOT'
#!/bin/bash -e
# script used by https://github.com/wkhere/forever.sh tool

if [ "$1" == files ]; then
    find . -type f -name '*.py'
    exit
fi

exec make $@
EOT
}

project_go() {
cat <<'EOT'
#!/bin/bash -e
# script used by https://github.com/wkhere/forever.sh tool

if [ "$1" == files ]; then
    find . -type f -name '*.go'
    exit
fi

exec make $@
EOT
}

project_mix() {
    cat <<'EOT'
#!/bin/bash -e
# script used by https://github.com/wkhere/forever.sh tool

if [ "$1" == files ]; then
    find lib test *.exs -type f -name '*.ex*'
    exit
fi

[ -z "$1" ] && set -- "test"

echo -n "Compiling dev.. "; time mix compile

[[ $1 == com* ]] && exit
[[ $1 == doc* ]] && mix docs
[[ $1 == dia* ]] && time nice mix dialyze --no-check  --error-handling --race-co
if [[ $1 == cov* ]]; then
    echo -n "Running coverage.. "
    shift
    if [ -z "$@" ]; then
        MIX_ENV=test mix coveralls
    else
        MIX_ENV=test mix coveralls.detail $@
    fi
fi
if [[ $1 == test ]]; then
    shift
    echo -n "Running tests.. "; mix test $@
fi
EOT
}

if [ ! -x "$stepfile" ]; then
    echo -n "Discovering project type... "
    guess=`discover_project`
    [ $? -ne 0 ] && err "$stepfile not found and couldn't guess project type"
    $guess > $stepfile
    [ $? -ne 0 ] && err "couldn't find $guess function in my script"
    chmod a+x $stepfile
    echo "$guess. Created $stepfile."
fi

export TIMEFORMAT=$'\e[34m''[%2Us user  %2Ss sys  %P%% cpu  %Rs total]'$'\e[0m'

case `uname` in
Linux)
    which inotifywait >/dev/null || err "you need 'inotifywait' command (apt-get install inotify-tools  or similar)"
    log started
    while true; do
        time $stepfile $@
        $stepfile files | xargs inotifywait -q -e modify
        [ $? -eq 130 ] && exit 130
        log awakened
    done
    ;;
Darwin)
    which fswatch >/dev/null || err "you need 'fswatch' command (brew install fswatch)"
    log started
    time $stepfile $@
    $stepfile files | xargs fswatch -x | while read x; do
        if [ `echo $x | grep -cE Attribute` -eq 0 ]; then
            log awakened
            time $stepfile $@
        fi
    done
    ;;
FreeBSD)
    err $'FreeBSD not supported. Please donate access to a box with one.\nContact via Github Issues.'
    ;;
esac
