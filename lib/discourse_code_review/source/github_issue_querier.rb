# frozen_string_literal: true

module DiscourseCodeReview
  class Source::GithubIssueQuerier
    
    def initialize(graphql_client)
      @graphql_client = graphql_client
    end

    def timeline(issue)
      item_types = [
        "CLOSED_EVENT",
        "ISSUE_COMMENT",
        "RENAMED_TITLE_EVENT",
        "REOPENED_EVENT"
      ]

      events =
        graphql_client.paginated_query do |execute, cursor|
          query = "
            query {
              repository(owner: #{issue.owner.to_json}, name: #{issue.name.to_json}) {
                issue(number: #{issue.issue_number.to_json}) {
                  timelineItems(first: 100, itemTypes: [#{item_types.join(',')}], after: #{cursor.to_json}) {
                    nodes {
                      ... on ClosedEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        }
                      },
                      ... on IssueComment {
                        __typename,
                        id,
                        databaseId,
                        createdAt,
                        actor: author {
                          login
                        },
                        body
                      },
                      ... on RenamedTitleEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        },
                        previousTitle,
                        currentTitle
                      },
                      ... on ReopenedEvent {
                        __typename,
                        id,
                        createdAt,
                        actor {
                          login
                        }
                      },
                    },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            }
          "
          response = execute.call(query)
          data = response[:repository][:issue][:timelineItems]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage]
          }
        end

      # Enumerators::CompactEnumerator.new(
      #   Enumerators::MapEnumerator.new(events) { |event|
      events.lazy.filter_map { |event|
          event_info =
            IssueEventInfo.new(
              github_id: event[:id],
              actor:
                Actor.new(
                  github_login: event[:actor][:login]
                ),
              created_at: Time.parse(event[:createdAt])
            )

          event =
            case event[:__typename]
            when "ClosedEvent"
              IssueEvent.create(:closed)
            when "IssueComment"
              IssueEvent.create(
                :issue_comment,
                body: event[:body],
                number: event[:databaseId]
              )
            when "RenamedTitleEvent"
              IssueEvent.create(
                :renamed_title,
                previous_title: event[:previousTitle],
                new_title: event[:currentTitle]
              )
            when "ReopenedEvent"
              IssueEvent.create(:reopened)
            else
              raise "Unexpected typename"
            end

          [event_info, event] unless event.nil?
        }
    end

    def issue_data(issue)
      response =
        graphql_client.execute("
          query {
            repository(owner: #{issue.owner.to_json}, name: #{issue.name.to_json}) {
              issue(number: #{issue.issue_number.to_json}) {
                id,
                author {
                  login
                },
                body,
                title,
                createdAt
              }
            }
          }
        ")

      data = response[:repository][:issue]
      IssueData.new(
        author: Actor.new(github_login: data[:author][:login]),
        body: data[:body],
        title: data[:title],
        created_at: Time.parse(data[:createdAt]),
        github_id: data[:id]
      )
    end

    def issues(owner, name)
      iss =
        graphql_client.paginated_query do |execute, cursor|
          response =
            execute.call("
              query {
                repository(owner: #{owner.to_json}, name: #{name.to_json}) {
                  issues(first: 100, orderBy: { direction: DESC, field: CREATED_AT }, after: #{cursor.to_json}) {
                    nodes { number },
                    pageInfo { endCursor, hasNextPage }
                  }
                }
              }
            ")
          data = response[:repository][:issues]

          {
            items: data[:nodes],
            cursor: data[:pageInfo][:endCursor],
            has_next_page: data[:pageInfo][:hasNextPage]
          }
        end

      Enumerators::MapEnumerator.new(iss) { |is|
        Issue.new(
          owner: owner,
          name: name,
          issue_number: is[:number]
        )
      }
    end

    private

    attr_reader :graphql_client
  end
end