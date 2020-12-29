# frozen_string_literal: true

# name: discourse-code-review
# about: use discourse for after the fact code reviews
# version: 0.1
# authors: Sam Saffron
# url: https://github.com/discourse/discourse-code-review

# match version in discourse dev
gem 'addressable', '2.7.0'
gem 'sawyer', '0.8.2'
gem 'octokit', '4.16.0'
gem 'pqueue', '2.1.0'
gem 'rugged', '0.28.4.1'

if Rails.env.test?
  gem 'graphql', '1.11.6'
end

enabled_site_setting :code_review_enabled

register_asset 'stylesheets/code_review.scss'
register_svg_icon 'history'

require_dependency 'auth/github_authenticator'
require_dependency 'lib/staff_constraint'
module HackGithubAuthenticator

  def after_authenticate(auth_token, existing_account: nil)
    result = super(auth_token, existing_account: existing_account)

    if SiteSetting.code_review_enabled?
      if user_id = result.user&.id
        user = result.user
        user.custom_fields[DiscourseCodeReview::GITHUB_ID] = auth_token[:uid]
        user.custom_fields[DiscourseCodeReview::GITHUB_LOGIN] = auth_token.info.nickname
        user.save_custom_fields
      end
    end

    result
  end
end

class ::Auth::GithubAuthenticator
  prepend HackGithubAuthenticator
end

after_initialize do

  if !SiteSetting.tagging_enabled
    Rails.logger.warn("The code review plugin requires tagging, enabling it!")
    SiteSetting.tagging_enabled = true
  end

  module ::DiscourseCodeReview
    PluginName = 'discourse-code-review'
    NOTIFY_REVIEW_CUSTOM_FIELD = 'notify_on_code_reviews'

    class APIUserError < StandardError
    end

    class Engine < ::Rails::Engine
      engine_name 'code-review'
      isolate_namespace DiscourseCodeReview
    end

    COMMIT_HASH = 'commit hash'
    GITHUB_ID = 'github id'
    GITHUB_LOGIN = 'github login'
    COMMENT_PATH = 'comment path'
    COMMENT_POSITION = 'comment position'

    def self.octokit_bot_client
      token = SiteSetting.code_review_github_token

      if !token || token.empty?
        raise APIUserError, "code_review_github_token not set"
      end

      Octokit::Client.new(access_token: token)
    end

    def self.octokit_client
      self.octokit_bot_client
    rescue APIUserError
      Octokit::Client.new
    end

    def self.reset_state!
      @graphql_client = nil
      @github_commit_querier = nil
      @github_pr_querier = nil
      @github_pr_service = nil
      @github_user_querier = nil
      @github_user_syncer = nil
      @github_pr_syncer = nil
    end

    def self.graphql_client
      @graphql_client ||= GraphQLClient.new(self.octokit_bot_client)
    end

    def self.github_commit_querier
      @github_commit_querier ||= Source::CommitQuerier.new(self.graphql_client)
    end

    def self.github_pr_service
      @github_pr_querier ||= Source::GithubPRQuerier.new(self.graphql_client)
      @github_pr_service ||=
        Source::GithubPRService.new(
          self.octokit_bot_client,
          @github_pr_querier
        )
    end

    def self.github_user_querier
      @github_user_querier ||= Source::GithubUserQuerier.new(self.octokit_client)
    end

    def self.github_user_syncer
      @github_user_syncer ||= GithubUserSyncer.new(self.github_user_querier)
    end

    def self.github_pr_syncer
      @github_pr_syncer ||=
        GithubPRSyncer.new(
          self.github_pr_service,
          self.github_user_syncer
        )
    end

    def self.without_rate_limiting
      previously_disabled = RateLimiter.disabled?

      RateLimiter.disable

      yield
    ensure
      RateLimiter.enable unless previously_disabled
    end

    def self.sync_post_to_github(client, post)
      topic = post.topic
      hash = topic&.custom_fields[DiscourseCodeReview::COMMIT_HASH]
      user = post.user

      if post.post_number > 1 && post.post_type == Post.types[:regular] && post.raw.present? && topic && hash && user
        if !post.custom_fields[DiscourseCodeReview::GITHUB_ID]
          fields = post.reply_to_post&.custom_fields || {}
          path = fields[DiscourseCodeReview::COMMENT_PATH]
          position = fields[DiscourseCodeReview::COMMENT_POSITION]

          if repo = post.topic.category.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME]
            post_user_name = user.name || user.username

            github_post_contents = [
              "[#{post_user_name} posted](#{post.full_url}):",
              '',
              post.raw
            ].join("\n")

            comment = client.create_commit_comment(repo, hash, github_post_contents, path, nil, position)
            post.custom_fields[DiscourseCodeReview::GITHUB_ID] = comment.id
            post.custom_fields[DiscourseCodeReview::COMMENT_PATH] = path if path.present?
            post.custom_fields[DiscourseCodeReview::COMMENT_POSITION] = position if position.present?
            post.save_custom_fields
          end
        end
      end
    end

    def self.github_organizations
      SiteSetting
        .code_review_github_organizations
        .split(',')
        .map(&:strip)
    end
  end

  # TODO Drop after Discourse 2.6.0 release
  register_editable_user_custom_field(DiscourseCodeReview::NOTIFY_REVIEW_CUSTOM_FIELD)
  if respond_to?(:allow_staff_user_custom_field)
    allow_staff_user_custom_field(DiscourseCodeReview::NOTIFY_REVIEW_CUSTOM_FIELD)
  else
    whitelist_staff_user_custom_field(DiscourseCodeReview::NOTIFY_REVIEW_CUSTOM_FIELD)
  end

  User.register_custom_field_type(DiscourseCodeReview::NOTIFY_REVIEW_CUSTOM_FIELD, :boolean)

  require File.expand_path("../app/controllers/discourse_code_review/code_review_controller.rb", __FILE__)
  require File.expand_path("../app/controllers/discourse_code_review/organizations_controller.rb", __FILE__)
  require File.expand_path("../app/controllers/discourse_code_review/repos_controller.rb", __FILE__)
  require File.expand_path("../app/controllers/discourse_code_review/admin_code_review_controller.rb", __FILE__)
  require File.expand_path("../app/models/skipped_code_review.rb", __FILE__)
  require File.expand_path("../app/jobs/regular/code_review_sync_commits", __FILE__)
  require File.expand_path("../app/jobs/regular/code_review_sync_commit_comments", __FILE__)
  require File.expand_path("../lib/enumerators", __FILE__)
  require File.expand_path("../lib/typed_data", __FILE__)
  require File.expand_path("../lib/graphql_client", __FILE__)
  require File.expand_path("../lib/discourse_code_review/source.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/state.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/github_pr_poster", __FILE__)
  require File.expand_path("../lib/discourse_code_review/github_pr_syncer", __FILE__)
  require File.expand_path("../lib/discourse_code_review/github_user_syncer.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/importer.rb", __FILE__)
  require File.expand_path("../lib/discourse_code_review/github_repo.rb", __FILE__)

  Site.preloaded_category_custom_fields << DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME

  add_admin_route 'code_review.title', 'code-review'

  DiscourseCodeReview::Engine.routes.draw do
    scope '/code-review' do
      post '/approve' => 'code_review#approve'
      post '/followup' => 'code_review#followup'
      post '/followed_up' => 'code_review#followed_up'
      post '/skip' => 'code_review#skip'
      post '/webhook' => 'code_review#webhook'
      get "/redirect/:sha1" => 'code_review#redirect', constraints: { sha1: /[0-9a-fA-F]+/ }
    end

    scope '/admin/plugins/code-review', as: 'admin_code_review', constraints: StaffConstraint.new do
      scope format: false do
        get '/' => 'admin_code_review#index'
      end

      scope format: true, constraints: { format: 'json' } do
        resources :organizations, only: [:index] do
          resources :repos, only: [:index] do
            member do
              get '/has-configured-webhook' => 'repos#has_configured_webhook'
              post '/configure-webhook' => 'repos#configure_webhook'
            end
          end
        end
      end
    end
  end

  Discourse::Application.routes.append do
    get '/topics/approval-given/:username' => 'list#approval_given',
        as: :topics_approval_given,
        constraints: { username: RouteFormat.username }

    get '/topics/approval-pending/:username' => 'list#approval_pending',
        as: :topics_approval_pending,
        constraints: { username: RouteFormat.username }

    mount ::DiscourseCodeReview::Engine, at: '/'
  end

  on(:post_process_cooked) do |doc, post|
    if SiteSetting.code_review_sync_to_github?
      client = DiscourseCodeReview.octokit_bot_client
      DiscourseCodeReview.sync_post_to_github(client, post)

      DiscourseCodeReview.github_pr_syncer.mirror_pr_post(post)
    end
  end

  on(:before_post_process_cooked) do |doc, post|
    unless post.topic.custom_fields[DiscourseCodeReview::COMMIT_HASH].present? && post.post_number == 1
      doc =
        DiscourseCodeReview::State::CommitTopics
          .auto_link_commits(post.raw, doc)[2]
    end
  end

  on(:post_destroyed) do |post, opts, user|
    if (github_id = post.custom_fields[DiscourseCodeReview::GITHUB_ID]).present?
      client = DiscourseCodeReview.octokit_bot_client
      category = post&.topic&.category

      repo_name =
        category && category.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME]

      if repo_name.present?
        client.delete_commit_comment(repo_name, github_id)
      end
    end
  end

  add_to_class(:list_controller, :approval_given) do
    respond_with_list(
      TopicQuery.new(
        current_user,
        tags: [SiteSetting.code_review_approved_tag]
      ).list_topics_by(current_user)
    )
  end

  add_to_class(:list_controller, :approval_pending) do
    respond_with_list(
      TopicQuery.new(
        current_user,
        tags: [SiteSetting.code_review_pending_tag]
      ).list_topics_by(current_user)
    )
  end
end

Rake::Task.define_task code_review_delete_user_github_access_tokens: :environment do
  num_deleted = UserCustomField.where(name: 'github user token').delete_all
  puts "deleted #{num_deleted} user_custom_fields"
end

Rake::Task.define_task code_review_tag_commits: :environment do
  topics =
    Topic
      .where(
        id:
          TopicCustomField
            .select(:topic_id)
            .where(name: DiscourseCodeReview::COMMIT_HASH)
      )
      .to_a

  puts "Tagging #{topics.size} topics"

  topics.each do |topic|
    DiscourseTagging.tag_topic_by_names(
      topic,
      Discourse.system_user.guardian,
      [SiteSetting.code_review_commit_tag],
      append: true
    )
  end
end
