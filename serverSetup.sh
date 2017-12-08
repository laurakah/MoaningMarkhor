#!/bin/bash

set -u
set -e
#set -n
#set -x

WEB_PROJECT_DIR_NAME=website
WEB_PROJECT_GIT_REPO=git@gitlab.com:foo/${WEB_PROJECT_DIR_NAME}.git
HTTPD_DOCROOT_PARENT=/var/www

add_nodesource_pkgsrv() {
    wget https://deb.nodesource.com/gpgkey/nodesource.gpg.key
    apt-key add nodesource.gpg.key
    rm nodesource.gpg.key
    f=/etc/apt/sources.list.d/nodesource.list
    > $f
    echo "deb https://deb.nodesource.com/node_8.x stretch main" >> $f
    echo "deb-src https://deb.nodesource.com/node_8.x stretch main" >> $f
    apt-get install -y apt-transport-https
    apt-get update
}

install() {
    #install source control management
    apt-get install -y git

    #install object store
    apt-get install -y mongodb

    #install web server
    apt-get install -y lighttpd

    #install node package manager
    add_nodesource_pkgsrv
    apt-get install -y nodejs

    #install munin
    apt-get install -y munin munin-node
}

configure_munin() {
    d=/var/www/html/munin
    f=/etc/munin/munin-node.conf
    if [ ! -e $d ]; then
        ln -s /var/cache/munin/www $d
    fi
    sed -i 's/localhost\.localdomain/dabserver/g' $f
    sed -i 's/#host_name/host_name/g' $f
    systemctl restart munin-node
}

configure_lighttpd() {
    return
}

configure_sshkey() {
    f=/home/dab/.ssh/id_rsa
    if [ ! -e $f ]; then
        su -c "ssh-keygen -f $f -N \"\"" - dab
    fi
}

configure_sys() {
    #TODO: git: generate ssh key
    configure_sshkey
    #TODO: lighttpd: prevent webserver from serving everything starting with .
    #TODO: munin: configure munin node hostname
    configure_munin
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
    echo "configuresys          configure installed components"
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
        "configuresys")
            configure_sys
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
