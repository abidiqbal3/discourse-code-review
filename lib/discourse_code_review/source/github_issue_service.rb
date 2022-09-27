# frozen_string_literal: true

module DiscourseCodeReview
    Issue =
      TypedData::TypedStruct.new(
        owner: String,
        name: String,
        issue_number: Integer
      )
  
    IssueEventInfo =
      TypedData::TypedStruct.new(
        github_id: String,
        created_at: Time,
        actor: Actor
      )
  
    IssueEvent =
      TypedData::TypedTaggedUnion.new(
        closed: {},
        issue_comment: {
          body: String,
          number: Integer
        },
        renamed_title: {
          previous_title: String,
          new_title: String
        },
        reopened: {}
      )
  
    IssueData =
      TypedData::TypedStruct.new(
        title: String,
        body: String,
        github_id: String,
        created_at: Time,
        author: Actor
      )
  
    class Source::GithubIssueService
      class EventStream
        include Enumerable
        # puts "In enumerable class shAMSSSSSSSSSSSSSSSSSSSS "
        def initialize(issue_querier, issue)
          puts "In enumerable class shAMSSSSSSSSSSSSSSSSSSSS "
          @issue_querier = issue_querier
          @issue = issue
        end
  
        def each(&blk)
          puts "iN EACH METHOD NOW AAAAAAABBBBBBBBBBIIIIIIIIDDDDDDDDDD"
          enumerables = [
            issue_querier.timeline(issue)
          ]
           puts "enumberables data is      aaaaaabbbbbbiiiiiidddddd"
         
          Enumerators::FlattenMerge
            .new(enumerables) { |a, b|
              a[0].created_at < b[0].created_at
            }
            .each(&blk)
        end
  
        private
  
        attr_reader :issue_querier
        attr_reader :issue
      end
  
      def initialize(client, issue_querier)
        @client = client
        @issue_querier = issue_querier
      end
  
      def issues(repo_name)
        owner, name = repo_name.split('/', 2)
        issue_querier.issues(owner, name)
      end
  
      def issue_data(issue)
        issue_querier.issue_data(issue)
      end
  
      def issue_events(issue)
        EventStream.new(issue_querier, issue)
      end
  
      def create_issue_comment(repo_name, issue_number, body)
        client.add_comment(repo_name, issue_number, body)
      end
      
      def delete_issue_comment(repo_name, comment_number)
        client.delete_comment(repo_name, comment_number)
      end
  
      private
  
      attr_reader :issue_querier
      attr_reader :client
    end
  end