# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

class VirtualMachine < ArvadosBase
  attr_accessor :current_user_logins

  def self.creatable?
    false
  end

  def attributes_for_display
    super.append ['current_user_logins', @current_user_logins]
  end

  def editable_attributes
    super - %w(current_user_logins)
  end

  def self.attribute_info
    merger = ->(k,a,b) { a.merge(b, &merger) }
    merger [nil,
            {current_user_logins: {column_heading: "logins", type: 'array'}},
            super]
  end

  def friendly_link_name lookup=nil
    (hostname && !hostname.empty?) ? hostname : uuid
  end
end
