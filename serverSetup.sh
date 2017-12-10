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

install_mongoose() {
    apt-get install -y python-setuptools
    # attention: version should not be later than 2.7.2
    easy_install pymongo==2.7.2
    apt-get install -y python-openssl
    if [ ! -e sleepy.mongoose ]; then
        git clone https://github.com/mongodb-labs/sleepy.mongoose
        f=sleepy.mongoose/sleepymongoose/httpd.py
        sed -i "s/HTTPServer((''/HTTPServer(('127.0.0.1'/g" $f
    fi
    f=/lib/systemd/system/mongoose.service
    > $f
    echo "[Unit]" >> $f
    echo "Description=MongoDB REST Interface" >> $f
    echo "After=mongodb.service" >> $f
    echo "" >> $f
    echo "[Service]" >> $f
    echo "ExecStart=/usr/bin/python /home/dab/sleepy.mongoose/httpd.py" >> $f
    echo "Restart=always" >> $f
    echo "" >> $f
    echo "[Install]" >> $f
    echo "WantedBy=multi-user.target" >> $f
    systemctl daemon-reload
    systemctl enable mongoose
    systemctl start mongoose
}

install() {
    #install ssl
    apt-get install -y openssl

    #install mail server
    apt-get install -y exim4

    #install source control management
    apt-get install -y git

    #install object store
    apt-get install -y mongodb

    #install rest interface
    install_mongoose

    #install web server
    apt-get install -y lighttpd
    apt-get install -y apache2-utils
    apt-get install -y pwgen

    #install node package manager
    add_nodesource_pkgsrv
    apt-get install -y nodejs

    #install munin
    apt-get install -y munin munin-node
}

configure_munin_for_mongodb() {
    git clone https://github.com/comerford/mongo-munin
    plugin_dir=/usr/share/munin/plugins
    cp mongo-munin/mongo_* $plugin_dir
    chmod +x $plugin_dir/mongo_*
    plugins="$(ls -1 $plugin_dir | grep mongo_)"
    cd /etc/munin/plugins
    for p in $plugins; do
        if [ ! -e $p ]; then
            ln -s $plugin_dir/$p
        fi
    done
    cd -
    systemctl restart munin-node
    rm -rf mongo-munin
}

configure_munin() {
    d=/var/www/html/munin
    if [ ! -e $d ]; then
        ln -s /var/cache/munin/www $d
    fi
    f=/etc/munin/munin-node.conf
    sed -i 's/localhost\.localdomain/dabserver/g' $f
    sed -i 's/#host_name/host_name/g' $f
    systemctl restart munin-node
    f=/etc/munin/munin.conf
    sed -i 's/\[localhost\.localdomain\]/[dabserver]/g' $f
}

configure_ssl_key() {
    archive=ssl_keys.tar.gz
    destDir=/etc/lighttpd
    if [ ! -e $archive ]; then
        openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -days 365 -nodes -sha256 -subj "/C=DE/ST=Berlin/L=Berlin/O=dab/OU=dab/CN=dabserver.de"
        tar cvfz $archive key.pem cert.pem
    else
        tar xvfz $archive
    fi
    if [ ! -e $destDir/server.pem ]; then
        cat key.pem cert.pem > server.pem
        rm key.pem cert.pem
        mv server.pem $destDir
    fi
}

configure_lighttpd() {
    # create server proxy
    k=/etc/lighttpd/api.user
    > $k
    htpasswd -b $k admin admin
    f=/etc/lighttpd/conf-available/99-dabserver.conf
    > $f
    echo "\$HTTP[\"url\"] =~ \"^/api\" {" >> $f
    echo "proxy.server = (\"\" => ((\"host\" => \"127.0.0.1\", \"port\" => \"27080\")))" >> $f
    echo "auth.backend = \"htpasswd\"" >> $f
    echo "auth.backend.htpasswd.userfile = \"/etc/lighttpd/api.user\"" >> $f
    echo "auth.require = (\"\" => (\"method\" => \"basic\", \"realm\" => \"admin\", \"require\" => \"valid-user\"))" >> $f
    echo "}" >> $f
    cd /etc/lighttpd/conf-enabled
    if [ ! -e 10-proxy.conf ]; then
        ln -s ../conf-available/10-proxy.conf
    fi
    if [ ! -e 99-dabserver.conf ]; then
        ln -s ../conf-available/99-dabserver.conf
    fi
    if [ ! -e 05-auth.conf ]; then
        ln -s ../conf-available/05-auth.conf
    fi
    if [ ! -e 10-ssl.conf ]; then
        ln -s ../conf-available/10-ssl.conf
    fi
    cd -
    systemctl restart lighttpd
}

# check if ssh key or ssh archive exists, else create new ssh key
configure_ssh_key() {
    destDir=/home/dab/.ssh
    keyFile=$destDir/id_rsa
    archiveFile=sshkey.tar.gz
    mkdir -p $destDir
    chown dab:dab $destDir
    if [ -e $keyFile ]; then
        return
    fi
    if [ ! -e $archiveFile ]; then
        su -c "ssh-keygen -f $keyFile -N \"\"" - dab
        tar -C $destDir -cvzf $archiveFile id_rsa id_rsa.pub authorized_keys
        echo "SSH Key has been created. Please do not forget to copy the archive file to a secure place."
    else
        tar -xvzf $archiveFile -C $destDir
    fi
    # TODO: send archive via mail or something similar
}

configure_sys() {
    configure_ssh_key
    configure_ssl_key
    configure_lighttpd
    #TODO: redirect from http to https
    #TODO: lighttpd: prevent webserver from serving everything starting with .
    configure_munin
    configure_munin_for_mongodb
    #TODO: mail
    #TODO: mongodb: create db
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
