# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class RemoveOutputIsPersistentColumn < ActiveRecord::Migration
  def up
    remove_column :jobs, :output_is_persistent
  end

  def down
    add_column :jobs, :output_is_persistent, :boolean, null: false, default: false
  end
end
