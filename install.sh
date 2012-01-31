#!/bin/sh

DIR=$(dirname $0)
YLOOKUP=ylookup.rb

RUBYPREFIX="/usr/lib"
[ -d "/usr/lib64/ruby/site_ruby/1.8/" ] && RUBYPREFIX="/usr/lib64"
[ -d "/opt/lib/ruby/site_ruby/1.8/" ] && RUBYPREFIX="/opt/lib"
[ -d "/opt/lib64/ruby/site_ruby/1.8/" ] && RUBYPREFIX="/opt/lib64"

RUBYSUFFIX="/ruby/site_ruby/1.8/puppet/parser/functions/"
RUBYPATH=${RUBYPREFIX}${RUBYSUFFIX}

if [ -x /usr/bin/install ] ; then
    install -v --mode=0644 --owner=root --group=root $DIR/$YLOOKUP ${RUBYPATH}/ylookup.rb
else
    cp -v $DIR/$YLOOKUP ${RUBYPATH}/ylookup.rb
    chown -c root:root ${RUBYPATH}/ylookup.rb
fi
