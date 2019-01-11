# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'integration_helper'

class AnonymousAccessTest < ActionDispatch::IntegrationTest
  include KeepWebConfig

  # These tests don't do state-changing API calls. Save some time by
  # skipping the database reset.
  reset_api_fixtures :after_each_test, false
  reset_api_fixtures :after_suite, true

  setup do
    need_javascript
    Rails.configuration.anonymous_user_token = api_fixture('api_client_authorizations')['anonymous']['api_token']
  end

  PUBLIC_PROJECT = "/projects/#{api_fixture('groups')['anonymously_accessible_project']['uuid']}"

  def verify_site_navigation_anonymous_enabled user, is_active
    if user
      if user['is_active']
        assert_text 'Unrestricted public data'
        assert_selector 'a', text: 'Projects'
        page.find("#projects-menu").click
        within('.dropdown-menu') do
          assert_selector 'a', text: 'Search all projects'
          assert_selector "a[href=\"/projects/public\"]", text: 'Browse public projects'
          assert_selector 'a', text: 'Add a new project'
          assert_selector 'li[class="dropdown-header"]', text: 'My projects'
        end
      else
        assert_text 'indicate that you have read and accepted the user agreement'
      end
      within('.navbar-fixed-top') do
        assert_selector 'a', text: Rails.configuration.site_name.downcase
        assert(page.has_link?("notifications-menu"), 'no user menu')
        page.find("#notifications-menu").click
        within('.dropdown-menu') do
          assert_selector 'a', text: 'Log out'
        end
      end
    else  # anonymous
      assert_text 'Unrestricted public data'
      within('.navbar-fixed-top') do
        assert_text Rails.configuration.site_name.downcase
        assert_no_selector 'a', text: Rails.configuration.site_name.downcase
        assert_selector 'a', text: 'Log in'
        assert_selector 'a', text: 'Browse public projects'
      end
    end
  end

  [
    [nil, nil, false, false],
    ['inactive', api_fixture('users')['inactive'], false, false],
    ['active', api_fixture('users')['active'], true, true],
  ].each do |token, user, is_active|
    test "visit public project as user #{token.inspect} when anonymous browsing is enabled" do
      if !token
        visit PUBLIC_PROJECT
      else
        visit page_with_token(token, PUBLIC_PROJECT)
      end

      verify_site_navigation_anonymous_enabled user, is_active
    end
  end

  test "selection actions when anonymous user accesses shared project" do
    visit PUBLIC_PROJECT

    assert_selector 'a', text: 'Description'
    assert_selector 'a', text: 'Data collections'
    assert_selector 'a', text: 'Pipelines and processes'
    assert_selector 'a', text: 'Pipeline templates'
    assert_selector 'a', text: 'Subprojects'
    assert_selector 'a', text: 'Advanced'
    assert_no_selector 'a', text: 'Other objects'
    assert_no_selector 'button', text: 'Add data'

    click_link 'Data collections'
    click_button 'Selection'
    within('.selection-action-container') do
      assert_selector 'li', text: 'Compare selected'
      assert_no_selector 'li', text: 'Create new collection with selected collections'
      assert_no_selector 'li', text: 'Copy selected'
      assert_no_selector 'li', text: 'Move selected'
      assert_no_selector 'li', text: 'Remove selected'
    end
  end

  test "anonymous user accesses data collections tab in shared project" do
    visit PUBLIC_PROJECT
    click_link 'Data collections'
    collection = api_fixture('collections')['user_agreement_in_anonymously_accessible_project']
    assert_text 'GNU General Public License'

    assert_selector 'a', text: 'Data collections'

    # click on show collection
    within "tr[data-object-uuid=\"#{collection['uuid']}\"]" do
      click_link 'Show'
    end

    # in collection page
    assert_no_selector 'input', text: 'Create sharing link'
    assert_no_text 'Sharing and permissions'
    assert_no_selector 'a', text: 'Upload'
    assert_no_selector 'button', 'Selection'

    within '#collection_files tr,li', text: 'GNU_General_Public_License,_version_3.pdf' do
      assert page.has_no_selector?('[value*="GNU_General_Public_License"]')
      find 'a[title~=View]'
      find 'a[title~=Download]'
    end
  end

  test 'view file' do
    use_keep_web_config

    magic = rand(2**512).to_s 36
    owner = api_fixture('groups')['anonymously_accessible_project']['uuid']
    col = upload_data_and_get_collection(magic, 'admin', "Hello\\040world.txt", owner)
    visit '/collections/' + col.uuid
    find('tr,li', text: 'Hello world.txt').
      find('a[title~=View]').click
    assert_text magic
  end

  [
    'running anonymously accessible cr',
    'pipelineInstance'
  ].each do |proc|
    test "anonymous user accesses pipelines and processes tab in shared project and clicks on '#{proc}'" do
      visit PUBLIC_PROJECT
      click_link 'Data collections'
      assert_text 'GNU General Public License'

      click_link 'Pipelines and processes'
      assert_text 'Pipeline in publicly accessible project'

      if proc.include? 'pipeline'
        verify_pipeline_instance_row
      else
        verify_container_request_row proc
      end
    end
  end

  def verify_container_request_row look_for
    within first('tr', text: look_for) do
      click_link 'Show'
    end
    assert_text 'Public Projects Unrestricted public data'
    assert_text 'command'

    assert_text 'zzzzz-tpzed-xurymjxw79nv3jz' # modified by user
    assert_no_selector 'a', text: 'zzzzz-tpzed-xurymjxw79nv3jz'
    assert_no_selector 'button', text: 'Cancel'
  end

  def verify_pipeline_instance_row
    within first('tr[data-kind="arvados#pipelineInstance"]') do
      assert_text 'Pipeline in publicly accessible project'
      click_link 'Show'
    end

    # in pipeline instance page
    assert_text 'Public Projects Unrestricted public data'
    assert_text 'This pipeline is complete'
    assert_no_selector 'a', text: 'Re-run with latest'
    assert_no_selector 'a', text: 'Re-run options'
  end

  [
    'pipelineTemplate',
    'workflow'
  ].each do |type|
    test "anonymous user accesses pipeline templates tab in shared project and click on #{type}" do
      visit PUBLIC_PROJECT
      click_link 'Data collections'
      assert_text 'GNU General Public License'

      assert_selector 'a', text: 'Pipeline templates'

      click_link 'Pipeline templates'
      assert_text 'Pipeline template in publicly accessible project'
      assert_text 'Workflow with input specifications'

      if type == 'pipelineTemplate'
        within first('tr[data-kind="arvados#pipelineTemplate"]') do
          click_link 'Show'
        end

        # in template page
        assert_text 'Public Projects Unrestricted public data'
        assert_text 'script version'
        assert_no_selector 'a', text: 'Run this pipeline'
      else
        within first('tr[data-kind="arvados#workflow"]') do
          click_link 'Show'
        end

        # in workflow page
        assert_text 'Public Projects Unrestricted public data'
        assert_text 'this workflow has inputs specified'
      end
    end
  end

  test "anonymous user accesses subprojects tab in shared project" do
    visit PUBLIC_PROJECT + '#Subprojects'

    assert_text 'Subproject in anonymous accessible project'

    within first('tr[data-kind="arvados#group"]') do
      click_link 'Show'
    end

    # in subproject
    assert_text 'Description for subproject in anonymous accessible project'
  end

  [
    ['pipeline_in_publicly_accessible_project', true],
    ['pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', false],
    ['pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', false, 'spectator'],
    ['pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', true, 'admin'],

    ['completed_job_in_publicly_accessible_project', true],
    ['running_job_in_publicly_accessible_project', true],
    ['job_in_publicly_accessible_project_but_other_objects_elsewhere', false],
  ].each do |fixture, objects_readable, user=nil|
    test "access #{fixture} in public project with objects readable=#{objects_readable} with user #{user}" do
      pipeline_page = true if fixture.include?('pipeline')

      if pipeline_page
        object = api_fixture('pipeline_instances')[fixture]
        page_link = "/pipeline_instances/#{object['uuid']}"
        expect_log_text = "Log for foo"
      else      # job
        object = api_fixture('jobs')[fixture]
        page_link = "/jobs/#{object['uuid']}"
        expect_log_text = "stderr crunchstat"
      end

      if user
        visit page_with_token user, page_link
      else
        visit page_link
      end

      # click job link, if in pipeline page
      click_link 'foo' if pipeline_page

      if objects_readable
        assert_selector 'a[href="#Log"]', text: 'Log'
        assert_no_selector 'a[data-toggle="disabled"]', text: 'Log'
        assert_no_text 'zzzzz-4zz18-bv31uwvy3neko21 (Unavailable)'
        if pipeline_page
          assert_text 'This pipeline was created from'
          job_id = object['components']['foo']['job']['uuid']
          assert_selector 'a', text: job_id
          assert_selector "a[href=\"/jobs/#{job_id}#Log\"]", text: 'Log'

          # We'd like to test the Log tab on job pages too, but we can't right
          # now because Poltergeist 1.x doesn't support JavaScript's
          # Function.prototype.bind, which is used by job_log_graph.js.
          find(:xpath, "//a[@href='#Log']").click
          assert_text expect_log_text
        end
      else
        assert_selector 'a[data-toggle="disabled"]', text: 'Log'
        assert_text 'zzzzz-4zz18-bv31uwvy3neko21 (Unavailable)'
        assert_text object['job']
        if pipeline_page
          assert_no_text 'This pipeline was created from'  # template is not readable
          assert_no_selector 'a', text: object['components']['foo']['job']['uuid']
          assert_text 'Log unavailable'
        end
        find(:xpath, "//a[@href='#Log']").click
        assert_text 'zzzzz-4zz18-bv31uwvy3neko21 (Unavailable)'
        assert_no_text expect_log_text
      end
    end
  end

  [
    ['new_pipeline_in_publicly_accessible_project', true],
    ['new_pipeline_in_publicly_accessible_project', true, 'spectator'],
    ['new_pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', false],
    ['new_pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', false, 'spectator'],
    ['new_pipeline_in_publicly_accessible_project_but_other_objects_elsewhere', true, 'admin'],
    ['new_pipeline_in_publicly_accessible_project_with_dataclass_file_and_other_objects_elsewhere', false],
    ['new_pipeline_in_publicly_accessible_project_with_dataclass_file_and_other_objects_elsewhere', false, 'spectator'],
    ['new_pipeline_in_publicly_accessible_project_with_dataclass_file_and_other_objects_elsewhere', true, 'admin'],
  ].each do |fixture, objects_readable, user=nil|
    test "access #{fixture} in public project with objects readable=#{objects_readable} with user #{user}" do
      object = api_fixture('pipeline_instances')[fixture]
      page = "/pipeline_instances/#{object['uuid']}"
      if user
        visit page_with_token user, page
      else
        visit page
      end

      # click Components tab
      click_link 'Components'

      if objects_readable
        assert_text 'This pipeline was created from'
        if user == 'admin'
          assert_text 'input'
          assert_selector 'a', text: 'Choose'
          assert_selector 'a', text: 'Run'
          assert_no_selector 'a.disabled', text: 'Run'
        else
          assert_selector 'a', text: object['components']['foo']['script_parameters']['input']['value']
          user ? (assert_selector 'a', text: 'Run') : (assert_no_selector 'a', text: 'Run')
        end
      else
        assert_no_text 'This pipeline was created from'  # template is not readable
        input = object['components']['foo']['script_parameters']['input']['value']
        assert_no_selector 'a', text: input
        if user
          input = input.gsub('/', '\\/')
          assert_text "One or more inputs provided are not readable"
          assert_selector "input[type=text][value=#{input}]"
          assert_selector 'a.disabled', text: 'Run'
        else
          assert_no_text "One or more inputs provided are not readable"
          assert_text input
          assert_no_selector 'a', text: 'Run'
        end
      end
    end
  end
end
