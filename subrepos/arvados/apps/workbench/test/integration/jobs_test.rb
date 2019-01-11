# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'fileutils'
require 'tmpdir'

require 'integration_helper'

class JobsTest < ActionDispatch::IntegrationTest
  include KeepWebConfig

  setup do
      need_javascript
  end

  def fakepipe_with_log_data
    content =
      "2014-01-01_12:00:01 zzzzz-8i9sb-0vsrcqi7whchuil 0  log message 1\n" +
      "2014-01-01_12:00:02 zzzzz-8i9sb-0vsrcqi7whchuil 0  log message 2\n" +
      "2014-01-01_12:00:03 zzzzz-8i9sb-0vsrcqi7whchuil 0  log message 3\n"
    StringIO.new content, 'r'
  end

  test "add job description" do
    job = api_fixture('jobs')['nearly_finished_job']
    visit page_with_token("active", "/jobs/#{job['uuid']}")

    # edit job description
    within('.arv-description-as-subtitle') do
      find('.fa-pencil').click
      find('.editable-input textarea').set('*Textile description for job* - "Go to dashboard":/')
      find('.editable-submit').click
    end

    # Verify edited description
    assert_no_text '*Textile description for job*'
    assert_text 'Textile description for job'
    assert_selector 'a[href="/"]', text: 'Go to dashboard'
  end

  test 'view partial job log' do
    need_selenium 'to be able to see the CORS response headers (PhantomJS 1.9.8 does not)'
    use_keep_web_config

    # This config will be restored during teardown by ../test_helper.rb:
    Rails.configuration.log_viewer_max_bytes = 100

    logdata = fakepipe_with_log_data.read
    job_uuid = api_fixture('jobs')['running']['uuid']
    logcollection = upload_data_and_get_collection(logdata, 'active', "#{job_uuid}.log.txt")
    job = nil
    use_token 'active' do
      job = Job.find job_uuid
      job.update_attributes log: logcollection.portable_data_hash
    end
    visit page_with_token 'active', '/jobs/'+job.uuid
    find('a[href="#Log"]').click
    wait_for_ajax
    assert_text 'Showing only 100 bytes of this log'
  end

  test 'view log via keep-web redirect' do
    use_keep_web_config

    token = api_fixture('api_client_authorizations')['active']['api_token']
    logdata = fakepipe_with_log_data.read
    logblock = `echo -n #{logdata.shellescape} | ARVADOS_API_TOKEN=#{token.shellescape} arv-put --no-progress --raw -`.strip
    assert $?.success?, $?

    job = nil
    use_token 'active' do
      job = Job.find api_fixture('jobs')['running']['uuid']
      mtxt = ". #{logblock} 0:#{logdata.length}:#{job.uuid}.log.txt\n"
      logcollection = Collection.create(manifest_text: mtxt)
      job.update_attributes log: logcollection.portable_data_hash
    end
    visit page_with_token 'active', '/jobs/'+job.uuid
    find('a[href="#Log"]').click
    assert_text 'log message 1'
  end

  [
    ['foobar', false, false],
    ['job_with_latest_version', true, false],
    ['job_with_latest_version', true, true],
  ].each do |job_name, expect_options, use_latest|
    test "Rerun #{job_name} job, expect options #{expect_options},
          and use latest version option #{use_latest}" do
      job = api_fixture('jobs')[job_name]
      visit page_with_token 'active', '/jobs/'+job['uuid']

      if expect_options
        assert_text 'supplied_script_version: master'
      else
        assert_no_text 'supplied_script_version'
      end

      assert_triggers_dom_event 'shown.bs.modal' do
        find('a,button', text: 'Re-run job...').click
      end
      within('.modal-dialog') do
        assert_selector 'a,button', text: 'Cancel'
        if use_latest
          page.choose("job_script_version_#{job['supplied_script_version']}")
        end
        click_on "Run now"
      end

      # Re-running jobs doesn't currently work because the test API
      # server has no git repository to check against.  For now, check
      # that the error message says something appropriate for that
      # situation.
      if expect_options && use_latest
        assert_text "077ba2ad3ea24a929091a9e6ce545c93199b8e57"
      else
        assert_text "Script version #{job['script_version']} does not resolve to a commit"
      end
    end
  end

  [
    ['active', true],
    ['job_reader2', false],
  ].each do |user, readable|
    test "view job with components as #{user} user" do
      job = api_fixture('jobs')['running_job_with_components']
      component1 = api_fixture('jobs')['completed_job_in_publicly_accessible_project']
      component2 = api_fixture('pipeline_instances')['running_pipeline_with_complete_job']
      component2_child1 = api_fixture('jobs')['previous_job_run']
      component2_child2 = api_fixture('jobs')['running']

      visit page_with_token(user, "/jobs/#{job['uuid']}")
      assert page.has_text? job['script_version']
      assert page.has_no_text? 'script_parameters'

      # The job_reader2 is allowed to read job, component2, and component2_child1,
      # and component2_child2 only as a component of the pipeline component2
      if readable
        assert page.has_link? 'component1'
        assert page.has_link? 'component2'
      else
        assert page.has_no_link? 'component1'
        assert page.has_link? 'component2'
      end

      if readable
        click_link('component1')
        within('.panel-collapse') do
          assert(has_text? component1['uuid'])
          assert(has_text? component1['script_version'])
          assert(has_text? 'script_parameters')
        end
        click_link('component1')
      end

      click_link('component2')
      within('.panel-collapse') do
        assert(has_text? component2['uuid'])
        assert(has_text? component2['script_version'])
        assert(has_no_text? 'script_parameters')
        assert(has_link? 'previous')
        assert(has_link? 'running')

        click_link('previous')
        within('.panel-collapse') do
          assert(has_text? component2_child1['uuid'])
          assert(has_text? component2_child1['script_version'])
        end
        click_link('previous')

        click_link('running')
        within('.panel-collapse') do
          assert(has_text? component2_child2['uuid'])
          if readable
            assert(has_text? component2_child2['script_version'])
          else
            assert(has_no_text? component2_child2['script_version'])
          end
        end
      end
    end
  end
end
