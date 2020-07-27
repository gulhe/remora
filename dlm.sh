#!/usr/bin/env bash

function usage {
    echo "${1}'s usage:"
    echo "${1} {[ARG_NAME]=[ARG_VALUE]}... [GOAL] {[GOAL_OPTS]}"
    echo '---------------------'
    echo 'GOALS:'
    echo " - build : build's the image and stores it in the local-repo"
    echo ' - run   : (depends on `build`) runs a shell on the container of the built image'
    echo ' - test  : (depends on `build`) runs the tests on the container of the built image'
    echo ' - deploy: (depends on `test`) deploys the image in the repository'
    echo '---------------------'
    echo 'ARGS:'
    echo ' -c/--config: `(default: ./dlm.json)`'
    echo '    sets the location of the dlm configuration'
}

getopt --test > /dev/null
if [[ ${?} -ne 4 ]]; then
    echo "I’m sorry, `getopt --test` failed in this environment."
    exit 1
fi

OPTIONS=c:
LONGOPTS=config:

# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
PARSED=$(getopt --options=+${OPTIONS} --longoptions=${LONGOPTS} --name "$0" -- "$@")
if [[ ${?} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:

eval set -- "${PARSED}"

# now enjoy the options in order and nicely split
while true; do
    case "$1" in
        -c|--config)
            configFile="$2"
            shift 2
            ;;
        --)
            shift
            goal=$1
            shift
            break
            ;;
        *)
            usage $0
            exit 5
            ;;
    esac
done

remainingOptions=$@

function locateFileOrDefault {
    if [ -f "${1}" ] ; then
        echo ${1}
    else
        echo ${2}
    fi
}
function locateFileOrFail {
    if [ ! -f "${1}" ] ; then
        echo could not locate "[${1}]"
        exit 6
    fi
}

function locateConf {
    locateFileOrDefault "${1}" dlm.json
}

configFile=$(locateConf ${configFile})
locateFileOrFail ${configFile}

function readKey {
    jq -r ${1} ${2}
}
function readLocalConfKey {
    readKey ${1} ${configFile}
}
function readUserConfKey {
    readKey ${1} ~/.dlm.json
}

function readInString {
    echo $2 | jq -r ${1}
}

function readArray {
    jq -c ${1} ${configFile}
}

project_name=$(readLocalConfKey '.name')
project_group=$(readLocalConfKey '.group')
project_version=$(readLocalConfKey .version)
project_repository=$(readLocalConfKey .repository)
readarray -t project_tests < <(readArray '.tests[]')
project_tag="${project_group}/${project_name}:${project_version}"

USER_ID=$(readUserConfKey '.["'${project_repository}'"].user')
PWD=$(readUserConfKey '.["'${project_repository}'"].password')

function build {
    docker image build -t "${project_tag}" .
}
function run {
    build &&\
    docker container run -it "${project_tag}" sh
}
function doTest {
    build &&\
    for test in "${project_tests[@]}" ; do
        cmd=$(readInString '.cmd' "$test")
        expected=$(readInString '.expected' "$test")
        actual=$(docker container run "${project_tag}" ${cmd})
        if [ "${actual}" != "${expected}" ]; then
            echo "Test failed, expected [$cmd] to return [$expected] but got [$actual]"
            exit 12;
        else
            echo "Test [$cmd => $expected] passed."
        fi
    done
}
function deploy {
    doTest &&\
    echo  ${PWD} | docker login -u ${USER_ID} --password-stdin ${project_repository} &&\
    docker image push "${project_tag}"
}
case "${goal}" in
    build)
        build
        ;;
    run)
        run
        ;;
    test)
        doTest
        ;;
    deploy)
        deploy
        ;;
    *)
        usage $0
        ;;
esac

exit 0
