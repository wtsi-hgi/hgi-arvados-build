# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

# Load the rails application
require File.expand_path('../application', __FILE__)
require 'josh_id'

# Initialize the rails application
Server::Application.initialize!
