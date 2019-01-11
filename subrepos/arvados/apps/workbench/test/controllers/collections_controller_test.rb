# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'test_helper'

class CollectionsControllerTest < ActionController::TestCase
  # These tests don't do state-changing API calls. Save some time by
  # skipping the database reset.
  reset_api_fixtures :after_each_test, false
  reset_api_fixtures :after_suite, true

  include PipelineInstancesHelper

  NONEXISTENT_COLLECTION = "ffffffffffffffffffffffffffffffff+0"

  def config_anonymous enable
    Rails.configuration.anonymous_user_token =
      if enable
        api_fixture('api_client_authorizations')['anonymous']['api_token']
      else
        false
      end
  end

  def collection_params(collection_name, file_name=nil)
    uuid = api_fixture('collections')[collection_name.to_s]['uuid']
    params = {uuid: uuid, id: uuid}
    params[:file] = file_name if file_name
    params
  end

  def assert_hash_includes(actual_hash, expected_hash, msg=nil)
    expected_hash.each do |key, value|
      assert_equal(value, actual_hash[key], msg)
    end
  end

  def assert_no_session
    assert_hash_includes(session, {arvados_api_token: nil},
                         "session includes unexpected API token")
  end

  def assert_session_for_auth(client_auth)
    api_token =
      api_fixture('api_client_authorizations')[client_auth.to_s]['api_token']
    assert_hash_includes(session, {arvados_api_token: api_token},
                         "session token does not belong to #{client_auth}")
  end

  def show_collection(params, session={}, response=:success)
    params = collection_params(params) if not params.is_a? Hash
    session = session_for(session) if not session.is_a? Hash
    get(:show, params, session)
    assert_response response
  end

  test "viewing a collection" do
    show_collection(:foo_file, :active)
    assert_equal([['.', 'foo', 3]], assigns(:object).files)
  end

  test "viewing a collection with spaces in filename" do
    show_collection(:w_a_z_file, :active)
    assert_equal([['.', 'w a z', 5]], assigns(:object).files)
  end

  test "download a file with spaces in filename" do
    setup_for_keep_web
    collection = api_fixture('collections')['w_a_z_file']
    get :show_file, {
      uuid: collection['uuid'],
      file: 'w a z'
    }, session_for(:active)
    assert_response :redirect
    assert_match /w%20a%20z/, response.redirect_url
  end

  test "viewing a collection fetches related projects" do
    show_collection({id: api_fixture('collections')["foo_file"]['portable_data_hash']}, :active)
    assert_includes(assigns(:same_pdh).map(&:owner_uuid),
                    api_fixture('groups')['aproject']['uuid'],
                    "controller did not find linked project")
  end

  test "viewing a collection fetches related permissions" do
    show_collection(:bar_file, :active)
    assert_includes(assigns(:permissions).map(&:uuid),
                    api_fixture('links')['bar_file_readable_by_active']['uuid'],
                    "controller did not find permission link")
  end

  test "viewing a collection fetches jobs that output it" do
    show_collection(:bar_file, :active)
    assert_includes(assigns(:output_of).map(&:uuid),
                    api_fixture('jobs')['foobar']['uuid'],
                    "controller did not find output job")
  end

  test "viewing a collection fetches jobs that logged it" do
    show_collection(:baz_file, :active)
    assert_includes(assigns(:log_of).map(&:uuid),
                    api_fixture('jobs')['foobar']['uuid'],
                    "controller did not find logger job")
  end

  test "sharing auths available to admin" do
    show_collection("collection_owned_by_active", "admin_trustedclient")
    assert_not_nil assigns(:search_sharing)
  end

  test "sharing auths available to owner" do
    show_collection("collection_owned_by_active", "active_trustedclient")
    assert_not_nil assigns(:search_sharing)
  end

  test "sharing auths available to reader" do
    show_collection("foo_collection_in_aproject",
                    "project_viewer_trustedclient")
    assert_not_nil assigns(:search_sharing)
  end

  test "viewing collection files with a reader token" do
    params = collection_params(:foo_file)
    params[:reader_token] = api_fixture("api_client_authorizations",
                                        "active_all_collections", "api_token")
    get(:show_file_links, params)
    assert_response :redirect
    assert_no_session
  end

  test "fetching collection file with reader token" do
    setup_for_keep_web
    params = collection_params(:foo_file, "foo")
    params[:reader_token] = api_fixture("api_client_authorizations",
                                        "active_all_collections", "api_token")
    get(:show_file, params)
    assert_response :redirect
    assert_match /foo/, response.redirect_url
    assert_no_session
  end

  test "reader token Collection links end with trailing slash" do
    # Testing the fix for #2937.
    session = session_for(:active_trustedclient)
    post(:share, collection_params(:foo_file), session)
    assert(@controller.download_link.ends_with? '/',
           "Collection share link does not end with slash for wget")
  end

  test "getting a file from Keep" do
    setup_for_keep_web
    params = collection_params(:foo_file, 'foo')
    sess = session_for(:active)
    get(:show_file, params, sess)
    assert_response :redirect
    assert_match /foo/, response.redirect_url
  end

  test 'anonymous download' do
    setup_for_keep_web
    config_anonymous true
    get :show_file, {
      uuid: api_fixture('collections')['user_agreement_in_anonymously_accessible_project']['uuid'],
      file: 'GNU_General_Public_License,_version_3.pdf',
    }
    assert_response :redirect
    assert_match /GNU_General_Public_License/, response.redirect_url
  end

  test "can't get a file from Keep without permission" do
    params = collection_params(:foo_file, 'foo')
    sess = session_for(:spectator)
    get(:show_file, params, sess)
    assert_response 404
  end

  test "getting a file from Keep with a good reader token" do
    setup_for_keep_web
    params = collection_params(:foo_file, 'foo')
    read_token = api_fixture('api_client_authorizations')['active']['api_token']
    params[:reader_token] = read_token
    get(:show_file, params)
    assert_response :redirect
    assert_match /foo/, response.redirect_url
    assert_not_equal(read_token, session[:arvados_api_token],
                     "using a reader token set the session's API token")
  end

  [false, true].each do |anon|
    test "download a file using a reader token with insufficient scope, anon #{anon}" do
      config_anonymous anon
      params = collection_params(:foo_file, 'foo')
      params[:reader_token] =
        api_fixture('api_client_authorizations')['active_noscope']['api_token']
      get(:show_file, params)
      if anon
        # Some files can be shown without a valid token, but not this one.
        assert_response 404
      else
        # No files will ever be shown without a valid token. You
        # should log in and try again.
        assert_response :redirect
      end
    end
  end

  test "can get a file with an unpermissioned auth but in-scope reader token" do
    setup_for_keep_web
    params = collection_params(:foo_file, 'foo')
    sess = session_for(:expired)
    read_token = api_fixture('api_client_authorizations')['active']['api_token']
    params[:reader_token] = read_token
    get(:show_file, params, sess)
    assert_response :redirect
    assert_not_equal(read_token, session[:arvados_api_token],
                     "using a reader token set the session's API token")
  end

  test "inactive user can retrieve user agreement" do
    setup_for_keep_web
    ua_collection = api_fixture('collections')['user_agreement']
    # Here we don't test whether the agreement can be retrieved from
    # Keep. We only test that show_file decides to send file content.
    get :show_file, {
      uuid: ua_collection['uuid'],
      file: ua_collection['manifest_text'].match(/ \d+:\d+:(\S+)/)[1]
    }, session_for(:inactive)
    assert_nil(assigns(:unsigned_user_agreements),
               "Did not skip check_user_agreements filter " +
               "when showing the user agreement.")
    assert_response :redirect
  end

  test "requesting nonexistent Collection returns 404" do
    show_collection({uuid: NONEXISTENT_COLLECTION, id: NONEXISTENT_COLLECTION},
                    :active, 404)
  end

  test "show file in a subdirectory of a collection" do
    setup_for_keep_web
    params = collection_params(:collection_with_files_in_subdir, 'subdir2/subdir3/subdir4/file1_in_subdir4.txt')
    get(:show_file, params, session_for(:user1_with_load))
    assert_response :redirect
    assert_match /subdir2\/subdir3\/subdir4\/file1_in_subdir4\.txt/, response.redirect_url
  end

  test 'provenance graph' do
    use_token 'admin'

    obj = find_fixture Collection, "graph_test_collection3"

    provenance = obj.provenance.stringify_keys

    [obj[:portable_data_hash]].each do |k|
      assert_not_nil provenance[k], "Expected key #{k} in provenance set"
    end

    prov_svg = ProvenanceHelper::create_provenance_graph(provenance, "provenance_svg",
                                                         {:request => RequestDuck,
                                                           :direction => :bottom_up,
                                                           :combine_jobs => :script_only})

    stage1 = find_fixture Job, "graph_stage1"
    stage3 = find_fixture Job, "graph_stage3"
    previous_job_run = find_fixture Job, "previous_job_run"

    obj_id = obj.portable_data_hash.gsub('+', '\\\+')
    stage1_out = stage1.output.gsub('+', '\\\+')
    stage1_id = "#{stage1.script}_#{Digest::MD5.hexdigest(stage1[:script_parameters].to_json)}"
    stage3_id = "#{stage3.script}_#{Digest::MD5.hexdigest(stage3[:script_parameters].to_json)}"

    assert /#{obj_id}&#45;&gt;#{stage3_id}/.match(prov_svg)

    assert /#{stage3_id}&#45;&gt;#{stage1_out}/.match(prov_svg)

    assert /#{stage1_out}&#45;&gt;#{stage1_id}/.match(prov_svg)

  end

  test 'used_by graph' do
    use_token 'admin'
    obj = find_fixture Collection, "graph_test_collection1"

    used_by = obj.used_by.stringify_keys

    used_by_svg = ProvenanceHelper::create_provenance_graph(used_by, "used_by_svg",
                                                            {:request => RequestDuck,
                                                              :direction => :top_down,
                                                              :combine_jobs => :script_only,
                                                              :pdata_only => true})

    stage2 = find_fixture Job, "graph_stage2"
    stage3 = find_fixture Job, "graph_stage3"

    stage2_id = "#{stage2.script}_#{Digest::MD5.hexdigest(stage2[:script_parameters].to_json)}"
    stage3_id = "#{stage3.script}_#{Digest::MD5.hexdigest(stage3[:script_parameters].to_json)}"

    obj_id = obj.portable_data_hash.gsub('+', '\\\+')
    stage3_out = stage3.output.gsub('+', '\\\+')

    assert /#{obj_id}&#45;&gt;#{stage2_id}/.match(used_by_svg)

    assert /#{obj_id}&#45;&gt;#{stage3_id}/.match(used_by_svg)

    assert /#{stage3_id}&#45;&gt;#{stage3_out}/.match(used_by_svg)

    assert /#{stage3_id}&#45;&gt;#{stage3_out}/.match(used_by_svg)

  end

  test "view collection with empty properties" do
    fixture_name = :collection_with_empty_properties
    show_collection(fixture_name, :active)
    assert_equal(api_fixture('collections')[fixture_name.to_s]['name'], assigns(:object).name)
    assert_not_nil(assigns(:object).properties)
    assert_empty(assigns(:object).properties)
  end

  test "view collection with one property" do
    fixture_name = :collection_with_one_property
    show_collection(fixture_name, :active)
    fixture = api_fixture('collections')[fixture_name.to_s]
    assert_equal(fixture['name'], assigns(:object).name)
    assert_equal(fixture['properties'][0], assigns(:object).properties[0])
  end

  test "create collection with properties" do
    post :create, {
      collection: {
        name: 'collection created with properties',
        manifest_text: '',
        properties: {
          property_1: 'value_1'
        },
      },
      format: :json
    }, session_for(:active)
    assert_response :success
    assert_not_nil assigns(:object).uuid
    assert_equal 'collection created with properties', assigns(:object).name
    assert_equal 'value_1', assigns(:object).properties[:property_1]
  end

  test "update description and check manifest_text is not lost" do
    collection = api_fixture("collections")["multilevel_collection_1"]
    post :update, {
      id: collection["uuid"],
      collection: {
        description: 'test description update'
      },
      format: :json
    }, session_for(:active)
    assert_response :success
    assert_not_nil assigns(:object)
    # Ensure the Workbench response still has the original manifest_text
    assert_equal 'test description update', assigns(:object).description
    assert_equal true, strip_signatures_and_compare(collection['manifest_text'], assigns(:object).manifest_text)
    # Ensure the API server still has the original manifest_text after
    # we called arvados.v1.collections.update
    use_token :active do
      assert_equal true, strip_signatures_and_compare(Collection.find(collection['uuid']).manifest_text,
                                                      collection['manifest_text'])
    end
  end

  # Since we got the initial collection from fixture, there are no signatures in manifest_text.
  # However, after update or find, the collection retrieved will have singed manifest_text.
  # Hence, let's compare each line after excluding signatures.
  def strip_signatures_and_compare m1, m2
    m1_lines = m1.split "\n"
    m2_lines = m2.split "\n"

    return false if m1_lines.size != m2_lines.size

    m1_lines.each_with_index do |line, i|
      m1_words = []
      line.split.each do |word|
        m1_words << word.split('+A')[0]
      end
      m2_words = []
      m2_lines[i].split.each do |word|
        m2_words << word.split('+A')[0]
      end
      return false if !m1_words.join(' ').eql?(m2_words.join(' '))
    end

    return true
  end

  test "view collection and verify none of the file types listed are disabled" do
    show_collection(:collection_with_several_supported_file_types, :active)

    files = assigns(:object).files
    assert_equal true, files.length>0, "Expected one or more files in collection"

    disabled = css_select('[disabled="disabled"]').collect do |el|
      el
    end
    assert_equal 0, disabled.length, "Expected no disabled files in collection viewables list"
  end

  test "view collection and verify file types listed are all disabled" do
    show_collection(:collection_with_several_unsupported_file_types, :active)

    files = assigns(:object).files.collect do |_, file, _|
      file
    end
    assert_equal true, files.length>0, "Expected one or more files in collection"

    disabled = css_select('[disabled="disabled"]').collect do |el|
      el.attributes['title'].value.split[-1]
    end

    assert_equal files.sort, disabled.sort, "Expected to see all collection files in disabled list of files"
  end

  test "anonymous user accesses collection in shared project" do
    config_anonymous true
    collection = api_fixture('collections')['public_text_file']
    get(:show, {id: collection['uuid']})

    response_object = assigns(:object)
    assert_equal collection['name'], response_object['name']
    assert_equal collection['uuid'], response_object['uuid']
    assert_includes @response.body, 'Hello world'
    assert_includes @response.body, 'Content address'
    refute_nil css_select('[href="#Advanced"]')
  end

  test "can view empty collection" do
    get :show, {id: 'd41d8cd98f00b204e9800998ecf8427e+0'}, session_for(:active)
    assert_includes @response.body, 'The following collections have this content'
  end

  test "collection portable data hash redirect" do
    di = api_fixture('collections')['docker_image']
    get :show, {id: di['portable_data_hash']}, session_for(:active)
    assert_match /\/collections\/#{di['uuid']}/, @response.redirect_url
  end

  test "collection portable data hash with multiple matches" do
    pdh = api_fixture('collections')['foo_file']['portable_data_hash']
    get :show, {id: pdh}, session_for(:admin)
    matches = api_fixture('collections').select {|k,v| v["portable_data_hash"] == pdh}
    assert matches.size > 1

    matches.each do |k,v|
      assert_match /href="\/collections\/#{v['uuid']}">.*#{v['name']}<\/a>/, @response.body
    end

    assert_includes @response.body, 'The following collections have this content:'
    assert_not_includes @response.body, 'more results are not shown'
    assert_not_includes @response.body, 'Activity'
    assert_not_includes @response.body, 'Sharing and permissions'
  end

  test "collection page renders name" do
    collection = api_fixture('collections')['foo_file']
    get :show, {id: collection['uuid']}, session_for(:active)
    assert_includes @response.body, collection['name']
    assert_match /not authorized to manage collection sharing links/, @response.body
  end

  test "No Upload tab on non-writable collection" do
    get :show, {id: api_fixture('collections')['user_agreement']['uuid']}, session_for(:active)
    assert_not_includes @response.body, '<a href="#Upload"'
  end

  def setup_for_keep_web cfg='https://%{uuid_or_pdh}.example', dl_cfg=false
    Rails.configuration.keep_web_url = cfg
    Rails.configuration.keep_web_download_url = dl_cfg
  end

  %w(uuid portable_data_hash).each do |id_type|
    test "Redirect to keep_web_url via #{id_type}" do
      setup_for_keep_web
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['w_a_z_file'][id_type]
      get :show_file, {uuid: id, file: "w a z"}, session_for(:active)
      assert_response :redirect
      assert_equal "https://#{id.sub '+', '-'}.example/_/w%20a%20z?api_token=#{tok}", @response.redirect_url
    end

    test "Redirect to keep_web_url via #{id_type} with reader token" do
      setup_for_keep_web
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['w_a_z_file'][id_type]
      get :show_file, {uuid: id, file: "w a z", reader_token: tok}, session_for(:expired)
      assert_response :redirect
      assert_equal "https://#{id.sub '+', '-'}.example/t=#{tok}/_/w%20a%20z", @response.redirect_url
    end

    test "Redirect to keep_web_url via #{id_type} with no token" do
      setup_for_keep_web
      config_anonymous true
      id = api_fixture('collections')['public_text_file'][id_type]
      get :show_file, {uuid: id, file: "Hello World.txt"}
      assert_response :redirect
      assert_equal "https://#{id.sub '+', '-'}.example/_/Hello%20World.txt", @response.redirect_url
    end

    test "Redirect to keep_web_url via #{id_type} with disposition param" do
      setup_for_keep_web
      config_anonymous true
      id = api_fixture('collections')['public_text_file'][id_type]
      get :show_file, {
        uuid: id,
        file: "Hello World.txt",
        disposition: 'attachment',
      }
      assert_response :redirect
      assert_equal "https://#{id.sub '+', '-'}.example/_/Hello%20World.txt?disposition=attachment", @response.redirect_url
    end

    test "Redirect to keep_web_download_url via #{id_type}" do
      setup_for_keep_web('https://collections.example/c=%{uuid_or_pdh}',
                         'https://download.example/c=%{uuid_or_pdh}')
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['w_a_z_file'][id_type]
      get :show_file, {uuid: id, file: "w a z"}, session_for(:active)
      assert_response :redirect
      assert_equal "https://download.example/c=#{id.sub '+', '-'}/_/w%20a%20z?api_token=#{tok}", @response.redirect_url
    end

    test "Redirect to keep_web_url via #{id_type} when trust_all_content enabled" do
      Rails.configuration.trust_all_content = true
      setup_for_keep_web('https://collections.example/c=%{uuid_or_pdh}',
                         'https://download.example/c=%{uuid_or_pdh}')
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['w_a_z_file'][id_type]
      get :show_file, {uuid: id, file: "w a z"}, session_for(:active)
      assert_response :redirect
      assert_equal "https://collections.example/c=#{id.sub '+', '-'}/_/w%20a%20z?api_token=#{tok}", @response.redirect_url
    end
  end

  [false, true].each do |anon|
    test "No redirect to keep_web_url if collection not found, anon #{anon}" do
      setup_for_keep_web
      config_anonymous anon
      id = api_fixture('collections')['w_a_z_file']['uuid']
      get :show_file, {uuid: id, file: "w a z"}, session_for(:spectator)
      assert_response 404
    end

    test "Redirect download to keep_web_download_url, anon #{anon}" do
      config_anonymous anon
      setup_for_keep_web('https://collections.example/c=%{uuid_or_pdh}',
                         'https://download.example/c=%{uuid_or_pdh}')
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['public_text_file']['uuid']
      get :show_file, {
        uuid: id,
        file: 'Hello world.txt',
        disposition: 'attachment',
      }, session_for(:active)
      assert_response :redirect
      expect_url = "https://download.example/c=#{id.sub '+', '-'}/_/Hello%20world.txt"
      if not anon
        expect_url += "?api_token=#{tok}"
      end
      assert_equal expect_url, @response.redirect_url
    end
  end

  test "Error if file is impossible to retrieve from keep_web_url" do
    # Cannot pass a session token using a single-origin keep-web URL,
    # cannot read this collection without a session token.
    setup_for_keep_web 'https://collections.example/c=%{uuid_or_pdh}', false
    id = api_fixture('collections')['w_a_z_file']['uuid']
    get :show_file, {uuid: id, file: "w a z"}, session_for(:active)
    assert_response 422
  end

  [false, true].each do |trust_all_content|
    test "Redirect preview to keep_web_download_url when preview is disabled and trust_all_content is #{trust_all_content}" do
      Rails.configuration.trust_all_content = trust_all_content
      setup_for_keep_web false, 'https://download.example/c=%{uuid_or_pdh}'
      tok = api_fixture('api_client_authorizations')['active']['api_token']
      id = api_fixture('collections')['w_a_z_file']['uuid']
      get :show_file, {uuid: id, file: "w a z"}, session_for(:active)
      assert_response :redirect
      assert_equal "https://download.example/c=#{id.sub '+', '-'}/_/w%20a%20z?api_token=#{tok}", @response.redirect_url
    end
  end

  test "remove selected files from collection" do
    use_token :active

    # create a new collection to test; using existing collections will cause other tests to fail,
    # and resetting fixtures after each test makes it take almost 4 times to run this test file.
    manifest_text = ". d41d8cd98f00b204e9800998ecf8427e+0 0:0:file1 0:0:file2\n./dir1 d41d8cd98f00b204e9800998ecf8427e+0 0:0:file1 0:0:file2\n"

    collection = Collection.create(manifest_text: manifest_text)
    assert_includes(collection['manifest_text'], "0:0:file1")

    # now remove all files named 'file1' from the collection
    post :remove_selected_files, {
      id: collection['uuid'],
      selection: ["#{collection['uuid']}/file1",
                  "#{collection['uuid']}/dir1/file1"],
      format: :json
    }, session_for(:active)
    assert_response :success

    # verify no 'file1' in the updated collection
    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_not_includes(collection['manifest_text'], "0:0:file1")
    assert_includes(collection['manifest_text'], "0:0:file2") # but other files still exist
  end

  test "remove all files from a subdir of a collection" do
    use_token :active

    # create a new collection to test
    manifest_text = ". d41d8cd98f00b204e9800998ecf8427e+0 0:0:file1 0:0:file2\n./dir1 d41d8cd98f00b204e9800998ecf8427e+0 0:0:file1 0:0:file2\n"

    collection = Collection.create(manifest_text: manifest_text)
    assert_includes(collection['manifest_text'], "0:0:file1")

    # now remove all files from "dir1" subdir of the collection
    post :remove_selected_files, {
      id: collection['uuid'],
      selection: ["#{collection['uuid']}/dir1/file1",
                  "#{collection['uuid']}/dir1/file2"],
      format: :json
    }, session_for(:active)
    assert_response :success

    # verify that "./dir1" no longer exists in this collection's manifest text
    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_match /. d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:file1 0:0:file2\n$/, collection['manifest_text']
    assert_not_includes(collection['manifest_text'], 'dir1')
  end

  test "rename file in a collection" do
    use_token :active

    # create a new collection to test
    manifest_text = ". d41d8cd98f00b204e9800998ecf8427e+0 0:0:file1 0:0:file2\n./dir1 d41d8cd98f00b204e9800998ecf8427e+0 0:0:dir1file1 0:0:dir1file2 0:0:dir1imagefile.png\n"

    collection = Collection.create(manifest_text: manifest_text)
    assert_includes(collection['manifest_text'], "0:0:file1")

    # rename 'file1' as 'file1renamed' and verify
    post :update, {
      id: collection['uuid'],
      collection: {
        'rename-file-path:file1' => 'file1renamed'
      },
      format: :json
    }, session_for(:active)
    assert_response :success

    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_match /. d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:file1renamed 0:0:file2\n.\/dir1 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file1 0:0:dir1file2 0:0:dir1imagefile.png\n$/, collection['manifest_text']

    # now rename 'file2' such that it is moved into 'dir1'
    @test_counter = 0
    post :update, {
      id: collection['uuid'],
      collection: {
        'rename-file-path:file2' => 'dir1/file2'
      },
      format: :json
    }, session_for(:active)
    assert_response :success

    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_match /. d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:file1renamed\n.\/dir1 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file1 0:0:dir1file2 0:0:dir1imagefile.png 0:0:file2\n$/, collection['manifest_text']

    # now rename 'dir1/dir1file1' such that it is moved into a new subdir
    @test_counter = 0
    post :update, {
      id: collection['uuid'],
      collection: {
        'rename-file-path:dir1/dir1file1' => 'dir2/dir3/dir1file1moved'
      },
      format: :json
    }, session_for(:active)
    assert_response :success

    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_match /. d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:file1renamed\n.\/dir1 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file2 0:0:dir1imagefile.png 0:0:file2\n.\/dir2\/dir3 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file1moved\n$/, collection['manifest_text']

    # now rename the image file 'dir1/dir1imagefile.png'
    @test_counter = 0
    post :update, {
      id: collection['uuid'],
      collection: {
        'rename-file-path:dir1/dir1imagefile.png' => 'dir1/dir1imagefilerenamed.png'
      },
      format: :json
    }, session_for(:active)
    assert_response :success

    collection = Collection.select([:uuid, :manifest_text]).where(uuid: collection['uuid']).first
    assert_match /. d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:file1renamed\n.\/dir1 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file2 0:0:dir1imagefilerenamed.png 0:0:file2\n.\/dir2\/dir3 d41d8cd98f00b204e9800998ecf8427e\+0\+A(.*) 0:0:dir1file1moved\n$/, collection['manifest_text']
  end

  test "renaming file with a duplicate name in same stream not allowed" do
    use_token :active

    # rename 'file2' as 'file1' and expect error
    post :update, {
      id: 'zzzzz-4zz18-pyw8yp9g3pr7irn',
      collection: {
        'rename-file-path:file2' => 'file1'
      },
      format: :json
    }, session_for(:active)
    assert_response 422
    assert_includes json_response['errors'], 'Duplicate file path'
  end

  test "renaming file with a duplicate name as another stream not allowed" do
    use_token :active

    # rename 'file1' as 'dir1/file1' and expect error
    post :update, {
      id: 'zzzzz-4zz18-pyw8yp9g3pr7irn',
      collection: {
        'rename-file-path:file1' => 'dir1/file1'
      },
      format: :json
    }, session_for(:active)
    assert_response 422
    assert_includes json_response['errors'], 'Duplicate file path'
  end
end
