# frozen_string_literal: true

require 'rails_helper'

class MockGithubIssueService
  def initialize(**opts)
    @opts = opts
  end

  def issues(repo_name)
    @opts.fetch(:issues, {}).fetch(repo_name, [])
  end

  def issue_data(issue)
    @opts.fetch(:issue_data, {}).fetch(issue, [])
  end

  def issue_events(issue)
    @opts.fetch(:issue_events, {}).fetch(issue, [])
  end
end

class MockGithubUserQuerier
  def initialize(**opts)
    @opts = opts
  end

  def get_user_email(github_login)
    @opts.fetch(:emails, {}).fetch(github_login, nil)
  end
end

describe DiscourseCodeReview::GithubIssueSyncer do
  let!(:issue) {
    DiscourseCodeReview::Issue.new(
      owner: "owner",
      name: "name",
      issue_number: 101,
    )
  }

  let!(:actor) {
    DiscourseCodeReview::Actor.new(
      github_login: "coder1234",
    )
  }

  let!(:issue_data) {
    DiscourseCodeReview::IssueData.new(
      title: "Title",
      body: "Body",
      github_id: "Issue github id",
      created_at: Time.parse("2000-01-01 00:00:00 UTC"),
      author: actor
    )
  }

  let!(:empty_user_querier) {
    MockGithubUserQuerier.new()
  }

  define_method(:create_issue_syncer) do |issue_service, user_querier|
    DiscourseCodeReview::GithubIssueSyncer.new(
      issue_service,
      DiscourseCodeReview::GithubUserSyncer.new(user_querier)
    )
  end

  let!(:event_info) {
    DiscourseCodeReview::IssueEventInfo.new(
      github_id: "github event id",
      created_at: Time.parse("2000-01-01 01:00:00 UTC"),
      actor: actor
    )
  }

  let!(:event_info2) {
    DiscourseCodeReview::IssueEventInfo.new(
      github_id: "second github event id",
      created_at: Time.parse("2000-01-01 02:00:00 UTC"),
      actor: actor
    )
  }

  define_method(:last_topic) do
    Topic.order('id DESC').first
  end

  define_method(:first_post_of_last_topic) do
    last_topic.posts.first
  end

  define_method(:last_post_of_last_topic) do
    last_topic.posts.last
  end

  fab!(:category) do
    DiscourseCodeReview::State::GithubRepoCategories.ensure_category(
      repo_name: 'owner/name',
      repo_id: '24',
      issues: true
    )
  end

  context "#sync_issues" do
    context "when there are no events" do
      let!(:syncer) do
        issue_service =
          MockGithubIssueService.new(
            issue_data: {
              issue => issue_data
            }
          )

        create_issue_syncer(issue_service, empty_user_querier)
      end

      it "creates a topic" do
        expect {
          syncer.sync_issue("owner/name", 101)
        }.to change { Topic.count }.by(1)
      end

      it "creates a topic idempotently" do
        syncer.sync_issue("owner/name", 101)

        expect {
          syncer.sync_issue("owner/name", 101)
        }.to change { Topic.count }.by(0)
      end

      it "creates one post" do
        expect {
          syncer.sync_issue("owner/name", 101)
        }.to change { Post.count }.by(1)
      end

      it "puts the github url in the first post" do
        syncer.sync_issue("owner/name", 101)

        expect(first_post_of_last_topic.raw).to include("https://github.com/owner/name/issues/101")
      end

      it "puts the original comment in the first post" do
        syncer.sync_issue("owner/name", 101)

        expect(first_post_of_last_topic.raw).to include(issue_data.body)
      end
    end

    context "when there is a close event" do
      let!(:closed_event) do
        DiscourseCodeReview::IssueEvent.create(:closed)
      end

      let!(:syncer) do
        issue_service =
          MockGithubIssueService.new(
            issue_data: {
              issue => issue_data
            },
            issue_events: {
              issue => [[event_info, closed_event]]
            }
          )

        create_issue_syncer(issue_service, empty_user_querier)
      end

      it "creates closed posts" do
        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(2)

        expect(last_post_of_last_topic.action_code).to eq("closed.enabled")
      end

      it "creates closed posts idempotently" do
        syncer.sync_issue('owner/name', 101)

        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(0)
      end

      it "closes the topic" do
        syncer.sync_issue('owner/name', 101)

        expect(last_topic).to be_closed
      end
    end

    context "when the events contain an issue comment" do
      let!(:issue_comment) do
        DiscourseCodeReview::IssueEvent.create(
          :issue_comment,
          body: "Body",
          number: 1108947678
        )
      end

      let!(:syncer) do
        issue_service =
          MockGithubIssueService.new(
            issue_data: {
              issue => issue_data
            },
            issue_events: {
              issue => [[event_info, issue_comment]]
            }
          )

        create_issue_syncer(issue_service, empty_user_querier)
      end

      it "creates posts for issue comments" do
        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(2)
      end

      it "puts the issue comment body in the created post" do
        syncer.sync_issue('owner/name', 101)

        expect(last_post_of_last_topic.raw).to include(issue_comment.body)
      end

      it "creates posts for issue comments idempotently" do
        syncer.sync_issue('owner/name', 101)

        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(0)
      end
    end

    context "when the events contain a renamed event" do
      let!(:renamed_event) do
        DiscourseCodeReview::IssueEvent.create(
          :renamed_title,
          previous_title: "Old Title",
          new_title: "New Title"
        )
      end

      let!(:syncer) do
        issue_service =
          MockGithubIssueService.new(
            issue_data: {
              issue => issue_data
            },
            issue_events: {
              issue => [[event_info, renamed_event]]
            }
          )

        create_issue_syncer(issue_service, empty_user_querier)
      end

      it "creates renamed title posts" do
        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(2)
      end

      it "changes the title" do
        syncer.sync_issue('owner/name', 101)

        expect(last_topic.title).to eq("New Title (Issue #101)")
      end
    end

    context "when the events contain a re-opened event" do
      let!(:closed_event) do
        DiscourseCodeReview::IssueEvent.create(:closed)
      end

      let!(:reopened_event) do
        DiscourseCodeReview::IssueEvent.create(:reopened)
      end

      let!(:syncer) do
        issue_service =
          MockGithubIssueService.new(
            issue_data: {
              issue => issue_data
            },
            issue_events: {
              issue => [
                [event_info, closed_event],
                [event_info2, reopened_event]
              ]
            }
          )

        create_issue_syncer(issue_service, empty_user_querier)
      end

      it "creates re-opened posts" do
        expect {
          syncer.sync_issue('owner/name', 101)
        }.to change { Post.count }.by(3)
      end

      it "leaves the topic open" do
        syncer.sync_issue('owner/name', 101)

        expect(last_topic).to_not be_closed
      end
    end
  end
end