#!/bin/bash

set -u
set -e
set -n
set -x

WEB_PROJECT_DIR_NAME=website
WEB_PROJECT_GIT_REPO=git@gitlab.com:foo/${WEB_PROJECT_DIR_NAME}.git
HTTPD_DOCROOT_PARENT=/var/www

install() {
    #install source control management
    apt-get install -y git

    #install object store
    apt-get install -y mongodb

    #install web server
    apt-get install -y lighttpd

    #install node package manager
    apt-get install -y npm

    #install munin
    apt-get install -y munin munin-node
}

configure() {
    #TODO: git: generate ssh key
    #TODO: lighttpd: prevent webserver from serving everything starting with .
    #TODO: munin: configure munin node hostname
    #TODO: mongodb: basic configuration
    #TODO: cron: set up new Cronjob for data evaluation script
    #TODO: cron: set up Cronjob for db backup
    return
}

deploy() {
    cd $HTTPD_DOCROOT_PARENT
    if [ ! -d $WEB_PROJECT_DIR_NAME ]; then
        git clone $WEB_PROJECT_GIT_REPO
    fi
    if [ -e dist ]; then
        mv dist dist_original
    fi
    ln -s $WEB_PROJECT_DIR_NAME dist
    systemctl restart lighttpd
}

usage() {
    echo "USAGE: $0 <cmd>"
    echo ""
    echo "commands: "
    echo ""
    echo "install               install dependencies (requires root access)"
    echo "configure             configure installed components"
    echo "deploy                deploy artifacts"
}

main() {
    cmd="$1"
    case $cmd in
        "install")
            if [ $UID != 0 ]; then
                echo "ERROR. Must be run as root."
                exit 1
            fi
            install
            ;;
        "configure")
            configure
            ;;
        "deploy")
            deploy
            ;;
        *)
            usage
            exit 1
            ;;
    esac
}

if [ $# == 0 ]; then
    usage
    exit 1
fi

main $@
