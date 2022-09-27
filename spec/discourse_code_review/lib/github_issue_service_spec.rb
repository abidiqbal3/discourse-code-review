# frozen_string_literal: true

require 'rails_helper'

class MockIssueQuerier
  def initialize(**opts)
    @opts = opts
  end

  def timeline(issue)
    @opts.fetch(:timeline, {}).fetch(issue, [])
  end

  def issue_data(issue)
    @opts.fetch(:issue_data, {}).fetch(issue, [])
  end

  def issues(owner, name)
    @opts.fetch(:issues, {}).fetch([owner, name], [])
  end
end

describe DiscourseCodeReview::Source::GithubIssueService do
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

  let!(:issue_comment1) {
    event_info =
      DiscourseCodeReview::IssueEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 00:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::IssueEvent.create(
        :issue_comment,
        body: "some legitimate comment",
        number: 1108947678
      )

    [event_info, event]
  }

  let!(:issue_comment2) {
    event_info =
      DiscourseCodeReview::IssueEventInfo.new(
        github_id: "some github id",
        created_at: Time.parse("2000-01-01 01:00:00 UTC"),
        actor: actor
      )

    event =
      DiscourseCodeReview::IssueEvent.create(
        :issue_comment,
        body: "another legitimate comment",
        number: 1017179885
      )

    [event_info, event]
  }

  context "#issue_events" do
    it "preserves timeline events" do
      issue_querier =
        MockIssueQuerier.new(
          timeline: {
            issue => [issue_comment1]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubIssueService
          .new(nil, issue_querier)
          .issue_events(issue)
          .to_a

      expect(result).to eq([issue_comment1])
    end

    it "preserves timeline event order" do
      issue_querier =
        MockIssueQuerier.new(
          timeline: {
            issue => [
              issue_comment1,
              issue_comment2
            ]
          }
        )

      result =
        DiscourseCodeReview::Source::GithubIssueService
          .new(nil, issue_querier)
          .issue_events(issue)
          .to_a

      expect(result).to eq([issue_comment1, issue_comment2])
    end
  end
end