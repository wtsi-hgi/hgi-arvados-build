# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'integration_helper'

class FilterableInfiniteScrollTest < ActionDispatch::IntegrationTest
  setup do
    need_javascript
  end

  # Chrome remembers what you had in the text field when you hit
  # "back". Here, we simulate the same effect by sending an otherwise
  # unused ?search=foo param to pre-populate the search field.
  test 'no double-load if text input has a value at page load time' do
    visit page_with_token('admin', '/pipeline_instances')
    assert_text 'pipeline_with_job'
    visit page_with_token('admin', '/pipeline_instances?search=pipeline_with_tagged')
    # Horrible hack to ensure the search results can't load correctly
    # on the second attempt.
    assert_selector '#recent-pipeline-instances'
    assert page.evaluate_script('$("#recent-pipeline-instances[data-infinite-content-href0]").attr("data-infinite-content-href0","/give-me-an-error").length == 1')
    # Wait for the first page of results to appear.
    assert_text 'pipeline_with_tagged_collection_input'
    # Make sure the results are filtered.
    assert_no_text 'pipeline_with_job'
    # Make sure pipeline_with_job didn't disappear merely because
    # the results were replaced with an error message.
    assert_text 'pipeline_with_tagged_collection_input'
  end
end
