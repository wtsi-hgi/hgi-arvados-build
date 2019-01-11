# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

module VersionHelper
  # Get the source_version given in the API server's discovery
  # document.
  def api_source_version
    arvados_api_client.discovery[:source_version]
  end

  # URL for browsing source code for the given version.
  def version_link_target version
    "https://arvados.org/projects/arvados/repository/changes?rev=#{version.sub(/-.*/, "")}"
  end
end
