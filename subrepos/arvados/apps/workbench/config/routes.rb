# Copyright (C) The Arvados Authors. All rights reserved.
#
# SPDX-License-Identifier: AGPL-3.0

ArvadosWorkbench::Application.routes.draw do
  themes_for_rails

  resources :keep_disks
  resources :keep_services
  resources :user_agreements do
    post 'sign', on: :collection
    get 'signatures', on: :collection
  end
  get '/user_agreements/signatures' => 'user_agreements#signatures'
  get "users/setup_popup" => 'users#setup_popup', :as => :setup_user_popup
  get "users/setup" => 'users#setup', :as => :setup_user
  get "report_issue_popup" => 'actions#report_issue_popup', :as => :report_issue_popup
  post "report_issue" => 'actions#report_issue', :as => :report_issue
  get "star" => 'actions#star', :as => :star
  get "all_processes" => 'work_units#index', :as => :all_processes
  get "choose_work_unit_templates" => 'work_unit_templates#choose', :as => :choose_work_unit_templates
  resources :work_units do
    post 'show_child_component', :on => :member
  end
  resources :nodes
  resources :humans
  resources :traits
  resources :api_client_authorizations
  resources :virtual_machines
  resources :containers
  resources :container_requests do
    post 'cancel', :on => :member
    post 'copy', on: :member
  end
  get '/virtual_machines/:id/webshell/:login' => 'virtual_machines#webshell', :as => :webshell_virtual_machine
  resources :authorized_keys
  resources :job_tasks
  resources :jobs do
    post 'cancel', :on => :member
    get 'logs', :on => :member
  end
  resources :repositories do
    post 'share_with', on: :member
  end
  # {format: false} prevents rails from treating "foo.png" as foo?format=png
  get '/repositories/:id/tree/:commit' => 'repositories#show_tree'
  get '/repositories/:id/tree/:commit/*path' => 'repositories#show_tree', as: :show_repository_tree, format: false
  get '/repositories/:id/blob/:commit/*path' => 'repositories#show_blob', as: :show_repository_blob, format: false
  get '/repositories/:id/commit/:commit' => 'repositories#show_commit', as: :show_repository_commit
  resources :sessions
  match '/logout' => 'sessions#destroy', via: [:get, :post]
  get '/logged_out' => 'sessions#logged_out'
  resources :users do
    get 'choose', :on => :collection
    get 'home', :on => :member
    get 'welcome', :on => :collection
    get 'inactive', :on => :collection
    get 'activity', :on => :collection
    get 'storage', :on => :collection
    post 'sudo', :on => :member
    post 'unsetup', :on => :member
    get 'setup_popup', :on => :member
    get 'profile', :on => :member
    post 'request_shell_access', :on => :member
    get 'virtual_machines', :on => :member
    get 'repositories', :on => :member
    get 'ssh_keys', :on => :member
    get 'link_account', :on => :collection
    post 'link_account', :on => :collection, :action => :merge
  end
  get '/current_token' => 'users#current_token'
  get "/add_ssh_key_popup" => 'users#add_ssh_key_popup', :as => :add_ssh_key_popup
  get "/add_ssh_key" => 'users#add_ssh_key', :as => :add_ssh_key
  resources :logs
  resources :factory_jobs
  resources :uploaded_datasets
  resources :groups do
    get 'choose', on: :collection
  end
  resources :specimens
  resources :pipeline_templates do
    get 'choose', on: :collection
  end
  resources :pipeline_instances do
    post 'cancel', :on => :member
    get 'compare', on: :collection
    post 'copy', on: :member
  end
  resources :links
  get '/collections/graph' => 'collections#graph'
  resources :collections do
    post 'set_persistent', on: :member
    get 'sharing_popup', :on => :member
    post 'share', :on => :member
    post 'unshare', :on => :member
    get 'choose', on: :collection
    post 'remove_selected_files', on: :member
    get 'tags', on: :member
    post 'save_tags', on: :member
    get 'multisite', on: :collection, to: redirect('/search')
  end
  get('/collections/download/:uuid/:reader_token/*file' => 'collections#show_file',
      format: false)
  get '/collections/download/:uuid/:reader_token' => 'collections#show_file_links'
  get '/collections/:uuid/*file' => 'collections#show_file', :format => false
  resources :projects do
    match 'remove/:item_uuid', on: :member, via: :delete, action: :remove_item
    match 'remove_items', on: :member, via: :delete, action: :remove_items
    get 'choose', on: :collection
    post 'share_with', on: :member
    get 'tab_counts', on: :member
    get 'public', on: :collection
  end

  resources :search do
    get 'choose', :on => :collection
  end

  resources :workflows

  get "trash" => 'trash_items#index', :as => :trash
  resources :trash_items do
    post 'untrash_items', on: :collection
  end

  post 'actions' => 'actions#post'
  get 'actions' => 'actions#show'
  get 'websockets' => 'websocket#index'
  post "combine_selected" => 'actions#combine_selected_files_into_collection'

  root :to => 'projects#index'

  match '/_health/ping', to: 'healthcheck#ping', via: [:get]

  get '/tests/mithril', to: 'tests#mithril'

  get '/status', to: 'status#status'

  # Send unroutable requests to an arbitrary controller
  # (ends up at ApplicationController#render_not_found)
  match '*a', to: 'links#render_not_found', via: [:get, :post]
end
