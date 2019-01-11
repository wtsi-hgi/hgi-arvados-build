#!/bin/sh
# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

# This code runs after package variable definitions and step2.sh.

remove () {
  rm -f $RELEASE_PATH/config/database.yml
  rm -f $RELEASE_PATH/config/environments/production.rb
  rm -f $RELEASE_PATH/config/application.yml
  # Old API server configuration file.
  rm -f $RELEASE_PATH/config/initializers/omniauth.rb
  rm -rf $RELEASE_PATH/public/assets/
  rm -rf $RELEASE_PATH/tmp
  rm -rf $RELEASE_PATH/.bundle
  rm -rf $RELEASE_PATH/log
}

if [ "$1" = 'remove' ]; then
  # This is a debian-based system and removal was requested
  remove
elif [ "$1" = "0" ] || [ "$1" = "1" ] || [ "$1" = "2" ]; then
  # This is an rpm-based system
  remove
fi
