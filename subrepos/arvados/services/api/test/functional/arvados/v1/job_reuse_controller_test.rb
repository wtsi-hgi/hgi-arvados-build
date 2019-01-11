# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

require 'test_helper'
require 'helpers/git_test_helper'

class Arvados::V1::JobReuseControllerTest < ActionController::TestCase
  fixtures :repositories, :users, :jobs, :links, :collections

  # See git_setup.rb for the commit log for test.git.tar
  include GitTestHelper

  setup do
    @controller = Arvados::V1::JobsController.new
    authorize_with :active
  end

  test "reuse job with no_reuse=false" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        an_integer: '1',
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "reuse job with find_or_create=true" do
    post :create, {
      job: {
        script: "hash",
        script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '1'
        }
      },
      find_or_create: true
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "no reuse job with null log" do
    post :create, {
      job: {
        script: "hash",
        script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '3'
        }
      },
      find_or_create: true
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqq3', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "reuse job with symbolic script_version" do
    post :create, {
      job: {
        script: "hash",
        script_version: "tag1",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '1'
        }
      },
      find_or_create: true
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "do not reuse job because no_reuse=true" do
    post :create, {
      job: {
        no_reuse: true,
        script: "hash",
        script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '1'
        }
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  [false, "false"].each do |whichfalse|
    test "do not reuse job because find_or_create=#{whichfalse.inspect}" do
      post :create, {
        job: {
          script: "hash",
          script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
          repository: "active/foo",
          script_parameters: {
            input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
            an_integer: '1'
          }
        },
        find_or_create: whichfalse
      }
      assert_response :success
      assert_not_nil assigns(:object)
      new_job = JSON.parse(@response.body)
      assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
      assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
    end
  end

  test "do not reuse job because output is not readable by user" do
    authorize_with :job_reader
    post :create, {
      job: {
        script: "hash",
        script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '1'
        }
      },
      find_or_create: true
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "test_cannot_reuse_job_no_output" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '2'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykppp', new_job['uuid']
  end

  test "test_reuse_job_range" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      minimum_script_version: "tag1",
      script_version: "master",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "cannot_reuse_job_no_minimum_given_so_must_use_specified_commit" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "master",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '077ba2ad3ea24a929091a9e6ce545c93199b8e57', new_job['script_version']
  end

  test "test_cannot_reuse_job_different_input" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '2'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "test_cannot_reuse_job_different_version" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "master",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '2'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '077ba2ad3ea24a929091a9e6ce545c93199b8e57', new_job['script_version']
  end

  test "test_can_reuse_job_submitted_nondeterministic" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      },
      nondeterministic: true
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "test_cannot_reuse_job_past_nondeterministic" do
    post :create, job: {
      no_reuse: false,
      script: "hash2",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykyyy', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "test_cannot_reuse_job_no_permission" do
    authorize_with :spectator
    post :create, job: {
      no_reuse: false,
      script: "hash",
      script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
      repository: "active/foo",
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "test_cannot_reuse_job_excluded" do
    post :create, job: {
      no_reuse: false,
      script: "hash",
      minimum_script_version: "31ce37fe365b3dc204300a3e4c396ad333ed0556",
      script_version: "master",
      repository: "active/foo",
      exclude_script_versions: ["tag1"],
      script_parameters: {
        input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
        an_integer: '1'
      }
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_not_equal('4fe459abe02d9b365932b8f5dc419439ab4e2577',
                     new_job['script_version'])
  end

  test "cannot reuse job with find_or_create but excluded version" do
    post :create, {
      job: {
        script: "hash",
        script_version: "master",
        repository: "active/foo",
        script_parameters: {
          input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
          an_integer: '1'
        }
      },
      find_or_create: true,
      minimum_script_version: "31ce37fe365b3dc204300a3e4c396ad333ed0556",
      exclude_script_versions: ["tag1"],
    }
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_not_equal('4fe459abe02d9b365932b8f5dc419439ab4e2577',
                     new_job['script_version'])
  end

  test "cannot reuse job when hash-like branch includes newer commit" do
    check_new_job_created_from({job: {script_version: "738783"}},
                               :previous_job_run_superseded_by_hash_branch)
  end

  BASE_FILTERS = {
    'repository' => ['=', 'active/foo'],
    'script' => ['=', 'hash'],
    'script_version' => ['in git', 'master'],
    'docker_image_locator' => ['=', nil],
    'arvados_sdk_version' => ['=', nil],
  }

  def filters_from_hash(hash)
    hash.each_pair.map { |name, filter| [name] + filter }
  end

  test "can reuse a Job based on filters" do
    filters_hash = BASE_FILTERS.
      merge('script_version' => ['in git', 'tag1'])
    post(:create, {
           job: {
             script: "hash",
             script_version: "master",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             }
           },
           filters: filters_from_hash(filters_hash),
           find_or_create: true,
         })
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "can not reuse a Job based on filters" do
    filters = filters_from_hash(BASE_FILTERS
                                  .reject { |k| k == 'script_version' })
    filters += [["script_version", "in git",
                 "31ce37fe365b3dc204300a3e4c396ad333ed0556"],
                ["script_version", "not in git", ["tag1"]]]
    post(:create, {
           job: {
             script: "hash",
             script_version: "master",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             }
           },
           filters: filters,
           find_or_create: true,
         })
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '077ba2ad3ea24a929091a9e6ce545c93199b8e57', new_job['script_version']
  end

  test "can not reuse a Job based on arbitrary filters" do
    filters_hash = BASE_FILTERS.
      merge("created_at" => ["<", "2010-01-01T00:00:00Z"])
    post(:create, {
           job: {
             script: "hash",
             script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             }
           },
           filters: filters_from_hash(filters_hash),
           find_or_create: true,
         })
    assert_response :success
    assert_not_nil assigns(:object)
    new_job = JSON.parse(@response.body)
    assert_not_equal 'zzzzz-8i9sb-cjs4pklxxjykqqq', new_job['uuid']
    assert_equal '4fe459abe02d9b365932b8f5dc419439ab4e2577', new_job['script_version']
  end

  test "can reuse a Job with a Docker image" do
    post(:create, {
           job: {
             script: "hash",
             script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             },
             runtime_constraints: {
               docker_image: 'arvados/apitestfixture',
             }
           },
           find_or_create: true,
         })
    assert_response :success
    new_job = assigns(:object)
    assert_not_nil new_job
    target_job = jobs(:previous_docker_job_run)
    [:uuid, :script_version, :docker_image_locator].each do |attr|
      assert_equal(target_job.send(attr), new_job.send(attr))
    end
  end

  test "can reuse a Job with a Docker image hash filter" do
    filters_hash = BASE_FILTERS.
      merge("script_version" =>
              ["=", "4fe459abe02d9b365932b8f5dc419439ab4e2577"],
            "docker_image_locator" =>
              ["in docker", links(:docker_image_collection_hash).name])
    post(:create, {
           job: {
             script: "hash",
             script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             },
           },
           filters: filters_from_hash(filters_hash),
           find_or_create: true,
         })
    assert_response :success
    new_job = assigns(:object)
    assert_not_nil new_job
    target_job = jobs(:previous_docker_job_run)
    [:uuid, :script_version, :docker_image_locator].each do |attr|
      assert_equal(target_job.send(attr), new_job.send(attr))
    end
  end

  test "reuse Job with Docker image repo+tag" do
    filters_hash = BASE_FILTERS.
      merge("script_version" =>
              ["=", "4fe459abe02d9b365932b8f5dc419439ab4e2577"],
            "docker_image_locator" =>
              ["in docker", links(:docker_image_collection_tag2).name])
    post(:create, {
           job: {
             script: "hash",
             script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             },
           },
           filters: filters_from_hash(filters_hash),
           find_or_create: true,
         })
    assert_response :success
    new_job = assigns(:object)
    assert_not_nil new_job
    target_job = jobs(:previous_docker_job_run)
    [:uuid, :script_version, :docker_image_locator].each do |attr|
      assert_equal(target_job.send(attr), new_job.send(attr))
    end
  end

  test "new job with unknown Docker image filter" do
    filters_hash = BASE_FILTERS.
      merge("docker_image_locator" => ["in docker", "_nonesuchname_"])
    post(:create, {
           job: {
             script: "hash",
             script_version: "4fe459abe02d9b365932b8f5dc419439ab4e2577",
             repository: "active/foo",
             script_parameters: {
               input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
               an_integer: '1'
             },
           },
           filters: filters_from_hash(filters_hash),
           find_or_create: true,
         })
    assert_response :success
    new_job = assigns(:object)
    assert_not_nil new_job
    assert_not_equal(jobs(:previous_docker_job_run).uuid, new_job.uuid)
  end

  test "don't reuse job using older Docker image of same name" do
    jobspec = {runtime_constraints: {
        docker_image: "arvados/apitestfixture",
      }}
    check_new_job_created_from({job: jobspec},
                               :previous_ancient_docker_image_job_run)
  end

  test "reuse job with Docker image that has hash name" do
    jobspec = {runtime_constraints: {
        docker_image: "a" * 64,
      }}
    check_job_reused_from(jobspec, :previous_docker_job_run)
  end

  ["repository", "script"].each do |skip_key|
    test "missing #{skip_key} filter raises an error" do
      filters = filters_from_hash(BASE_FILTERS.reject { |k| k == skip_key })
      post(:create, {
             job: {
               script: "hash",
               script_version: "master",
               repository: "active/foo",
               script_parameters: {
                 input: 'fa7aeb5140e2848d39b416daeef4ffc5+45',
                 an_integer: '1'
               }
             },
             filters: filters,
             find_or_create: true,
           })
      assert_includes(405..599, @response.code.to_i,
                      "bad status code with missing #{skip_key} filter")
    end
  end

  test "find Job with script version range" do
    get :index, filters: [["repository", "=", "active/foo"],
                          ["script", "=", "hash"],
                          ["script_version", "in git", "tag1"]]
    assert_response :success
    assert_not_nil assigns(:objects)
    assert_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
  end

  test "find Job with script version range exclusions" do
    get :index, filters: [["repository", "=", "active/foo"],
                          ["script", "=", "hash"],
                          ["script_version", "not in git", "tag1"]]
    assert_response :success
    assert_not_nil assigns(:objects)
    refute_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
  end

  test "find Job with Docker image range" do
    get :index, filters: [["docker_image_locator", "in docker",
                           "arvados/apitestfixture"]]
    assert_response :success
    assert_not_nil assigns(:objects)
    assert_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_docker_job_run).uuid)
    refute_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
  end

  test "find Job with Docker image using reader tokens" do
    authorize_with :inactive
    get(:index, {
          filters: [["docker_image_locator", "in docker",
                     "arvados/apitestfixture"]],
          reader_tokens: [api_token(:active)],
        })
    assert_response :success
    assert_not_nil assigns(:objects)
    assert_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_docker_job_run).uuid)
    refute_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
  end

  test "'in docker' filter accepts arrays" do
    get :index, filters: [["docker_image_locator", "in docker",
                           ["_nonesuchname_", "arvados/apitestfixture"]]]
    assert_response :success
    assert_not_nil assigns(:objects)
    assert_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_docker_job_run).uuid)
    refute_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
  end

  test "'not in docker' filter accepts arrays" do
    get :index, filters: [["docker_image_locator", "not in docker",
                           ["_nonesuchname_", "arvados/apitestfixture"]]]
    assert_response :success
    assert_not_nil assigns(:objects)
    assert_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_job_run).uuid)
    refute_includes(assigns(:objects).map { |job| job.uuid },
                    jobs(:previous_docker_job_run).uuid)
  end

  JOB_SUBMIT_KEYS = [:script, :script_parameters, :script_version, :repository]
  DEFAULT_START_JOB = :previous_job_run

  def create_job_params(params, start_from=DEFAULT_START_JOB)
    if not params.has_key?(:find_or_create)
      params[:find_or_create] = true
    end
    job_attrs = params.delete(:job) || {}
    start_job = jobs(start_from)
    params[:job] = Hash[JOB_SUBMIT_KEYS.map do |key|
                          [key, start_job.send(key)]
                        end]
    params[:job][:runtime_constraints] =
      job_attrs.delete(:runtime_constraints) || {}
    { arvados_sdk_version: :arvados_sdk_version,
      docker_image_locator: :docker_image }.each do |method, constraint_key|
      if constraint_value = start_job.send(method)
        params[:job][:runtime_constraints][constraint_key] ||= constraint_value
      end
    end
    params[:job].merge!(job_attrs)
    params
  end

  def create_job_from(params, start_from)
    post(:create, create_job_params(params, start_from))
    assert_response :success
    new_job = assigns(:object)
    assert_not_nil new_job
    new_job
  end

  def check_new_job_created_from(params, start_from=DEFAULT_START_JOB)
    start_time = Time.now
    new_job = create_job_from(params, start_from)
    assert_operator(start_time, :<=, new_job.created_at)
    new_job
  end

  def check_job_reused_from(params, start_from)
    new_job = create_job_from(params, start_from)
    assert_equal(jobs(start_from).uuid, new_job.uuid)
  end

  def check_errors_from(params, start_from=DEFAULT_START_JOB)
    post(:create, create_job_params(params, start_from))
    assert_includes(405..499, @response.code.to_i)
    errors = json_response.fetch("errors", [])
    assert(errors.any?, "no errors assigned from #{params}")
    refute(errors.any? { |msg| msg =~ /^#<[A-Za-z]+: / },
           "errors include raw exception: #{errors.inspect}")
    errors
  end

  # 1de84a8 is on the b1 branch, after master's tip.
  test "new job created from unsatisfiable minimum version filter" do
    filters_hash = BASE_FILTERS.merge("script_version" => ["in git", "1de84a8"])
    check_new_job_created_from(filters: filters_from_hash(filters_hash))
  end

  test "new job created from unsatisfiable minimum version parameter" do
    check_new_job_created_from(minimum_script_version: "1de84a8")
  end

  test "new job created from unsatisfiable minimum version attribute" do
    check_new_job_created_from(job: {minimum_script_version: "1de84a8"})
  end

  test "graceful error from nonexistent minimum version filter" do
    filters_hash = BASE_FILTERS.merge("script_version" =>
                                      ["in git", "__nosuchbranch__"])
    errors = check_errors_from(filters: filters_from_hash(filters_hash))
    assert(errors.any? { |msg| msg.include? "__nosuchbranch__" },
           "bad refspec not mentioned in error message")
  end

  test "graceful error from nonexistent minimum version parameter" do
    errors = check_errors_from(minimum_script_version: "__nosuchbranch__")
    assert(errors.any? { |msg| msg.include? "__nosuchbranch__" },
           "bad refspec not mentioned in error message")
  end

  test "graceful error from nonexistent minimum version attribute" do
    errors = check_errors_from(job: {minimum_script_version: "__nosuchbranch__"})
    assert(errors.any? { |msg| msg.include? "__nosuchbranch__" },
           "bad refspec not mentioned in error message")
  end

  test "don't reuse job with older Arvados SDK version specified by branch" do
    jobspec = {runtime_constraints: {
        arvados_sdk_version: "master",
      }}
    check_new_job_created_from({job: jobspec},
                               :previous_job_run_with_arvados_sdk_version)
  end

  test "don't reuse job with older Arvados SDK version specified by commit" do
    jobspec = {runtime_constraints: {
        arvados_sdk_version: "ca68b24e51992e790f29df5cc4bc54ce1da4a1c2",
      }}
    check_new_job_created_from({job: jobspec},
                               :previous_job_run_with_arvados_sdk_version)
  end

  test "don't reuse job with newer Arvados SDK version specified by commit" do
    jobspec = {runtime_constraints: {
        arvados_sdk_version: "436637c87a1d2bdbf4b624008304064b6cf0e30c",
      }}
    check_new_job_created_from({job: jobspec},
                               :previous_job_run_with_arvados_sdk_version)
  end

  test "reuse job from arvados_sdk_version git filters" do
    prev_job = jobs(:previous_job_run_with_arvados_sdk_version)
    filters_hash = BASE_FILTERS.
      merge("arvados_sdk_version" => ["in git", "commit2"],
            "docker_image_locator" => ["=", prev_job.docker_image_locator])
    filters_hash.delete("script_version")
    params = create_job_params(filters: filters_from_hash(filters_hash))
    post(:create, params)
    assert_response :success
    assert_equal(prev_job.uuid, assigns(:object).uuid)
  end

  test "create new job because of arvados_sdk_version 'not in git' filters" do
    filters_hash = BASE_FILTERS.reject { |k| k == "script_version" }
    filters = filters_from_hash(filters_hash)
    # Allow anything from the root commit, but before commit 2.
    filters += [["arvados_sdk_version", "in git", "436637c8"],
                ["arvados_sdk_version", "not in git", "00634b2b"]]
    check_new_job_created_from(filters: filters)
  end
end
