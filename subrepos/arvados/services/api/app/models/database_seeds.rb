# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class DatabaseSeeds
  extend CurrentApiClient
  def self.install
    system_user
    system_group
    all_users_group
    anonymous_group
    anonymous_group_read_permission
    anonymous_user
    empty_collection
  end
end
