# frozen_string_literal: true

module DiscourseCodeReview
    class GithubIssueSyncer
      GITHUB_NODE_ID = "github node id"
      GITHUB_ISSUE_NUMBER = "github issue number"
      GITHUB_COMMENT_NUMBER = "github comment number"
  
      def initialize(issue_service, user_syncer)
        @issue_service = issue_service
        @user_syncer = user_syncer
      end
      puts "In syncer now about to sync               sadadasda  as da d asd "
      def sync_issue(repo_name, issue_number, repo_id: nil)
        puts "Syncing issue now abbbbbbbbboiiiiiiiiiiidddddddd"
        owner, name = repo_name.split('/', 2)
  
        issue =
          Issue.new(
            owner: owner,
            name: name,
            issue_number: issue_number
          )
        puts "Got the issue details now "+owner+" "+name+" "+issue_number.to_s
        issue_data = issue_service.issue_data(issue)
        puts "Issue data is "+ issue_data.to_s

        category =
          State::GithubRepoCategories
            .ensure_category(
              repo_name: repo_name,
              repo_id: repo_id,
              issues: true
            )
        url = "https://github.com/#{repo_name}/issues/#{issue_number}"
        puts "url of issue is "+url
        topic =
          ensure_issue_topic(
            category: category,
            author: ensure_actor(issue_data.author),
            github_id: issue_data.github_id,
            created_at: issue_data.created_at,
            title: issue_data.title,
            body: issue_data.body,
            url: url,
            issue_number: issue_number
          )
          puts "ALERT NOTIFICATION: Topic data has been created"+topic.to_s

        issue_service.issue_events(issue).each do |event_info, event|
          puts "In issue service testing aaaaabbbbbbbbbbbiiiiiiiiiiddddddddddd"
          poster =
            GithubIssuePoster.new(
              topic: topic,
              author: ensure_actor(event_info.actor),
              github_id: event_info.github_id,
              created_at: event_info.created_at
            )
  
          poster.post_event(event)
        end
      end
  
      def sync_repo(repo_name)
        issue_service.issues(repo_name).each do |issue|
          sync_issue(repo_name, issue.issue_number)
        end
      end
  
      def mirror_issue_post(post)
        topic = post.topic
        user = post.user
  
        conditions = [
          topic.regular?,
          post.post_number > 1,
          post.post_type == Post.types[:regular],
          post.custom_fields[GITHUB_NODE_ID].nil?
        ]
  
        if conditions.all?
          repo_name = topic.category.custom_fields[DiscourseCodeReview::State::GithubRepoCategories::GITHUB_REPO_NAME]
          issue_number = topic.custom_fields[GITHUB_ISSUE_NUMBER]
  
          if repo_name && issue_number
            issue_number = issue_number.to_i
            post_user_name = user.name || user.username
            github_post_contents = [
              "[#{post_user_name} posted](#{post.full_url}):",
              '',
              post.raw
            ].join("\n")
            response = @issue_service.create_issue_comment(
              repo_name,
              issue_number,
              github_post_contents
            )
  
            post.custom_fields[GITHUB_NODE_ID] = response[:node_id]
            post.save_custom_fields
          end
        end
      end
  
      private
  
      attr_reader :issue_service
      attr_reader :user_syncer
  
      def ensure_actor(actor)
        github_login = actor.github_login
        user_syncer.ensure_user(
          name: github_login,
          github_login: github_login
        )
      end
  
      def ensure_issue_topic(category:, author:, github_id:, created_at:, title:, body:, url:, issue_number:)
        topic_title = "#{title} (Issue ##{issue_number})"
        raw = "#{body}\n\n[GitHub](#{url})"
        custom_fields = { GITHUB_ISSUE_NUMBER => issue_number.to_s }
  
        State::Helpers.ensure_topic_with_nonce(
          category: category.id,
          created_at: created_at,
          custom_fields: custom_fields,
          nonce_name: GITHUB_NODE_ID,
          nonce_value: github_id,
          raw: raw,
          skip_validations: true,
          tags: [SiteSetting.code_review_issue_tag],
          title: topic_title,
          user: author,
        )
      end
    end
  end