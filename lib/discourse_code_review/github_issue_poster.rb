# frozen_string_literal: true

module DiscourseCodeReview
    class GithubIssuePoster
      def initialize(topic:, author:, github_id:, created_at:)
        @topic = topic
        @author = author
        @github_id = github_id
        @created_at = created_at
      end
  
      def post_event(event)
        case event.class.tag
        when :closed
          update_closed(true)
        when :issue_comment
          ensure_issue_post(
            body: event.body,
            number: event.number,
            post_type: :regular
          )
        when :renamed_title
          body =
            "The title of this issue changed from \"#{event.previous_title}\" to \"#{event.new_title}"
  
          ensure_issue_post(body: body, post_type: :small_action, action_code: 'renamed') do |post|
            topic = post.topic
            issue_number = topic.custom_fields[DiscourseCodeReview::GithubIssueSyncer::GITHUB_ISSUE_NUMBER]
  
            topic.title = "#{event.new_title} (Issue ##{issue_number})"
            topic.save!(validate: false)
          end
        when :reopened
          update_closed(false)
        end
      end
  
      private
  
      attr_reader :topic
      attr_reader :author
      attr_reader :github_id
      attr_reader :created_at
  
      def update_closed(closed)
        State::Helpers.ensure_closed_state_with_nonce(
          closed: closed,
          created_at: created_at,
          nonce_name: DiscourseCodeReview::GithubIssueSyncer::GITHUB_NODE_ID,
          nonce_value: github_id,
          topic: topic,
          user: author,
        )
      end
  
      def ensure_issue_post(post_type:, body: nil, number: nil, action_code: nil, author: @author)
        custom_fields = {}
        custom_fields[DiscourseCodeReview::GithubIssueSyncer::GITHUB_COMMENT_NUMBER] = number
  
        post =
          State::Helpers.ensure_post_with_nonce(
            action_code: action_code,
            created_at: created_at,
            custom_fields: custom_fields,
            nonce_name: DiscourseCodeReview::GithubIssueSyncer::GITHUB_NODE_ID,
            nonce_value: github_id,
            post_type: Post.types[post_type],
            raw: body,
            skip_validations: true,
            topic_id: topic.id,
            user: author,
          )
  
        yield post if block_given?
      end
    end
  end