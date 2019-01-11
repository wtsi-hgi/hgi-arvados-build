# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'integration_helper'
require 'helpers/share_object_helper'
require_relative 'integration_test_utils'

class ProjectsTest < ActionDispatch::IntegrationTest
  include ShareObjectHelper

  setup do
    need_javascript
  end

  test 'Check collection count for A Project in the tab pane titles' do
    project_uuid = api_fixture('groups')['aproject']['uuid']
    visit page_with_token 'active', '/projects/' + project_uuid
    click_link 'Data collections'
    wait_for_ajax
    collection_count = page.all("[data-pk*='collection']").count
    assert_selector '#Data_collections-tab span', text: "(#{collection_count})"
  end

  test 'Find a project and edit its description' do
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: "A Project").click
    within('.container-fluid', text: api_fixture('groups')['aproject']['name']) do
      find('span', text: api_fixture('groups')['aproject']['name']).click
      within('.arv-description-as-subtitle') do
        find('.fa-pencil').click
        find('.editable-input textarea').set('I just edited this.')
        find('.editable-submit').click
      end
      wait_for_ajax
    end
    visit current_path
    assert(find?('.container-fluid', text: 'I just edited this.'),
           "Description update did not survive page refresh")
  end

  test 'Create a project and move it into a different project' do
    visit page_with_token 'active', '/projects'
    find("#projects-menu").click
    within('.dropdown-menu') do
      first('li', text: 'Home').click
    end
    wait_for_ajax
    find('.btn', text: "Add a subproject").click

    within('h2') do
      find('.fa-pencil').click
      find('.editable-input input').set('Project 1234')
      find('.glyphicon-ok').click
    end
    wait_for_ajax

    visit '/projects'
    find("#projects-menu").click
    within('.dropdown-menu') do
      first('li', text: 'Home').click
    end
    wait_for_ajax
    find('.btn', text: "Add a subproject").click
    within('h2') do
      find('.fa-pencil').click
      find('.editable-input input').set('Project 5678')
      find('.glyphicon-ok').click
    end
    wait_for_ajax

    click_link 'Move project...'
    find('.selectable', text: 'Project 1234').click
    find('.modal-footer a,button', text: 'Move').click
    wait_for_ajax

    # Wait for the page to refresh and show the new parent in Sharing panel
    click_link 'Sharing'
    assert(page.has_link?("Project 1234"),
           "Project 5678 should now be inside project 1234")
  end

  def open_groups_sharing(project_name="aproject", token_name="active")
    project = api_fixture("groups", project_name)
    visit(page_with_token(token_name, "/projects/#{project['uuid']}"))
    click_on "Sharing"
    click_on "Share with groups"
  end

  def group_name(group_key)
    api_fixture("groups", group_key, "name")
  end

  test "projects not publicly sharable when anonymous browsing disabled" do
    Rails.configuration.anonymous_user_token = false
    open_groups_sharing
    # Check for a group we do expect first, to make sure the modal's loaded.
    assert_selector(".modal-container .selectable",
                    text: group_name("all_users"))
    assert_no_selector(".modal-container .selectable",
                       text: group_name("anonymous_group"))
  end

  test "projects publicly sharable when anonymous browsing enabled" do
    Rails.configuration.anonymous_user_token = "testonlytoken"
    open_groups_sharing
    assert_selector(".modal-container .selectable",
                    text: group_name("anonymous_group"))
  end

  test "project owner can manage sharing for another user" do
    add_user = api_fixture('users')['future_project_user']
    new_name = ["first_name", "last_name"].map { |k| add_user[k] }.join(" ")

    show_object_using('active', 'groups', 'aproject', 'A Project')
    click_on "Sharing"
    add_share_and_check("users", new_name, add_user)
    modify_share_and_check(new_name)
  end

  test "project owner can manage sharing for another group" do
    new_name = api_fixture('groups')['future_project_viewing_group']['name']

    show_object_using('active', 'groups', 'aproject', 'A Project')
    click_on "Sharing"
    add_share_and_check("groups", new_name)
    modify_share_and_check(new_name)
  end

  test "'share with group' listing does not offer projects" do
    show_object_using('active', 'groups', 'aproject', 'A Project')
    click_on "Sharing"
    click_on "Share with groups"
    good_uuid = api_fixture("groups")["private"]["uuid"]
    assert(page.has_selector?(".selectable[data-object-uuid=\"#{good_uuid}\"]"),
           "'share with groups' listing missing owned user group")
    bad_uuid = api_fixture("groups")["asubproject"]["uuid"]
    assert(page.has_no_selector?(".selectable[data-object-uuid=\"#{bad_uuid}\"]"),
           "'share with groups' listing includes project")
  end

  [
    ['Move',api_fixture('collections')['collection_to_move_around_in_aproject'],
      api_fixture('groups')['aproject'],api_fixture('groups')['asubproject']],
    ['Remove',api_fixture('collections')['collection_to_move_around_in_aproject'],
      api_fixture('groups')['aproject']],
    ['Copy',api_fixture('collections')['collection_to_move_around_in_aproject'],
      api_fixture('groups')['aproject'],api_fixture('groups')['asubproject']],
    ['Remove',api_fixture('collections')['collection_in_aproject_with_same_name_as_in_home_project'],
      api_fixture('groups')['aproject'],nil,true],
  ].each do |action, my_collection, src, dest=nil, expect_name_change=nil|
    test "selection #{action} -> #{expect_name_change.inspect} for project" do
      perform_selection_action src, dest, my_collection, action

      case action
      when 'Copy'
        assert page.has_text?(my_collection['name']), 'Collection not found in src project after copy'
        visit page_with_token 'active', '/'
        find("#projects-menu").click
        find(".dropdown-menu a", text: dest['name']).click
        click_link 'Data collections'
        assert page.has_text?(my_collection['name']), 'Collection not found in dest project after copy'

      when 'Move'
        assert page.has_no_text?(my_collection['name']), 'Collection still found in src project after move'
        visit page_with_token 'active', '/'
        find("#projects-menu").click
        find(".dropdown-menu a", text: dest['name']).click
        click_link 'Data collections'
        assert page.has_text?(my_collection['name']), 'Collection not found in dest project after move'

      when 'Remove'
        assert page.has_no_text?(my_collection['name']), 'Collection still found in src project after remove'
      end
    end
  end

  def perform_selection_action src, dest, item, action
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: src['name']).click
    click_link 'Data collections'
    assert page.has_text?(item['name']), 'Collection not found in src project'

    within('tr', text: item['name']) do
      find('input[type=checkbox]').click
    end

    click_button 'Selection'

    within('.selection-action-container') do
      assert page.has_text?("Compare selected"), "Compare selected link text not found"
      assert page.has_link?("Copy selected"), "Copy selected link not found"
      assert page.has_link?("Move selected"), "Move selected link not found"
      assert page.has_link?("Remove selected"), "Remove selected link not found"

      click_link "#{action} selected"
    end

    # select the destination project if a Copy or Move action is being performed
    if action == 'Copy' || action == 'Move'
      within(".modal-container") do
        find('.selectable', text: dest['name']).click
        find('.modal-footer a,button', text: action).click
        wait_for_ajax
      end
    end
  end

  # Test copy action state. It should not be available when a subproject is selected.
  test "copy action is disabled when a subproject is selected" do
    my_project = api_fixture('groups')['aproject']
    my_collection = api_fixture('collections')['collection_to_move_around_in_aproject']
    my_subproject = api_fixture('groups')['asubproject']

    # verify that selection options are disabled on the project until an item is selected
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: my_project['name']).click

    click_link 'Data collections'
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li.disabled', text: 'Remove selected'
    end

    # select collection and verify links are enabled
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: my_project['name']).click
    click_link 'Data collections'
    assert page.has_text?(my_collection['name']), 'Collection not found in project'

    within('tr', text: my_collection['name']) do
      find('input[type=checkbox]').click
    end

    click_button 'Selection'
    within('.selection-action-container') do
      assert_no_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_no_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li', text: 'Move selected'
      assert_no_selector 'li.disabled', text: 'Remove selected'
      assert_selector 'li', text: 'Remove selected'
    end

    # select subproject and verify that copy action is disabled
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: my_project['name']).click

    click_link 'Subprojects'
    assert page.has_text?(my_subproject['name']), 'Subproject not found in project'

    within('tr', text: my_subproject['name']) do
      find('input[type=checkbox]').click
    end

    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_selector 'li.disabled', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li', text: 'Move selected'
      assert_no_selector 'li.disabled', text: 'Remove selected'
      assert_selector 'li', text: 'Remove selected'
    end

    # select subproject and a collection and verify that copy action is still disabled
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: my_project['name']).click

    click_link 'Subprojects'
    assert page.has_text?(my_subproject['name']), 'Subproject not found in project'

    within('tr', text: my_subproject['name']) do
      find('input[type=checkbox]').click
    end

    click_link 'Data collections'
    assert page.has_text?(my_collection['name']), 'Collection not found in project'

    within('tr', text: my_collection['name']) do
      find('input[type=checkbox]').click
    end

    click_link 'Subprojects'
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_selector 'li.disabled', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li', text: 'Move selected'
      assert_no_selector 'li.disabled', text: 'Remove selected'
      assert_selector 'li', text: 'Remove selected'
    end
  end

  # When project tabs are switched, only options applicable to the current tab's selections are enabled.
  test "verify selection options when tabs are switched" do
    my_project = api_fixture('groups')['aproject']
    my_collection = api_fixture('collections')['collection_to_move_around_in_aproject']
    my_subproject = api_fixture('groups')['asubproject']

    # select subproject and a collection and verify that copy action is still disabled
    visit page_with_token 'active', '/'
    find("#projects-menu").click
    find(".dropdown-menu a", text: my_project['name']).click

    # Select a sub-project
    click_link 'Subprojects'
    assert page.has_text?(my_subproject['name']), 'Subproject not found in project'

    within('tr', text: my_subproject['name']) do
      find('input[type=checkbox]').click
    end

    # Select a collection
    click_link 'Data collections'
    assert page.has_text?(my_collection['name']), 'Collection not found in project'

    within('tr', text: my_collection['name']) do
      find('input[type=checkbox]').click
    end

    # Go back to Subprojects tab
    click_link 'Subprojects'
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_selector 'li.disabled', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li', text: 'Move selected'
      assert_no_selector 'li.disabled', text: 'Remove selected'
      assert_selector 'li', text: 'Remove selected'
    end

    # Close the dropdown by clicking outside it.
    find('.dropdown-toggle', text: 'Selection').find(:xpath, '..').click

    # Go back to Data collections tab
    find('.nav-tabs a', text: 'Data collections').click
    click_button 'Selection'
    within('.selection-action-container') do
      assert_no_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Compare selected'
      assert_no_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Move selected'
      assert_selector 'li', text: 'Move selected'
      assert_no_selector 'li.disabled', text: 'Remove selected'
      assert_selector 'li', text: 'Remove selected'
    end
  end

  # "Move selected" and "Remove selected" options should not be
  # available when current user cannot write to the project
  test "move selected and remove selected actions not available when current user cannot write to project" do
    my_project = api_fixture('groups')['anonymously_accessible_project']
    visit page_with_token 'active', "/projects/#{my_project['uuid']}"

    click_link 'Data collections'
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_selector 'li', text: 'Compare selected'
      assert_selector 'li', text: 'Copy selected'
      assert_no_selector 'li', text: 'Move selected'
      assert_no_selector 'li', text: 'Remove selected'
    end
  end

  [
    ['active', true],
    ['project_viewer', false],
  ].each do |user, expect_collection_in_aproject|
    test "combine selected collections into new collection #{user} #{expect_collection_in_aproject}" do
      my_project = api_fixture('groups')['aproject']
      my_collection = api_fixture('collections')['collection_to_move_around_in_aproject']

      visit page_with_token user, "/projects/#{my_project['uuid']}"
      click_link 'Data collections'
      assert page.has_text?(my_collection['name']), 'Collection not found in project'

      within('tr', text: my_collection['name']) do
        find('input[type=checkbox]').click
      end

      click_button 'Selection'
      within('.selection-action-container') do
        click_link 'Create new collection with selected collections'
      end

      # now in the new collection page
      if expect_collection_in_aproject
        assert page.has_text?("Created new collection in the project #{my_project['name']}"),
                              'Not found flash message that new collection is created in aproject'
      else
        assert page.has_text?("Created new collection in your Home project"),
                              'Not found flash message that new collection is created in Home project'
      end
    end
  end

  def scroll_setup(project_name,
                   total_nbr_items,
                   item_list_parameter,
                   sorted = false,
                   sort_parameters = nil)
    project_uuid = api_fixture('groups')[project_name]['uuid']
    visit page_with_token 'user1_with_load', '/projects/' + project_uuid

    assert(page.has_text?("#{item_list_parameter.humanize} (#{total_nbr_items})"), "Number of #{item_list_parameter.humanize} did not match the input amount")

    click_link item_list_parameter.humanize
    wait_for_ajax

    if sorted
      find("th[data-sort-order='#{sort_parameters.gsub(/\s/,'')}']").click
      wait_for_ajax
    end
  end

  def scroll_items_check(nbr_items,
                         fixture_prefix,
                         item_list_parameter,
                         item_selector,
                         sorted = false)
    items = []
    for i in 1..nbr_items
      items << "#{fixture_prefix}#{i}"
    end

    verify_items = items.dup
    unexpected_items = []
    item_count = 0
    within(".arv-project-#{item_list_parameter}") do
      page.execute_script "window.scrollBy(0,999000)"
      begin
        wait_for_ajax
      rescue
      end

      # Visit all rows. If not all expected items are found, retry
      found_items = page.all(item_selector)
      item_count = found_items.count

      previous = nil
      (0..item_count-1).each do |i|
        # Found row text using the fixture string e.g. "Show Collection_#{n} "
        item_name = found_items[i].text.split[1]
        if !items.include? item_name
          unexpected_items << item_name
        else
          verify_items.delete item_name
        end
        if sorted
          # check sort order
          assert_operator( previous.downcase, :<=, item_name.downcase) if previous
          previous = item_name
        end
      end

      assert_equal true, unexpected_items.empty?, "Found unexpected #{item_list_parameter.humanize} #{unexpected_items.inspect}"
      assert_equal nbr_items, item_count, "Found different number of #{item_list_parameter.humanize}"
      assert_equal true, verify_items.empty?, "Did not find all the #{item_list_parameter.humanize}"
    end
  end

  [
    ['project_with_10_collections', 10],
    ['project_with_201_collections', 201], # two pages of data
  ].each do |project_name, nbr_items|
    test "scroll collections tab for #{project_name} with #{nbr_items} objects" do
      item_list_parameter = "Data_collections"
      scroll_setup project_name,
                   nbr_items,
                   item_list_parameter
      scroll_items_check nbr_items,
                         "Collection_",
                         item_list_parameter,
                         'tr[data-kind="arvados#collection"]'
    end
  end

  [
    ['project_with_10_collections', 10],
    ['project_with_201_collections', 201], # two pages of data
  ].each do |project_name, nbr_items|
    test "scroll collections tab for #{project_name} with #{nbr_items} objects with ascending sort (case insensitive)" do
      item_list_parameter = "Data_collections"
      scroll_setup project_name,
                   nbr_items,
                   item_list_parameter,
                   true,
                   "collections.name"
      scroll_items_check nbr_items,
                         "Collection_",
                         item_list_parameter,
                         'tr[data-kind="arvados#collection"]',
                         true
    end
  end

  [
    ['project_with_10_pipelines', 10, 0],
    ['project_with_2_pipelines_and_60_crs', 2, 60],
    ['project_with_25_pipelines', 25, 0],
  ].each do |project_name, num_pipelines, num_crs|
    test "scroll pipeline instances tab for #{project_name} with #{num_pipelines} pipelines and #{num_crs} container requests" do
      item_list_parameter = "Pipelines_and_processes"
      scroll_setup project_name,
                   num_pipelines + num_crs,
                   item_list_parameter
      # check the general scrolling and the pipelines
      scroll_items_check num_pipelines,
                         "pipeline_",
                         item_list_parameter,
                         'tr[data-kind="arvados#pipelineInstance"]'
      # Check container request count separately
      crs_found = page.all('tr[data-kind="arvados#containerRequest"]')
      found_cr_count = crs_found.count
      assert_equal num_crs, found_cr_count, 'Did not find expected number of container requests'
    end
  end

  test "error while loading tab" do
    original_arvados_v1_base = Rails.configuration.arvados_v1_base

    visit page_with_token 'active', '/projects/' + api_fixture('groups')['aproject']['uuid']

    # Point to a bad api server url to generate error
    Rails.configuration.arvados_v1_base = "https://[::1]:1/"
    click_link 'Other objects'
    within '#Other_objects' do
      # Error
      assert_selector('a', text: 'Reload tab')

      # Now point back to the orig api server and reload tab
      Rails.configuration.arvados_v1_base = original_arvados_v1_base
      click_link 'Reload tab'
      assert_no_selector('a', text: 'Reload tab')
      assert_selector('button', text: 'Selection')
      within '.selection-action-container' do
        assert_selector 'tr[data-kind="arvados#trait"]'
      end
    end
  end

  test "add new project using projects dropdown" do
    visit page_with_token 'active', '/'

    # Add a new project
    find("#projects-menu").click
    click_link 'Add a new project'
    assert_text 'New project'
    assert_text 'No description provided'
  end

  test "first tab loads data when visiting other tab directly" do
    # As of 2014-12-19, the first tab of project#show uses infinite scrolling.
    # Make sure that it loads data even if we visit another tab directly.
    need_selenium 'to land on specified tab using {url}#Advanced'
    user = api_fixture("users", "active")
    visit(page_with_token("active_trustedclient",
                          "/projects/#{user['uuid']}#Advanced"))
    assert_text("API response")
    find("#page-wrapper .nav-tabs :first-child a").click
    assert_text("Collection modified at")
  end

  # "Select all" and "Unselect all" options
  test "select all and unselect all actions" do
    need_selenium 'to check and uncheck checkboxes'

    visit page_with_token 'active', '/projects/' + api_fixture('groups')['aproject']['uuid']

    # Go to "Data collections" tab and click on "Select all"
    click_link 'Data collections'
    wait_for_ajax

    # Initially, all selection options for this tab should be disabled
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Copy selected'
    end

    # Select all
    click_button 'Select all'

    assert_checkboxes_state('input[type=checkbox]', true, '"select all" should check all checkboxes')

    # Now the selection options should be enabled
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
    end

    # Go to Pipelines and processes tab and assert none selected
    click_link 'Pipelines and processes'
    wait_for_ajax

    # Since this is the first visit to this tab, all selection options should be disabled
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Copy selected'
    end

    assert_checkboxes_state('input[type=checkbox]', false, '"select all" should check all checkboxes')

    # Select all
    click_button 'Select all'
    assert_checkboxes_state('input[type=checkbox]', true, '"select all" should check all checkboxes')

    # Applicable selection options should be enabled
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li', text: 'Copy selected'
      assert_no_selector 'li.disabled', text: 'Copy selected'
    end

    # Unselect all
    click_button 'Unselect all'
    assert_checkboxes_state('input[type=checkbox]', false, '"select all" should check all checkboxes')

    # All selection options should be disabled again
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Create new collection with selected collections'
      assert_selector 'li.disabled', text: 'Copy selected'
    end

    # Go back to Data collections tab and verify all are still selected
    click_link 'Data collections'
    wait_for_ajax

    # Selection options should be enabled based on the fact that all collections are still selected in this tab
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
    end

    assert_checkboxes_state('input[type=checkbox]', true, '"select all" should check all checkboxes')

    # Unselect all
    find('button#unselect-all').click
    assert_checkboxes_state('input[type=checkbox]', false, '"unselect all" should clear all checkboxes')

    # Now all selection options should be disabled because none of the collections are checked
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li.disabled', text: 'Copy selected'
    end

    # Verify checking just one checkbox still works as expected
    within('tr', text: api_fixture('collections')['collection_to_move_around_in_aproject']['name']) do
      find('input[type=checkbox]').click
    end

    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
      assert_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li.disabled', text: 'Copy selected'
    end
  end

  test "test search all projects menu item in projects menu" do
     need_selenium
     visit page_with_token('active')
     find('#projects-menu').click
     within('.dropdown-menu') do
       assert_selector 'a', text: 'Search all projects'
       find('a', text: 'Search all projects').click
     end
     within('.modal-content') do
        assert page.has_text?('All projects'), 'No text - All projects'
        assert page.has_text?('Search'), 'No text - Search'
        assert page.has_text?('Cancel'), 'No text - Cancel'
        fill_in "Search", with: 'Unrestricted public data'
        wait_for_ajax
        assert_selector 'div', text: 'Unrestricted public data'
        find(:xpath, '//*[@id="choose-scroll"]/div[2]/div').click
        click_button 'Show'
     end
     assert page.has_text?('Unrestricted public data'), 'No text - Unrestricted public data'
     assert page.has_text?('An anonymously accessible project'), 'No text - An anonymously accessible project'
  end

  test "test star and unstar project" do
    visit page_with_token 'active', "/projects/#{api_fixture('groups')['anonymously_accessible_project']['uuid']}"

    # add to favorites
    find('.fa-star-o').click
    wait_for_ajax

    find("#projects-menu").click
    within('.dropdown-menu') do
      assert_selector 'li', text: 'Unrestricted public data'
    end

    # remove from favotires
    find('.fa-star').click
    wait_for_ajax

    find("#projects-menu").click
    within('.dropdown-menu') do
      assert_no_selector 'li', text: 'Unrestricted public data'
    end
  end

  [
    ['Two Part Pipeline Template', 'part-one', 'Provide a value for the following'],
    ['Workflow with input specifications', 'this workflow has inputs specified', 'Provide a value for the following'],
  ].each do |template_name, preview_txt, process_txt|
    test "run a process using template #{template_name} in a project" do
      project = api_fixture('groups')['aproject']
      visit page_with_token 'active', '/projects/' + project['uuid']

      find('.btn', text: 'Run a process').click

      # in the chooser, verify preview and click Next button
      within('.modal-dialog') do
        find('.selectable', text: template_name).click
        assert_text preview_txt
        find('.btn', text: 'Next: choose inputs').click
      end

      # in the process page now
      assert_text process_txt
      assert_text project['name']
    end
  end
end
