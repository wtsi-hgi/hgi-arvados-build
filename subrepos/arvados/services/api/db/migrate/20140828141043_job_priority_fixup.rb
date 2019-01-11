# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class JobPriorityFixup < ActiveRecord::Migration
  def up
    remove_column :jobs, :priority
    add_column :jobs, :priority, :integer, null: false, default: 0
  end

  def down
    remove_column :jobs, :priority
    add_column :jobs, :priority, :string, null: true, default: nil
  end
end
