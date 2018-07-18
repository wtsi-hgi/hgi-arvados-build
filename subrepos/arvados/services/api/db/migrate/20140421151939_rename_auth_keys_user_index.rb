# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class RenameAuthKeysUserIndex < ActiveRecord::Migration
  # Rails' default name for this index is so long, Rails can't modify
  # the index later, because the autogenerated temporary name exceeds
  # PostgreSQL's 64-character limit.  This migration gives the index
  # an explicit name to work around that issue.
  def change
    rename_index("authorized_keys",
                 "index_authorized_keys_on_authorized_user_uuid_and_expires_at",
                 "index_authkeys_on_user_and_expires_at")
  end
end