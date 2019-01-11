# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'integration_helper'

# The tests in the "integration_performance" dir are not included in regular
#   build pipeline since it is not one of the "standard" test directories.
#
# To run tests in this directory use the following command:
# ./run-tests.sh WORKSPACE=~/arvados --only apps/workbench apps/workbench_test="TEST=test/integration_performance/*.rb"
#

class CollectionsPerfTest < ActionDispatch::IntegrationTest
  setup do
    Capybara.current_driver = :rack_test
  end

  def create_large_collection size, file_name_prefix
    manifest_text = ". d41d8cd98f00b204e9800998ecf8427e+0"

    i = 0
    until manifest_text.length > size do
      manifest_text << " 0:0:#{file_name_prefix}#{i.to_s}"
      i += 1
    end
    manifest_text << "\n"

    Rails.logger.info "Creating collection at #{Time.now.to_f}"
    collection = Collection.create! ({manifest_text: manifest_text})
    Rails.logger.info "Done creating collection at #{Time.now.to_f}"

    collection
  end

  [
    1000000,
    10000000,
    20000000,
  ].each do |size|
    test "Create and show large collection with manifest text of #{size}" do
      use_token :active
      new_collection = create_large_collection size, 'collection_file_name_with_prefix_'

      Rails.logger.info "Visiting collection at #{Time.now.to_f}"
      visit page_with_token('active', "/collections/#{new_collection.uuid}")
      Rails.logger.info "Done visiting collection at #{Time.now.to_f}"

      assert_selector "input[value=\"#{new_collection.uuid}\"]"
      assert(page.has_link?('collection_file_name_with_prefix_0'), "Collection page did not include file link")
    end
  end

  # This does not work with larger sizes because of need_javascript.
  # Just use one test with 100,000 for now.
  [
    100000,
  ].each do |size|
    test "Create, show, and update description for large collection with manifest text of #{size}" do
      need_javascript

      use_token :active
      new_collection = create_large_collection size, 'collection_file_name_with_prefix_'

      Rails.logger.info "Visiting collection at #{Time.now.to_f}"
      visit page_with_token('active', "/collections/#{new_collection.uuid}")
      Rails.logger.info "Done visiting collection at #{Time.now.to_f}"

      assert_selector "input[value=\"#{new_collection.uuid}\"]"
      assert(page.has_link?('collection_file_name_with_prefix_0'), "Collection page did not include file link")

      # edit description
      Rails.logger.info "Editing description at #{Time.now.to_f}"
      within('.arv-description-as-subtitle') do
        find('.fa-pencil').click
        find('.editable-input textarea').set('description for this large collection')
        find('.editable-submit').click
      end
      Rails.logger.info "Done editing description at #{Time.now.to_f}"

      assert_text 'description for this large collection'
    end
  end

  [
    [1000000, 10000],
    [10000000, 10000],
    [20000000, 10000],
  ].each do |size1, size2|
    test "Create one large collection of #{size1} and one small collection of #{size2} and combine them" do
      use_token :active
      first_collection = create_large_collection size1, 'collection_file_name_with_prefix_1_'
      second_collection = create_large_collection size2, 'collection_file_name_with_prefix_2_'

      Rails.logger.info "Visiting collections page at #{Time.now.to_f}"
      visit page_with_token('active', "/collections")
      Rails.logger.info "Done visiting collections page at at #{Time.now.to_f}"

      assert_text first_collection.uuid
      assert_text second_collection.uuid

      within('tr', text: first_collection['uuid']) do
        find('input[type=checkbox]').click
      end

      within('tr', text: second_collection['uuid']) do
        find('input[type=checkbox]').click
      end

      Rails.logger.info "Clicking on combine collections option at #{Time.now.to_f}"
      click_button 'Selection...'
      within('.selection-action-container') do
        click_link 'Create new collection with selected collections'
      end
      Rails.logger.info "Done combining collections at #{Time.now.to_f}"

      assert(page.has_link?('collection_file_name_with_prefix_1_0'), "Collection page did not include file link")
    end
  end
end
