# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class AddDescriptionToPipelineInstancesAndJobs < ActiveRecord::Migration
  def up
    add_column :pipeline_instances, :description, :text, null: true
    add_column :jobs, :description, :text, null: true
  end

  def down
    remove_column :jobs, :description
    remove_column :pipeline_instances, :description
  end
end
